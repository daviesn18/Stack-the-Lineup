-- Writes that must land together. supabase-js cannot wrap several calls in one
-- transaction, so these run as RPCs.
--
-- All are SECURITY INVOKER: they run as the calling coach, so the row-level
-- security policies in the initial migration still decide what they may touch.
-- The explicit can_edit_team checks only turn a silent zero-row write into a
-- clear error.
--
-- UUIDs inside jsonb (game-log innings, player snapshots) are written
-- UPPER-case, matching the iOS/.stlteam format. Postgres returns uuid columns
-- lower-case; the app's data layer normalizes on read.

-- ----------------------------------------------------------------------------
-- Helpers
-- ----------------------------------------------------------------------------

create function public.require_editable_lineup(p_lineup_id uuid)
returns public.lineups
language plpgsql stable set search_path = '' as $$
declare l public.lineups;
begin
  select * into l from public.lineups where id = p_lineup_id and deleted_at is null;
  if not found or not public.can_edit_team(l.team_id) then
    raise exception 'Lineup not found' using errcode = 'P0002';
  end if;
  return l;
end $$;

-- Mirrors LineupStore.revertToDraftIfFinalized: any edit to a finalized lineup
-- silently returns it to draft and clears the finalization stamp.
create function public.revert_to_draft(p_lineup_id uuid)
returns void
language sql set search_path = '' as $$
  update public.lineups set
    status            = 'draft',
    last_finalized_by = case when status = 'finalized' then null else last_finalized_by end,
    last_finalized_at = case when status = 'finalized' then null else last_finalized_at end
  where id = p_lineup_id;
$$;

-- ----------------------------------------------------------------------------
-- save_innings: replace the cells of one or more innings in one transaction.
--   p_innings = {"0": {"<player uuid>": "SS", ...}, "3": {...}}
-- A single cell edit sends one inning; Auto-Fill sends all of them.
-- The one-fielder-per-position constraint is checked at commit.
-- ----------------------------------------------------------------------------

create function public.save_innings(p_lineup_id uuid, p_innings jsonb)
returns void
language plpgsql set search_path = '' as $$
declare
  l public.lineups := public.require_editable_lineup(p_lineup_id);
  k text;
  v jsonb;
begin
  if jsonb_typeof(p_innings) is distinct from 'object' then
    raise exception 'innings must be an object keyed by inning index' using errcode = '22023';
  end if;

  for k, v in select key, value from jsonb_each(p_innings) loop
    if k !~ '^[0-9]+$' or k::int >= l.inning_count then
      raise exception 'Inning % is outside this lineup (% innings)', k, l.inning_count
        using errcode = '22023';
    end if;
    if jsonb_typeof(v) is distinct from 'object' then
      raise exception 'Inning % must be an object of player id to position', k using errcode = '22023';
    end if;

    delete from public.lineup_cells where lineup_id = l.id and inning = k::smallint;
    insert into public.lineup_cells (lineup_id, team_id, inning, player_id, position)
    select l.id, l.team_id, k::smallint, e.key::uuid, e.value #>> '{}'
    from jsonb_each(v) e;
  end loop;

  perform public.revert_to_draft(l.id);
end $$;

-- ----------------------------------------------------------------------------
-- archive_game: mirrors LineupStore.archiveCurrentLineup.
--   * snapshot the current roster; clamp innings played to 1...game length
--   * freeze every inning of the lineup, plus batting order, into a game log
--   * record pitch counts ({"<player uuid>": 42})
--   * detach the lineup from its scheduled game and clear its grid, keeping
--     date, opponent, batting order and absences, as iOS clearPositions does
-- Not done here (spring): re-applying the default template to the cleared
-- grid; the app will do that after this returns once templates ship on web.
-- iOS caps history at 20 logs for CloudKit's blob size; the web keeps all.
-- ----------------------------------------------------------------------------

create function public.archive_game(
  p_lineup_id      uuid,
  p_innings_played int,
  p_notes          text  default '',
  p_pitch_counts   jsonb default '{}',
  p_game_log_id    uuid  default null
)
returns uuid
language plpgsql set search_path = '' as $$
declare
  l      public.lineups := public.require_editable_lineup(p_lineup_id);
  t      public.teams;
  log_id uuid := coalesce(p_game_log_id, gen_random_uuid());
