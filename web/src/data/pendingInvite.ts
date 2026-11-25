// Merge 4: an invite link opened before the coach was signed in. It waits
// here until they are, so they join without opening the link again:
//
//   * Apple and Google sign-in leave the page and come back to the site's root.
//   * An email sign-up made on the iPhone confirms in a new browser tab; that
//     account carries the token itself (user metadata `pending_invite`, see
//     iOS PendingInvite), read by `inviteFromAccount`.
//
// Kept in localStorage (new tabs see it) for 30 days. The team list sends the
// coach to /join?resume, which joins straight away.

const KEY = 'stl.pendingInvite';
const LIFETIME_MS = 30 * 24 * 3600 * 1000;
export const METADATA_KEY = 'pending_invite';

const store = (): Storage | null => (typeof window === 'undefined' ? null : window.localStorage);

export function rememberInvite(token: string, now = Date.now()) {
  try { store()?.setItem(KEY, JSON.stringify({ token, savedAt: now })); } catch { /* private mode: the coach opens the link again */ }
}

/** The waiting token, once: reading it clears it. Null when there's none or it's older than 30 days. */
export function takeInvite(now = Date.now()): string | null {
  try {
    const s = store();
    const raw = s?.getItem(KEY) ?? null;
    s?.removeItem(KEY);
    if (!raw) return null;
    const saved = JSON.parse(raw) as { token?: unknown; savedAt?: unknown };
    if (typeof saved.token !== 'string' || typeof saved.savedAt !== 'number') return null;
    return now - saved.savedAt < LIFETIME_MS ? saved.token : null;
  } catch {
    return null;
  }
}

export function forgetInvite() {
  try { store()?.removeItem(KEY); } catch { /* nothing to clear */ }
}

/** The token an email sign-up left on the account, if any. */
export function inviteFromAccount(metadata: Record<string, unknown> | undefined): string | null {
  const t = metadata?.[METADATA_KEY];
  return typeof t === 'string' && t ? t : null;
}
