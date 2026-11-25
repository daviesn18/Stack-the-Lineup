import XCTest
@testable import Lineup_Builder

// MARK: - TeamRowsDiff / TeamRowsMerge tests (Merge 0b)
//
// The diff is the save queue, and the merge decides what survives when the
// iPhone was offline while the web (or the iPad) edited the same team. Each
// merge case in the design is pinned here: only-server, only-device, both (the
// device wins), and edit-beats-delete in both directions.

final class TeamRowsSyncTests: XCTestCase {

    // MARK: - Fixture

    private let teamID = UUID()
    private let lineupID = UUID()
    private let p1 = UUID(), p2 = UUID(), p3 = UUID()

    private func player(_ id: UUID, _ name: String, order: Int) -> PlayerRecord {
        PlayerRecord(id: id, teamID: teamID, firstName: name, lastName: "", number: "",
                     leagueAge: nil, positionPreferences: [:], hittingStyle: nil, speed: nil,
                     onBase: nil, rosterOrder: order)
    }

    private func baseRows() -> TeamRows {
        var r = TeamRows(team: TeamRecord(
            id: teamID, name: "Cubs", colorHex: "0000FF", coachName: "Coach", gameInningCount: 6,
            fairPlayConfig: .object([:]), pitchingConfig: .object([:]), calendarSubscriptionURL: nil,
            defaultTemplateID: nil, currentLineupID: lineupID,
            createdAt: Date(timeIntervalSince1970: 1_790_000_000)))
        r.players = [p1: player(p1, "Ava", order: 0), p2: player(p2, "Ben", order: 1), p3: player(p3, "Cal", order: 2)]
        r.lineups = [lineupID: LineupRecord(
            id: lineupID, teamID: teamID, scheduledGameID: nil,
            gameDate: Date(timeIntervalSince1970: 1_790_000_000), opponent: "", inningCount: 6,
            battingOrder: [p1, p2, p3], absentPlayerIDs: [], status: "draft",
            lastFinalizedBy: nil, lastFinalizedAt: nil, defaultTemplateID: nil)]
        r.cells = [lineupID: [0: [p1: "P", p2: "C"], 1: [p1: "SS"]]]
        return r
    }

    // MARK: - Diff

    func testNothingChangedIsEmpty() {
        XCTAssertTrue(TeamRowsDiff.changes(from: baseRows(), to: baseRows()).isEmpty)
    }

    func testNewTeamSendsEverything() {
        let c = TeamRowsDiff.changes(from: nil, to: baseRows())
        XCTAssertTrue(c.isNewTeam)
        XCTAssertNotNil(c.team)
        // The open lineup is no longer sent (Merge 3) and this team has no
        // default template, so no pointer changed; push still writes pointers
        // for a new team because it checks isNewTeam.
        XCTAssertFalse(c.pointersChanged)
        XCTAssertEqual(c.players.count, 3)
        XCTAssertEqual(c.innings[lineupID]?.count, 6, "every inning, empty ones as clears")
        XCTAssertEqual(c.innings[lineupID]?[2], [:])
    }

    func testOneCellEditSendsOneInning() {
        var w = baseRows()
        w.cells[lineupID]?[1] = [p2: "SS"]
        let c = TeamRowsDiff.changes(from: baseRows(), to: w)
        XCTAssertEqual(c.innings, [lineupID: [1: [p2: "SS"]]])
        XCTAssertNil(c.team)
        XCTAssertTrue(c.lineups.isEmpty)
        XCTAssertEqual(c.rowCount, 1)
    }

    func testClearingAnInningSendsAnEmptyInning() {
        var w = baseRows()
        w.cells[lineupID]?[1] = nil
        XCTAssertEqual(TeamRowsDiff.changes(from: baseRows(), to: w).innings, [lineupID: [1: [:]]])
    }

