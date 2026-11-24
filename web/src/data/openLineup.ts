// The lineup this browser has open, per team (Merge 3). Each device keeps its
// own; teams.current_lineup_id is no longer used. Storage can be missing or
// blocked (private windows), so every access is guarded: without it the
// browser just opens the default game each time.

const key = (teamId: string) => `stl.openLineup.${teamId.toUpperCase()}`;

export interface StoredOpenLineup {
  lineupId: string;
  /** The scheduled game it belonged to; null for an ad-hoc lineup. */
  gameId: string | null;
}

export function readOpenLineup(teamId: string): StoredOpenLineup | null {
  try {
    const raw = globalThis.localStorage?.getItem(key(teamId));
    if (!raw) return null;
    const v = JSON.parse(raw);
    return typeof v?.lineupId === 'string' ? { lineupId: v.lineupId, gameId: typeof v.gameId === 'string' ? v.gameId : null } : null;
  } catch {
    return null;
  }
}

export function rememberOpenLineup(teamId: string, value: StoredOpenLineup): void {
  try {
    globalThis.localStorage?.setItem(key(teamId), JSON.stringify(value));
  } catch {
    // Storage unavailable: the default game opens next time.
  }
}
