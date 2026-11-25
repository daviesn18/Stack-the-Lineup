-- Merge 4: Shared Teams on Supabase.
--
-- Design (decided with Nick 2026-11-23): docs/merge4-shared-teams-design.md and
-- the Merge 4 task in Asana. In short:
--
--   * A team has one owner (teams.owner_id) and any number of coaches in
--     team_members, each an editor or a viewer. Everyone joins from the team's
--     one invite link, and the link's role applies to every coach (as with
--     CloudKit sharing today).
--   * can_read_team / can_edit_team are the only access checks, as the initial
--     schema planned. Readers: the owner and every member. Editors: the owner
--     and editor members, while the team isn't deleted.
--   * The team row itself (name, color, rules, inning count, schedule) stays
--     owner-only: team_update already pins owner_id = auth.uid().
--   * Only the owner finalizes a lineup (enforced below by a trigger).
--   * Creating a link needs the owner's Pro. Joining never does. If the
--     owner's Pro lapses, coaches keep their access.
--   * No direct writes to the two new tables: every change goes through the
--     functions here, each checking who is calling.
--
-- The invite token is kept so the owner can send the same link again (today's
-- "Share Link" on iOS). It's readable only through team_invite_link(), by the
-- owner; the table has no grants at all.

-- ============================================================================
-- Tables
-- ============================================================================

create table public.team_members (
  team_id   uuid not null references public.teams on delete cascade,
  user_id   uuid not null references auth.users on delete cascade,
  role      text not null check (role in ('editor','viewer')),
  -- The coach's name when they joined, shown to the owner and other coaches.
  -- Profiles are readable only by their owner, so it's copied here.
  name      text not null default '',
  invite_id uuid,
  joined_at timestamptz not null default now(),
  primary key (team_id, user_id)
);
create index team_members_user on public.team_members (user_id);

create table public.team_invites (
  id         uuid primary key default gen_random_uuid(),
  team_id    uuid not null references public.teams on delete cascade,
  token      text not null unique,
  role       text not null check (role in ('editor','viewer')),
  created_by uuid not null references auth.users on delete cascade,
  created_at timestamptz not null default now(),
  revoked_at timestamptz
);
-- At most one live link per team: "stop sharing" or a new link revokes it.
create unique index team_invites_one_live on public.team_invites (team_id) where revoked_at is null;

-- Failed join attempts, to rate-limit token guessing. Tokens carry about 244
-- random bits, so guessing is hopeless anyway; this keeps it cheap to refuse.
create table public.team_invite_attempts (
  user_id uuid not null references auth.users on delete cascade,
  at      timestamptz not null default now()
);
create index team_invite_attempts_user on public.team_invite_attempts (user_id, at);

alter table public.team_members         enable row level security;
alter table public.team_invites         enable row level security;
alter table public.team_invite_attempts enable row level security;

-- Every coach on a team sees who else is on it. No write grants: functions only.
revoke all on public.team_members, public.team_invites, public.team_invite_attempts from anon, authenticated;
grant select on public.team_members to authenticated;
create policy team_members_read on public.team_members for select to authenticated
  using (public.can_read_team(team_id));

-- ============================================================================
-- Access (the two functions every policy goes through)
-- ============================================================================

create or replace function public.can_read_team(t uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.teams where id = t and owner_id = (select auth.uid())
  ) or exists (
    select 1 from public.team_members where team_id = t and user_id = (select auth.uid())
  )
$$;

create or replace function public.can_edit_team(t uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.teams tm
    where tm.id = t and tm.deleted_at is null
      and (tm.owner_id = (select auth.uid())
           or exists (select 1 from public.team_members m
                      where m.team_id = tm.id and m.user_id = (select auth.uid()) and m.role = 'editor'))
  )
$$;

-- ============================================================================
-- Helpers (internal: not executable by any client role)
-- ============================================================================

-- Pro as both apps read it: is_pro, and not past expires_at.
create function public.user_has_pro(u uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.entitlements e
    where e.user_id = u and e.is_pro and (e.expires_at is null or e.expires_at > now())
  )
$$;

-- The caller's own team, or an error. Owner-only actions start here.
create function public.require_owned_team(p_team uuid) returns public.teams
language plpgsql stable security definer set search_path = '' as $$
declare
  t public.teams;
