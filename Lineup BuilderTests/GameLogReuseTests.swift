import XCTest
@testable import Lineup_Builder

// MARK: - Game Log Reuse Tests
//
// Covers applyGameLog / lineupFromGameLog — the transform behind the History
// tab's "Apply to Current Game" action. The interesting cases are all about
// the gap between when a game was archived and when it's reused: the roster
// may have changed, the team's game length may have changed, and ABS markers
// from that game shouldn't follow the coach into today's game.

@MainActor
final class GameLogReuseTests: XCTestCase {

    private var store: LineupStore!
    private var players: [Player]!

    override func setUp() {
        super.setUp()
        store = LineupStore()
        var team = Team()
        team.name = "Reds"
        players = (1...4).map { Player(firstName: "P\($0)", lastName: "Test", number: "\($0)") }
        team.players = players
        store.teams = [team]
        store.activeTeamID = team.id
    }

    // MARK: - Helpers

    /// Builds a log whose inning 0 assigns each player the given positions.
    private func makeLog(
        battingOrder: [UUID],
        inning0: [UUID: FieldPosition],
        inningCount: Int = 7
    ) -> GameLog {
        var innings = Array(repeating: InningAssignment(), count: inningCount)
        innings[0].assignments = inning0
        return GameLog(
            gameDate: Date(),
            opponent: "Jays",
            inningsPlayed: inningCount,
            battingOrder: battingOrder,
            innings: innings,
            playerSnapshot: players.map { PlayerSnapshot(from: $0) }
        )
    }

    // MARK: - Batting order

    func testAppliesBattingOrderAndPositions() {
        let order = players.map { $0.id }
        let log = makeLog(
            battingOrder: order,
            inning0: [players[0].id: .pitcher, players[1].id: .catcher]
        )

        store.applyGameLog(log)

        XCTAssertEqual(store.lineup.battingOrder, order)
        XCTAssertEqual(store.lineup.innings[0].assignments[players[0].id], .pitcher)
        XCTAssertEqual(store.lineup.innings[0].assignments[players[1].id], .catcher)
    }

    func testDepartedPlayersAreDroppedAndOrderCompresses() {
        let ghost = UUID() // archived player no longer on the roster
        let log = makeLog(
            battingOrder: [players[0].id, ghost, players[1].id],
            inning0: [players[0].id: .pitcher, ghost: .catcher]
        )

        store.applyGameLog(log)

        XCTAssertEqual(store.lineup.battingOrder, [players[0].id, players[1].id],
                       "Departed player should be removed without leaving a gap")
        XCTAssertNil(store.lineup.innings[0].assignments[ghost],
                     "Departed player's cell should be left open")
        XCTAssertEqual(store.lineup.innings[0].assignments[players[0].id], .pitcher)
    }

    // MARK: - ABS handling

    func testAbsentAssignmentsAreNotCarriedOver() {
        let log = makeLog(
            battingOrder: players.map { $0.id },
            inning0: [players[0].id: .absent, players[1].id: .bench]
        )

        store.applyGameLog(log)

        XCTAssertNil(store.lineup.innings[0].assignments[players[0].id],
                     "Absence is specific to the archived game and should not follow forward")
        XCTAssertEqual(store.lineup.innings[0].assignments[players[1].id], .bench,
                       "Bench is part of the rotation and should be reused")
        XCTAssertTrue(store.lineup.absentPlayerIDs.isEmpty)
    }

    // MARK: - Inning count

    func testInningsResizeToTeamGameLength() {
        store.teams[0].gameInningCount = 5
        let log = makeLog(battingOrder: players.map { $0.id }, inning0: [:], inningCount: 7)

        store.applyGameLog(log)

        XCTAssertEqual(store.lineup.innings.count, 5)
    }

