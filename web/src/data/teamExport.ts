// Gathers everything a .stlteam file carries for one team. The workbench only
// loads what it edits (roster, the open lineup, archived games), so the
// schedule, templates and the other games' saved lineups are read here, at
// export time.

import { type LineupTemplate, type Lineup, type ScheduledGame, type Team } from '../core/model';
import { stlTeamFilename, writeStlTeam } from '../core/stlteamWrite';
import { supabase } from './supabase';
import { toLineup, type TeamData } from './teamStore';
import { upperId } from './teams';

/** Shown as the exporting app's version in the file and on the import preview. */
export const WEB_APP_VERSION = 'web';

type Row = Record<string, any>;

async function must<T>(p: PromiseLike<{ data: T; error: { message: string } | null }>): Promise<T> {
  const { data, error } = await p;
  if (error) throw new Error(error.message);
  return data;
}

export async function loadFullTeam(data: TeamData): Promise<Team> {
  const id = data.team.id;
  const [team, games, templates, lineups] = await Promise.all([
    must(supabase.from('teams').select('created_at, calendar_subscription_url, default_template_id').eq('id', id).single()),
    must(supabase.from('scheduled_games').select('*').eq('team_id', id).is('deleted_at', null).order('starts_at')),
    must(supabase.from('lineup_templates').select('*, template_locks(*)').eq('team_id', id).is('deleted_at', null).order('created_at')),
    must(supabase.from('lineups').select('*, lineup_cells(inning, player_id, position)').eq('team_id', id)
      .is('deleted_at', null).not('scheduled_game_id', 'is', null)),
  ]);
  const scheduledGames: ScheduledGame[] = (games as Row[]).map((g) => ({
    id: upperId(g.id), icalUID: g.ical_uid, date: new Date(g.starts_at), rawSummary: g.raw_summary,
    isCancelled: g.is_cancelled, lastSyncedAt: new Date(g.last_synced_at ?? g.starts_at),
    ...(g.opponent !== null ? { opponent: g.opponent } : {}),
    ...(g.location !== null ? { location: g.location } : {}),
  }));
  const lineupTemplates: LineupTemplate[] = (templates as Row[]).map((r) => ({
    id: upperId(r.id), name: r.name, battingOrder: (r.batting_order ?? []).map(upperId), createdAt: new Date(r.created_at),
    positionLocks: (r.template_locks ?? []).map((l: Row) => ({
      id: upperId(l.id), playerID: upperId(l.player_id), position: l.position,
      innings: [l.first_inning, l.last_inning] as [number, number],
    })),
  }));
  const t = team as Row;
  const gameLineups: Record<string, Lineup> = {};
  let currentGameID: string | undefined;
  for (const r of lineups as Row[]) {
    const gameId = upperId(r.scheduled_game_id);
    if (upperId(r.id) === data.lineup.id) { currentGameID = gameId; continue; }
    const { id: _id, ...l } = toLineup(r);
    gameLineups[gameId] = l;
  }
  return {
    id, name: data.team.name, colorHex: data.team.colorHex, coachName: data.team.coachName,
    gameInningCount: data.team.gameInningCount, fairPlayConfig: data.team.fairPlayConfig,
    pitchingConfig: data.team.pitchingConfig, players: data.players, gameLogs: data.gameLogs,
    lineup: data.lineup, createdAt: new Date(t.created_at), scheduledGames, lineupTemplates, gameLineups,
    ...(t.calendar_subscription_url ? { calendarSubscriptionURL: t.calendar_subscription_url } : {}),
    ...(t.default_template_id ? { defaultTemplateID: upperId(t.default_template_id) } : {}),
    ...(currentGameID ? { currentGameID } : {}),
  };
}

/** Builds the .stlteam file and hands it to the browser as a download. */
export async function downloadTeamFile(data: TeamData): Promise<string> {
  const team = await loadFullTeam(data);
  const filename = stlTeamFilename(team.name);
  const blob = new Blob([writeStlTeam(team, WEB_APP_VERSION)], { type: 'application/octet-stream' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 10_000);
  return filename;
}
