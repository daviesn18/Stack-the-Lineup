import XCTest
import SwiftUI
@testable import Lineup_Builder

// MARK: - LineupStore Tests
//
// Verifies LineupStore mutation methods behave correctly: fair play config
// updates write to the right team, inning count resizing, player operations,
// and multi-team isolation. These tests instantiate a real LineupStore in
// memory (no persistence) and exercise it through its public API.

@MainActor
final class LineupStoreTests: XCTestCase {

    // MARK: - Setup

    private var store: LineupStore!

    override func setUp() async throws {
        store = LineupStore()
        // Start fresh with one team
        store.teams = [makeTeam("Reds")]
        store.activeTeamID = store.teams[0].id
    }

    // MARK: - Helpers

    private func makeTeam(_ name: String) -> Team {
        var team = Team()
        team.name = name
        return team
    }

    private func makePlayer(_ name: String) -> Player {
        Player(firstName: name, lastName: "Test", number: "0")
    }

    // MARK: - updateFairPlayConfig

    func testUpdateFairPlayConfigWritesToCorrectTeam() {
        // Add a second team
        var second = makeTeam("Blues")
        store.teams.append(second)
        let secondID = second.id

        var config = FairPlayConfig()
        config.noPitcher = true
        config.minimumFieldingInnings = 3
        config.outfielderCount = 4

        store.updateFairPlayConfig(config, for: secondID)

        let updated = store.teams.first { $0.id == secondID }!
        XCTAssertTrue(updated.fairPlayConfig.noPitcher)
        XCTAssertEqual(updated.fairPlayConfig.minimumFieldingInnings, 3)
        XCTAssertEqual(updated.fairPlayConfig.outfielderCount, 4)
    }

    func testUpdateFairPlayConfigDoesNotAffectOtherTeams() {
        var second = makeTeam("Blues")
        store.teams.append(second)
        let firstID = store.teams[0].id
        let secondID = second.id

        var config = FairPlayConfig()
        config.noPitcher = true
        store.updateFairPlayConfig(config, for: secondID)

        let firstTeam = store.teams.first { $0.id == firstID }!
        XCTAssertFalse(firstTeam.fairPlayConfig.noPitcher,
                       "Config update for team 2 should not affect team 1")
    }

    func testUpdateFairPlayConfigForActiveTeam() {
        let activeID = store.activeTeamID!
        var config = FairPlayConfig()
        config.equalBenchTime = true
        config.catcherToPitcherThreshold = 3

        store.updateFairPlayConfig(config, for: activeID)

        XCTAssertTrue(store.fairPlayConfig.equalBenchTime)
        XCTAssertEqual(store.fairPlayConfig.catcherToPitcherThreshold, 3)
    }

    func testUpdateFairPlayConfigWithUnknownIDIsNoop() {
        let originalConfig = store.teams[0].fairPlayConfig
        let unknownID = UUID()

        var config = FairPlayConfig()
        config.noPitcher = true
        store.updateFairPlayConfig(config, for: unknownID)

        // Active team should be unchanged
        XCTAssertFalse(store.fairPlayConfig.noPitcher,
                       "Update with unknown ID should be a no-op")
        XCTAssertEqual(store.fairPlayConfig.minimumFieldingInnings,
                       originalConfig.minimumFieldingInnings)
    }

    // MARK: - fairPlayConfig passthrough

    func testFairPlayConfigPassthroughReflectsActiveTeam() {
        var config = FairPlayConfig()
        config.outfielderCount = 4
        store.teams[0].fairPlayConfig = config

        XCTAssertEqual(store.fairPlayConfig.outfielderCount, 4)
    }

    func testFairPlayConfigPassthroughUpdatesWhenTeamSwitches() {
        var second = makeTeam("Blues")
        second.fairPlayConfig.noPitcher = true
        store.teams.append(second)

        XCTAssertFalse(store.fairPlayConfig.noPitcher, "Active team should not have noPitcher")

        store.switchTeam(to: second.id)
        XCTAssertTrue(store.fairPlayConfig.noPitcher, "After switching, should reflect second team's config")
    }

