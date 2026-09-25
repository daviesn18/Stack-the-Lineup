// The Team settings page edits a draft of the team row. This is the pure part:
// team row → draft, draft → team row, the unsaved-change count, the rail's
// status lines and the age-bracket table's ranges and warnings.

import { defaultFairPlayConfig, type FairPlayConfig, type PitchingAgeBracket, type PitchingLimits, type Player, type RollingWindowType } from '@/core/model';
import { bracketFor, LITTLE_LEAGUE_PRESET } from '@/core/pitching';
import type { TeamInfo } from '@/data/teamStore';

export const BRACKETS: PitchingAgeBracket[] = ['7-8', '9-10', '11-12', '13-14', '15-16'];

/** The fair-play fields that pausing turns off. Positions (P, C, outfielders) stay as they are. */
const RULE_KEYS = [
  'noConsecutiveBench', 'noConsecutivePosition', 'equalBenchTime', 'noRepeatPositions',
  'minimumFieldingInnings', 'minimumInfieldInnings', 'minimumOutfieldInnings',
  'catcherToPitcherThreshold', 'pitcherToCatcherThreshold',
] as const;

const rulesOff = (c: FairPlayConfig): FairPlayConfig => ({
  ...c, noConsecutiveBench: false, noConsecutivePosition: false, equalBenchTime: false, noRepeatPositions: false,
  minimumFieldingInnings: 0, minimumInfieldInnings: 0, minimumOutfieldInnings: 0,
  catcherToPitcherThreshold: 0, pitcherToCatcherThreshold: 0,
});

type Num = number | '';
export interface BracketRow { bracket: PitchingAgeBracket; max: Num; t: [Num, Num, Num, Num] }

export interface SettingsDraft {
  name: string;
  coach: string;
  /** Six hex digits, upper case, no #. */
  color: string;
  gameLen: number;
  /** Master switch. Off keeps `fair`'s rule values and saves them as paused. */
  fp: boolean;
  /** The coach's rule values, whether or not they're paused. */
  fair: FairPlayConfig;
  pc: boolean;
  cap: boolean;
  capN: Num;
  capReset: RollingWindowType;
  brackets: BracketRow[];
}

export function draftFromTeam(team: TeamInfo): SettingsDraft {
  const c = team.fairPlayConfig;
  const { pausedRules, ...live } = c;
  const p = team.pitchingConfig;
  return {
    name: team.name,
    coach: team.coachName,
    color: team.colorHex.toUpperCase(),
    gameLen: team.gameInningCount,
    fp: !pausedRules,
    fair: pausedRules ? { ...live, ...pausedRules } : live,
    pc: p.rulesEnabled,
    cap: p.weeklyLimitEnabled,
    capN: p.weeklyLimit || 100,
    capReset: p.rollingWindowType,
    brackets: BRACKETS.filter((b) => p.ageLimits[b]).map((b) => rowFromLimits(b, p.ageLimits[b]!)),
  };
}

const rowFromLimits = (bracket: PitchingAgeBracket, l: PitchingLimits): BracketRow => ({
  bracket, max: l.dailyMax, t: [l.restDay1Min, l.restDay2Min, l.restDay3Min ?? '', l.restDay4Min ?? ''],
});

/** The draft as a team row. Call only when `draftProblems` is empty. */
export function teamFromDraft(team: TeamInfo, d: SettingsDraft): TeamInfo {
  const { pausedRules: _, ...fair } = d.fair;
  const fairPlayConfig: FairPlayConfig = d.fp
    ? fair
    : { ...rulesOff(fair), pausedRules: Object.fromEntries(RULE_KEYS.map((k) => [k, fair[k]])) };
  const ageLimits: Partial<Record<PitchingAgeBracket, PitchingLimits>> = {};
  for (const r of d.brackets) {
    const [t1, t2, t3, t4] = r.t;
    const l: PitchingLimits = { dailyMax: Number(r.max), restDay1Min: Number(t1), restDay2Min: Number(t2) };
    if (t3 !== '') l.restDay3Min = t3;
    if (t4 !== '') l.restDay4Min = t4;
    ageLimits[r.bracket] = l;
  }
  return {
    ...team,
    name: d.name.trim(),
    coachName: d.coach.trim(),
    colorHex: d.color,
    gameInningCount: d.gameLen,
    fairPlayConfig,
    pitchingConfig: {
      ...team.pitchingConfig,
      rulesEnabled: d.pc,
      weeklyLimitEnabled: d.cap,
      weeklyLimit: d.capN === '' ? 0 : d.capN,
      rollingWindowType: d.capReset,
      ageLimits,
    },
  };
}

/** One entry per setting a coach would call a change; a bracket row counts once. */
function flatten(d: SettingsDraft): Map<string, string> {
  const f = d.fair;
  const m = new Map<string, string>(Object.entries({
    name: d.name.trim(), coach: d.coach.trim(), color: d.color, gameLen: d.gameLen, fp: d.fp,
    noP: f.noPitcher, noC: f.noCatcher, of: f.outfielderCount,
    b2b: f.noConsecutiveBench, eqBench: f.equalBenchTime, noRepeat: f.noRepeatPositions,
    minField: f.minimumFieldingInnings, minIF: f.minimumInfieldInnings, minOF: f.minimumOutfieldInnings,
    c2p: f.catcherToPitcherThreshold, p2c: f.pitcherToCatcherThreshold,
    pc: d.pc, cap: d.cap, capN: d.capN, capReset: d.capReset,
  }).map(([k, v]) => [k, String(v)]));
  for (const r of d.brackets) m.set(`br:${r.bracket}`, JSON.stringify([r.max, r.t]));
  return m;
}

