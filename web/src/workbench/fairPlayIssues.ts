// The live fair-play panel: the team's own rules (fairPlay.ts, the iOS port)
// plus open spots, Never positions and pitchers who must rest, turned into the
// issue cards from the design handoff. Red issues block a clean lineup; orange
// ones are worth a look. Each card knows which inning to jump to.

import {
  activePlayers, backToBackBenchInnings, fairPlayFindings, openPositions,
} from '@/core/fairPlay';
import { shortName } from '@/core/lineupOps';
import {
  isInfield, isNonFielding, isOutfield, type FairPlayConfig, type FieldPosition, type GameLog, type Lineup, type PitchingConfig, type Player,
} from '@/core/model';
import { blocksAssignment, status as pitchStatus } from '@/core/pitching';

export type Severity = 'red' | 'orange';

export interface FairPlayIssue {
  key: string;
  title: string;
  detail: string;
  severity: Severity;
  /** 0-based inning to open in the Field view when the chip is clicked. */
  inning: number;
  /** Back-to-back bench only: who, and the 0-based innings involved. */
  pid?: string;
  cells?: number[];
}

export interface IssueInput {
  lineup: Lineup;
  players: Player[];
  config: FairPlayConfig;
  pitchingConfig: PitchingConfig;
  gameLogs: GameLog[];
}

const names = (ps: Player[]) => ps.map(shortName).join(', ');
const fieldingInnings = (l: Lineup, p: Player) =>
  l.innings.filter((inn) => { const x = inn.assignments[p.id]; return x !== undefined && !isNonFielding(x); }).length;
const firstInning = (l: Lineup, p: Player, pred: (pos: FieldPosition) => boolean) =>
  Math.max(0, l.innings.findIndex((inn) => { const x = inn.assignments[p.id]; return x !== undefined && pred(x); }));

export function fairPlayIssues({ lineup, players, config, pitchingConfig, gameLogs }: IssueInput): FairPlayIssue[] {
  const out: FairPlayIssue[] = [];
  const active = activePlayers(lineup, players);
  if (active.length === 0) return out;

  // 1. Open field spots.
  const open = lineup.innings.flatMap((_, i) => openPositions(lineup, i, players, config).map((pos) => ({ pos, i })));
  if (open.length) {
    const innings = [...new Set(open.map((o) => o.i + 1))];
    out.push({
      key: 'open', title: 'Positions not filled', severity: 'red', inning: open[0].i,
      detail: open.length <= 2
        ? open.map((o) => `${o.pos} in inning ${o.i + 1}`).join(', ')
        : `${open.length} open in innings ${innings.join(', ')}`,
    });
  }

  // 2. Pitchers the pitch-count rules say must rest (or can't be checked).
  if (pitchingConfig.rulesEnabled) {
    for (const p of active) {
      if (!lineup.innings.some((inn) => inn.assignments[p.id] === 'P')) continue;
      const s = pitchStatus(p, gameLogs, pitchingConfig, lineup.gameDate);
      if (!blocksAssignment(s)) continue;
      out.push({
        key: `rest-${p.id}`, severity: 'red', inning: firstInning(lineup, p, (x) => x === 'P'),
        title: s.kind === 'mustRest' ? 'Pitcher needs rest' : 'Pitcher has no league age',
        detail: s.kind === 'mustRest'
          ? `${shortName(p)} can pitch again ${s.until.toLocaleDateString('en-US', { weekday: 'short', month: 'numeric', day: 'numeric' })}`
          : `${shortName(p)}: add a league age so pitch counts can be checked`,
      });
    }
  }

  const f = fairPlayFindings(lineup, players, config);

  // 3. Back-to-back bench (the team's rule).
  for (const p of f.backToBackBench) {
    const pairs = backToBackBenchInnings(lineup, p);
    const [a, b] = pairs[0];
    out.push({
      key: `b2b-${p.id}`, title: 'Back-to-back bench', detail: `${shortName(p)}, innings ${a}-${b}`, severity: 'red', inning: a - 1,
      pid: p.id, cells: [...new Set(pairs.flat().map((n) => n - 1))],
    });
  }

  // 4. Infield / outfield minimums, once a player has enough innings to judge.
  const judged = (ps: Player[]) => ps.filter((p) => fieldingInnings(lineup, p) >= 3);
  const noIn = judged(f.withoutInfield);
  const noOut = judged(f.withoutOutfield);
  if (noIn.length) out.push({ key: 'no-in', title: 'Missing infield inning', detail: names(noIn), severity: 'orange', inning: firstInning(lineup, noIn[0], (x) => isOutfield(x)) });
  if (noOut.length) out.push({ key: 'no-out', title: 'Missing outfield inning', detail: names(noOut), severity: 'orange', inning: firstInning(lineup, noOut[0], (x) => isInfield(x)) });

  // 5. Fielding minimum, only once every inning is set for everyone.
  const complete = lineup.innings.every((inn) => active.every((p) => p.id in inn.assignments));
  if (complete && f.underFieldingMinimum.length) {
    out.push({
      key: 'min', title: `Under ${f.minimumFieldingInnings} fielding innings`, detail: names(f.underFieldingMinimum),
      severity: 'orange', inning: 0,
    });
  }

  // 6. League battery rules.
  if (f.catcherThenPitcher.length) out.push({ key: 'c2p', title: 'Caught, then pitched', detail: names(f.catcherThenPitcher), severity: 'orange', inning: firstInning(lineup, f.catcherThenPitcher[0], (x) => x === 'P') });
  if (f.pitcherThenCatcher.length) out.push({ key: 'p2c', title: 'Pitched, then caught', detail: names(f.pitcherThenCatcher), severity: 'orange', inning: firstInning(lineup, f.pitcherThenCatcher[0], (x) => x === 'C') });

  // 7. Someone playing a position they're marked Never at.
  for (const p of active) {
    lineup.innings.forEach((inn, i) => {
      const x = inn.assignments[p.id];
      if (x && p.positionPreferences[x] === 'Never') {
        out.push({ key: `never-${p.id}-${i}`, title: 'Never position', detail: `${shortName(p)} at ${x}, inning ${i + 1}`, severity: 'orange', inning: i });
      }
    });
  }
  return out;
}

/** Infield and outfield innings per active player, for the playing-time bars. */
export function playingTime(lineup: Lineup, player: Player) {
  let infield = 0;
  let outfield = 0;
  for (const inn of lineup.innings) {
    const x = inn.assignments[player.id];
    if (x && isInfield(x)) infield++;
    else if (x && isOutfield(x)) outfield++;
  }
  return { infield, outfield };
}