    // MARK: - updateGameInningCount

    func testInningCountIncreasePadsLineup() {
        let id = store.activeTeamID!
        store.updateGameInningCount(5, for: id)
        XCTAssertEqual(store.lineup.innings.count, 5)

        store.updateGameInningCount(7, for: id)
        XCTAssertEqual(store.lineup.innings.count, 7)
    }

    func testInningCountDecreaseTrimsLineup() {
        let id = store.activeTeamID!
        store.updateGameInningCount(7, for: id)
        store.updateGameInningCount(5, for: id)
        XCTAssertEqual(store.lineup.innings.count, 5)
    }

    func testInningCountClampsToValidRange() {
        let id = store.activeTeamID!
        store.updateGameInningCount(0, for: id) // below min
        XCTAssertEqual(store.gameInningCount, 1)

        store.updateGameInningCount(99, for: id) // above max
        XCTAssertEqual(store.gameInningCount, 9)
    }

    // MARK: - updateTeamDetails
    //
    // Edit Team used to mutate teams[idx] by hand, call updateGameInningCount
    // (which saves) and then save() again — two full CloudKit uploads per
    // submission. The trailing save() was load-bearing on the path where the
    // inning count didn't change, so the fix had to keep both fields persisting
    // through one save rather than just dropping a line.

    func testUpdateTeamDetailsAppliesEveryFieldWhenInningCountChanges() {
        let id = store.activeTeamID!
        store.updateTeamDetails(id: id, name: "Sharks", color: .red, coachName: "Alex", gameInningCount: 5)

        XCTAssertEqual(store.teams[0].name, "Sharks")
        // Assert on the stored hex, not the Color: `color` round-trips through
        // colorHex, so the value read back is not `==` to the one passed in.
        XCTAssertEqual(store.teams[0].colorHex, Color.red.toHex())
        XCTAssertEqual(store.teams[0].coachName, "Alex")
        XCTAssertEqual(store.teams[0].gameInningCount, 5)
        XCTAssertEqual(store.teams[0].lineup.innings.count, 5, "Lineup should resize with the count")
    }

    func testUpdateTeamDetailsPersistsNameWhenInningCountUnchanged() {
        let id = store.activeTeamID!
        let unchanged = store.teams[0].gameInningCount

        store.updateTeamDetails(id: id, name: "Sharks", color: .red, coachName: "Alex", gameInningCount: unchanged)

        XCTAssertEqual(store.teams[0].name, "Sharks", "Name must still be applied when the count doesn't move")
        XCTAssertEqual(store.teams[0].coachName, "Alex")
        XCTAssertEqual(store.teams[0].gameInningCount, unchanged)
    }

    func testUpdateTeamDetailsIgnoresUnknownTeam() {
        store.updateTeamDetails(id: UUID(), name: "Ghost", color: .red, coachName: "Nobody", gameInningCount: 5)

        XCTAssertEqual(store.teams.count, 1)
        XCTAssertEqual(store.teams[0].name, "Reds")
    }

    func testUpdateTeamDetailsClampsInningCount() {
        let id = store.activeTeamID!
        store.updateTeamDetails(id: id, name: "Reds", color: .blue, coachName: "", gameInningCount: 99)
        XCTAssertEqual(store.teams[0].gameInningCount, 9)
    }

    // MARK: - addTeam

    func testAddTeamAppliesGameInningCount() {
        store.addTeam(name: "Blues", color: .green, gameInningCount: 5)

        XCTAssertEqual(store.activeTeam.name, "Blues")
        XCTAssertEqual(store.activeTeam.gameInningCount, 5)
        XCTAssertEqual(store.activeTeam.lineup.innings.count, 5)
    }

    func testAddTeamWithoutInningCountKeepsTheDefault() {
        store.addTeam(name: "Blues")

        XCTAssertEqual(store.activeTeam.gameInningCount, Team().gameInningCount)
        XCTAssertEqual(store.activeTeam.lineup.innings.count, Lineup.inningCount)
    }

