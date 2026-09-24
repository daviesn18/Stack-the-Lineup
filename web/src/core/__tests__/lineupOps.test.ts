import { runAutoFill, incompleteMessage } from '../autofillCoordinator';
import {
  assign, changedInnings, clearPositions, displayPlayers, finalize, moveBatter, removePlayer, reopen, shortName,
  toggleAbsent, unassign,
} from '../lineupOps';
import { defaultFairPlayConfig, emptyLineup, type Lineup, type Player } from '../model';

const p = (n: number, extra: Partial<Player> = {}): Player =>
  ({ id: `ID${n}`, firstName: `Kid${n}`, lastName: `Last${n}`, number: String(n), positionPreferences: {}, ...extra });
const roster = Array.from({ length: 11 }, (_, i) => p(i + 1));
const base = (): Lineup => ({ ...emptyLineup(6), battingOrder: roster.map((x) => x.id), gameDate: new Date('2026-09-27T17:00:00Z') });

describe('lineup edits behave like the iOS app', () => {
  it('assigning a taken position evicts the holder (unassigned, not swapped)', () => {
    let l = assign(base(), 'ID1', [0], 'SS');
    l = assign(l, 'ID2', [0], 'SS');
    expect(l.innings[0].assignments).toEqual({ ID2: 'SS' });
  });

  it('bench is shared and never evicts', () => {
    let l = assign(base(), 'ID1', [0, 1], 'Bench');
    l = assign(l, 'ID2', [0], 'Bench');
    expect(l.innings[0].assignments).toEqual({ ID1: 'Bench', ID2: 'Bench' });
  });

  it('any edit to a finalized lineup reverts it to draft and clears the stamp', () => {
    const f = finalize(base(), ' Nick ');
    expect(f.lastFinalizedBy).toBe('Nick');
    const edited = unassign(assign(f, 'ID1', [0], 'P'), 'ID1', [0]);
    expect(edited.status).toBe('draft');
    expect(edited.lastFinalizedBy).toBeUndefined();
    expect(reopen(f)).toMatchObject({ status: 'draft', lastFinalizedBy: 'Nick' });
  });

  it('absent drops the player from order and innings; back again appends to the bottom', () => {
    let l = assign(base(), 'ID3', [0, 2], 'C');
    l = toggleAbsent(l, 'ID3');
    expect(l.battingOrder).not.toContain('ID3');
    expect(l.innings.every((inn) => !('ID3' in inn.assignments))).toBe(true);
    l = toggleAbsent(l, 'ID3');
    expect(l.battingOrder[l.battingOrder.length - 1]).toBe('ID3');
    expect(l.absentPlayerIDs).toEqual([]);
  });

  it('moves a batter, clears positions, removes a deleted player, reports changed innings', () => {
    expect(moveBatter(base(), 'ID5', 0).battingOrder.slice(0, 2)).toEqual(['ID5', 'ID1']);
    const filled = assign(assign(base(), 'ID1', [0], 'P'), 'ID2', [3], 'C');
    expect(changedInnings(base(), filled)).toEqual([0, 3]);
    expect(clearPositions(filled).innings.every((i) => Object.keys(i.assignments).length === 0)).toBe(true);
    const gone = removePlayer(filled, 'ID1');
    expect(gone.battingOrder).not.toContain('ID1');
    expect(gone.innings[0].assignments).toEqual({});
  });

  it('shows the batting order, or the roster until there is one', () => {
    expect(displayPlayers({ ...base(), battingOrder: [] }, roster).map((x) => x.id)).toEqual(roster.map((x) => x.id));
    expect(displayPlayers(toggleAbsent(base(), 'ID1'), roster)[0].id).toBe('ID2');
    expect(shortName(p(1))).toBe('Kid1 L.');
    expect(shortName({ firstName: 'Solo', lastName: '' })).toBe('Solo');
  });
});

describe('Auto-Fill coordinator', () => {
  const args = { lineup: base(), players: roster, config: defaultFairPlayConfig(), gameLogs: [] };

  it('fills the game and words the undo toast like iOS', () => {
    const o = runAutoFill({ ...args, scope: { kind: 'through', inning: 5 }, prompt: '' });
    expect(o.filledCount).toBe(66);
    expect(o.undoMessage).toBe('Auto-filled 66 positions (innings 1–6)');
    expect(o.incompleteMessage).toBeNull();
  });

  it('honors a clear instruction and says so when an instruction is unclear', () => {
    const o = runAutoFill({ ...args, scope: { kind: 'through', inning: 5 }, prompt: 'Kid4 pitches the first 2 innings' });
    expect(o.lineup.innings[0].assignments.ID4).toBe('P');
    expect(o.lineup.innings[1].assignments.ID4).toBe('P');
    expect(o.noticeMessage).toBeNull();
    const vague = runAutoFill({ ...args, scope: { kind: 'inning', inning: 0 }, prompt: 'give Kid2 a breather' });
    expect(vague.noticeMessage).toMatch(/wasn't clear enough/);
  });

  it('confirms bench pairing', () => {
    const o = runAutoFill({ ...args, scope: { kind: 'through', inning: 5 }, prompt: 'have players sit two innings in a row' });
    expect(o.noticeMessage).toMatch(/Bench pairing is on/);
  });

  it('groups unfilled slots by position with inning numbers', () => {
    const msg = incompleteMessage({
      lineup: base(), filledCount: 0, constraintOverrides: [], constraintRejections: [],
      unfilledSlots: [
        { inningIndex: 0, position: 'CF', reason: 'rosterTooSmall' },
        { inningIndex: 2, position: 'CF', reason: 'rosterTooSmall' },
        { inningIndex: 1, position: 'C', reason: 'rosterTooSmall' },
      ],
    }, true);
    expect(msg).toMatch(/^C \(Inning 2\), CF \(Innings 1, 3\) could not be filled/);
  });
});
