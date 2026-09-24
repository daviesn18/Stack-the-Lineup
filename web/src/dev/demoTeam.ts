// Made-up team for the development-only /dev-grid preview. Fake names only.

import { applyLittleLeaguePreset } from '@/core/pitching';
import { defaultFairPlayConfig, defaultPitchingConfig, emptyLineup, type Player } from '@/core/model';
import type { TeamData } from '@/data/teamStore';

const names = [
  ['Jake', 'Rivera', 11, { P: 'Strength', C: 'Never' }], ['Connor', 'Walsh', 11, { SS: 'Strength', '3B': 'Strength' }],
  ['Tyler', 'Brooks', 10, { C: 'Strength' }], ['Marcus', 'Lee', 10, { '1B': 'Strength', P: 'Capable' }],
  ['Drew', 'Patel', 10, { CF: 'Strength' }], ['Eli', 'Nguyen', 9, { '2B': 'Capable', P: 'Never' }],
  ['Owen', 'Carter', 11, { C: 'Capable', P: 'Capable' }], ['Nate', 'Kim', 10, { LF: 'Capable' }],
  ['Leo', 'Garcia', 9, {}], ['Cam', 'Diaz', 10, { RF: 'Capable' }], ['Sam', 'Ortiz', 11, { P: 'Capable' }],
  ['Max', 'Young', 9, {}],
] as const;

export function demoTeam(): TeamData {
  const players: Player[] = names.map(([first, last, age, prefs], i) => ({
    id: `00000000-0000-4000-8000-${String(900 + i).padStart(12, '0')}`,
    firstName: first, lastName: last, number: String(i + 2), leagueAge: age,
    positionPreferences: { ...prefs } as Player['positionPreferences'],
  }));
  const gameDate = new Date();
  gameDate.setHours(17, 30, 0, 0);
  const yesterday = new Date(gameDate);
  yesterday.setDate(yesterday.getDate() - 1);
  return {
    team: {
      id: 'DEMO', name: 'Demo Tigers', colorHex: 'E4572E', coachName: 'Coach',
      gameInningCount: 6, fairPlayConfig: { ...defaultFairPlayConfig(), minimumFieldingInnings: 3 },
      pitchingConfig: applyLittleLeaguePreset({ ...defaultPitchingConfig(), rulesEnabled: true }),
    },
    players,
    lineup: { ...emptyLineup(6), id: 'DEMO-LINEUP', gameDate, opponent: 'Demo Opponent', battingOrder: players.map((p) => p.id) },
    // Sam threw 60 yesterday: 3 rest days at age 11, so Auto-Fill keeps him off the mound.
    gameLogs: [{
      id: 'DEMO-LOG', gameDate: yesterday, opponent: 'Earlier Opponent', inningsPlayed: 6, battingOrder: [], innings: [],
      playerSnapshot: [], archivedAt: yesterday, archivedBy: 'Coach', notes: '', pitchCounts: { [players[10].id]: 60 },
    }],
  };
}
