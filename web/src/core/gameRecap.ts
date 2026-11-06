// "How did we do?" — one archived game as facts a coach repeats to a parent.
// Port of GameRecap.swift (GameRecap + GameRecapBuilder). Everything here is
// counted from the game log, never generated.

import { fairPlayFindings, type FairPlayFindings } from './fairPlay';
import { emptyLineup, type FairPlayConfig, type GameLog, type Lineup, type Player } from './model';

export interface RecapIssue {
  names: string[];
  /** Agrees with a singular or plural subject: "never played the infield". */
  predicate: string;
}

export interface RecapPitchingLine {
  playerID: string;
  name: string;
  innings: number;
  /** undefined when no count was recorded: "not recorded", never zero. */
  pitches?: number;
}

export interface GameRecap {
  opponent: string;
  gameDate: Date;
  inningsPlayed: number;
  /** Short names ("Jake R."), in batting order. */
  battingOrder: string[];
  /** In the order they first took the mound. */
  pitching: RecapPitchingLine[];
  fairPlayIssues: RecapIssue[];
  /** The game was too short to judge against the fielding minimum. */
  fieldingMinimumSkipped: boolean;
}

const innings = (n: number) => (n === 1 ? '1 inning' : `${n} innings`);
const pitches = (n: number) => (n === 1 ? '1 pitch' : `${n} pitches`);
const displayName = (p: Pick<Player, 'firstName' | 'lastName'>) => `${p.firstName} ${p.lastName}`;
const shortName = (p: Pick<Player, 'firstName' | 'lastName'>) => {
  const initial = p.lastName.charAt(0);
  return initial ? `${p.firstName} ${initial}.` : p.firstName;
};

/** "Leo and Cam", "Leo, Cam, and Eli": names mid-sentence, unpunctuated. */
export function listOf(names: string[]): string {
  if (names.length <= 1) return names[0] ?? '';
  if (names.length === 2) return `${names[0]} and ${names[1]}`;
  return `${names.slice(0, -1).join(', ')}, and ${names[names.length - 1]}`;
}

/** Independent clauses: two keep the comma ("Jake pitched 2 innings, and Nate pitched 2."). */
export function sentenceJoining(clauses: string[]): string {
  if (clauses.length === 0) return '';
  if (clauses.length === 1) return `${clauses[0]}.`;
  return `${clauses.slice(0, -1).join(', ')}, and ${clauses[clauses.length - 1]}.`;
}

/** RecapIssue.sentence(namingAtMost:): names `limit` players and counts the rest. */
export function issueSentence(issue: RecapIssue, limit?: number): string {
  if (limit === undefined || limit <= 0 || issue.names.length <= limit) return `${listOf(issue.names)} ${issue.predicate}.`;
  const rest = issue.names.length - limit;
  return `${listOf([...issue.names.slice(0, limit), rest === 1 ? '1 other' : `${rest} others`])} ${issue.predicate}.`;
}

const sameDay = (a: Date, b: Date) =>
  a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();

/** "today" / "yesterday" / "Tuesday" (within a week) / "Tuesday, Jul 28". */
export function datePhrase(date: Date, now = new Date()): string {
  if (sameDay(date, now)) return 'today';
  const y = new Date(now); y.setDate(y.getDate() - 1);
  if (sameDay(date, y)) return 'yesterday';
  const start = (d: Date) => new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
  const daysAgo = Math.round((start(now) - start(date)) / 86_400_000);
  const weekday = date.toLocaleDateString('en-US', { weekday: 'long' });
  return daysAgo >= 0 && daysAgo <= 6 ? weekday : `${weekday}, ${date.toLocaleDateString('en-US', { month: 'short', day: 'numeric' })}`;
}

const dateVerbPhrase = (date: Date, now = new Date()) => {
  const p = datePhrase(date, now);
  return p === 'today' || p === 'yesterday' ? p : `on ${p}`;
};

export function pitchingSentence(r: GameRecap): string | undefined {
  if (!r.pitching.length) return undefined;
  return sentenceJoining(r.pitching.map((l) => (l.pitches !== undefined
    ? `${l.name} pitched ${innings(l.innings)} on ${pitches(l.pitches)}`
    : `${l.name} pitched ${innings(l.innings)}`)));
}

