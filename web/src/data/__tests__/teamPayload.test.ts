import { readFileSync } from 'node:fs';
import { join } from 'node:path';

import { emptyLineup } from '../../core/model';
import { parseStlTeam } from '../../core/stlteam';
import { toImportPayload } from '../teamPayload';

const sample = parseStlTeam(readFileSync(join(__dirname, '../../../fixtures/sample-fall-team.stlteam'), 'utf8')).team;

describe('lineup inning counts on import', () => {
  it("sizes iOS's blanked open lineup to the team's game length, not Lineup()'s default 7", () => {
    expect(sample.gameInningCount).toBe(6);
    const team = { ...sample, lineup: emptyLineup(7) };
    const [working] = toImportPayload(team).payload.lineups;
    expect(working.inning_count).toBe(6);
  });

  it('sizes an empty saved game lineup to the game length too', () => {
    const [gameId] = Object.keys(sample.gameLineups);
    const team = { ...sample, gameLineups: { [gameId]: { ...emptyLineup(7), opponent: 'X' } } };
    const saved = toImportPayload(team).payload.lineups.find((l) => l.scheduled_game_id === gameId)!;
    expect(saved.inning_count).toBe(6);
  });

  it('keeps the length of a lineup that has positions', () => {
    const [gameId] = Object.keys(sample.gameLineups);
    const built = sample.gameLineups[gameId];
    expect(built.innings.some((i) => Object.keys(i.assignments).length)).toBe(true);
    const seven = { ...built, innings: [...built.innings, { assignments: {} }].slice(0, 7) };
    while (seven.innings.length < 7) seven.innings.push({ assignments: {} });
    const team = { ...sample, gameLineups: { [gameId]: seven } };
    const saved = toImportPayload(team).payload.lineups.find((l) => l.scheduled_game_id === gameId)!;
    expect(saved.inning_count).toBe(7);
  });
});
