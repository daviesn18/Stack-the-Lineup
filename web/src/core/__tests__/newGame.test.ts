import { addGameLog, gameLogFrom, hasGameDetails, nextGameLineup, pitchersIn } from '../newGame';
import { emptyLineup, type GameLog, type Lineup, type Player } from '../model';

const players: Player[] = [
  { id: 'A', firstName: 'Ann', lastName: 'Lee', number: '4', positionPreferences: {}, leagueAge: 10 },
  { id: 'B', firstName: 'Bo', lastName: 'Ray', number: '7', positionPreferences: {} },
];

const lineup = (): Lineup & { id: string } => ({
  ...emptyLineup(3),
  id: 'L',
  opponent: 'Cedar Mills',
  gameDate: new Date(2026, 8, 27, 10),
  battingOrder: ['A', 'B'],
  innings: [{ assignments: { A: 'P', B: 'C' } }, { assignments: { A: 'SS', B: 'P' } }, { assignments: {} }],
  absentPlayerIDs: ['B'],
  status: 'finalized',
  lastFinalizedBy: 'Nick',
  lastFinalizedAt: new Date(2026, 8, 26),
});

describe('new game', () => {
  it('freezes the lineup into a game log', () => {
    const l = lineup();
    const log = gameLogFrom(l, players, 3, ' Nick ', {
      id: 'G', inningsPlayed: 9, notes: ' Won 8-5 ', pitchCounts: { A: 42, B: 0 }, archivedAt: new Date(),
    });
    expect(log.inningsPlayed).toBe(3);
    expect(log.opponent).toBe('Cedar Mills');
    expect(log.innings).toEqual(l.innings);
    expect(log.innings[0].assignments).not.toBe(l.innings[0].assignments);
    expect(log.playerSnapshot).toEqual([
      { id: 'A', firstName: 'Ann', lastName: 'Lee', number: '4' }, { id: 'B', firstName: 'Bo', lastName: 'Ray', number: '7' },
    ]);
    expect(log.pitchCounts).toEqual({ A: 42 });
    expect(log.archivedBy).toBe('Nick');
    expect(log.notes).toBe('Won 8-5');
  });

  it('clears the lineup for the next game, keeping the batting order', () => {
    const next = nextGameLineup(lineup(), 6, { opponent: ' Tigard ', gameDate: new Date(2026, 9, 4, 9) });
    expect(next.id).toBe('L');
    expect(next.opponent).toBe('Tigard');
    expect(next.innings).toHaveLength(6);
    expect(next.innings.every((i) => Object.keys(i.assignments).length === 0)).toBe(true);
    expect(next.battingOrder).toEqual(['A', 'B']);
    expect(next.absentPlayerIDs).toEqual([]);
    expect(next.status).toBe('draft');
    expect(next.lastFinalizedBy).toBeUndefined();
  });

  it('keeps logs newest first', () => {
    const log = (id: string, day: number) => ({ id, gameDate: new Date(2026, 8, day) }) as GameLog;
    expect(addGameLog([log('x', 20), log('y', 6)], log('z', 13)).map((g) => g.id)).toEqual(['x', 'z', 'y']);
  });

  it('finds pitchers and whether there is anything to archive', () => {
    expect(pitchersIn(lineup())).toEqual(['A', 'B']);
    expect(hasGameDetails(lineup())).toBe(true);
    expect(hasGameDetails(emptyLineup(3))).toBe(false);
  });
});