    func testShorterLogPadsWithEmptyInnings() {
        store.teams[0].gameInningCount = 7
        let log = makeLog(battingOrder: players.map { $0.id }, inning0: [:], inningCount: 4)

        store.applyGameLog(log)

        XCTAssertEqual(store.lineup.innings.count, 7)
        XCTAssertTrue(store.lineup.innings[6].assignments.isEmpty)
    }

    // MARK: - Current game info is preserved

    func testCurrentGameDateAndOpponentSurviveApply() {
        let today = Date()
        store.teams[0].lineup.gameDate = today
        store.teams[0].lineup.opponent = "Sharks"

        let log = makeLog(battingOrder: players.map { $0.id }, inning0: [:])
        store.applyGameLog(log)

        XCTAssertEqual(store.lineup.opponent, "Sharks",
                       "Applying an old lineup reuses its shape, not its game info")
        XCTAssertEqual(store.lineup.gameDate.timeIntervalSince1970,
                       today.timeIntervalSince1970, accuracy: 1)
    }

    func testApplyRevertsFinalizedLineupToDraft() {
        store.teams[0].lineup.status = .finalized
        let log = makeLog(battingOrder: players.map { $0.id }, inning0: [:])

        store.applyGameLog(log)

        XCTAssertEqual(store.lineup.status, .draft)
    }

    // MARK: - Duplicate positions (reported bug)

    /// Repro for the reported bug: applying a historical game left two players
    /// at the same position in an inning.
    func testApplyReplacesExistingAssignmentsEntirely() {
        // Current game already has players 0 and 1 at P and SS.
        store.assignPosition(player: players[0], inning: 0, position: .pitcher)
        store.assignPosition(player: players[1], inning: 0, position: .shortstop)

        // Historical game has *different* players at those positions.
        let log = makeLog(
            battingOrder: players.map { $0.id },
            inning0: [players[2].id: .pitcher, players[3].id: .shortstop]
        )

        store.applyGameLog(log)

        let inning0 = store.lineup.innings[0]
        XCTAssertEqual(inning0.assignments[players[2].id], .pitcher)
        XCTAssertEqual(inning0.assignments[players[3].id], .shortstop)
        XCTAssertNil(inning0.assignments[players[0].id], "Previous pitcher should be gone")
        XCTAssertNil(inning0.assignments[players[1].id], "Previous shortstop should be gone")
        XCTAssertEqual(inning0.assignments.values.filter { $0 == .pitcher }.count, 1)
        XCTAssertEqual(inning0.assignments.values.filter { $0 == .shortstop }.count, 1)
    }

    /// A log that itself contains two players at one position must not
    /// propagate that into the current game.
    func testDuplicatePositionsInLogAreNotPropagated() {
        let log = makeLog(
            battingOrder: players.map { $0.id },
            inning0: [
                players[0].id: .pitcher,
                players[1].id: .pitcher,   // corrupt log: two pitchers
                players[2].id: .shortstop,
                players[3].id: .shortstop, // corrupt log: two shortstops
            ]
        )

        store.applyGameLog(log)

        let inning0 = store.lineup.innings[0]
        XCTAssertEqual(inning0.assignments.values.filter { $0 == .pitcher }.count, 1,
                       "Only one player may hold a fielding position in an inning")
        XCTAssertEqual(inning0.assignments.values.filter { $0 == .shortstop }.count, 1,
                       "Only one player may hold a fielding position in an inning")
    }

    /// Bench and ABS are the exceptions — any number of players may share them.
    func testBenchAllowsMultiplePlayers() {
        let log = makeLog(
            battingOrder: players.map { $0.id },
            inning0: [players[0].id: .bench, players[1].id: .bench, players[2].id: .bench]
        )

        store.applyGameLog(log)

        XCTAssertEqual(store.lineup.innings[0].assignments.values.filter { $0 == .bench }.count, 3)
    }

