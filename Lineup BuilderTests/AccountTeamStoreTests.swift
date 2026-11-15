import XCTest
@testable import Lineup_Builder

// MARK: - AccountTeamStore / TeamStorage account tests (Merge 0b)
//
// Account teams live in their own files and join the blob's teams in
// TeamStorage.load(), the single reader for the app, App Intents and widgets.
// Isolated like TeamStorageTests: a private UserDefaults suite (never the
// running app's .standard) and a temporary folder for the account files.

@MainActor
final class AccountTeamStoreTests: XCTestCase {

    private static let suiteName = "com.stackthelineup.tests.AccountTeamStore"
    private var defaults: UserDefaults!
    private var root: URL!
    private let userID = "0F8C7B9E-1111-4222-8333-944455556666"

    override func setUp() async throws {
        UserDefaults.standard.removePersistentDomain(forName: Self.suiteName)
        defaults = UserDefaults(suiteName: Self.suiteName)
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    override func tearDown() async throws {
        defaults?.removePersistentDomain(forName: Self.suiteName)
        try? FileManager.default.removeItem(at: root)
    }

    private func team(_ name: String, id: UUID = UUID()) -> Team {
        Team(id: id, name: name)
    }

    private func writeBlob(_ teams: [Team]) throws {
        defaults.set(try JSONEncoder().encode(teams), forKey: TeamStorage.teamsKey)
    }

    private var store: AccountTeamStore { AccountTeamStore(userID: userID, root: root) }

    // MARK: - Store

    func testTeamsRoundTrip() throws {
        try store.saveTeams([team("Cubs")])
        guard case .loaded(let teams) = store.loadTeams() else { return XCTFail("not loaded") }
        XCTAssertEqual(teams.map(\.name), ["Cubs"])
    }

    func testNoFileIsEmptyAndGarbageIsDecodeFailed() throws {
        XCTAssertEqual(store.loadTeams(), .empty)
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: store.directory.appendingPathComponent("teams.json"))
        XCTAssertEqual(store.loadTeams(), .decodeFailed)
    }

    func testSyncFileRoundTrip() throws {
        var file = AccountSyncFile()
        let id = UUID()
        file.teams[id] = TeamSyncState(lastError: "offline")
        file.pendingDeletes = [UUID()]
        try store.saveSync(file)
        XCTAssertEqual(store.loadSync(), file)
    }

    func testFolderIsPerAccountAndCaseInsensitive() {
        XCTAssertEqual(AccountTeamStore(userID: userID.lowercased(), root: root).directory, store.directory)
        XCTAssertNotEqual(AccountTeamStore(userID: UUID().uuidString, root: root).directory, store.directory)
    }

    func testWipeRemovesEverything() throws {
        try store.saveTeams([team("Cubs")])
        try store.saveSync(AccountSyncFile())
        try store.wipe()
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.directory.path))
        XCTAssertEqual(store.loadTeams(), .empty)
    }

    func testWriterDropsAnOlderWrite() async throws {
        let writer = AccountTeamWriter()
        await writer.write([team("newer")], sequence: 2, to: store)
        await writer.write([team("older")], sequence: 1, to: store)
        guard case .loaded(let teams) = store.loadTeams() else { return XCTFail("not loaded") }
        XCTAssertEqual(teams.map(\.name), ["newer"])
    }

    // MARK: - TeamStorage

    func testSignedOutReadsOnlyTheBlob() throws {
        try writeBlob([team("Device")])
        try store.saveTeams([team("Account")])
        guard case .loaded(let teams, _) = TeamStorage.load(defaults: defaults, accountsRoot: root) else {
            return XCTFail("not loaded")
        }
        XCTAssertEqual(teams.map(\.name), ["Device"])
        XCTAssertTrue(TeamStorage.accountTeamIDs(defaults: defaults, accountsRoot: root).isEmpty)
    }

    func testSignedInJoinsAccountTeamsToTheBlob() throws {
        AccountTeamStore.setSignedInAccount(userID, defaults: defaults)
        try writeBlob([team("Device")])
        let account = team("Account")
        try store.saveTeams([account])
        guard case .loaded(let teams, _) = TeamStorage.load(defaults: defaults, accountsRoot: root) else {
            return XCTFail("not loaded")
        }
        XCTAssertEqual(teams.map(\.name), ["Device", "Account"])
        XCTAssertEqual(TeamStorage.accountTeamIDs(defaults: defaults, accountsRoot: root), [account.id])
    }

    func testAccountOnlyIsLoadedNotEmpty() throws {
        AccountTeamStore.setSignedInAccount(userID, defaults: defaults)
        try store.saveTeams([team("Account")])
        guard case .loaded(let teams, _) = TeamStorage.load(defaults: defaults, accountsRoot: root) else {
            return XCTFail("an account team on a device with no blob is not a first launch")
        }
        XCTAssertEqual(teams.map(\.name), ["Account"])
    }

    func testTheAccountCopyWinsOverABlobLeftover() throws {
        AccountTeamStore.setSignedInAccount(userID, defaults: defaults)
        let id = UUID()
        try writeBlob([team("Old blob copy", id: id)])
        try store.saveTeams([team("Account copy", id: id)])
        guard case .loaded(let teams, _) = TeamStorage.load(defaults: defaults, accountsRoot: root) else {
            return XCTFail("not loaded")
        }
        XCTAssertEqual(teams.map(\.name), ["Account copy"])
    }

    func testABrokenBlobStillReportsDecodeFailed() throws {
        AccountTeamStore.setSignedInAccount(userID, defaults: defaults)
        defaults.set(Data("garbage".utf8), forKey: TeamStorage.teamsKey)
        try store.saveTeams([team("Account")])
        guard case .decodeFailed = TeamStorage.load(defaults: defaults, accountsRoot: root) else {
            return XCTFail("the SAFETY RULE needs decodeFailed whatever the account holds")
        }
    }

    func testIntentsSeeAccountTeams() throws {
        AccountTeamStore.setSignedInAccount(userID, defaults: defaults)
        try store.saveTeams([team("Account")])
        guard case .loaded(let teams, _) = TeamStorage.load(defaults: defaults, accountsRoot: root) else {
            return XCTFail("not loaded")
        }
        XCTAssertEqual(teams.count, 1)
    }
}
