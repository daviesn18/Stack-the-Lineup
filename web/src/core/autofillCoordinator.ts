// Runs one Auto-Fill for the grid and turns the result into what the coach
// sees. Port of AutoFillCoordinator.run/outcome and AutoFillResult's
// incompleteMessage / constraintNoticeMessage; message wording is the iOS copy.
//
// Web differences:
//  * No on-device model. The deterministic parser always runs; when it can't
//    confidently read an instruction (iOS would ask Apple Intelligence), its
//    best-effort constraints are still used and the coach is told.
//  * The pitch-rules reference date is the lineup's game date (iOS Auto-Fill
//    used today's date; its grid warning already used the game date).
//  * The unfilled-pitcher copy mentions rest days, since the web also blocks
//    pitchers who must rest.

import { AutoFillParser, BENCH_PAIRING_CONFIRMATION, detectedPatternRules } from './autofillParser';
import { fill } from './autofillEngine';
import type { AutoFillResult, ConstraintSet, ConstraintTarget } from './autofillTypes';
import type { FairPlayConfig, GameLog, Lineup, PitchingConfig, Player } from './model';
import { shortName } from './lineupOps';

export type FillScope = { kind: 'inning'; inning: number } | { kind: 'through'; inning: number };

export interface AutoFillOutcome {
  scope: FillScope;
  lineup: Lineup;
  filledCount: number;
  /** Why some slots stayed empty, or null. */
  incompleteMessage: string | null;
  /** Parse misses and instruction notices, combined, or null. */
  noticeMessage: string | null;
  /** "Auto-filled 9 positions (inning 3)". */
  undoMessage: string;
}

export const scopeLabel = (s: FillScope) => (s.kind === 'inning' ? `inning ${s.inning + 1}` : `innings 1–${s.inning + 1}`);

export function runAutoFill(args: {
  scope: FillScope;
  prompt: string;
  lineup: Lineup;
  players: Player[];
  config: FairPlayConfig;
  pitchingConfig?: PitchingConfig;
  gameLogs: GameLog[];
  random?: () => number;
}): AutoFillOutcome {
  const { scope, lineup, players } = args;
  const prompt = args.prompt.trim();
  let constraints: ConstraintSet = { playerConstraints: [], patternRules: { benchInConsecutivePairs: false } };
  const parseNotes: string[] = [];

  if (prompt) {
    const absent = new Set(lineup.absentPlayerIDs);
    const active = players.filter((p) => !absent.has(p.id));
    const parse = new AutoFillParser(active, lineup.innings.length).parseDeterministically(prompt);
    constraints = { playerConstraints: parse.constraints, patternRules: { benchInConsecutivePairs: false } };
    if (parse.hasUnresolvedInstruction) {
      parseNotes.push(parse.constraints.length
        ? 'Part of your note wasn\'t clear enough to follow, so only the instructions that were clear were used. Check the lineup, and try one instruction per line, like "Jake pitches innings 1 to 2".'
        : 'Your note wasn\'t clear enough to follow, so the lineup was filled without it. Try one instruction per line, like "Jake pitches innings 1 to 2".');
    }
    // Pattern rules (no player named) come from the same text detection on every path.
    if (detectedPatternRules(prompt).benchInConsecutivePairs) {
      constraints = { ...constraints, patternRules: { benchInConsecutivePairs: true } };
      parseNotes.push(BENCH_PAIRING_CONFIRMATION);
    }
  }

  const result = fill({
    scope: scope.kind === 'inning' ? { kind: 'inning', inning: scope.inning } : { kind: 'through', inning: scope.inning },
    lineup, players, config: args.config, pitchingConfig: args.pitchingConfig, gameLogs: args.gameLogs,
    constraints, referenceDate: lineup.gameDate, random: args.random,
  });

  const notice = [parseNotes.join('\n') || null, constraintNoticeMessage(result, players)].filter(Boolean).join('\n');
  const noun = result.filledCount === 1 ? 'position' : 'positions';
  return {
    scope,
    lineup: result.lineup,
    filledCount: result.filledCount,
    incompleteMessage: incompleteMessage(result, scope.kind === 'through'),
    noticeMessage: notice || null,
    undoMessage: `Auto-filled ${result.filledCount} ${noun} (${scopeLabel(scope)})`,
  };
}

