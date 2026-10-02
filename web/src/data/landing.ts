// Where a coach lands after signing in (or opening the app): with exactly one
// team, straight into it; otherwise the team list, to pick one.
//
// Only the first screen of a visit auto-opens. Once the coach has been inside
// the app (a team, the import page, or a team list they were shown), "All
// teams" must show the list even when it holds a single team, or there would
// be no way to reach New team and Import. Signing out starts a new visit.

let landed = false;

export const hasLanded = () => landed;
export const markLanded = () => { landed = true; };
export const resetLanding = () => { landed = false; };

/** The team to open instead of showing the list, if this is the landing and there is exactly one. */
export function teamToAutoOpen<T extends { id: string }>(teams: T[]): T | null {
  const only = !landed && teams.length === 1 ? teams[0] : null;
  landed = true;
  return only;
}
