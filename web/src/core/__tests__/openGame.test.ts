// Merge 3: the open game is each device's own. Mirrors OpenGameTests.swift.
import { archivedMessage, defaultLineup, resolveOpenLineup, type LineupRef, type LogRef } from '../openGame';
import type { ScheduledGame } from '../model';

// Saturday 2026-11-21, 10:00 in the test time zone (America/Los_Angeles).
const now = new Date(2026, 10, 21, 10, 0);
const hours = (n: number) => new Date(now.getTime() + n * 3600_000);

let n = 0;
const id = () => `00000000-0000-4000-8000-${String(++n).padStart(12, '0')}`;

function setup() {
  const games: ScheduledGame[] = [];
  const lineups: LineupRef[] = [];
  const logs: LogRef[] = [];
  const addGame = (at: Date, { cancelled = false, lineup = true, opponent = 'Tigers' } = {}) => {
    const game = id();
    const lineupId = id();
    games.push({ id: game, icalUID: game, date: at, rawSummary: `vs ${opponent}`, opponent, isCancelled: cancelled, lastSyncedAt: at });
    if (lineup) lineups.push({ id: lineupId, scheduledGameId: game });
    return { game, lineup: lineupId };
  };
  const addLog = (game: string | null, { opponent = 'Tigers', by = null as string | null, name = '' } = {}) => {
    logs.push({ id: id(), scheduledGameId: game, opponent, archivedByUser: by, archivedByName: name });
  };
  return { games, lineups, logs, addGame, addLog };
}

describe('defaultLineup', () => {
  it('opens the next game from the start of today', () => {
    const s = setup();
    s.addGame(hours(48));
    const earlierToday = s.addGame(hours(-2));
    s.addGame(hours(-30));
    expect(defaultLineup(s.lineups, s.games, now)).toBe(earlierToday.lineup);
  });

  it('skips cancelled games and games without a lineup', () => {
    const s = setup();
    s.addGame(hours(1), { cancelled: true });
    s.addGame(hours(2), { lineup: false });
    const later = s.addGame(hours(5));
    expect(defaultLineup(s.lineups, s.games, now)).toBe(later.lineup);
  });

  it('falls back to the latest past game, then an ad-hoc lineup', () => {
    const s = setup();
    s.addGame(hours(-96));
    const latestPast = s.addGame(hours(-30));
    expect(defaultLineup(s.lineups, s.games, now)).toBe(latestPast.lineup);

    const a = id(), b = id();
    const adhoc = [{ id: a, scheduledGameId: null }, { id: b, scheduledGameId: null }];
    expect(defaultLineup(adhoc, [], now, b)).toBe(b);
    expect(defaultLineup(adhoc, [], now)).not.toBeNull();
    expect(defaultLineup([], [], now)).toBeNull();
  });
});

describe('resolveOpenLineup', () => {
  it("keeps this browser's open game even when it isn't the default", () => {
    const s = setup();
    s.addGame(hours(1));
    const later = s.addGame(hours(72));
    const r = resolveOpenLineup({ ...s, stored: { lineupId: later.lineup, gameId: later.game }, now });
    expect(r).toEqual({ lineupId: later.lineup, archived: null });
  });

  it('keeps an ad-hoc lineup open', () => {
    const s = setup();
    s.addGame(hours(1));
    const adhoc = id();
    s.lineups.push({ id: adhoc, scheduledGameId: null });
    expect(resolveOpenLineup({ ...s, stored: { lineupId: adhoc, gameId: null }, now }).lineupId).toBe(adhoc);
  });

  it('compares ids without regard to case', () => {
    const s = setup();
    const g = s.addGame(hours(1));
    const r = resolveOpenLineup({ ...s, stored: { lineupId: g.lineup.toLowerCase(), gameId: g.game.toLowerCase() }, now });
    expect(r.lineupId).toBe(g.lineup);
  });

  it('moves on when the open game was archived elsewhere, and says who', () => {
    const s = setup();
    const open = s.addGame(hours(-1));
    const next = s.addGame(hours(48), { opponent: 'Lions' });
    s.lineups.find((l) => l.id === open.lineup)!.scheduledGameId = null; // archive_game detaches the row
    s.addLog(open.game, { by: 'sam', name: ' Sam Rivera ' });
    const r = resolveOpenLineup({ ...s, stored: { lineupId: open.lineup, gameId: open.game }, me: 'nick', now });
    expect(r.lineupId).toBe(next.lineup);
    expect(r.archived).toEqual({ byName: 'Sam Rivera', byMe: false, opponent: 'Tigers' });
    expect(archivedMessage(r.archived!)).toBe('Sam Rivera archived the game vs Tigers. Showing your next game.');
  });

  it('says "you" when this account archived it on another device', () => {
    const s = setup();
    const open = s.addGame(now);
    s.lineups.splice(s.lineups.findIndex((l) => l.id === open.lineup), 1); // iOS deletes the game's row
    s.addLog(open.game, { by: 'nick', name: 'Nick' });
    const r = resolveOpenLineup({ ...s, stored: { lineupId: open.lineup, gameId: open.game }, me: 'NICK', now });
    expect(archivedMessage(r.archived!)).toBe('You archived the game vs Tigers on another device. Showing your next game.');
  });

  it('follows the row "Archive and start new game" carried forward, not an older ad-hoc lineup', () => {
    const s = setup();
    const stale = id();
    s.lineups.push({ id: stale, scheduledGameId: null }); // sorts first: the old fallback picked it
    const open = s.addGame(hours(-1), { opponent: 'Lions' });
    s.lineups.find((l) => l.id === open.lineup)!.scheduledGameId = null; // now the ad-hoc game vs Bears
    s.addLog(open.game, { opponent: 'Lions', by: 'nick' });
    const r = resolveOpenLineup({ ...s, stored: { lineupId: open.lineup, gameId: open.game }, me: 'nick', now });
    expect(r.lineupId).toBe(open.lineup);
    expect(archivedMessage(r.archived!)).toBe('You archived the game vs Lions on another device. Showing your next game.');
  });

  it('names no one when the archiver has no name', () => {
    const s = setup();
    const open = s.addGame(now, { opponent: '' });
    s.lineups.length = 0;
    s.addLog(open.game, { opponent: '' });
    const r = resolveOpenLineup({ ...s, stored: { lineupId: open.lineup, gameId: open.game }, now });
    expect(archivedMessage(r.archived!)).toBe('Another coach archived the game. Showing your next game.');
  });

  it('moves on quietly when the game just left the schedule', () => {
    const s = setup();
    const open = s.addGame(now);
    s.lineups.length = 0;
    s.addLog(id());
    expect(resolveOpenLineup({ ...s, stored: { lineupId: open.lineup, gameId: open.game }, now }).archived).toBeNull();
  });

  it('opens the default with nothing stored', () => {
    const s = setup();
    const g = s.addGame(hours(3));
    expect(resolveOpenLineup({ ...s, stored: null, now })).toEqual({ lineupId: g.lineup, archived: null });
  });
});
