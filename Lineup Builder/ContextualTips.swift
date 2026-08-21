import SwiftUI
import TipKit

// MARK: - Contextual Tips
//
// The guided walkthrough. Two arcs:
//   Arc 1 (first launch)  — gets the coach to their first game.
//   Arc 2 (first archive) — gets them to their second.
//
// Tips are anchored to real controls with .tourTip(), ordered within a page by
// TipGroup, and gated by TourState parameters that mirror real app state. This
// file is the single source of truth for tour content; AppPage.tips in
// WelcomeView.swift remains the separate pull-help reference.
//
// Free vs Pro: every tip shows to every coach. Pro features carry a PRO badge
// that renders only for non-subscribers. No tour tip opens the paywall — the
// gated controls already do that when actually tapped.

// MARK: - Tour State
//
// TipKit parameters mirroring app state. Kept in sync by TourState.sync(),
// called from ContentView on appear and whenever the underlying data changes.

enum TourState {
    @Parameter static var hasPlayers: Bool = false
    @Parameter static var hasBattingOrder: Bool = false
    @Parameter static var hasPositions: Bool = false
    @Parameter static var hasArchivedGame: Bool = false
    @Parameter static var isPro: Bool = false

    /// Set when the coach skips the welcome cards. Drives the one tip that
    /// points at the Settings re-entry row.
    @Parameter static var welcomeSkipped: Bool = false

    static func sync(
        players: Int,
        battingOrder: Int,
        hasAnyAssignments: Bool,
        archivedGames: Int,
        isPro proValue: Bool
    ) {
        hasPlayers = players > 0
        hasBattingOrder = battingOrder > 0
        hasPositions = hasAnyAssignments
        hasArchivedGame = archivedGames > 0
        isPro = proValue
    }
}

// MARK: - Pro Badge
//
// Appended to the title of a Pro feature's tip, and only for coaches who don't
// have it. Labeling a feature PRO to someone who already pays reads as noise.

private func tourTitle(_ text: String, pro: Bool = false) -> Text {
    guard pro, !TourState.isPro else { return Text(text) }
    return Text(text)
        + Text("  PRO")
            .font(.caption2.weight(.black))
            .foregroundColor(.orange)
}

// MARK: - Shared Actions

private var nextAction: [Tip.Action] {
    [Tip.Action(id: "next", title: "Next")]
}

private var doneAction: [Tip.Action] {
    [Tip.Action(id: "done", title: "Got it")]
}

// MARK: - Arc 1 · Players

