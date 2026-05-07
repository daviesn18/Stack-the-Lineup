import XCTest
@testable import Lineup_Builder

// MARK: - Fair Play Validation Tests
//
// Tests for all Lineup validation methods that power fair play warnings.
// Each test targets a specific rule and verifies both the "rule fires" and
// "rule is off / threshold not met" paths.

final class FairPlayValidationTests: XCTestCase {

    // MARK: - Helpers

    private func makePlayer(_ name: String) -> Player {
        Player(firstName: name, lastName: "Test", number: "0")
    }

    private func makeLineup(innings: Int = 6) -> Lineup {
        Lineup(innings: Array(repeating: InningAssignment(), count: innings))
    }

    private func assign(_ position: FieldPosition, to player: Player, inning: Int, in lineup: inout Lineup) {
        lineup.innings[inning].assign(player: player, position: position)
    }

    // MARK: - activeFieldPositions

    func testDefaultConfigProducesStandard9Positions() {
        let lineup = makeLineup()
        let config = FairPlayConfig()
        let positions = lineup.activeFieldPositions(config: config)
        XCTAssertTrue(positions.contains(.pitcher))
        XCTAssertTrue(positions.contains(.catcher))
        XCTAssertTrue(positions.contains(.centerField))
        XCTAssertFalse(positions.contains(.leftCenterField))
        XCTAssertFalse(positions.contains(.rightCenterField))
        XCTAssertEqual(positions.count, 9)
    }

    func testNoPitcherRemovesPitcherFromPool() {
        let lineup = makeLineup()
        var config = FairPlayConfig()
        config.noPitcher = true
        let positions = lineup.activeFieldPositions(config: config)
        XCTAssertFalse(positions.contains(.pitcher))
        XCTAssertEqual(positions.count, 8)
    }

    func testNoCatcherRemovesCatcherFromPool() {
        let lineup = makeLineup()
        var config = FairPlayConfig()
        config.noCatcher = true
        let positions = lineup.activeFieldPositions(config: config)
        XCTAssertFalse(positions.contains(.catcher))
        XCTAssertEqual(positions.count, 8)
    }

    func testNoPitcherAndNoCatcherRemovesBoth() {
        let lineup = makeLineup()
        var config = FairPlayConfig()
        config.noPitcher = true
        config.noCatcher = true
        let positions = lineup.activeFieldPositions(config: config)
        XCTAssertFalse(positions.contains(.pitcher))
        XCTAssertFalse(positions.contains(.catcher))
        XCTAssertEqual(positions.count, 7)
    }

    func testFourOutfieldersSwapsCFforLCFandRCF() {
        let lineup = makeLineup()
        var config = FairPlayConfig()
        config.outfielderCount = 4
        let positions = lineup.activeFieldPositions(config: config)
        XCTAssertTrue(positions.contains(.leftCenterField))
        XCTAssertTrue(positions.contains(.rightCenterField))
        XCTAssertFalse(positions.contains(.centerField))
        XCTAssertEqual(positions.count, 10) // 6 IF + LF + LCF + RCF + RF
    }

    func testThreeOutfieldersExcludesLCFandRCF() {
        let lineup = makeLineup()
        let config = FairPlayConfig()
        let positions = lineup.activeFieldPositions(config: config)
        XCTAssertFalse(positions.contains(.leftCenterField))
        XCTAssertFalse(positions.contains(.rightCenterField))
        XCTAssertTrue(positions.contains(.centerField))
    }

    // MARK: - openPositions (config-aware)

    func testOpenPositionsExcludesRestrictedPositions() {
        var lineup = makeLineup(innings: 1)
        let player = makePlayer("Alex")
        assign(.firstBase, to: player, inning: 0, in: &lineup)

        var config = FairPlayConfig()
        config.noPitcher = true
        config.noCatcher = true

        let open = lineup.openPositions(inning: 0, players: [player], config: config)
        XCTAssertFalse(open.contains(.pitcher))
        XCTAssertFalse(open.contains(.catcher))
        XCTAssertFalse(open.contains(.firstBase))
    }

