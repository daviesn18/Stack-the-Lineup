import XCTest
@testable import Lineup_Builder

// MARK: - Pitching Summary Tests
//
// Coverage for `PitchEligibilityEngine.coachesGuideSummary` — the pitching
// summary table behind the Coaches Guide and the PDF.
//
// Why this file exists: backlog 3.1 wants `PositionSummaryView.pitchingRows()`
// — a third copy of the pitch-window arithmetic — folded into this function,
// and says tests come first. Nothing covered `coachesGuideSummary` before this,
// so the fold-in had no safety net. This pins the parts a merge would move:
// the window boundaries, the `available` ceiling, the exclusions, and the sort.
//
// `pitchingRows()` itself is `private` inside a SwiftUI `View` and cannot be
// called from a test target. Where the two copies are known to diverge, the
// test for this side carries a DIVERGENCE note saying what the other one does,
// so whoever consolidates knows which behavior they are choosing. The four
// known divergences are: the `.never` filter, the `rulesEnabled` guard,
// `assignedInnings` (view-only), and the last-name tiebreak in the sort.

final class PitchingSummaryTests: XCTestCase {

    // MARK: - Fixtures

    /// Little League preset, rules on. u12 = dailyMax 85, rest tiers 21/36/51/66.
    private func config(
        rulesEnabled: Bool = true,
        weeklyLimit: Int? = nil,
        windowType: RollingWindowType = .rolling
    ) -> PitchingConfig {
        var config = PitchingConfig()
        config.rulesEnabled = rulesEnabled
        config.applyLittleLeaguePreset()
        config.rollingWindowType = windowType
        if let weeklyLimit {
            config.weeklyLimitEnabled = true
            config.weeklyLimit = weeklyLimit
        }
        return config
    }

    private func player(
        _ first: String,
        _ last: String,
        age: Int? = 11,
        pitcher: PositionPreferenceTier = .capable
    ) -> Player {
        Player(firstName: first, lastName: last, number: "7",
               leagueAge: age, positionPreferences: [.pitcher: pitcher])
    }

