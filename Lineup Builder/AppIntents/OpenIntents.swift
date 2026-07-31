import AppIntents
import Foundation

// MARK: - Open Intents
//
// The tap-through half of Spotlight surfacing: a result is only useful if
// selecting it lands somewhere. Both intents foreground the app and hand the
// destination to AppRouter, which ContentView and iPadDashboardView drain.
//
// Free, deliberately. Finding a player by voice or search is discovery — it's
// what makes a coach reach for the app at all. The Pro gates sit on the actions
// (auto-fill, recap), not on being able to look something up.
//
// Isolation note: unlike the entities and queries, these are NOT marked
// `nonisolated`. The project sets SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor, and
// `nonisolated` on the type propagates to `@Parameter`'s mutable stored property
// — a warning today and a hard error in the Swift 6 language mode. Leaving them
// on the default actor is also simply honest: every `perform()` here touches
// AppRouter, which is @MainActor.

struct OpenPlayerIntent: AppIntent {

    static let title: LocalizedStringResource = "Open Player"

    static let description = IntentDescription(
        "Opens a player and scrolls to their position preferences.",
        categoryName: "Roster",
        searchKeywords: ["player", "roster", "position", "preferences"]
    )

    /// The player sheet is the point — there is nothing to report by voice.
    static let openAppWhenRun = true

    @Parameter(title: "Player")
    var player: PlayerEntity

    init() {}

    init(player: PlayerEntity) {
        self.player = player
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        Analytics.signal("intent.open_player")
        AppRouter.shared.route(to: .player(player.id))
        return .result()
    }
}

struct OpenTeamIntent: AppIntent {

    static let title: LocalizedStringResource = "Open Team"

    static let description = IntentDescription(
        "Switches to a team and opens its lineup.",
        categoryName: "Roster",
        searchKeywords: ["team", "roster", "lineup", "switch"]
    )

    static let openAppWhenRun = true

    @Parameter(title: "Team")
    var team: TeamEntity

    init() {}

    init(team: TeamEntity) {
        self.team = team
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        Analytics.signal("intent.open_team")
        AppRouter.shared.route(to: .team(team.id))
        return .result()
    }
}

// MARK: - Open Lineup
//
// No parameters, so this is the one phrase Siri can satisfy with nothing but the
// app name — the equivalent of tapping the home screen widget.

struct OpenLineupIntent: AppIntent {

    static let title: LocalizedStringResource = "Open Lineup"

    static let description = IntentDescription(
        "Opens today's lineup.",
        categoryName: "Roster",
        searchKeywords: ["lineup", "today", "game"]
    )

    static let openAppWhenRun = true

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        Analytics.signal("intent.open_lineup")
        AppRouter.shared.route(to: .lineup)
        return .result()
    }
}
