-- Stack the Lineup: initial schema for the web pilot.
--
-- Design doc (approved 2026-09-23): https://claude.ai/artifact/VS64ow4jiR9oMgDmpujxDY
--
-- Ground rules, each fixing a CloudKit-era failure or avoiding rework later:
--   * Rows for anything edited on its own (roster, lineup cells, game logs,
--     pitch counts); jsonb only for small settings edited as a unit.
--   * IDs are client-generated and keep the iOS UUIDs.
--   * The SERVER stamps updated_at (trigger); client clocks are never trusted.
--   * Soft delete (deleted_at) on teams, players, templates, games, lineups, logs.
--   * Every row carries team_id, pinned by a composite FK so it cannot lie.
--   * Access goes through can_read_team / can_edit_team. Shared Teams later
--     changes only those two functions.
--   * Enum columns are text + CHECK with the iOS raw values.

-- ============================================================================
-- Shared helpers
-- ============================================================================

create function public.stamp_row() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  if tg_op = 'INSERT' then
    new.created_at := coalesce(new.created_at, now());
  else
    new.created_at := old.created_at;   -- immutable after insert
  end if;
  return new;
end $$;

-- Positions, in iOS raw-value form.
create domain public.position as text
  check (value in ('P','C','1B','2B','SS','3B','LF','LCF','CF','RCF','RF','Bench','ABS'));
create domain public.fielding_position as text
  check (value in ('P','C','1B','2B','SS','3B','LF','LCF','CF','RCF','RF'));

-- ============================================================================
-- Accounts
-- ============================================================================

create table public.profiles (
  id           uuid primary key references auth.users on delete cascade,
  display_name text not null default '',
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create table public.entitlements (
  user_id    uuid primary key references auth.users on delete cascade,
  is_pro     boolean not null default false,
  source     text not null default 'manual'
             check (source in ('manual','app_store','play_store','revenuecat')),
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Every new account gets a profile and a (non-Pro) entitlement row. Pro is
-- granted from the dashboard during the pilot, by a RevenueCat webhook later.
create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'display_name', ''));
  insert into public.entitlements (user_id) values (new.id);
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ============================================================================
-- Team data
-- ============================================================================

create table public.teams (
  id                        uuid primary key,                      -- = iOS Team.id
  owner_id                  uuid not null default auth.uid()
                            references auth.users on delete cascade,
  name                      text not null default '',
  color_hex                 text not null default '0000FF' check (color_hex ~ '^[0-9A-Fa-f]{6}$'),
  coach_name                text not null default '',
  game_inning_count         smallint not null default 7 check (game_inning_count between 3 and 9),
  fair_play_config          jsonb not null default '{}' check (jsonb_typeof(fair_play_config) = 'object'),
  pitching_config           jsonb not null default '{}' check (jsonb_typeof(pitching_config) = 'object'),
  calendar_subscription_url text,
  default_template_id       uuid,
  current_lineup_id         uuid,
  created_at                timestamptz not null default now(),
  updated_at                timestamptz not null default now(),
  deleted_at                timestamptz
);
create index teams_owner on public.teams (owner_id);

create table public.players (
  id                   uuid primary key,
  team_id              uuid not null references public.teams on delete cascade,
  first_name           text not null,
  last_name            text not null default '',
  number               text not null default '',
  league_age           smallint,                                   -- unchecked by decision
  -- {"SS":"Strength","C":"Never"}; the app validates keys/values like iOS decode.
  position_preferences jsonb not null default '{}' check (jsonb_typeof(position_preferences) = 'object'),
  hitting_style        text check (hitting_style in ('Power','Gap','Singles')),
  speed                text check (speed in ('Fast','Medium','Slow')),
  on_base              text check (on_base in ('High','Medium','Low')),
  roster_order         integer not null default 0,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  deleted_at           timestamptz,
  unique (id, team_id)
);
create index players_team on public.players (team_id);

create table public.scheduled_games (
  id             uuid primary key,
  team_id        uuid not null references public.teams on delete cascade,
  ical_uid       text not null,
  starts_at      timestamptz not null,
  opponent       text,
  location       text,
  raw_summary    text not null default '',
  is_cancelled   boolean not null default false,
  last_synced_at timestamptz,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  deleted_at     timestamptz,
  unique (team_id, ical_uid),
  unique (id, team_id)
);

create table public.lineup_templates (
  id            uuid primary key,
  team_id       uuid not null references public.teams on delete cascade,
  name          text not null default '',
  batting_order uuid[] not null default '{}',
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz,
  unique (id, team_id)
);
create index lineup_templates_team on public.lineup_templates (team_id);

