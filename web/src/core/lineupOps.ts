// Lineup edits, as pure functions returning a new Lineup. Mirrors the
// LineupStore operations in Models.swift so the web grid behaves like the app:
//
//  * assign: taking a position that someone else holds that inning removes
//    them from it (they're left unassigned, not swapped). Bench and ABS are
//    shared and never evict.
//  * every edit to a finalized lineup quietly returns it to draft
//    (revertToDraftIfFinalized).
//  * marking a player absent drops them from the batting order and every
//    inning; marking them back appends them to the bottom of the order.

import { displayName, isNonFielding, type FieldPosition, type Lineup, type Player, type PlayerID } from './model';

const withInnings = (l: Lineup, innings: Lineup['innings']): Lineup => ({ ...l, innings });

/** Clears the finalized stamp only when the lineup was finalized. */
export function revertToDraft(l: Lineup): Lineup {
  if (l.status !== 'finalized') return l;
  const { lastFinalizedBy: _by, lastFinalizedAt: _at, ...rest } = l;
  return { ...rest, status: 'draft' };
}

export function assign(l: Lineup, playerID: PlayerID, innings: number[], position: FieldPosition): Lineup {
  const next = l.innings.map((inn, i) => {
    if (!innings.includes(i)) return inn;
    const a = { ...inn.assignments };
    if (!isNonFielding(position)) {
      for (const [id, pos] of Object.entries(a)) if (pos === position && id !== playerID) delete a[id];
    }
    a[playerID] = position;
    return { assignments: a };
  });
  return revertToDraft(withInnings(l, next));
}

export function unassign(l: Lineup, playerID: PlayerID, innings: number[]): Lineup {
  const next = l.innings.map((inn, i) => {
    if (!innings.includes(i) || !(playerID in inn.assignments)) return inn;
    const { [playerID]: _gone, ...rest } = inn.assignments;
    return { assignments: rest };
  });
  return revertToDraft(withInnings(l, next));
}

/** Empties every inning (iOS clearPositions); keeps date, opponent, order, absences. */
export function clearPositions(l: Lineup, inningCount = l.innings.length): Lineup {
  const { defaultTemplateID: _t, ...rest } = revertToDraft(l);
  return { ...rest, innings: Array.from({ length: inningCount }, () => ({ assignments: {} })) };
}

export function toggleAbsent(l: Lineup, playerID: PlayerID): Lineup {
  const base = revertToDraft(l);
  if (base.absentPlayerIDs.includes(playerID)) {
    return {
      ...base,
      absentPlayerIDs: base.absentPlayerIDs.filter((id) => id !== playerID),
      battingOrder: base.battingOrder.includes(playerID) ? base.battingOrder : [...base.battingOrder, playerID],
    };
  }
  return {
    ...base,
    absentPlayerIDs: [...base.absentPlayerIDs, playerID],
    battingOrder: base.battingOrder.filter((id) => id !== playerID),
    innings: base.innings.map((inn) => {
      if (!(playerID in inn.assignments)) return inn;
      const { [playerID]: _gone, ...rest } = inn.assignments;
      return { assignments: rest };
    }),
  };
}

/** Moves one batter to `to` (0-based index in the batting order). */
export function moveBatter(l: Lineup, playerID: PlayerID, to: number): Lineup {
  const order = l.battingOrder.filter((id) => id !== playerID);
  const at = Math.max(0, Math.min(to, order.length));
  order.splice(at, 0, playerID);
  return revertToDraft({ ...l, battingOrder: order });
}

export const addToBattingOrder = (l: Lineup, playerID: PlayerID): Lineup =>
  l.battingOrder.includes(playerID) ? l : { ...l, battingOrder: [...l.battingOrder, playerID] };

/** Removes a deleted player from the order and every inning (iOS deletePlayer). */
export function removePlayer(l: Lineup, playerID: PlayerID): Lineup {
  return {
    ...l,
    battingOrder: l.battingOrder.filter((id) => id !== playerID),
    absentPlayerIDs: l.absentPlayerIDs.filter((id) => id !== playerID),
    innings: l.innings.map((inn) => {
      if (!(playerID in inn.assignments)) return inn;
      const { [playerID]: _gone, ...rest } = inn.assignments;
      return { assignments: rest };
    }),
  };
}

export function finalize(l: Lineup, coachName: string, now = new Date()): Lineup {
  const by = coachName.trim();
  return { ...l, status: 'finalized', lastFinalizedAt: now, ...(by ? { lastFinalizedBy: by } : {}) };
}

/** iOS reopenLineup: back to draft, keeping who finalized it last. */
export const reopen = (l: Lineup): Lineup => ({ ...l, status: 'draft' });

/**
 * The batting order with every active player in it: the saved order first
 * (minus deleted or absent players), then anyone missing, in roster order.
 * A lineup whose order was left partial (an imported file with no order, or an
 * edit made before one existed) would otherwise hide players from the order,
 * the fair-play panel and the printouts. Returns `l` itself when complete.
 */
export function completeBattingOrder(l: Lineup, players: Player[]): Lineup {
  const absent = new Set(l.absentPlayerIDs);
  const known = new Set(players.map((p) => p.id));
  const kept = l.battingOrder.filter((id, i) => known.has(id) && !absent.has(id) && l.battingOrder.indexOf(id) === i);
  const inOrder = new Set(kept);
  const order = [...kept, ...players.filter((p) => !absent.has(p.id) && !inOrder.has(p.id)).map((p) => p.id)];
  const same = order.length === l.battingOrder.length && order.every((id, i) => id === l.battingOrder[i]);
  return same ? l : { ...l, battingOrder: order };
}

