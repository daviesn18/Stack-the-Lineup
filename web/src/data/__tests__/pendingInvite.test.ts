// Merge 4: an invite opened before signing in waits until the coach is in.

import { forgetInvite, inviteFromAccount, rememberInvite, takeInvite } from '../pendingInvite';

const token = 'ab12'.repeat(16);

beforeAll(() => {
  const data = new Map<string, string>();
  (globalThis as { window?: unknown }).window = {
    localStorage: {
      getItem: (k: string) => data.get(k) ?? null,
      setItem: (k: string, v: string) => { data.set(k, v); },
      removeItem: (k: string) => { data.delete(k); },
    },
  };
});
afterAll(() => { delete (globalThis as { window?: unknown }).window; });
beforeEach(forgetInvite);

test('kept until the coach is signed in, then read once', () => {
  rememberInvite(token);
  expect(takeInvite()).toBe(token);
  expect(takeInvite()).toBeNull();
});

test('dropped after 30 days', () => {
  const t0 = Date.parse('2026-11-24T00:00:00Z');
  rememberInvite(token, t0);
  expect(takeInvite(t0 + 31 * 24 * 3600 * 1000)).toBeNull();
  rememberInvite(token, t0);
  expect(takeInvite(t0 + 29 * 24 * 3600 * 1000)).toBe(token);
});

test('a garbled entry is ignored', () => {
  window.localStorage.setItem('stl.pendingInvite', 'not json');
  expect(takeInvite()).toBeNull();
});

test("an email sign-up's invite is read from the account", () => {
  expect(inviteFromAccount({ pending_invite: token })).toBe(token);
  expect(inviteFromAccount({ pending_invite: null })).toBeNull();
  expect(inviteFromAccount({ pending_invite: '' })).toBeNull();
  expect(inviteFromAccount(undefined)).toBeNull();
});
