import XCTest
@testable import Lineup_Builder

// MARK: - AutoFillCoordinator Tests
//
// The coordinator exists because the iPhone grid and the iPad summary pane each
// had their own copy of this sequence, and FillLineupIntent would have been a
// third. These tests pin the parts all three now share: how a scope reads in
// coach-facing text, and how the parse-side and engine-side messages get
// combined. The engine itself is covered by AutoFillEngineTests.
//
// Everything here avoids the on-device model — `outcome(from:...)` is split out
// of `run` precisely so message composition is testable without Apple
// Intelligence, which is unavailable in the test runner anyway.

final class AutoFillCoordinatorTests: XCTestCase {

    private func makePlayer(_ name: String) -> Player {
        Player(firstName: name, lastName: "Test", number: "0")
    }

    private func makeResult(
        filledCount: Int = 0,
        unfilledSlots: [AutoFillUnfilledSlot] = []
    ) -> AutoFillResult {
        AutoFillResult(
            lineup: Lineup(),
            filledCount: filledCount,
            unfilledSlots: unfilledSlots
        )
    }

    // MARK: - Scope

    func testScopeReadsAsOneBasedInnings() {
        // Indices are zero-based everywhere in the engine; only coach-facing
        // text is 1-based. Getting this backwards is an off-by-one nobody
        // notices until a coach reads "inning 0".
        XCTAssertEqual(AutoFillScope.inning(0).label, "inning 1")
        XCTAssertEqual(AutoFillScope.inning(2).label, "inning 3")
        XCTAssertEqual(AutoFillScope.through(5).label, "innings 1–6")
    }

    func testOnlyARangeIsMultiInning() {
        // Drives whether incompleteMessage names inning numbers.
        XCTAssertFalse(AutoFillScope.inning(3).isMultiInning)
        XCTAssertTrue(AutoFillScope.through(3).isMultiInning)
    }

    func testAnalyticsModeMatchesTheShippedSignalValues() {
        // The autofill.used funnel already has history under these two strings.
        XCTAssertEqual(AutoFillScope.inning(0).analyticsMode, "inning")
        XCTAssertEqual(AutoFillScope.through(0).analyticsMode, "range")
    }

    // MARK: - Undo copy

    func testUndoMessageNamesTheCountAndScope() {
        let outcome = AutoFillCoordinator.outcome(
            from: makeResult(filledCount: 9),
            scope: .inning(2),
            players: [],
            parseDiagnosticMessage: nil
        )
        XCTAssertEqual(outcome.undoMessage, "Auto-filled 9 positions (inning 3)")
    }

    func testUndoMessageIsSingularForOnePosition() {
        let outcome = AutoFillCoordinator.outcome(
            from: makeResult(filledCount: 1),
            scope: .through(5),
            players: [],
            parseDiagnosticMessage: nil
        )
        XCTAssertEqual(outcome.undoMessage, "Auto-filled 1 position (innings 1–6)")
    }

    // MARK: - Spoken summary
    //
    // Siri's answer has to stand alone — the coach may not be looking at the
    // screen — so the three zero-filled cases must not collapse into one
    // ambiguous sentence.

    func testSpokenSummaryLeadsWithWhatChanged() {
        let outcome = AutoFillCoordinator.outcome(
            from: makeResult(filledCount: 18),
            scope: .through(2),
            players: [],
            parseDiagnosticMessage: nil
        )
        XCTAssertEqual(outcome.spokenSummary, "Filled 18 positions in innings 1–3.")
    }

    func testSpokenSummaryDistinguishesAlreadyFullFromCouldNotFill() {
        let alreadyFull = AutoFillCoordinator.outcome(
            from: makeResult(filledCount: 0),
            scope: .through(2),
            players: [],
            parseDiagnosticMessage: nil
        )
        XCTAssertEqual(alreadyFull.spokenSummary,
                       "Every position in innings 1–3 was already assigned.")

        let blocked = AutoFillCoordinator.outcome(
            from: makeResult(
                filledCount: 0,
                unfilledSlots: [AutoFillUnfilledSlot(inningIndex: 0,
                                                     position: .pitcher,
                                                     reason: .rosterTooSmall)]
            ),
            scope: .inning(0),
            players: [],
            parseDiagnosticMessage: nil
        )
        XCTAssertTrue(blocked.spokenSummary.hasPrefix("I couldn't fill anything in inning 1."),
                      "Got: \(blocked.spokenSummary)")
    }