    /// Templates have the same exposure: two locks can name one position.
    func testConflictingTemplateLocksDoNotProduceDuplicates() {
        let template = LineupTemplate(
            name: "Conflict",
            battingOrder: players.map { $0.id },
            positionLocks: [
                PositionLock(playerID: players[0].id, position: .pitcher, innings: 0...0),
                PositionLock(playerID: players[1].id, position: .pitcher, innings: 0...0),
            ]
        )

        store.applyTemplate(template)

        XCTAssertEqual(store.lineup.innings[0].assignments.values.filter { $0 == .pitcher }.count, 1)
    }

    /// The batting order decides who keeps a contested position, so the same
    /// input always resolves the same way.
    func testDuplicateResolutionPrefersEarlierInBattingOrder() {
        let order = [players[3].id, players[2].id, players[1].id, players[0].id]
        let log = makeLog(
            battingOrder: order,
            inning0: [players[0].id: .pitcher, players[3].id: .pitcher]
        )

        store.applyGameLog(log)

        XCTAssertEqual(store.lineup.innings[0].assignments[players[3].id], .pitcher,
                       "Player batting first should keep the contested position")
        XCTAssertNil(store.lineup.innings[0].assignments[players[0].id],
                     "Loser of the conflict is left open, not benched")
    }

    // MARK: - Seeded debug data

    /// The debug seeder feeds the History tab, and those games can be applied
    /// to a real lineup — so its grids have to be alignments the app's own
    /// editing rules would permit. An earlier version had two pitchers in the
    /// first inning, which surfaced as duplicates after Apply.
    func testSeededGameLogsAreValidLineups() {
        let seeded = DebugDataSeeder.debugAssignmentGrid()
        // The nine positions of a standard 3-outfielder alignment. LCF/RCF
        // only exist in 4-outfielder configs, which the seeded team doesn't
        // use. Ten players means exactly one bench slot per inning.
        let expected: Set<FieldPosition> = [
            .pitcher, .catcher, .firstBase, .secondBase, .thirdBase,
            .shortstop, .leftField, .centerField, .rightField,
        ]

        XCTAssertEqual(seeded.count, 7)

        for (index, inning) in seeded.enumerated() {
            let fielding = inning.assignments.values.filter { !$0.isNonFielding }

            XCTAssertEqual(Set(fielding), expected,
                           "Inning \(index + 1) should fill every field position exactly once")
            XCTAssertEqual(fielding.count, Set(fielding).count,
                           "Inning \(index + 1) has a position filled by two players")
            XCTAssertEqual(inning.assignments.values.filter { $0 == .bench }.count, 1,
                           "Inning \(index + 1) should sit exactly one player")
            XCTAssertEqual(inning.assignments.count, 10)
        }
    }

    /// The seeder sets Never preferences to drive the stripe UI; assigning a
    /// player a position they'd never play makes that data self-contradictory.
    func testSeededGridRespectsNeverPreferences() {
        let seeded = DebugDataSeeder.debugAssignmentGrid()
        let roster = DebugDataSeeder.fakePlayers

        for (index, inning) in seeded.enumerated() {
            for (playerID, position) in inning.assignments {
                guard let player = roster.first(where: { $0.id == playerID }) else { continue }
                XCTAssertNotEqual(player.positionPreferences[position], .never,
                                  "Inning \(index + 1): \(player.firstName) assigned \(position.rawValue), marked Never")
            }
        }
    }

    /// Nobody should sit in consecutive innings — that would trip the app's
    /// own back-to-back bench warning on freshly seeded data.
    func testSeededGridHasNoBackToBackBench() {
        let seeded = DebugDataSeeder.debugAssignmentGrid()

        for index in 0..<(seeded.count - 1) {
            let sittingNow = Set(seeded[index].assignments.filter { $0.value == .bench }.keys)
            let sittingNext = Set(seeded[index + 1].assignments.filter { $0.value == .bench }.keys)
            XCTAssertTrue(sittingNow.intersection(sittingNext).isEmpty,
                          "A player sits in both inning \(index + 1) and \(index + 2)")
        }
    }
}
