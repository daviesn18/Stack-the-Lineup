import XCTest
import SwiftUI
@testable import Lineup_Builder

// MARK: - New team routing (Merge 1, slice 1)
//
// Where a team made on this device starts life: signed in, the coach's
// account (tagged before its first save, so it never reaches CloudKit);
// signed out, CloudKit as before. Covers addTeam and addImportedTeam, the only
// two ways a team is created on the device.
//
// Signs the store in by writing the persisted sign-in to standard defaults,
// which is what the store reads. The simulator's own sign-in is saved first and
// restored afterwards, and the test account's folder is deleted.

@MainActor
final class NewTeamRoutingTests: XCTestCase {

    private var store: LineupStore!
    private var previousAccount: String?
    private let testAccount = UUID().uuidString.lowercased()

    override func setUp() async throws {
        previousAccount = AccountTeamStore.signedInAccount()
        AccountTeamStore.setSignedInAccount(nil)
        store = LineupStore()
        var team = Team()
        team.name = "Reds"
        store.teams = [team]
        store.activeTeamID = team.id
        store.accountTeamIDs = []
    }

    override func tearDown() async throws {
        store = nil
        try? AccountTeamStore(userID: testAccount).wipe()
        AccountTeamStore.setSignedInAccount(previousAccount)
    }

    private func signIn() {
        AccountTeamStore.setSignedInAccount(testAccount)
    }

    /// A .stlteam as another device would export it: still carrying the
    /// sender's CloudKit record name and sharing flags.
    private func exportedSnapshot() throws -> Team {
        var original = Team()
        original.name = "Blue Jays"
        original.ckRecordName = "team-\(original.id.uuidString)"
        original.isReadOnly = true
        let data = try XCTUnwrap(TeamExporter.export(team: original))
        guard case .success(let parsed) = TeamImporter.parse(data: data) else {
            XCTFail("export didn't parse"); throw CancellationError()
        }
        // The file really does carry them, which is why import clears them.
        XCTAssertEqual(parsed.team.ckRecordName, original.ckRecordName)
        XCTAssertTrue(parsed.team.isReadOnly)
        return parsed.team
    }

    // MARK: addTeam

    func testSignedOutNewTeamStaysOnCloudKit() {
        XCTAssertFalse(store.newTeamsGoToAccount)
        store.addTeam(name: "Cubs")

        let id = store.activeTeam.id
        XCTAssertEqual(store.activeTeam.name, "Cubs")
        XCTAssertFalse(store.accountTeamIDs.contains(id))
        XCTAssertTrue(store.pendingCloudPushIDs.contains(id), "a signed-out team is pushed to CloudKit")
    }

    func testSignedInNewTeamGoesToTheAccount() {
        signIn()
        XCTAssertTrue(store.newTeamsGoToAccount)
        store.addTeam(name: "Cubs", gameInningCount: 7)

        let id = store.activeTeam.id
        XCTAssertEqual(store.activeTeam.name, "Cubs")
        XCTAssertTrue(store.accountTeamIDs.contains(id))
        XCTAssertFalse(store.pendingCloudPushIDs.contains(id), "an account team must never be queued for CloudKit")
        XCTAssertNil(store.activeTeam.ckRecordName)
    }

    func testSignedInNewTeamLeavesExistingTeamsWhereTheyAre() {
        let existing = store.teams[0].id
        signIn()
        store.addTeam(name: "Cubs")

        XCTAssertFalse(store.accountTeamIDs.contains(existing), "creating a team doesn't move the others")
        XCTAssertEqual(store.accountTeamIDs, [store.activeTeam.id])
    }

    // MARK: addImportedTeam

    func testSignedInImportGoesToTheAccountWithAFreshID() throws {
        let snapshot = try exportedSnapshot()
        signIn()
        store.addImportedTeam(snapshot)

        let imported = store.activeTeam
        XCTAssertNotEqual(imported.id, snapshot.id)
        XCTAssertEqual(imported.name, "Blue Jays")
        XCTAssertTrue(store.accountTeamIDs.contains(imported.id))
        XCTAssertFalse(store.pendingCloudPushIDs.contains(imported.id))
    }

    func testImportClearsTheSendersCloudKitStateEvenSignedOut() throws {
        let snapshot = try exportedSnapshot()
        store.addImportedTeam(snapshot)

        let imported = store.activeTeam
        XCTAssertFalse(store.accountTeamIDs.contains(imported.id))
        // Kept, its first push would target the original team's record.
        XCTAssertNil(imported.ckRecordName)
        XCTAssertFalse(imported.isReadOnly)
        XCTAssertFalse(imported.isSharedParticipant)
        XCTAssertTrue(store.pendingCloudPushIDs.contains(imported.id))
    }

    // MARK: Replace keeps the team where it is

    func testReplaceEditsInPlaceWhereverTheTeamLives() throws {
        signIn()
        store.addTeam(name: "Cubs")
        let id = store.activeTeam.id

        store.replaceActiveTeam(with: try exportedSnapshot())

        XCTAssertEqual(store.activeTeam.id, id)
        XCTAssertEqual(store.activeTeam.name, "Blue Jays")
        XCTAssertTrue(store.accountTeamIDs.contains(id), "replacing an account team keeps it in the account")
        XCTAssertNil(store.activeTeam.ckRecordName, "the file's record name isn't taken over")
        XCTAssertFalse(store.activeTeam.isReadOnly, "the file's read-only flag isn't taken over")
    }

    func testReplaceKeepsACloudKitTeamsOwnRecord() throws {
        store.teams[0].ckRecordName = "team-\(store.teams[0].id.uuidString)"
        let own = store.teams[0].ckRecordName

        store.replaceActiveTeam(with: try exportedSnapshot())

        XCTAssertEqual(store.activeTeam.ckRecordName, own)
        XCTAssertFalse(store.activeTeam.isReadOnly)
    }
}
