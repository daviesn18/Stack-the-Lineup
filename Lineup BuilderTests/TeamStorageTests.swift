import XCTest
@testable import Lineup_Builder

// MARK: - TeamStorage Tests
//
// TeamStorage is the single read path shared by LineupStore and the App Intents
// layer. These tests pin the three-way LoadResult contract, because collapsing
// `empty` and `decodeFailed` into "no teams" is precisely what would let a schema
// mismatch cascade into migrateOrCreateDefaultTeam() and overwrite iCloud with a
// blank team — the July 2026 failure mode.
//
// These run in DEBUG, so TeamStorage.load() reads local UserDefaults only and the
// iCloud KV store is never consulted. That keeps them deterministic.
//
// ISOLATION: these run against a private UserDefaults suite, never .standard.
//
// They used to use .standard and guard it with a setUp/tearDown snapshot-restore.
// That could not work: the test host IS the real app, so .standard here is the
// running app's own store, and LineupStore.saveLocalOnly() writes these same three
// keys from a detached Task (Models.swift). setUp() cleared the keys synchronously
// and a pending app write could land before the assertion read -- which is why
// testNoStoredDataReportsEmpty, the only test asserting *absence*, failed on any
// simulator that had ever held a roster while the suite still reported green on a
// fresh one. The snapshot dance was guarding against a synchronous writer while the
// real writer was async.
//
// A private suite removes the shared mutable state instead of trying to out-race
// it, and as a side effect these tests no longer touch a developer's roster at all.

@MainActor
final class TeamStorageTests: XCTestCase {

    // MARK: - Setup / Teardown

    /// Private to this suite. Never the app's store.
    private static let suiteName = "com.stackthelineup.tests.TeamStorage"

    private var defaults: UserDefaults!

    override func setUp() async throws {
        // Clear first: a crashed previous run can leave the domain populated.
        UserDefaults.standard.removePersistentDomain(forName: Self.suiteName)
        defaults = UserDefaults(suiteName: Self.suiteName)
    }

    override func tearDown() async throws {
        defaults?.removePersistentDomain(forName: Self.suiteName)
        defaults = nil
    }

    // MARK: - Helpers

    private func makeTeam(_ name: String) -> Team {
        var team = Team()
        team.name = name
        return team
    }

    private func makeLog(_ gameDate: Date, _ opponent: String) -> GameLog {
        GameLog(gameDate: gameDate, opponent: opponent, inningsPlayed: 6,
                battingOrder: [], innings: [], playerSnapshot: [])
    }

    private func write(_ teams: [Team], activeID: UUID?) {
        let data = try! JSONEncoder().encode(teams)
        defaults.set(data, forKey: TeamStorage.teamsKey)
        if let activeID {
            defaults.set(activeID.uuidString, forKey: TeamStorage.activeTeamKey)
        }
    }

    // MARK: - empty

    func testNoStoredDataReportsEmpty() {
        guard case .empty(let activeID) = TeamStorage.load(defaults: defaults) else {
            return XCTFail("A genuine first launch must report .empty so migration can run")
        }
        XCTAssertNil(activeID)
    }

    // MARK: - decodeFailed

    func testUndecodableBlobReportsDecodeFailedNotEmpty() {
        defaults.set(Data("not json".utf8), forKey: TeamStorage.teamsKey)

        guard case .decodeFailed = TeamStorage.load(defaults: defaults) else {
            return XCTFail(
                "A corrupt blob must NOT report .empty — that path runs migration and overwrites iCloud."
            )
        }
    }

    // MARK: - loaded

    func testStoredTeamsRoundTrip() {
        let teams = [makeTeam("Reds"), makeTeam("Tigers")]
        write(teams, activeID: teams[1].id)

        guard case .loaded(let loaded, let activeID) = TeamStorage.load(defaults: defaults) else {
            return XCTFail("Valid stored data should decode")
        }
        XCTAssertEqual(loaded.map(\.name), ["Reds", "Tigers"])
        XCTAssertEqual(activeID, teams[1].id)
    }

    func testGameLogsAreSortedNewestFirst() {
        // Corrects logs persisted out of order by the archive-order bug.
        var team = makeTeam("Reds")
        let old = Date(timeIntervalSince1970: 1_000)
        let mid = Date(timeIntervalSince1970: 2_000)
        let new = Date(timeIntervalSince1970: 3_000)
        team.gameLogs = [makeLog(old, "Old"), makeLog(new, "New"), makeLog(mid, "Mid")]
        write([team], activeID: team.id)

        guard case .loaded(let loaded, _) = TeamStorage.load(defaults: defaults) else {
            return XCTFail("Valid stored data should decode")
        }
        XCTAssertEqual(loaded[0].gameLogs.map(\.opponent), ["New", "Mid", "Old"])
    }

    func testMalformedActiveIDIsIgnoredRatherThanFatal() {
        let teams = [makeTeam("Reds")]
        let data = try! JSONEncoder().encode(teams)
        defaults.set(data, forKey: TeamStorage.teamsKey)
        defaults.set("not-a-uuid", forKey: TeamStorage.activeTeamKey)

        guard case .loaded(let loaded, let activeID) = TeamStorage.load(defaults: defaults) else {
            return XCTFail("A bad active-team ID must not prevent teams from loading")
        }
        XCTAssertEqual(loaded.count, 1)
        XCTAssertNil(activeID)
    }

    // MARK: - loadTeamsForReading (the App Intents entry point)

    func testReadingFallsBackToFirstTeamWhenActiveIDMissing() {
        let teams = [makeTeam("Reds"), makeTeam("Tigers")]
        write(teams, activeID: nil)

        let result = TeamStorage.loadTeamsForReading(defaults: defaults)
        XCTAssertEqual(result.teams.count, 2)
        XCTAssertEqual(result.activeTeam?.name, "Reds",
                       "With no stored active team, an intent should answer about the first team")
    }

    func testReadingResolvesStoredActiveTeam() {
        let teams = [makeTeam("Reds"), makeTeam("Tigers")]
        write(teams, activeID: teams[1].id)

        XCTAssertEqual(TeamStorage.loadTeamsForReading(defaults: defaults).activeTeam?.name, "Tigers")
    }

    func testReadingReportsNothingOnCorruptData() {
        // An intent should say "no teams yet" rather than attempt recovery.
        defaults.set(Data("not json".utf8), forKey: TeamStorage.teamsKey)

        let result = TeamStorage.loadTeamsForReading(defaults: defaults)
        XCTAssertTrue(result.teams.isEmpty)
        XCTAssertNil(result.activeTeam)
    }
}
