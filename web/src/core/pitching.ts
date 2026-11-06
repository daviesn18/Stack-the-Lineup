// Pitch-count rules: a port of PitchEligibilityEngine.swift, the Little League
// preset and restDaysRequired from Models.swift, and pitchesRemaining from
// DefensiveGridView.swift.
//
// These numbers protect kids' arms and print on the coaches guide, so the port
// is exact, including the calendar arithmetic: days are LOCAL calendar days,
// like Calendar.current on iOS. Adding days keeps the wall-clock time (a
// 00:00 stays 00:00 across a DST change), matching Calendar.date(byAdding:).
//
// Parity: fixtures/parity/pitch-eligibility.json (exact).

import type {
  GameLog, PitchingAgeBracket, PitchingConfig, PitchingLimits, Player, PlayerID,
} from './model';

export type PitchEligibilityStatus =
  | { kind: 'eligible' }
  | { kind: 'limited'; remaining: number }
  /** May pitch again ON `until` (a local midnight). */
  | { kind: 'mustRest'; until: Date }
  | { kind: 'unknownAge' };

/** Eligible or limited: the player may pitch. */
export const isEligible = (s: PitchEligibilityStatus) => s.kind === 'eligible' || s.kind === 'limited';
/** Must rest or age unknown: the player cannot be assigned pitcher. */
export const blocksAssignment = (s: PitchEligibilityStatus) => !isEligible(s);

export interface PitchingSummaryRow {
  player: Player;
  pitchesInWindow: number;
  dailyMax: number;
  /** min(daily max, what's left in the weekly window): what they can throw today. */
  available: number;
  /** Rest days owed from the most recent outing; only meaningful with a restricted status. */
  restDaysRequired: number;
  status: PitchEligibilityStatus;
}

// MARK: - Rules tables

export function bracketFor(age: number): PitchingAgeBracket | undefined {
  if (age <= 8) return '7-8';
  if (age <= 10) return '9-10';
  if (age <= 12) return '11-12';
  if (age <= 14) return '13-14';
  if (age <= 16) return '15-16';
  return undefined;
}

export function restDaysRequired(limits: PitchingLimits, pitches: number): number {
  if (limits.restDay4Min !== undefined && pitches >= limits.restDay4Min) return 4;
  if (limits.restDay3Min !== undefined && pitches >= limits.restDay3Min) return 3;
  if (pitches >= limits.restDay2Min) return 2;
  if (pitches >= limits.restDay1Min) return 1;
  return 0;
}

/** Standard Little League pitch counts. A starting point; coaches can edit every value. */
export const LITTLE_LEAGUE_PRESET: Record<PitchingAgeBracket, PitchingLimits> = {
  '7-8': { dailyMax: 50, restDay1Min: 21, restDay2Min: 36 },
  '9-10': { dailyMax: 75, restDay1Min: 21, restDay2Min: 36, restDay3Min: 51, restDay4Min: 66 },
  '11-12': { dailyMax: 85, restDay1Min: 21, restDay2Min: 36, restDay3Min: 51, restDay4Min: 66 },
  '13-14': { dailyMax: 95, restDay1Min: 21, restDay2Min: 36, restDay3Min: 51, restDay4Min: 66 },
  '15-16': { dailyMax: 95, restDay1Min: 31, restDay2Min: 46, restDay3Min: 61, restDay4Min: 76 },
};

export const applyLittleLeaguePreset = (config: PitchingConfig): PitchingConfig => ({
  ...config,
  ageLimits: Object.fromEntries(Object.entries(LITTLE_LEAGUE_PRESET).map(([k, v]) => [k, { ...v }])),
});

const limitsFor = (player: Player, config: PitchingConfig): PitchingLimits | undefined => {
  if (player.leagueAge === undefined) return undefined;
  const bracket = bracketFor(player.leagueAge);
  return bracket ? config.ageLimits[bracket] : undefined;
};

// MARK: - Local calendar days

export const startOfDay = (d: Date) => new Date(d.getFullYear(), d.getMonth(), d.getDate());

/** Calendar.date(byAdding: .day, value: n, to:): same wall-clock time, n days later. */
export const addDays = (d: Date, n: number) =>
  new Date(d.getFullYear(), d.getMonth(), d.getDate() + n, d.getHours(), d.getMinutes(), d.getSeconds(),
    d.getMilliseconds());