    // MARK: - Player operations

    func testAddPlayerAppendsToRosterAndBattingOrder() {
        let player = makePlayer("Cam")
        store.addPlayer(player)

        XCTAssertTrue(store.players.contains { $0.id == player.id })
        XCTAssertTrue(store.lineup.battingOrder.contains(player.id))
    }

    func testDeletePlayerRemovesFromRosterAndOrder() {
        let player = makePlayer("Leo")
        store.addPlayer(player)
        store.deletePlayer(at: IndexSet(integer: store.players.firstIndex { $0.id == player.id }!))

        XCTAssertFalse(store.players.contains { $0.id == player.id })
        XCTAssertFalse(store.lineup.battingOrder.contains(player.id))
    }

    func testUpdatePlayerPreservesID() {
        let player = makePlayer("Eli")
        store.addPlayer(player)

        var updated = player
        updated.firstName = "Elijah"
        store.updatePlayer(updated)

        let found = store.players.first { $0.id == player.id }
        XCTAssertEqual(found?.firstName, "Elijah")
    }

    // MARK: - Multi-team isolation

    func testEachTeamHasItsOwnFairPlayConfig() {
        var teamA = makeTeam("TeamA")
        var teamB = makeTeam("TeamB")
        teamA.fairPlayConfig.noPitcher = true
        teamB.fairPlayConfig.noCatcher = true
        store.teams = [teamA, teamB]
        store.activeTeamID = teamA.id

        store.switchTeam(to: teamA.id)
        XCTAssertTrue(store.fairPlayConfig.noPitcher)
        XCTAssertFalse(store.fairPlayConfig.noCatcher)

        store.switchTeam(to: teamB.id)
        XCTAssertFalse(store.fairPlayConfig.noPitcher)
        XCTAssertTrue(store.fairPlayConfig.noCatcher)
    }

    func testEachTeamHasItsOwnRoster() {
        var second = makeTeam("Blues")
        store.teams.append(second)

        store.addPlayer(makePlayer("Alice"))
        XCTAssertEqual(store.players.count, 1)

        store.switchTeam(to: second.id)
        XCTAssertEqual(store.players.count, 0, "Second team should start with empty roster")
    }

    // MARK: - clearPositions respects gameInningCount

    func testClearPositionsResetsToCorrectInningCount() {
        let id = store.activeTeamID!
        store.updateGameInningCount(5, for: id)
        store.addPlayer(makePlayer("Test"))
        store.assignPosition(player: store.players[0], inning: 0, position: .leftField)

        store.clearPositions()
        XCTAssertEqual(store.lineup.innings.count, 5, "Clear should preserve inning count")
        XCTAssertTrue(store.lineup.innings[0].assignments.isEmpty)
    }

    // MARK: - shouldPreferCloudBlob (sync freshness)

    // The iCloud KV copy must only shadow local data when it is strictly newer.
    // Missing timestamps (legacy blobs) sort oldest; ties prefer local. This is
    // the guard against the July 2026 KV clobber incident.

    private let blob = Data("x".utf8)

    func testCloudBlobIgnoredWhenAbsent() {
        XCTAssertFalse(LineupStore.shouldPreferCloudBlob(
            cloudData: nil, cloudSavedAt: 999, localData: blob, localSavedAt: 0))
        XCTAssertFalse(LineupStore.shouldPreferCloudBlob(
            cloudData: nil, cloudSavedAt: 0, localData: nil, localSavedAt: 0))
    }

    func testCloudBlobUsedWhenNoLocalData() {
        XCTAssertTrue(LineupStore.shouldPreferCloudBlob(
            cloudData: blob, cloudSavedAt: 0, localData: nil, localSavedAt: 0),
            "First launch on a new device should adopt the synced blob even without a timestamp")
    }

