import XCTest
@testable import Lineup_Builder

// MARK: - Fair Play Validation Tests
//
// Covers the Lineup validation engine: activeFieldPositions, openPositions
// (config-aware), playersWithoutInfield/Outfield, playersUnderFieldingMinimum,
// playersWithBackToBackBench, and both battery restriction validators
// (catcher-to-pitcher, pitcher-to-catcher).

@MainActor
final class FairPlayValidationTests: XCTestCase {

    // MARK: - Helpers

    private func makePlayer(_ name: String) -> Player {
        Player(firstName: name, lastName: "Test", number: "0")
    }

    private func makeLineup(innings: Int = 7) -> Lineup {
        Lineup(innings: Array(repeating: InningAssignment(), count: innings))
    }

    // MARK: - activeFieldPositions

    func testActiveFieldPositionsDefaultConfigHasNinePositions() {
        let positions = makeLineup().activeFieldPositions(config: FairPlayConfig())

        XCTAssertEqual(positions.count, 9)
        XCTAssertTrue(positions.contains(.pitcher))
        XCTAssertTrue(positions.contains(.catcher))
        XCTAssertTrue(positions.contains(.centerField))
        XCTAssertFalse(positions.contains(.leftCenterField))
        XCTAssertFalse(positions.contains(.rightCenterField))
        XCTAssertFalse(positions.contains(.bench))
        XCTAssertFalse(positions.contains(.absent))
    }

    func testActiveFieldPositionsNoPitcherRemovesPitcherOnly() {
        var config = FairPlayConfig()
        config.noPitcher = true
        let positions = makeLineup().activeFieldPositions(config: config)

        XCTAssertFalse(positions.contains(.pitcher))
        XCTAssertTrue(positions.contains(.catcher))
        XCTAssertEqual(positions.count, 8)
    }

    func testActiveFieldPositionsNoCatcherRemovesCatcherOnly() {
        var config = FairPlayConfig()
        config.noCatcher = true
        let positions = makeLineup().activeFieldPositions(config: config)

        XCTAssertFalse(positions.contains(.catcher))
        XCTAssertTrue(positions.contains(.pitcher))
        XCTAssertEqual(positions.count, 8)
    }

    func testActiveFieldPositionsFourOutfieldersSwapsCFForLCFAndRCF() {
        var config = FairPlayConfig()
        config.outfielderCount = 4
        let positions = makeLineup().activeFieldPositions(config: config)

        XCTAssertTrue(positions.contains(.leftCenterField))
        XCTAssertTrue(positions.contains(.rightCenterField))
        XCTAssertFalse(positions.contains(.centerField))
        // 6 infield + 4 outfield = 10
        XCTAssertEqual(positions.count, 10)
    }

    func testActiveFieldPositionsNoPitcherNoCatcherFourOFCombined() {
        var config = FairPlayConfig()
        config.noPitcher = true
        config.noCatcher = true
        config.outfielderCount = 4
        let positions = makeLineup().activeFieldPositions(config: config)

        XCTAssertFalse(positions.contains(.pitcher))
        XCTAssertFalse(positions.contains(.catcher))
        XCTAssertFalse(positions.contains(.centerField))
        XCTAssertTrue(positions.contains(.leftCenterField))
        XCTAssertTrue(positions.contains(.rightCenterField))
        // 4 infield + 4 outfield = 8
        XCTAssertEqual(positions.count, 8)
    }

    // MARK: - openPositions (config-aware)

    func testOpenPositionsNoPitcherDoesNotReportPitcherAsOpen() {
        var config = FairPlayConfig()
        config.noPitcher = true

        let players = (1...9).map { makePlayer("P\($0)") }
        let open = makeLineup(innings: 1).openPositions(inning: 0, players: players, config: config)

        XCTAssertFalse(open.contains(.pitcher),
                       "Pitcher should not appear as open when noPitcher is true")
    }

    func testOpenPositionsExcludesAlreadyFilledPositions() {
        let pitcher = makePlayer("Ace")
        var lineup = makeLineup(innings: 1)
        lineup.innings[0].assign(player: pitcher, position: .pitcher)

        let players = [pitcher] + (1...8).map { makePlayer("P\($0)") }
        let open = lineup.openPositions(inning: 0, players: players, config: FairPlayConfig())

        XCTAssertFalse(open.contains(.pitcher),
                       "Pitcher should not appear as open after being assigned")
    }