struct PlayersAddTip: Tip {
    var title: Text { tourTitle("Start with your roster") }
    var message: Text? {
        Text("Add players one at a time, or use Bulk Add to type the whole roster in one pass.")
    }
    var image: Image? { Image(systemName: "person.badge.plus") }
    var actions: [Action] { nextAction }
    var rules: [Rule] {
        [#Rule(TourState.$hasArchivedGame) { $0 == false }]
    }
}

struct PlayersImportTip: Tip {
    var title: Text { tourTitle("Already have it in a file?") }
    var message: Text? {
        Text("Import Roster pulls names, numbers, and position preferences from a GameChanger CSV.")
    }
    var image: Image? { Image(systemName: "square.and.arrow.down") }
    var actions: [Action] { nextAction }
    var rules: [Rule] {
        [#Rule(TourState.$hasArchivedGame) { $0 == false }]
    }
}

struct PlayersTeamSetupTip: Tip {
    var title: Text { tourTitle("Set up your team") }
    var message: Text? {
        Text("Tap your team name for color, game length, and your league's fair play rules. Name and color print on every PDF.")
    }
    var image: Image? { Image(systemName: "paintpalette.fill") }
    var actions: [Action] { nextAction }
    var rules: [Rule] {
        [#Rule(TourState.$hasArchivedGame) { $0 == false }]
    }
}

struct PlayersPreferencesTip: Tip {
    var title: Text { tourTitle("Tag what each player can handle", pro: true) }
    var message: Text? {
        Text("Strength, Capable, Emergency, Never. Auto-Fill works down that list — Never is never assigned.")
    }
    var image: Image? { Image(systemName: "star.circle.fill") }
    var actions: [Action] { doneAction }
    var rules: [Rule] {
        [
            #Rule(TourState.$hasPlayers) { $0 == true },
            #Rule(TourState.$hasArchivedGame) { $0 == false },
        ]
    }
}

// MARK: - Arc 1 · Lineup
//
// Templates are deliberately absent here — you can't reuse a lineup you haven't
// built yet. They open arc 2.

struct LineupGameInfoTip: Tip {
    var title: Text { tourTitle("Set the game") }
    var message: Text? {
        Text("Tap to set date and opponent, or pull one straight from your imported schedule.")
    }
    var image: Image? { Image(systemName: "calendar.badge.plus") }
    var actions: [Action] { nextAction }
    var rules: [Rule] {
        [
            #Rule(TourState.$hasPlayers) { $0 == true },
            #Rule(TourState.$hasArchivedGame) { $0 == false },
        ]
    }
}

struct LineupBattingOrderTip: Tip {
    var title: Text { tourTitle("Build the order") }
    var message: Text? {
        Text("Tap + to add a player. Tap Edit, then drag the handle to reorder.")
    }
    var image: Image? { Image(systemName: "arrow.up.arrow.down") }
    var actions: [Action] { nextAction }
    var rules: [Rule] {
        [
            #Rule(TourState.$hasPlayers) { $0 == true },
            #Rule(TourState.$hasArchivedGame) { $0 == false },
        ]
    }
}

struct LineupAbsentTip: Tip {
    var title: Text { tourTitle("Someone out today?") }
    var message: Text? {
        Text("The toggle marks a player out for the whole game and pulls them from every inning.")
    }
    var image: Image? { Image(systemName: "person.slash") }
    var actions: [Action] { nextAction }
    var rules: [Rule] {
        [
            #Rule(TourState.$hasBattingOrder) { $0 == true },
            #Rule(TourState.$hasArchivedGame) { $0 == false },
        ]
    }
}

/// The clearest tier contrast in the app — one free export, one Pro, side by side.
struct LineupExportTip: Tip {
    var title: Text { tourTitle("Hand it out") }
    var message: Text? {
        Text("Batting Order PDF is free. Coaches Guide adds the full inning-by-inning grid for the dugout.")
    }
    var image: Image? { Image(systemName: "doc.richtext") }
    var actions: [Action] { doneAction }
    var rules: [Rule] {
        [
            #Rule(TourState.$hasBattingOrder) { $0 == true },
            #Rule(TourState.$hasArchivedGame) { $0 == false },
        ]
    }
}

// MARK: - Arc 1 · Positions

struct PositionsViewModeTip: Tip {
    var title: Text { tourTitle("Two ways to look at it") }
    var message: Text? {
        Text("By Inning walks one inning at a time. Summary shows the whole game in one grid.")
    }
    var image: Image? { Image(systemName: "tablecells") }
    var actions: [Action] { nextAction }
    var rules: [Rule] {
        [
            #Rule(TourState.$hasBattingOrder) { $0 == true },
            #Rule(TourState.$hasArchivedGame) { $0 == false },
        ]
    }
}

struct PositionsAssignTip: Tip {
    var title: Text { tourTitle("Assign anyone") }
    var message: Text? {
        Text("Tap any player or open slot to set their position for that inning.")
    }
    var image: Image? { Image(systemName: "hand.tap.fill") }
    var actions: [Action] { nextAction }
    var rules: [Rule] {
        [
            #Rule(TourState.$hasBattingOrder) { $0 == true },
            #Rule(TourState.$hasArchivedGame) { $0 == false },
        ]
    }
}

struct PositionsAutoFillTip: Tip {
    var title: Text { tourTitle("Fill it in one tap", pro: true) }
    var message: Text? {
        Text("Auto-Fill covers one inning or the whole game, fair play rules included.")
    }
    var image: Image? { Image(systemName: "bolt.fill") }
    var actions: [Action] { nextAction }
    var rules: [Rule] {
        [
            #Rule(TourState.$hasBattingOrder) { $0 == true },
            #Rule(TourState.$hasArchivedGame) { $0 == false },
        ]
    }
}

/// Closes arc 1. The coach has a complete game at this point.
struct PositionsWarningsTip: Tip {
    var title: Text { tourTitle("Check before you go") }
    var message: Text? {
        Text("The warnings icon lists everything open, doubled up, or against your rules. Then finalize.")
    }
    var image: Image? { Image(systemName: "exclamationmark.triangle.fill") }
    var actions: [Action] { doneAction }
    var rules: [Rule] {
        [
            #Rule(TourState.$hasPositions) { $0 == true },
            #Rule(TourState.$hasArchivedGame) { $0 == false },
        ]
    }
}

// MARK: - Arc 2 · Second game
//
// Fires on first archive. One idea: you don't have to build this from scratch
// again. The route forks by tier — reuse-from-archive is Pro, but the first
// template is free for everyone (GameLogDetailView.attemptSaveAsTemplate).

/// Anchored inside `GameLogDetailView`, which a free coach can't reach — game
/// detail is Pro, and on the History teaser the visible game row taps through
/// to the paywall instead. So this tip is Pro-gated and lives in the `history`
/// group. A free coach's arc-2 save-template path is the Positions "Save as
/// Template" banner, not this History copy; guiding them here would dead-end at
/// a paywall, and as the lead tip of an ordered group an unreachable anchor
/// stalls the whole group (see [[tipkit-toolbar-anchor-fails]] for the same
/// failure mode).
struct ReuseSaveTemplateTip: Tip {
    var title: Text { tourTitle("Don't build that twice") }
    var message: Text? {
        Text("Save this game as a template and rebuild it next week in one tap.")
    }
    var image: Image? { Image(systemName: "square.stack.3d.up") }
    var actions: [Action] { nextAction }
    var rules: [Rule] {
        [
            #Rule(TourState.$hasArchivedGame) { $0 == true },
            #Rule(TourState.$isPro) { $0 == true },
        ]
    }
}

struct ReuseApplyTemplateTip: Tip {
    var title: Text { tourTitle("Game two in one tap") }
    var message: Text? {
        Text("Pick your template when you set the next game — batting order and locked positions come back with it.")
    }
    var image: Image? { Image(systemName: "square.stack.3d.up.fill") }
    var actions: [Action] { doneAction }
    var rules: [Rule] {
        [#Rule(TourState.$hasArchivedGame) { $0 == true }]
    }
}

/// History-anchored. Never fires for free coaches — the `isPro` rule gates it,
/// and its game-detail anchor sits behind the paywall on the teaser.
struct HistoryCopyGameTip: Tip {
    var title: Text { tourTitle("Or start from a game you played", pro: true) }
    var message: Text? {
        Text("Open any archived game and copy its lineup into today's. It lands on the Lineup tab ready to adjust.")
    }
    var image: Image? { Image(systemName: "arrow.uturn.down") }
    var actions: [Action] { nextAction }
    var rules: [Rule] {
        [
            #Rule(TourState.$hasArchivedGame) { $0 == true },
            #Rule(TourState.$isPro) { $0 == true },
        ]
    }
}

struct HistorySeasonViewsTip: Tip {
    var title: Text { tourTitle("Your season is building", pro: true) }
    var message: Text? {
        Text("Players for season stats, Team for roster coverage, Games for the archive. Insights appear after two games.")
    }
    var image: Image? { Image(systemName: "rectangle.3.group") }
    var actions: [Action] { doneAction }
    var rules: [Rule] {
        [
            #Rule(TourState.$hasArchivedGame) { $0 == true },
            #Rule(TourState.$isPro) { $0 == true },
        ]
    }
}

struct AutoFillConstraintsTip: Tip {
    var title: Text { tourTitle("Tell Auto-Fill what you want", pro: true) }
    var message: Text? {
        Text("\"Jack pitches 3 and 4, keep Maya off catcher.\" It works around your instructions and says so if it can't.")
    }
    var image: Image? { Image(systemName: "text.bubble") }
    var actions: [Action] { doneAction }
    var rules: [Rule] {
        [#Rule(TourState.$hasArchivedGame) { $0 == true }]
    }
}

/// Arc 2 rather than arc 1, and on purpose.
///
/// Every voice action is worth more to a coach who already has a season going:
/// Game Recap needs an archived game to recap, and the pitching answers need
/// recorded pitch counts to be about anything. Arc 1 is a tight path to a first
/// game and doesn't need a second way to do things in it.
///
/// Shares the bolt with `PositionsAutoFillTip` (arc 1) and
/// `AutoFillConstraintsTip` (arc 2), which is the natural progression on one
/// control: here's the button, here's what you can tell it, here's how to skip
/// the button entirely.
struct AskSiriTip: Tip {
    var title: Text { tourTitle("Or just ask") }
    var message: Text? {
        Text("\"Hey Siri, fill my lineup in Stack the Lineup.\" Siri can also recap your last game and check whether a pitcher is rested. The full list is in Settings.")
    }
    var image: Image? { Image(systemName: "mic.fill") }
    var actions: [Action] { doneAction }
    var rules: [Rule] {
        [#Rule(TourState.$hasArchivedGame) { $0 == true }]
    }
}

struct ShareTeamTip: Tip {
    var title: Text { tourTitle("Bring in an assistant", pro: true) }
    var message: Text? {
        Text("Invite another coach to build positions with you. You still finalize.")
    }
    var image: Image? { Image(systemName: "person.2.wave.2") }
    var actions: [Action] { doneAction }
    var rules: [Rule] {
        [#Rule(TourState.$hasArchivedGame) { $0 == true }]
    }
}

// MARK: - Re-entry
//
// The only tip that fires as a consequence of dismissal rather than navigation.
// Shown once to a coach who skipped the welcome cards.

struct TourInSettingsTip: Tip {
    var title: Text { tourTitle("Changed your mind?") }
    var message: Text? {
        Text("Take the Tour lives in Settings, under Help & Support.")
    }
    var image: Image? { Image(systemName: "figure.walk.motion") }
    var actions: [Action] { doneAction }
    var rules: [Rule] {
        [#Rule(TourState.$welcomeSkipped) { $0 == true }]
    }
    var options: [TipOption] { [Tips.MaxDisplayCount(1)] }
}

// MARK: - Tour Groups
//
// Ordered per page, independent across pages. A page-scoped group means a tip
// whose anchor lives inside a sheet the coach never opens can't stall the tips
// on other tabs — sheet-anchored tips are always ordered last within their page.

enum Tour {
    static let players = TipGroup(.ordered) {
        PlayersAddTip()
        PlayersImportTip()
        PlayersTeamSetupTip()
        PlayersPreferencesTip()
    }

