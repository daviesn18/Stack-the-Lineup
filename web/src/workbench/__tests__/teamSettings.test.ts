import { defaultFairPlayConfig, defaultPitchingConfig } from '@/core/model';
import { applyLittleLeaguePreset } from '@/core/pitching';
import type { TeamInfo } from '@/data/teamStore';

import {
  changeCount, clampToGame, draftFromTeam, draftProblems, nextBracket, railStatus, rulesOn, teamFromDraft, tierCells,
  type BracketRow,
} from '../teamSettings';

const team = (): TeamInfo => ({
  id: 'T', name: 'Mudcats', colorHex: '1b2c5d', coachName: 'Coach', gameInningCount: 7,
  fairPlayConfig: defaultFairPlayConfig(), pitchingConfig: applyLittleLeaguePreset({ ...defaultPitchingConfig(), rulesEnabled: true }),
});

describe('team settings draft', () => {
  it('round-trips a team with no changes', () => {
    const t = team();
    const d = draftFromTeam(t);
    expect(changeCount(d, d)).toBe(0);
    const back = teamFromDraft(t, d);
    expect(back.fairPlayConfig).toEqual(t.fairPlayConfig);
    expect(back.pitchingConfig.ageLimits).toEqual(t.pitchingConfig.ageLimits);
    expect(back.colorHex).toBe('1B2C5D');
  });

  it('pausing fair play turns the rules off and keeps the coach values', () => {
    const t = team();
    const d = { ...draftFromTeam(t), fp: false };
    const paused = teamFromDraft(t, d);
    expect(rulesOn(paused.fairPlayConfig)).toBe(0);
    expect(paused.fairPlayConfig.pausedRules?.minimumFieldingInnings).toBe(4);
    const again = draftFromTeam(paused);
    expect(again.fp).toBe(false);
    expect(again.fair.minimumFieldingInnings).toBe(4);
    expect(railStatus(again).fair).toBe('Paused');
    const resumed = teamFromDraft(paused, { ...again, fp: true });
    expect(resumed.fairPlayConfig).toEqual(t.fairPlayConfig);
  });

  it('pausing leaves the positions on the field alone', () => {
    const t = team();
    t.fairPlayConfig = { ...t.fairPlayConfig, noPitcher: true, outfielderCount: 4 };
    const paused = teamFromDraft(t, { ...draftFromTeam(t), fp: false }).fairPlayConfig;
    expect(paused.noPitcher).toBe(true);
    expect(paused.outfielderCount).toBe(4);
  });

  it('counts changes per setting, one per bracket row', () => {
    const d = draftFromTeam(team());
    const e = { ...d, name: 'X', gameLen: 6, brackets: d.brackets.slice(1).map((r, i) => (i === 0 ? { ...r, max: 80 } : r)) };
    expect(changeCount(d, e)).toBe(4);
  });

  it('clamps minimums to a shorter game', () => {
    const f = clampToGame({ ...defaultFairPlayConfig(), minimumFieldingInnings: 6, catcherToPitcherThreshold: 5 }, 4);
    expect(f.minimumFieldingInnings).toBe(4);
    expect(f.catcherToPitcherThreshold).toBe(4);
  });

  it('rail status for pitching', () => {
    const d = draftFromTeam(team());
    expect(railStatus(d).pitch).toBe('Rest days only');
    expect(railStatus({ ...d, cap: true, capN: 100 }).pitch).toBe('100 per week cap');
    expect(railStatus({ ...d, pc: false }).pitch).toBe('Paused');
  });
});

describe('age bracket table', () => {
  const row = (max: number | '', t: BracketRow['t']): BracketRow => ({ bracket: '9-10', max, t });

  it('shows each tier range up to the next filled tier or the daily max', () => {
    expect(tierCells(row(75, [21, 36, 51, 66]))).toEqual([
      { kind: 'range', text: '21–35' }, { kind: 'range', text: '36–50' }, { kind: 'range', text: '51–65' }, { kind: 'range', text: '66–75' },
    ]);
    expect(tierCells(row(50, [21, 36, '', '']))).toEqual([
      { kind: 'range', text: '21–35' }, { kind: 'range', text: '36–50' }, { kind: 'skipped' }, { kind: 'skipped' },
    ]);
  });

  it('flags out-of-order and empty tiers', () => {
    expect(tierCells(row(75, [21, 20, '', ''])).map((c) => c.kind)).toEqual(['check', 'check', 'skipped', 'skipped']);
    expect(tierCells(row(30, [21, 36, '', ''])).map((c) => c.kind)).toEqual(['range', 'check', 'skipped', 'skipped']);
  });

  it('blocks saving a bracket with a problem', () => {
    const d = draftFromTeam(team());
    expect(draftProblems(d)).toEqual([]);
    expect(draftProblems({ ...d, brackets: [row('', [21, 36, '', ''])] })).toHaveLength(1);
    expect(draftProblems({ ...d, brackets: [row(75, ['', 36, '', ''])] })).toHaveLength(1);
    expect(draftProblems({ ...d, name: ' ' })).toHaveLength(1);
  });

  it('adds the next bracket, copying the one before it', () => {
    const rows: BracketRow[] = [{ bracket: '9-10', max: 70, t: [20, 35, '', ''] }];
    expect(nextBracket(rows)).toEqual({ bracket: '11-12', max: 70, t: [20, 35, '', ''] });
    expect(nextBracket([])?.bracket).toBe('7-8');
    const all = draftFromTeam(team()).brackets;
    expect(nextBracket(all)).toBeNull();
  });

  it('saves skipped tiers as absent', () => {
    const t = team();
    const d = draftFromTeam(t);
    const out = teamFromDraft(t, { ...d, brackets: [row(75, [21, 36, '', ''])] });
    expect(out.pitchingConfig.ageLimits).toEqual({ '9-10': { dailyMax: 75, restDay1Min: 21, restDay2Min: 36 } });
  });
});
