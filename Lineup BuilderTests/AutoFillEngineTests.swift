import XCTest
@testable import Lineup_Builder

// MARK: - AutoFill Engine Tests
//
// Verifies that AutoFillEngine correctly respects FairPlayConfig when
// building position assignments. Each test constructs a minimal scenario,
// runs fill, and asserts on the resulting lineup.

final class AutoFillEngineTests: XCTestCase {

    // MARK: - Helpers

    private func makePlayer(_ name: String) -> Player {
        Player(firstName: name, lastName: "Test", number: "0")
    }

    private func makeLineup(innings: Int = 1) -> Lineup {
        Lineup(innings: Array(repeating: InningAssignment(), count: innings))
    }

    /// Returns the FieldPosition assigned to the player in a given inning, or nil.
    private func position(for player: Player, inning: Int, in lineup: Lineup) -> FieldPosition? {
        lineup.innings[inning].position(for: player)
    }

    // MARK: - noPitcher

    func testNoPitcherConfigNeverFillsPitcher() {
        var config = FairPlayConfig()
        config.noPitcher = true

        // 9 players — normally would fill pitcher
        let players = (1...9).map { makePlayer("P\($0)") }
        let lineup = makeLineup()

        let (result, _) = AutoFillEngine.fillInning(0, in: lineup, players: players, config: config)

        for player in players {
            let pos = position(for: player, inning: 0, in: result)
            XCTAssertNotEqual(pos, .pitcher, "\(player.firstName) should not be assigned pitcher when noPitcher is true")
        }
    }

    func testDefaultConfigMayFillPitcher() {
        let config = FairPlayConfig()
        let players = (1...9).map { makePlayer("P\($0)") }
        let lineup = makeLineup()

        let (result, _) = AutoFillEngine.fillInning(0, in: lineup, players: players, config: config)

        let hasPitcher = players.contains { position(for: $0, inning: 0, in: result) == .pitcher }
        XCTAssertTrue(hasPitcher, "Default config should fill pitcher slot")
    }

    // MARK: - noCatcher

    func testNoCatcherConfigNeverFillsCatcher() {
        var config = FairPlayConfig()
        config.noCatcher = true

        let players = (1...9).map { makePlayer("P\($0)") }
        let lineup = makeLineup()

        let (result, _) = AutoFillEngine.fillInning(0, in: lineup, players: players, config: config)

        for player in players {
            let pos = position(for: player, inning: 0, in: result)
            XCTAssertNotEqual(pos, .catcher, "\(player.firstName) should not be assigned catcher when noCatcher is true")
        }
    }

    // MARK: - outfielderCount

    func testThreeOFConfigNeverFillsLCForRCF() {
        let config = FairPlayConfig() // outfielderCount = 3
        let players = (1...9).map { makePlayer("P\($0)") }
        let lineup = makeLineup()

        let (result, _) = AutoFillEngine.fillInning(0, in: lineup, players: players, config: config)

        for player in players {
            let pos = position(for: player, inning: 0, in: result)
            XCTAssertNotEqual(pos, .leftCenterField, "LCF should not be filled with 3-OF config")
            XCTAssertNotEqual(pos, .rightCenterField, "RCF should not be filled with 3-OF config")
        }
    }

    func testFourOFConfigFillsLCFandRCFNotCF() {
        var config = FairPlayConfig()
        config.outfielderCount = 4

        // 10 players to fill all 10 field slots (6 IF + LF + LCF + RCF + RF)
        let players = (1...10).map { makePlayer("P\($0)") }
        let lineup = makeLineup()

        let (result, _) = AutoFillEngine.fillInning(0, in: lineup, players: players, config: config)

        let allPositions = players.compactMap { position(for: $0, inning: 0, in: result) }
        XCTAssertTrue(allPositions.contains(.leftCenterField), "LCF should be filled with 4-OF config")
        XCTAssertTrue(allPositions.contains(.rightCenterField), "RCF should be filled with 4-OF config")
        XCTAssertFalse(allPositions.contains(.centerField), "CF should not be filled with 4-OF config")
    }

