import type { ScheduledGame } from '../model';
import { isPractice, planOpenGame, upcomingGames } from '../schedule';

const game = (id: string, date: string, extra: Partial<ScheduledGame> = {}): ScheduledGame => ({
  id, icalUID: id, date: new Date(date), rawSummary: 'Mudcats vs Pirates', isCancelled: false,
  lastSyncedAt: new Date(date), opponent: 'Pirates', ...extra,
});

describe('upcomingGames', () => {
  const now = new Date(2026, 10, 6, 15, 0);
  it('keeps games from the start of today, soonest first, minus cancelled and practices', () => {
    const list = upcomingGames([
      game('later', '2026-11-20T18:00:00Z'),
      game('earlierToday', new Date(2026, 10, 6, 9, 0).toISOString()),
      game('yesterday', new Date(2026, 10, 5, 9, 0).toISOString()),
      game('cancelled', '2026-11-10T18:00:00Z', { isCancelled: true }),
      game('practice', '2026-11-11T18:00:00Z', { rawSummary: 'Team Practice' }),
    ], now);
    expect(list.map((g) => g.id)).toEqual(['earlierToday', 'later']);
  });
  it('matches ICalParser.isPractice', () => {
    expect(isPractice('BP at Field 3')).toBe(true);
    expect(isPractice('Mudcats @ Pirates')).toBe(false);
  });
});

describe('planOpenGame (applyScheduledGame)', () => {
  const saved = { G2: { lineupId: 'L2', status: 'draft' as const, hasContent: true } };
  it('is a no-op for the open game', () => expect(planOpenGame('G1', 'G1', saved)).toEqual({ kind: 'noop' }));
  it('reopens a saved lineup', () => expect(planOpenGame('G2', 'G1', saved)).toEqual({ kind: 'reopen', lineupId: 'L2' }));
  it('stamps the ad-hoc lineup onto its first game', () => expect(planOpenGame('G3', undefined, saved)).toEqual({ kind: 'stamp' }));
  it('starts fresh when moving from one game to an unbuilt one', () => expect(planOpenGame('G3', 'G1', saved)).toEqual({ kind: 'fresh' }));
});