/**
 * Monday 00:00 of the week containing `date`, by counting back from the
 * weekday. (The iOS comment explains why: rebuilding from weekOfYear follows
 * the locale's week start and broke the weekly cap on Sundays.)
 */
export function startOfPitchingWeek(date: Date): Date {
  const today = startOfDay(date);
  // getDay(): 0 = Sunday ... 6 = Saturday. Monday -> 0 days back, Sunday -> 6.
  const daysSinceMonday = (today.getDay() + 6) % 7;
  return addDays(today, -daysSinceMonday);
}

// MARK: - Engine

interface PitchEntry { gameDate: Date; pitches: number }

/** One entry per game with pitches > 0, oldest first. */
function pitchEntries(playerID: PlayerID, gameLogs: GameLog[]): PitchEntry[] {
  return gameLogs
    .flatMap((log) => {
      const n = log.pitchCounts[playerID];
      return n !== undefined && n > 0 ? [{ gameDate: log.gameDate, pitches: n }] : [];
    })
    .sort((a, b) => a.gameDate.getTime() - b.gameDate.getTime());
}

/** Most recent outing on a day before today, if any. */
const lastPastEntry = (entries: PitchEntry[], today: Date) =>
  [...entries].reverse().find((e) => startOfDay(e.gameDate) < today);

function windowStartDate(config: PitchingConfig, referenceDate: Date): Date {
  const today = startOfDay(referenceDate);
  return config.rollingWindowType === 'Calendar Week'
    ? startOfPitchingWeek(today)
    : addDays(today, -(config.rollingWindowDays - 1));
}

/** Entries inside the window, not counting today (today's game isn't archived yet). */
function entriesInWindow(entries: PitchEntry[], config: PitchingConfig, referenceDate: Date): PitchEntry[] {
  const start = windowStartDate(config, referenceDate);
  const today = startOfDay(referenceDate);
  return entries.filter((e) => {
    const day = startOfDay(e.gameDate);
    return day >= start && day < today;
  });
}

const pitchesInWindow = (entries: PitchEntry[], config: PitchingConfig, referenceDate: Date) =>
  entriesInWindow(entries, config, referenceDate).reduce((sum, e) => sum + e.pitches, 0);

function restDayStatus(entries: PitchEntry[], limits: PitchingLimits, referenceDate: Date): PitchEligibilityStatus | null {
  const today = startOfDay(referenceDate);
  const last = lastPastEntry(entries, today);
  if (!last) return null;
  const rest = restDaysRequired(limits, last.pitches);
  if (rest <= 0) return null;
  // 25 pitches Monday = 1 rest day (Tuesday), available Wednesday: gameDay + rest + 1.
  const available = addDays(startOfDay(last.gameDate), rest + 1);
  return today < available ? { kind: 'mustRest', until: available } : null;
}

/** When the weekly cap clears: the oldest in-window game rolls off (rolling) or next Monday (calendar week). */
function windowClearDate(entries: PitchEntry[], config: PitchingConfig, referenceDate: Date): Date | null {
  const inWindow = entriesInWindow(entries, config, referenceDate);
  if (inWindow.length === 0) return null;
  if (config.rollingWindowType === 'Rolling 7 Days') {
    const oldest = inWindow.reduce((a, b) => (b.gameDate < a.gameDate ? b : a));
    return addDays(startOfDay(oldest.gameDate), config.rollingWindowDays);
  }
  return addDays(startOfPitchingWeek(startOfDay(referenceDate)), 7);
}

/** Eligibility for one player. */
export function status(
  player: Player, gameLogs: GameLog[], config: PitchingConfig, referenceDate: Date,
): PitchEligibilityStatus {
  if (!config.rulesEnabled) return { kind: 'eligible' };
  if (player.leagueAge === undefined) return { kind: 'unknownAge' };
  const limits = limitsFor(player, config);
  if (!limits) return { kind: 'eligible' };      // age outside every configured bracket

  const entries = pitchEntries(player.id, gameLogs);
  const rest = restDayStatus(entries, limits, referenceDate);
  if (rest) return rest;

  if (config.weeklyLimitEnabled && config.weeklyLimit > 0) {
    const remaining = config.weeklyLimit - pitchesInWindow(entries, config, referenceDate);
    if (remaining <= 0) {
      return { kind: 'mustRest', until: windowClearDate(entries, config, referenceDate) ?? referenceDate };
    }
    const effectiveMax = Math.min(limits.dailyMax, remaining);
    if (effectiveMax < limits.dailyMax) return { kind: 'limited', remaining: effectiveMax };
  }
  return { kind: 'eligible' };
}

