// Starting the next game, as iOS archiveCurrentLineup does: freeze the open
// lineup into a game log (roster snapshot, innings played, pitch counts,
// notes), then clear its positions and return it to draft, keeping the batting
// order. The web also sets the next game's opponent and date and marks
// everyone present, since it asks for both in the same step.
//
// The server's archive_game function does the same; this builds the result
// locally so the page updates before the save finishes.

import type { GameLog, Lineup, Player, PlayerID } from './model';

export interface ArchiveInput {
  id: string;
  inningsPlayed: number;
  notes: string;
  /** Pitches thrown, by player. Zero and blank are left out. */
  pitchCounts: Record<PlayerID, number>;
  archivedAt: Date;
}

export function gameLogFrom(lineup: Lineup, players: Player[], gameInningCount: number, coachName: string, a: ArchiveInput): GameLog {
  return {
    id: a.id,
    gameDate: lineup.gameDate,
    opponent: lineup.opponent,
    inningsPlayed: Math.max(1, Math.min(gameInningCount, a.inningsPlayed)),
    battingOrder: [...lineup.battingOrder],
    innings: lineup.innings.map((inn) => ({ assignments: { ...inn.assignments } })),
    playerSnapshot: players.map((p) => ({ id: p.id, firstName: p.firstName, lastName: p.lastName, number: p.number })),
    archivedAt: a.archivedAt,
    archivedBy: coachName.trim(),
    notes: a.notes.trim(),
    pitchCounts: Object.fromEntries(Object.entries(a.pitchCounts).filter(([, n]) => n > 0)),
  };
}

/** The open lineup cleared for the next game. */
export function nextGameLineup<L extends Lineup>(lineup: L, gameInningCount: number, next: { opponent: string; gameDate: Date }): L {
  const finalized = lineup.status === 'finalized';
  const out: L = {
    ...lineup,
    opponent: next.opponent.trim(),
    gameDate: next.gameDate,
    innings: Array.from({ length: gameInningCount }, () => ({ assignments: {} })),
    absentPlayerIDs: [],
    status: 'draft',
    lastFinalizedBy: finalized ? undefined : lineup.lastFinalizedBy,
    lastFinalizedAt: finalized ? undefined : lineup.lastFinalizedAt,
  };
  delete out.defaultTemplateID;
  return out;
}

/** Newest first, as iOS keeps them. */
export const addGameLog = (logs: GameLog[], log: GameLog): GameLog[] =>
  [...logs, log].sort((a, b) => b.gameDate.getTime() - a.gameDate.getTime());

/** Whether the open lineup has anything worth archiving (iOS: an opponent or any position). */
export const hasGameDetails = (l: Lineup) => l.opponent.trim() !== '' || l.innings.some((i) => Object.keys(i.assignments).length > 0);

/** Players who pitched in any inning, in the order they first pitched. */
export function pitchersIn(l: Lineup): PlayerID[] {
  const out: PlayerID[] = [];
  for (const inn of l.innings) {
    for (const [pid, pos] of Object.entries(inn.assignments)) if (pos === 'P' && !out.includes(pid)) out.push(pid);
  }
  return out;
}
