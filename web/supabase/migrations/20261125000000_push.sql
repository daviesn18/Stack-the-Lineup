-- Merge 5: push notifications for account teams.
--
-- Design (decided with Nick 2026-11-24): docs/merge5-push-design.md. In short:
--
--   * The database sends the push, not the app. When a lineup becomes
--     finalized on a shared account team, or a coach joins one, a trigger works
--     out who should hear about it, gathers their device tokens, and hands them
--     to the push Worker in one asynchronous call (pg_net). Every client is
--     covered (iPhone, web, later Android), and nobody can make the Worker push
--     to a team they aren't on.
--   * Device tokens live in device_tokens, one row per device, written only
--     through register_device_token / unregister_device_token.
--   * The Worker URL and its shared secret are Vault secrets
--     (push_worker_url, push_worker_secret). Without them nothing is sent,
--     which is how a local or test database behaves.
--
-- CloudKit-shared teams keep the old path: the app POSTs to the Worker, which
-- reads CloudKit. Nothing here touches it.

-- pg_net makes the HTTP call; Supabase has it, a test database doesn't (the
-- test harness stands in a net.http_post that records calls).
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_net') then
    create extension if not exists pg_net;
  end if;
end $$;

-- ============================================================================
-- Device tokens
-- ============================================================================

create table public.device_tokens (
  token       text primary key,
  user_id     uuid not null references auth.users on delete cascade,
  platform    text not null check (platform in ('ios', 'android')),
  -- Debug builds get sandbox APNs tokens, TestFlight and App Store builds get
  -- production ones; the Worker picks the APNs host per token.
  apns_env    text not null check (apns_env in ('production', 'sandbox')),
  app_version text not null default '',
  updated_at  timestamptz not null default now()
);
create index device_tokens_user on public.device_tokens (user_id);

alter table public.device_tokens enable row level security;
revoke all on public.device_tokens from anon, authenticated;

-- Called by the app after sign-in and on every launch with an account. A token
-- another account had moves to this one (one phone, a different coach signed
-- in). Tokens not seen for 60 days are dropped here too: the app re-registers
-- on every launch, so an old row is an uninstalled app.
create function public.register_device_token(p_token text, p_platform text, p_apns_env text, p_app_version text default '')
returns void
language plpgsql security definer set search_path = '' as $$
declare
  u uuid := (select auth.uid());
  t text := lower(btrim(coalesce(p_token, '')));
begin
  if u is null then
    raise exception 'Not signed in' using errcode = '28000';
  end if;
  if t !~ '^[0-9a-f]{32,255}$' then
    raise exception 'Not a device token' using errcode = '22023';
  end if;
  insert into public.device_tokens (token, user_id, platform, apns_env, app_version, updated_at)
  values (t, u, p_platform, p_apns_env, left(coalesce(p_app_version, ''), 40), now())
  on conflict (token) do update
    set user_id = excluded.user_id, platform = excluded.platform, apns_env = excluded.apns_env,
        app_version = excluded.app_version, updated_at = now();
  delete from public.device_tokens where updated_at < now() - interval '60 days';
end $$;

-- Called on sign-out, so the next coach on this phone doesn't get the last one's pushes.
create function public.unregister_device_token(p_token text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  delete from public.device_tokens
  where token = lower(btrim(coalesce(p_token, ''))) and user_id = (select auth.uid());
end $$;

-- ============================================================================
-- Sending (internal)
-- ============================================================================

-- Hands one event to the Worker for these users' devices. Never raises: a push
-- that can't be sent must not undo the finalize or the join that caused it.
create function public.send_push(p_users uuid[], p_event text, p_team uuid, p_metadata jsonb)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  url    text;
  secret text;
  tokens jsonb;
begin
  select decrypted_secret into url    from vault.decrypted_secrets where name = 'push_worker_url';
  select decrypted_secret into secret from vault.decrypted_secrets where name = 'push_worker_secret';
  if url is null or secret is null then
    return;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('token', d.token, 'env', d.apns_env)), '[]'::jsonb)
    into tokens
  from public.device_tokens d
  where d.user_id = any(p_users) and d.platform = 'ios';
  if jsonb_array_length(tokens) = 0 then
    return;
  end if;
  perform net.http_post(
    url := rtrim(url, '/') || '/v2/send',
    body := jsonb_build_object(
      'eventType', p_event,
      'teamID', upper(p_team::text),
      'metadata', p_metadata,
      'tokens', tokens),
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || secret),
    timeout_milliseconds := 5000);
exception when others then
  raise warning 'send_push(%) failed: %', p_event, sqlerrm;
end $$;

-- Everyone on a team: the owner and every member.
create function public.team_coach_ids(p_team uuid) returns uuid[]
language sql stable security definer set search_path = '' as $$
  select array(
    select owner_id from public.teams where id = p_team
    union
    select user_id from public.team_members where team_id = p_team
  )
$$;

-- "Cubs: Sam finalized the lineup vs Tigers." to every coach but the one who
-- finalized. Only on a shared team, only when the lineup turns finalized (not
-- when a finalized row is saved again), and only for a recent finalize, so
-- uploading a team's old lineups can't set off a burst of pushes.
create function public.push_lineup_finalized() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  t public.teams;
  who text;
begin
  if new.status <> 'finalized'
     or (tg_op = 'UPDATE' and old.status = 'finalized')
     or new.last_finalized_at is null
     or new.last_finalized_at < now() - interval '1 hour' then
    return null;
  end if;
  if not exists (select 1 from public.team_members where team_id = new.team_id) then
    return null;
  end if;
  select * into t from public.teams where id = new.team_id;
  who := coalesce(nullif(btrim(new.last_finalized_by), ''), nullif(btrim(t.coach_name), ''), 'The head coach');
  perform public.send_push(
    array(select c from unnest(public.team_coach_ids(new.team_id)) c
          where c is distinct from (select auth.uid())),
    'lineup_finalized', new.team_id,
    jsonb_strip_nulls(jsonb_build_object(
      'teamName', t.name,
      'triggeredBy', who,
      'opponent', nullif(btrim(new.opponent), ''))));
  return null;
end $$;

create trigger push_lineup_finalized after insert or update of status on public.lineups
  for each row execute function public.push_lineup_finalized();

-- "Cubs: Jo joined as an assistant coach." to the head coach.
create function public.push_coach_joined() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  t public.teams;
begin
  select * into t from public.teams where id = new.team_id;
  perform public.send_push(
    array[t.owner_id], 'coach_joined', new.team_id,
    jsonb_build_object(
      'teamName', t.name,
      'triggeredBy', coalesce(nullif(btrim(new.name), ''), 'A coach'),
      'role', new.role));
  return null;
end $$;

create trigger push_coach_joined after insert on public.team_members
  for each row execute function public.push_coach_joined();

-- ============================================================================
-- Execute rights: the two token functions for signed-in coaches; the rest
-- internal. (New functions are executable by PUBLIC unless revoked.)
-- ============================================================================

revoke execute on function
  public.register_device_token(text, text, text, text), public.unregister_device_token(text),
  public.send_push(uuid[], text, uuid, jsonb), public.team_coach_ids(uuid),
  public.push_lineup_finalized(), public.push_coach_joined()
  from public, anon, authenticated;

grant execute on function
  public.register_device_token(text, text, text, text), public.unregister_device_token(text)
  to authenticated;
