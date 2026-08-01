import XCTest
@testable import Lineup_Builder

// MARK: - PitchEligibilityAnswer Tests
//
// This is the intent where a wrong answer has a consequence off the phone, so
// most of what's pinned here is the difference between "no" and "I didn't
// check". `PitchEligibilityEngine.status` returns `.eligible` for a rested
// player, for a team with pitching rules switched off, and for a bracket with
// no limits entered — and only the first of those is a yes.

final class PitchEligibilityAnswerTests: XCTestCase {

    // MARK: - Fixtures

    private func team(rulesEnabled: Bool = true, preset: Bool = true) -> Team {
        var team = Team()
        team.name = "Tigers"
        team.pitchingConfig.rulesEnabled = rulesEnabled
        if preset { team.pitchingConfig.applyLittleLeaguePreset() }
        return team
    }

    private func player(_ first: String = "Bobby", age: Int? = 11) -> Player {
        Player(firstName: first, lastName: "Reyes", number: "7", leagueAge: age)
    }

    /// A log on `daysAgo` where `player` threw `pitches`.
    private func log(_ player: Player, pitches: Int, daysAgo: Int,
                     from now: Date = Date()) -> GameLog {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: now)!
        return GameLog(
            gameDate: date,
            opponent: "Eagles",
            inningsPlayed: 5,
            battingOrder: [player.id],
            innings: Array(repeating: InningAssignment(), count: 7),
            playerSnapshot: [PlayerSnapshot(from: player)],
            pitchCounts: [player.id.uuidString: pitches]
        )
    }

    private func containsDigit(_ text: String) -> Bool {
        text.rangeOfCharacter(from: .decimalDigits) != nil
    }

    // MARK: - The .eligible conflation
    //
    // The three cases that all come back from the engine as `.eligible`.

    func testRulesOffIsNotAYes() {
        // The engine returns .eligible here because there's nothing to check.
        // Spoken, "Yes, Bobby can pitch" would sound like the app checked.
        var subject = team(rulesEnabled: false)
        let bobby = player()
        subject.players = [bobby]

        let answer = PitchEligibilityAnswerBuilder.answer(player: bobby, team: subject)

        XCTAssertEqual(answer.verdict, .notTracked(.rulesOff))
        XCTAssertFalse(answer.verdict.isAnswered)
        XCTAssertFalse(answer.spokenSummary.lowercased().hasPrefix("yes"), answer.spokenSummary)
        XCTAssertTrue(answer.spokenSummary.contains("not tracking pitch counts"), answer.spokenSummary)
    }

    func testBracketWithNoLimitsIsNotAYes() {
        // Rules on, age known, but nobody ever filled in the 11-12 row.
        var subject = team(preset: false)
        subject.pitchingConfig.ageLimits = [
            .u10: PitchingLimits(dailyMax: 75, restDay1Min: 21, restDay2Min: 36)
        ]
        let bobby = player(age: 12)
        subject.players = [bobby]

        let answer = PitchEligibilityAnswerBuilder.answer(player: bobby, team: subject)

        XCTAssertEqual(answer.verdict, .notTracked(.noLimitsForBracket(.u12)))
        XCTAssertFalse(answer.spokenSummary.lowercased().hasPrefix("yes"), answer.spokenSummary)
        // Must not borrow the one bracket that is configured.
        XCTAssertFalse(answer.spokenSummary.contains("75"), answer.spokenSummary)
    }

    func testGenuinelyRestedIsAYesWithTheirLimit() {
        var subject = team()
        let bobby = player()
        subject.players = [bobby]

        let answer = PitchEligibilityAnswerBuilder.answer(player: bobby, team: subject)

        XCTAssertEqual(answer.verdict, .clear(maxPitches: 85))
        XCTAssertTrue(answer.spokenSummary.hasPrefix("Yes, Bobby can pitch today"), answer.spokenSummary)
        XCTAssertTrue(answer.spokenSummary.contains("up to 85 pitches"), answer.spokenSummary)
    }

    func testMissingLeagueAgeIsNotAYes() {
        var subject = team()
        let bobby = player(age: nil)
        subject.players = [bobby]

        let answer = PitchEligibilityAnswerBuilder.answer(player: bobby, team: subject)

        XCTAssertEqual(answer.verdict, .notTracked(.noLeagueAge))
        XCTAssertFalse(answer.spokenSummary.lowercased().hasPrefix("yes"), answer.spokenSummary)
    }

    func testAgeAboveEveryBracketIsNotAYes() {
        // The engine returns .eligible for a 17-year-old too.
        var subject = team()
        let bobby = player(age: 17)
        subject.players = [bobby]

        let answer = PitchEligibilityAnswerBuilder.answer(player: bobby, team: subject)

        XCTAssertEqual(answer.verdict, .notTracked(.ageOutOfRange(17)))
        XCTAssertFalse(answer.spokenSummary.lowercased().hasPrefix("yes"), answer.spokenSummary)
    }

    // MARK: - Rest

    func testAPlayerInsideTheirRestWindowIsBlocked() {
        // 55 pitches for an 11-year-old needs 3 rest days, so a game yesterday
        // leaves them unavailable today.
        var subject = team()
        let bobby = player()
        subject.players = [bobby]
        subject.gameLogs = [log(bobby, pitches: 55, daysAgo: 1)]

        let answer = PitchEligibilityAnswerBuilder.answer(player: bobby, team: subject)

        guard case .blocked = answer.verdict else {
            return XCTFail("Expected blocked, got \(answer.verdict)")
        }
        XCTAssertTrue(answer.spokenSummary.hasPrefix("No."), answer.spokenSummary)
        // A "no" has to say why, or it's just an assertion the coach can't check.
        XCTAssertTrue(answer.spokenSummary.contains("55 pitches"), answer.spokenSummary)
    }

    func testRestClearsOnceEnoughDaysHavePassed() {
        var subject = team()
        let bobby = player()
        subject.players = [bobby]
        subject.gameLogs = [log(bobby, pitches: 55, daysAgo: 10)]

        let answer = PitchEligibilityAnswerBuilder.answer(player: bobby, team: subject)

        XCTAssertEqual(answer.verdict, .clear(maxPitches: 85))
        // The outing still gets mentioned — it's context, not a verdict.
        XCTAssertEqual(answer.lastOuting?.pitches, 55)
    }

    func testAskingAboutAFutureDateUsesThatDate() {
        // The whole point of the date parameter: 55 pitches yesterday blocks
        // today, but not a game the following week.
        var subject = team()
        let bobby = player()
        subject.players = [bobby]
        subject.gameLogs = [log(bobby, pitches: 55, daysAgo: 1)]

        let today = PitchEligibilityAnswerBuilder.answer(player: bobby, team: subject)
        let nextWeek = PitchEligibilityAnswerBuilder.answer(
            player: bobby, team: subject,
            on: Calendar.current.date(byAdding: .day, value: 7, to: Date())!
        )

        guard case .blocked = today.verdict else {
            return XCTFail("Expected today to be blocked, got \(today.verdict)")
        }
        XCTAssertEqual(nextWeek.verdict, .clear(maxPitches: 85))
    }

    func testAnUnansweredVerdictCarriesNoPitchCount() {
        // Reciting "they last threw 55 pitches" under "I'm not tracking pitch
        // counts" contradicts the sentence it's attached to.
        var subject = team(rulesEnabled: false)
        let bobby = player()
        subject.players = [bobby]
        subject.gameLogs = [log(bobby, pitches: 55, daysAgo: 1)]

        let answer = PitchEligibilityAnswerBuilder.answer(player: bobby, team: subject)

        XCTAssertNil(answer.lastOuting)
        XCTAssertFalse(containsDigit(answer.spokenSummary), answer.spokenSummary)
    }

    func testLastOutingIgnoresGamesOnOrAfterTheDateAsked() {
        // Mirrors the engine, which only counts games already played. A game
        // logged for today isn't a reason to rest today.
        var subject = team()
        let bobby = player()
        subject.players = [bobby]
        subject.gameLogs = [log(bobby, pitches: 60, daysAgo: 0)]

        let answer = PitchEligibilityAnswerBuilder.answer(player: bobby, team: subject)

        XCTAssertNil(answer.lastOuting)
        XCTAssertEqual(answer.verdict, .clear(maxPitches: 85))
    }

    func testLastOutingPicksTheMostRecentOfSeveral() {
        var subject = team()
        let bobby = player()
        subject.players = [bobby]
        subject.gameLogs = [
            log(bobby, pitches: 40, daysAgo: 20),
            log(bobby, pitches: 12, daysAgo: 8),
            log(bobby, pitches: 33, daysAgo: 14)
        ]

        let answer = PitchEligibilityAnswerBuilder.answer(player: bobby, team: subject)

        XCTAssertEqual(answer.lastOuting?.pitches, 12)
    }

    // MARK: - Weekly cap

    func testAWeeklyCapReportsWhatIsLeftRatherThanAFlatYes() {
        var subject = team()
        subject.pitchingConfig.weeklyLimitEnabled = true
        subject.pitchingConfig.weeklyLimit = 70
        let bobby = player()
        subject.players = [bobby]
        subject.gameLogs = [log(bobby, pitches: 50, daysAgo: 5)]

        let answer = PitchEligibilityAnswerBuilder.answer(player: bobby, team: subject)

        guard case .limited(let remaining) = answer.verdict else {
            return XCTFail("Expected limited, got \(answer.verdict)")
        }
        XCTAssertEqual(remaining, 20)
        XCTAssertTrue(answer.spokenSummary.contains("only 20 more pitches"), answer.spokenSummary)
    }

    // MARK: - Phrasing

    func testDayPhraseFacesBothDirections() {
        // GameRecap.datePhrase only looks backwards; this question is usually
        // about an upcoming game and cites a past one in the same sentence.
        let now = Date()
        let calendar = Calendar.current
        XCTAssertEqual(PitchEligibilityAnswer.dayPhrase(now, relativeTo: now), "today")
        XCTAssertEqual(PitchEligibilityAnswer.dayPhrase(
            calendar.date(byAdding: .day, value: 1, to: now)!, relativeTo: now), "tomorrow")
        XCTAssertEqual(PitchEligibilityAnswer.dayPhrase(
            calendar.date(byAdding: .day, value: -1, to: now)!, relativeTo: now), "yesterday")

        // Beyond a week either way a bare weekday stops being unambiguous.
        let farOut = PitchEligibilityAnswer.dayPhrase(
            calendar.date(byAdding: .day, value: 30, to: now)!, relativeTo: now)
        XCTAssertTrue(farOut.contains(","), farOut)
    }

    func testShortSummaryDoesNotRepeatTheSnippet() {
        var subject = team()
        let bobby = player()
        subject.players = [bobby]
        subject.gameLogs = [log(bobby, pitches: 55, daysAgo: 10)]

        let answer = PitchEligibilityAnswerBuilder.answer(player: bobby, team: subject)

        XCTAssertEqual(answer.shortSummary, "Yes — Bobby is clear to pitch.")
        XCTAssertFalse(containsDigit(answer.shortSummary), answer.shortSummary)
        // The full answer still carries the numbers, for the voice-only case.
        XCTAssertTrue(answer.spokenSummary.contains("85"), answer.spokenSummary)
    }

    func testAnUntrackedShortSummaryIsTheWholeAnswer() {
        // Nothing renders in the snippet's table, so the short line has to carry it.
        var subject = team(rulesEnabled: false)
        let bobby = player()
        subject.players = [bobby]

        let answer = PitchEligibilityAnswerBuilder.answer(player: bobby, team: subject)

        XCTAssertEqual(answer.shortSummary, answer.spokenSummary)
    }

    func testSingularPitchReadsCorrectly() {
        var subject = team()
        subject.pitchingConfig.weeklyLimitEnabled = true
        subject.pitchingConfig.weeklyLimit = 51
        let bobby = player()
        subject.players = [bobby]
        subject.gameLogs = [log(bobby, pitches: 50, daysAgo: 6)]

        let answer = PitchEligibilityAnswerBuilder.answer(player: bobby, team: subject)

        XCTAssertTrue(answer.spokenSummary.contains("only 1 more pitch —"), answer.spokenSummary)
        XCTAssertFalse(answer.spokenSummary.contains("1 more pitches"), answer.spokenSummary)
    }
}
