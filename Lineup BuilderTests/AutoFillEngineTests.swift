import XCTest
@testable import Lineup_Builder

// MARK: - AutoFill Engine Tests
//
// Verifies that AutoFillEngine correctly respects FairPlayConfig when
// building position assignments. Each test constructs a minimal scenario,
// runs fill, and asserts on the resulting AutoFillResult.
//
// API note: all public AutoFillEngine methods return AutoFillResult, not a
// tuple. Access the filled lineup via result.lineup, the count via
// result.filledCount, and unfilled diagnostics via result.unfilledSlots.

@MainActor
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

        let players = (1...9).map { makePlayer("P\($0)") }
        let fill = AutoFillEngine.fillInning(0, in: makeLineup(), players: players, config: config)

        for player in players {
            let pos = position(for: player, inning: 0, in: fill.lineup)
            XCTAssertNotEqual(pos, .pitcher, "\(player.firstName) should not be assigned pitcher when noPitcher is true")
        }
    }

    func testDefaultConfigMayFillPitcher() {
        let players = (1...9).map { makePlayer("P\($0)") }
        let fill = AutoFillEngine.fillInning(0, in: makeLineup(), players: players, config: FairPlayConfig())

        let hasPitcher = players.contains { position(for: $0, inning: 0, in: fill.lineup) == .pitcher }
        XCTAssertTrue(hasPitcher, "Default config should fill pitcher slot")
    }

    // MARK: - noCatcher

    func testNoCatcherConfigNeverFillsCatcher() {
        var config = FairPlayConfig()
        config.noCatcher = true

        let players = (1...9).map { makePlayer("P\($0)") }
        let fill = AutoFillEngine.fillInning(0, in: makeLineup(), players: players, config: config)

        for player in players {
            let pos = position(for: player, inning: 0, in: fill.lineup)
            XCTAssertNotEqual(pos, .catcher, "\(player.firstName) should not be assigned catcher when noCatcher is true")
        }
    }

    // MARK: - outfielderCount

    func testThreeOFConfigNeverFillsLCForRCF() {
        let config = FairPlayConfig() // outfielderCount defaults to 3
        let players = (1...9).map { makePlayer("P\($0)") }
        let fill = AutoFillEngine.fillInning(0, in: makeLineup(), players: players, config: config)

        for player in players {
            let pos = position(for: player, inning: 0, in: fill.lineup)
            XCTAssertNotEqual(pos, .leftCenterField, "LCF should not be filled with 3-OF config")
            XCTAssertNotEqual(pos, .rightCenterField, "RCF should not be filled with 3-OF config")
        }
    }

    func testFourOFConfigFillsLCFandRCFNotCF() {
        var config = FairPlayConfig()
        config.outfielderCount = 4

        // 10 players to fill all 10 field slots (6 IF + LF + LCF + RCF + RF)
        let players = (1...10).map { makePlayer("P\($0)") }
        let fill = AutoFillEngine.fillInning(0, in: makeLineup(), players: players, config: config)

        let allPositions = players.compactMap { position(for: $0, inning: 0, in: fill.lineup) }
        XCTAssertTrue(allPositions.contains(.leftCenterField), "LCF should be filled with 4-OF config")
        XCTAssertTrue(allPositions.contains(.rightCenterField), "RCF should be filled with 4-OF config")
        XCTAssertFalse(allPositions.contains(.centerField), "CF should not be filled with 4-OF config")
    }

    func testFourOFConfigProducesCorrectFieldSlotCount() {
        var config = FairPlayConfig()
        config.outfielderCount = 4

        let players = (1...10).map { makePlayer("P\($0)") }
        let fill = AutoFillEngine.fillInning(0, in: makeLineup(), players: players, config: config)

        let fieldAssignments = players.filter {
            guard let pos = position(for: $0, inning: 0, in: fill.lineup) else { return false }
            return !pos.isBench
        }
        XCTAssertEqual(fieldAssignments.count, 10)
        XCTAssertEqual(fill.filledCount, 10)
    }

    // MARK: - Combined restrictions

    func testNoPitcherAndNoCatcherBothRespected() {
        var config = FairPlayConfig()
        config.noPitcher = true
        config.noCatcher = true

        let players = (1...9).map { makePlayer("P\($0)") }
        let fill = AutoFillEngine.fillInning(0, in: makeLineup(), players: players, config: config)

        for player in players {
            let pos = position(for: player, inning: 0, in: fill.lineup)
            XCTAssertNotEqual(pos, .pitcher)
            XCTAssertNotEqual(pos, .catcher)
        }
    }

    // MARK: - Pre-existing assignments not overwritten

    func testExistingAssignmentNotOverwritten() {
        let pitcher = makePlayer("Ace")
        var lineup = makeLineup()
        lineup.innings[0].assign(player: pitcher, position: .pitcher)

        let allPlayers = [pitcher] + (1...8).map { makePlayer("P\($0)") }
        let fill = AutoFillEngine.fillInning(0, in: lineup, players: allPlayers, config: FairPlayConfig())

        XCTAssertEqual(position(for: pitcher, inning: 0, in: fill.lineup), .pitcher,
                       "Pre-assigned pitcher should remain pitcher after AutoFill")
    }

    // MARK: - fillInnings (multi-inning)

    func testFillInningsRespectsConfigAcrossAllInnings() {
        var config = FairPlayConfig()
        config.noPitcher = true

        let players = (1...9).map { makePlayer("P\($0)") }
        let fill = AutoFillEngine.fillInnings(through: 3, in: makeLineup(innings: 4), players: players, config: config)

        for inningIdx in 0..<4 {
            for player in players {
                let pos = position(for: player, inning: inningIdx, in: fill.lineup)
                XCTAssertNotEqual(pos, .pitcher,
                                  "Pitcher should never be assigned in inning \(inningIdx + 1) when noPitcher is true")
            }
        }
    }

    // MARK: - fillGame

    func testFillGameRespectsConfig() {
        var config = FairPlayConfig()
        config.noCatcher = true

        let players = (1...9).map { makePlayer("P\($0)") }
        let fill = AutoFillEngine.fillGame(in: makeLineup(innings: 6), players: players, config: config)

        for inningIdx in 0..<6 {
            for player in players {
                let pos = position(for: player, inning: inningIdx, in: fill.lineup)
                XCTAssertNotEqual(pos, .catcher,
                                  "Catcher should never be assigned in any inning when noCatcher is true")
            }
        }
    }

    // MARK: - Default config fills all nine positions

    func testDefaultConfigFillsAllNinePositions() {
        let players = (1...9).map { makePlayer("P\($0)") }
        let fill = AutoFillEngine.fillInning(0, in: makeLineup(), players: players, config: FairPlayConfig())

        XCTAssertEqual(fill.filledCount, 9, "9 players with default config should fill exactly 9 slots")
        for player in players {
            XCTAssertNotNil(position(for: player, inning: 0, in: fill.lineup),
                            "\(player.firstName) should have a position assigned")
        }
    }

    // MARK: - AutoFillResult: unfilledSlots

    func testAutoFillResultHasNoUnfilledSlotsWithFullRoster() {
        let players = (1...9).map { makePlayer("P\($0)") }
        let fill = AutoFillEngine.fillInning(0, in: makeLineup(), players: players, config: FairPlayConfig())

        XCTAssertFalse(fill.hasUnfilledSlots,
                       "Full 9-player roster with default config should have no unfilled slots")
        XCTAssertTrue(fill.unfilledSlots.isEmpty)
    }

    func testAutoFillResultReportsRosterTooSmallWhenPlayersInsufficient() {
        // 5 players cannot cover all 9 field positions — 4 slots remain unfilled
        let players = (1...5).map { makePlayer("P\($0)") }
        let fill = AutoFillEngine.fillInning(0, in: makeLineup(), players: players, config: FairPlayConfig())

        XCTAssertTrue(fill.hasUnfilledSlots, "5 players cannot fill 9 field slots")
        XCTAssertEqual(fill.unfilledSlots.count, 4, "9 slots - 5 players = 4 unfilled")
        let rosterSmallSlots = fill.unfilledSlots.filter { $0.reason == .rosterTooSmall }
        XCTAssertFalse(rosterSmallSlots.isEmpty,
                       "Unfilled slots should be attributed to .rosterTooSmall")
    }

    func testAutoFillResultReportsNeverPreferencesWhenAllPitcherNever() {
        // All 9 players have .pitcher set to .never — pitcher slot should be unfilled
        // with reason .neverPreferences, not .rosterTooSmall.
        var config = FairPlayConfig()
        config.noPitcher = false

        let players = (1...9).map { makePlayer("P\($0)") }
        let preferences: [UUID: [FieldPosition: PositionPreferenceTier]] = Dictionary(
            uniqueKeysWithValues: players.map { ($0.id, [FieldPosition.pitcher: PositionPreferenceTier.never]) }
        )

        let fill = AutoFillEngine.fillInning(
            0, in: makeLineup(), players: players,
            preferences: preferences, config: config
        )

        XCTAssertTrue(fill.hasUnfilledSlots,
                      "Pitcher should be unfilled when all players have it set to Never")
        let pitcherSlot = fill.unfilledSlots.first { $0.position == .pitcher }
        XCTAssertNotNil(pitcherSlot)
        XCTAssertEqual(pitcherSlot?.reason, .neverPreferences)
    }

    func testAutoFillResultUnfilledSlotInningIndexIsCorrect() {
        // Filling inning 2 specifically — every unfilled slot must reference inningIndex 2
        let players = (1...4).map { makePlayer("P\($0)") }
        let fill = AutoFillEngine.fillInning(2, in: makeLineup(innings: 3), players: players, config: FairPlayConfig())

        for slot in fill.unfilledSlots {
            XCTAssertEqual(slot.inningIndex, 2, "Unfilled slot should reference inning index 2")
        }
    }

    func testAutoFillResultFillInningsAggregatesUnfilledAcrossAllInnings() {
        // 4 players, 3 innings, 9 slots per inning -> 5 unfilled per inning -> 15 total
        let players = (1...4).map { makePlayer("P\($0)") }
        let fill = AutoFillEngine.fillInnings(
            through: 2, in: makeLineup(innings: 3), players: players, config: FairPlayConfig()
        )

        XCTAssertEqual(fill.unfilledSlots.count, 15, "5 unfilled slots x 3 innings = 15 total")
    }

    // MARK: - AutoFillResult: incompleteMessage

    func testIncompleteMessageIsNilWhenAllSlotsFilled() {
        let players = (1...9).map { makePlayer("P\($0)") }
        let fill = AutoFillEngine.fillInning(0, in: makeLineup(), players: players, config: FairPlayConfig())

        XCTAssertNil(fill.incompleteMessage(multiInning: false),
                     "incompleteMessage should be nil when all slots are filled")
    }

    func testIncompleteMessageIsNonNilWhenSlotsAreUnfilled() {
        let players = (1...4).map { makePlayer("P\($0)") }
        let fill = AutoFillEngine.fillInning(0, in: makeLineup(), players: players, config: FairPlayConfig())

        XCTAssertNotNil(fill.incompleteMessage(multiInning: false),
                        "incompleteMessage should return a string when slots are unfilled")
    }

    func testIncompleteMessageMultiInningIncludesInningNumbers() {
        // In multi-inning mode the message should mention inning numbers
        let players = (1...4).map { makePlayer("P\($0)") }
        let fill = AutoFillEngine.fillInnings(
            through: 1, in: makeLineup(innings: 2), players: players, config: FairPlayConfig()
        )

        let message = fill.incompleteMessage(multiInning: true)
        XCTAssertNotNil(message)
        // The multi-inning format embeds inning numbers — look for "Inning" in the output
        XCTAssertTrue(message?.contains("Inning") == true,
                      "Multi-inning message should reference specific inning numbers")
    }
}
