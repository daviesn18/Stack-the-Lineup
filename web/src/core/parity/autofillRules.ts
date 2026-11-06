// The checks run on every Auto-Fill result in the parity tests. A line-by-line
// mirror of `AutoFillRules` in Lineup BuilderTests/ParityFixtureWriter.swift:
// the Swift side records which invariants held in every iOS run and the range
// of each metric; this side must reproduce the same names and arithmetic, or
// the comparison is meaningless. Keep the two in step.

import {
  isInfield, isNonFielding, isOutfield,
  type FairPlayConfig, type FieldPosition, type GameLog, type Lineup, type PitchingConfig, type Player,
} from '../model';
import type { AutoFillResult, ConstraintSet, Engines } from './engines';

export const INVARIANT_NAMES = [
  'lockedCellsUnchanged',
  'noDuplicateFielders',
  'neverPreferenceRespected',
  'absentPlayersUntouched',
  'onlyActivePositions',
  'pitcherReentryRespected',
  'everyActivePlayerPlaced',
  'pitchCapacityRespected',
  'avoidConstraintsRespected',
] as const;

export interface RuleCheck {
  violated: Set<string>;
  metrics: Record<string, number>;
}

export function evaluateAutoFill(args: {
  engines: Required<Pick<Engines, 'fairPlay' | 'pitching'>>;
  players: Player[];
  before: Lineup;
  result: AutoFillResult;
  config: FairPlayConfig;
  pitching?: PitchingConfig;
  gameLogs: GameLog[];
  constraints: ConstraintSet;
  filledInnings: [number, number];
  referenceDate: Date;
}): RuleCheck {
  const { engines, players, before, result, config, pitching, gameLogs, constraints, referenceDate } = args;
  const after = result.lineup;
  const violated = new Set<string>();
  const absent = new Set(after.absentPlayerIDs);
  const active = players.filter((p) => !absent.has(p.id));
  const activePositions = new Set(engines.fairPlay.activeFieldPositions(config));
  const pos = (l: Lineup, i: number, p: Player): FieldPosition | undefined => l.innings[i]?.assignments[p.id];
  const isAuto = (i: number, p: Player) => pos(before, i, p) === undefined && pos(after, i, p) !== undefined;
  const inningsIdx = after.innings.map((_, i) => i);

  for (const i of inningsIdx) {
    for (const p of players) {
      const b = pos(before, i, p);
      if (b !== undefined && pos(after, i, p) !== b) violated.add('lockedCellsUnchanged');
      if (before.absentPlayerIDs.includes(p.id) && isAuto(i, p)) violated.add('absentPlayersUntouched');
      const a = pos(after, i, p);
      if (!isAuto(i, p) || a === undefined) continue;
      if (p.positionPreferences[a] === 'Never') violated.add('neverPreferenceRespected');
      if (!isNonFielding(a) && !activePositions.has(a)) violated.add('onlyActivePositions');
      for (const k of constraints.playerConstraints) {
        if (k.playerID !== p.id || k.intent !== 'avoid') continue;
        if (i < k.inningRange[0] || i > k.inningRange[1]) continue;
        const t = k.target;
        const hit =
          t.kind === 'position' ? a === t.position :
          t.kind === 'infield' ? isInfield(a) :
          t.kind === 'outfield' ? isOutfield(a) : false;
        if (hit) violated.add('avoidConstraintsRespected');
      }
    }
    const fielding = Object.values(after.innings[i].assignments).filter((x) => !isNonFielding(x));
    if (new Set(fielding).size !== fielding.length) violated.add('noDuplicateFielders');
  }

  const [first, last] = args.filledInnings;
  for (let i = first; i <= last; i++) {
    if (active.length && active.some((p) => pos(after, i, p) === undefined)) violated.add('everyActivePlayerPlaced');
  }

  for (const p of players) {
    let pitchedAt: number | undefined;
    for (const i of inningsIdx) {
      if (pos(after, i, p) !== 'P') continue;
      if (pitchedAt !== undefined && isAuto(i, p)) {
        for (let j = pitchedAt + 1; j < i; j++) {
          const q = pos(after, j, p);
          if (q !== undefined && !isNonFielding(q) && q !== 'P') violated.add('pitcherReentryRespected');
        }
      }
      pitchedAt = i;
    }
    if (pitching?.rulesEnabled) {
      const remaining = engines.pitching.pitchesRemaining(p, gameLogs, pitching, referenceDate);
      if (remaining !== null) {
        const capacity = Math.floor(remaining / 20);
        const autoP = inningsIdx.filter((i) => isAuto(i, p) && pos(after, i, p) === 'P').length;
        const totalP = inningsIdx.filter((i) => pos(after, i, p) === 'P').length;
        if (autoP > 0 && totalP > capacity) violated.add('pitchCapacityRespected');
      }
    }
  }

  // Metrics over the filled innings.
  const range = Array.from({ length: last - first + 1 }, (_, k) => first + k);
  const bench = active.map((p) => range.filter((i) => pos(after, i, p) === 'Bench').length);
  const f = engines.fairPlay.fairPlayFindings(after, players, config);
  const implicated = new Set(
    [...f.withoutInfield, ...f.withoutOutfield, ...f.underFieldingMinimum, ...f.backToBackBench,
     ...f.catcherThenPitcher, ...f.pitcherThenCatcher].map((p) => p.id),
  );
  const pitcherInnings = new Map<string, number>();
  for (const inning of after.innings) {
    for (const [id, a] of Object.entries(inning.assignments)) {
      if (a === 'P') pitcherInnings.set(id, (pitcherInnings.get(id) ?? 0) + 1);
    }
  }
  let repeats = 0;
  for (const p of active) {
    const played = after.innings.map((inn) => inn.assignments[p.id]).filter((x): x is FieldPosition =>
      x !== undefined && !isNonFielding(x));
    repeats += played.length - new Set(played).size;
  }
  let blockedPitcherInnings = 0;
  if (pitching?.rulesEnabled) {
    for (const p of players) {
      const s = engines.pitching.status(p, gameLogs, pitching, referenceDate);
      if (s.kind === 'mustRest' || s.kind === 'unknownAge') {
        blockedPitcherInnings += inningsIdx.filter((i) => isAuto(i, p) && pos(after, i, p) === 'P').length;
      }
    }
  }
  const overrides = (reason: string) => result.constraintOverrides.filter((o) => o.reason === reason).length;
  const has = (p: Player, pred: (x: FieldPosition) => boolean) =>
    after.innings.some((inn) => { const x = inn.assignments[p.id]; return x !== undefined && pred(x); });

  const metrics: Record<string, number> = {
    filledCount: result.filledCount,
    unfilledCount: result.unfilledSlots.length,
    benchSpread: bench.length ? Math.max(...bench) - Math.min(...bench) : 0,
    maxBenchInnings: bench.length ? Math.max(...bench) : 0,
    backToBackBenchPlayers: active.filter((p) => engines.fairPlay.backToBackBenchInnings(after, p).length > 0).length,
    playersWithoutInfield: active.filter((p) => !has(p, isInfield)).length,
    playersWithoutOutfield: active.filter((p) => !has(p, isOutfield)).length,
    playersUnderFieldingMinimum: config.minimumFieldingInnings > 0 ? f.underFieldingMinimum.length : 0,
    implicatedPlayers: implicated.size,
    repeatPositions: repeats,
    distinctPitchers: pitcherInnings.size,
    maxPitcherInnings: pitcherInnings.size ? Math.max(...pitcherInnings.values()) : 0,
    blockedPitcherInnings,
    constraintRejections: result.constraintRejections.length,
    'overrides.pitcherSoftCapBypassed': overrides('pitcherSoftCapBypassed'),
    'overrides.pitcherSoftCapBypassedByFallback': overrides('pitcherSoftCapBypassedByFallback'),
    'overrides.benchedOutOfTurn': overrides('benchedOutOfTurn'),
    'overrides.fairPlayZoneSkipped.infield': overrides('fairPlayZoneSkipped.infield'),
    'overrides.fairPlayZoneSkipped.outfield': overrides('fairPlayZoneSkipped.outfield'),
  };
  return { violated, metrics };
}