/** Active players in batting order, or in roster order until an order exists (iOS displayPlayers). */
export function displayPlayers(l: Lineup, players: Player[]): Player[] {
  const absent = new Set(l.absentPlayerIDs);
  const active = players.filter((p) => !absent.has(p.id));
  const byId = new Map(active.map((p) => [p.id, p]));
  const ordered = l.battingOrder.map((id) => byId.get(id)).filter((p): p is Player => !!p);
  return ordered.length ? ordered : active;
}

/** Innings whose assignments differ between two lineups (what needs saving). */
export function changedInnings(before: Lineup, after: Lineup): number[] {
  const out: number[] = [];
  for (let i = 0; i < after.innings.length; i++) {
    const a = before.innings[i]?.assignments ?? {};
    const b = after.innings[i].assignments;
    const keys = new Set([...Object.keys(a), ...Object.keys(b)]);
    for (const k of keys) if (a[k] !== b[k]) { out.push(i); break; }
  }
  return out;
}

/** "Jake R." — iOS Player.shortName. */
export function shortName(p: Pick<Player, 'firstName' | 'lastName'>): string {
  const initial = p.lastName.charAt(0);
  return initial ? `${p.firstName} ${initial}.` : p.firstName;
}

export { displayName };

// MARK: - Web grid (design handoff): assign with swap

/**
 * The web grid's core edit: put a player at `position` (a field spot, Bench,
 * or null for unassigned) in one inning. If someone else holds that field
 * spot, they SWAP into the player's old spot (or go to Bench if the player had
 * none). iOS `assign` evicts instead; the web picker, menu and drag and drop
 * all use this.
 */
export function place(l: Lineup, playerID: PlayerID, inning: number, position: FieldPosition | null): Lineup {
  const next = l.innings.map((inn, i) => {
    if (i !== inning) return inn;
    const a = { ...inn.assignments };
    const prev = a[playerID];
    if (position && !isNonFielding(position)) {
      const holder = Object.keys(a).find((id) => id !== playerID && a[id] === position);
      if (holder) a[holder] = prev && prev !== 'ABS' ? prev : 'Bench';
    }
    if (position) a[playerID] = position;
    else delete a[playerID];
    return { assignments: a };
  });
  return revertToDraft(withInnings(l, next));
}

/** "Keep here for remaining innings": the player's spot in `inning`, repeated (with swaps) to the end. */
export function keepForRemaining(l: Lineup, playerID: PlayerID, inning: number): Lineup {
  const position = l.innings[inning]?.assignments[playerID] ?? null;
  let out = l;
  for (let i = inning + 1; i < l.innings.length; i++) out = place(out, playerID, i, position);
  return out;
}

/** Back from absent: into the batting order (bottom) and on Bench wherever they have no spot. */
export function restoreAbsent(l: Lineup, playerID: PlayerID): Lineup {
  const back = l.absentPlayerIDs.includes(playerID) ? toggleAbsent(l, playerID) : l;
  return {
    ...back,
    innings: back.innings.map((inn) =>
      playerID in inn.assignments ? inn : { assignments: { ...inn.assignments, [playerID]: 'Bench' as FieldPosition } }),
  };
}

/**
 * What the grid calls each player: the first name, or "Caleb J." when two
 * players share a first name, or the full name if the initials match too.
 */
export function gridNames(players: Player[]): Map<PlayerID, string> {
  const count = (key: (p: Player) => string) => {
    const m = new Map<string, number>();
    for (const p of players) m.set(key(p), (m.get(key(p)) ?? 0) + 1);
    return (p: Player) => m.get(key(p)) ?? 0;
  };
  const first = count((p) => p.firstName.trim().toLowerCase());
  const short = count((p) => shortName(p).toLowerCase());
  return new Map(players.map((p) => [
    p.id, first(p) < 2 ? p.firstName : short(p) < 2 ? shortName(p) : displayName(p),
  ]));
}

/**
 * Game length changed (iOS applyGameInningCount): cut innings off the end or
 * add empty ones. Shortening a finalized lineup returns it to draft.
 */
export function resizeInnings(l: Lineup, count: number): Lineup {
  const n = Math.max(1, Math.min(9, count));
  if (n === l.innings.length) return l;
  if (n < l.innings.length) return revertToDraft(withInnings(l, l.innings.slice(0, n)));
  return withInnings(l, [...l.innings, ...Array.from({ length: n - l.innings.length }, () => ({ assignments: {} }))]);
}

/** The last inning (1-based) with anyone assigned, or 0. */
export const lastAssignedInning = (l: Lineup): number =>
  l.innings.reduce((last, inn, i) => (Object.keys(inn.assignments).length ? i + 1 : last), 0);

/**
 * Unassigns everyone at `positions` (taken off the field by a rules change,
 * e.g. going from 4 outfielders to 3), so nobody is left on a spot the grid
 * no longer shows. Returns `l` itself when nothing changed.
 */
export function dropPositions(l: Lineup, positions: FieldPosition[]): Lineup {
  if (!positions.length) return l;
  let changed = false;
  const innings = l.innings.map((inn) => {
    const a = Object.fromEntries(Object.entries(inn.assignments).filter(([, p]) => !positions.includes(p)));
    if (Object.keys(a).length === Object.keys(inn.assignments).length) return inn;
    changed = true;
    return { assignments: a };
  });
  return changed ? revertToDraft(withInnings(l, innings)) : l;
}
