// Auto-Fill instruction parser: a port of the model-free half of
// AutoFillNLConstraintService.swift (parseDeterministically, the bench-pairing
// detector) and AutoFillCoordinator.shouldTrustDeterministic.
//
// The web has no on-device model, so this is the whole parser here. A prompt
// the iOS app would hand to Apple Intelligence (hasUnresolvedInstruction) is
// used best-effort on the web, with a notice to the coach (see the Auto-Fill
// coordinator).
//
// Precision over recall, as on iOS: an ambiguous clause is reported unresolved
// rather than guessed. Matching mirrors Swift exactly, including case-sensitive
// " then " / ", " / " and " splitting and substring checks for intent words.
//
// Two deliberate, documented differences:
//  * Swift iterates a Dictionary for number words, in random order. That only
//    matters when one clause holds two competing phrases ("two inning ... five
//    inning"); here the order is fixed (one..nine, then first..ninth).
//  * Word boundaries: NSRegularExpression's \b is Unicode-aware, JS's is ASCII.
//    Identical for ASCII names; a name like "José" could differ.
//
// Parity: fixtures/parity/autofill-parse.json (exact).

import type { Player } from './model';
import type { ConstraintTarget, PlayerConstraint } from './autofillTypes';

export interface DeterministicParse {
  constraints: PlayerConstraint[];
  /** The text clearly holds a player instruction the parser couldn't map. */
  hasUnresolvedInstruction: boolean;
}

const pos = (position: 'P' | 'C' | '1B' | '2B' | 'SS' | '3B' | 'LF' | 'LCF' | 'CF' | 'RCF' | 'RF'): ConstraintTarget =>
  ({ kind: 'position', position });

/** Longest phrases first so "left center field" beats "center field". */
const TARGET_PHRASES: [string, ConstraintTarget][] = [
  ['left center field', pos('LCF')], ['right center field', pos('RCF')],
  ['center field', pos('CF')], ['left field', pos('LF')], ['right field', pos('RF')],
  ['first base', pos('1B')], ['second base', pos('2B')], ['third base', pos('3B')],
  ['shortstop', pos('SS')], ['short stop', pos('SS')], ['catcher', pos('C')], ['pitcher', pos('P')],
  ['infield', { kind: 'infield' }], ['outfield', { kind: 'outfield' }], ['bench', { kind: 'bench' }],
  ['1b', pos('1B')], ['2b', pos('2B')], ['3b', pos('3B')], ['ss', pos('SS')],
  ['lcf', pos('LCF')], ['rcf', pos('RCF')], ['lf', pos('LF')], ['cf', pos('CF')], ['rf', pos('RF')],
  ['short', pos('SS')],
];

/** Verbs that imply a position, checked only when no explicit phrase matched. */
const VERB_TARGETS: [string, ConstraintTarget][] = [
  ['pitches', pos('P')], ['pitching', pos('P')], ['pitch', pos('P')], ['on the mound', pos('P')],
  ['catches', pos('C')], ['catching', pos('C')], ['catch', pos('C')], ['behind the plate', pos('C')],
];

const NUMBER_WORDS: [string, number][] = [
  ['one', 1], ['two', 2], ['three', 3], ['four', 4], ['five', 5],
  ['six', 6], ['seven', 7], ['eight', 8], ['nine', 9],
  ['first', 1], ['second', 2], ['third', 3], ['fourth', 4], ['fifth', 5],
  ['sixth', 6], ['seventh', 7], ['eighth', 8], ['ninth', 9],
];

const escapeRegex = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

/** Index of `phrase` as whole words in `text` (case-insensitive), or -1. */
function wordIndex(phrase: string, text: string): number {
  const m = new RegExp(`\\b${escapeRegex(phrase)}\\b`, 'i').exec(text);
  return m ? m.index : -1;
}

/** Capture groups [full, g1, ...] of the first case-insensitive match, or null. */
function firstMatch(pattern: string, text: string): string[] | null {
  const m = new RegExp(pattern, 'i').exec(text);
  return m ? Array.from(m, (g) => g ?? '') : null;
}

/** Swift String.split(whereSeparator: \.isNewline), empty pieces dropped. */
const splitLines = (s: string) => s.split(/\r\n|[\n\r\u000B\u000C\u0085\u2028\u2029]/).filter((x) => x.length > 0);

const sameTarget = (a: ConstraintTarget, b: ConstraintTarget) =>
  a.kind === b.kind && (a.kind !== 'position' || a.position === (b as { position: string }).position);

export class AutoFillParser {
  constructor(private readonly activePlayers: Player[], private readonly inningCount: number) {}

