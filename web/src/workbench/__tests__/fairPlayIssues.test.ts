import { place, toggleAbsent } from '@/core/lineupOps';
import { demoTeam } from '@/dev/demoTeam';

import { fairPlayIssues, playingTime } from '../fairPlayIssues';

const setup = () => {
  const d = demoTeam();
  const input = { lineup: d.lineup, players: d.players, config: d.team.fairPlayConfig, pitchingConfig: d.team.pitchingConfig, gameLogs: d.gameLogs };
  return { d, input };
};
const byFirst = (d: ReturnType<typeof demoTeam>, name: string) => d.players.find((p) => p.firstName === name)!;

describe('fairPlayIssues', () => {
  it('the handoff sample lineup is all clear', () => {
    expect(fairPlayIssues(setup().input)).toEqual([]);
  });

  it('marking a player absent opens their spots (red), pointing at the first open inning', () => {
    const { d, input } = setup();
    const lineup = toggleAbsent(d.lineup, byFirst(d, 'Nate').id);
    const issues = fairPlayIssues({ ...input, lineup });
    expect(issues).toHaveLength(1);
    expect(issues[0]).toMatchObject({ title: 'Positions not filled', severity: 'red', inning: 0 });
    expect(issues[0].detail).toBe('6 open in innings 1, 3, 4, 5, 6, 7');
  });

  it('flags back-to-back bench and a Never position', () => {
    const { d, input } = setup();
    const eli = byFirst(d, 'Eli');
    // Eli (benched in 1) takes Nate's SS in inning 1, so Nate sits 1 and 2.
    let lineup = place(d.lineup, eli.id, 0, 'SS');
    const issues = fairPlayIssues({ ...input, lineup });
    expect(issues.map((i) => i.title)).toEqual(['Back-to-back bench']);
    expect(issues[0].detail).toBe('Nate C., innings 1-2');
    // Tyler is Never at RF.
    lineup = place(d.lineup, byFirst(d, 'Tyler').id, 2, 'RF');
    expect(fairPlayIssues({ ...input, lineup }).find((i) => i.title === 'Never position')).toMatchObject({ severity: 'orange', inning: 2, detail: 'Tyler N. at RF, inning 3' });
  });

  it('flags a pitcher the pitch-count rules say must rest', () => {
    const { d, input } = setup();
    const jake = byFirst(d, 'Jake');
    const yesterday = new Date(d.lineup.gameDate);
    yesterday.setDate(yesterday.getDate() - 1);
    const gameLogs = [...d.gameLogs, { ...d.gameLogs[0], id: 'Y', gameDate: yesterday, pitchCounts: { [jake.id]: 70 } }];
    const issue = fairPlayIssues({ ...input, gameLogs }).find((i) => i.key === `rest-${jake.id}`);
    expect(issue).toMatchObject({ title: 'Pitcher needs rest', severity: 'red', inning: 0 });
  });
});

it('playingTime splits infield and outfield innings', () => {
  const { d } = setup();
  expect(playingTime(d.lineup, byFirst(d, 'Marcus'))).toEqual({ infield: 1, outfield: 5 });
});