    func testShorterLineupIsTrimmed() {
        var b = baseRows()
        b.cells[lineupID]?[5] = [p1: "P"]
        var w = b
        w.lineups[lineupID]?.inningCount = 5
        w.cells[lineupID]?[5] = nil
        let c = TeamRowsDiff.changes(from: b, to: w)
        XCTAssertEqual(c.trimmedLineups, [lineupID: 5])
        XCTAssertNil(c.innings[lineupID]?[5], "save_innings refuses innings past the count")
    }

    func testDeletesAreSplitByKind() {
        var w = baseRows()
        w.players[p3] = nil
        let gameID = UUID()
        var b = baseRows()
        b.scheduledGames[gameID] = ScheduledGameRecord(
            id: gameID, teamID: teamID, icalUID: "uid", startsAt: Date(timeIntervalSince1970: 1_790_000_000),
            opponent: nil, location: nil, rawSummary: "", isCancelled: false, lastSyncedAt: nil)
        let c = TeamRowsDiff.changes(from: b, to: w)
        XCTAssertEqual(c.deletedPlayers, [p3])
        XCTAssertEqual(c.deletedScheduledGames, [gameID])
    }

    func testRenameIsATeamChangeButNotAPointerChange() {
        var w = baseRows()
        w.team.name = "Cubs 10U"
        let c = TeamRowsDiff.changes(from: baseRows(), to: w)
        XCTAssertEqual(c.team?.name, "Cubs 10U")
        XCTAssertFalse(c.pointersChanged)
    }

    func testRemovedPitchCountsAreReplacedWithNone() {
        let logID = UUID()
        var b = baseRows()
        b.gameLogs[logID] = GameLogRecord(
            id: logID, teamID: teamID, gameDate: Date(timeIntervalSince1970: 1_790_000_000), opponent: "",
            inningsPlayed: 6, battingOrder: [], innings: [], playerSnapshot: [],
            archivedAt: Date(timeIntervalSince1970: 1_790_000_000), archivedBy: "", notes: "")
        b.pitchCounts[logID] = [p1.uuidString: 40]
        var w = b
        w.pitchCounts[logID] = nil
        XCTAssertEqual(TeamRowsDiff.changes(from: b, to: w).pitchCounts, [logID: [:]])
    }

    // MARK: - Merge

    func testOnlyTheServerChangedTakesTheServer() {
        var s = baseRows()
        s.players[p1]?.number = "7"
        let r = TeamRowsMerge.merge(base: baseRows(), local: baseRows(), server: s)
        XCTAssertEqual(r.rows, s)
        XCTAssertEqual(r.conflicts, 0)
    }

    func testOnlyTheDeviceChangedKeepsTheDevice() {
        var l = baseRows()
        l.players[p1]?.number = "7"
        let r = TeamRowsMerge.merge(base: baseRows(), local: l, server: baseRows())
        XCTAssertEqual(r.rows, l)
        XCTAssertEqual(r.conflicts, 0)
    }

    func testDifferentRowsChangedOnEachSideBothSurvive() {
        var l = baseRows(), s = baseRows()
        l.players[p1]?.number = "7"
        s.players[p2]?.number = "9"
        s.cells[lineupID]?[3] = [p3: "LF"]
        let r = TeamRowsMerge.merge(base: baseRows(), local: l, server: s)
        XCTAssertEqual(r.rows.players[p1]?.number, "7")
        XCTAssertEqual(r.rows.players[p2]?.number, "9")
        XCTAssertEqual(r.rows.cells[lineupID]?[3], [p3: "LF"])
        XCTAssertEqual(r.conflicts, 0)
    }

    func testSameRowChangedOnBothSidesTheDeviceWins() {
        var l = baseRows(), s = baseRows()
        l.cells[lineupID]?[0] = [p1: "C", p2: "P"]
        s.cells[lineupID]?[0] = [p3: "P"]
        let r = TeamRowsMerge.merge(base: baseRows(), local: l, server: s)
        XCTAssertEqual(r.rows.cells[lineupID]?[0], [p1: "C", p2: "P"])
        XCTAssertEqual(r.conflicts, 1)
    }

