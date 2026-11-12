// What a coach sees when an Apple or Google sign-in comes back without signing
// them in. Kept apart from the sign-in page so it can be unit-tested.

/** The coach-facing reason an Apple or Google sign-in came back without signing in. */
export function oauthMessage(e: { code: string; description: string } | null): string | null {
  if (!e) return null;
  if (e.code === 'signup_disabled' || /signups? not allowed/i.test(e.description)) {
    return "That Apple or Google account isn't linked to a Stack the Lineup account yet. "
      + 'The web is invite-only for now: sign in with the email address your invite went to.';
  }
  if (e.code === 'access_denied' || /cancel/i.test(e.description)) return null;   // the coach backed out; nothing to explain
  return e.description ? `Sign-in didn't finish: ${e.description}` : "Sign-in didn't finish. Try again.";
}