/** Eligibility for every player not marked Never at pitcher. Empty when rules are off. */
export function compute(
  gameLogs: GameLog[], players: Player[], config: PitchingConfig, referenceDate: Date,
): Record<PlayerID, PitchEligibilityStatus> {
  if (!config.rulesEnabled) return {};
  const out: Record<PlayerID, PitchEligibilityStatus> = {};
  for (const p of players) {
    if (p.positionPreferences.P !== 'Never') out[p.id] = status(p, gameLogs, config, referenceDate);
  }
  return out;
}

/** The per-player pitching math for exactly the players given, in order. No filtering or sorting. */
export function pitchingSummaryRows(
  gameLogs: GameLog[], players: Player[], config: PitchingConfig, referenceDate: Date,
): PitchingSummaryRow[] {
  const statuses = compute(gameLogs, players, config, referenceDate);
  const today = startOfDay(referenceDate);
  return players.map((player) => {
    const limits = limitsFor(player, config);
    const entries = pitchEntries(player.id, gameLogs);
    const windowPitches = pitchesInWindow(entries, config, referenceDate);
    const last = lastPastEntry(entries, today);
    const restDays = last && limits ? restDaysRequired(limits, last.pitches) : 0;
    const dailyMax = limits?.dailyMax ?? 0;
    let available = dailyMax;
    if (config.weeklyLimitEnabled && config.weeklyLimit > 0) {
      available = Math.min(dailyMax, Math.max(0, config.weeklyLimit - windowPitches));
    }
    return {
      player, pitchesInWindow: windowPitches, dailyMax, available,
      restDaysRequired: restDays, status: statuses[player.id] ?? { kind: 'eligible' },
    };
  });
}

/**
 * Rows for the coaches-guide pitch table: Never-pitchers excluded, null when
 * rules are off or nobody can pitch. Sorted as a coach reads it: who can
 * throw first, most available first, then last name.
 */
export function coachesGuideSummary(
  gameLogs: GameLog[], players: Player[], config: PitchingConfig, referenceDate: Date,
): PitchingSummaryRow[] | null {
  if (!config.rulesEnabled) return null;
  const pitchable = players.filter((p) => p.positionPreferences.P !== 'Never');
  if (pitchable.length === 0) return null;
  return pitchingSummaryRows(gameLogs, pitchable, config, referenceDate).sort((a, b) => {
    const ra = blocksAssignment(a.status);
    const rb = blocksAssignment(b.status);
    if (ra !== rb) return ra ? 1 : -1;
    if (a.available !== b.available) return b.available - a.available;
    return a.player.lastName < b.player.lastName ? -1 : a.player.lastName > b.player.lastName ? 1 : 0;
  });
}

/**
 * Pitches the player can throw today: min(daily max, weekly cap remaining).
 * Null when rules are off, the player is Never at pitcher, or has no bracket.
 * (Rest days are NOT considered here, which is the iOS behavior; Auto-Fill on
 * the web additionally checks `status` before placing a pitcher.)
 */
export function pitchesRemaining(
  player: Player, gameLogs: GameLog[], config: PitchingConfig, referenceDate: Date,
): number | null {
  if (!config.rulesEnabled) return null;
  if (player.positionPreferences.P === 'Never') return null;
  const limits = limitsFor(player, config);
  if (!limits) return null;
  const start = windowStartDate(config, referenceDate);
  const today = startOfDay(referenceDate);
  const windowPitches = gameLogs
    .filter((log) => {
      const day = startOfDay(log.gameDate);
      return day >= start && day < today;
    })
    .reduce((sum, log) => sum + (log.pitchCounts[player.id] ?? 0), 0);
  let available = limits.dailyMax;
  if (config.weeklyLimitEnabled && config.weeklyLimit > 0) {
    available = Math.min(available, Math.max(0, config.weeklyLimit - windowPitches));
  }
  return available;
}
