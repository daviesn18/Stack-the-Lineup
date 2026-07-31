import AppIntents
import Foundation

// MARK: - Fill Lineup
//
// "Hey Siri, fill 3 innings, start Caleb pitching."
//
// Pro, matching the bolt button's gate in DefensiveGridView and the iPad
// summary pane. Gating happens on PurchaseManager.isProNow() rather than the
// @EnvironmentObject PurchaseManager, which an intent can't reach.
//
// Why this opens the app: a fill rewrites up to seven innings of assignments,
// and no spoken sentence conveys that well enough for a coach to trust it
// unseen. Siri says what changed; the grid shows it.
//
// Why the app applies the lineup rather than this intent writing it:
// LineupStore holds the authoritative in-memory copy whenever the app is
// running, and its next save() would silently overwrite anything written to
// UserDefaults behind its back. So perform() computes against the on-disk team
// via TeamStorage, stages the finished lineup on AppRouter, and ContentView —
// which owns the store — applies it. Computing here rather than deferring the
// whole operation is what lets the dialog report a real result instead of
// "opening the app".

struct FillLineupIntent: AppIntent {

    static let title: LocalizedStringResource = "Fill Lineup"

    static let description = IntentDescription(
        "Auto-fills open defensive positions using position preferences and fair-play rules.",
        categoryName: "Lineup",
        searchKeywords: ["auto-fill", "fill", "positions", "defense", "lineup"]
    )

    static let openAppWhenRun = true

    @Parameter(
        title: "Team",
        description: "Leave empty to use the team you're currently coaching."
    )
    var team: TeamEntity?

    @Parameter(
        title: "Through Inning",
        description: "Fill innings 1 through this one. Leave empty for the whole game.",
        // Must be a literal — @Parameter rejects `Lineup.inningCount` here.
        // lastInningIndex(for:requested:) clamps to the real inning count
        // anyway, so a drifted ceiling costs a picker row, not a crash.
        inclusiveRange: (1, 7)
    )
    var throughInning: Int?

    @Parameter(
        title: "Instructions",
        description: "Optional adjustments, e.g. \"Caleb pitches the first 2 innings\"."
    )
    var instructions: String?

    init() {}

    init(team: TeamEntity? = nil, throughInning: Int? = nil, instructions: String? = nil) {
        self.team = team
        self.throughInning = throughInning
        self.instructions = instructions
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Fill positions through inning \(\.$throughInning) for \(\.$team)") {
            \.$instructions
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Not Pro: show the paywall rather than throwing. `openAppWhenRun` has
        // already brought the app forward by the time this returns either way,
        // so a thrown error would leave the coach on whatever tab was last open
        // with nothing explaining why nothing happened.
        guard await PurchaseManager.isProNow() else {
            Analytics.signal("intent.fill_lineup.blocked_not_pro")
            AppRouter.shared.requestPaywall(source: "intent_fill_lineup")
            return .result(dialog: "Auto-Fill is part of Pro. I've opened the upgrade options for you.")
        }

        let (teams, activeTeam) = TeamStorage.loadTeamsForReading()
        let target: Team?
        if let requested = team {
            target = teams.first { $0.id == requested.id }
        } else {
            target = activeTeam
        }
        guard let target else { throw STLIntentError.noTeam }

        // A read-only shared team can't be written back, so filling it would
        // produce a lineup that silently vanishes on the next sync.
        guard !target.isReadOnly else { throw STLIntentError.teamIsReadOnly }

        guard !target.lineup.activePlayers(from: target.players).isEmpty else {
            throw STLIntentError.noActivePlayers(teamName: target.name)
        }

        let scope = AutoFillScope.through(Self.lastInningIndex(for: target, requested: throughInning))

        let coordinator = AutoFillCoordinator()
        let outcome = await coordinator.run(
            scope: scope,
            prompt: instructions ?? "",
            team: target
        )

        Analytics.signal("intent.fill_lineup", parameters: [
            "filledCount": "\(outcome.filledCount)",
            "hadInstructions": instructions?.isEmpty == false ? "true" : "false"
        ])

        // Nothing changed — don't stage a write, and don't yank the coach to
        // the Positions tab for a no-op.
        guard outcome.didFill else {
            return .result(dialog: IntentDialog(stringLiteral: outcome.spokenSummary))
        }

        AppRouter.shared.stageFill(outcome, teamID: target.id)
        AppRouter.shared.route(to: .positions)

        return .result(dialog: IntentDialog(stringLiteral: outcome.spokenSummary))
    }

    /// Zero-based last inning to fill.
    ///
    /// Defaults to the team's configured game length rather than the UI's
    /// "last inning that already has assignments" — a coach asking by voice
    /// with no inning named wants the game filled, whereas the popover's
    /// default exists to preselect a picker the coach can still adjust.
    /// Clamped to the innings that actually exist so a 9 from Siri on a
    /// 7-inning game fills 7 instead of throwing.
    static func lastInningIndex(for team: Team, requested: Int?) -> Int {
        let available = team.lineup.innings.count
        let requestedCount = requested ?? team.gameInningCount
        return min(max(requestedCount, 1), available) - 1
    }
}

// MARK: - Intent Errors
//
// App Intents surfaces `localizedStringResource` as the spoken and displayed
// failure, so each case has to read as a complete sentence to a coach standing
// at a dugout fence — not as a developer-facing error.

enum STLIntentError: Error, CustomLocalizedStringResourceConvertible {
    case noTeam
    case teamIsReadOnly
    case noActivePlayers(teamName: String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noTeam:
            return "I couldn't find that team in Stack the Lineup."
        case .teamIsReadOnly:
            return "You're only viewing that team, so I can't change its lineup."
        case .noActivePlayers(let teamName):
            return "No one is marked active on \(teamName), so there's nothing to fill."
        }
    }
}