    func testNewerCloudBlobWins() {
        XCTAssertTrue(LineupStore.shouldPreferCloudBlob(
            cloudData: blob, cloudSavedAt: 200, localData: blob, localSavedAt: 100))
    }

    func testOlderCloudBlobLoses() {
        XCTAssertFalse(LineupStore.shouldPreferCloudBlob(
            cloudData: blob, cloudSavedAt: 100, localData: blob, localSavedAt: 200))
    }

    func testTieAndLegacyBlobsPreferLocal() {
        XCTAssertFalse(LineupStore.shouldPreferCloudBlob(
            cloudData: blob, cloudSavedAt: 150, localData: blob, localSavedAt: 150))
        // Both legacy (no timestamps): local device's own data must win.
        XCTAssertFalse(LineupStore.shouldPreferCloudBlob(
            cloudData: blob, cloudSavedAt: 0, localData: blob, localSavedAt: 0))
        // Legacy cloud blob vs stamped local: local wins.
        XCTAssertFalse(LineupStore.shouldPreferCloudBlob(
            cloudData: blob, cloudSavedAt: 0, localData: blob, localSavedAt: 100))
    }

    // MARK: - Per-game lineups (doubleheader support)

    private func makeScheduledGame(_ uid: String, opponent: String, date: Date = Date()) -> ScheduledGame {
        ScheduledGame(icalUID: uid, date: date, opponent: opponent, rawSummary: "vs \(opponent)")
    }

    /// Sets the working lineup's batting order to a single marker id, so a test
    /// can tell which game's lineup is currently loaded.
    private func markWorkingLineup(_ marker: UUID) {
        let idx = store.teams.firstIndex { $0.id == store.activeTeamID }!
        store.teams[idx].lineup.battingOrder = [marker]
    }

    func testDoubleheaderGamesKeepIndependentLineups() {
        // Two games on the same day — the exact case the coach reported.
        let day = Date()
        let gameA = makeScheduledGame("A", opponent: "Eagles", date: day)
        let gameB = makeScheduledGame("B", opponent: "Hawks", date: day)
        let idx = store.teams.firstIndex { $0.id == store.activeTeamID }!
        store.teams[idx].scheduledGames = [gameA, gameB]

        let markerA = UUID()
        let markerB = UUID()

        store.applyScheduledGame(gameA)
        markWorkingLineup(markerA)

        store.applyScheduledGame(gameB)
        XCTAssertEqual(store.lineup.opponent, "Hawks", "Opening game B seeds a fresh lineup")
        XCTAssertNotEqual(store.lineup.battingOrder, [markerA], "Game B must not inherit game A's lineup")
        markWorkingLineup(markerB)

        // Switch back to game A: its lineup must be exactly what we left.
        store.applyScheduledGame(gameA)
        XCTAssertEqual(store.lineup.battingOrder, [markerA], "Game A's lineup must be restored intact")
        XCTAssertEqual(store.currentGame?.id, gameA.id)

        // And game B is still independently preserved in the stash.
        XCTAssertEqual(store.savedLineup(for: gameB)?.battingOrder, [markerB])
    }

    func testFinalizedStatusSurvivesGameSwitch() {
        // Reported bug: finalize game A, build+finalize game B, come back to A
        // and it had reverted to draft. Switching games must not revert.
        let day = Date()
        let gameA = makeScheduledGame("A", opponent: "Eagles", date: day)
        let gameB = makeScheduledGame("B", opponent: "Hawks", date: day)
        let idx = store.teams.firstIndex { $0.id == store.activeTeamID }!
        store.teams[idx].scheduledGames = [gameA, gameB]

        store.applyScheduledGame(gameA)
        store.finalizeLineup()
        XCTAssertEqual(store.lineup.status, .finalized)

        store.applyScheduledGame(gameB)
        store.finalizeLineup()

        // A must still read as finalized from its stash while B is the open game.
        XCTAssertEqual(store.savedLineup(for: gameA)?.status, .finalized,
                       "Game A must stay finalized after building and finalizing game B")

        // And reopening A restores its finalized status, not draft.
        store.applyScheduledGame(gameA)
        XCTAssertEqual(store.lineup.status, .finalized, "Reopening game A restores its finalized status")
    }

