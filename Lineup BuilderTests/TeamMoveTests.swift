import XCTest
import Supabase
@testable import Lineup_Builder

// MARK: - Moving a team into the account (Merge 1, slice 2)
//
// The pure rules (preflight, what a read-back leads to) and the sync.json
// record, then the store end to end against a server that can't be reached:
// the read-back fails, so every move here must roll back and leave the team
// exactly where it was. A successful move needs staging.

final class TeamMoveRulesTests: XCTestCase {

    private func team(record: String? = "team-x", readOnly: Bool = false, participant: Bool = false) -> Team {
        var t = Team()
        t.ckRecordName = record
        t.isReadOnly = readOnly
        t.isSharedParticipant = participant
        return t
    }

    private func preflight(_ t: Team, signedIn: Bool = true, account: Bool = false, received: Bool = false,
                           record: Bool = false, online: Bool = true,
                           share: TeamMove.ShareState = .notShared) -> TeamMove.Block? {
        TeamMove.preflight(team: t, signedIn: signedIn, isAccountTeam: account, isReceivedShare: received,
                           hasMoveRecord: record, online: online, shareState: share)
    }

    func testOwnUnsharedTeamCanMove() {
        XCTAssertNil(preflight(team()))
        XCTAssertNil(preflight(team(record: nil)), "a device-only team can move too")
    }

    func testBlocks() {
        XCTAssertEqual(preflight(team(), signedIn: false), .signedOut)
        XCTAssertEqual(preflight(team(), account: true), .alreadyInAccount)
        XCTAssertEqual(preflight(team(), record: true), .moveInProgress)
        XCTAssertEqual(preflight(team(), received: true), .receivedShare)
        XCTAssertEqual(preflight(team(participant: true)), .receivedShare)
        XCTAssertEqual(preflight(team(), share: .participant), .receivedShare)
        XCTAssertEqual(preflight(team(readOnly: true)), .readOnly)
        XCTAssertEqual(preflight(team(), online: false), .offline)
        XCTAssertEqual(preflight(team(), share: .shared), .shared)
        XCTAssertEqual(preflight(team(), share: .unknown), .shareCheckFailed)
    }

    func testSignedOutIsReportedBeforeAnythingElse() {
        XCTAssertEqual(preflight(team(readOnly: true), signedIn: false, online: false, share: .shared), .signedOut)
    }

    func testOnlyAMatchingReadBackGoesAhead() {
        XCTAssertEqual(TeamMove.next(after: .match), .markVerified)
        for v: TeamMove.Verify in [.mismatch, .missing, .offline, .failed("x")] {
            XCTAssertEqual(TeamMove.next(after: v), .rollBack, "\(v) must roll back")
            XCTAssertFalse(TeamMove.rollbackMessage(v).isEmpty)
        }
    }

    func testFirstOfReturnsTheFallbackWithoutWaitingForTheSlowCall() async {
        let start = ContinuousClock.now
        let value = await LineupStore.firstOf(timeout: .milliseconds(100), fallback: "fallback") {
            try? await Task.sleep(for: .seconds(30))
            return "slow"
        }
        XCTAssertEqual(value, "fallback")
        XCTAssertLessThan(ContinuousClock.now - start, .seconds(5))
    }

    func testFirstOfReturnsAFastResult() async {
        let value = await LineupStore.firstOf(timeout: .seconds(30), fallback: "fallback") { "fast" }
        XCTAssertEqual(value, "fast")
    }

    func testEveryBlockHasAMessage() {
        let all: [TeamMove.Block] = [.signedOut, .alreadyInAccount, .receivedShare, .readOnly, .shared,
                                     .offline, .shareCheckFailed, .moveInProgress]
        XCTAssertEqual(Set(all.map(\.reason)).count, all.count)
        for b in all { XCTAssertFalse(b.message.isEmpty) }
    }

    // MARK: sync.json

    func testSyncFileWrittenBeforeMerge1StillDecodes() throws {
        // A Merge 0b sync.json: no "moves" key. Decoding it must not fail,
        // because a file that doesn't decode is read as empty (losing every
        // team's sync state).
        let old = try JSONEncoder().encode(AccountSyncFile(teams: [:], pendingDeletes: [UUID()]))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: old) as? [String: Any])
        json["moves"] = nil
        let file = try JSONDecoder().decode(AccountSyncFile.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(file.pendingDeletes.count, 1)
        XCTAssertNil(file.moves)
    }

    func testMoveRecordRoundTrips() throws {
        let id = UUID()
        var file = AccountSyncFile()
        file.moves = [id: TeamMoveRecord(phase: .verified, startedAt: Date(timeIntervalSince1970: 1_800_000_000),
                                         ckRecordName: "team-\(id)", backupFile: "b.json")]
        let decoded = try JSONDecoder().decode(AccountSyncFile.self, from: JSONEncoder().encode(file))
        XCTAssertEqual(decoded, file)
    }
}

// MARK: - The store, end to end

@MainActor
final class TeamMoveStoreTests: XCTestCase {

    private var store: LineupStore!
    private var previousAccount: String?
    private let testAccount = UUID().uuidString.lowercased()
    private var accountStore: AccountTeamStore { AccountTeamStore(userID: testAccount) }

