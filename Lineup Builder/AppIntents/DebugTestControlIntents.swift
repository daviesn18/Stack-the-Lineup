#if DEBUG
import AppIntents
import Foundation

// MARK: - Debug Test-Control Intents
//
// Test-only App Intents that let AppIntentsTesting arrange app state inside the
// SAME out-of-process app it launches to run the real intents. AppIntentsTesting
// exposes no launch-argument or launch-environment hook, so anything a test needs
// set up (Pro status, seed roster) has to be set through the intent channel
// itself — which is exactly what these do.
//
// Everything here is #if DEBUG and isDiscoverable = false: it is never in a
// shipping build and never surfaced to a coach in Shortcuts/Spotlight, while
// still being addressable by AppIntentsTesting via IntentDefinitions.
//
// Driven by STLAppIntentsTests in the UI-test bundle.

nonisolated enum DebugTestControl {

    /// Fixed id so `resetSeed()` removes exactly the seeded team and nothing else,
    /// even if a real roster is also present.
    static let seededTeamID = UUID(uuidString: "DEADBEEF-0000-0000-0000-000000000001")!
    static let seedFirstName = "Seedford"
    static let seedLastName  = "Testerson"
    static let seedNumber    = "99"

    /// The string AppIntentsTesting searches for to find the seeded player.
    static var seededPlayerQuery: String { seedLastName }

    private static func currentTeams(defaults: UserDefaults) -> [Team] {
        if case .loaded(let teams, _) = TeamStorage.load(defaults: defaults) { return teams }
        return []
    }

    /// Appends a known team + player (replacing any prior seed) and makes it active.
    /// `defaults` is injectable on the same terms as `TeamStorage.load` — tests pass
    /// a private suite; the intents use `.standard`.
    static func seedRoster(defaults: UserDefaults = .standard) {
        var teams = currentTeams(defaults: defaults).filter { $0.id != seededTeamID }
        let player = Player(
            id: UUID(),
            firstName: seedFirstName,
            lastName: seedLastName,
            number: seedNumber
        )
        teams.append(Team(id: seededTeamID, name: "Test Seed Team", players: [player]))
        persist(teams, activeID: seededTeamID, defaults: defaults)
    }

    /// Removes the seeded team. If it was active, hands active status to whatever
    /// remains (or clears it) so we never leave a dangling active id.
    static func resetSeed(defaults: UserDefaults = .standard) {
        guard case .loaded(let teams, let activeID) = TeamStorage.load(defaults: defaults) else { return }
        let remaining = teams.filter { $0.id != seededTeamID }
        persist(remaining, activeID: activeID == seededTeamID ? remaining.first?.id : activeID, defaults: defaults)
    }

    private static func persist(_ teams: [Team], activeID: UUID?, defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(teams) {
            defaults.set(data, forKey: TeamStorage.teamsKey)
        }
        if let activeID {
            defaults.set(activeID.uuidString, forKey: TeamStorage.activeTeamKey)
        } else {
            defaults.removeObject(forKey: TeamStorage.activeTeamKey)
        }
    }
}

/// Writes a known roster and returns the string a test can search for.
struct SeedTestRosterIntent: AppIntent {
    static let title: LocalizedStringResource = "Seed Test Roster (Debug)"
    static let isDiscoverable = false
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        DebugTestControl.seedRoster()
        return .result(value: DebugTestControl.seededPlayerQuery)
    }
}

/// Undoes `SeedTestRosterIntent` and clears any Pro override. Safe teardown for
/// every test in the suite.
struct ResetTestDataIntent: AppIntent {
    static let title: LocalizedStringResource = "Reset Test Data (Debug)"
    static let isDiscoverable = false
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        DebugTestControl.resetSeed()
        PurchaseManager.setProTestingOverride(nil)
        return .result()
    }
}

/// Forces `PurchaseManager.isProNow()` to a fixed value for the duration of a run.
struct SetProForTestingIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Pro For Testing (Debug)"
    static let isDiscoverable = false
    static let openAppWhenRun = false

    @Parameter(title: "Pro Enabled") var enabled: Bool

    func perform() async throws -> some IntentResult {
        PurchaseManager.setProTestingOverride(enabled)
        return .result()
    }
}

/// Returns what the real gate (`isProNow()`) currently reports — so a test can
/// assert the override is actually honored end-to-end, not just stored.
struct ProStatusForTestingIntent: AppIntent {
    static let title: LocalizedStringResource = "Pro Status For Testing (Debug)"
    static let isDiscoverable = false
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        let isPro = await PurchaseManager.isProNow()
        return .result(value: isPro)
    }
}
#endif