    func testFirstPickKeepsAdHocLineup() {
        // Picking a game for the first time with an in-progress ad-hoc lineup
        // must keep that work (pre-doubleheader behavior), only stamping the
        // game's opponent — not seed a blank grid over it.
        let marker = UUID()
        markWorkingLineup(marker)

        let game = makeScheduledGame("A", opponent: "Eagles")
        let idx = store.teams.firstIndex { $0.id == store.activeTeamID }!
        store.teams[idx].scheduledGames = [game]

        store.applyScheduledGame(game)

        XCTAssertEqual(store.lineup.battingOrder, [marker], "The ad-hoc lineup's work is carried into the game")
        XCTAssertEqual(store.lineup.opponent, "Eagles", "The game's opponent is stamped on")
        XCTAssertEqual(store.currentGame?.id, game.id)
    }

    func testApplyScheduledGameSetsCurrentGame() {
        let game = makeScheduledGame("A", opponent: "Eagles")
        let idx = store.teams.firstIndex { $0.id == store.activeTeamID }!
        store.teams[idx].scheduledGames = [game]

        XCTAssertNil(store.currentGame, "No game is open before applying one")
        store.applyScheduledGame(game)

        XCTAssertEqual(store.currentGame?.id, game.id)
        XCTAssertEqual(store.lineup.opponent, "Eagles")
        // savedLineup for the open game returns the live working lineup.
        XCTAssertNotNil(store.savedLineup(for: game))
    }

    func testArchiveClearsCurrentGameSlot() {
        let game = makeScheduledGame("A", opponent: "Eagles")
        let idx = store.teams.firstIndex { $0.id == store.activeTeamID }!
        store.teams[idx].scheduledGames = [game]

        store.applyScheduledGame(game)
        markWorkingLineup(UUID())
        XCTAssertNotNil(store.currentGame)

        store.archiveCurrentLineup(inningsPlayed: store.activeTeam.gameInningCount)

        XCTAssertNil(store.activeTeam.currentGameID, "Archiving detaches the working lineup from its game")
        XCTAssertNil(store.savedLineup(for: game), "The played game's saved lineup slot is cleared")
    }

    func testClearSchedulePrunesGameLineups() {
        let game = makeScheduledGame("A", opponent: "Eagles")
        let idx = store.teams.firstIndex { $0.id == store.activeTeamID }!
        store.teams[idx].scheduledGames = [game]
        store.applyScheduledGame(game)
        markWorkingLineup(UUID())

        store.clearSchedule()

        XCTAssertTrue(store.activeTeam.gameLineups.isEmpty, "Clearing the schedule prunes orphaned per-game lineups")
        XCTAssertNil(store.activeTeam.currentGameID, "The working lineup detaches when its game is removed")
    }

    func testTeamBlobRoundTripsPerGameLineups() throws {
        let gameID = UUID()
        var lineup = Lineup(opponent: "Eagles")
        let marker = UUID()
        lineup.battingOrder = [marker]

        var team = Team()
        team.gameLineups = [gameID: lineup]
        team.currentGameID = gameID

        let data = try JSONEncoder().encode(team)
        let decoded = try JSONDecoder().decode(Team.self, from: data)

        XCTAssertEqual(decoded.currentGameID, gameID)
        XCTAssertEqual(decoded.gameLineups[gameID]?.battingOrder, [marker])
        XCTAssertEqual(decoded.gameLineups[gameID]?.opponent, "Eagles")
    }