    func testOpenPositionsFourOFDoesNotReportCFAsOpen() {
        var config = FairPlayConfig()
        config.outfielderCount = 4

        let open = makeLineup(innings: 1).openPositions(
            inning: 0, players: (1...10).map { makePlayer("P\($0)") }, config: config
        )

        XCTAssertFalse(open.contains(.centerField), "CF should not be open in a 4-OF config")
        XCTAssertTrue(open.contains(.leftCenterField))
        XCTAssertTrue(open.contains(.rightCenterField))
    }

    func testOpenPositionsEmptyWhenNoActivePlayers() {
        let player = makePlayer("Alice")
        var lineup = makeLineup(innings: 1)
        lineup.absentPlayerIDs.insert(player.id)

        let open = lineup.openPositions(inning: 0, players: [player], config: FairPlayConfig())
        XCTAssertTrue(open.isEmpty, "No open positions when all players are absent")
    }

    // MARK: - playersWithoutInfield

    func testPlayersWithoutInfieldIdentifiesMissingPlayers() {
        let p1 = makePlayer("Alice")  // gets an infield inning
        let p2 = makePlayer("Bob")    // only outfield innings
        var lineup = makeLineup(innings: 3)
        lineup.innings[0].assign(player: p1, position: .shortstop)
        lineup.innings[1].assign(player: p1, position: .leftField)
        lineup.innings[0].assign(player: p2, position: .leftField)
        lineup.innings[1].assign(player: p2, position: .rightField)

        let missing = lineup.playersWithoutInfield(players: [p1, p2])

        XCTAssertFalse(missing.contains { $0.id == p1.id },
                       "p1 has an infield inning and should not appear")
        XCTAssertTrue(missing.contains { $0.id == p2.id },
                      "p2 has no infield inning and should appear")
    }

    func testPlayersWithoutInfieldExcludesAbsentPlayers() {
        let p1 = makePlayer("Alice")
        var lineup = makeLineup(innings: 1)
        lineup.absentPlayerIDs.insert(p1.id)

        let missing = lineup.playersWithoutInfield(players: [p1])
        XCTAssertTrue(missing.isEmpty, "Absent players should be excluded from playersWithoutInfield")
    }

    func testPlayersWithoutInfieldCountsAllInfieldPositions() {
        // Verify that pitcher and catcher count as infield
        let p1 = makePlayer("Pitcher")
        let p2 = makePlayer("Catcher")
        var lineup = makeLineup(innings: 1)
        lineup.innings[0].assign(player: p1, position: .pitcher)
        lineup.innings[0].assign(player: p2, position: .catcher)

        let missing = lineup.playersWithoutInfield(players: [p1, p2])
        XCTAssertTrue(missing.isEmpty, "Pitcher and catcher should count as infield innings")
    }

    // MARK: - playersWithoutOutfield

    func testPlayersWithoutOutfieldIdentifiesMissingPlayers() {
        let p1 = makePlayer("Alice")  // gets an outfield inning
        let p2 = makePlayer("Bob")    // only infield innings
        var lineup = makeLineup(innings: 2)
        lineup.innings[0].assign(player: p1, position: .leftField)
        lineup.innings[0].assign(player: p2, position: .shortstop)
        lineup.innings[1].assign(player: p2, position: .thirdBase)

        let missing = lineup.playersWithoutOutfield(players: [p1, p2])

        XCTAssertFalse(missing.contains { $0.id == p1.id })
        XCTAssertTrue(missing.contains { $0.id == p2.id })
    }

    func testPlayersWithoutOutfieldCountsAllOutfieldPositions() {
        let p1 = makePlayer("LCF")
        let p2 = makePlayer("RCF")
        var lineup = makeLineup(innings: 1)
        lineup.innings[0].assign(player: p1, position: .leftCenterField)
        lineup.innings[0].assign(player: p2, position: .rightCenterField)

        let missing = lineup.playersWithoutOutfield(players: [p1, p2])
        XCTAssertTrue(missing.isEmpty, "LCF and RCF innings should count as outfield")
    }

    // MARK: - playersUnderFieldingMinimum

    func testPlayersUnderFieldingMinimumDefaultFourInningThreshold() {
        let p1 = makePlayer("Alice")  // 4 fielding innings -- should NOT appear
        let p2 = makePlayer("Bob")    // 3 fielding + 1 bench -- should appear
        var lineup = makeLineup(innings: 4)

        for i in 0..<4 { lineup.innings[i].assign(player: p1, position: .leftField) }
        for i in 0..<3 { lineup.innings[i].assign(player: p2, position: .leftField) }
        lineup.innings[3].assign(player: p2, position: .bench)

        let under = lineup.playersUnderFieldingMinimum(players: [p1, p2], minimumInnings: 4)

        XCTAssertFalse(under.contains { $0.id == p1.id },
                       "p1 has exactly 4 fielding innings and should meet the minimum")
        XCTAssertTrue(under.contains { $0.id == p2.id },
                      "p2 has only 3 fielding innings and should be flagged")
    }

