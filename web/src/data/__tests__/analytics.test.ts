// The wrapper's rules: nothing signed out or in development, platform=web and
// string values on every signal, Test Mode off the live hosts, and a failing
// send never reaching the app.

const mockSent: { type: string; payload: Record<string, string>; testMode: boolean; user: string }[] = [];
const mockState = { failSends: false };
const sent = mockSent;

jest.mock('@telemetrydeck/sdk', () => ({
  __esModule: true,
  default: class {
    mockOptions: { clientUser: string; testMode: boolean };
    constructor(options: { clientUser: string; testMode: boolean }) { this.mockOptions = options; }
    signal(type: string, payload: Record<string, string>) {
      mockSent.push({ type, payload, testMode: this.mockOptions.testMode, user: this.mockOptions.clientUser });
      return mockState.failSends ? Promise.reject(new Error('blocked')) : Promise.resolve();
    }
  },
}));

type Analytics = typeof import('../analytics');
const g = globalThis as unknown as { __DEV__: boolean; location?: { hostname: string } };

function load(dev: boolean, hostname = 'app.stackthelineup.com'): Analytics {
  jest.resetModules();
  g.__DEV__ = dev;
  g.location = { hostname };
  // eslint-disable-next-line @typescript-eslint/no-require-imports -- a fresh module per test, after __DEV__ is set
  return require('../analytics');
}

beforeEach(() => { sent.length = 0; mockState.failSends = false; });
afterAll(() => { g.__DEV__ = true; delete g.location; });

describe('analytics', () => {
  it('sends nothing in development', () => {
    const a = load(true);
    a.setAnalyticsUser('coach-1');
    a.signal('lineup.finalized');
    expect(sent).toEqual([]);
  });

  it('sends nothing while signed out', () => {
    const a = load(false);
    a.signal('lineup.finalized');
    a.setAnalyticsUser(null);
    a.signal('lineup.finalized');
    expect(sent).toEqual([]);
  });

  it('starts a session once per coach, as that coach', () => {
    const a = load(false);
    a.setAnalyticsUser('coach-1');
    a.setAnalyticsUser('coach-1');   // token refreshes repeat the same user
    expect(sent.map((s) => [s.type, s.user])).toEqual([['TelemetryDeck.Session.started', 'coach-1']]);
    a.setAnalyticsUser(null);
    a.setAnalyticsUser('coach-2');
    expect(sent.map((s) => s.user)).toEqual(['coach-1', 'coach-2']);
  });

  it('marks every signal platform=web and stringifies values like iOS', () => {
    const a = load(false);
    a.setAnalyticsUser('coach-1');
    a.signal('game.archived', { inningsPlayed: 6, pitchCountsEntered: 0, ok: true });
    expect(sent[1]).toMatchObject({
      type: 'game.archived',
      payload: { platform: 'web', inningsPlayed: '6', pitchCountsEntered: '0', ok: 'true' },
      testMode: false,
    });
  });

  it('uses Test Mode off the live hosts', () => {
    const a = load(false, 'stack-the-lineup-git-some-branch.vercel.app');
    a.setAnalyticsUser('coach-1');
    expect(sent[0].testMode).toBe(true);
    expect(a.isTestHost('stack-the-lineup.vercel.app')).toBe(false);
    expect(a.isTestHost('localhost')).toBe(true);
    expect(a.isTestHost(undefined)).toBe(true);
  });

  it('a failed send never throws into the app', async () => {
    const a = load(false);
    a.setAnalyticsUser('coach-1');
    mockState.failSends = true;
    expect(() => a.signal('pdf.exported', { type: 'battingOrder' })).not.toThrow();
    await new Promise((r) => setTimeout(r, 0));
  });

  it('app.opened on the first team of a page load, team.switched for a different one after', () => {
    const a = load(false);
    a.setAnalyticsUser('coach-1');
    a.teamOpened('A', 12);
    a.teamOpened('A', 12);
    a.teamOpened('B', 9);
    expect(sent.slice(1).map((s) => s.type)).toEqual(['app.opened', 'team.switched']);
    expect(sent[1].payload.playerCount).toBe('12');
  });

  it('tallies ride along on a later signal and reset', () => {
    const a = load(false);
    a.setAnalyticsUser('coach-1');
    a.tally('assign.drag'); a.tally('assign.drag'); a.tally('assign.picker');
    expect(a.takeTallies('assign')).toEqual({ assignDrag: 2, assignPicker: 1 });
    expect(a.takeTallies('assign')).toEqual({});
  });
});