    override func setUp() async throws {
        previousAccount = AccountTeamStore.signedInAccount()
        AccountTeamStore.setSignedInAccount(nil)
        store = LineupStore()
        var team = Team()
        team.name = "Reds"
        team.ckRecordName = "team-\(team.id.uuidString)"
        store.teams = [team]
        store.activeTeamID = team.id
        store.accountTeamIDs = []

        // Signed in, with a sync actor whose server can't be reached: a closed
        // port on this machine, so every request fails at once as offline.
        AccountTeamStore.setSignedInAccount(testAccount)
        let unreachable = SupabaseClient(supabaseURL: URL(string: "http://127.0.0.1:9")!, supabaseKey: "test")
        store.accountSync = SupabaseTeamSync(store: accountStore, client: unreachable)
    }

    override func tearDown() async throws {
        store.accountSync = nil
        store = nil
        try? accountStore.wipe()
        AccountTeamStore.setSignedInAccount(previousAccount)
    }

    private var teamID: UUID { store.teams[0].id }

    /// A team with a CloudKit record needs CloudKit to confirm it isn't shared,
    /// and the test host can't reach CloudKit (that block is checked below).
    /// A device-only team skips the share check, so the move runs to the
    /// read-back. Restoring a record name is covered by the resume tests.
    private func makeDeviceOnly() { store.teams[0].ckRecordName = nil }

    func testACloudKitTeamWhoseSharingCantBeCheckedIsBlocked() async {
        let result = await store.moveTeamToAccount(teamID)
        XCTAssertEqual(result, .blocked(.shareCheckFailed))
        XCTAssertFalse(store.accountTeamIDs.contains(teamID))
    }

    func testAMoveThatCantBeConfirmedRollsBack() async throws {
        makeDeviceOnly()

        let result = await store.moveTeamToAccount(teamID)

        guard case .failed(let message) = result else { return XCTFail("expected a rollback, got \(result)") }
        XCTAssertFalse(message.isEmpty)
        XCTAssertFalse(store.accountTeamIDs.contains(teamID), "back to being a CloudKit team")
        XCTAssertNil(store.teams[0].ckRecordName)
        XCTAssertTrue(store.pendingCloudPushIDs.contains(teamID), "edits made during the move reach CloudKit")
        XCTAssertNil(store.movingTeamID)
        let records = await store.accountSync!.moveRecords()
        XCTAssertTrue(records.isEmpty, "a rolled-back move leaves no record")
    }

    func testAMoveKeepsARawBackupFirst() async throws {
        makeDeviceOnly()
        _ = await store.moveTeamToAccount(teamID)

        let dir = accountStore.directory.appendingPathComponent("backups")
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        let backup = try XCTUnwrap(files.first { $0.hasPrefix("\(teamID.uuidString)-move-") })
        let saved = try JSONDecoder().decode(Team.self, from: Data(contentsOf: dir.appendingPathComponent(backup)))
        XCTAssertEqual(saved.id, teamID)
        XCTAssertEqual(saved.name, "Reds")
    }

    func testBlockedMovesChangeNothing() async {
        store.accountTeamIDs = [teamID]
        let already = await store.moveTeamToAccount(teamID)
        XCTAssertEqual(already, .blocked(.alreadyInAccount))

        store.accountTeamIDs = []
        store.teams[0].isReadOnly = true
        let readOnly = await store.moveTeamToAccount(teamID)
        XCTAssertEqual(readOnly, .blocked(.readOnly))
        XCTAssertNotNil(store.teams[0].ckRecordName)

        store.accountSync = nil
        let signedOut = await store.moveTeamToAccount(teamID)
        XCTAssertEqual(signedOut, .blocked(.signedOut))
    }

    // MARK: Resuming after the app was killed

    func testAMoveKilledBeforeTheTeamWasTaggedIsCleared() async {
        let sync = store.accountSync!
        await sync.beginMove(teamID, record: TeamMoveRecord(phase: .uploading, startedAt: Date(),
                                                           ckRecordName: store.teams[0].ckRecordName, backupFile: nil))

        await store.resumeTeamMoves()

        let records = await sync.moveRecords()
        XCTAssertTrue(records.isEmpty)
        XCTAssertFalse(store.accountTeamIDs.contains(teamID))
        XCTAssertNotNil(store.teams[0].ckRecordName, "an unstarted move doesn't touch the team")
    }

    func testAMoveKilledMidUploadRollsBackWhenItCantBeConfirmed() async {
        let sync = store.accountSync!
        let recordName = store.teams[0].ckRecordName
        await sync.beginMove(teamID, record: TeamMoveRecord(phase: .uploading, startedAt: Date(),
                                                           ckRecordName: recordName, backupFile: nil))
        // Killed after the team became an account team.
        store.teams[0].ckRecordName = nil
        store.accountTeamIDs = [teamID]

        await store.resumeTeamMoves()

        XCTAssertFalse(store.accountTeamIDs.contains(teamID))
        XCTAssertEqual(store.teams[0].ckRecordName, recordName)
        let records = await sync.moveRecords()
        XCTAssertTrue(records.isEmpty)
    }

    func testAVerifiedMoveNeverRollsBack() async {
        // Verified, but the marker couldn't be written (no CloudKit in tests):
        // the team stays in the account and the record waits for a retry.
        let sync = store.accountSync!
        await sync.beginMove(teamID, record: TeamMoveRecord(phase: .verified, startedAt: Date(),
                                                           ckRecordName: "team-\(teamID.uuidString)", backupFile: nil))
        store.teams[0].ckRecordName = nil
        store.accountTeamIDs = [teamID]

        await store.resumeTeamMoves()

        XCTAssertTrue(store.accountTeamIDs.contains(teamID), "a verified move stays moved")
        XCTAssertNil(store.teams[0].ckRecordName)
    }
}