    func testPlayersUnderFieldingMinimumExemptsPlayersWithABSInning() {
        let p1 = makePlayer("Alice")
        var lineup = makeLineup(innings: 4)
        lineup.innings[0].assign(player: p1, position: .leftField)
        lineup.innings[1].assign(player: p1, position: .leftField)
        lineup.innings[2].assign(player: p1, position: .absent)
        lineup.innings[3].assign(player: p1, position: .bench)

        let under = lineup.playersUnderFieldingMinimum(players: [p1], minimumInnings: 4)
        XCTAssertTrue(under.isEmpty,
                      "A player with an ABS inning should be exempt from the fielding minimum")
    }

    func testPlayersUnderFieldingMinimumCustomThreshold() {
        let p1 = makePlayer("Alice")
        var lineup = makeLineup(innings: 3)
        for i in 0..<3 { lineup.innings[i].assign(player: p1, position: .leftField) }

        // 3 innings meets a threshold of 3 but not 4
        let under3 = lineup.playersUnderFieldingMinimum(players: [p1], minimumInnings: 3)
        let under4 = lineup.playersUnderFieldingMinimum(players: [p1], minimumInnings: 4)

        XCTAssertTrue(under3.isEmpty, "3 fielding innings meets a threshold of 3")
        XCTAssertFalse(under4.isEmpty, "3 fielding innings does not meet a threshold of 4")
    }

    func testPlayersUnderFieldingMinimumExcludesAbsentPlayers() {
        let p1 = makePlayer("Alice")
        var lineup = makeLineup(innings: 4)
        lineup.absentPlayerIDs.insert(p1.id)

        let under = lineup.playersUnderFieldingMinimum(players: [p1], minimumInnings: 4)
        XCTAssertTrue(under.isEmpty, "Absent players should not appear in fielding minimum results")
    }

    // MARK: - playersWithBackToBackBench

    func testPlayersWithBackToBackBenchDetectsAdjacentBenchInnings() {
        let p1 = makePlayer("Alice")  // back-to-back bench in innings 0-1
        let p2 = makePlayer("Bob")    // alternating bench -- no back-to-back
        var lineup = makeLineup(innings: 4)

        lineup.innings[0].assign(player: p1, position: .bench)
        lineup.innings[1].assign(player: p1, position: .bench)
        lineup.innings[2].assign(player: p1, position: .leftField)
        lineup.innings[3].assign(player: p1, position: .leftField)

        lineup.innings[0].assign(player: p2, position: .leftField)
        lineup.innings[1].assign(player: p2, position: .bench)
        lineup.innings[2].assign(player: p2, position: .leftField)
        lineup.innings[3].assign(player: p2, position: .bench)

        let flagged = lineup.playersWithBackToBackBench(from: [p1, p2])

        XCTAssertTrue(flagged.contains { $0.id == p1.id },
                      "p1 should be flagged for back-to-back bench")
        XCTAssertFalse(flagged.contains { $0.id == p2.id },
                       "p2 alternates bench and should not be flagged")
    }

    func testPlayersWithBackToBackBenchLastTwoInnings() {
        // Back-to-back at the end of the lineup (innings 5-6) should also be caught
        let p1 = makePlayer("Alice")
        var lineup = makeLineup(innings: 7)
        lineup.innings[5].assign(player: p1, position: .bench)
        lineup.innings[6].assign(player: p1, position: .bench)

        let flagged = lineup.playersWithBackToBackBench(from: [p1])
        XCTAssertTrue(flagged.contains { $0.id == p1.id })
    }

    func testPlayersWithBackToBackBenchExcludesAbsentPlayers() {
        let p1 = makePlayer("Alice")
        var lineup = makeLineup(innings: 2)
        lineup.innings[0].assign(player: p1, position: .bench)
        lineup.innings[1].assign(player: p1, position: .bench)
        lineup.absentPlayerIDs.insert(p1.id)

        let flagged = lineup.playersWithBackToBackBench(from: [p1])
        XCTAssertTrue(flagged.isEmpty, "Absent players should be excluded from back-to-back bench checks")
    }

    // MARK: - Battery restrictions: catcher to pitcher

