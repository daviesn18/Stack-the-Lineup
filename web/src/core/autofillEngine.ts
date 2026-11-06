// Auto-Fill: a port of AutoFillEngine.swift. Fills open slots, never touching
// a cell the coach already set.
//
// The algorithm, ordering and tie-breaks follow Swift line by line; see the
// long header comment in AutoFillEngine.swift for the reasoning (field-queue
// tiers, bench queue, preference tiers, pitch capacity). Like iOS it shuffles
// within each priority tier, so two runs give two valid lineups; `random` can
// be injected for tests.
//
// Deliberately STRICTER than iOS (decided 2026-09-23; iOS tickets filed in the
// 3.5 section):
//  1. With pitching rules on, a pitcher whose eligibility status blocks
//     assignment (owes rest days, or has no league age) is never auto-placed,
//     and an explicit "X pitches" instruction for them is rejected with a
//     reason instead of honored. iOS only checks daily max / weekly cap here.
//  2. The last-resort pitcher fill honors every avoid instruction, including
//     zone avoids ("keep X out of the infield"). iOS only skips exact
//     avoid-pitcher instructions there.
// Both stay inside the ranges iOS produced, so parity holds.
//
// `referenceDate` is explicit (iOS reads today's date internally); the web
// coordinator passes the lineup's game date.
//
// Parity: fixtures/parity/autofill.json (rules held in every iOS run).

import type {
  AutoFillInput, AutoFillResult, ConstraintSet, ConstraintTarget, OverrideReason, PlayerConstraint,
  UnfilledReason,
} from './autofillTypes';
import {
  FIELD_POSITIONS, isInfield, isNonFielding, isOutfield,
  type FairPlayConfig, type FieldPosition, type GameLog, type Lineup, type PitchingConfig, type Player,
  type PositionPreferenceTier,
} from './model';
import { blocksAssignment, pitchesRemaining, status as pitchStatus } from './pitching';

/** Conservative pitches-per-inning estimate (low end of 20-25), protecting arms. */
const PITCHES_PER_INNING = 20;
const MAX_PITCHER_INNINGS_SOFT_CAP = 2;

type Prefs = Partial<Record<FieldPosition, PositionPreferenceTier>>;

interface Override { inningIndex: number; playerID: string; target: ConstraintTarget; reason: OverrideReason }
interface Rejection { inningIndex: number; playerID: string; target: ConstraintTarget; reason: string }
interface Unfilled { inningIndex: number; position: FieldPosition; reason: UnfilledReason }
interface PendingZoneCheck { inningIndex: number; playerID: string; target: ConstraintTarget; missing: 'infield' | 'outfield' }

export interface FillOptions extends AutoFillInput {
  /** Defaults to Math.random. */
  random?: () => number;
}

export function fill(input: FillOptions): AutoFillResult {
  const lineup = cloneLineup(input.lineup);
  const ctx: Context = {
    players: input.players,
    prefs: new Map(input.players.map((p) => [p.id, p.positionPreferences])),
    config: input.config,
    pitching: input.pitchingConfig,
    gameLogs: input.gameLogs,
    constraints: input.constraints,
    referenceDate: input.referenceDate,
    random: input.random ?? Math.random,
  };

  let innings: number[];
  switch (input.scope.kind) {
    case 'game':
      innings = range(0, lineup.innings.length - 1);
      break;
    case 'through':
      innings = range(0, Math.max(0, Math.min(input.scope.inning, lineup.innings.length - 1)));
      break;
    case 'inning':
      innings = [input.scope.inning];
      break;
  }

  let filledCount = 0;
  const unfilled: Unfilled[] = [];
  const overrides: Override[] = [];
  const rejections: Rejection[] = [];
  const pending: PendingZoneCheck[] = [];
  for (const i of innings) {
    const r = fillInning(i, lineup, ctx);
    filledCount += r.filled;
    unfilled.push(...r.unfilled);
    overrides.push(...r.overrides);
    rejections.push(...r.rejections);
    pending.push(...r.pending);
  }
  // Zone gaps are confirmed against the finished lineup: a gap after inning 2
  // may have closed by inning 6 within the same fill.
  overrides.push(...reconcileZoneChecks(pending, ctx.players, lineup));

  return { lineup, filledCount, unfilledSlots: unfilled, constraintOverrides: overrides, constraintRejections: rejections };
}

// MARK: - Internals

