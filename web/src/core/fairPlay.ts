// Fair-play validation: a port of the Lineup validators and fairPlayFindings
// in Models.swift. These drive the warnings on the grid and the coaches guide.
//
// Parity: fixtures/parity/fair-play.json (exact). Orders matter: every list
// keeps roster order, as the Swift filters do.

import {
  FIELD_POSITIONS, isInfield, isNonFielding, isOutfield,
  type FairPlayConfig, type FieldPosition, type Lineup, type Player,
} from './model';

export interface FairPlayFindings {
  /** Empty when the matching rule is off in the config. */
  withoutInfield: Player[];
  withoutOutfield: Player[];
  underFieldingMinimum: Player[];
  backToBackBench: Player[];
  catcherThenPitcher: Player[];
  pitcherThenCatcher: Player[];
  /** The threshold underFieldingMinimum was measured against. */
  minimumFieldingInnings: number;
}

export const positionFor = (lineup: Lineup, inning: number, player: Player): FieldPosition | undefined =>
  lineup.innings[inning]?.assignments[player.id];

export const activePlayers = (lineup: Lineup, players: Player[]): Player[] => {
  const absent = new Set(lineup.absentPlayerIDs);
  return players.filter((p) => !absent.has(p.id));
};

/** Removes P/C when toggled off; swaps CF for LCF + RCF with four outfielders. */
export function activeFieldPositions(config: FairPlayConfig): FieldPosition[] {
  return FIELD_POSITIONS.filter((p) => {
    if (config.noPitcher && p === 'P') return false;
    if (config.noCatcher && p === 'C') return false;
    if (config.outfielderCount === 4) return p !== 'CF';
    return p !== 'LCF' && p !== 'RCF';
  });
}

/** Positions still open in an inning. ABS counts as filled, as on iOS. */
export function openPositions(lineup: Lineup, inning: number, players: Player[], config: FairPlayConfig): FieldPosition[] {
  if (activePlayers(lineup, players).length === 0) return [];
  const filled = new Set<FieldPosition>(Object.values(lineup.innings[inning]?.assignments ?? {}).filter((p) => p !== 'ABS'));
  return activeFieldPositions(config).filter((p) => !filled.has(p));
}

/** Positions assigned to more than one player in an inning (bench and ABS excluded). */
export function duplicatePositions(lineup: Lineup, inning: number): FieldPosition[] {
  const seen = new Set<FieldPosition>();
  const dupes = new Set<FieldPosition>();
  for (const p of Object.values(lineup.innings[inning]?.assignments ?? {})) {
    if (isNonFielding(p)) continue;
    if (seen.has(p)) dupes.add(p);
    seen.add(p);
  }
  return [...dupes];
}

const playedSomewhere = (lineup: Lineup, player: Player, pred: (p: FieldPosition) => boolean) =>
  lineup.innings.some((inn) => {
    const p = inn.assignments[player.id];
    return p !== undefined && pred(p);
  });

export const playersWithoutInfield = (lineup: Lineup, players: Player[]) =>
  activePlayers(lineup, players).filter((p) => !playedSomewhere(lineup, p, isInfield));

export const playersWithoutOutfield = (lineup: Lineup, players: Player[]) =>
  activePlayers(lineup, players).filter((p) => !playedSomewhere(lineup, p, isOutfield));

/**
 * Active players with fewer than `minimumInnings` fielding innings. A player
 * with any ABS inning is exempt entirely.
 */
export function playersUnderFieldingMinimum(lineup: Lineup, players: Player[], minimumInnings = 4): Player[] {
  const active = activePlayers(lineup, players);
  if (active.length === 0) return [];
  return active.filter((player) => {
    if (playedSomewhere(lineup, player, (p) => p === 'ABS')) return false;
    const fielding = lineup.innings.filter((inn) => {
      const p = inn.assignments[player.id];
      return p !== undefined && !isNonFielding(p);
    }).length;
    return fielding < minimumInnings;
  });
}

/** 1-based inning pairs where the player sits twice in a row, e.g. [[3, 4]]. */
export function backToBackBenchInnings(lineup: Lineup, player: Player): [number, number][] {
  const out: [number, number][] = [];
  for (let i = 0; i < lineup.innings.length - 1; i++) {
    if (positionFor(lineup, i, player) === 'Bench' && positionFor(lineup, i + 1, player) === 'Bench') {
      out.push([i + 1, i + 2]);
    }
  }
  return out;
}

export const playersWithBackToBackBench = (lineup: Lineup, players: Player[]) =>
  activePlayers(lineup, players).filter((p) => backToBackBenchInnings(lineup, p).length > 0);

/**
 * True if the player reaches `threshold` innings at `from` before ever being
 * assigned `to`. Innings at `from` after the `to` inning don't count.
 */
function crossesBatteryTransition(
  lineup: Lineup, player: Player, from: FieldPosition, to: FieldPosition, threshold: number,
): boolean {
  let prior = 0;
  for (const inning of lineup.innings) {
    const p = inning.assignments[player.id];
    if (p === to && prior >= threshold) return true;
    if (p === from) prior += 1;
  }
  return false;
}

export const playersViolatingCatcherToPitcher = (lineup: Lineup, players: Player[], threshold: number) =>
  threshold > 0
    ? activePlayers(lineup, players).filter((p) => crossesBatteryTransition(lineup, p, 'C', 'P', threshold))
    : [];

export const playersViolatingPitcherToCatcher = (lineup: Lineup, players: Player[], threshold: number) =>
  threshold > 0
    ? activePlayers(lineup, players).filter((p) => crossesBatteryTransition(lineup, p, 'P', 'C', threshold))
    : [];

/**
 * Every fair-play rule the config has switched on. As on iOS, back-to-back
 * bench is given the full roster (it filters to active itself) while the other
 * rules get active players; the results are the same either way.
 */
export function fairPlayFindings(lineup: Lineup, players: Player[], config: FairPlayConfig): FairPlayFindings {
  const active = activePlayers(lineup, players);
  return {
    withoutInfield: config.minimumInfieldInnings > 0 ? playersWithoutInfield(lineup, active) : [],
    withoutOutfield: config.minimumOutfieldInnings > 0 ? playersWithoutOutfield(lineup, active) : [],
    underFieldingMinimum: config.minimumFieldingInnings > 0
      ? playersUnderFieldingMinimum(lineup, active, config.minimumFieldingInnings) : [],
    backToBackBench: config.noConsecutiveBench ? playersWithBackToBackBench(lineup, players) : [],
    catcherThenPitcher: playersViolatingCatcherToPitcher(lineup, active, config.catcherToPitcherThreshold),
    pitcherThenCatcher: playersViolatingPitcherToCatcher(lineup, active, config.pitcherToCatcherThreshold),
    minimumFieldingInnings: config.minimumFieldingInnings,
  };
}

/** Distinct players implicated in at least one rule (the badges count players, not violations). */
export const implicatedPlayerIDs = (f: FairPlayFindings): Set<string> =>
  new Set([
    ...f.withoutInfield, ...f.withoutOutfield, ...f.underFieldingMinimum,
    ...f.backToBackBench, ...f.catcherThenPitcher, ...f.pitcherThenCatcher,
  ].map((p) => p.id));
