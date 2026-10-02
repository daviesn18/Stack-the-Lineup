// TelemetryDeck analytics, the web's counterpart to Analytics.swift.
//
// Signals go to the SAME TelemetryDeck app as iOS and reuse the iOS signal
// names and parameters, so one chart can show both; every web signal also
// carries platform=web so they can be split. Web-only signals are noted where
// they're sent.
//
// What differs from the Swift SDK:
//   * Nothing is automatic. This file sends TelemetryDeck.Session.started
//     itself (the name the Swift SDK uses), once per identified page load.
//   * The user is the coach's Supabase account id, hashed by the SDK before it
//     leaves the browser. Signed out, nothing is sent.
//   * Development builds and tests send nothing (as the iOS simulator sends
//     nothing). A production build on any host other than the live ones (a
//     Vercel preview, a local export) sends in TelemetryDeck's Test Mode.
//
// Analytics must never break the app: every failure (an ad blocker, no
// network, no crypto) is swallowed.

import TelemetryDeck from '@telemetrydeck/sdk';

const APP_ID = 'F6A09F00-2EFC-4DAD-9137-3350F267E78A';   // same app as iOS (LineupBuilderApp.swift)
const LIVE_HOSTS = ['app.stackthelineup.com', 'stack-the-lineup.vercel.app'];

export type SignalParameters = Record<string, string | number | boolean>;

let client: TelemetryDeck | null = null;
let currentUser: string | null = null;
// Counts kept in memory and attached to a later signal, for things too
// frequent to send one by one (each position assignment).
let tallies: Record<string, number> = {};
let lastTeamId: string | null = null;

/** False in development and tests, and wherever the SDK can't hash (no SubtleCrypto). */
const enabled = () => !__DEV__ && typeof globalThis.crypto?.subtle?.digest === 'function';

/** Test Mode unless the page is served from a live host. */
export const isTestHost = (hostname: string | undefined) => !hostname || !LIVE_HOSTS.includes(hostname);

/** The signed-in coach, or null when signed out. Starts a new session when the coach changes. */
export function setAnalyticsUser(userId: string | null) {
  if (userId === currentUser) return;
  currentUser = userId;
  client = null;
  tallies = {};
  lastTeamId = null;
  if (!userId || !enabled()) return;
  try {
    client = new TelemetryDeck({
      appID: APP_ID, clientUser: userId,
      testMode: isTestHost(globalThis.location?.hostname),
    });
  } catch {
    return;
  }
  signal('TelemetryDeck.Session.started');
}

/** Sends a signal. iOS sends every parameter as a string, so values are stringified the same way. */
export function signal(name: string, parameters: SignalParameters = {}) {
  if (!client) return;
  const payload: Record<string, string> = { platform: 'web' };
  for (const [k, v] of Object.entries(parameters)) payload[k] = String(v);
  try {
    client.signal(name, payload).catch(() => {});
  } catch { /* never let analytics break the app */ }
}

// MARK: - Tallies

export function tally(key: string) {
  tallies[key] = (tallies[key] ?? 0) + 1;
}

/** The counts under `prefix` (e.g. "assign"), keyed like assignDrag, and resets them. */
export function takeTallies(prefix: string): Record<string, number> {
  const out: Record<string, number> = {};
  for (const [k, n] of Object.entries(tallies)) {
    if (k.startsWith(`${prefix}.`)) {
      const rest = k.slice(prefix.length + 1);
      out[prefix + rest.charAt(0).toUpperCase() + rest.slice(1)] = n;
      delete tallies[k];
    }
  }
  return out;
}

// MARK: - Opening a team

/** A team finished loading: app.opened the first time in a page load, team.switched after that. */
export function teamOpened(teamId: string, playerCount: number) {
  if (lastTeamId === null) signal('app.opened', { playerCount });
  else if (lastTeamId !== teamId) signal('team.switched', { shared: false });
  lastTeamId = teamId;
}