  parseDeterministically(prompt: string): DeterministicParse {
    const firstNames = this.activePlayers.map((p) => p.firstName.toLowerCase());
    const hasDuplicateFirstNames = new Set(firstNames).size !== firstNames.length;

    const constraints: PlayerConstraint[] = [];
    let unresolved = false;

    for (const clause of this.splitClauses(prompt)) {
      const lower = clause.toLowerCase();
      const target = this.firstTarget(lower);
      if (!target) {
        if (this.playersMentioned(lower).length) unresolved = true;
        continue;
      }
      if (hasDuplicateFirstNames && this.playersMentioned(lower).length) {
        unresolved = true;
        continue;
      }
      const players = this.clausePlayers(lower);
      if (players.length === 0) {
        unresolved = true;
        continue;
      }
      const intent = this.clauseIntent(lower);
      // A bare assign means inning 1 only; a bare avoid/prioritize means all game.
      const defaultRange: [number, number] = intent === 'assign' ? [0, 0] : [0, this.inningCount - 1];
      const inningRange = this.parseRange(lower) ?? defaultRange;
      for (const p of players) constraints.push({ playerID: p.id, target, inningRange, intent });
    }

    const mentioned = this.playersMentioned(prompt.toLowerCase());
    if (!hasDuplicateFirstNames) {
      const covered = new Set(constraints.map((c) => c.playerID));
      if (mentioned.some((p) => !covered.has(p.id))) unresolved = true;
    } else if (mentioned.length) {
      unresolved = true;
    }

    return { constraints: this.withImplicitPitcherAvoids(constraints), hasUnresolvedInstruction: unresolved };
  }

  /** A pitcher assign implies "avoid pitcher" for the rest of the game (re-entry rule). */
  private withImplicitPitcherAvoids(resolved: PlayerConstraint[]): PlayerConstraint[] {
    const out = [...resolved];
    for (const a of resolved) {
      if (a.intent !== 'assign' || !sameTarget(a.target, pos('P'))) continue;
      for (const inningRange of this.complementRanges(a.inningRange)) {
        out.push({ playerID: a.playerID, target: pos('P'), inningRange, intent: 'avoid' });
      }
    }
    return out;
  }

  private complementRanges([lo, hi]: [number, number]): [number, number][] {
    if (this.inningCount <= 0) return [];
    const out: [number, number][] = [];
    if (lo > 0) out.push([0, lo - 1]);
    if (hi < this.inningCount - 1) out.push([hi + 1, this.inningCount - 1]);
    return out;
  }

  // MARK: Clause splitting

  /** Newlines, ";", "then", "after that" always split; ", " and " and " only when both sides name a target. */
  private splitClauses(prompt: string): string[] {
    const strong = prompt
      .replaceAll(' and then ', '\n')
      .replaceAll(' then ', '\n')
      .replaceAll(' after that ', '\n')
      .replaceAll(';', '\n');
    return splitLines(strong)
      .map((s) => s.replace(/^[ \t]+|[ \t]+$/g, ''))
      .filter((s) => s.length > 0)
      .flatMap((s) => this.conditionallySplit(s));
  }

  private conditionallySplit(clause: string): string[] {
    for (const sep of [', ', ' and ']) {
      let from = 0;
      for (;;) {
        const at = clause.indexOf(sep, from);
        if (at < 0) break;
        const left = clause.slice(0, at);
        const right = clause.slice(at + sep.length);
        if (this.firstTarget(left.toLowerCase()) && this.firstTarget(right.toLowerCase())) {
          return [...this.conditionallySplit(left), ...this.conditionallySplit(right)];
        }
        from = at + sep.length;
      }
    }
    return [clause];
  }

  // MARK: Clause fields

  private firstTarget(lower: string): ConstraintTarget | null {
    const earliest = (table: [string, ConstraintTarget][]) => {
      let best: { index: number; target: ConstraintTarget } | null = null;
      for (const [phrase, target] of table) {
        const i = wordIndex(phrase, lower);
        if (i >= 0 && (best === null || i < best.index)) best = { index: i, target };
      }
      return best?.target ?? null;
    };
    return earliest(TARGET_PHRASES) ?? earliest(VERB_TARGETS);
  }

  private clausePlayers(lower: string): Player[] {
    if (['everyone', 'everybody', 'all players', 'whole team', 'the team'].some((w) => lower.includes(w))) {
      return this.activePlayers;
    }
    return this.playersMentioned(lower);
  }

  private playersMentioned(lower: string): Player[] {
    const seen = new Set<string>();
    const out: Player[] = [];
    for (const p of this.activePlayers) {
      const name = p.firstName.toLowerCase();
      if (!name || seen.has(p.id)) continue;
      if (wordIndex(name, lower) >= 0) {
        seen.add(p.id);
        out.push(p);
      }
    }
    return out;
  }

  /** "keep X at short" is an assign; the avoid signal is off/never/avoid/don't/not/can't. */
  private clauseIntent(lower: string): PlayerConstraint['intent'] {
    if (['prefer', 'if possible', 'when possible', 'ideally', 'try to'].some((w) => lower.includes(w))) {
      return 'prioritize';
    }
    const avoid = [' off ', 'off the', "don't", 'do not', 'dont', 'never', 'avoid', 'not at', 'not in',
      "can't", 'cannot', 'stay off', 'away from'];
    return avoid.some((w) => lower.includes(w)) ? 'avoid' : 'assign';
  }