    // MARK: - Shared teams: rows merge field by field (Merge 5 test, 2026-11-24)

    /// The bug: the head coach finalized on the web while an assistant's phone
    /// held a lineup it had changed on its own (its date, reset at launch). The
    /// whole row went to the device, so the phone put the lineup back to draft.
    func testAFinalizeSurvivesADeviceThatChangedSomethingElse() {
        var l = baseRows(), s = baseRows()
        l.lineups[lineupID]?.gameDate = Date(timeIntervalSince1970: 1_795_000_000)
        let at = Date(timeIntervalSince1970: 1_795_000_100)
        s.lineups[lineupID]?.status = "finalized"
        s.lineups[lineupID]?.lastFinalizedBy = "Sam"
        s.lineups[lineupID]?.lastFinalizedAt = at
        let r = TeamRowsMerge.merge(base: baseRows(), local: l, server: s)
        let m = r.rows.lineups[lineupID]
        XCTAssertEqual(m?.status, "finalized", "the head coach's finalize stands")
        XCTAssertEqual(m?.lastFinalizedBy, "Sam")
        XCTAssertEqual(m?.lastFinalizedAt, at)
        XCTAssertEqual(m?.gameDate, Date(timeIntervalSince1970: 1_795_000_000), "and the device's own change too")
        XCTAssertEqual(r.conflicts, 0)
        // What the device then sends is only its date: nothing that undoes the finalize.
        let changes = TeamRowsDiff.changes(from: s, to: r.rows)
        XCTAssertEqual(changes.lineups.map(\.status), ["finalized"])
    }

    func testAFinalizeMovesAsOneWhenBothSidesChangedIt() {
        // The device reopened the lineup (an edit) while the server finalized
        // it again: the device wins the finalize as a whole, never half of it.
        var b = baseRows(), l = baseRows(), s = baseRows()
        b.lineups[lineupID]?.status = "finalized"; b.lineups[lineupID]?.lastFinalizedBy = "Sam"
        b.lineups[lineupID]?.lastFinalizedAt = Date(timeIntervalSince1970: 1_795_000_000)
        l = b; s = b
        l.lineups[lineupID]?.status = "draft"; l.lineups[lineupID]?.lastFinalizedBy = nil; l.lineups[lineupID]?.lastFinalizedAt = nil
        s.lineups[lineupID]?.lastFinalizedAt = Date(timeIntervalSince1970: 1_795_000_500)
        let r = TeamRowsMerge.merge(base: b, local: l, server: s)
        XCTAssertEqual(r.rows.lineups[lineupID]?.status, "draft")
        XCTAssertNil(r.rows.lineups[lineupID]?.lastFinalizedBy)
        XCTAssertNil(r.rows.lineups[lineupID]?.lastFinalizedAt)
        XCTAssertEqual(r.conflicts, 1)
    }

    func testAbsentPlayersCompareAsASet() {
        var b = baseRows(), l = baseRows(), s = baseRows()
        b.lineups[lineupID]?.absentPlayerIDs = [p1, p2, p3]
        l = b; s = b
        l.lineups[lineupID]?.opponent = "Tigers"
        s.lineups[lineupID]?.battingOrder = [p3, p2, p1]
        let r = TeamRowsMerge.merge(base: b, local: l, server: s)
        XCTAssertEqual(r.rows.lineups[lineupID]?.opponent, "Tigers")
        XCTAssertEqual(r.rows.lineups[lineupID]?.battingOrder, [p3, p2, p1])
        XCTAssertEqual(r.rows.lineups[lineupID]?.absentPlayerIDs, [p1, p2, p3])
        XCTAssertEqual(r.conflicts, 0)
    }

    func testPlayerFieldsMergeOneByOne() {
        var l = baseRows(), s = baseRows()
        l.players[p1]?.number = "7"
        s.players[p1]?.firstName = "Avery"
        let r = TeamRowsMerge.merge(base: baseRows(), local: l, server: s)
        XCTAssertEqual(r.rows.players[p1]?.number, "7")
        XCTAssertEqual(r.rows.players[p1]?.firstName, "Avery")
        XCTAssertEqual(r.conflicts, 0)
    }