export function incompleteMessage(result: AutoFillResult, multiInning: boolean): string | null {
  const slots = result.unfilledSlots;
  if (!slots.length) return null;
  const label = (group: typeof slots) => {
    if (!multiInning) return group.map((s) => s.position).join(', ');
    const byPos = new Map<string, number[]>();
    for (const s of group) byPos.set(s.position, [...(byPos.get(s.position) ?? []), s.inningIndex + 1]);
    return [...byPos.entries()]
      .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))
      .map(([pos, innings]) => {
        const nums = innings.sort((a, b) => a - b).join(', ');
        return `${pos} (${innings.length === 1 ? 'Inning' : 'Innings'} ${nums})`;
      })
      .join(', ');
  };
  const parts: string[] = [];
  const of = (reason: string) => slots.filter((s) => s.reason === reason);
  if (of('rosterTooSmall').length) {
    parts.push(`${label(of('rosterTooSmall'))} could not be filled. Not enough active players to cover every field position. Mark additional players as active in the batting order, or assign these slots manually.`);
  }
  if (of('pitcherReentry').length) {
    parts.push(`${label(of('pitcherReentry'))} could not be filled. All eligible pitchers have already left the mound this game and cannot re-enter. Assign pitcher manually.`);
  }
  if (of('pitchCapacityLimited').length) {
    parts.push(`${label(of('pitchCapacityLimited'))} could not be filled. Every eligible pitcher either needs rest under your pitch count rules or has reached their estimated pitch limit for this game. Assign pitcher manually or check pitch counts on the Pitching tab.`);
  }
  if (of('neverPreferences').length) {
    parts.push(`${label(of('neverPreferences'))} could not be filled. All remaining players have those positions set to Never in their preferences. Update preferences on the Roster tab, or assign manually.`);
  }
  return parts.join('\n\n') || null;
}

export function constraintNoticeMessage(result: AutoFillResult, players: Player[]): string | null {
  const { constraintOverrides: overrides, constraintRejections: rejections } = result;
  if (!overrides.length && !rejections.length) return null;
  const name = (id: string) => {
    const p = players.find((x) => x.id === id);
    return p ? shortName(p) : 'A player';
  };
  const targetLabel = (t: ConstraintTarget) =>
    t.kind === 'position' ? t.position : t.kind === 'infield' ? 'an infield position'
    : t.kind === 'outfield' ? 'an outfield position' : 'Bench';
  const inningList = (innings: number[]) => {
    const n = [...innings].sort((a, b) => a - b).map((i) => String(i + 1));
    if (n.length === 1) return `inning ${n[0]}`;
    if (n.length === 2) return `innings ${n[0]} and ${n[1]}`;
    return `innings ${n.slice(0, -1).join(', ')}, and ${n[n.length - 1]}`;
  };
  const byPlayer = (reason: string) => {
    const groups = new Map<string, number[]>();
    for (const o of overrides.filter((x) => x.reason === reason)) {
      groups.set(o.playerID, [...(groups.get(o.playerID) ?? []), o.inningIndex]);
    }
    return [...groups.entries()].sort(([a], [b]) => (a < b ? -1 : 1));
  };

  const lines: string[] = [];
  for (const [id, inns] of byPlayer('pitcherSoftCapBypassed')) {
    lines.push(`${name(id)} also pitched ${inningList(inns)} — past the usual 2-inning guideline.`);
  }
  for (const [id, inns] of byPlayer('pitcherSoftCapBypassedByFallback')) {
    lines.push(`${name(id)} ended up pitching ${inningList(inns)} since no one else was eligible — past the usual 2-inning guideline.`);
  }
  for (const [id, inns] of byPlayer('benchedOutOfTurn')) {
    lines.push(`${name(id)} sat out ${inningList(inns)} ahead of the normal rotation turn.`);
  }
  for (const o of overrides) {
    if (o.reason === 'fairPlayZoneSkipped.infield') lines.push(`${name(o.playerID)} still hasn't played infield this game.`);
    if (o.reason === 'fairPlayZoneSkipped.outfield') lines.push(`${name(o.playerID)} still hasn't played outfield this game.`);
  }
  for (const r of rejections) {
    lines.push(`Couldn't put ${name(r.playerID)} at ${targetLabel(r.target)} in ${inningList([r.inningIndex])} — ${r.reason}`);
  }
  if (!lines.length) return null;
  return lines.length > 1 ? lines.map((l) => `• ${l}`).join('\n') : lines[0];
}
