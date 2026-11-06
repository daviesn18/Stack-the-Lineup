// Swift/TypeScript parity (Web 5).
//
// The fixtures in fixtures/parity/ are written by the iOS test
// Lineup BuilderTests/ParityFixtureWriter.swift, from the real iOS engines.
// Each engine group runs here once its port is registered in
// src/core/parity/engines.ts; until then its scenarios show as pending.
//
// Pitch rules are calendar-day based, so these tests must run in the zone the
// fixtures were written in (the `test` script pins TZ).

import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

import type {
  FairPlayConfig, FieldPosition, GameLog, InningAssignment, Lineup, PitchingConfig, Player,
} from '../model';
import { evaluateAutoFill, INVARIANT_NAMES } from '../parity/autofillRules';
import {
  engines, type ConstraintSet, type PitchEligibilityStatus, type PitchingSummaryRow, type PlayerConstraint,
} from '../parity/engines';

const DIR = join(__dirname, '../../../fixtures/parity');
type Json = any;

function load(name: string): Json | null {
  const f = join(DIR, name);
  return existsSync(f) ? JSON.parse(readFileSync(f, 'utf8')) : null;
}

// MARK: - Fixture JSON -> model

const toPlayer = (j: Json): Player => ({
  id: j.id, firstName: j.firstName, lastName: j.lastName, number: j.number,
  ...(j.leagueAge !== undefined ? { leagueAge: j.leagueAge } : {}),
  positionPreferences: j.positionPreferences,
});
const toInning = (j: Record<string, FieldPosition>): InningAssignment => ({ assignments: { ...j } });
const toLineup = (j: Json): Lineup => ({
  gameDate: new Date(j.gameDate), opponent: j.opponent, battingOrder: j.battingOrder,
  innings: j.innings.map(toInning), absentPlayerIDs: j.absentPlayerIDs, status: j.status,
});
const toGameLog = (j: Json): GameLog => ({
  id: j.id, gameDate: new Date(j.gameDate), opponent: j.opponent, inningsPlayed: j.inningsPlayed,
  battingOrder: j.battingOrder, innings: j.innings.map(toInning), playerSnapshot: j.playerSnapshot,
  archivedAt: new Date(j.archivedAt), pitchCounts: j.pitchCounts, archivedBy: j.archivedBy, notes: j.notes,
});
const toFairPlay = (j: Json): FairPlayConfig => ({ ...j });
const toPitching = (j: Json): PitchingConfig => ({ ...j });
const ids = (ps: Player[]) => ps.map((p) => p.id);

const statusJson = (s: PitchEligibilityStatus) =>
  s.kind === 'limited' ? { kind: s.kind, remaining: s.remaining }
  : s.kind === 'mustRest' ? { kind: s.kind, until: isoSeconds(s.until) }
  : { kind: s.kind };
const rowJson = (r: PitchingSummaryRow) => ({
  playerID: r.player.id, pitchesInWindow: r.pitchesInWindow, dailyMax: r.dailyMax,
  available: r.available, restDaysRequired: r.restDaysRequired, status: statusJson(r.status),
});
/** Swift's ISO8601DateFormatter: UTC, whole seconds, "Z". */
const isoSeconds = (d: Date) => d.toISOString().replace(/\.\d{3}Z$/, 'Z');

/** Runs one test per scenario, or marks them pending while the engine is unported. */
function eachScenario<T extends { name?: string; prompt?: string }>(
  ported: boolean, scenarios: T[], fn: (s: T) => void,
) {
  scenarios.forEach((s, i) => {
    const title = s.name ?? `case ${i}: ${JSON.stringify(s.prompt)}`;
    if (ported) it(title, () => fn(s));
    else it.todo(title);
  });
}

const fairPlay = load('fair-play.json');
const pitching = load('pitch-eligibility.json');
const parse = load('autofill-parse.json');
const autofill = load('autofill.json');

describe('parity fixtures', () => {
  it('exist (run ParityFixtureWriter to generate them)', () => {
    expect([fairPlay, pitching, parse, autofill].every(Boolean)).toBe(true);
  });

  it('run in the time zone they were written in', () => {
    const zone = Intl.DateTimeFormat().resolvedOptions().timeZone;
    for (const f of [fairPlay, pitching, parse, autofill].filter(Boolean)) expect(zone).toBe(f.timeZone);
  });
});

