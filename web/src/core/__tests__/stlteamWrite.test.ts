import { readFileSync } from 'node:fs';
import { join } from 'node:path';

import { emptyLineup } from '../model';
import { parseStlTeam } from '../stlteam';
import { stlTeamFilename, swiftDate, writeStlTeam } from '../stlteamWrite';

const sample = readFileSync(join(__dirname, '../../../fixtures/sample-fall-team.stlteam'), 'utf8');

describe('writeStlTeam', () => {
  const { team } = parseStlTeam(sample);
  const text = writeStlTeam(team, '1.0-web', new Date('2026-11-06T18:04:05.123Z'));
  const back = parseStlTeam(text);

  it('reads back as the same team, minus the open lineup (as TeamExporter does)', () => {
    const expected = { ...team, lineup: emptyLineup(team.gameInningCount) };
    // The open lineup's gameDate is "now" on both sides; compare everything else.
    expect({ ...back.team, lineup: { ...back.team.lineup, gameDate: 0 } })
      .toEqual({ ...expected, lineup: { ...expected.lineup, gameDate: 0 } });
    expect(back.appVersion).toBe('1.0-web');
    expect(back.exportedAt.toISOString()).toBe('2026-11-06T18:04:05.000Z');
  });

  it('writes Swift shapes: flat dictionaries, whole-second dates, sorted keys', () => {
    const o = JSON.parse(text);
    expect(o.exportedAt).toBe('2026-11-06T18:04:05Z');
    expect(Array.isArray(o.team.gameLineups)).toBe(true);
    expect(o.team.gameLineups).toHaveLength(Object.keys(team.gameLineups).length * 2);
    expect(Array.isArray(o.team.players[0].positionPreferences)).toBe(true);
    expect(Array.isArray(o.team.pitchingConfig.ageLimits)).toBe(true);
    expect(Object.keys(o.team)).toEqual([...Object.keys(o.team)].sort());
    expect(text).not.toMatch(/\d\.\d{3}Z"/);
  });

  it('matches the iOS file key for key on the parts both sides carry', () => {
    const ios = JSON.parse(sample).team;
    const web = JSON.parse(text).team;
    expect(Object.keys(web.players[0]).sort()).toEqual(
      Object.keys(ios.players[0]).filter((k) => k in web.players[0]).sort(),
    );
    expect(web.gameLogs[0]).toEqual(ios.gameLogs[0]);
    expect(web.scheduledGames).toEqual(ios.scheduledGames);
  });
});

describe('stlTeamFilename', () => {
  it('mirrors TeamExporter.filename', () => {
    const d = new Date(2026, 10, 6);
    expect(stlTeamFilename('Mudcats 10U!', d)).toBe('Mudcats_10U_2026-11-06.stlteam');
    expect(stlTeamFilename('  ', d)).toBe('Team_2026-11-06.stlteam');
  });
  it('swiftDate drops milliseconds', () => {
    expect(swiftDate(new Date('2026-01-02T03:04:05.678Z'))).toBe('2026-01-02T03:04:05Z');
  });
});
