// Made-up team for the development-only /dev-grid preview. Fake names only.
// It is the design handoff's sample team and lineup, so the preview can be
// checked against the mockup screenshots.

import { applyLittleLeaguePreset } from '@/core/pitching';
import {
  defaultFairPlayConfig, defaultPitchingConfig, emptyLineup, type FieldPosition, type GameLog, type Player,
  type PositionPreferenceTier,
} from '@/core/model';
import type { TeamData } from '@/data/teamStore';

const TIER: Record<string, PositionPreferenceTier> = { s: 'Strength', c: 'Capable', e: 'Emergency', n: 'Never' };

const ROSTER: [string, string, string, string, number, Record<string, string>][] = [
  ['jr', 'Jake', 'Rivera', '4', 11, { P: 's', '2B': 'c', '1B': 'c', C: 'n', LF: 'e' }],
  ['cw', 'Connor', 'Walsh', '7', 11, { '3B': 's', SS: 's', CF: 'c', '2B': 'c' }],
  ['tn', 'Tyler', 'Nguyen', '11', 10, { C: 's', '1B': 'c', RF: 'n', P: 'e' }],
  ['mb', 'Marcus', 'Bell', '2', 10, { LF: 's', CF: 's', RF: 'c', C: 'n', P: 'n' }],
  ['ds', 'Drew', 'Santos', '9', 10, { '1B': 's', '3B': 'c', P: 'c' }],
  ['ep', 'Eli', 'Park', '14', 9, { '2B': 's', '3B': 'c', SS: 'c' }],
  ['of', 'Owen', 'Fischer', '5', 11, { CF: 's', RF: 'c', LF: 'c' }],
  ['nc', 'Nate', 'Coleman', '18', 10, { P: 's', SS: 'c', '1B': 'c' }],
  ['lh', 'Leo', 'Huang', '3', 9, { '3B': 's', '2B': 'c', LF: 'c' }],
  ['ct', 'Cam', 'Torres', '21', 10, { RF: 's', CF: 'c', '1B': 'c' }],
];

const GRID: Record<string, string[]> = {
  jr: ['P', '1B', '1B', 'CF', 'SS', '3B', 'SS'], cw: ['RF', 'SS', 'SS', 'C', 'RF', 'SS', 'RF'],
  tn: ['C', 'C', 'LF', 'Bench', 'C', 'C', 'C'], mb: ['CF', '3B', 'Bench', 'LF', 'LF', 'CF', 'LF'],
  ds: ['2B', 'LF', 'C', '1B', '1B', '1B', '1B'], ep: ['Bench', '2B', 'CF', '2B', '2B', '2B', '2B'],
  of: ['LF', 'P', 'P', 'RF', 'CF', 'Bench', 'CF'], nc: ['SS', 'Bench', 'RF', 'P', 'P', 'P', 'P'],
  lh: ['3B', 'CF', '3B', '3B', '3B', 'LF', '3B'], ct: ['1B', 'RF', '2B', 'SS', 'Bench', 'RF', 'Bench'],
};

const id = (key: string) => `00000000-0000-4000-8000-${key.split('').map((c) => c.charCodeAt(0).toString(16)).join('').padStart(12, '0')}`;

export function demoTeam(): TeamData {
  const players: Player[] = ROSTER.map(([key, first, last, num, age, prefs]) => ({
    id: id(key), firstName: first, lastName: last, number: num, leagueAge: age,
    positionPreferences: Object.fromEntries(Object.entries(prefs).map(([pos, t]) => [pos, TIER[t]])),
  }));
  const gameDate = new Date();
  gameDate.setHours(17, 30, 0, 0);
  const lineup = { ...emptyLineup(7), id: 'DEMO-LINEUP', gameDate, opponent: '', battingOrder: players.map((p) => p.id) };
  lineup.innings.forEach((inn, i) => {
    for (const [key, row] of Object.entries(GRID)) inn.assignments[id(key)] = row[i] as FieldPosition;
  });

  // Three earlier games (rotated copies of the same grid) so History has something to show.
  const daysAgo = (n: number) => { const d = new Date(gameDate); d.setDate(d.getDate() - n); return d; };
  const gameLogs: GameLog[] = [['Hornets', 8, 6], ['Wildcats', 15, 7], ['Riverdogs', 22, 6]].map(([opp, ago, n], g) => ({
    id: `DEMO-LOG-${g}`, gameDate: daysAgo(ago as number), opponent: opp as string, inningsPlayed: n as number,
    battingOrder: players.map((p) => p.id),
    innings: lineup.innings.slice(0, n as number).map((_, i) => ({
      assignments: Object.fromEntries(Object.entries(GRID).map(([key, row]) => [id(key), row[(i + g + 1) % 7] as FieldPosition])),
    })),
    playerSnapshot: players.map(({ id: pid, firstName, lastName, number }) => ({ id: pid, firstName, lastName, number })), archivedAt: daysAgo(ago as number), archivedBy: 'Coach', notes: '',
    pitchCounts: g === 0 ? { [id('of')]: 35 } : {},
  }));

  return {
    team: {
      id: 'DEMO', name: 'Test Team', colorHex: 'FF9500', coachName: 'Coach',
      gameInningCount: 7, fairPlayConfig: { ...defaultFairPlayConfig(), minimumFieldingInnings: 3 },
      pitchingConfig: applyLittleLeaguePreset({ ...defaultPitchingConfig(), rulesEnabled: true }),
    },
    players,
    lineup,
    gameLogs,
  };
}