    func testFourOFConfigProducesCorrectFieldSlotCount() {
        var config = FairPlayConfig()
        config.outfielderCount = 4

        let players = (1...10).map { makePlayer("P\($0)") }
        let lineup = makeLineup()

        let (result, filledCount) = AutoFillEngine.fillInning(0, in: lineup, players: players, config: config)

        // All 10 players should be assigned (10 field slots, 10 players)
        let fieldAssignments = players.filter {
            guard let pos = position(for: $0, inning: 0, in: result) else { return false }
            return !pos.isBench
        }
        XCTAssertEqual(fieldAssignments.count, 10)
        XCTAssertEqual(filledCount, 10)
    }

    // MARK: - Combined restrictions

    func testNoPitcherAndNoCatcherBothRespected() {
        var config = FairPlayConfig()
        config.noPitcher = true
        config.noCatcher = true

        let players = (1...9).map { makePlayer("P\($0)") }
        let lineup = makeLineup()

        let (result, _) = AutoFillEngine.fillInning(0, in: lineup, players: players, config: config)

        for player in players {
            let pos = position(for: player, inning: 0, in: result)
            XCTAssertNotEqual(pos, .pitcher)
            XCTAssertNotEqual(pos, .catcher)
        }
    }

    // MARK: - Pre-existing assignments not overwritten

    func testExistingAssignmentNotOverwritten() {
        var config = FairPlayConfig()
        config.noPitcher = false

        let pitcher = makePlayer("Ace")
        var lineup = makeLineup()
        lineup.innings[0].assign(player: pitcher, position: .pitcher)

        let otherPlayers = (1...8).map { makePlayer("P\($0)") }
        let allPlayers = [pitcher] + otherPlayers

        let (result, _) = AutoFillEngine.fillInning(0, in: lineup, players: allPlayers, config: config)

        XCTAssertEqual(position(for: pitcher, inning: 0, in: result), .pitcher,
                       "Pre-assigned pitcher should remain pitcher after AutoFill")
    }

    // MARK: - fillInnings (multi-inning)

    func testFillInningsRespectsConfigAcrossAllInnings() {
        var config = FairPlayConfig()
        config.noPitcher = true

        let players = (1...9).map { makePlayer("P\($0)") }
        let lineup = makeLineup(innings: 4)

        let (result, _) = AutoFillEngine.fillInnings(through: 3, in: lineup, players: players, config: config)

        for inningIdx in 0..<4 {
            for player in players {
                let pos = position(for: player, inning: inningIdx, in: result)
                XCTAssertNotEqual(pos, .pitcher, "Pitcher should never be assigned in inning \(inningIdx + 1) when noPitcher is true")
            }
        }
    }

    // MARK: - fillGame

    func testFillGameRespectsConfig() {
        var config = FairPlayConfig()
        config.noCatcher = true

        let players = (1...9).map { makePlayer("P\($0)") }
        let lineup = makeLineup(innings: 6)

        let (result, _) = AutoFillEngine.fillGame(in: lineup, players: players, config: config)

        for inningIdx in 0..<6 {
            for player in players {
                let pos = position(for: player, inning: inningIdx, in: result)
                XCTAssertNotEqual(pos, .catcher, "Catcher should never be assigned in any inning when noCatcher is true")
            }
        }
    }

    // MARK: - Default config matches previous behavior

    func testDefaultConfigFillsAllNinePositions() {
        let config = FairPlayConfig()
        let players = (1...9).map { makePlayer("P\($0)") }
        let lineup = makeLineup()

        let (result, filledCount) = AutoFillEngine.fillInning(0, in: lineup, players: players, config: config)

        XCTAssertEqual(filledCount, 9, "9 players with default config should fill exactly 9 slots")
        for player in players {
            let pos = position(for: player, inning: 0, in: result)
            XCTAssertNotNil(pos, "\(player.firstName) should have a position assigned")
        }
    }
}
