import XCTest
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

    override func setUp() {
        super.setUp()
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
}