    static let lineup = TipGroup(.ordered) {
        LineupGameInfoTip()
        LineupBattingOrderTip()
        LineupAbsentTip()
        LineupExportTip()
    }

    static let positions = TipGroup(.ordered) {
        PositionsViewModeTip()
        PositionsAssignTip()
        PositionsAutoFillTip()
        PositionsWarningsTip()
    }

    // AskSiriTip follows AutoFillConstraintsTip because they share the bolt
    // anchor and read as one thought there. ShareTeamTip stays last: its anchor
    // is elsewhere, and an ordered group shouldn't leave the page mid-arc.
    static let secondGame = TipGroup(.ordered) {
        ReuseApplyTemplateTip()
        AutoFillConstraintsTip()
        AskSiriTip()
        ShareTeamTip()
    }

    // `ReuseSaveTemplateTip` and `HistoryCopyGameTip` both anchor in
    // `GameLogDetailView` (Pro-only, behind the History paywall), so the
    // save-template tip is grouped here rather than in `secondGame` — keeping
    // it out of the free coach's ordered arc-2 path, where its unreachable
    // anchor would stall every tip behind it.
    //
    // Order follows a Pro coach's navigation: the season-views tip anchors on
    // the History *list* picker (seen first), then opening a game reveals the
    // two game-*detail* tips in on-screen row order (Copy above Save). Leading
    // with a detail-anchored tip would stall the group on the list, where its
    // anchor isn't on screen.
    static let history = TipGroup(.ordered) {
        HistorySeasonViewsTip()
        HistoryCopyGameTip()
        ReuseSaveTemplateTip()
    }
}

// MARK: - Anchor Modifier
//
// One entry point for every anchored tip, so action handling and analytics
// stay in a single place. Pass the group's currentTip cast to the tip type
// that belongs on this control:
//
//     .tourTip(Tour.players.currentTip as? PlayersAddTip)

// Cross-platform "hold the tour until the welcome / what's-new covers are gone"
// gate. `ContentView` sets it once at the root for both the iPhone tab bar and
// the iPad dashboard; it defaults to `true` so previews and any unhosted view
// behave normally. This is what keeps arc-1 tips from presenting over the
// welcome cards on iPad, where the dashboard's own anchors don't carry the
// iPhone's per-tab `enabled:` gate. On iPhone it's redundant with the
// `tourEnabled` folded into `isTourTabActive`, and harmlessly ANDs with it.
private struct TourActiveKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var tourActive: Bool {
        get { self[TourActiveKey.self] }
        set { self[TourActiveKey.self] = newValue }
    }
}

extension View {
    /// - Parameter enabled: pass `false` to stand this anchor down. Used by the
    ///   views the iPad dashboard embeds (PlayersView, LineupView): the sidebar
    ///   is always on screen and carries its own anchor for the same tip, so the
    ///   embedded copy would double-fire whenever that detail tab is selected.
    ///   ANDed with the environment's `tourActive` welcome gate.
    func tourTip<T: Tip>(_ tip: T?, arrowEdge: Edge = .top, enabled: Bool = true) -> some View {
        modifier(TourTipModifier(tip: tip, arrowEdge: arrowEdge, enabled: enabled))
    }
}

private struct TourTipModifier<T: Tip>: ViewModifier {
    let tip: T?
    let arrowEdge: Edge
    let enabled: Bool
    @Environment(\.tourActive) private var tourActive

