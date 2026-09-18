import XCTest
@testable import Lineup_Builder

// MARK: - CloudKitMergeRecencyTests
//
// mergeCloudKitChanges used to overwrite a local team wholesale with whatever a
// CloudKit fetch returned, with no recency guard. Because a local edit's own push
// is debounced, a foreground fetch could land a server copy that PREDATES the
// edit and stomp it (the Siri Fill Lineup bug, and any lineup edited around a
// foreground fetch). The fix adds Team.updatedAt (stamped in save(), carried in
// the JSON blob) and gates the overwrite on `shouldApplyServerTeam`.
//
// These pin the pure decision function and the blob contract. The end-to-end
// two-device behavior still needs a device run (see V3.5_P1_DEVICE_TEST_CHECKLIST).

final class CloudKitMergeRecencyTests: XCTestCase {

    private let older = Date(timeIntervalSince1970: 100)
    private let newer = Date(timeIntervalSince1970: 200)

    // MARK: - shouldApplyServerTeam

    func testServerNewerThanLocalIsApplied() {
        let local  = Team(updatedAt: older)
        let server = Team(id: local.id, updatedAt: newer)
        XCTAssertTrue(LineupStore.shouldApplyServerTeam(local: local, server: server))
    }

    func testLocalNewerThanServerIsSkipped() {
        // The stomp case: local holds a just-made edit whose push hasn't landed,
        // so the fetched server copy is older. It must NOT overwrite local.
        let local  = Team(updatedAt: newer)
        let server = Team(id: local.id, updatedAt: older)
        XCTAssertFalse(LineupStore.shouldApplyServerTeam(local: local, server: server))
    }

    func testEqualTimestampsResolveToTheServer() {
        // Ties keep the prior CloudKit-authoritative behavior.
        let local  = Team(updatedAt: newer)
        let server = Team(id: local.id, updatedAt: newer)
        XCTAssertTrue(LineupStore.shouldApplyServerTeam(local: local, server: server))
    }

    func testReadOnlyTeamAlwaysTakesTheServerCopyEvenIfLocalLooksNewer() {
        // A read-only shared team can't be edited locally, so a "newer" local
        // stamp can only be clock skew — always take the owner's copy.
        let local  = Team(isReadOnly: true, updatedAt: newer)
        let server = Team(id: local.id, isReadOnly: true, updatedAt: older)
        XCTAssertTrue(LineupStore.shouldApplyServerTeam(local: local, server: server))
    }

    func testStampedServerBeatsALegacyLocalCopy() {
        // A team decoded from a pre-updatedAt blob sorts oldest, so a real remote
        // edit on the new build still wins.
        let legacyLocal = Team(updatedAt: .distantPast)
        let server      = Team(id: legacyLocal.id, updatedAt: newer)
        XCTAssertTrue(LineupStore.shouldApplyServerTeam(local: legacyLocal, server: server))
    }

    // MARK: - Blob contract (rides CloudKit)

    func testLegacyBlobWithoutUpdatedAtDecodesToDistantPast() throws {
        // Team's decode is tolerant: an object with no updatedAt key must still
        // decode, defaulting the field to .distantPast (never throwing and taking
        // the whole shared roster down).
        let data = Data("{}".utf8)
        let team = try JSONDecoder().decode(Team.self, from: data)
        XCTAssertEqual(team.updatedAt, .distantPast)
    }

    func testUpdatedAtSurvivesTheJSONBlobRoundTrip() throws {
        let team = Team(name: "Tigers", updatedAt: Date(timeIntervalSince1970: 1_234_567))
        let back = try JSONDecoder().decode(Team.self, from: JSONEncoder().encode(team))
        XCTAssertEqual(back.updatedAt.timeIntervalSince1970,
                       team.updatedAt.timeIntervalSince1970,
                       accuracy: 0.001)
    }
}
