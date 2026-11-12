// Free vs Pro on the web, matching iOS (PurchaseManager.isPro call sites and
// PaywallView's feature list). Pure, so the whole table is unit-tested.
//
// Multiple Teams is free on iOS (taken out of Pro in July 2026), so it isn't
// here. AI Coaching Insights is Pro but has no web feature yet.

/** The paywall sources iOS sends with paywall.shown, plus the two iOS gates that only hide UI. */
export type ProFeature =
  | 'autofill'            // Auto-Fill, including instructions
  | 'player_preferences'  // Position Preferences and Hitting Archetypes
  | 'lineup_template'     // more than one template (templates aren't on web yet: Web 12)
  | 'pdf_export'          // Coaches Guide PDF; the lineup card stays free
  | 'shared_teams'        // inviting a coach (sharing isn't on web yet: Web 14)
  | 'game_history'        // Season stats and the game log
  | 'pitch_tracking';     // entering pitch counts; pitching rules stay free

/** 'loading' while the entitlement is unknown: show neither state, so a Pro coach never sees a lock flash (iOS showsLockedUI). */
export type Entitlement = 'pro' | 'free' | 'loading';

/** open: use it. locked: show the lock and open the paywall. pending: render nothing yet. */
export type GateState = 'open' | 'locked' | 'pending';

export interface GateContext {
  /** Templates the team already has; the first one is free. */
  templateCount?: number;
  /** A team another coach shared with this coach, read-only. */
  receivedReadOnly?: boolean;
}

export function gate(feature: ProFeature, entitlement: Entitlement, ctx: GateContext = {}): GateState {
  if (entitlement === 'pro') return 'open';
  // Free exceptions iOS makes for everyone, so they don't wait on the entitlement.
  if (feature === 'lineup_template' && (ctx.templateCount ?? 0) === 0) return 'open';
  if (feature === 'pdf_export' && ctx.receivedReadOnly) return 'open';
  return entitlement === 'loading' ? 'pending' : 'locked';
}

/** The paywall list, in iOS PaywallView's order and words. */
export const PAYWALL_GROUPS: { title: string; features: { id: string; icon: string; color: string; title: string; text: string }[] }[] = [
  {
    title: 'Build lineups faster',
    features: [
      { id: 'autofill', icon: 'bolt.fill', color: 'blue', title: 'Auto-Fill Positions', text: 'Fill an inning or the whole game in one click, fair play rules included.' },
      { id: 'player_preferences', icon: 'star.fill', color: 'green', title: 'Position Preferences', text: 'Tag what each player can handle. Auto-Fill places them accordingly.' },
      { id: 'lineup_template', icon: 'square.stack.3d.up.fill', color: 'blue', title: 'Lineup Templates', text: 'Save a lineup and rebuild it next week in one click.' },
    ],
  },
  {
    title: 'Share it with your coaches and parents',
    features: [
      { id: 'pdf_export', icon: 'doc.richtext.fill', color: 'blue', title: 'Coaches Guide PDF', text: 'The full inning-by-inning grid, printed for the dugout.' },
      { id: 'shared_teams', icon: 'person.3.fill', color: 'green', title: 'Shared Teams', text: 'Invite an assistant coach to build positions with you.' },
    ],
  },
  {
    title: 'Track the whole season',
    features: [
      { id: 'game_history', icon: 'clock.arrow.circlepath', color: 'purple', title: 'Game History', text: 'Archive every game and keep a season record.' },
      { id: 'pitch_tracking', icon: 'figure.baseball.pitcher', color: 'red', title: 'Pitch Count Tracking', text: 'Weekly limits and rest days by age, checked as you assign.' },
    ],
  },
];
