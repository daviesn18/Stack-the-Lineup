import XCTest
@testable import Lineup_Builder

// MARK: - Merge 2 + 3: the open game is each device's own
//
// OpenGame decides which lineup a device keeps open after a sync. The same
// rule lives in web/src/core/openGame.ts (and its tests); keep the two in step.

final class OpenGameTests: XCTestCase {

    private let teamID = UUID()
    private var cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/Los_Angeles")!; return c }()
    /// Saturday 2026-11-21, 10:00 Pacific.
    private let now = Date(timeIntervalSince1970: 1_795_284_000)

    private func rows() -> TeamRows {
        TeamRows(team: TeamRecord(
            id: teamID, name: "Cubs", colorHex: "0000FF", coachName: "Coach", gameInningCount: 6,
            fairPlayConfig: .object([:]), pitchingConfig: .object([:]), calendarSubscriptionURL: nil,
            defaultTemplateID: nil, currentLineupID: nil, createdAt: now))
    }

    @discardableResult
    private func addGame(_ r: inout TeamRows, at date: Date, cancelled: Bool = false, lineup: Bool = true,
                         opponent: String = "Tigers") -> (game: UUID, lineup: UUID) {
        let game = UUID(), lineupID = UUID()
        r.scheduledGames[game] = ScheduledGameRecord(id: game, teamID: teamID, icalUID: game.uuidString, startsAt: date,
                                                     opponent: opponent, location: nil, rawSummary: "vs \(opponent)",
                                                     isCancelled: cancelled, lastSyncedAt: nil)
        if lineup { addLineup(&r, id: lineupID, game: game) }
        return (game, lineupID)
    }

    private func addLineup(_ r: inout TeamRows, id: UUID, game: UUID?) {
        r.lineups[id] = LineupRecord(id: id, teamID: teamID, scheduledGameID: game, gameDate: now, opponent: "",
                                     inningCount: 6, battingOrder: [], absentPlayerIDs: [], status: "draft",
                                     lastFinalizedBy: nil, lastFinalizedAt: nil, defaultTemplateID: nil)
    }

    private func addLog(_ r: inout TeamRows, for game: UUID?, opponent: String = "Tigers") -> UUID {
        let id = UUID()
        r.gameLogs[id] = GameLogRecord(id: id, teamID: teamID, gameDate: now, opponent: opponent, inningsPlayed: 6,
                                       battingOrder: [], innings: [], playerSnapshot: [], archivedAt: now,
                                       archivedBy: "Team Owner", notes: "", scheduledGameID: game)
        return id
    }

    private let hour: TimeInterval = 3600

    // MARK: - Default

    func testDefaultIsTheNextGameFromTheStartOfToday() {
        var r = rows()
        addGame(&r, at: now.addingTimeInterval(48 * hour))
        let earlierToday = addGame(&r, at: now.addingTimeInterval(-2 * hour))   // 8am today: still "today"
        addGame(&r, at: now.addingTimeInterval(-30 * hour))                     // yesterday
        XCTAssertEqual(OpenGame.defaultLineup(in: r, now: now, calendar: cal), earlierToday.lineup)
    }

    func testDefaultSkipsCancelledGamesAndGamesWithoutALineup() {
        var r = rows()
        addGame(&r, at: now.addingTimeInterval(1 * hour), cancelled: true)
        addGame(&r, at: now.addingTimeInterval(2 * hour), lineup: false)
        let later = addGame(&r, at: now.addingTimeInterval(5 * hour))
        XCTAssertEqual(OpenGame.defaultLineup(in: r, now: now, calendar: cal), later.lineup)
    }

