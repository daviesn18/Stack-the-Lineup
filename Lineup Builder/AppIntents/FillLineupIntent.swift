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

    static var supportedModes: IntentModes { .foreground }

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
        // Not Pro: show the paywall rather than throwing. `supportedModes` is
        // `.foreground`, so the app has already been brought forward by the time
        // this returns either way,
        // so a thrown error would leave the coach on whatever tab was last open
        // with nothing explaining why nothing happened.
        guard await PurchaseManager.isProNow() else {
            Analytics.signal("intent.fill_lineup.blocked_not_pro")
            AppRouter.shared.requestPaywall(source: "intent_fill_lineup")
            return .result(dialog: "Auto-Fill is part of Pro. I've opened the upgrade options for you.")
        }

        let (teams, activeTeam) = TeamStorage.loadTeamsForReading()
        var target: Team
        if let requested = team {
            guard let match = teams.first(where: { $0.id == requested.id }) else {
                throw STLIntentError.noTeam
            }
            target = match
        } else if let activeTeam {
            target = activeTeam
        } else {
            throw STLIntentError.noTeam
        }

        // A read-only shared team can't be written back, so filling it would
        // produce a lineup that silently vanishes on the next sync. This is
        // reachable in practice — the active team is a common shape for a coach
        // who also has a view-only share of someone else's roster. When the
        // read-only team was the active *default* (not named this run), redirect
        // to the coach's writable teams rather than dead-ending; a team the
        // coach named explicitly is honored, not swapped (see readOnlyFallback).
        var redirectNote = ""
        if target.isReadOnly {
            switch Self.readOnlyFallback(explicitlyNamed: team != nil,
                                         writableTeams: teams.filter { !$0.isReadOnly }) {
            case .throwReadOnly:
                throw STLIntentError.teamIsReadOnly
            case .useOnly(let only):
                // Silent redirect from the active view-only team to the coach's
                // one writable team. Name it, because AutoFillOutcome.spokenSummary
                // doesn't — otherwise the reply sounds like it filled the team
                // the coach was looking at.
                target = only
                redirectNote = "Your other team \(only.name) is the one I can edit. "
            case .askAmong(let candidates):
                // requestDisambiguation is a real, interactive Siri/Shortcuts
                // prompt — AppIntentsTesting's out-of-process harness can't
                // drive it (fails with AppIntentsServicesExecutionErrorDomain
                // 206, "not supported by the default delegate"), so this call
                // itself is exercised by manual verification, not automation.
                // readOnlyFallback(writableTeams:) above covers the branching.
                let chosen = try await $team.requestDisambiguation(
                    among: candidates.map(TeamEntity.init),
                    dialog: "Which team should I fill?"
                )
                guard let match = teams.first(where: { $0.id == chosen.id }) else {
                    throw STLIntentError.noTeam
                }
                target = match
            }
        }

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
            return .result(dialog: IntentDialog(stringLiteral: redirectNote + outcome.spokenSummary))
        }

        AppRouter.shared.stageFill(outcome, teamID: target.id)
        AppRouter.shared.route(to: .positions)

        return .result(dialog: IntentDialog(stringLiteral: redirectNote + outcome.spokenSummary))
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

    /// What to do once the resolved team turns out to be read-only. A pure
    /// function so this branching is unit-testable without AppIntentsTesting,
    /// which can't drive the interactive `requestDisambiguation` case (see the
    /// comment where `.askAmong` is handled in `perform()`).
    enum ReadOnlyFallback {
        case throwReadOnly
        case useOnly(Team)
        case askAmong([Team])
    }

    static func readOnlyFallback(explicitlyNamed: Bool, writableTeams: [Team]) -> ReadOnlyFallback {
        // An explicitly named team is honored, never silently swapped. A coach
        // who said "fill the Eagles" (a view-only share) should be told it's
        // view-only — not have a different team filled behind their back. The
        // redirect only kicks in when the read-only team was the *active*
        // default the coach didn't choose for this run.
        if explicitlyNamed { return .throwReadOnly }
        switch writableTeams.count {
        case 0: return .throwReadOnly
        case 1: return .useOnly(writableTeams[0])
        default: return .askAmong(writableTeams)
        }
    }
}

// MARK: - Intent Errors
//
// App Intents surfaces `localizedStringResource` as the spoken and displayed
// failure, so each case has to read as a complete sentence to a coach standing
// at a dugout fence — not as a developer-facing error.

enum STLIntentError: Error, CustomLocalizedStringResourceConvertible {
    /// Only for intents that **don't** open the app — see 4c in the handoff.
    /// `FillLineupIntent` routes to the paywall instead, because throwing there
    /// would leave the coach looking at an app that opened and did nothing.
    case needsPro(feature: String)
    case noTeam
    case teamIsReadOnly
    case noActivePlayers(teamName: String)
    case noGames(teamName: String)
    case noSuchGame
    case noSuchPlayer

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .needsPro(let feature):
            return "\(feature) are part of Pro. Open Stack the Lineup to upgrade."
        case .noTeam:
            return "I couldn't find that team in Stack the Lineup."
        case .teamIsReadOnly:
            return "You're only viewing that team, so I can't change its lineup."
        case .noActivePlayers(let teamName):
            return "No one is marked active on \(teamName), so there's nothing to fill."
        case .noGames(let teamName):
            return "\(teamName) doesn't have any archived games yet."
        case .noSuchGame:
            return "I couldn't find that game in Stack the Lineup."
        case .noSuchPlayer:
            return "I couldn't find that player on any of your rosters."
        }
    }
}
