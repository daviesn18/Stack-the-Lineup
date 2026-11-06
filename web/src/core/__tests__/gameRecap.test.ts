// Mirrors GameRecapTests.swift.
import {
  buildRecap, datePhrase, issueSentence, listOf, pitchingSentence, recapIssues, recapSummary, sentenceJoining, type GameRecap,
} from '../gameRecap';
import { defaultFairPlayConfig, type FairPlayConfig, type FieldPosition, type GameLog, type Player } from '../model';

let n = 0;
const player = (first: string, last: string, number = ''): Player => ({
  id: `00000000-0000-4000-8000-${String(++n).padStart(12, '0')}`, firstName: first, lastName: last, number, positionPreferences: {},
});
const noRules = (): FairPlayConfig => ({
  ...defaultFairPlayConfig(), minimumFieldingInnings: 0, minimumInfieldInnings: 0, minimumOutfieldInnings: 0,
  noConsecutiveBench: false, catcherToPitcherThreshold: 0, pitcherToCatcherThreshold: 0,
});
const log = (inningsPlayed: number, players: Player[], innings: Record<string, FieldPosition>[], pitchCounts: Record<string, number> = {}): GameLog => ({
  id: 'L', gameDate: new Date(), opponent: 'Rangers', inningsPlayed, battingOrder: players.map((p) => p.id),
  innings: innings.map((assignments) => ({ assignments })),
  playerSnapshot: players.map(({ id, firstName, lastName, number }) => ({ id, firstName, lastName, number })),
  archivedAt: new Date(), pitchCounts, archivedBy: '', notes: '',
});

describe('pitching lines', () => {
  it('count only innings actually played', () => {
    const jake = player('Jake', 'Rivera');
    const r = buildRecap(log(4, [jake], [{}, {}, {}, { [jake.id]: 'P' }, { [jake.id]: 'P' }, { [jake.id]: 'P' }]), noRules());
    expect(r.pitching).toHaveLength(1);
    expect(r.pitching[0].innings).toBe(1);
  });
  it('list pitchers in the order they took the mound, with recorded pitches', () => {
    const jake = player('Jake', 'Rivera');
    const nate = player('Nate', 'Coleman');
    const r = buildRecap(log(3, [jake, nate], [{ [nate.id]: 'P' }, { [jake.id]: 'P' }, { [jake.id]: 'P' }], { [jake.id]: 34 }), noRules());
    expect(r.pitching.map((l) => l.name)).toEqual(['Nate Coleman', 'Jake Rivera']);
    expect(r.pitching[1].pitches).toBe(34);
    expect(r.pitching[0].pitches).toBeUndefined();
  });
  it('the sentence omits pitches it does not have', () => {
    const r: GameRecap = {
      opponent: 'Rangers', gameDate: new Date(), inningsPlayed: 4, battingOrder: [], fairPlayIssues: [], fieldingMinimumSkipped: false,
      pitching: [{ playerID: 'a', name: 'Jake Rivera', innings: 2, pitches: 34 }, { playerID: 'b', name: 'Nate Coleman', innings: 2 }],
    };
    expect(pitchingSentence(r)).toBe('Jake Rivera pitched 2 innings on 34 pitches, and Nate Coleman pitched 2 innings.');
  });
});

describe('roster identity', () => {
  it('describes who played, from the snapshot', () => {
    const owen = player('Owen', 'Fischer', '5');
    const r = buildRecap(log(2, [owen], [{ [owen.id]: 'P' }, { [owen.id]: 'P' }]), noRules());
    expect(r.pitching.map((l) => l.name)).toEqual(['Owen Fischer']);
    expect(r.battingOrder).toEqual(['Owen F.']);
  });
});

describe('fair play', () => {
  it('a clean game reports no issues', () => {
    const players = Array.from({ length: 10 }, (_, i) => player(`P${i + 1}`, 'Test'));
    const pos: FieldPosition[] = ['P', 'C', '1B', '2B', '3B', 'SS', 'LF', 'CF', 'RF', 'Bench'];
    const r = buildRecap(log(1, players, [Object.fromEntries(players.map((p, i) => [p.id, pos[i]]))]), noRules());
    expect(r.fairPlayIssues).toEqual([]);
    expect(recapSummary(r)).toContain('Everyone met your fair play rules.');
  });
  it('a short game skips the fielding minimum instead of flagging everyone', () => {
    const players = [player('A', 'T'), player('B', 'T'), player('C', 'T')];
    const a = Object.fromEntries(players.map((p, i) => [p.id, (['P', 'C', '1B'] as FieldPosition[])[i]]));
    const r = buildRecap(log(2, players, [a, a]), { ...noRules(), minimumFieldingInnings: 4 });
    expect(r.fieldingMinimumSkipped).toBe(true);
    expect(r.fairPlayIssues).toEqual([]);
    expect(recapSummary(r)).toContain('too short');
  });
  it('a full-length game still applies the fielding minimum', () => {
    const cam = player('Cam', 'Torres');
    const leo = player('Leo', 'Huang');
    const a: Record<string, FieldPosition> = { [cam.id]: 'P', [leo.id]: 'Bench' };
    const r = buildRecap(log(4, [cam, leo], [a, a, a, a]), { ...noRules(), minimumFieldingInnings: 4 });
    expect(r.fieldingMinimumSkipped).toBe(false);
    expect(r.fairPlayIssues.map((i) => i.names)).toEqual([['Leo Huang']]);
  });
  it('issue sentences name players rather than counting', () => {
    const leo = player('Leo', 'Huang');
    const cam = player('Cam', 'Torres');
    const issues = recapIssues({
      withoutInfield: [leo, cam], withoutOutfield: [], underFieldingMinimum: [], backToBackBench: [leo],
      catcherThenPitcher: [], pitcherThenCatcher: [], minimumFieldingInnings: 4,
    });
    expect(issues.map((i) => issueSentence(i))).toEqual([
      'Leo Huang and Cam Torres never played the infield.',
      'Leo Huang sat two innings in a row.',
    ]);
  });
  it('a capped issue names a few and counts the rest', () => {
    const issue = { names: ['Jake Rivera', 'Tyler Nguyen', 'Drew Santos', 'Eli Park', 'Nate Coleman', 'Leo Huang'], predicate: 'never played the outfield' };
    expect(issueSentence(issue, 3)).toBe('Jake Rivera, Tyler Nguyen, Drew Santos, and 3 others never played the outfield.');
    expect(issueSentence(issue)).toContain('Leo Huang');
  });
});

describe('phrasing', () => {
  it('lists and sentences', () => {
    expect(listOf(['Leo', 'Cam'])).toBe('Leo and Cam');
    expect(listOf(['Leo', 'Cam', 'Nate'])).toBe('Leo, Cam, and Nate');
    expect(sentenceJoining([])).toBe('');
    expect(sentenceJoining(['A'])).toBe('A.');
    expect(sentenceJoining(['A', 'B'])).toBe('A, and B.');
    expect(sentenceJoining(['A', 'B', 'C'])).toBe('A, B, and C.');
  });
  it('dates', () => {
    const now = new Date(2026, 10, 6, 12);
    expect(datePhrase(now, now)).toBe('today');
    expect(datePhrase(new Date(2026, 10, 5, 9), now)).toBe('yesterday');
    expect(datePhrase(new Date(2026, 10, 3, 9), now)).toBe('Tuesday');
    expect(datePhrase(new Date(2026, 9, 20, 9), now)).toBe('Tuesday, Oct 20');
  });
});
