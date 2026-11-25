// Merge 4: how the web reads a coach's role, the invite-link format, and the
// server refusals it shows. Mirrors iOS TeamAccessTests.

import {
  canChangeSettings, canEdit, coachDisplayName, failureOf, inviteToken, inviteUrl, isOwner, isShared, ownerDisplayName,
  resolveAccess, type MemberRow,
} from '../sharing';

// jest hoists this above the imports.
jest.mock('../supabase', () => ({ supabase: {} }));

const owner = '6f1d2c34-1111-4aaa-8bbb-0123456789ab';
const editor = '7a2e3d45-2222-4bbb-9ccc-123456789abc';
const viewer = '8b3f4e56-3333-4ccc-addd-23456789abcd';
const members: MemberRow[] = [
  { user_id: viewer, role: 'viewer', name: 'Lee', joined_at: '2026-11-24T02:00:00Z' },
  { user_id: editor, role: 'editor', name: ' Jo ', joined_at: '2026-11-24T01:00:00Z' },
  { user_id: '9c4a5f67-4444-4ddd-beee-3456789abcde', role: 'someday-a-new-role', name: null, joined_at: null },
];

describe('resolveAccess', () => {
  test('the owner, from the fetched team', () => {
    const a = resolveAccess(owner, 'Sam', members, owner)!;
    expect(a.role).toBe('owner');
    expect(isOwner(a) && canChangeSettings(a) && canEdit(a) && isShared(a)).toBe(true);
    expect(a.coaches.map((c) => c.userId)).toEqual([editor.toUpperCase(), viewer.toUpperCase()]);
  });

  test('an editor edits but leaves settings to the owner (decision 1)', () => {
    const a = resolveAccess(owner, 'Sam', members, editor.toUpperCase())!;
    expect(a.role).toBe('editor');
    expect(canEdit(a)).toBe(true);
    expect(canChangeSettings(a)).toBe(false);
    expect(a.myName).toBe('Jo');
  });

  test('a viewer changes nothing', () => {
    const a = resolveAccess(owner, 'Sam', members, viewer)!;
    expect(canEdit(a)).toBe(false);
    expect(canChangeSettings(a)).toBe(false);
  });

  test('someone not on the team, or signed out, gets nothing', () => {
    expect(resolveAccess(owner, 'Sam', members, '00000000-0000-0000-0000-000000000000')).toBeNull();
    expect(resolveAccess(owner, 'Sam', members, null)).toBeNull();
  });

  test('an unknown role is skipped, not a failure', () => {
    expect(resolveAccess(owner, 'Sam', members, owner)!.coaches).toHaveLength(2);
  });

  test('names fall back', () => {
    const a = resolveAccess(owner, '  ', members, owner)!;
    expect(ownerDisplayName(a)).toBe('the head coach');
    expect(coachDisplayName(a.coaches[0])).toBe('Jo');
    expect(coachDisplayName({ userId: 'x', role: 'editor', name: ' ', joinedAt: null })).toBe('Coach');
  });
});

describe('invite links', () => {
  const token = 'ab12'.repeat(16);

  test('the link iOS opens', () => {
    expect(inviteUrl(token)).toBe(`https://app.stackthelineup.com/join/${token}`);
  });

  test('the route parameter is a token only when it looks like one', () => {
    expect(inviteToken(token)).toBe(token);
    expect(inviteToken(token.toUpperCase())).toBe(token);
    expect(inviteToken([token])).toBe(token);
    for (const bad of [undefined, '', 'short', `${token}0`, 'z'.repeat(64), `${token}/extra`]) {
      expect(inviteToken(bad)).toBeNull();
    }
  });
});

describe('failureOf', () => {
  test('the server hints and codes the screens act on', () => {
    expect(failureOf({ message: 'x', hint: 'pro_required' })).toBe('proRequired');
    expect(failureOf({ message: 'x', hint: 'rate_limited' })).toBe('rateLimited');
    expect(failureOf({ message: 'x', code: '42501' })).toBe('notOwner');
    expect(failureOf({ message: 'TypeError: Failed to fetch' })).toBe('offline');
    expect(failureOf({ message: 'boom', code: 'P0001' })).toBe('other');
  });
});