describe('fair play (exact)', () => {
  eachScenario(!!engines.fairPlay, fairPlay?.scenarios ?? [], (s: Json) => {
    const e = engines.fairPlay!;
    const players = s.players.map(toPlayer);
    const lineup = toLineup(s.lineup);
    const config = toFairPlay(s.config);
    const x = s.expected;
    expect(e.activeFieldPositions(config)).toEqual(x.activeFieldPositions);
    expect(lineup.innings.map((_, i) => e.openPositions(lineup, i, players, config))).toEqual(x.openPositions);
    const f = e.fairPlayFindings(lineup, players, config);
    expect({
      withoutInfield: ids(f.withoutInfield), withoutOutfield: ids(f.withoutOutfield),
      underFieldingMinimum: ids(f.underFieldingMinimum), backToBackBench: ids(f.backToBackBench),
      catcherThenPitcher: ids(f.catcherThenPitcher), pitcherThenCatcher: ids(f.pitcherThenCatcher),
      minimumFieldingInnings: f.minimumFieldingInnings,
      implicatedPlayerIDs: [...new Set([
        ...f.withoutInfield, ...f.withoutOutfield, ...f.underFieldingMinimum, ...f.backToBackBench,
        ...f.catcherThenPitcher, ...f.pitcherThenCatcher,
      ].map((p) => p.id))].sort(),
    }).toEqual(x.findings);
    const b2b: Record<string, [number, number][]> = {};
    for (const p of players) {
      const pairs = e.backToBackBenchInnings(lineup, p);
      if (pairs.length) b2b[p.id] = pairs;
    }
    expect(b2b).toEqual(x.backToBackBenchInnings);
  });
});

describe('pitch eligibility and coaches-guide table (exact)', () => {
  const players: Player[] = (pitching?.players ?? []).map(toPlayer);
  const logs: GameLog[] = (pitching?.gameLogs ?? []).map(toGameLog);

  eachScenario(!!engines.pitching, pitching?.scenarios ?? [], (s: Json) => {
    const e = engines.pitching!;
    const config = toPitching(s.config);
    const ref = new Date(s.referenceDate);
    const statuses = e.compute(logs, players, config, ref);
    expect(Object.fromEntries(Object.entries(statuses).map(([k, v]) => [k, statusJson(v)]))).toEqual(s.expected.statuses);
    expect(e.pitchingSummaryRows(logs, players, config, ref).map(rowJson)).toEqual(s.expected.summaryRows);
    const guide = e.coachesGuideSummary(logs, players, config, ref);
    expect(guide === null ? null : guide.map(rowJson)).toEqual(s.expected.coachesGuide);
    expect(Object.fromEntries(players.map((p) => [p.id, e.pitchesRemaining(p, logs, config, ref)])))
      .toEqual(s.expected.pitchesRemaining);
  });

  eachScenario(!!engines.pitching, (pitching?.startOfPitchingWeek ?? []).map((w: Json) => ({ ...w, name: `week of ${w.date}` })),
    (w: Json) => {
      expect(isoSeconds(engines.pitching!.startOfPitchingWeek(new Date(w.date)))).toBe(w.startOfPitchingWeek);
    });
});

describe('Auto-Fill prompt parser (exact)', () => {
  const rosters: Record<string, Player[]> = Object.fromEntries(
    Object.entries(parse?.rosters ?? {}).map(([k, v]) => [k, (v as Json[]).map(toPlayer)]),
  );
  eachScenario(!!engines.parser, parse?.cases ?? [], (c: Json) => {
    const e = engines.parser!;
    const result = e.parseDeterministically(rosters[c.roster], c.inningCount, c.prompt);
    const pattern = e.detectedPatternRules(c.prompt);
    expect({
      constraints: result.constraints,
      hasUnresolvedInstruction: result.hasUnresolvedInstruction,
      benchInConsecutivePairs: pattern.benchInConsecutivePairs,
      shouldTrustDeterministic: e.shouldTrustDeterministic(result, pattern.benchInConsecutivePairs),
    }).toEqual(c.expected);
  });
});

// Web Auto-Fill is deliberately stricter than iOS about pitchers (rest days,
// no league age, avoid instructions in the last-resort pitcher fill), so in
// scenarios where that can bite, pitcher-shaped metrics are allowed to differ.
// The stricter rules are asserted directly instead.
const STRICTER_PITCHER_METRICS = new Set([
  'blockedPitcherInnings', 'maxPitcherInnings', 'distinctPitchers', 'filledCount', 'unfilledCount',
  'constraintRejections', 'overrides.pitcherSoftCapBypassedByFallback', 'overrides.pitcherSoftCapBypassed',
]);
// With an infield avoid, iOS's leak puts the player at pitcher (an infield
// position) in ~57% of fills, so iOS averages 3 - 0.57 = 2.43 players without
// infield where the web, keeping the instruction, is always 3. Zone counts
// shift by exactly that leak; everything else must still match.
const STRICTER_AVOID_METRICS = new Set(['playersWithoutInfield', 'playersWithoutOutfield', 'implicatedPlayers']);