  // MARK: Inning ranges

  /** Zero-based, inclusive, clamped; null when no inning is stated. */
  private parseRange(lower: string): [number, number] | null {
    if (this.inningCount <= 0) return null;
    const last = this.inningCount - 1;
    const clamp = (oneBased: number) => Math.max(0, Math.min(oneBased - 1, last));

    if (['all game', 'whole game', 'entire game', 'every inning'].some((w) => lower.includes(w))) return [0, last];

    let m = firstMatch(String.raw`innings?\s+(\d+)\s*(?:-|to|through|thru|and)\s*(\d+)`, lower);
    if (m) {
      const a = Number(m[1]);
      const b = Number(m[2]);
      return [clamp(Math.min(a, b)), clamp(Math.max(a, b))];
    }
    let n = this.countAfter(['first', 'the first'], lower);
    if (n !== null) return [0, clamp(n)];
    n = this.countAfter(['last', 'the last'], lower);
    if (n !== null) return [Math.max(0, this.inningCount - n), last];

    if (['start', 'starts', 'starting', 'begins', 'begin'].some((w) => wordIndex(w, lower) >= 0)) return [0, 0];

    m = firstMatch(String.raw`inning\s+(\d+)`, lower);
    if (m) return [clamp(Number(m[1])), clamp(Number(m[1]))];
    m = firstMatch(String.raw`(\d+)(?:st|nd|rd|th)\s+inning`, lower);
    if (m) return [clamp(Number(m[1])), clamp(Number(m[1]))];
    for (const [word, k] of NUMBER_WORDS) {
      if (wordIndex(`${word} inning`, lower) >= 0) return [clamp(k), clamp(k)];
    }
    return null;
  }

  /** "first N innings" -> N (digits or a number word); bare "first inning" -> 1. */
  private countAfter(anchors: string[], lower: string): number | null {
    for (const anchor of anchors) {
      const m = firstMatch(`${anchor}\\s+(\\d+)\\s+innings?`, lower);
      if (m) return Number(m[1]);
      for (const [word, k] of NUMBER_WORDS) {
        if (lower.includes(`${anchor} ${word} innings`)) return k;
      }
      if (lower.includes(`${anchor} inning`) && !lower.includes(`${anchor} innings`)) return 1;
    }
    return null;
  }
}

// MARK: - Pattern rules (no player named)

/**
 * True when the prompt asks that anyone who sits sits two innings in a row.
 * Leans toward recall (a visible confirmation makes a false positive cheap),
 * but needs a bench word, and negations bail out.
 */
export function promptRequestsBenchPairing(prompt: string): boolean {
  const p = prompt.toLowerCase();
  const negations = [
    'no back', 'not back', 'no consecutive', 'not consecutive',
    'no two in a row', 'not two in a row', 'no 2 in a row',
    "don't sit", 'do not sit', 'dont sit', 'never sit', 'avoid sitting',
    "don't have", 'do not have', 'dont have', 'no double', 'without sitting',
    'turn off', 'turned off', 'disable', 'no pairing', 'without pairing',
  ];
  if (negations.some((w) => p.includes(w))) return false;

  const featureName = ['bench pairing', 'bench pair', 'pair the bench', 'pair up the bench', 'pair benches', 'pairing the bench'];
  if (featureName.some((w) => p.includes(w))) return true;

  // Substring checks, as on iOS ("sit" and "bench" are the same concept).
  if (!['sit', 'sits', 'sitting', 'sat', 'bench', 'benched'].some((w) => p.includes(w))) return false;

  const pairing = [
    'consecutive', 'in a row', 'back to back', 'back-to-back', 'two in a row', '2 in a row',
    'twice in a row', 'double up', 'pairing', 'paired', 'in pairs', 'pair up',
  ];
  if (pairing.some((w) => p.includes(w))) return true;
  if (p.includes('again')) return true;
  return p.includes('next') && (p.includes('too') || p.includes('also') || p.includes('as well'));
}

export const detectedPatternRules = (prompt: string) => ({ benchInConsecutivePairs: promptRequestsBenchPairing(prompt) });

export const BENCH_PAIRING_CONFIRMATION =
  "Bench pairing is on: once a player sits, they'll sit the next inning too, as long as enough others are available to field every spot.";

/** Skip the model when the parse found real constraints with nothing unresolved, or the prompt is only a pattern rule. */
export function shouldTrustDeterministic(parse: DeterministicParse, patternDetected: boolean): boolean {
  if (parse.hasUnresolvedInstruction) return false;
  if (parse.constraints.length > 0) return true;
  return patternDetected;
}