begin
  select * into t from public.teams where id = p_team and deleted_at is null;
  if not found or t.owner_id is distinct from (select auth.uid()) then
    raise exception 'Only the head coach can do that' using errcode = '42501';
  end if;
  return t;
end $$;

-- A coach's display name: their profile name, then the name from sign-in, else empty.
create function public.coach_display_name(u uuid) returns text
language sql stable security definer set search_path = '' as $$
  select coalesce(
    (select nullif(btrim(p.display_name), '') from public.profiles p where p.id = u),
    (select nullif(btrim(coalesce(x.raw_user_meta_data ->> 'full_name', x.raw_user_meta_data ->> 'name')), '')
       from auth.users x where x.id = u),
    '')
$$;

-- True when this user has failed too many join attempts lately.
create function public.invite_attempts_exceeded(u uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select count(*) >= 20 from public.team_invite_attempts
  where user_id = u and at > now() - interval '10 minutes'
$$;

-- ============================================================================
-- Owner: the invite link
-- ============================================================================

-- Makes the team's invite link (revoking any live one) and returns its token.
-- Needs the owner's Pro. Coaches who already joined keep their access.
create function public.create_team_invite(p_team uuid, p_role text default 'editor') returns text
language plpgsql security definer set search_path = '' as $$
declare
  t     public.teams := public.require_owned_team(p_team);
  token text := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
begin
  if p_role not in ('editor','viewer') then
    raise exception 'Unknown role %', p_role using errcode = '22023';
  end if;
  if not public.user_has_pro(t.owner_id) then
    raise exception 'Sharing a team needs Stack the Lineup Pro' using errcode = 'P0001', hint = 'pro_required';
  end if;
  update public.team_invites set revoked_at = now() where team_id = t.id and revoked_at is null;
  insert into public.team_invites (team_id, token, role, created_by) values (t.id, token, p_role, t.owner_id);
  -- One role for every coach (decision 2): a new link's role applies to all.
  update public.team_members set role = p_role where team_id = t.id;
  return token;
end $$;

-- The live link, for sending it again. Owner only; no row when there's none.
create function public.team_invite_link(p_team uuid)
returns table (token text, role text, created_at timestamptz)
language plpgsql stable security definer set search_path = '' as $$
declare
  t public.teams := public.require_owned_team(p_team);
begin
  return query
    select i.token, i.role, i.created_at from public.team_invites i
    where i.team_id = t.id and i.revoked_at is null;
end $$;

-- Changes the link's role and every coach's (CloudKit-style: one role for all).
create function public.set_invite_role(p_team uuid, p_role text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  t public.teams := public.require_owned_team(p_team);
begin
  if p_role not in ('editor','viewer') then
    raise exception 'Unknown role %', p_role using errcode = '22023';
  end if;
  update public.team_invites set role = p_role where team_id = t.id and revoked_at is null;
  update public.team_members set role = p_role where team_id = t.id;
end $$;

create function public.remove_team_member(p_team uuid, p_user uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  t public.teams := public.require_owned_team(p_team);
begin
  delete from public.team_members where team_id = t.id and user_id = p_user;
end $$;

-- Every coach loses access and the link stops working. The team stays the owner's.
create function public.stop_sharing(p_team uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  t public.teams := public.require_owned_team(p_team);
begin
  update public.team_invites set revoked_at = now() where team_id = t.id and revoked_at is null;
  delete from public.team_members where team_id = t.id;
end $$;

-- ============================================================================
-- Coach: joining and leaving
-- ============================================================================

-- What the join screen shows before joining ("Sam invited you to coach the
-- Cubs"). No row for a link that's unknown, revoked, or for a deleted team.
create function public.team_invite_preview(p_token text)
returns table (team_id uuid, team_name text, color_hex text, owner_name text, role text, is_member boolean)
language plpgsql security definer set search_path = '' as $$
declare
  u uuid := (select auth.uid());
begin
  if u is null then
    raise exception 'Not signed in' using errcode = '28000';
  end if;
  if public.invite_attempts_exceeded(u) then
    raise exception 'Too many tries. Wait a few minutes and try again.' using errcode = 'P0001', hint = 'rate_limited';
  end if;
  return query
    select t.id, t.name, t.color_hex,
           -- The name the head coach gave the team (Your Name), as both apps
           -- show it inside the team; the account's name when it's blank.
           coalesce(nullif(btrim(t.coach_name), ''), public.coach_display_name(t.owner_id)),
           i.role,
           (t.owner_id = u or exists (select 1 from public.team_members m where m.team_id = t.id and m.user_id = u))
    from public.team_invites i join public.teams t on t.id = i.team_id
    where i.token = p_token and i.revoked_at is null and t.deleted_at is null;
  if not found then
    insert into public.team_invite_attempts (user_id) values (u);
  end if;
end $$;

-- Joins the team behind a live link with the link's role and returns the team
-- id. Null for a link that's unknown, revoked, or for a deleted team (the
-- attempt is counted). Joining again, or the owner opening their own link,
-- changes nothing.
create function public.accept_team_invite(p_token text, p_name text default '') returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  u uuid := (select auth.uid());
  i public.team_invites;
  t public.teams;
begin
  if u is null then
    raise exception 'Not signed in' using errcode = '28000';
  end if;
  if public.invite_attempts_exceeded(u) then
    raise exception 'Too many tries. Wait a few minutes and try again.' using errcode = 'P0001', hint = 'rate_limited';
  end if;
  select * into i from public.team_invites where token = p_token and revoked_at is null;
  if found then
    select * into t from public.teams where id = i.team_id and deleted_at is null;
  end if;
  if i.id is null or t.id is null then
    insert into public.team_invite_attempts (user_id) values (u);
    return null;
  end if;
  if t.owner_id = u then
    return t.id;
  end if;
  insert into public.team_members (team_id, user_id, role, name, invite_id)
  values (t.id, u, i.role,
          coalesce(nullif(btrim(coalesce(p_name, '')), ''), public.coach_display_name(u)),
          i.id)
  on conflict (team_id, user_id) do nothing;
  return t.id;
end $$;

create function public.leave_team(p_team uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  u uuid := (select auth.uid());
begin
  if u is null then
    raise exception 'Not signed in' using errcode = '28000';
  end if;
  delete from public.team_members where team_id = p_team and user_id = u;
end $$;

-- ============================================================================
-- Only the owner finalizes (decision 4)
-- ============================================================================
--
-- A coach who isn't the owner can't set a lineup to finalized. The iOS sync
-- upserts lineups, and an upsert fires BEFORE INSERT even when it becomes an
-- update, so a lineup that's ALREADY finalized may be sent again unchanged;
-- its finalized-by and -at stay the owner's whatever the client sends.
-- Moving it back to draft (an edit to a finalized lineup) is allowed, as today.
-- Server-side work with no signed-in user (auth.uid() null) isn't affected.

create function public.guard_lineup_finalize() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  u     uuid := (select auth.uid());
  owner uuid;
  cur   public.lineups;
begin
  if new.status <> 'finalized' or u is null then
    return new;
  end if;
  select owner_id into owner from public.teams where id = new.team_id;
  if owner is not distinct from u then
    return new;
  end if;
  if tg_op = 'UPDATE' then
    cur := old;
  else
    select * into cur from public.lineups where id = new.id;
  end if;
  if cur.id is not null and cur.status = 'finalized' then
    new.last_finalized_by := cur.last_finalized_by;
    new.last_finalized_at := cur.last_finalized_at;
    return new;
  end if;
  raise exception 'Only the head coach can finalize the lineup' using errcode = '42501', hint = 'owner_finalizes';
end $$;

create trigger guard_finalize before insert or update on public.lineups
  for each row execute function public.guard_lineup_finalize();

-- ============================================================================
-- Execute rights: nothing for anon; the client API for signed-in coaches.
-- ============================================================================

revoke execute on function
  public.user_has_pro(uuid), public.require_owned_team(uuid), public.coach_display_name(uuid),
  public.invite_attempts_exceeded(uuid), public.guard_lineup_finalize(),
  public.create_team_invite(uuid, text), public.team_invite_link(uuid), public.set_invite_role(uuid, text),
  public.remove_team_member(uuid, uuid), public.stop_sharing(uuid),
  public.team_invite_preview(text), public.accept_team_invite(text, text), public.leave_team(uuid)
  from public, anon, authenticated;

grant execute on function
  public.create_team_invite(uuid, text), public.team_invite_link(uuid), public.set_invite_role(uuid, text),
  public.remove_team_member(uuid, uuid), public.stop_sharing(uuid),
  public.team_invite_preview(text), public.accept_team_invite(text, text), public.leave_team(uuid)
  to authenticated;
