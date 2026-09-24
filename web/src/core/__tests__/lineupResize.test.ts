import { dropPositions, lastAssignedInning, resizeInnings } from '../lineupOps';
import { emptyLineup, type Lineup } from '../model';

const lineup = (): Lineup => {
  const l = { ...emptyLineup(7), status: 'finalized' as const, lastFinalizedBy: 'Nick', lastFinalizedAt: new Date() };
  l.innings[0].assignments = { A: 'LCF', B: 'SS' };
  l.innings[6].assignments = { A: 'RCF', B: 'Bench' };
  return l;
};

describe('resizeInnings', () => {
  it('shortens from the end and returns to draft', () => {
    const l = resizeInnings(lineup(), 6);
    expect(l.innings).toHaveLength(6);
    expect(l.innings[0].assignments).toEqual({ A: 'LCF', B: 'SS' });
    expect(l.status).toBe('draft');
    expect(l.lastFinalizedAt).toBeUndefined();
  });
  it('lengthens with empty innings and keeps the status', () => {
    const l = resizeInnings(lineup(), 9);
    expect(l.innings).toHaveLength(9);
    expect(l.innings[8].assignments).toEqual({});
    expect(l.status).toBe('finalized');
  });
  it('same count returns the same lineup; clamps to 1-9', () => {
    const l = lineup();
    expect(resizeInnings(l, 7)).toBe(l);
    expect(resizeInnings(l, 12).innings).toHaveLength(9);
  });
});

describe('lastAssignedInning', () => {
  it('is the 1-based last inning with anyone in it', () => {
    expect(lastAssignedInning(lineup())).toBe(7);
    expect(lastAssignedInning(emptyLineup(6))).toBe(0);
  });
});

describe('dropPositions', () => {
  it('unassigns players at removed positions only', () => {
    const l = dropPositions(lineup(), ['LCF', 'RCF']);
    expect(l.innings[0].assignments).toEqual({ B: 'SS' });
    expect(l.innings[6].assignments).toEqual({ B: 'Bench' });
    expect(l.status).toBe('draft');
  });
  it('returns the same lineup when nobody was there', () => {
    const l = lineup();
    expect(dropPositions(l, ['C'])).toBe(l);
    expect(dropPositions(l, [])).toBe(l);
  });
});