    /// A log `daysAgo` before `from` where `player` threw `pitches`.
    private func log(_ player: Player, pitches: Int, daysAgo: Int,
                     from now: Date) -> GameLog {
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

    /// A fixed Wednesday, so week-boundary tests don't depend on the run date.
    private let wednesday = Calendar.current.date(
        from: DateComponents(year: 2026, month: 8, day: 5)
    )!

    private func row(
        _ rows: [PitchingGuideSummaryRow]?, _ last: String,
        file: StaticString = #filePath, line: UInt = #line
    ) throws -> PitchingGuideSummaryRow {
        let match = try XCTUnwrap(rows, "expected rows, got nil", file: file, line: line)
            .first { $0.player.lastName == last }
        return try XCTUnwrap(match, "no row for \(last)", file: file, line: line)
    }

    // MARK: - When the table is absent entirely

    func testRulesDisabledReturnsNil() {
        let rows = PitchEligibilityEngine.coachesGuideSummary(
            gameLogs: [], players: [player("Bobby", "Reyes")],
            config: config(rulesEnabled: false), referenceDate: wednesday
        )

        // DIVERGENCE: pitchingRows() has no rulesEnabled guard — the Pitching
        // tab still renders rows with dailyMax resolved from the preset. A
        // fold-in has to keep the table off the PDF when rules are off.
        XCTAssertNil(rows)
    }

    func testEmptyRosterReturnsNil() {
        XCTAssertNil(PitchEligibilityEngine.coachesGuideSummary(
            gameLogs: [], players: [], config: config(), referenceDate: wednesday
        ))
    }

    func testRosterOfOnlyNeverPitchersReturnsNil() {
        let rows = PitchEligibilityEngine.coachesGuideSummary(
            gameLogs: [], players: [player("Bobby", "Reyes", pitcher: .never)],
            config: config(), referenceDate: wednesday
        )

        XCTAssertNil(rows)
    }

    func testNeverPitcherIsExcludedButOthersRemain() throws {
        let bobby = player("Bobby", "Reyes", pitcher: .never)
        let alex = player("Alex", "Ng", pitcher: .strength)

        let rows = try XCTUnwrap(PitchEligibilityEngine.coachesGuideSummary(
            gameLogs: [], players: [bobby, alex],
            config: config(), referenceDate: wednesday
        ))

        // DIVERGENCE: pitchingRows() does not filter .never — a player marked
        // "never pitch" still gets a row on the Pitching tab. The Coaches Guide
        // and the PDF drop them. This is the divergence most likely to surprise
        // a coach comparing the screen against the printout.
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].player.lastName, "Ng")
    }

    // MARK: - Window boundaries
    //
    // The window is half-open: [windowStart, today). Games played *today* are
    // excluded, because today's pitches aren't logged until the game is over.

    func testTodaysPitchesAreNotCountedInTheWindow() throws {
        let bobby = player("Bobby", "Reyes")
        let rows = PitchEligibilityEngine.coachesGuideSummary(
            gameLogs: [log(bobby, pitches: 40, daysAgo: 0, from: wednesday)],
            players: [bobby], config: config(weeklyLimit: 100),
            referenceDate: wednesday
        )

        XCTAssertEqual(try row(rows, "Reyes").pitchesInWindow, 0)
    }

    func testRollingWindowIncludesTheOldestDayInRange() throws {
        // rollingWindowDays = 7 → windowStart = today - 6. Day 6 is the last
        // day inside the window.
        let bobby = player("Bobby", "Reyes")
        let rows = PitchEligibilityEngine.coachesGuideSummary(
            gameLogs: [log(bobby, pitches: 30, daysAgo: 6, from: wednesday)],
            players: [bobby], config: config(weeklyLimit: 100),
            referenceDate: wednesday
        )

        XCTAssertEqual(try row(rows, "Reyes").pitchesInWindow, 30)
    }

    func testRollingWindowExcludesTheDayItAgesOut() throws {
        let bobby = player("Bobby", "Reyes")
        let rows = PitchEligibilityEngine.coachesGuideSummary(
            gameLogs: [log(bobby, pitches: 30, daysAgo: 7, from: wednesday)],
            players: [bobby], config: config(weeklyLimit: 100),
            referenceDate: wednesday
        )

        XCTAssertEqual(try row(rows, "Reyes").pitchesInWindow, 0)
    }

    func testWindowSumsEveryGameInRange() throws {
        let bobby = player("Bobby", "Reyes")
        let rows = PitchEligibilityEngine.coachesGuideSummary(
            gameLogs: [
                log(bobby, pitches: 20, daysAgo: 1, from: wednesday),
                log(bobby, pitches: 15, daysAgo: 4, from: wednesday),
                log(bobby, pitches: 99, daysAgo: 9, from: wednesday) // aged out
            ],
            players: [bobby], config: config(weeklyLimit: 100),
            referenceDate: wednesday
        )

        XCTAssertEqual(try row(rows, "Reyes").pitchesInWindow, 35)
    }

    func testCalendarWeekWindowStartsAtMonday() throws {
        // Reference is Wed 5 Aug 2026. Monday of that week is 3 Aug, so a game
        // 2 days back (Mon) counts and one 3 days back (Sun) does not.
        let bobby = player("Bobby", "Reyes")
        let rows = PitchEligibilityEngine.coachesGuideSummary(
            gameLogs: [
                log(bobby, pitches: 20, daysAgo: 2, from: wednesday),
                log(bobby, pitches: 50, daysAgo: 3, from: wednesday)
            ],
            players: [bobby],
            config: config(weeklyLimit: 100, windowType: .calendarWeek),
            referenceDate: wednesday
        )

        XCTAssertEqual(try row(rows, "Reyes").pitchesInWindow, 20)
    }

    func testCalendarWeekWindowOnSundayStillCountsTheWeek() throws {
        // Sun 9 Aug 2026, with 40 pitches thrown on the Thursday before.
        //
        // KNOWN BUG — see the note at the end of this file. `windowStartDate`
        // reconstructs Monday from the *calendar's* week, and on a US calendar
        // (firstWeekday = Sunday) the week containing Sun 9 Aug runs 9-15 Aug,
        // so weekday=2 resolves to Mon 10 Aug — tomorrow. windowStart lands in
        // the future, the window matches nothing, and the weekly cap silently
        // stops applying for the whole of Sunday.
        //
        // The assertion below is what the app *should* report. XCTExpectFailure
        // keeps the suite green while pinning the intent: fix windowStartDate
        // and this test starts passing (and strict mode then flags it, which is
        // the signal to delete this wrapper).
        let sunday = Calendar.current.date(
            from: DateComponents(year: 2026, month: 8, day: 9)
        )!
        let bobby = player("Bobby", "Reyes")

        XCTExpectFailure("windowStartDate resolves to next Monday on Sundays")

        let rows = PitchEligibilityEngine.coachesGuideSummary(
            gameLogs: [log(bobby, pitches: 40, daysAgo: 3, from: sunday)],
            players: [bobby],
            config: config(weeklyLimit: 100, windowType: .calendarWeek),
            referenceDate: sunday
        )

        XCTAssertEqual(try row(rows, "Reyes").pitchesInWindow, 40)
    }

    // MARK: - dailyMax and the available ceiling

    func testDailyMaxComesFromTheAgeBracket() throws {
        let rows = PitchEligibilityEngine.coachesGuideSummary(
            gameLogs: [], players: [player("Bobby", "Reyes", age: 11)],
            config: config(), referenceDate: wednesday
        )

        XCTAssertEqual(try row(rows, "Reyes").dailyMax, 85) // u12
    }

    func testUnknownAgeGivesZeroDailyMax() throws {
        let rows = PitchEligibilityEngine.coachesGuideSummary(
            gameLogs: [], players: [player("Bobby", "Reyes", age: nil)],
            config: config(), referenceDate: wednesday
        )

        let subject = try row(rows, "Reyes")
        XCTAssertEqual(subject.dailyMax, 0)
        XCTAssertEqual(subject.available, 0)
        XCTAssertEqual(subject.status, .unknownAge)
    }

    func testAgeOutsideEveryBracketGivesZeroDailyMaxButStaysEligible() throws {
        // 17 has no bracket. The engine returns .eligible (nothing to enforce)
        // while the row still shows a 0 ceiling — worth pinning because the two
        // halves disagree in tone and a fold-in could "tidy" one of them.
        let rows = PitchEligibilityEngine.coachesGuideSummary(
            gameLogs: [], players: [player("Bobby", "Reyes", age: 17)],
            config: config(), referenceDate: wednesday
        )

        let subject = try row(rows, "Reyes")
        XCTAssertEqual(subject.dailyMax, 0)
        XCTAssertEqual(subject.status, .eligible)
    }

    func testAvailableIsDailyMaxWhenNoWeeklyLimit() throws {
        let bobby = player("Bobby", "Reyes")
        let rows = PitchEligibilityEngine.coachesGuideSummary(
            gameLogs: [log(bobby, pitches: 60, daysAgo: 2, from: wednesday)],
            players: [bobby], config: config(), referenceDate: wednesday
        )

        // History does not reduce today's ceiling — those pitches were thrown
        // on past days. Only an enabled weekly cap constrains today.
        XCTAssertEqual(try row(rows, "Reyes").available, 85)
    }

    func testAvailableIsCappedByWhatRemainsInTheWeeklyWindow() throws {
        // 70 in the window, but split across two outings of 35. A single 70 at
        // u12 crosses restDay4Min (66) and the rest check short-circuits before
        // the weekly cap is read — that would test rest days, not the cap. 35
        // owes 1 rest day, served by the time the reference date comes around.
        let bobby = player("Bobby", "Reyes")
        let rows = PitchEligibilityEngine.coachesGuideSummary(
            gameLogs: [log(bobby, pitches: 35, daysAgo: 2, from: wednesday),
                       log(bobby, pitches: 35, daysAgo: 3, from: wednesday)],
            players: [bobby], config: config(weeklyLimit: 100),
            referenceDate: wednesday
        )

        let subject = try row(rows, "Reyes")
        XCTAssertEqual(subject.available, 30) // min(85, 100 - 70)
        XCTAssertEqual(subject.status, .limited(remaining: 30))
    }

    func testAvailableNeverGoesNegative() throws {
        let bobby = player("Bobby", "Reyes")
        let rows = PitchEligibilityEngine.coachesGuideSummary(
            gameLogs: [log(bobby, pitches: 130, daysAgo: 2, from: wednesday)],
            players: [bobby], config: config(weeklyLimit: 100),
            referenceDate: wednesday
        )

        XCTAssertEqual(try row(rows, "Reyes").available, 0)
    }

    // MARK: - Rest days

    func testRestDaysComeFromTheMostRecentOuting() throws {
        // 40 pitches at u12 crosses restDay2Min (36) → 2 days owed.
        let bobby = player("Bobby", "Reyes")
        let rows = PitchEligibilityEngine.coachesGuideSummary(
            gameLogs: [log(bobby, pitches: 40, daysAgo: 1, from: wednesday)],
            players: [bobby], config: config(), referenceDate: wednesday
        )

        let subject = try row(rows, "Reyes")
        XCTAssertEqual(subject.restDaysRequired, 2)
        XCTAssertTrue(subject.status.isRestricted)
    }

    func testRestDaysAreZeroWithNoPriorOuting() throws {
        let rows = PitchEligibilityEngine.coachesGuideSummary(
            gameLogs: [], players: [player("Bobby", "Reyes")],
            config: config(), referenceDate: wednesday
        )

        XCTAssertEqual(try row(rows, "Reyes").restDaysRequired, 0)
    }

    func testRestDaysStayPopulatedAfterTheRestHasElapsed() throws {
        // 40 pitches 5 days ago: rest is long since served, so the player is
        // eligible — but restDaysRequired still reports the 2 days that outing
        // demanded. The field is only meaningful next to a restricted status,
        // which is exactly the trap the doc comment warns about.
        let bobby = player("Bobby", "Reyes")
        let rows = PitchEligibilityEngine.coachesGuideSummary(
            gameLogs: [log(bobby, pitches: 40, daysAgo: 5, from: wednesday)],
            players: [bobby], config: config(), referenceDate: wednesday
        )

        let subject = try row(rows, "Reyes")
        XCTAssertEqual(subject.status, .eligible)
        XCTAssertEqual(subject.restDaysRequired, 2)
    }

    // MARK: - Sort order
    //
    // How a coach reads the table: who can throw, most available first,
    // restricted players last.

    func testRestrictedPlayersSortLast() throws {
        let resting = player("Bobby", "Reyes")
        let ready = player("Alex", "Ng")
        let rows = try XCTUnwrap(PitchEligibilityEngine.coachesGuideSummary(
            gameLogs: [log(resting, pitches: 40, daysAgo: 1, from: wednesday)],
            players: [resting, ready], config: config(), referenceDate: wednesday
        ))

        XCTAssertEqual(rows.map(\.player.lastName), ["Ng", "Reyes"])
    }

    func testMostAvailableSortsFirst() throws {
        // Both players are unrestricted, so this exercises the availability
        // comparison rather than falling through to the restricted check: 35
        // pitches owes 1 rest day and it has been served.
        let depleted = player("Bobby", "Reyes")
        let fresh = player("Alex", "Ng")
        let rows = try XCTUnwrap(PitchEligibilityEngine.coachesGuideSummary(
            gameLogs: [log(depleted, pitches: 35, daysAgo: 2, from: wednesday)],
            players: [depleted, fresh], config: config(weeklyLimit: 100),
            referenceDate: wednesday
        ))

        XCTAssertFalse(rows.contains { $0.status.isRestricted })
        XCTAssertEqual(rows.map(\.available), [85, 65])
        XCTAssertEqual(rows.map(\.player.lastName), ["Ng", "Reyes"])
    }

    func testEqualAvailabilityBreaksOnLastName() throws {
        let rows = try XCTUnwrap(PitchEligibilityEngine.coachesGuideSummary(
            gameLogs: [],
            players: [player("Bobby", "Reyes"),
                      player("Alex", "Ng"),
                      player("Casey", "Achterberg")],
            config: config(), referenceDate: wednesday
        ))

        // DIVERGENCE: pitchingRows() sorts on availability with no tiebreak, so
        // equal-availability rows keep roster order and can reshuffle between
        // renders. The stable order here is deliberate — the PDF needs a
        // deterministic page. Keep this behavior when the two are merged.
        XCTAssertEqual(rows.map(\.player.lastName), ["Achterberg", "Ng", "Reyes"])
    }

    // MARK: - Agreement with the engine
    //
    // The summary reports the same status the rest of the app enforces. If a
    // fold-in recomputes status locally instead of delegating, this catches it.

    func testStatusMatchesTheEngineForEveryRow() throws {
        let resting = player("Bobby", "Reyes")
        let limited = player("Alex", "Ng")
        let fresh = player("Casey", "Achterberg")
        let players = [resting, limited, fresh]
        let logs = [
            log(resting, pitches: 40, daysAgo: 1, from: wednesday),
            log(limited, pitches: 70, daysAgo: 3, from: wednesday)
        ]
        let subject = config(weeklyLimit: 100)

        let rows = try XCTUnwrap(PitchEligibilityEngine.coachesGuideSummary(
            gameLogs: logs, players: players, config: subject,
            referenceDate: wednesday
        ))

        for summaryRow in rows {
            let expected = PitchEligibilityEngine.status(
                for: summaryRow.player, gameLogs: logs, config: subject,
                referenceDate: wednesday
            )
            XCTAssertEqual(summaryRow.status, expected,
                           "status drifted for \(summaryRow.player.lastName)")
        }
    }
}

// MARK: - Note: the Sunday window bug
//
// `PitchEligibilityEngine.windowStartDate` derives Monday by taking the
// reference date's `weekOfYear` and setting `weekday = 2`. That assumes the
// calendar's week begins on Monday. On the US default (firstWeekday = Sunday)
// the week containing a Sunday starts *on* that Sunday, so weekday = 2 resolves
// to the following Monday and windowStart lands one day in the future.
//
// Effect, on Sundays only, for teams using Calendar Week:
//   - pitchesInWindow returns 0 regardless of the week's actual games
//   - the weekly cap does not apply, and .limited / .mustRest never trigger
//   - the Coaches Guide and the PDF show a full `available` ceiling
//
// Sunday is a game day in youth baseball, and the same arithmetic is duplicated
// in PositionSummaryView.pitchingRows(), so the tab agrees with the guide and
// nothing looks wrong. The fix is to anchor the week explicitly rather than
// borrow the locale's, e.g. build a Gregorian calendar with firstWeekday = 2
// inside windowStartDate. Deliberately not fixed here: this file is the test
// pass that backlog 3.1 asks for first, and changing enforcement is a separate,
// verifiable change.