begin
  select * into t from public.teams where id = l.team_id;

  insert into public.game_logs
    (id, team_id, game_date, opponent, innings_played, batting_order,
     innings, player_snapshot, archived_by, notes)
  select
    log_id, l.team_id, l.game_date, l.opponent,
    greatest(1, least(t.game_inning_count, p_innings_played)),
    l.batting_order,
    (select coalesce(jsonb_agg(
              coalesce((select jsonb_object_agg(upper(c.player_id::text), c.position)
                        from public.lineup_cells c
                        where c.lineup_id = l.id and c.inning = i), '{}'::jsonb)
              order by i), '[]'::jsonb)
     from generate_series(0, l.inning_count - 1) as i),
    (select coalesce(jsonb_agg(jsonb_build_object(
              'id', upper(p.id::text), 'firstName', p.first_name,
              'lastName', p.last_name, 'number', p.number)
              order by p.roster_order, p.created_at), '[]'::jsonb)
     from public.players p
     where p.team_id = l.team_id and p.deleted_at is null),
    btrim(t.coach_name),
    btrim(coalesce(p_notes, ''), E' \t\n\r');

  perform public.replace_pitch_counts(log_id, p_pitch_counts);

  delete from public.lineup_cells where lineup_id = l.id;
  perform public.revert_to_draft(l.id);
  update public.lineups set
    scheduled_game_id   = null,
    inning_count        = t.game_inning_count,
    default_template_id = null
  where id = l.id;

  return log_id;
end $$;

-- ----------------------------------------------------------------------------
-- replace_pitch_counts: mirrors LineupStore.replacePitchCounts. Replaces the
-- whole set so a pitcher removed in the editor is cleared.
--   p_counts = {"<player uuid>": 42, ...}
-- ----------------------------------------------------------------------------

