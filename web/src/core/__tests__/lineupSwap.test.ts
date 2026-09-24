import { completeBattingOrder, gridNames, keepForRemaining, place, restoreAbsent, toggleAbsent } from '../lineupOps';
import { emptyLineup, type Lineup } from '../model';

const lineup = (): Lineup => {
  const l = { ...emptyLineup(3), battingOrder: ['A', 'B', 'C'] };
  l.innings[0].assignments = { A: 'SS', B: '2B', C: 'Bench' };
  l.innings[1].assignments = { A: 'P', B: 'SS' };
  return l;
};

describe('place (assign with swap)', () => {
  it('swaps the holder into the player\'s old spot', () => {
    const l = place(lineup(), 'B', 0, 'SS');
    expect(l.innings[0].assignments).toEqual({ A: '2B', B: 'SS', C: 'Bench' });
  });
  it('benches the holder when the player had no spot', () => {
    const l = place(lineup(), 'C', 1, 'SS');
    expect(l.innings[1].assignments).toEqual({ A: 'P', B: 'Bench', C: 'SS' });
  });
  it('benches the holder when the player came off the bench', () => {
    const l = place(lineup(), 'C', 0, 'SS');
    expect(l.innings[0].assignments).toEqual({ A: 'Bench', B: '2B', C: 'SS' });
  });
  it('Bench and null never move anyone else', () => {
    expect(place(lineup(), 'A', 0, 'Bench').innings[0].assignments).toEqual({ A: 'Bench', B: '2B', C: 'Bench' });
    expect(place(lineup(), 'A', 0, null).innings[0].assignments).toEqual({ B: '2B', C: 'Bench' });
  });
  it('only touches that inning, and returns a finalized lineup to draft', () => {
    const l = place({ ...lineup(), status: 'finalized' }, 'B', 0, 'SS');
    expect(l.innings[1].assignments).toEqual({ A: 'P', B: 'SS' });
    expect(l.status).toBe('draft');
  });
});

it('keepForRemaining repeats the spot to the last inning', () => {
  const l = keepForRemaining(lineup(), 'A', 0);
  expect(l.innings.map((i) => i.assignments.A)).toEqual(['SS', 'SS', 'SS']);
  expect(l.innings[1].assignments.B).toBe('P');   // B swapped into A's old inning-2 spot
});

it('restoreAbsent brings a player back on the bench', () => {
  const gone = toggleAbsent(lineup(), 'C');
  const back = restoreAbsent(gone, 'C');
  expect(back.absentPlayerIDs).toEqual([]);
  expect(back.battingOrder).toEqual(['A', 'B', 'C']);
  expect(back.innings.map((i) => i.assignments.C)).toEqual(['Bench', 'Bench', 'Bench']);
});

describe('completeBattingOrder', () => {
  const players = ['A', 'B', 'C', 'D'].map((id) => ({ id, firstName: id, lastName: 'X', number: '', positionPreferences: {} }));
  it('appends missing active players in roster order, skipping absent and deleted ones', () => {
    const l = { ...emptyLineup(1), battingOrder: ['C', 'GONE', 'A'], absentPlayerIDs: ['D'] };
    expect(completeBattingOrder(l, players).battingOrder).toEqual(['C', 'A', 'B']);
  });
  it('returns the same lineup when the order is already complete', () => {
    const l = { ...emptyLineup(1), battingOrder: ['B', 'A', 'C', 'D'] };
    expect(completeBattingOrder(l, players)).toBe(l);
  });
});

it('gridNames disambiguates shared first names', () => {
  const p = (id: string, firstName: string, lastName: string) => ({ id, firstName, lastName, number: '', positionPreferences: {} });
  const names = gridNames([p('1', 'Caleb', 'Johnston'), p('2', 'Caleb', 'Van Vleet'), p('3', 'Noah', 'Davies'), p('4', 'Noah', 'Dunn'), p('5', 'Ian', 'Nehez')]);
  expect([...names.values()]).toEqual(['Caleb J.', 'Caleb V.', 'Noah Davies', 'Noah Dunn', 'Ian']);
});