export function changeCount(saved: SettingsDraft, draft: SettingsDraft): number {
  const a = flatten(saved);
  const b = flatten(draft);
  let n = 0;
  for (const k of new Set([...a.keys(), ...b.keys()])) if (a.get(k) !== b.get(k)) n++;
  return n;
}

/** Rules counted by the rail's "N rules on". */
export function rulesOn(f: FairPlayConfig): number {
  return [
    f.noConsecutiveBench, f.equalBenchTime, f.minimumFieldingInnings > 0, f.minimumInfieldInnings > 0,
    f.minimumOutfieldInnings > 0, f.catcherToPitcherThreshold > 0, f.pitcherToCatcherThreshold > 0, f.noRepeatPositions,
  ].filter(Boolean).length;
}

export function railStatus(d: SettingsDraft): Record<'team' | 'fair' | 'pitch', string> {
  const n = rulesOn(d.fair);
  return {
    team: d.name.trim() || 'Untitled team',
    fair: d.fp ? `${n} rule${n === 1 ? '' : 's'} on` : 'Paused',
    pitch: !d.pc ? 'Paused' : d.cap ? `${d.capN || 0} per week cap` : 'Rest days only',
  };
}

/** Fair play defaults, keeping the field (P, C, outfielders) as it is. */
export const resetFairPlay = (f: FairPlayConfig): FairPlayConfig => ({
  ...defaultFairPlayConfig(), noPitcher: f.noPitcher, noCatcher: f.noCatcher, outfielderCount: f.outfielderCount,
  leagueRuleset: f.leagueRuleset,
});

/** Keeps every minimum and threshold within a shorter game. */
export function clampToGame(f: FairPlayConfig, len: number): FairPlayConfig {
  const c = (n: number) => Math.min(n, len);
  return {
    ...f,
    minimumFieldingInnings: c(f.minimumFieldingInnings), minimumInfieldInnings: c(f.minimumInfieldInnings),
    minimumOutfieldInnings: c(f.minimumOutfieldInnings), catcherToPitcherThreshold: c(f.catcherToPitcherThreshold),
    pitcherToCatcherThreshold: c(f.pitcherToCatcherThreshold),
  };
}

export type TierCell = { kind: 'range'; text: string } | { kind: 'skipped' } | { kind: 'check' };

/**
 * What each rest tier covers: its start to one below the next filled tier's
 * start, or to the daily max. A tier that starts at or below an earlier one,
 * or covers nothing, needs a look.
 */
export function tierCells(r: BracketRow): TierCell[] {
  return r.t.map((start, i) => {
    if (start === '') return { kind: 'skipped' };
    const prev = r.t.slice(0, i).filter((x): x is number => x !== '');
    if (prev.some((p) => start <= p)) return { kind: 'check' };
    const next = r.t.slice(i + 1).find((x): x is number => x !== '');
    const end = next !== undefined ? next - 1 : r.max === '' ? undefined : r.max;
    if (end === undefined) return { kind: 'range', text: `${start}+` };
    if (end < start) return { kind: 'check' };
    return { kind: 'range', text: `${start}–${end}` };
  });
}

/** Why Save is off, or [] when the draft can be saved. */
export function draftProblems(d: SettingsDraft): string[] {
  const out: string[] = [];
  if (!d.name.trim()) out.push('Add a team name.');
  if (d.pc && d.cap && !d.capN) out.push('Set the most pitches per week.');
  for (const r of d.brackets) {
    const label = `Ages ${r.bracket}`;
    if (!r.max) out.push(`${label} needs a daily max.`);
    else if (r.t[0] === '' || r.t[1] === '') out.push(`${label} needs where 1 and 2 rest days start.`);
    else if (tierCells(r).some((c) => c.kind === 'check')) out.push(`Check the order of ${label}'s rest days.`);
  }
  return out;
}

/**
 * The next bracket to add: the first missing one after the last bracket in the
 * table (or the first missing overall), copying the bracket before it.
 */
export function nextBracket(rows: BracketRow[]): BracketRow | null {
  const have = new Set(rows.map((r) => r.bracket));
  const last = Math.max(-1, ...rows.map((r) => BRACKETS.indexOf(r.bracket)));
  const b = BRACKETS.slice(last + 1).find((x) => !have.has(x)) ?? BRACKETS.find((x) => !have.has(x));
  if (!b) return null;
  const before = [...rows].sort((x, y) => BRACKETS.indexOf(x.bracket) - BRACKETS.indexOf(y.bracket))
    .filter((r) => BRACKETS.indexOf(r.bracket) < BRACKETS.indexOf(b)).pop();
  return before ? { bracket: b, max: before.max, t: [...before.t] } : rowFromLimits(b, LITTLE_LEAGUE_PRESET[b]);
}

export const sortBrackets = (rows: BracketRow[]) =>
  [...rows].sort((a, b) => BRACKETS.indexOf(a.bracket) - BRACKETS.indexOf(b.bracket));

export const littleLeagueRows = (): BracketRow[] => BRACKETS.map((b) => rowFromLimits(b, LITTLE_LEAGUE_PRESET[b]));

/** The bracket most of the roster's league ages fall in. */
export function teamBracket(players: Player[]): PitchingAgeBracket | undefined {
  const n = new Map<PitchingAgeBracket, number>();
  for (const p of players) {
    const b = p.leagueAge === undefined ? undefined : bracketFor(p.leagueAge);
    if (b) n.set(b, (n.get(b) ?? 0) + 1);
  }
  return [...n.entries()].sort((a, b) => b[1] - a[1])[0]?.[0];
}
