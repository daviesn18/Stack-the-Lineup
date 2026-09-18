import XCTest
@testable import Lineup_Builder

// MARK: - DebugTestControlTests
//
// Pins the logic behind the DEBUG test-control surface that STLAppIntentsTests
// drives through the real App Intents stack. These run in the UNIT target — no
// UI-test runner — so the Pro-override seam and the seed round-trip are verified
// reliably regardless of the UI runner's launch flakiness. The AppIntentsTesting
// UI tests then exercise the same code through the out-of-process intent stack.

final class DebugTestControlTests: XCTestCase {

    override func tearDown() async throws {
        PurchaseManager.setProTestingOverride(nil)
        try await super.tearDown()
    }

    // MARK: Pro override seam

    /// The seam that lets AppIntentsTesting reach the Pro path in the out-of-process
    /// app: setting the override must change what the real gate, isProNow(), reports.
    func testProOverrideDrivesIsProNow() async {
        PurchaseManager.setProTestingOverride(true)
        let forcedOn = await PurchaseManager.isProNow()
        XCTAssertTrue(forcedOn, "override = true should make isProNow() report Pro")

        PurchaseManager.setProTestingOverride(false)
        let forcedOff = await PurchaseManager.isProNow()
        XCTAssertFalse(forcedOff, "override = false should make isProNow() report not-Pro")

        PurchaseManager.setProTestingOverride(nil)
        let cleared = await PurchaseManager.isProNow()
        XCTAssertFalse(cleared, "clearing falls back to real StoreKit — no entitlement under test")
    }

    func testProOverrideStoresAndClears() {
        PurchaseManager.setProTestingOverride(nil)
        XCTAssertNil(PurchaseManager.proTestingOverride)

        PurchaseManager.setProTestingOverride(true)
        XCTAssertEqual(PurchaseManager.proTestingOverride, true)

        PurchaseManager.setProTestingOverride(false)
        XCTAssertEqual(PurchaseManager.proTestingOverride, false)

        PurchaseManager.setProTestingOverride(nil)
        XCTAssertNil(PurchaseManager.proTestingOverride)
    }

    // MARK: Seed round-trip (injected suite — never touches .standard)

    /// Seeding writes a team whose player the roster read path decodes back, which
    /// is what makes the PlayerEntity query resolvable. Reset removes exactly it.
    func testSeedRosterWritesADecodablePlayerThenResets() throws {
        let suite = "DebugTestControlTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        DebugTestControl.seedRoster(defaults: defaults)

        let (teams, active) = TeamStorage.loadTeamsForReading(defaults: defaults)
        let seededPlayer = teams.flatMap(\.players)
            .first { $0.lastName == DebugTestControl.seedLastName }
        XCTAssertNotNil(seededPlayer, "seeded player should decode back from storage")
        XCTAssertEqual(seededPlayer?.number, DebugTestControl.seedNumber)
        XCTAssertEqual(active?.id, DebugTestControl.seededTeamID, "seeded team should be active")
        XCTAssertEqual(DebugTestControl.seededPlayerQuery, DebugTestControl.seedLastName)

        DebugTestControl.resetSeed(defaults: defaults)
        let (after, _) = TeamStorage.loadTeamsForReading(defaults: defaults)
        XCTAssertFalse(
            after.contains { $0.id == DebugTestControl.seededTeamID },
            "reset should remove the seeded team"
        )
    }
}