interface Context {
  players: Player[];
  prefs: Map<string, Prefs>;
  config: FairPlayConfig;
  pitching?: PitchingConfig;
  gameLogs: GameLog[];
  constraints: ConstraintSet;
  referenceDate: Date;
  random: () => number;
}

const range = (lo: number, hi: number) => (hi < lo ? [] : Array.from({ length: hi - lo + 1 }, (_, k) => lo + k));

function cloneLineup(l: Lineup): Lineup {
  return {
    ...l,
    battingOrder: [...l.battingOrder],
    absentPlayerIDs: [...l.absentPlayerIDs],
    innings: l.innings.map((inn) => ({ assignments: { ...inn.assignments } })),
  };
}

function shuffled<T>(items: T[], random: () => number): T[] {
  const a = [...items];
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(random() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

const constraintsAreEmpty = (c: ConstraintSet) =>
  c.playerConstraints.length === 0 && !c.patternRules.benchInConsecutivePairs;

function reconcileZoneChecks(pending: PendingZoneCheck[], players: Player[], finalLineup: Lineup): Override[] {
  const seen = { infield: new Set<string>(), outfield: new Set<string>() };
  const out: Override[] = [];
  for (const p of pending) {
    const player = players.find((x) => x.id === p.playerID);
    if (!player || seen[p.missing].has(p.playerID)) continue;
    const pred = p.missing === 'infield' ? isInfield : isOutfield;
    const stillMissing = !finalLineup.innings.some((inn) => {
      const x = inn.assignments[player.id];
      return x !== undefined && pred(x);
    });
    if (!stillMissing) continue;
    seen[p.missing].add(p.playerID);
    out.push({
      inningIndex: p.inningIndex, playerID: p.playerID, target: p.target,
      reason: p.missing === 'infield' ? 'fairPlayZoneSkipped.infield' : 'fairPlayZoneSkipped.outfield',
    });
  }
  return out;
}

function fillInning(inningIndex: number, lineup: Lineup, ctx: Context) {
  const empty = { filled: 0, unfilled: [] as Unfilled[], overrides: [] as Override[], rejections: [] as Rejection[], pending: [] as PendingZoneCheck[] };
  const { config, constraints } = ctx;
  const absent = new Set(lineup.absentPlayerIDs);
  const active = ctx.players.filter((p) => !absent.has(p.id));
  if (active.length === 0) return empty;

  const cell = (i: number, p: Player): FieldPosition | undefined => lineup.innings[i]?.assignments[p.id];
  const here = (p: Player) => cell(inningIndex, p);
  const assign = (p: Player, pos: FieldPosition) => { lineup.innings[inningIndex].assignments[p.id] = pos; };
  const prefsOf = (p: Player): Prefs => ctx.prefs.get(p.id) ?? {};

  let unassigned = active.filter((p) => here(p) === undefined);
  if (unassigned.length === 0) return empty;

  const occupied = new Set(Object.values(lineup.innings[inningIndex].assignments).filter((p) => p !== 'Bench'));
  const valid = FIELD_POSITIONS.filter((p) => {
    if (config.noPitcher && p === 'P') return false;
    if (config.noCatcher && p === 'C') return false;
    if (config.outfielderCount === 4) return p !== 'CF';
    return p !== 'LCF' && p !== 'RCF';
  });
  let open: FieldPosition[] = shuffled(valid.filter((p) => !occupied.has(p)), ctx.random);
  const removeOpen = (pos: FieldPosition) => { open = open.filter((p) => p !== pos); };
  let filled = 0;

  // MARK: stat helpers (read the live lineup)
  const benchInningsSoFar = (p: Player) => range(0, inningIndex - 1).filter((i) => cell(i, p) === 'Bench').length;
  const benchedLastInning = (p: Player) => inningIndex > 0 && cell(inningIndex - 1, p) === 'Bench';
  const mustCompleteBenchPair = (p: Player) => {
    if (!constraints.patternRules.benchInConsecutivePairs || inningIndex < 1) return false;
    if (cell(inningIndex - 1, p) !== 'Bench') return false;
    return !(inningIndex >= 2 && cell(inningIndex - 2, p) === 'Bench');
  };
  const consecutiveFieldInnings = (p: Player) => {
    let count = 0;
    for (let i = inningIndex - 1; i >= 0; i--) {
      const x = cell(i, p);
      if (x === undefined || isNonFielding(x)) break;
      count += 1;
    }
    return count;
  };
  const playedWhere = (p: Player, pred: (x: FieldPosition) => boolean) =>
    lineup.innings.some((inn) => { const x = inn.assignments[p.id]; return x !== undefined && pred(x); });
  const needsInfield = (p: Player) => !playedWhere(p, isInfield);
  const needsOutfield = (p: Player) => !playedWhere(p, isOutfield);

  // MARK: pitcher rules
  const pitcherInningsSoFar = (p: Player) => lineup.innings.filter((inn) => inn.assignments[p.id] === 'P').length;
  const hasExitedPitcher = (p: Player) => {
    let pitchedAt: number | undefined;
    for (let i = 0; i < lineup.innings.length; i++) {
      const x = cell(i, p);
      if (x === 'P') pitchedAt = i;
      else if (x !== undefined && x !== 'Bench' && x !== 'ABS' && pitchedAt !== undefined && i > pitchedAt) return true;
    }
    return false;
  };
  const rulesOn = !!ctx.pitching?.rulesEnabled;
  const restBlocked = (p: Player) =>
    rulesOn && blocksAssignment(pitchStatus(p, ctx.gameLogs, ctx.pitching!, ctx.referenceDate));
  const capacity = (p: Player): number | null => {
    if (!rulesOn) return null;
    const remaining = pitchesRemaining(p, ctx.gameLogs, ctx.pitching!, ctx.referenceDate);
    return remaining === null ? null : Math.floor(remaining / PITCHES_PER_INNING);
  };
  /** Hard rules: re-entry and Never. */
  const isPitcherBaseEligible = (p: Player) => !hasExitedPitcher(p) && prefsOf(p).P !== 'Never';
  /** Hard rules plus rest (web) and pitch capacity. */
  const isPitcherEligible = (p: Player) => {
    if (!isPitcherBaseEligible(p) || restBlocked(p)) return false;
    const cap = capacity(p);
    return cap === null || pitcherInningsSoFar(p) < cap;
  };
  const filteringPitcher = (p: Player, candidates: FieldPosition[], allowSoftCapBypass = false) => {
    if (!candidates.includes('P')) return candidates;
    if (!isPitcherEligible(p)) return candidates.filter((c) => c !== 'P');
    if (!allowSoftCapBypass && pitcherInningsSoFar(p) >= MAX_PITCHER_INNINGS_SOFT_CAP) {
      return candidates.filter((c) => c !== 'P');
    }
    return candidates;
  };

  // MARK: preferences and constraints
  /** Strength -> Capable -> untagged -> Emergency; Never excluded. */
  const preferredPosition = (p: Player, candidates: FieldPosition[]) => {
    const prefs = prefsOf(p);
    const allowed = candidates.filter((c) => prefs[c] !== 'Never');
    return allowed.find((c) => prefs[c] === 'Strength')
      ?? allowed.find((c) => prefs[c] === 'Capable')
      ?? allowed.find((c) => prefs[c] === undefined)
      ?? allowed.find((c) => prefs[c] === 'Emergency')
      ?? null;
  };
  const inningConstraints: PlayerConstraint[] = constraints.playerConstraints.filter(
    (c) => inningIndex >= c.inningRange[0] && inningIndex <= c.inningRange[1],
  );
  const avoidedPositions = (p: Player) => {
    const out = new Set<FieldPosition>();
    for (const c of inningConstraints) {
      if (c.playerID !== p.id || c.intent !== 'avoid') continue;
      if (c.target.kind === 'position') out.add(c.target.position);
      else if (c.target.kind === 'infield') FIELD_POSITIONS.filter(isInfield).forEach((x) => out.add(x));
      else if (c.target.kind === 'outfield') FIELD_POSITIONS.filter(isOutfield).forEach((x) => out.add(x));
    }
    return out;
  };
  const prioritizedPosition = (p: Player) => {
    for (const c of inningConstraints) {
      if (c.playerID === p.id && c.intent === 'prioritize' && c.target.kind === 'position') return c.target.position;
    }
    return null;
  };
  const resolvePosition = (p: Player, candidates: FieldPosition[]) => {
    const avoided = avoidedPositions(p);
    const filtered = avoided.size ? candidates.filter((c) => !avoided.has(c)) : candidates;
    if (filtered.length === 0) return null;
    const prio = prioritizedPosition(p);
    if (prio && filtered.includes(prio) && prefsOf(p)[prio] !== 'Never') return prio;
    return preferredPosition(p, filtered);
  };
  const freshCandidates = (candidates: FieldPosition[], p: Player) => {
    if (!config.noRepeatPositions) return candidates;
    const played = new Set(range(0, inningIndex - 1).map((i) => cell(i, p)).filter(
      (x): x is FieldPosition => x !== undefined && !isNonFielding(x)));
    const fresh = candidates.filter((c) => !played.has(c));
    return fresh.length ? fresh : candidates;
  };
  const place = (p: Player, pos: FieldPosition) => {
    assign(p, pos);
    removeOpen(pos);
    unassigned = unassigned.filter((x) => x.id !== p.id);
    filled += 1;
  };

  const forcedBench = new Set<string>();
  const overrides: Override[] = [];
  const rejections: Rejection[] = [];
  const pending: PendingZoneCheck[] = [];

  // MARK: 1. explicit "assign" instructions
  for (const c of inningConstraints) {
    if (c.intent !== 'assign') continue;
    const player = active.find((p) => p.id === c.playerID);
    if (!player || here(player) !== undefined) continue;
    if (c.target.kind === 'bench') { forcedBench.add(player.id); continue; }
    const candidates: FieldPosition[] =
      c.target.kind === 'position' ? [c.target.position]
      : c.target.kind === 'infield' ? open.filter(isInfield)
      : open.filter(isOutfield);
    const target = candidates.find((x) => open.includes(x));
    if (!target) {
      rejections.push({ inningIndex, playerID: player.id, target: c.target,
        reason: 'No open position was available to honor this instruction.' });
      continue;
    }
    if (target === 'P' && !isPitcherBaseEligible(player)) {
      rejections.push({ inningIndex, playerID: player.id, target: c.target,
        reason: 'Already exited the mound this game (re-entry rule), or marked Never for Pitcher.' });
      continue;
    }
    if (target === 'P' && restBlocked(player)) {
      rejections.push({ inningIndex, playerID: player.id, target: c.target,
        reason: 'Needs rest under your pitch count rules (or has no league age set), so they can\'t pitch today.' });
      continue;
    }
    place(player, target);
    if (target === 'P' && pitcherInningsSoFar(player) > MAX_PITCHER_INNINGS_SOFT_CAP) {
      overrides.push({ inningIndex, playerID: player.id, target: c.target, reason: 'pitcherSoftCapBypassed' });
    }
    if (!isInfield(target) && needsInfield(player)) {
      pending.push({ inningIndex, playerID: player.id, target: c.target, missing: 'infield' });
    }
    if (!isOutfield(target) && needsOutfield(player)) {
      pending.push({ inningIndex, playerID: player.id, target: c.target, missing: 'outfield' });
    }
  }

  // MARK: 2. bench pairing (pattern rule), within the bench budget
  const pairing = new Set<string>();
  if (constraints.patternRules.benchInConsecutivePairs) {
    const fieldEligible = unassigned.filter((p) => !forcedBench.has(p.id));
    let budget = Math.max(0, fieldEligible.length - open.length);
    for (const p of fieldEligible) {
      if (!mustCompleteBenchPair(p)) continue;
      if (budget <= 0) break;
      forcedBench.add(p.id);
      pairing.add(p.id);
      budget -= 1;
    }
  }
  for (const id of forcedBench) {
    if (pairing.has(id)) continue;
    const player = active.find((p) => p.id === id);
    if (!player) continue;
    const mine = benchInningsSoFar(player);
    const othersWithFewer = active.some((o) => o.id !== id && !forcedBench.has(o.id) && benchInningsSoFar(o) < mine);
    if (othersWithFewer) {
      overrides.push({ inningIndex, playerID: id, target: { kind: 'bench' }, reason: 'benchedOutOfTurn' });
    }
  }

  // MARK: 3. field queue
  const fieldEligible = unassigned.filter((p) => !forcedBench.has(p.id));
  const standardFieldOrder = (pool: Player[]) => {
    const sh = (xs: Player[]) => shuffled(xs, ctx.random);
    if (config.noConsecutiveBench) {
      return [
        ...sh(pool.filter((p) => benchedLastInning(p))),
        ...sh(pool.filter((p) => !benchedLastInning(p) && needsInfield(p))),
        ...sh(pool.filter((p) => !benchedLastInning(p) && !needsInfield(p) && needsOutfield(p))),
        ...sh(pool.filter((p) => !benchedLastInning(p) && !needsInfield(p) && !needsOutfield(p))),
      ];
    }
    return [
      ...sh(pool.filter((p) => needsInfield(p))),
      ...sh(pool.filter((p) => !needsInfield(p) && needsOutfield(p))),
      ...sh(pool.filter((p) => !needsInfield(p) && !needsOutfield(p))),
    ];
  };
  let fieldQueue: Player[];
  if (config.equalBenchTime) {
    // Most-benched first, so nobody sits twice before everyone has sat once.
    const groups = new Map<number, Player[]>();
    for (const p of fieldEligible) {
      const k = benchInningsSoFar(p);
      groups.set(k, [...(groups.get(k) ?? []), p]);
    }
    fieldQueue = [...groups.keys()].sort((a, b) => b - a).flatMap((k) => standardFieldOrder(groups.get(k)!));
  } else {
    fieldQueue = standardFieldOrder(fieldEligible);
  }

  for (const player of fieldQueue) {
    if (open.length === 0) break;
    let assigned = false;
    let neverBlockedInfield = false;
    let neverBlockedOutfield = false;
    if (needsInfield(player)) {
      const candidates = filteringPitcher(player, freshCandidates(open.filter(isInfield), player));
      if (candidates.length) {
        const pos = resolvePosition(player, candidates);
        if (pos) { place(player, pos); assigned = true; } else neverBlockedInfield = true;
      }
    }
    if (!assigned && needsOutfield(player)) {
      const candidates = freshCandidates(open.filter(isOutfield), player);
      if (candidates.length) {
        const pos = resolvePosition(player, candidates);
        if (pos) { place(player, pos); assigned = true; } else neverBlockedOutfield = true;
      }
    }
    if (!assigned) {
      let fallback = open;
      if (neverBlockedInfield) fallback = fallback.filter((x) => !isInfield(x));
      if (neverBlockedOutfield) fallback = fallback.filter((x) => !isOutfield(x));
      fallback = filteringPitcher(player, freshCandidates(fallback, player));
      const pos = resolvePosition(player, fallback);
      if (pos) place(player, pos);
    }
  }

  // MARK: 4. pitcher force-fill (soft cap bypassed; hard rules, rest and avoids kept)
  if (open.includes('P')) {
    const candidates = active
      .filter((p) => here(p) === undefined && isPitcherEligible(p) && !avoidedPositions(p).has('P') && !forcedBench.has(p.id))
      .sort((a, b) => pitcherInningsSoFar(a) - pitcherInningsSoFar(b));
    const pick = candidates[0];
    if (pick) {
      assign(pick, 'P');
      removeOpen('P');
      filled += 1;
      if (!constraintsAreEmpty(constraints) && pitcherInningsSoFar(pick) > MAX_PITCHER_INNINGS_SOFT_CAP) {
        overrides.push({ inningIndex, playerID: pick.id, target: { kind: 'position', position: 'P' },
          reason: 'pitcherSoftCapBypassedByFallback' });
      }
    }
  }

  // MARK: 5. bench: fewest bench innings first; back-to-back only when unavoidable
  const benchQueue = active.filter((p) => here(p) === undefined).sort((a, b) => {
    const ab = benchInningsSoFar(a), bb = benchInningsSoFar(b);
    if (ab !== bb) return ab - bb;
    const as = consecutiveFieldInnings(a), bs = consecutiveFieldInnings(b);
    if (as !== bs) return bs - as;
    return Number(benchedLastInning(a)) - Number(benchedLastInning(b));
  });
  const backToBack: Player[] = [];
  for (const p of benchQueue) {
    if (benchedLastInning(p)) backToBack.push(p);
    else { assign(p, 'Bench'); filled += 1; }
  }
  for (const p of backToBack) { assign(p, 'Bench'); filled += 1; }

  // MARK: 6. explain what stayed open
  const unfilled: Unfilled[] = open.map((position) => {
    let reason: UnfilledReason;
    if (position === 'P') {
      const allNever = active.every((p) => prefsOf(p).P === 'Never');
      const anyBase = active.some(isPitcherBaseEligible);
      const anyFull = active.some(isPitcherEligible);
      reason = allNever ? 'neverPreferences'
        : anyBase && !anyFull ? 'pitchCapacityLimited'
        : !anyBase ? 'pitcherReentry'
        : 'rosterTooSmall';
    } else {
      reason = active.some((p) => prefsOf(p)[position] !== 'Never') ? 'rosterTooSmall' : 'neverPreferences';
    }
    return { inningIndex, position, reason };
  });

  return { filled, unfilled, overrides, rejections, pending };
}