    func body(content: Content) -> some View {
        content.popoverTip((enabled && tourActive) ? tip : nil, arrowEdge: arrowEdge) { action in
            Analytics.signal("tour.tip.action", parameters: [
                "tip": String(describing: T.self),
                "action": action.id,
            ])
            tip?.invalidate(reason: .actionPerformed)
        }
    }
}

// MARK: - Configuration & Migration

enum TipsConfigurator {

    /// UserDefaults keys from the pre-TipKit onboarding. Read once during
    /// migration, then left alone — SettingsView's reset now clears the
    /// TipKit datastore instead.
    private static let legacyKeys = [
        "hasCompletedChecklist",
        "hasSeenAutoFillTip",
        "hasSeenPDFExportTip",
        "hasSeenScheduleImportTip",
        "hasSeenRosterImportTip",
    ]

    private static let migrationKey = "didMigrateToTipKit"

    /// Set by `restartTour()`, consumed by `configure()` on the next launch.
    /// See `restartTour()` for why the reset can't happen inline.
    private static let pendingResetKey = "tourPendingDatastoreReset"

    /// Call once at launch, before any tip can be displayed.
    static func configure() {
        migrateLegacyFlagsIfNeeded()
        applyPendingDatastoreResetIfNeeded()
        try? Tips.configure([
            .displayFrequency(.immediate),
            .datastoreLocation(.applicationDefault),
        ])
        if arcOneSuppressed { suppressArcOne() }
    }