    func testDefaultFallsBackToTheLatestPastGameThenAdHoc() {
        var r = rows()
        addGame(&r, at: now.addingTimeInterval(-96 * hour))
        let latestPast = addGame(&r, at: now.addingTimeInterval(-30 * hour))
        XCTAssertEqual(OpenGame.defaultLineup(in: r, now: now, calendar: cal), latestPast.lineup)

        var adhocOnly = rows()
        let a = UUID(), b = UUID()
        addLineup(&adhocOnly, id: a, game: nil)
        addLineup(&adhocOnly, id: b, game: nil)
        XCTAssertEqual(OpenGame.defaultLineup(in: adhocOnly, preferredAdhoc: b, now: now, calendar: cal), b,
                       "this device's own ad-hoc lineup when there's a choice")
        XCTAssertNotNil(OpenGame.defaultLineup(in: adhocOnly, now: now, calendar: cal))
        XCTAssertNil(OpenGame.defaultLineup(in: rows(), now: now, calendar: cal), "no lineups at all")
    }

    // MARK: - Keeping the device's choice

    func testTheDevicesOpenGameStaysOpenEvenWhenNotTheDefault() {
        var r = rows()
        addGame(&r, at: now.addingTimeInterval(1 * hour))
        let later = addGame(&r, at: now.addingTimeInterval(72 * hour))
        let result = OpenGame.resolve(rows: r, openLineupID: later.lineup, openGameID: later.game, now: now, calendar: cal)
        XCTAssertEqual(result.lineupID, later.lineup)
        XCTAssertNil(result.archived)
    }

    func testAnAdHocLineupStaysOpen() {
        var r = rows()
        addGame(&r, at: now.addingTimeInterval(1 * hour))
        let adhoc = UUID()
        addLineup(&r, id: adhoc, game: nil)
        XCTAssertEqual(OpenGame.resolve(rows: r, openLineupID: adhoc, openGameID: nil, now: now, calendar: cal).lineupID, adhoc)
    }

    // MARK: - Archived elsewhere

    /// The web's archive_game keeps the row but detaches and clears it.
    func testArchivedOnTheWebMovesOnAndSaysWho() {
        var r = rows()
        let open = addGame(&r, at: now.addingTimeInterval(-1 * hour), opponent: "Tigers")
        let next = addGame(&r, at: now.addingTimeInterval(48 * hour), opponent: "Lions")
        r.lineups[open.lineup]?.scheduledGameID = nil
        let log = addLog(&r, for: open.game)
        let sam = UUID()
        let result = OpenGame.resolve(rows: r, openLineupID: open.lineup, openGameID: open.game,
                                      archivers: [log: GameLogArchiver(userID: sam, name: " Sam Rivera ")],
                                      me: UUID(), now: now, calendar: cal)
        XCTAssertEqual(result.lineupID, next.lineup)
        XCTAssertEqual(result.archived, OpenGame.Archived(byName: "Sam Rivera", byMe: false, opponent: "Tigers"))
        XCTAssertEqual(result.archived?.message, "Sam Rivera archived the game vs Tigers. Showing your next game.")
    }

    /// iOS's own archive deletes the game's row and logs it with the game id.
    func testArchivedOnMyOtherDeviceSaysYou() {
        var r = rows()
        let open = addGame(&r, at: now, opponent: "Tigers")
        r.lineups[open.lineup] = nil
        let log = addLog(&r, for: open.game)
        let me = UUID()
        let result = OpenGame.resolve(rows: r, openLineupID: open.lineup, openGameID: open.game,
                                      archivers: [log: GameLogArchiver(userID: me, name: "Nick")], me: me, now: now, calendar: cal)
        XCTAssertEqual(result.archived?.message, "You archived the game vs Tigers on another device. Showing your next game.")
    }