/** Deterministic PRNG (mulberry32) so a failure reproduces exactly. */
function seeded(name: string): () => number {
  let a = [...name].reduce((h, c) => Math.imul(h ^ c.charCodeAt(0), 2654435761) >>> 0, 2166136261);
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const meanSd = (xs: number[]) => {
  const mean = xs.reduce((a, b) => a + b, 0) / xs.length;
  const sd = Math.sqrt(xs.reduce((a, b) => a + (b - mean) ** 2, 0) / xs.length);
  return { mean, sd };
};

describe('Auto-Fill (rules held in every iOS run, same distributions)', () => {
  const RUNS = 500;

  it('checks the same invariants the iOS writer checks', () => {
    if (!autofill) return;
    const known = new Set<string>(INVARIANT_NAMES);
    for (const s of autofill.scenarios) {
      for (const name of [...s.invariants, ...Object.keys(s.notAlwaysHeld)]) expect(known.has(name)).toBe(true);
    }
  });

  eachScenario(!!(engines.autofill && engines.fairPlay && engines.pitching), autofill?.scenarios ?? [], (s: Json) => {
    const input = s.input;
    const players = input.players.map(toPlayer);
    const lineup = toLineup(input.lineup);
    const config = toFairPlay(input.config);
    const pitchingConfig = input.pitchingConfig ? toPitching(input.pitchingConfig) : undefined;
    const gameLogs = input.gameLogs.map(toGameLog);
    const constraints: ConstraintSet = {
      playerConstraints: input.constraints as PlayerConstraint[],
      patternRules: input.patternRules,
    };
    const referenceDate = new Date(input.referenceDate);
    const scope = input.scope;
    const filled: [number, number] =
      scope.kind === 'game' ? [0, lineup.innings.length - 1]
      : scope.kind === 'through' ? [0, scope.inning] : [scope.inning, scope.inning];
    const hasAvoid = constraints.playerConstraints.some((c) => c.intent === 'avoid');
    const stricterApplies = !!pitchingConfig?.rulesEnabled || hasAvoid;
    const allowedDrift = (k: string) =>
      (stricterApplies && STRICTER_PITCHER_METRICS.has(k)) || (hasAvoid && STRICTER_AVOID_METRICS.has(k));
    const random = seeded(s.name);
    const samples: Record<string, number[]> = {};
    const outcomes = new Set<string>();

    for (let run = 0; run < RUNS; run++) {
      const result = engines.autofill!.fill({
        scope, lineup, players, config, pitchingConfig, gameLogs, constraints, referenceDate, random,
      } as Parameters<NonNullable<typeof engines.autofill>['fill']>[0]);
      const check = evaluateAutoFill({
        engines: { fairPlay: engines.fairPlay!, pitching: engines.pitching! },
        players, before: lineup, result, config, pitching: pitchingConfig, gameLogs, constraints,
        filledInnings: filled, referenceDate,
      });
      // Every guarantee iOS kept in all runs, plus the two web-only rules.
      const required = new Set<string>([...s.invariants, 'avoidConstraintsRespected']);
      const broken = [...required].filter((name) => check.violated.has(name));
      expect({ run, broken }).toEqual({ run, broken: [] });
      expect({ run, blockedPitcherInnings: check.metrics.blockedPitcherInnings })
        .toEqual({ run, blockedPitcherInnings: 0 });

      for (const [k, v] of Object.entries(check.metrics)) (samples[k] ??= []).push(v);
      for (const u of result.unfilledSlots) {
        if (!stricterApplies) expect(s.unfilledReasons).toContain(u.reason);
      }
      outcomes.add(result.unfilledSlots.map((u) => `${u.inningIndex}:${u.position}:${u.reason}`).sort().join(','));
    }

    // Where iOS was deterministic (one outcome in 500 runs), the web must be too.
    if (s.unfilledOutcomes.length === 1 && !stricterApplies) expect([...outcomes]).toEqual(s.unfilledOutcomes);

    // Averages match iOS within statistical tolerance.
    const drift: string[] = [];
    for (const [k, ios] of Object.entries(s.metrics) as [string, { mean: number; sd: number }][]) {
      if (allowedDrift(k)) continue;
      const web = meanSd(samples[k]);
      const diff = Math.abs(web.mean - ios.mean);
      if (ios.sd === 0 && web.sd === 0) {
        if (diff > 0) drift.push(`${k}: always ${web.mean} on web, always ${ios.mean} on iOS`);
        continue;
      }
      const se = Math.sqrt(ios.sd ** 2 / autofill.runs + web.sd ** 2 / RUNS);
      if (diff > 0.05 && diff / se > 5) {
        drift.push(`${k}: web mean ${web.mean.toFixed(3)} vs iOS ${ios.mean.toFixed(3)} (z=${(diff / se).toFixed(1)})`);
      }
    }
    expect(drift).toEqual([]);
  });
});
