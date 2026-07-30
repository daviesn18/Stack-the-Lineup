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
// SAFETY: the test host is the real app, so UserDefaults.standard here is the
// app's own store. setUp/tearDown snapshot and restore every key touched so a
// test run can never destroy a developer's simulator roster.

@MainActor
final class TeamStorageTests: XCTestCase {

    // MARK: - Setup / Teardown

    private var savedTeams:    Data?
    private var savedSavedAt:  Any?
    private var savedActiveID: String?

    override func setUp() {
        super.setUp()
        let d = UserDefaults.standard
        savedTeams    = d.data(forKey: TeamStorage.teamsKey)
        savedSavedAt  = d.object(forKey: TeamStorage.savedAtKey)
        savedActiveID = d.string(forKey: TeamStorage.activeTeamKey)
        clearKeys()
    }

    override func tearDown() {
        let d = UserDefaults.standard
        clearKeys()
        if let savedTeams    { d.set(savedTeams,    forKey: TeamStorage.teamsKey) }
        if let savedSavedAt  { d.set(savedSavedAt,  forKey: TeamStorage.savedAtKey) }
        if let savedActiveID { d.set(savedActiveID, forKey: TeamStorage.activeTeamKey) }
        super.tearDown()
    }

    private func clearKeys() {
        let d = UserDefaults.standard
        d.removeObject(forKey: TeamStorage.teamsKey)
        d.removeObject(forKey: TeamStorage.savedAtKey)
        d.removeObject(forKey: TeamStorage.activeTeamKey)
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
        UserDefaults.standard.set(data, forKey: TeamStorage.teamsKey)
        if let activeID {
            UserDefaults.standard.set(activeID.uuidString, forKey: TeamStorage.activeTeamKey)
        }
    }

    // MARK: - empty

    func testNoStoredDataReportsEmpty() {
        guard case .empty(let activeID) = TeamStorage.load() else {
            return XCTFail("A genuine first launch must report .empty so migration can run")
        }
        XCTAssertNil(activeID)
    }

    // MARK: - decodeFailed

    func testUndecodableBlobReportsDecodeFailedNotEmpty() {
        UserDefaults.standard.set(Data("not json".utf8), forKey: TeamStorage.teamsKey)

        guard case .decodeFailed = TeamStorage.load() else {
            return XCTFail(
                "A corrupt blob must NOT report .empty — that path runs migration and overwrites iCloud."
            )
        }
    }

    // MARK: - loaded

    func testStoredTeamsRoundTrip() {
        let teams = [makeTeam("Reds"), makeTeam("Tigers")]
        write(teams, activeID: teams[1].id)

        guard case .loaded(let loaded, let activeID) = TeamStorage.load() else {
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

        guard case .loaded(let loaded, _) = TeamStorage.load() else {
            return XCTFail("Valid stored data should decode")
        }
        XCTAssertEqual(loaded[0].gameLogs.map(\.opponent), ["New", "Mid", "Old"])
    }

    func testMalformedActiveIDIsIgnoredRatherThanFatal() {
        let teams = [makeTeam("Reds")]
        let data = try! JSONEncoder().encode(teams)
        UserDefaults.standard.set(data, forKey: TeamStorage.teamsKey)
        UserDefaults.standard.set("not-a-uuid", forKey: TeamStorage.activeTeamKey)

        guard case .loaded(let loaded, let activeID) = TeamStorage.load() else {
            return XCTFail("A bad active-team ID must not prevent teams from loading")
        }
        XCTAssertEqual(loaded.count, 1)
        XCTAssertNil(activeID)
    }

    // MARK: - loadTeamsForReading (the App Intents entry point)

    func testReadingFallsBackToFirstTeamWhenActiveIDMissing() {
        let teams = [makeTeam("Reds"), makeTeam("Tigers")]
        write(teams, activeID: nil)

        let result = TeamStorage.loadTeamsForReading()
        XCTAssertEqual(result.teams.count, 2)
        XCTAssertEqual(result.activeTeam?.name, "Reds",
                       "With no stored active team, an intent should answer about the first team")
    }

    func testReadingResolvesStoredActiveTeam() {
        let teams = [makeTeam("Reds"), makeTeam("Tigers")]
        write(teams, activeID: teams[1].id)

        XCTAssertEqual(TeamStorage.loadTeamsForReading().activeTeam?.name, "Tigers")
    }

    func testReadingReportsNothingOnCorruptData() {
        // An intent should say "no teams yet" rather than attempt recovery.
        UserDefaults.standard.set(Data("not json".utf8), forKey: TeamStorage.teamsKey)

        let result = TeamStorage.loadTeamsForReading()
        XCTAssertTrue(result.teams.isEmpty)
        XCTAssertNil(result.activeTeam)
    }
}