    func testOpenPositionsWithFourOFExcludesCF() {
        let lineup = makeLineup(innings: 1)
        let player = makePlayer("Sam")
        var config = FairPlayConfig()
        config.outfielderCount = 4

        let open = lineup.openPositions(inning: 0, players: [player], config: config)
        XCTAssertFalse(open.contains(.centerField))
        XCTAssertTrue(open.contains(.leftCenterField))
        XCTAssertTrue(open.contains(.rightCenterField))
    }

    // MARK: - playersWithoutInfield / playersWithoutOutfield

    func testPlayerWithNoInfieldIsDetected() {
        var lineup = makeLineup(innings: 3)
        let player = makePlayer("Jordan")
        assign(.leftField, to: player, inning: 0, in: &lineup)
        assign(.centerField, to: player, inning: 1, in: &lineup)
        assign(.bench, to: player, inning: 2, in: &lineup)

        let result = lineup.playersWithoutInfield(players: [player])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].id, player.id)
    }

    func testPlayerWithInfieldNotFlagged() {
        var lineup = makeLineup(innings: 3)
        let player = makePlayer("Casey")
        assign(.shortstop, to: player, inning: 0, in: &lineup)
        assign(.leftField, to: player, inning: 1, in: &lineup)
        assign(.bench, to: player, inning: 2, in: &lineup)

        let result = lineup.playersWithoutInfield(players: [player])
        XCTAssertTrue(result.isEmpty)
    }

    func testPlayerWithNoOutfieldIsDetected() {
        var lineup = makeLineup(innings: 3)
        let player = makePlayer("Riley")
        assign(.pitcher, to: player, inning: 0, in: &lineup)
        assign(.firstBase, to: player, inning: 1, in: &lineup)
        assign(.bench, to: player, inning: 2, in: &lineup)

        let result = lineup.playersWithoutOutfield(players: [player])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].id, player.id)
    }

    func testLCFandRCFCountAsOutfieldForMinimum() {
        var lineup = makeLineup(innings: 2)
        let player = makePlayer("Morgan")
        assign(.leftCenterField, to: player, inning: 0, in: &lineup)
        assign(.firstBase, to: player, inning: 1, in: &lineup)

        let result = lineup.playersWithoutOutfield(players: [player])
        XCTAssertTrue(result.isEmpty, "LCF should count as an outfield inning")
    }

    // MARK: - playersUnderFieldingMinimum

    func testPlayerUnderConfiguredMinimumIsFlagged() {
        var lineup = makeLineup(innings: 6)
        let player = makePlayer("Drew")
        // 2 fielding innings, 4 bench — under a minimum of 3
        assign(.leftField, to: player, inning: 0, in: &lineup)
        assign(.firstBase, to: player, inning: 1, in: &lineup)
        assign(.bench, to: player, inning: 2, in: &lineup)
        assign(.bench, to: player, inning: 3, in: &lineup)
        assign(.bench, to: player, inning: 4, in: &lineup)
        assign(.bench, to: player, inning: 5, in: &lineup)

        let result = lineup.playersUnderFieldingMinimum(players: [player], minimumInnings: 3)
        XCTAssertEqual(result.count, 1)
    }

    func testPlayerMeetingConfiguredMinimumNotFlagged() {
        var lineup = makeLineup(innings: 6)
        let player = makePlayer("Taylor")
        assign(.leftField, to: player, inning: 0, in: &lineup)
        assign(.firstBase, to: player, inning: 1, in: &lineup)
        assign(.shortstop, to: player, inning: 2, in: &lineup)
        assign(.bench, to: player, inning: 3, in: &lineup)
        assign(.bench, to: player, inning: 4, in: &lineup)
        assign(.bench, to: player, inning: 5, in: &lineup)

        let result = lineup.playersUnderFieldingMinimum(players: [player], minimumInnings: 3)
        XCTAssertTrue(result.isEmpty)
    }

    func testMinimumZeroNeverFlags() {
        var lineup = makeLineup(innings: 6)
        let player = makePlayer("Avery")
        // All bench — would be flagged at any positive minimum
        for i in 0..<6 { assign(.bench, to: player, inning: i, in: &lineup) }

        let result = lineup.playersUnderFieldingMinimum(players: [player], minimumInnings: 0)
        XCTAssertTrue(result.isEmpty, "minimumInnings of 0 should never flag anyone")
    }

    func testPlayerWithABSInningExemptFromMinimum() {
        var lineup = makeLineup(innings: 6)
        let player = makePlayer("Quinn")
        assign(.absent, to: player, inning: 0, in: &lineup)
        assign(.bench, to: player, inning: 1, in: &lineup)
        assign(.bench, to: player, inning: 2, in: &lineup)
        assign(.bench, to: player, inning: 3, in: &lineup)
        assign(.bench, to: player, inning: 4, in: &lineup)
        assign(.bench, to: player, inning: 5, in: &lineup)

        let result = lineup.playersUnderFieldingMinimum(players: [player], minimumInnings: 4)
        XCTAssertTrue(result.isEmpty, "Player with ABS inning should be exempt from fielding minimum")
    }

    // MARK: - playersWithBackToBackBench

    func testBackToBackBenchDetected() {
        var lineup = makeLineup(innings: 4)
        let player = makePlayer("Blake")
        assign(.leftField, to: player, inning: 0, in: &lineup)
        assign(.bench, to: player, inning: 1, in: &lineup)
        assign(.bench, to: player, inning: 2, in: &lineup)
        assign(.firstBase, to: player, inning: 3, in: &lineup)

        let result = lineup.playersWithBackToBackBench(from: [player])
        XCTAssertEqual(result.count, 1)
    }

    func testNonConsecutiveBenchNotFlagged() {
        var lineup = makeLineup(innings: 4)
        let player = makePlayer("Reese")
        assign(.bench, to: player, inning: 0, in: &lineup)
        assign(.leftField, to: player, inning: 1, in: &lineup)
        assign(.bench, to: player, inning: 2, in: &lineup)
        assign(.firstBase, to: player, inning: 3, in: &lineup)

        let result = lineup.playersWithBackToBackBench(from: [player])
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - playersViolatingCatcherToPitcher

    func testCatcherToPitcherThresholdZeroNeverFlags() {
        var lineup = makeLineup(innings: 4)
        let player = makePlayer("River")
        assign(.catcher, to: player, inning: 0, in: &lineup)
        assign(.catcher, to: player, inning: 1, in: &lineup)
        assign(.catcher, to: player, inning: 2, in: &lineup)
        assign(.pitcher, to: player, inning: 3, in: &lineup)

        let result = lineup.playersViolatingCatcherToPitcher(players: [player], threshold: 0)
        XCTAssertTrue(result.isEmpty, "threshold 0 means rule is off")
    }

    func testCatcherToPitcherViolationDetected() {
        var lineup = makeLineup(innings: 5)
        let player = makePlayer("Sage")
        assign(.catcher, to: player, inning: 0, in: &lineup)
        assign(.catcher, to: player, inning: 1, in: &lineup)
        assign(.catcher, to: player, inning: 2, in: &lineup)
        assign(.catcher, to: player, inning: 3, in: &lineup)
        assign(.pitcher, to: player, inning: 4, in: &lineup)

        // threshold 4: caught 4 innings then pitched — violation
        let result = lineup.playersViolatingCatcherToPitcher(players: [player], threshold: 4)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].id, player.id)
    }

    func testCatcherToPitcherBelowThresholdNotFlagged() {
        var lineup = makeLineup(innings: 4)
        let player = makePlayer("Rowan")
        assign(.catcher, to: player, inning: 0, in: &lineup)
        assign(.catcher, to: player, inning: 1, in: &lineup)
        assign(.catcher, to: player, inning: 2, in: &lineup)
        assign(.pitcher, to: player, inning: 3, in: &lineup)

        // threshold 4: only caught 3 innings — no violation
        let result = lineup.playersViolatingCatcherToPitcher(players: [player], threshold: 4)
        XCTAssertTrue(result.isEmpty)
    }

    func testCatcherToPitcherWithNoPitcherInningNotFlagged() {
        var lineup = makeLineup(innings: 4)
        let player = makePlayer("Finley")
        assign(.catcher, to: player, inning: 0, in: &lineup)
        assign(.catcher, to: player, inning: 1, in: &lineup)
        assign(.catcher, to: player, inning: 2, in: &lineup)
        assign(.catcher, to: player, inning: 3, in: &lineup)

        // caught 4 innings but never pitched — no violation
        let result = lineup.playersViolatingCatcherToPitcher(players: [player], threshold: 4)
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - playersViolatingPitcherToCatcher

    func testPitcherToCatcherThresholdZeroNeverFlags() {
        var lineup = makeLineup(innings: 4)
        let player = makePlayer("Emery")
        assign(.pitcher, to: player, inning: 0, in: &lineup)
        assign(.pitcher, to: player, inning: 1, in: &lineup)
        assign(.pitcher, to: player, inning: 2, in: &lineup)
        assign(.catcher, to: player, inning: 3, in: &lineup)

        let result = lineup.playersViolatingPitcherToCatcher(players: [player], threshold: 0)
        XCTAssertTrue(result.isEmpty, "threshold 0 means rule is off")
    }

    func testPitcherToCatcherViolationDetected() {
        var lineup = makeLineup(innings: 5)
        let player = makePlayer("Harlow")
        assign(.pitcher, to: player, inning: 0, in: &lineup)
        assign(.pitcher, to: player, inning: 1, in: &lineup)
        assign(.pitcher, to: player, inning: 2, in: &lineup)
        assign(.catcher, to: player, inning: 3, in: &lineup)
        assign(.leftField, to: player, inning: 4, in: &lineup)

        // threshold 3: pitched 3 innings then caught — violation
        let result = lineup.playersViolatingPitcherToCatcher(players: [player], threshold: 3)
        XCTAssertEqual(result.count, 1)
    }

    func testPitcherToCatcherBelowThresholdNotFlagged() {
        var lineup = makeLineup(innings: 4)
        let player = makePlayer("Indigo")
        assign(.pitcher, to: player, inning: 0, in: &lineup)
        assign(.pitcher, to: player, inning: 1, in: &lineup)
        assign(.catcher, to: player, inning: 2, in: &lineup)
        assign(.leftField, to: player, inning: 3, in: &lineup)

        // threshold 3: only pitched 2 innings — no violation
        let result = lineup.playersViolatingPitcherToCatcher(players: [player], threshold: 3)
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Multi-player scenarios

    func testOnlyViolatingPlayerFlagged() {
        var lineup = makeLineup(innings: 5)
        let violator = makePlayer("Wolf")
        let clean = makePlayer("Hawk")

        // violator: caught 4, pitched 1 — violates C-to-P at threshold 4
        assign(.catcher, to: violator, inning: 0, in: &lineup)
        assign(.catcher, to: violator, inning: 1, in: &lineup)
        assign(.catcher, to: violator, inning: 2, in: &lineup)
        assign(.catcher, to: violator, inning: 3, in: &lineup)
        assign(.pitcher, to: violator, inning: 4, in: &lineup)

        // clean: only played outfield
        assign(.leftField, to: clean, inning: 0, in: &lineup)
        assign(.rightField, to: clean, inning: 1, in: &lineup)
        assign(.centerField, to: clean, inning: 2, in: &lineup)
        assign(.leftField, to: clean, inning: 3, in: &lineup)
        assign(.rightField, to: clean, inning: 4, in: &lineup)

        let result = lineup.playersViolatingCatcherToPitcher(players: [violator, clean], threshold: 4)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].id, violator.id)
    }

    func testAbsentPlayerExcludedFromValidation() {
        var lineup = makeLineup(innings: 4)
        var player = makePlayer("Ghost")
        // Mark absent at the lineup level
        lineup.absentPlayerIDs.insert(player.id)

        assign(.catcher, to: player, inning: 0, in: &lineup)
        assign(.catcher, to: player, inning: 1, in: &lineup)
        assign(.catcher, to: player, inning: 2, in: &lineup)
        assign(.pitcher, to: player, inning: 3, in: &lineup)

        let result = lineup.playersViolatingCatcherToPitcher(players: [player], threshold: 3)
        XCTAssertTrue(result.isEmpty, "Absent players should be excluded from all validation")
    }
}