    /// Applies a "Take the Tour" reset requested during a previous session.
    ///
    /// Has to run before `Tips.configure()`. Resetting from a live, already
    /// configured session does *not* stick: the call itself succeeds (it does
    /// not throw — that was measured, not assumed), but the running TipKit
    /// instance still holds every tip's status in memory and persists it again,
    /// so the cleared store is repopulated and nothing replays. Doing it here,
    /// before configure, there is no live instance to undo the wipe.
    ///
    /// The flag is cleared whether or not the reset succeeds, so a datastore
    /// that refuses to clear can't wedge the app into resetting on every launch.
    /// Failures are reported rather than swallowed — the original bug hid under
    /// a `try?` and left "Take the Tour" doing nothing with no signal anywhere.
    private static func applyPendingDatastoreResetIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: pendingResetKey) else { return }
        defaults.set(false, forKey: pendingResetKey)

        do {
            try Tips.resetDatastore()
            Analytics.signal("tour.reset.applied")
        } catch {
            Analytics.signal("tour.reset.failed", parameters: [
                "error": String(describing: error),
            ])
        }
    }

    /// Retires every arc-1 tip. Invalidation is keyed by tip type, so throwaway
    /// instances are the documented way to do this.
    private static func suppressArcOne() {
        PlayersAddTip().invalidate(reason: .actionPerformed)
        PlayersImportTip().invalidate(reason: .actionPerformed)
        PlayersTeamSetupTip().invalidate(reason: .actionPerformed)
        PlayersPreferencesTip().invalidate(reason: .actionPerformed)
        LineupGameInfoTip().invalidate(reason: .actionPerformed)
        LineupBattingOrderTip().invalidate(reason: .actionPerformed)
        LineupAbsentTip().invalidate(reason: .actionPerformed)
        LineupExportTip().invalidate(reason: .actionPerformed)
        PositionsViewModeTip().invalidate(reason: .actionPerformed)
        PositionsAssignTip().invalidate(reason: .actionPerformed)
        PositionsAutoFillTip().invalidate(reason: .actionPerformed)
        PositionsWarningsTip().invalidate(reason: .actionPerformed)
    }