    func testCatcherToPitcherViolationDetectedAtThreshold() {
        let player = makePlayer("Ace")
        var lineup = makeLineup(innings: 4)
        // 2 catching innings + 1 pitcher inning => violation at threshold 2
        lineup.innings[0].assign(player: player, position: .catcher)
        lineup.innings[1].assign(player: player, position: .catcher)
        lineup.innings[2].assign(player: player, position: .pitcher)
        lineup.innings[3].assign(player: player, position: .leftField)

        let violations = lineup.playersViolatingCatcherToPitcher(players: [player], threshold: 2)
        XCTAssertTrue(violations.contains { $0.id == player.id })
    }

    func testCatcherToPitcherNoViolationBelowThreshold() {
        let player = makePlayer("Ace")
        var lineup = makeLineup(innings: 4)
        // Only 1 catching inning; threshold is 2 -- no violation
        lineup.innings[0].assign(player: player, position: .catcher)
        lineup.innings[1].assign(player: player, position: .pitcher)
        lineup.innings[2].assign(player: player, position: .leftField)
        lineup.innings[3].assign(player: player, position: .leftField)

        let violations = lineup.playersViolatingCatcherToPitcher(players: [player], threshold: 2)
        XCTAssertTrue(violations.isEmpty)
    }

    func testCatcherToPitcherNoViolationIfNeverPitched() {
        let player = makePlayer("Ace")
        var lineup = makeLineup(innings: 3)
        // Caught 3 innings but never pitched -- no violation
        for i in 0..<3 { lineup.innings[i].assign(player: player, position: .catcher) }

        let violations = lineup.playersViolatingCatcherToPitcher(players: [player], threshold: 2)
        XCTAssertTrue(violations.isEmpty)
    }

    func testCatcherToPitcherThresholdZeroDisablesRule() {
        let player = makePlayer("Ace")
        var lineup = makeLineup(innings: 2)
        lineup.innings[0].assign(player: player, position: .catcher)
        lineup.innings[1].assign(player: player, position: .pitcher)

        let violations = lineup.playersViolatingCatcherToPitcher(players: [player], threshold: 0)
        XCTAssertTrue(violations.isEmpty, "Threshold 0 should disable the catcher-to-pitcher rule")
    }

    // MARK: - Battery restrictions: pitcher to catcher

    func testPitcherToCatcherViolationDetectedAtThreshold() {
        let player = makePlayer("Ace")
        var lineup = makeLineup(innings: 4)
        lineup.innings[0].assign(player: player, position: .pitcher)
        lineup.innings[1].assign(player: player, position: .pitcher)
        lineup.innings[2].assign(player: player, position: .catcher)
        lineup.innings[3].assign(player: player, position: .leftField)

        let violations = lineup.playersViolatingPitcherToCatcher(players: [player], threshold: 2)
        XCTAssertTrue(violations.contains { $0.id == player.id })
    }

    func testPitcherToCatcherNoViolationBelowThreshold() {
        let player = makePlayer("Ace")
        var lineup = makeLineup(innings: 3)
        lineup.innings[0].assign(player: player, position: .pitcher)
        lineup.innings[1].assign(player: player, position: .catcher)
        lineup.innings[2].assign(player: player, position: .leftField)

        // Only pitched 1 inning; threshold is 2 -- no violation
        let violations = lineup.playersViolatingPitcherToCatcher(players: [player], threshold: 2)
        XCTAssertTrue(violations.isEmpty)
    }

    func testPitcherToCatcherNoViolationIfNeverCaught() {
        let player = makePlayer("Ace")
        var lineup = makeLineup(innings: 3)
        for i in 0..<3 { lineup.innings[i].assign(player: player, position: .pitcher) }

        let violations = lineup.playersViolatingPitcherToCatcher(players: [player], threshold: 2)
        XCTAssertTrue(violations.isEmpty)
    }

    func testPitcherToCatcherThresholdZeroDisablesRule() {
        let player = makePlayer("Ace")
        var lineup = makeLineup(innings: 2)
        lineup.innings[0].assign(player: player, position: .pitcher)
        lineup.innings[1].assign(player: player, position: .catcher)

        let violations = lineup.playersViolatingPitcherToCatcher(players: [player], threshold: 0)
        XCTAssertTrue(violations.isEmpty, "Threshold 0 should disable the pitcher-to-catcher rule")
    }

    // MARK: - isPastAndFinalized

    func testIsPastAndFinalizedFalseForDraftLineup() {
        var lineup = makeLineup()
        lineup.status = .draft
        lineup.gameDate = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        XCTAssertFalse(lineup.isPastAndFinalized,
                       "Draft lineup should never be considered past-and-finalized")
    }

    func testIsPastAndFinalizedFalseForFutureGame() {
        var lineup = makeLineup()
        lineup.status = .finalized
        lineup.gameDate = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        XCTAssertFalse(lineup.isPastAndFinalized,
                       "Future finalized game should not be considered past-and-finalized")
    }

