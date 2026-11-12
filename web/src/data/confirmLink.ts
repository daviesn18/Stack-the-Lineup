// Auth email links on our own domain: app.stackthelineup.com/auth/confirm?
// token_hash=…&type=…, instead of the supabase.co verify link. The email
// templates (supabase/templates) build the link; the confirm page calls
// verifyOtp with it. Two wins: the link matches the sender's domain (spam
// filters weigh that), and a mail scanner that opens the link without running
// JavaScript can't use up the one-time token.

/** The email kinds our templates link here, as verifyOtp names them. */
export type ConfirmType = 'invite' | 'recovery' | 'email' | 'email_change';

const TYPES: readonly ConfirmType[] = ['invite', 'recovery', 'email', 'email_change'];

export const CONFIRM_PATH = '/auth/confirm';

/** The token and kind from a confirm link, or null when this isn't one. */
export function parseConfirmLink(pathname: string, search: string): { tokenHash: string; type: ConfirmType } | null {
  if (pathname.replace(/\/+$/, '') !== CONFIRM_PATH) return null;
  const p = new URLSearchParams(search.startsWith('?') ? search.slice(1) : search);
  const tokenHash = p.get('token_hash')?.trim();
  const type = p.get('type') as ConfirmType | null;
  if (!tokenHash || !type || !TYPES.includes(type)) return null;
  return { tokenHash, type };
}

/** Invite and reset links end on Choose a password; the others go straight into the app. */
export const needsPassword = (type: ConfirmType) => type === 'invite' || type === 'recovery';
