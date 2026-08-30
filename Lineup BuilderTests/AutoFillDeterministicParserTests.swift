import XCTest
@testable import Lineup_Builder

// Tests the model-free deterministic parser that handles the common, templated
// coach instructions. Runs entirely without Apple Intelligence (the whole point),
// so it exercises the same path a device without the on-device model would take.

@MainActor
final class AutoFillDeterministicParserTests: XCTestCase {

    // Seeded roster has unique first names (Jake, Connor, Tyler, Marcus, Drew,
    // Eli, Owen, Nate, Leo, Cam) — good for name-matching tests.
    private func service(inningCount: Int = 6) -> AutoFillNLConstraintService {
        AutoFillNLConstraintService(activePlayers: DebugDataSeeder.fakePlayers, inningCount: inningCount)
    }

    private func player(_ name: String) -> Player {
        DebugDataSeeder.fakePlayers.first { $0.firstName == name }!
    }

    private func constraint(
        _ parse: AutoFillNLConstraintService.DeterministicParse,
        player name: String, target: AutoFillConstraintTarget, intent: AutoFillConstraintIntent
    ) -> AutoFillPlayerConstraint? {
        let id = player(name).id
        return parse.constraints.first {
            $0.playerID == id && $0.target == target && $0.intent == intent
        }
    }

    // MARK: - Single player, position + range

    func testPitchesFirstTwoInnings() {
        let p = service().parseDeterministically("Jake pitches the first 2 innings")
        XCTAssertFalse(p.hasUnresolvedInstruction)
        let assign = constraint(p, player: "Jake", target: .position(.pitcher), intent: .assign)
        XCTAssertEqual(assign?.inningRange, 0...1, "First 2 innings = zero-based 0...1")
        // Implicit exact-boundary avoid for the rest of the game.
        let avoid = constraint(p, player: "Jake", target: .position(.pitcher), intent: .avoid)
        XCTAssertEqual(avoid?.inningRange, 2...5)
    }

    func testExplicitInningRange() {
        let p = service().parseDeterministically("Tyler plays second base innings 3 to 5")
        let c = constraint(p, player: "Tyler", target: .position(.secondBase), intent: .assign)
        XCTAssertEqual(c?.inningRange, 2...4)
    }

    func testPlaysAtPositionNoInningDefaultsToInningOne() {
        let p = service().parseDeterministically("Jake at short")
        let c = constraint(p, player: "Jake", target: .position(.shortstop), intent: .assign)
        XCTAssertEqual(c?.inningRange, 0...0, "A bare assign means inning 1 only")
    }

    func testCatchesVerb() {
        let p = service().parseDeterministically("Owen catches")
        XCTAssertNotNil(constraint(p, player: "Owen", target: .position(.catcher), intent: .assign))
    }

    func testStartsOnTheBench() {
        let p = service().parseDeterministically("Nate starts on the bench")
        let c = constraint(p, player: "Nate", target: .bench, intent: .assign)
        XCTAssertEqual(c?.inningRange, 0...0)
    }

    // MARK: - Avoid

    func testKeepOffPitcherIsWholeGameAvoid() {
        let p = service().parseDeterministically("keep Nate off pitcher")
        let c = constraint(p, player: "Nate", target: .position(.pitcher), intent: .avoid)
        XCTAssertEqual(c?.inningRange, 0...5, "A bare avoid means the whole game, not just inning 1")
    }

    func testDontLetPitch() {
        let p = service().parseDeterministically("don't let Drew pitch")
        XCTAssertNotNil(constraint(p, player: "Drew", target: .position(.pitcher), intent: .avoid))
    }

    // MARK: - Name lists and compounds

    func testNameListSharesOnePlacement() {
        let p = service().parseDeterministically("Marcus, Drew and Eli play infield")
        XCTAssertFalse(p.hasUnresolvedInstruction)
        for name in ["Marcus", "Drew", "Eli"] {
            XCTAssertNotNil(constraint(p, player: name, target: .infield, intent: .assign),
                            "\(name) should be assigned infield")
        }
    }

    func testCompoundDifferentSubjects() {
        let p = service().parseDeterministically("Jake pitches and Owen catches")
        XCTAssertFalse(p.hasUnresolvedInstruction)
        XCTAssertNotNil(constraint(p, player: "Jake", target: .position(.pitcher), intent: .assign))
        XCTAssertNotNil(constraint(p, player: "Owen", target: .position(.catcher), intent: .assign))
    }

    func testEveryonePlaysInfield() {
        let p = service().parseDeterministically("everyone plays infield")
        XCTAssertEqual(p.constraints.filter { $0.target == .infield && $0.intent == .assign }.count,
                       DebugDataSeeder.fakePlayers.count)
    }

    // MARK: - Deferrals to the model (hasUnresolvedInstruction)

    func testSameSubjectCompoundDefersToModel() {
        // "then plays outfield" has no named subject and an implied relative
        // range — deterministically unsafe, so defer.
        let p = service().parseDeterministically("Jake starts on the bench then plays outfield")
        XCTAssertTrue(p.hasUnresolvedInstruction)
    }

    func testDuplicateFirstNameDefersToModel() {
        let sam1 = Player(firstName: "Sam", lastName: "A", number: "1")
        let sam2 = Player(firstName: "Sam", lastName: "B", number: "2")
        let svc = AutoFillNLConstraintService(activePlayers: [sam1, sam2], inningCount: 6)
        let p = svc.parseDeterministically("Sam pitches the first inning")
        XCTAssertTrue(p.hasUnresolvedInstruction, "A shared first name can't be resolved deterministically")
    }

    func testFreeformProducesNothing() {
        // No roster name, no recognizable target — parser stays out of it; the
        // coordinator will route this to the model.
        let p = service().parseDeterministically("give the twins a breather up the middle")
        XCTAssertTrue(p.constraints.isEmpty)
    }

    // MARK: - Doesn't confuse pattern-rule prompts

    func testPurePatternPromptHasNoPlayerConstraints() {
        // Bench pairing is detected separately; the player-constraint parser
        // must not invent anything from it.
        let p = service().parseDeterministically("any player who sits must sit 2 consecutive innings")
        XCTAssertTrue(p.constraints.isEmpty)
        XCTAssertFalse(p.hasUnresolvedInstruction)
    }
}
