import XCTest
@testable import Lineup_Builder

// MARK: - AutoFill NL Pattern-Rule Detection Tests
//
// The on-device model is asked to set game-wide "pattern rule" flags (today:
// bench pairing) from free text, but a small on-device model sets a single
// niche boolean unreliably — the coach's "Any player who sits, must sit 2
// consecutive innings" is exactly the phrasing it missed in the field. So the
// service also runs a deterministic keyword detector, and THAT is what these
// tests pin down. They exercise detectedPatternRules(in:) directly, which needs
// neither Apple Intelligence nor a roster (the simulator has no model), so they
// run everywhere.

@MainActor
final class AutoFillNLPatternRuleTests: XCTestCase {

    private func detectsPairing(_ prompt: String) -> Bool {
        // Pure static detection — needs neither a model session nor a roster.
        AutoFillNLConstraintService.detectedPatternRules(in: prompt).benchInConsecutivePairs
    }

    // MARK: Positive cases — should activate bench pairing

    func testDetectsTheCoachsExactPhrasing() {
        XCTAssertTrue(detectsPairing("Any player who sits, must sit 2 consecutive innings"))
    }

    func testDetectsCommonPairingPhrasings() {
        let prompts = [
            "have players sit two innings in a row",
            "players should sit two in a row",
            "double up the bench",
            "when someone sits, keep them on the bench back to back",
            "anyone who is benched sits two consecutive innings"
        ]
        for prompt in prompts {
            XCTAssertTrue(detectsPairing(prompt), "Should detect bench pairing in: \(prompt)")
        }
    }

    /// Natural, conversational sports lingo — "sit" means "bench," and coaches
    /// phrase the rule as a repetition ("again", "the next one too") rather than
    /// with the word "consecutive."
    func testDetectsConversationalSportsLingo() {
        let prompts = [
            "if a player sits one inning, have them sit the next too",
            "when a kid sits, sit them again",
            "if someone sits, they sit the next inning as well",
            "anyone who sits, benches the next one too"
        ]
        for prompt in prompts {
            XCTAssertTrue(detectsPairing(prompt), "Should detect bench pairing in natural lingo: \(prompt)")
        }
    }

    // MARK: Negative cases — should NOT activate

    func testDoesNotFireOnTheOppositeRequest() {
        // These mean "avoid back-to-back" — the default behavior, not pairing.
        let prompts = [
            "don't sit anyone two innings in a row",
            "no back-to-back bench",
            "never sit a player consecutive innings",
            "avoid sitting players back to back"
        ]
        for prompt in prompts {
            XCTAssertFalse(detectsPairing(prompt), "Should NOT treat an avoidance request as pairing: \(prompt)")
        }
    }

    func testDoesNotFireOnConsecutiveWithoutBench() {
        // "consecutive" tied to a field position, not the bench, is a per-player
        // matter (handled elsewhere), not the bench-pairing pattern.
        XCTAssertFalse(detectsPairing("Caleb plays two consecutive innings at shortstop"))
        XCTAssertFalse(detectsPairing("Pitch Owen the first two innings"))
    }

    func testDoesNotFireOnAnEmptyOrUnrelatedPrompt() {
        XCTAssertFalse(detectsPairing(""))
        XCTAssertFalse(detectsPairing("Keep Zachary at catcher all game"))
    }
}