    func testIsPastAndFinalizedTrueForPastFinalizedGame() {
        var lineup = makeLineup()
        lineup.status = .finalized
        lineup.gameDate = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        XCTAssertTrue(lineup.isPastAndFinalized)
    }

    func testIsPastAndFinalizedFalseForTodaysGame() {
        var lineup = makeLineup()
        lineup.status = .finalized
        lineup.gameDate = Date()
        // Today is NOT past (startOfDay(today) is not < startOfDay(today))
        XCTAssertFalse(lineup.isPastAndFinalized,
                       "A game scheduled for today should not yet be considered past")
    }

    // MARK: - fairPlayFindings / implicatedPlayerIDs
    //
    // This is what every warning badge counts. The iPhone Positions tab used to
    // sum the per-rule counts instead, so one player breaking two rules showed
    // as 2 there and 1 on iPad for the same lineup.

    func testAPlayerBreakingTwoRulesIsCountedOnce() {
        // Alice fields all 4 innings and sees both infield and outfield — clean.
        // Bob sits one inning, so he's under the 4-inning fielding minimum AND
        // never plays the outfield. Two rules, one player to go fix.
        let alice = makePlayer("Alice")
        let bob = makePlayer("Bob")
        var lineup = makeLineup(innings: 4)
        for (i, pos) in [FieldPosition.leftField, .leftField, .shortstop, .shortstop].enumerated() {
            lineup.innings[i].assign(player: alice, position: pos)
        }
        for (i, pos) in [FieldPosition.shortstop, .shortstop, .shortstop, .bench].enumerated() {
            lineup.innings[i].assign(player: bob, position: pos)
        }

        let findings = lineup.fairPlayFindings(players: [alice, bob], config: FairPlayConfig())

        XCTAssertTrue(findings.withoutOutfield.contains { $0.id == bob.id })
        XCTAssertTrue(findings.underFieldingMinimum.contains { $0.id == bob.id })
        XCTAssertEqual(findings.implicatedPlayerIDs, [bob.id],
                       "Bob breaks two rules but is one thing to go fix")
    }

    func testRulesSwitchedOffContributeNoImplicatedPlayers() {
        // A lineup that trips several rules under the defaults, with every rule
        // switched off — nothing should be implicated.
        let bob = makePlayer("Bob")
        var lineup = makeLineup(innings: 2)
        lineup.innings[0].assign(player: bob, position: .shortstop)
        lineup.innings[1].assign(player: bob, position: .shortstop)

        var config = FairPlayConfig()
        config.minimumInfieldInnings = 0
        config.minimumOutfieldInnings = 0
        config.minimumFieldingInnings = 0
        config.noConsecutiveBench = false
        config.catcherToPitcherThreshold = 0
        config.pitcherToCatcherThreshold = 0

        let findings = lineup.fairPlayFindings(players: [bob], config: config)

        XCTAssertTrue(findings.isEmpty,
                      "A team with every rule off should have nothing to report")
    }

    // MARK: - backToBackBenchInnings

    func testBackToBackBenchInningsNamesThePairsOneBased() {
        // Bench in innings 1-2 and again in 5-6, as a coach counts them.
        let alice = makePlayer("Alice")
        var lineup = makeLineup(innings: 7)
        for i in [0, 1, 4, 5] {
            lineup.innings[i].assign(player: alice, position: .bench)
        }

        let pairs = lineup.backToBackBenchInnings(player: alice)

        XCTAssertEqual(pairs.map(\.first), [1, 5])
        XCTAssertEqual(pairs.map(\.second), [2, 6])
    }

    func testBackToBackBenchInningsIsEmptyForAlternatingBench() {
        let alice = makePlayer("Alice")
        var lineup = makeLineup(innings: 4)
        lineup.innings[0].assign(player: alice, position: .bench)
        lineup.innings[1].assign(player: alice, position: .leftField)
        lineup.innings[2].assign(player: alice, position: .bench)

        XCTAssertTrue(lineup.backToBackBenchInnings(player: alice).isEmpty)
        XCTAssertFalse(lineup.hasBackToBackBench(player: alice))
    }

    func testBackToBackBenchSurvivesALineupWithNoInnings() {
        // A truncated or hand-edited blob can decode to an empty innings array.
        // The old `0..<innings.count - 1` trapped on it.
        let alice = makePlayer("Alice")
        let lineup = Lineup(innings: [])

        XCTAssertTrue(lineup.backToBackBenchInnings(player: alice).isEmpty)
        XCTAssertFalse(lineup.hasBackToBackBench(player: alice))
    }
}
