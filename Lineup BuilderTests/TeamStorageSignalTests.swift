import XCTest
@testable import Lineup_Builder

// MARK: - teams.storage.daily tests
//
// The signal decides when CloudKit can be retired, so its counts must mean
// what the chart says: where each team lives, which were edited recently, and
// where the team the coach has open lives. And it must go at most once a day.

final class TeamStorageSignalTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_794_700_000)

    private func team(record: String? = "team-x", editedDaysAgo: Double, shared: Bool = false) -> Team {
        var t = Team(name: "T", ckRecordName: record, isSharedParticipant: shared)
        t.updatedAt = now.addingTimeInterval(-editedDaysAgo * 86_400)
        return t
    }

    func testCountsByWhereTeamsLive() {
        let recent = team(editedDaysAgo: 2)
        let stale = team(editedDaysAgo: 40)
        let local = team(record: nil, editedDaysAgo: 1)
        let received = team(editedDaysAgo: 3, shared: true)
        let p = TeamStorageSignal.parameters(teams: [recent, stale, local, received], activeTeamID: local.id,
                                             isReceivedShare: { _ in false }, now: now)
        XCTAssertEqual(p["cloudKitTeams"], "3")
        XCTAssertEqual(p["cloudKitActive"], "2", "edited within 14 days")
        XCTAssertEqual(p["deviceOnlyTeams"], "1")
        XCTAssertEqual(p["deviceOnlyActive"], "1")
        XCTAssertEqual(p["cloudKitReceivedTeams"], "1")
        XCTAssertEqual(p["accountTeams"], "0", "sent as 0 until account teams exist")
        XCTAssertEqual(p["openTeamStorage"], "device")
    }

    func testAccountTeamsWinOverACloudKitRecordName() {
        let moved = team(editedDaysAgo: 1)
        let p = TeamStorageSignal.parameters(teams: [moved], activeTeamID: moved.id, accountTeamIDs: [moved.id],
                                             isReceivedShare: { _ in false }, now: now)
        XCTAssertEqual(p["accountTeams"], "1")
        XCTAssertEqual(p["accountActive"], "1")
        XCTAssertEqual(p["cloudKitTeams"], "0")
        XCTAssertEqual(p["openTeamStorage"], "account")
    }

    func testLegacyTeamsNeverEditedAreNotActive() {
        var legacy = team(editedDaysAgo: 0)
        legacy.updatedAt = .distantPast   // how pre-3.5 blobs decode
        let p = TeamStorageSignal.parameters(teams: [legacy], activeTeamID: nil,
                                             isReceivedShare: { _ in false }, now: now)
        XCTAssertEqual(p["cloudKitActive"], "0")
        XCTAssertEqual(p["openTeamStorage"], "none")
    }

    func testOncePerDay() {
        let suite = "com.stackthelineup.tests.TeamStorageSignal"
        UserDefaults.standard.removePersistentDomain(forName: suite)
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertTrue(TeamStorageSignal.claimToday(defaults: defaults, now: now))
        XCTAssertFalse(TeamStorageSignal.claimToday(defaults: defaults, now: now.addingTimeInterval(3_600)))
        XCTAssertTrue(TeamStorageSignal.claimToday(defaults: defaults, now: now.addingTimeInterval(86_400)))
    }
}