create function public.replace_pitch_counts(p_game_log_id uuid, p_counts jsonb)
returns void
language plpgsql set search_path = '' as $$
declare g public.game_logs;
begin
  select * into g from public.game_logs where id = p_game_log_id and deleted_at is null;
  if not found or not public.can_edit_team(g.team_id) then
    raise exception 'Game log not found' using errcode = 'P0002';
  end if;
  if jsonb_typeof(coalesce(p_counts, '{}')) is distinct from 'object' then
    raise exception 'pitch counts must be an object of player id to count' using errcode = '22023';
  end if;

  delete from public.pitch_counts where game_log_id = g.id;
  insert into public.pitch_counts (game_log_id, team_id, player_id, pitches)
  select g.id, g.team_id, e.key::uuid, (e.value #>> '{}')::smallint
  from jsonb_each(coalesce(p_counts, '{}')) e;
end $$;

-- ----------------------------------------------------------------------------
-- import_team: writes a whole team (from a .stlteam file) in one transaction.
-- The app converts the file into this shape; keys are column names.
--   {
--     "team": {id, name, color_hex, coach_name, game_inning_count,
--              fair_play_config, pitching_config, calendar_subscription_url,
--              created_at, default_template_id, current_lineup_id},
--     "players": [...], "scheduled_games": [...],
--     "lineup_templates": [{..., "locks": [...]}],
--     "lineups": [{..., "cells": {"0": {"<player>": "SS"}}}],
--     "game_logs": [{..., "pitch_counts": {"<player>": 42}}]
--   }
-- IDs are kept (they are the iOS UUIDs). If the coach already has this team,
-- the call fails unless p_replace, which deletes the old copy first.
-- ----------------------------------------------------------------------------

create function public.import_team(p_payload jsonb, p_replace boolean default false)
returns uuid
language plpgsql set search_path = '' as $$
declare
  tj      jsonb := p_payload -> 'team';
  v_team_id uuid := (tj ->> 'id')::uuid;
  item    jsonb;
begin
  if v_team_id is null then
    raise exception 'The team file has no team id' using errcode = '22023';
  end if;

  if exists (select 1 from public.teams where id = v_team_id) then
    if not p_replace then
      raise exception 'You already have this team' using errcode = 'P0001', hint = 'TEAM_EXISTS';
    end if;
    delete from public.teams where id = v_team_id;   -- cascades to everything it owns
  end if;

  insert into public.teams
    (id, name, color_hex, coach_name, game_inning_count, fair_play_config,
     pitching_config, calendar_subscription_url, created_at)
  select v_team_id, coalesce(r.name, ''), coalesce(r.color_hex, '0000FF'), coalesce(r.coach_name, ''),
         coalesce(r.game_inning_count, 7),
         coalesce(r.fair_play_config, '{}'), coalesce(r.pitching_config, '{}'),
         r.calendar_subscription_url, r.created_at
  from jsonb_populate_record(null::public.teams, tj) r;

  insert into public.players
    (id, team_id, first_name, last_name, number, league_age, position_preferences,
     hitting_style, speed, on_base, roster_order)
  select r.id, v_team_id, r.first_name, coalesce(r.last_name, ''), coalesce(r.number, ''),
         r.league_age, coalesce(r.position_preferences, '{}'),
         r.hitting_style, r.speed, r.on_base, coalesce(r.roster_order, 0)
  from jsonb_populate_recordset(null::public.players, coalesce(p_payload -> 'players', '[]')) r;

  insert into public.scheduled_games
    (id, team_id, ical_uid, starts_at, opponent, location, raw_summary, is_cancelled, last_synced_at)
  select r.id, v_team_id, r.ical_uid, r.starts_at, r.opponent, r.location,
         coalesce(r.raw_summary, ''), coalesce(r.is_cancelled, false), r.last_synced_at
  from jsonb_populate_recordset(null::public.scheduled_games, coalesce(p_payload -> 'scheduled_games', '[]')) r;

  for item in select * from jsonb_array_elements(coalesce(p_payload -> 'lineup_templates', '[]')) loop
    insert into public.lineup_templates (id, team_id, name, batting_order, created_at)
    select r.id, v_team_id, coalesce(r.name, ''), coalesce(r.batting_order, '{}'), r.created_at
    from jsonb_populate_record(null::public.lineup_templates, item) r;

    insert into public.template_locks (id, template_id, team_id, player_id, position, first_inning, last_inning)
    select r.id, (item ->> 'id')::uuid, v_team_id, r.player_id, r.position, r.first_inning, r.last_inning
    from jsonb_populate_recordset(null::public.template_locks, coalesce(item -> 'locks', '[]')) r;
  end loop;

  for item in select * from jsonb_array_elements(coalesce(p_payload -> 'lineups', '[]')) loop
    insert into public.lineups
      (id, team_id, scheduled_game_id, game_date, opponent, inning_count, batting_order,
       absent_player_ids, status, last_finalized_by, last_finalized_at, default_template_id)
    select r.id, v_team_id, r.scheduled_game_id, coalesce(r.game_date, now()), coalesce(r.opponent, ''),
           coalesce(r.inning_count, 7), coalesce(r.batting_order, '{}'), coalesce(r.absent_player_ids, '{}'),
           coalesce(r.status, 'draft'), r.last_finalized_by, r.last_finalized_at, r.default_template_id
    from jsonb_populate_record(null::public.lineups, item) r;

    perform public.save_innings((item ->> 'id')::uuid, coalesce(item -> 'cells', '{}'));
    -- save_innings reverts to draft; restore the imported status.
    update public.lineups set
      status            = coalesce(item ->> 'status', 'draft'),
      last_finalized_by = item ->> 'last_finalized_by',
      last_finalized_at = (item ->> 'last_finalized_at')::timestamptz
    where id = (item ->> 'id')::uuid;
  end loop;

  for item in select * from jsonb_array_elements(coalesce(p_payload -> 'game_logs', '[]')) loop
    insert into public.game_logs
      (id, team_id, game_date, opponent, innings_played, batting_order, innings,
       player_snapshot, archived_at, archived_by, notes)
    select r.id, v_team_id, r.game_date, coalesce(r.opponent, ''), r.innings_played,
           coalesce(r.batting_order, '{}'), coalesce(r.innings, '[]'), coalesce(r.player_snapshot, '[]'),
           coalesce(r.archived_at, now()), coalesce(r.archived_by, ''), coalesce(r.notes, '')
    from jsonb_populate_record(null::public.game_logs, item) r;

    perform public.replace_pitch_counts((item ->> 'id')::uuid, coalesce(item -> 'pitch_counts', '{}'));
  end loop;

  update public.teams set
    default_template_id = (tj ->> 'default_template_id')::uuid,
    current_lineup_id   = (tj ->> 'current_lineup_id')::uuid
  where id = v_team_id;

  return v_team_id;
end $$;

grant execute on function
  public.save_innings(uuid, jsonb),
  public.archive_game(uuid, int, text, jsonb, uuid),
  public.replace_pitch_counts(uuid, jsonb),
  public.import_team(jsonb, boolean)
  to authenticated;
-- Helpers the functions above call as the coach. Also reachable as RPCs, which
-- is harmless: both only act on lineups the caller may already edit.
grant execute on function public.require_editable_lineup(uuid), public.revert_to_draft(uuid) to authenticated;
