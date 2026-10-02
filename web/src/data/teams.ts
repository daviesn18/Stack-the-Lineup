// Team list and .stlteam import against Supabase.

import { parseStlTeam, TeamImportError } from '../core/stlteam';
import { defaultFairPlayConfig, defaultPitchingConfig, emptyLineup, type Team } from '../core/model';
import { signal } from './analytics';
import { supabase } from './supabase';
import { asSeparateCopy, toImportPayload, type ImportPayload } from './teamPayload';

export interface TeamSummary {
  id: string;
  name: string;
  colorHex: string;
  playerCount: number;
  archivedGames: number;
  /** The open lineup's game, when it has an opponent. */
  nextGame: { opponent: string; gameDate: Date } | null;
}

/** Postgres returns uuids lower-case; the app (like iOS) works in upper-case. */
export const upperId = (id: string) => id.toUpperCase();

export async function listTeams(): Promise<TeamSummary[]> {
  const { data, error } = await supabase
    .from('teams')
    .select('id, name, color_hex, players(count), game_logs(count), current:lineups!teams_current_lineup_fk(opponent, game_date)')
    .is('deleted_at', null)
    .is('players.deleted_at', null)
    .is('game_logs.deleted_at', null)
    .order('name');
  if (error) throw new Error(error.message);
  return (data ?? []).map((t) => ({
    id: upperId(t.id),
    name: t.name,
    colorHex: t.color_hex,
    playerCount: (t.players as unknown as { count: number }[])[0]?.count ?? 0,
    archivedGames: (t.game_logs as unknown as { count: number }[])[0]?.count ?? 0,
    nextGame: nextGameOf(t.current as unknown),
  }));
}

function nextGameOf(row: unknown): TeamSummary['nextGame'] {
  const l = (Array.isArray(row) ? row[0] : row) as { opponent: string; game_date: string } | null | undefined;
  return l?.opponent ? { opponent: l.opponent, gameDate: new Date(l.game_date) } : null;
}

export interface ImportPreview {
  team: Team;
  exportedAt: Date;
  appVersion: string;
  payload: ImportPayload;
  notes: string[];
  savedLineups: number;
}

/** Reads a .stlteam file's text. Throws with the iOS wording on a bad file. */
export function previewImport(text: string): ImportPreview {
  let parsed: ReturnType<typeof parseStlTeam>;
  try {
    parsed = parseStlTeam(text);
  } catch (e) {
    signal('team.import.failed', { reason: e instanceof TeamImportError ? e.kind : 'read_error' });
    throw e;
  }
  const { team, exportedAt, appVersion } = parsed;
  const { payload, notes } = toImportPayload(team);
  const savedLineups = payload.lineups.filter((l) => {
    const cells = l.cells as Record<string, object>;
    return Object.keys(cells).length > 0;
  }).length;
  return { team, exportedAt, appVersion, payload, notes, savedLineups };
}

export type ImportOutcome =
  | { ok: true; teamId: string }
  /** This coach already has the team: offer to replace their copy. */
  | { ok: false; reason: 'alreadyYours' }
  /** Another account has these ids (a shared iOS team): offer a separate copy. */
  | { ok: false; reason: 'ownedElsewhere' }
  | { ok: false; reason: 'error'; message: string };

export async function importTeam(
  payload: ImportPayload, mode: 'new' | 'replace' | 'copy' = 'new',
): Promise<ImportOutcome> {
  const out = await writeTeam(payload, mode);
  if (out.ok) {
    signal('team.import.completed', {
      mode: mode === 'new' ? 'new_team' : mode,   // iOS: new_team | replace; "copy" is web only
      player_count: payload.players.length, game_count: payload.game_logs.length,
    });
  } else if (out.reason === 'error') {
    signal('team.import.failed', { reason: 'save_error' });
  }
  return out;
}

/** Writes a whole team through import_team (an import, or a new empty team). */
async function writeTeam(payload: ImportPayload, mode: 'new' | 'replace' | 'copy'): Promise<ImportOutcome> {
  const body = mode === 'copy' ? asSeparateCopy(payload) : payload;
  const { data, error } = await supabase.rpc('import_team', { p_payload: body, p_replace: mode === 'replace' });
  if (!error) return { ok: true, teamId: upperId(data as string) };
  if (error.hint === 'TEAM_EXISTS') return { ok: false, reason: 'alreadyYours' };
  if (error.code === '23505') return { ok: false, reason: 'ownedElsewhere' };
  return { ok: false, reason: 'error', message: error.message };
}

export { TeamImportError };

/**
 * Deletes a team for good, with its roster, lineups and game history (the
 * database cascades). Returns an error message, or null when it's gone.
 */
export async function deleteTeam(id: string): Promise<string | null> {
  const { data, error } = await supabase.from('teams').delete().eq('id', id).select('id');
  if (error) return error.message;
  // Row-level security turns "not yours" into zero rows, not an error.
  if (!data?.length) return "This team wasn't found. It may already be deleted.";
  const left = await supabase.from('teams').select('id', { count: 'exact', head: true }).is('deleted_at', null);
  signal('team.deleted', left.count === null ? {} : { remainingTeams: left.count });
  return null;
}

/** A new, empty team: no players yet, default rules. Written through the same import_team function. */
export async function createTeam(fields: { name: string; coachName: string; colorHex: string; gameInningCount: number }): Promise<ImportOutcome> {
  const team: Team = {
    id: crypto.randomUUID().toUpperCase(), name: fields.name.trim(), colorHex: fields.colorHex, coachName: fields.coachName.trim(),
    gameInningCount: fields.gameInningCount, players: [], lineup: emptyLineup(fields.gameInningCount), gameLogs: [],
    createdAt: new Date(), scheduledGames: [], fairPlayConfig: defaultFairPlayConfig(), pitchingConfig: defaultPitchingConfig(),
    lineupTemplates: [], gameLineups: {},
  };
  return writeTeam(toImportPayload(team).payload, 'new');
}
