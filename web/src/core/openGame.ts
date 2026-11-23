// Merge 3: which lineup is open is each device's own choice.
//
// teams.current_lineup_id used to say which lineup was open for the whole
// team, so opening Game 2 in one place moved every other device and coach off
// Game 1. Now each browser remembers its own (data/openLineup), and nothing
// reads or writes that column. Lineups themselves still sync.
//
// The same rule as OpenGame.swift on iOS; keep the two in step (their tests
// mirror each other).

import type { ScheduledGame } from './model';

export interface LineupRef {
  id: string;
  /** null for an ad-hoc lineup. */
  scheduledGameId: string | null;
}

export interface LogRef {
  id: string;
  /** The scheduled game it was archived from, when there was one. */
  scheduledGameId: string | null;
  opponent: string;
  /** Stamped by the server: who archived it (20261123000000_game_log_archiver). */
  archivedByUser: string | null;
  archivedByName: string;
}

export interface ArchivedElsewhere {
  /** The archiving coach's name, or null when the server doesn't know it. */
  byName: string | null;
  /** This same account, on another device. */
  byMe: boolean;
  opponent: string;
}

const same = (a: string | null | undefined, b: string | null | undefined) =>
  (a ?? '').toLowerCase() === (b ?? '').toLowerCase();

/**
 * The lineup a device opens when it has no choice of its own: the next game
 * from the start of today that has a lineup, else the latest past one, else
 * an ad-hoc lineup. Cancelled games are skipped. null: no lineups at all.
 */
export function defaultLineup(lineups: LineupRef[], games: ScheduledGame[], now = new Date(), preferredAdhoc?: string | null): string | null {
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
  const byId = new Map(games.map((g) => [g.id.toLowerCase(), g]));
  let upcoming: { id: string; at: number } | null = null;
  let past: { id: string; at: number } | null = null;
  const key = (at: number, id: string) => [at, id.toUpperCase()] as const;
  const before = (a: readonly [number, string], b: readonly [number, string]) => a[0] < b[0] || (a[0] === b[0] && a[1] < b[1]);
  for (const l of lineups) {
    const game = l.scheduledGameId ? byId.get(l.scheduledGameId.toLowerCase()) : undefined;
    if (!game || game.isCancelled) continue;
    const at = game.date.getTime();
    if (at >= today) {
      if (!upcoming || before(key(at, l.id), key(upcoming.at, upcoming.id))) upcoming = { id: l.id, at };
    } else if (!past || before(key(past.at, past.id), key(at, l.id))) {
      past = { id: l.id, at };
    }
  }
  if (upcoming) return upcoming.id;
  if (past) return past.id;
  const adhoc = lineups.filter((l) => !l.scheduledGameId).map((l) => l.id);
  if (preferredAdhoc && adhoc.some((id) => same(id, preferredAdhoc))) return adhoc.find((id) => same(id, preferredAdhoc))!;
  return adhoc.sort((a, b) => (a.toUpperCase() < b.toUpperCase() ? -1 : 1))[0] ?? null;
}

/**
 * Which lineup to open, given the one this device had open (`stored`). It
 * stays open while it still exists for the same game. Otherwise the default
 * opens, with a note when the old game was archived (not when it just left
 * the schedule).
 */
export function resolveOpenLineup(args: {
  lineups: LineupRef[]; games: ScheduledGame[]; logs: LogRef[];
  stored: { lineupId: string; gameId: string | null } | null;
  me?: string | null; now?: Date;
}): { lineupId: string | null; archived: ArchivedElsewhere | null } {
  const { lineups, games, logs, stored, me, now = new Date() } = args;
  if (stored) {
    const l = lineups.find((x) => same(x.id, stored.lineupId));
    if (l && same(l.scheduledGameId, stored.gameId)) return { lineupId: l.id, archived: null };
  }
  const next = defaultLineup(lineups, games, now, stored && !stored.gameId ? stored.lineupId : null);
  const log = stored?.gameId ? logs.find((g) => same(g.scheduledGameId, stored.gameId)) : undefined;
  if (!log) return { lineupId: next, archived: null };
  const name = log.archivedByName.trim();
  return {
    lineupId: next,
    archived: { byName: name || null, byMe: !!me && same(log.archivedByUser, me), opponent: log.opponent },
  };
}

/** "Sam archived the game vs Tigers. Showing your next game." */
export function archivedMessage(a: ArchivedElsewhere): string {
  const game = a.opponent ? `the game vs ${a.opponent}` : 'the game';
  const who = a.byMe ? `You archived ${game} on another device`
    : a.byName ? `${a.byName} archived ${game}` : `Another coach archived ${game}`;
  return `${who}. Showing your next game.`;
}