    func testLegacyBlobWithoutStashDecodesSafely() throws {
        // A Team blob written before per-game lineups existed has neither key.
        let json = Data(#"{"name":"Legacy","gameInningCount":6}"#.utf8)
        let decoded = try JSONDecoder().decode(Team.self, from: json)

        XCTAssertEqual(decoded.name, "Legacy")
        XCTAssertEqual(decoded.gameInningCount, 6)
        XCTAssertTrue(decoded.gameLineups.isEmpty, "Missing stash decodes to empty")
        XCTAssertNil(decoded.currentGameID, "Missing current game decodes to nil (ad-hoc lineup)")
    }
}

// MARK: - CloudPushDebouncer Tests
//
// The debounce policy behind the CloudKit push (backlog 3.2), tested in
// isolation from CloudKit. The flush-driven cases are deterministic; the two
// timer cases use a short interval with wide margins to avoid flake.

@MainActor
final class CloudPushDebouncerTests: XCTestCase {

    /// Escaping, non-Sendable sink for the fired id sets — the debouncer calls
    /// `perform` on the main actor and the test reads it on the main actor.
    private final class Sink { var calls: [Set<UUID>] = [] }

    // MARK: - Flush (deterministic)

    func testRepeatedSchedulesCoalesceToOneFlush() {
        let sink = Sink()
        let debouncer = CloudPushDebouncer(interval: .seconds(60)) { sink.calls.append($0) }
        let a = UUID()

        debouncer.schedule(a)
        debouncer.schedule(a)
        debouncer.schedule(a)
        XCTAssertTrue(debouncer.hasPendingWork)

        debouncer.flush()

        XCTAssertEqual(sink.calls, [[a]], "Three schedules of one team must flush as a single push")
        XCTAssertFalse(debouncer.hasPendingWork)
    }

    func testFlushDrainsEveryDirtyTeam() {
        let sink = Sink()
        let debouncer = CloudPushDebouncer(interval: .seconds(60)) { sink.calls.append($0) }
        let a = UUID(), b = UUID()

        // A team switch between edits must not drop the first team's push.
        debouncer.schedule(a)
        debouncer.schedule(b)
        debouncer.flush()

        XCTAssertEqual(sink.calls.count, 1)
        XCTAssertEqual(sink.calls.first, [a, b], "Both dirty teams must be pushed together")
    }

    func testFlushWithNothingPendingIsANoOp() {
        let sink = Sink()
        let debouncer = CloudPushDebouncer(interval: .seconds(60)) { sink.calls.append($0) }

        debouncer.flush()

        XCTAssertTrue(sink.calls.isEmpty, "Flushing with no dirty teams must not fire perform")
        XCTAssertFalse(debouncer.hasPendingWork)
    }

    func testDirtySetResetsAfterFlush() {
        let sink = Sink()
        let debouncer = CloudPushDebouncer(interval: .seconds(60)) { sink.calls.append($0) }
        let a = UUID(), b = UUID()

        debouncer.schedule(a)
        debouncer.flush()
        debouncer.schedule(b)
        debouncer.flush()

        XCTAssertEqual(sink.calls, [[a], [b]], "A team pushed once must not re-appear in the next flush")
    }

    // MARK: - Trailing timer (short interval, wide margins)

    func testTrailingTimerFiresWithoutAFlush() async throws {
        let sink = Sink()
        let debouncer = CloudPushDebouncer(interval: .milliseconds(40)) { sink.calls.append($0) }
        let a = UUID()

        debouncer.schedule(a)
        try await Task.sleep(for: .milliseconds(220))

        XCTAssertEqual(sink.calls, [[a]], "The trailing timer must fire the push on its own")
        XCTAssertFalse(debouncer.hasPendingWork)
    }

    func testScheduleWithinIntervalRestartsTheTimer() async throws {
        let sink = Sink()
        let debouncer = CloudPushDebouncer(interval: .milliseconds(60)) { sink.calls.append($0) }
        let a = UUID()

        debouncer.schedule(a)
        try await Task.sleep(for: .milliseconds(30))   // before the first timer would fire
        debouncer.schedule(a)                          // restarts the clock
        try await Task.sleep(for: .milliseconds(240))

        XCTAssertEqual(sink.calls, [[a]], "A reschedule inside the window must still produce one push")
    }
}