create table public.template_locks (
  id           uuid primary key,
  template_id  uuid not null,
  team_id      uuid not null,
  player_id    uuid not null,
  position     public.fielding_position not null,
  first_inning smallint not null,                     -- 0-based, inclusive (ClosedRange)
  last_inning  smallint not null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  check (first_inning between 0 and 8 and last_inning between 0 and 8 and first_inning <= last_inning),
  foreign key (template_id, team_id) references public.lineup_templates (id, team_id) on delete cascade,
  foreign key (player_id, team_id)   references public.players (id, team_id) on delete cascade
);
create index template_locks_template on public.template_locks (template_id);

-- One row per lineup. The iOS "working lineup + gameLineups stash" becomes:
-- every lineup is a row, optionally tied to one scheduled game, and
-- teams.current_lineup_id says which one is open.
create table public.lineups (
  id                  uuid primary key,
  team_id             uuid not null references public.teams on delete cascade,
  scheduled_game_id   uuid,
  game_date           timestamptz not null default now(),
  opponent            text not null default '',
  -- Runtime truth for inning count, as iOS uses innings.count. It can differ
  -- from teams.game_inning_count (lineups built before the setting changed).
  inning_count        smallint not null default 7 check (inning_count between 1 and 9),
  batting_order       uuid[] not null default '{}',
  absent_player_ids   uuid[] not null default '{}',
  status              text not null default 'draft' check (status in ('draft','finalized')),
  last_finalized_by   text,
  last_finalized_at   timestamptz,
  default_template_id uuid,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  deleted_at          timestamptz,
  unique (id, team_id),
  foreign key (scheduled_game_id, team_id)
    references public.scheduled_games (id, team_id) on delete set null (scheduled_game_id),
  foreign key (default_template_id, team_id)
    references public.lineup_templates (id, team_id) on delete set null (default_template_id)
);
create index lineups_team on public.lineups (team_id);
create unique index lineups_one_per_game on public.lineups (scheduled_game_id)
  where scheduled_game_id is not null and deleted_at is null;

create table public.lineup_cells (
  lineup_id  uuid not null,
  team_id    uuid not null,
  inning     smallint not null check (inning between 0 and 8),
  player_id  uuid not null,
  position   public.position not null,
  updated_at timestamptz not null default now(),
  primary key (lineup_id, inning, player_id),
  foreign key (lineup_id, team_id) references public.lineups (id, team_id) on delete cascade,
  foreign key (player_id, team_id) references public.players (id, team_id) on delete cascade,
  -- At most one fielder per position per inning (replaces iOS
  -- deduplicatingFieldingPositions). Checked at commit so a swap inside one
  -- save is fine.
  constraint one_fielder_per_position
    exclude using btree (lineup_id with =, inning with =, position with =)
    where (position not in ('Bench','ABS'))
    deferrable initially deferred
);
create index lineup_cells_player on public.lineup_cells (player_id, team_id);

create table public.game_logs (
  id              uuid primary key,
  team_id         uuid not null references public.teams on delete cascade,
  game_date       timestamptz not null,
  opponent        text not null default '',
  innings_played  smallint not null check (innings_played between 1 and 9),
  batting_order   uuid[] not null default '{}',
  -- Frozen at archive, iOS shape with a normal object per inning:
  -- [{"<PLAYER-UUID>":"SS", ...}, ...]
  innings         jsonb not null default '[]' check (jsonb_typeof(innings) = 'array'),
  -- [{"id","firstName","lastName","number"}]
  player_snapshot jsonb not null default '[]' check (jsonb_typeof(player_snapshot) = 'array'),
  archived_at     timestamptz not null default now(),
  archived_by     text not null default '',
  notes           text not null default '',
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz,
  unique (id, team_id)
);
create index game_logs_team_date on public.game_logs (team_id, game_date desc);

create table public.pitch_counts (
  game_log_id uuid not null,
  team_id     uuid not null,
  player_id   uuid not null,          -- no FK to players: the log outlives roster changes
  pitches     smallint not null check (pitches between 0 and 200),
  updated_at  timestamptz not null default now(),
  primary key (game_log_id, player_id),
  foreign key (game_log_id, team_id) references public.game_logs (id, team_id) on delete cascade
);

-- The team's own pointers, pinned to the same team.
alter table public.teams
  add constraint teams_default_template_fk foreign key (default_template_id, id)
    references public.lineup_templates (id, team_id) on delete set null (default_template_id),
  add constraint teams_current_lineup_fk foreign key (current_lineup_id, id)
    references public.lineups (id, team_id) on delete set null (current_lineup_id);