    func testTheSameFieldChangedOnBothSidesStillGoesToTheDevice() {
        var l = baseRows(), s = baseRows()
        l.lineups[lineupID]?.opponent = "Tigers"
        s.lineups[lineupID]?.opponent = "Lions"
        let r = TeamRowsMerge.merge(base: baseRows(), local: l, server: s)
        XCTAssertEqual(r.rows.lineups[lineupID]?.opponent, "Tigers")
        XCTAssertEqual(r.conflicts, 1)
    }

    func testTeamFieldsMergeOneByOne() {
        var l = baseRows(), s = baseRows()
        l.team.fairPlayConfig = .object(["equalBenchTime": .bool(true)])
        s.team.name = "Cubs 10U"
        let r = TeamRowsMerge.merge(base: baseRows(), local: l, server: s)
        XCTAssertEqual(r.rows.team.name, "Cubs 10U")
        XCTAssertEqual(r.rows.team.fairPlayConfig, .object(["equalBenchTime": .bool(true)]))
        XCTAssertEqual(r.conflicts, 0)
    }

    func testServerDeleteOfARowTheDeviceEditedKeepsTheEdit() {
        var l = baseRows(), s = baseRows()
        l.players[p3]?.number = "12"
        s.players[p3] = nil
        let r = TeamRowsMerge.merge(base: baseRows(), local: l, server: s)
        XCTAssertEqual(r.rows.players[p3]?.number, "12")
        XCTAssertEqual(r.conflicts, 1)
    }

    func testDeviceDeleteOfARowTheServerEditedKeepsTheEdit() {
        var l = baseRows(), s = baseRows()
        l.players[p3] = nil
        s.players[p3]?.number = "12"
        let r = TeamRowsMerge.merge(base: baseRows(), local: l, server: s)
        XCTAssertEqual(r.rows.players[p3]?.number, "12")
    }

    func testAnUntouchedDeleteOnEitherSideGoesThrough() {
        var s = baseRows()
        s.players[p3] = nil
        XCTAssertNil(TeamRowsMerge.merge(base: baseRows(), local: baseRows(), server: s).rows.players[p3])
        var l = baseRows()
        l.players[p3] = nil
        XCTAssertNil(TeamRowsMerge.merge(base: baseRows(), local: l, server: baseRows()).rows.players[p3])
    }

    func testTwoLineupsForOneGameKeepTheDevicesOne() {
        let gameID = UUID(), mine = UUID(), theirs = UUID()
        func lineup(_ id: UUID) -> LineupRecord {
            var l = baseRows().lineups[lineupID]!
            l.id = id
            l.scheduledGameID = gameID
            return l
        }
        var l = baseRows(), s = baseRows()
        l.lineups[mine] = lineup(mine)
        l.cells[mine] = [0: [p1: "P"]]
        s.lineups[theirs] = lineup(theirs)
        s.cells[theirs] = [0: [p2: "P"]]
        let r = TeamRowsMerge.merge(base: baseRows(), local: l, server: s)
        XCTAssertNotNil(r.rows.lineups[mine])
        XCTAssertNil(r.rows.lineups[theirs])
        XCTAssertNil(r.rows.cells[theirs])
    }

    func testMergedResultThenDiffsToJustTheDevicesChanges() {
        var l = baseRows(), s = baseRows()
        l.players[p1]?.number = "7"
        s.players[p2]?.number = "9"
        let merged = TeamRowsMerge.merge(base: baseRows(), local: l, server: s).rows
        // After a pull the server's rows are the new base; what's left to send
        // is exactly the device's own edit.
        let c = TeamRowsDiff.changes(from: s, to: merged)
        XCTAssertEqual(c.players.map(\.id), [p1])
        XCTAssertEqual(c.rowCount, 1)
    }
}