    /// "Archive and start new game" on the web keeps the open row and carries
    /// it forward as the next ad-hoc game. With no scheduled game ahead, the
    /// device follows that row, not an older ad-hoc lineup it kept a slot for.
    func testArchiveAndStartNewGameFollowsTheCarriedForwardRow() {
        var r = rows()
        let open = addGame(&r, at: now.addingTimeInterval(-1 * hour), opponent: "Lions")
        r.lineups[open.lineup]?.scheduledGameID = nil          // now the ad-hoc game vs Bears
        let stale = UUID()
        addLineup(&r, id: stale, game: nil)                    // an older ad-hoc lineup
        let log = addLog(&r, for: open.game, opponent: "Lions")
        let me = UUID()
        let result = OpenGame.resolve(rows: r, openLineupID: open.lineup, openGameID: open.game,
                                      archivers: [log: GameLogArchiver(userID: me, name: "")], me: me,
                                      preferredAdhoc: stale, now: now, calendar: cal)
        XCTAssertEqual(result.lineupID, open.lineup)
        XCTAssertEqual(result.archived?.message, "You archived the game vs Lions on another device. Showing your next game.")
    }

    func testAnArchiverWithNoNameIsAnotherCoach() {
        var r = rows()
        let open = addGame(&r, at: now, opponent: "")
        r.lineups[open.lineup] = nil
        _ = addLog(&r, for: open.game, opponent: "")
        let result = OpenGame.resolve(rows: r, openLineupID: open.lineup, openGameID: open.game, now: now, calendar: cal)
        XCTAssertEqual(result.archived?.message, "Another coach archived the game. Showing your next game.")
    }

    func testAGameTakenOffTheScheduleMovesOnQuietly() {
        var r = rows()
        let open = addGame(&r, at: now)
        r.lineups[open.lineup] = nil
        r.scheduledGames[open.game] = nil
        _ = addLog(&r, for: UUID())   // some other game's log
        let result = OpenGame.resolve(rows: r, openLineupID: open.lineup, openGameID: open.game, now: now, calendar: cal)
        XCTAssertNil(result.archived)
    }

    // MARK: - The pointer no longer syncs

    func testOpeningAnotherGameIsNotAChangeToSend() {
        var r = rows()
        let a = addGame(&r, at: now)
        let b = addGame(&r, at: now.addingTimeInterval(hour))
        r.team.currentLineupID = a.lineup
        var moved = r
        moved.team.currentLineupID = b.lineup
        let c = TeamRowsDiff.changes(from: r, to: moved)
        XCTAssertTrue(c.isEmpty, "which game is open stays on the device")
        XCTAssertFalse(c.pointersChanged)
    }
}

// MARK: - Archive parity (Merge 2)

@MainActor
final class ArchiveParityTests: XCTestCase {

    func testArchivingAScheduledGameLogsItAndLeavesNoRowForIt() {
        let store = LineupStore()
        var team = Team()
        team.name = "Reds"
        team.players = [Player(firstName: "Ava", lastName: "A", number: "1")]
        let game = ScheduledGame(icalUID: "G1", date: Date(), opponent: "Tigers", rawSummary: "vs Tigers")
        team.scheduledGames = [game]
        store.teams = [team]
        store.activeTeamID = team.id
        store.applyScheduledGame(game)

        var slots = LineupSlots()
        let before = TeamRowMapper.rows(from: store.activeTeam, slots: &slots).rows
        let gameRow = slots.games[game.id]
        XCTAssertNotNil(gameRow)
        XCTAssertEqual(before.lineups[gameRow!]?.scheduledGameID, game.id)

        store.archiveCurrentLineup(inningsPlayed: 6)

        XCTAssertEqual(store.activeTeam.gameLogs.first?.scheduledGameID, game.id, "the log says which game was played")
        let after = TeamRowMapper.rows(from: store.activeTeam, slots: &slots, base: before).rows
        XCTAssertFalse(after.lineups.values.contains { $0.scheduledGameID == game.id },
                       "no lineup for the played game, as after archive_game")
        let open = after.team.currentLineupID.flatMap { after.lineups[$0] }
        XCTAssertNil(open?.scheduledGameID, "an ad-hoc lineup is open")
        XCTAssertTrue(store.activeTeam.lineup.innings.allSatisfy { $0.assignments.values.allSatisfy { $0 == .bench } || $0.assignments.isEmpty },
                      "and it's cleared")
        XCTAssertEqual(after.gameLogs.values.first?.scheduledGameID, game.id)
    }
}
