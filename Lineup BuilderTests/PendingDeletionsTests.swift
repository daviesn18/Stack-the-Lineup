import XCTest
@testable import Lineup_Builder

// MARK: - Pending Record Deletions
//
// Guards the persistence half of the reliable-delete fix: the queue of team
// records awaiting CloudKit deletion must survive a relaunch, or a delete that
// failed on its first try (offline/throttled) would be forgotten and leak an
// orphan record — the "zombie team" bug. The retry itself talks to the CloudKit
// singleton and is verified on-device; this pins the storage contract.
final class PendingDeletionsTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suiteName = "PendingDeletionsTests.\(UUID().uuidString)"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testStartsEmpty() {
        XCTAssertTrue(TeamStorage.loadPendingDeletions(defaults: defaults).isEmpty)
    }

    func testRoundTripsAcrossReload() {
        let names: Set<String> = ["team-A", "team-B", "team-C"]
        TeamStorage.savePendingDeletions(names, defaults: defaults)
        // A fresh read is what a relaunch does.
        XCTAssertEqual(TeamStorage.loadPendingDeletions(defaults: defaults), names)
    }

    func testDrainingToEmptyPersists() {
        TeamStorage.savePendingDeletions(["team-X"], defaults: defaults)
        // Once CloudKit confirms every deletion, the queue is saved empty and must
        // stay empty on the next launch — not fall back to a stale value.
        TeamStorage.savePendingDeletions([], defaults: defaults)
        XCTAssertTrue(TeamStorage.loadPendingDeletions(defaults: defaults).isEmpty)
    }
}
