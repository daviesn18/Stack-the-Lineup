-- Merge 3: which game a log came from, and who archived it.
--
-- Each device now remembers its own open game (teams.current_lineup_id is no
-- longer read or written). When a coach's open game is archived somewhere
-- else, by another coach or on their own other device, the device moves on
-- and says who archived it. Two things were missing for that:
--
--   scheduled_game_id  which scheduled game the log came from, so a device
--                      can tell its open game was archived (not just deleted
--                      from the schedule). Plain uuid with no foreign key: the
--                      game can leave the schedule later and the log stays.
--   archived_by_user   the account that archived it, and
--   archived_by_name   that coach's name at the time.
--
-- archived_by isn't enough: both apps fill it with the TEAM's coach name, so
-- on a shared team it names the owner whoever archived. It stays as it is for
-- old logs and old app versions.
--
-- The archiver is stamped by the server from auth.uid() when the log is
-- inserted, whatever the client sends, and never changes afterwards. Profiles
-- are readable only by their owner, so the name is copied onto the log rather
-- than looked up when it's shown.

alter table public.game_logs
  add column scheduled_game_id uuid,
  add column archived_by_user  uuid references auth.users on delete set null,
  add column archived_by_name  text not null default '';

create function public.stamp_archiver() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    new.archived_by_user := auth.uid();
    new.archived_by_name := coalesce(
      (select nullif(btrim(p.display_name), '') from public.profiles p where p.id = auth.uid()),
      (select nullif(btrim(coalesce(u.raw_user_meta_data ->> 'full_name', u.raw_user_meta_data ->> 'name')), '')
         from auth.users u where u.id = auth.uid()),
      '');
  else
    new.archived_by_user := old.archived_by_user;
    new.archived_by_name := old.archived_by_name;
  end if;
  return new;
end $$;

-- A trigger function, never called directly.
revoke execute on function public.stamp_archiver() from public, anon, authenticated;

create trigger stamp_archiver before insert or update on public.game_logs
  for each row execute function public.stamp_archiver();

-- archive_game also records which scheduled game was played. Same body as
-- 20260924000100 apart from scheduled_game_id.
create or replace function public.archive_game(
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
     innings, player_snapshot, archived_by, notes, scheduled_game_id)
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
    btrim(coalesce(p_notes, ''), E' \t\n\r'),
    l.scheduled_game_id;

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
