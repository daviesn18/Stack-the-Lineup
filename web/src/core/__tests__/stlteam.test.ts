import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

import { parseStlTeam, TeamImportError } from '../stlteam';

const FIXTURES = join(__dirname, '../../../fixtures');
const read = (name: string) => readFileSync(join(FIXTURES, name), 'utf8');

/** Minimal valid envelope; `team` fields are merged over an empty team. */
const envelope = (team: Record<string, unknown>, version = 1) =>
  JSON.stringify({ version, exportedAt: '2026-09-19T22:14:25Z', appVersion: '3.5', team });

const P1 = '3DA40274-DB3F-4C04-AA1D-891C9FEEE62B';
const P2 = 'F4E92011-FCF6-46F3-8953-F6F8C06FDC0C';
const player = (id: string, extra: Record<string, unknown> = {}) => ({
  id, firstName: 'A', lastName: 'B', number: '7', ...extra,
});

describe('committed sample (anonymized real export from iOS 3.4.1)', () => {
  const { team, appVersion } = parseStlTeam(read('sample-fall-team.stlteam'));

  it('reads the envelope and roster', () => {
    expect(appVersion).toBe('3.4.1');
    expect(team.name).toBe('Sample Team');
    expect(team.players).toHaveLength(16);
    expect(team.gameInningCount).toBe(6);
    expect(team.scheduledGames).toHaveLength(8);
  });

  it('decodes flat-array dictionaries (per-game lineups, inning assignments, age limits)', () => {
    const games = Object.keys(team.gameLineups);
    expect(games).toHaveLength(2);
    for (const id of games) expect(team.scheduledGames.map((g) => g.id)).toContain(id);

    const inning = team.gameLineups[games[0]].innings[0].assignments;
    expect(Object.keys(inning).length).toBeGreaterThan(0);
    for (const pid of Object.keys(inning)) expect(team.players.map((p) => p.id)).toContain(pid);

    expect(team.pitchingConfig.ageLimits['7-8']).toEqual({ dailyMax: 50, restDay1Min: 21, restDay2Min: 36 });
  });

  it('never assigns two fielders to one position in an inning', () => {
    for (const l of Object.values(team.gameLineups)) {
      for (const inning of l.innings) {
        const fielding = Object.values(inning.assignments).filter((p) => p !== 'Bench' && p !== 'ABS');
        expect(new Set(fielding).size).toBe(fielding.length);
      }
    }
  });

  it('keeps the team config the coach set', () => {
    expect(team.fairPlayConfig).toMatchObject({
      minimumFieldingInnings: 3, equalBenchTime: true, noRepeatPositions: true, leagueRuleset: 'Custom',
    });
  });
});

// Real exports live only on the developer's machine (gitignored). When present,
// every one must decode cleanly; in CI this block is simply empty.
const privateDir = join(FIXTURES, 'private');
const privateFiles = existsSync(privateDir)
  ? readdirSync(privateDir).filter((f) => f.endsWith('.stlteam'))
  : [];
describe.each(privateFiles.map((f) => [f]))('private export %s', (f) => {
  it('decodes without losing players', () => {
    const raw = JSON.parse(readFileSync(join(privateDir, f), 'utf8'));
    const { team } = parseStlTeam(JSON.stringify(raw));
    expect(team.players).toHaveLength(raw.team.players.length);
    expect(Object.keys(team.gameLineups)).toHaveLength((raw.team.gameLineups ?? []).length / 2);
  });
});

describe('iOS decode fallbacks', () => {
  it('maps unknown positions to Bench (FieldPosition.init(from:))', () => {
    const { team } = parseStlTeam(envelope({
      players: [player(P1)],
      lineup: { innings: [{ assignments: [P1, 'DH'] }] },
    }));
    expect(team.lineup.innings[0].assignments[P1]).toBe('Bench');
  });

  it('maps legacy preference tiers forward, anything else to Capable', () => {
    const { team } = parseStlTeam(envelope({
      players: [player(P1, { positionPreferences: ['SS', 'Primary', 'C', 'Secondary', '1B', 'Bogus'] })],
    }));
    expect(team.players[0].positionPreferences).toEqual({ SS: 'Strength', C: 'Capable', '1B': 'Capable' });
  });

  it('drops the whole roster when one player is missing a required field, like iOS', () => {
    const { team } = parseStlTeam(envelope({
      players: [player(P1), { id: P2, firstName: 'No', number: '1' }],
    }));
    expect(team.players).toEqual([]);
  });

  it('falls back to defaults for missing configs and inning count', () => {
    const { team } = parseStlTeam(envelope({}));
    expect(team.gameInningCount).toBe(7);
    expect(team.fairPlayConfig.noConsecutiveBench).toBe(true);
    expect(team.fairPlayConfig.minimumFieldingInnings).toBe(4);
    expect(team.pitchingConfig.rulesEnabled).toBe(false);
    expect(team.lineup.innings).toHaveLength(7);
  });

  it('upper-cases UUIDs and pitch-count keys', () => {
    const { team } = parseStlTeam(envelope({
      players: [player(P1.toLowerCase())],
      gameLogs: [{
        gameDate: '2026-09-13T23:30:00Z', opponent: 'X', inningsPlayed: 6,
        battingOrder: [P1.toLowerCase()], innings: [], playerSnapshot: [],
        pitchCounts: { [P1.toLowerCase()]: 42 },
      }],
    }));
    expect(team.players[0].id).toBe(P1);
    expect(team.gameLogs[0].pitchCounts).toEqual({ [P1]: 42 });
  });

  it('decodes a template lock range from [lo, hi]', () => {
    const { team } = parseStlTeam(envelope({
      players: [player(P1)],
      lineupTemplates: [{
        id: P2, name: 'T', battingOrder: [P1], createdAt: '2026-09-01T00:00:00Z',
        positionLocks: [{ id: P2, playerID: P1, position: 'P', innings: [0, 1] }],
      }],
    }));
    expect(team.lineupTemplates[0].positionLocks[0].innings).toEqual([0, 1]);
  });
});

describe('envelope errors', () => {
  it('rejects non-JSON with the iOS message', () => {
    expect(() => parseStlTeam('not json')).toThrow(/valid team file/);
  });

  it('rejects a newer format version', () => {
    try {
      parseStlTeam(envelope({}, 2));
      throw new Error('expected a throw');
    } catch (e) {
      expect(e).toBeInstanceOf(TeamImportError);
      expect((e as TeamImportError).kind).toBe('unsupportedVersion');
      expect((e as Error).message).toMatch(/format v2/);
    }
  });
});