    /// A coach who was already using the app shouldn't be walked through it
    /// again. If they'd seen the old onboarding — or simply have real data —
    /// arc 1 is suppressed wholesale. This replaces the five hand-written
    /// grandfathering blocks that used to live in ContentView.onAppear.
    private static func migrateLegacyFlagsIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: migrationKey) else { return }
        defaults.set(true, forKey: migrationKey)

        let sawOldOnboarding = legacyKeys.contains { defaults.bool(forKey: $0) }
        let completedTutorial = defaults.bool(forKey: "hasCompletedTutorial")

        guard sawOldOnboarding || completedTutorial else { return }
        defaults.set(true, forKey: "didSkipArcOne")
    }

    /// True when arc 1 should never run — an existing coach mid-season.
    static var arcOneSuppressed: Bool {
        UserDefaults.standard.bool(forKey: "didSkipArcOne")
    }

    /// Backs the "Take the Tour" row in Settings.
    ///
    /// TipKit has no per-tip "un-invalidate", so wiping the datastore is the
    /// only way to make retired tips eligible again. Resetting inline from here
    /// looks like it works but doesn't: TipKit is already configured and live,
    /// and it writes its in-memory tip statuses back over the cleared store.
    /// So we only record the intent; `configure()` performs the actual reset on
    /// the next launch, before TipKit is configured. Callers must still tell the
    /// coach to reopen the app.
    static func restartTour() {
        UserDefaults.standard.set(false, forKey: "didSkipArcOne")
        UserDefaults.standard.set(true, forKey: pendingResetKey)
        TourState.welcomeSkipped = false
        Analytics.signal("tour.restarted")
    }
}