/** How many names a spoken (or texted) issue lists before it starts counting. */
export const SPOKEN_NAME_LIMIT = 3;

/** GameRecap.spokenSummary: the identifying facts first, the fair-play verdict last. */
export function recapSummary(r: GameRecap, now = new Date()): string {
  const parts = [
    `${r.opponent ? `Your game against ${r.opponent}` : 'Your game'} ${dateVerbPhrase(r.gameDate, now)} went ${innings(r.inningsPlayed)}.`,
  ];
  const pitching = pitchingSentence(r);
  if (pitching) parts.push(pitching);
  if (r.fieldingMinimumSkipped) parts.push('It was too short to judge against your fielding-innings minimum.');
  if (!r.fairPlayIssues.length) {
    parts.push(r.fieldingMinimumSkipped ? 'Nothing else was flagged.' : 'Everyone met your fair play rules.');
  } else {
    parts.push(r.fairPlayIssues.map((i) => issueSentence(i, SPOKEN_NAME_LIMIT)).join(' '));
  }
  return parts.join(' ');
}

/** GameRecapBuilder.issueSentences: costliest to a kid first. */
export function recapIssues(f: FairPlayFindings): RecapIssue[] {
  const out: RecapIssue[] = [];
  const add = (players: Player[], predicate: string) => {
    if (players.length) out.push({ names: players.map(displayName), predicate });
  };
  const m = f.minimumFieldingInnings;
  add(f.underFieldingMinimum, `played fewer than ${m} fielding ${m === 1 ? 'inning' : 'innings'}`);
  add(f.withoutInfield, 'never played the infield');
  add(f.withoutOutfield, 'never played the outfield');
  add(f.backToBackBench, 'sat two innings in a row');
  add(f.catcherThenPitcher, 'caught and then pitched');
  add(f.pitcherThenCatcher, 'pitched and then caught');
  return out;
}

/**
 * GameRecapBuilder.build. Players come from the game's own snapshot, so a
 * player since removed from the roster still shows. Absences are not exempted,
 * matching the live fair-play rail. Judged against the team's current rules, as on iOS.
 */
export function buildRecap(log: GameLog, config: FairPlayConfig): GameRecap {
  const players: Player[] = log.playerSnapshot.map((s) => ({ ...s, positionPreferences: {} }));
  const byId = new Map(players.map((p) => [p.id, p]));
  const played = log.innings.slice(0, log.inningsPlayed);
  const lineup: Lineup = {
    ...emptyLineup(played.length), gameDate: log.gameDate, opponent: log.opponent,
    battingOrder: log.battingOrder, innings: played,
  };

  const fieldingMinimumSkipped = config.minimumFieldingInnings > 0 && log.inningsPlayed < config.minimumFieldingInnings;
  const effective = fieldingMinimumSkipped ? { ...config, minimumFieldingInnings: 0 } : config;

  const count = new Map<string, number>();
  const first = new Map<string, number>();
  played.forEach((inn, i) => {
    for (const [id, pos] of Object.entries(inn.assignments)) {
      if (pos !== 'P') continue;
      count.set(id, (count.get(id) ?? 0) + 1);
      if (!first.has(id)) first.set(id, i);
    }
  });
  const pitching = [...count.keys()]
    .sort((a, b) => first.get(a)! - first.get(b)! || (a < b ? -1 : a > b ? 1 : 0))
    .map((id): RecapPitchingLine => {
      const p = byId.get(id);
      const n = log.pitchCounts[id];
      return { playerID: id, name: p ? displayName(p) : 'A player', innings: count.get(id)!, ...(n !== undefined ? { pitches: n } : {}) };
    });

  return {
    opponent: log.opponent,
    gameDate: log.gameDate,
    inningsPlayed: log.inningsPlayed,
    battingOrder: log.battingOrder.flatMap((id) => { const p = byId.get(id); return p ? [shortName(p)] : []; }),
    pitching,
    fairPlayIssues: recapIssues(fairPlayFindings(lineup, players, effective)),
    fieldingMinimumSkipped,
  };
}