    func testSpokenSummaryFlattensTheParagraphBreaksInAlertCopy() {
        // incompleteMessage is written for an alert and uses blank lines
        // between reasons. Spoken aloud those become dead air, and in a
        // Shortcuts result card they render as a ragged block.
        let outcome = AutoFillCoordinator.outcome(
            from: makeResult(
                filledCount: 4,
                unfilledSlots: [
                    AutoFillUnfilledSlot(inningIndex: 0, position: .pitcher, reason: .rosterTooSmall),
                    AutoFillUnfilledSlot(inningIndex: 1, position: .catcher, reason: .neverPreferences),
                ]
            ),
            scope: .through(1),
            players: [],
            parseDiagnosticMessage: nil
        )
        XCTAssertFalse(outcome.spokenSummary.contains("\n"),
                       "Got: \(outcome.spokenSummary)")
        XCTAssertTrue(outcome.spokenSummary.hasPrefix("Filled 4 positions in innings 1–2."))
    }

    // MARK: - Message composition

    func testIncompleteMessageNamesInningsOnlyForARange() {
        let slots = [AutoFillUnfilledSlot(inningIndex: 2, position: .pitcher, reason: .rosterTooSmall)]

        let single = AutoFillCoordinator.outcome(
            from: makeResult(unfilledSlots: slots),
            scope: .inning(2),
            players: [],
            parseDiagnosticMessage: nil
        )
        XCTAssertNotNil(single.incompleteMessage)
        XCTAssertFalse(single.incompleteMessage!.contains("Inning 3"),
                       "A single-inning fill already says which inning; repeating it is noise")

        let range = AutoFillCoordinator.outcome(
            from: makeResult(unfilledSlots: slots),
            scope: .through(4),
            players: [],
            parseDiagnosticMessage: nil
        )
        XCTAssertTrue(range.incompleteMessage!.contains("Inning 3"),
                      "Got: \(range.incompleteMessage!)")
    }

    func testEverythingFilledProducesNoMessagesAtAll() {
        let outcome = AutoFillCoordinator.outcome(
            from: makeResult(filledCount: 9),
            scope: .inning(0),
            players: [],
            parseDiagnosticMessage: nil
        )
        XCTAssertNil(outcome.incompleteMessage)
        XCTAssertNil(outcome.noticeMessage, "An empty notice must be nil, not \"\" — the views alert on non-nil")
        XCTAssertTrue(outcome.didFill)
        XCTAssertFalse(outcome.hasUnfilledSlots)
    }

    func testParseDiagnosticSurvivesWithNoEngineNotice() {
        // The common case for a misheard instruction: nothing was overridden,
        // but the coach still needs to know their sentence was skipped.
        let outcome = AutoFillCoordinator.outcome(
            from: makeResult(filledCount: 9),
            scope: .inning(0),
            players: [],
            parseDiagnosticMessage: "I couldn't find a player named Kayleb."
        )
        XCTAssertEqual(outcome.noticeMessage, "I couldn't find a player named Kayleb.")
    }

    func testParseDiagnosticLeadsTheEngineNotice() {
        // A skipped instruction is the more surprising outcome, so it goes
        // first when both have something to say.
        let player = makePlayer("Caleb")
        let result = AutoFillResult(
            lineup: Lineup(),
            filledCount: 9,
            unfilledSlots: [],
            constraintOverrides: [
                AutoFillConstraintOverride(
                    inningIndex: 2,
                    playerID: player.id,
                    target: .position(.pitcher),
                    reason: .pitcherSoftCapBypassed
                )
            ]
        )

        let outcome = AutoFillCoordinator.outcome(
            from: result,
            scope: .through(5),
            players: [player],
            parseDiagnosticMessage: "I couldn't find a player named Kayleb."
        )

        let notice = try! XCTUnwrap(outcome.noticeMessage)
        let lines = notice.components(separatedBy: "\n")
        XCTAssertEqual(lines.first, "I couldn't find a player named Kayleb.")
        XCTAssertTrue(notice.contains("Caleb"), "Got: \(notice)")
    }

    // MARK: - FillLineupIntent inning resolution

    func testUnspecifiedInningFillsTheWholeConfiguredGame() {
        var team = Team()
        team.gameInningCount = 6
        // Zero-based: inning 6 is index 5.
        XCTAssertEqual(FillLineupIntent.lastInningIndex(for: team, requested: nil), 5)
    }

    func testRequestedInningWinsOverTheConfiguredGameLength() {
        var team = Team()
        team.gameInningCount = 7
        XCTAssertEqual(FillLineupIntent.lastInningIndex(for: team, requested: 3), 2)
    }

    func testRequestedInningIsClampedToTheInningsThatExist() {
        // Siri hands back whatever number it heard. Asking for inning 12 of a
        // 7-inning game must fill 7, not trap on an out-of-range index.
        let team = Team()
        let available = team.lineup.innings.count
        XCTAssertEqual(FillLineupIntent.lastInningIndex(for: team, requested: 12), available - 1)
        XCTAssertEqual(FillLineupIntent.lastInningIndex(for: team, requested: 0), 0)
        XCTAssertEqual(FillLineupIntent.lastInningIndex(for: team, requested: -3), 0)
    }
}