-- ============================================================================
-- Triggers
-- ============================================================================

-- updated_at on every table (created_at too where it exists).
create trigger stamp before insert or update on public.profiles         for each row execute function public.stamp_row();
create trigger stamp before insert or update on public.entitlements     for each row execute function public.stamp_row();
create trigger stamp before insert or update on public.teams            for each row execute function public.stamp_row();
create trigger stamp before insert or update on public.players          for each row execute function public.stamp_row();
create trigger stamp before insert or update on public.scheduled_games  for each row execute function public.stamp_row();
create trigger stamp before insert or update on public.lineup_templates for each row execute function public.stamp_row();
create trigger stamp before insert or update on public.template_locks   for each row execute function public.stamp_row();
create trigger stamp before insert or update on public.lineups          for each row execute function public.stamp_row();
create trigger stamp before insert or update on public.game_logs        for each row execute function public.stamp_row();

create function public.stamp_updated_only() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end $$;
create trigger stamp before insert or update on public.lineup_cells for each row execute function public.stamp_updated_only();
create trigger stamp before insert or update on public.pitch_counts for each row execute function public.stamp_updated_only();

-- A team can never change owner or id.
create function public.guard_team_identity() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.owner_id is distinct from old.owner_id or new.id is distinct from old.id then
    raise exception 'A team''s owner and id cannot be changed' using errcode = '42501';
  end if;
  return new;
end $$;
create trigger guard_identity before update on public.teams
  for each row execute function public.guard_team_identity();

-- ============================================================================
-- Access
-- ============================================================================

-- The only place that decides who may see or change a team's data.
-- Shared Teams (later) adds: OR a team_members row for auth.uid() (editor/viewer).
create function public.can_read_team(t uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.teams
    where id = t and owner_id = (select auth.uid())
  )
$$;

create function public.can_edit_team(t uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.teams
    where id = t and owner_id = (select auth.uid()) and deleted_at is null
  )
$$;

-- Lock down defaults, then grant exactly what the app uses. anon gets nothing.
revoke all on all tables    in schema public from anon, authenticated;
revoke all on all functions in schema public from public, anon, authenticated;
alter default privileges in schema public revoke all on tables    from anon, authenticated;
alter default privileges in schema public revoke all on functions from public, anon, authenticated;

grant usage on schema public to authenticated;
grant select, update (display_name) on public.profiles to authenticated;
grant select on public.entitlements to authenticated;
grant select, insert, update, delete on
  public.teams, public.players, public.scheduled_games, public.lineup_templates,
  public.template_locks, public.lineups, public.lineup_cells, public.game_logs,
  public.pitch_counts
  to authenticated;
grant execute on function public.can_read_team(uuid), public.can_edit_team(uuid) to authenticated;

alter table public.profiles         enable row level security;
alter table public.entitlements     enable row level security;
alter table public.teams            enable row level security;
alter table public.players          enable row level security;
alter table public.scheduled_games  enable row level security;
alter table public.lineup_templates enable row level security;
alter table public.template_locks   enable row level security;
alter table public.lineups          enable row level security;
alter table public.lineup_cells     enable row level security;
alter table public.game_logs        enable row level security;
alter table public.pitch_counts     enable row level security;

create policy own_profile_read   on public.profiles for select to authenticated using (id = (select auth.uid()));
create policy own_profile_update on public.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

-- Readable by its owner; no write policy at all, so only the server grants Pro.
create policy own_entitlement_read on public.entitlements for select to authenticated
  using (user_id = (select auth.uid()));

create policy team_read   on public.teams for select to authenticated using (public.can_read_team(id));
create policy team_insert on public.teams for insert to authenticated with check (owner_id = (select auth.uid()));
create policy team_update on public.teams for update to authenticated
  using (public.can_read_team(id)) with check (owner_id = (select auth.uid()));
create policy team_delete on public.teams for delete to authenticated using (owner_id = (select auth.uid()));

-- Same two policies on every child table.
do $$
declare t text;
begin
  foreach t in array array['players','scheduled_games','lineup_templates','template_locks',
                           'lineups','lineup_cells','game_logs','pitch_counts'] loop
    execute format('create policy team_read on public.%I for select to authenticated
                      using (public.can_read_team(team_id))', t);
    execute format('create policy team_write on public.%I for all to authenticated
                      using (public.can_edit_team(team_id)) with check (public.can_edit_team(team_id))', t);
  end loop;
end $$;
