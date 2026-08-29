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

    // MARK: - Bench Pairing (patternRules.benchInConsecutivePairs)
    //
    // The rule a coach asked for that nothing in the app could express: once a
    // player sits, they sit the next inning too. It's the deliberate inverse of
    // the engine's usual back-to-back-bench avoidance, activated per fill via a
    // pattern rule (in production, set by the natural-language parser).

    private func benched(_ player: Player, inning: Int, in lineup: Lineup) -> Bool {
        position(for: player, inning: inning, in: lineup) == .bench
    }

    private var pairingConstraints: AutoFillConstraintSet {
        AutoFillConstraintSet(
            playerConstraints: [],
            patternRules: AutoFillPatternRules(benchInConsecutivePairs: true)
        )
    }

    /// With 10 players and 9 field slots, exactly one player sits each inning.
    /// Under bench pairing, whoever sat inning 1 must also sit inning 2.
    func testBenchPairingHoldsSitterForASecondInning() {
        let players = (1...10).map { makePlayer("P\($0)") }
        let fill = AutoFillEngine.fillInnings(
            through: 1, in: makeLineup(innings: 2), players: players,
            constraints: pairingConstraints
        )

        let sittersInning0 = players.filter { benched($0, inning: 0, in: fill.lineup) }
        XCTAssertEqual(sittersInning0.count, 1, "Exactly one of 10 players should sit with 9 field slots")
        for sitter in sittersInning0 {
            XCTAssertTrue(benched(sitter, inning: 1, in: fill.lineup),
                          "\(sitter.firstName) sat inning 1 and must sit inning 2 under bench pairing")
        }
    }

    /// The contrast case: default (no pattern rule) actively AVOIDS back-to-back
    /// bench, so the inning-1 sitter is pulled straight back onto the field in
    /// inning 2. This is exactly the behavior bench pairing inverts.
    func testDefaultAvoidsBackToBackBench() {
        let players = (1...10).map { makePlayer("P\($0)") }
        let fill = AutoFillEngine.fillInnings(
            through: 1, in: makeLineup(innings: 2), players: players
        )

        let sittersInning0 = players.filter { benched($0, inning: 0, in: fill.lineup) }
        XCTAssertEqual(sittersInning0.count, 1)
        for sitter in sittersInning0 {
            XCTAssertFalse(benched(sitter, inning: 1, in: fill.lineup),
                           "Default fill should not bench \(sitter.firstName) two innings in a row")
        }
    }

    /// The obligation is exactly one extra inning: a player who has already sat
    /// two in a row is released rather than held for a third. Over a full game
    /// every bench run should therefore be a clean pair (except one that starts
    /// on the final inning, which can't be completed).
    func testBenchPairingReleasesAfterTwoInnings() {
        let players = (1...10).map { makePlayer("P\($0)") }
        let innings = 6
        let fill = AutoFillEngine.fillGame(
            in: makeLineup(innings: innings), players: players,
            constraints: pairingConstraints
        )

        for player in players {
            var i = 0
            while i < innings {
                guard benched(player, inning: i, in: fill.lineup) else { i += 1; continue }
                // Measure the length of this consecutive bench run.
                var runEnd = i
                while runEnd + 1 < innings && benched(player, inning: runEnd + 1, in: fill.lineup) {
                    runEnd += 1
                }
                let runLength = runEnd - i + 1
                // A run that starts before the last inning must be a pair (or a
                // completed pair; never an isolated single). A run beginning on
                // the final inning can't be paired and is allowed to be length 1.
                if i < innings - 1 {
                    XCTAssertEqual(runLength, 2,
                        "\(player.firstName)'s bench run starting at inning \(i + 1) should be a clean pair, was \(runLength)")
                }
                i = runEnd + 1
            }
        }
    }

    /// Soft, not hard: pairing never manufactures an empty field slot. Two
    /// players are forced onto the bench in inning 1 via explicit constraints,
    /// so both are mid-pair in inning 2 — but with only one surplus player, the
    /// engine may complete only one pair and must still field all nine spots.
    func testBenchPairingIsSoftAndKeepsAFullField() {
        let players = (1...10).map { makePlayer("P\($0)") }
        let benchTwo = [players[0], players[1]].map {
            AutoFillPlayerConstraint(
                playerID: $0.id, target: .bench, inningRange: 0...0, intent: .assign
            )
        }
        let constraints = AutoFillConstraintSet(
            playerConstraints: benchTwo,
            patternRules: AutoFillPatternRules(benchInConsecutivePairs: true)
        )

        let fill = AutoFillEngine.fillInnings(
            through: 1, in: makeLineup(innings: 2), players: players,
            constraints: constraints
        )

        // Inning 2 (index 1): both players[0] and players[1] are mid-pair, but
        // holding both would leave a field slot open. The guard caps the held
        // count so all nine field positions stay filled.
        let inning1Unfilled = fill.unfilledSlots.filter { $0.inningIndex == 1 }
        XCTAssertTrue(inning1Unfilled.isEmpty,
                      "Bench pairing must not leave a field slot unfilled: \(inning1Unfilled.map { $0.position.rawValue })")
        let sittersInning1 = players.filter { benched($0, inning: 1, in: fill.lineup) }
        XCTAssertEqual(sittersInning1.count, 1,
                       "With one surplus player only one pair can be completed in inning 2")
    }

    // MARK: - No-Back-to-Back-Bench Toggle (config.noConsecutiveBench)
    //
    // Previously this Fair Play toggle only drove the warning badge — the
    // engine avoided back-to-back bench regardless of it. It now actually
    // gates the field-queue front-loading that does the avoiding, so turning
    // the rule off lets a player sit two innings running.

    /// Counts how many times any player is benched in two consecutive innings
    /// across the whole lineup.
    private func backToBackBenchCount(_ lineup: Lineup, players: [Player]) -> Int {
        var count = 0
        for player in players {
            for inning in 1..<lineup.innings.count
            where benched(player, inning: inning - 1, in: lineup)
                && benched(player, inning: inning, in: lineup) {
                count += 1
            }
        }
        return count
    }

    /// One comparison proves both halves of the fix: with the rule ON the
    /// engine never benches a player two innings running (it's always
    /// avoidable at 12 players / 9 slots), and with the rule OFF back-to-back
    /// bench is permitted and does occur. Run many times because field/bench
    /// selection is shuffled — the ON invariant must hold on every trial, and
    /// the OFF case need only surface across the batch.
    func testNoConsecutiveBenchToggleGatesBackToBack() {
        let players = (1...12).map { makePlayer("P\($0)") }
        let innings = 6

        var onConfig = FairPlayConfig()
        onConfig.noConsecutiveBench = true
        var offConfig = FairPlayConfig()
        offConfig.noConsecutiveBench = false

        var onTotal = 0
        var offTotal = 0
        for _ in 0..<60 {
            let on = AutoFillEngine.fillGame(
                in: makeLineup(innings: innings), players: players, config: onConfig
            )
            onTotal += backToBackBenchCount(on.lineup, players: players)

            let off = AutoFillEngine.fillGame(
                in: makeLineup(innings: innings), players: players, config: offConfig
            )
            offTotal += backToBackBenchCount(off.lineup, players: players)
        }

        XCTAssertEqual(onTotal, 0,
            "With No Back-to-Back Bench on, the engine should never sit a player two innings running when it's avoidable")
        XCTAssertGreaterThan(offTotal, 0,
            "With the rule off, back-to-back bench should be permitted and occur at least sometimes")
    }

    // MARK: - Equal Bench Time Toggle (config.equalBenchTime)
    //
    // Another Fair Play toggle that used to be warning-only. It now gates an
    // outer sort on the field queue: whoever's left for the bench is always
    // drawn from the players who've sat the fewest, so nobody sits twice before
    // everyone has sat once.

    private func benchCount(_ player: Player, in lineup: Lineup) -> Int {
        (0..<lineup.innings.count).filter { benched(player, inning: $0, in: lineup) }.count
    }

    /// Widest gap between any two players' total bench innings. Equal bench time
    /// keeps this to at most 1.
    private func benchSpread(_ lineup: Lineup, players: [Player]) -> Int {
        let counts = players.map { benchCount($0, in: lineup) }
        return (counts.max() ?? 0) - (counts.min() ?? 0)
    }

    /// With the rule on, bench counts stay within 1 of each other on every
    /// trial (nobody sits twice before all have sat once). With it off, an
    /// uneven spread of 2+ is permitted and shows up across the batch. Run
    /// repeatedly because selection is shuffled.
    func testEqualBenchTimeToggleGatesBenchBalance() {
        let players = (1...10).map { makePlayer("P\($0)") }
        let innings = 8

        var onConfig = FairPlayConfig()
        onConfig.equalBenchTime = true
        let offConfig = FairPlayConfig() // equalBenchTime defaults false

        var offSawImbalance = false
        for _ in 0..<80 {
            let on = AutoFillEngine.fillGame(
                in: makeLineup(innings: innings), players: players, config: onConfig
            )
            XCTAssertLessThanOrEqual(benchSpread(on.lineup, players: players), 1,
                "Equal bench time must not let anyone sit twice before everyone has sat once")

            let off = AutoFillEngine.fillGame(
                in: makeLineup(innings: innings), players: players, config: offConfig
            )
            if benchSpread(off.lineup, players: players) >= 2 { offSawImbalance = true }
        }

        XCTAssertTrue(offSawImbalance,
            "With equal bench time off, an uneven bench spread (2+) should be possible")
    }
}
