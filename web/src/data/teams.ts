// Team list and .stlteam import against Supabase.

import { parseStlTeam, TeamImportError } from '../core/stlteam';
import type { Team } from '../core/model';
import { supabase } from './supabase';
import { asSeparateCopy, toImportPayload, type ImportPayload } from './teamPayload';

export interface TeamSummary {
  id: string;
  name: string;
  colorHex: string;
  playerCount: number;
}

/** Postgres returns uuids lower-case; the app (like iOS) works in upper-case. */
export const upperId = (id: string) => id.toUpperCase();

export async function listTeams(): Promise<TeamSummary[]> {
  const { data, error } = await supabase
    .from('teams')
    .select('id, name, color_hex, players(count)')
    .is('deleted_at', null)
    .is('players.deleted_at', null)
    .order('name');
  if (error) throw new Error(error.message);
  return (data ?? []).map((t) => ({
    id: upperId(t.id),
    name: t.name,
    colorHex: t.color_hex,
    playerCount: (t.players as unknown as { count: number }[])[0]?.count ?? 0,
  }));
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
  const { team, exportedAt, appVersion } = parseStlTeam(text);
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
  const body = mode === 'copy' ? asSeparateCopy(payload) : payload;
  const { data, error } = await supabase.rpc('import_team', { p_payload: body, p_replace: mode === 'replace' });
  if (!error) return { ok: true, teamId: upperId(data as string) };
  if (error.hint === 'TEAM_EXISTS') return { ok: false, reason: 'alreadyYours' };
  if (error.code === '23505') return { ok: false, reason: 'ownedElsewhere' };
  return { ok: false, reason: 'error', message: error.message };
}

export { TeamImportError };
