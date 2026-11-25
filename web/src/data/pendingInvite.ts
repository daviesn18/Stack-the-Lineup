// Merge 4: an invite link opened while signed out. Apple and Google sign-in
// leave the page and come back to the site's root, so the token waits here
// (this tab only) and the team list sends the coach back to /join to finish.

const KEY = 'stl.pendingInvite';

const store = (): Storage | null => (typeof window === 'undefined' ? null : window.sessionStorage);

export function rememberInvite(token: string) {
  try { store()?.setItem(KEY, token); } catch { /* private mode: the coach opens the link again */ }
}

/** The waiting token, once: reading it clears it. */
export function takeInvite(): string | null {
  try {
    const s = store();
    const token = s?.getItem(KEY) ?? null;
    s?.removeItem(KEY);
    return token;
  } catch {
    return null;
  }
}

export function forgetInvite() {
  try { store()?.removeItem(KEY); } catch { /* nothing to clear */ }
}
