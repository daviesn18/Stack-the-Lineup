import XCTest
@testable import Lineup_Builder

// MARK: - GameRecap Tests
//
// The recap is spoken aloud and repeated to parents, so the failure mode that
// matters isn't a crash — it's a confidently wrong number. These tests pin the
// counting (only innings actually played, pitch counts that were never recorded
// staying absent rather than becoming zero) and the roster the recap describes.
//
// FairPlayFindings is covered here too, because the recap is its first
// non-view caller and the reason it was extracted.

final class GameRecapTests: XCTestCase {

    // MARK: - Fixtures

    private func makePlayer(_ first: String, _ last: String, number: String = "0") -> Player {
        Player(firstName: first, lastName: last, number: number)
    }

    /// Seven innings, `assignments` applied to the first `filled.count`.
    private func innings(_ filled: [[UUID: FieldPosition]]) -> [InningAssignment] {
        var result = Array(repeating: InningAssignment(), count: 7)
        for (index, assignments) in filled.enumerated() where index < result.count {
            result[index] = InningAssignment(assignments: assignments)
        }
        return result
    }

    private func makeLog(
        gameDate: Date = Date(),
        opponent: String = "Rangers",
        inningsPlayed: Int,
        players: [Player],
        innings: [InningAssignment],
        pitchCounts: [String: Int] = [:]
    ) -> GameLog {
        GameLog(
            gameDate: gameDate,
            opponent: opponent,
            inningsPlayed: inningsPlayed,
            battingOrder: players.map(\.id),
            innings: innings,
            playerSnapshot: players.map { PlayerSnapshot(from: $0) },
            pitchCounts: pitchCounts
        )
    }

    /// A team with every fair-play rule switched off, so a test can turn on
    /// exactly the one it's about.
    private func teamWithNoRules(name: String = "Tigers") -> Team {
        var team = Team()
        team.name = name
        team.fairPlayConfig.minimumFieldingInnings = 0
        team.fairPlayConfig.minimumInfieldInnings = 0
        team.fairPlayConfig.minimumOutfieldInnings = 0
        team.fairPlayConfig.noConsecutiveBench = false
        team.fairPlayConfig.catcherToPitcherThreshold = 0
        team.fairPlayConfig.pitcherToCatcherThreshold = 0
        return team
    }

    // MARK: - Pitching

    func testPitchingCountsOnlyTheInningsActuallyPlayed() {
        // The archive always stores 7 innings. A game called after 4 leaves
        // planned assignments sitting in innings 5–7; counting them would
        // credit a pitcher with innings nobody played.
        let jake = makePlayer("Jake", "Rivera")
        let log = makeLog(
            inningsPlayed: 4,
            players: [jake],
            innings: innings([
                [jake.id: .pitcher],
                [jake.id: .pitcher],
                [jake.id: .firstBase],
                [jake.id: .firstBase],
                [jake.id: .pitcher],   // planned, never played
                [jake.id: .pitcher],   // planned, never played
            ])
        )

        let lines = GameRecapBuilder.pitchingLines(log: log, players: [jake.id: jake])
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].innings, 2, "Innings 5 and 6 were never played")
    }

    func testPitchersAreListedInTheOrderTheyTookTheMound() {
        let jake = makePlayer("Jake", "Rivera")
        let nate = makePlayer("Nate", "Coleman")
        let log = makeLog(
            inningsPlayed: 4,
            players: [jake, nate],
            innings: innings([
                [nate.id: .pitcher],
                [nate.id: .pitcher],
                [jake.id: .pitcher],
                [jake.id: .pitcher],
            ])
        )

        let lines = GameRecapBuilder.pitchingLines(
            log: log, players: [jake.id: jake, nate.id: nate]
        )
        XCTAssertEqual(lines.map(\.name), ["Nate Coleman", "Jake Rivera"],
                       "A recap read aloud should follow the order of the game")
    }

    func testAnUnrecordedPitchCountStaysNilRatherThanZero() {
        // pitchCounts is optional per log. "0 pitches" is a claim; "not
        // recorded" is the truth, and the two read very differently to a coach
        // checking a kid against a limit.
        let jake = makePlayer("Jake", "Rivera")
        let nate = makePlayer("Nate", "Coleman")
        let log = makeLog(
            inningsPlayed: 2,
            players: [jake, nate],
            innings: innings([[jake.id: .pitcher], [nate.id: .pitcher]]),
            pitchCounts: [jake.id.uuidString: 34]
        )

        let lines = GameRecapBuilder.pitchingLines(
            log: log, players: [jake.id: jake, nate.id: nate]
        )
        XCTAssertEqual(lines.first(where: { $0.name == "Jake Rivera" })?.pitches, 34)
        XCTAssertNil(lines.first(where: { $0.name == "Nate Coleman" })?.pitches)
    }

    func testPitchingSentenceOmitsPitchesItDoesNotHave() {
        let recap = GameRecap(
            teamName: "Tigers", opponent: "Rangers", gameDate: Date(), inningsPlayed: 4,
            battingOrder: [],
            pitching: [
                RecapPitchingLine(playerID: UUID(), name: "Jake Rivera", innings: 2, pitches: 34),
                RecapPitchingLine(playerID: UUID(), name: "Nate Coleman", innings: 2, pitches: nil),
            ],
            fairPlayIssues: [], fieldingMinimumSkipped: false
        )
        XCTAssertEqual(
            recap.pitchingSentence,
            "Jake Rivera pitched 2 innings on 34 pitches, and Nate Coleman pitched 2 innings."
        )
    }

    // MARK: - Roster identity

    func testTheRecapDescribesWhoPlayed_NotWhoIsOnTheRosterNow() {
        // A coach who has since removed a player still wants to hear that they
        // pitched. This is the opposite of SeasonStatsCalculator, which filters
        // by the live roster on purpose — season totals for someone gone are noise.
        let departed = makePlayer("Owen", "Fischer", number: "5")
        let log = makeLog(
            inningsPlayed: 2,
            players: [departed],
            innings: innings([[departed.id: .pitcher], [departed.id: .pitcher]])
        )

        var team = teamWithNoRules()
        team.players = []   // no longer on the roster

        let recap = GameRecapBuilder.build(log: log, team: team)
        XCTAssertEqual(recap.pitching.map(\.name), ["Owen Fischer"])
        XCTAssertEqual(recap.battingOrder, ["Owen F."])
    }

    // MARK: - Fair play

    func testACleanGameReportsNoIssues() {
        let players = (1...10).map { makePlayer("P\($0)", "Test") }
        var assignments: [UUID: FieldPosition] = [:]
        let positions: [FieldPosition] = [.pitcher, .catcher, .firstBase, .secondBase,
                                          .thirdBase, .shortstop, .leftField, .centerField,
                                          .rightField, .bench]
        for (player, position) in zip(players, positions) {
            assignments[player.id] = position
        }
        let log = makeLog(
            inningsPlayed: 1,
            players: players,
            innings: innings([assignments])
        )

        let recap = GameRecapBuilder.build(log: log, team: teamWithNoRules())
        XCTAssertTrue(recap.isFairPlayClean)
        XCTAssertTrue(recap.spokenSummary.contains("Everyone met your fair play rules."),
                      "Got: \(recap.spokenSummary)")
    }

    func testAShortGameSkipsTheFieldingMinimumInsteadOfFlaggingEveryone() {
        // Rain-shortened game: 2 innings against a 4-inning minimum would put
        // the whole roster "under", which is true and useless.
        let players = (1...3).map { makePlayer("P\($0)", "Test") }
        var team = teamWithNoRules()
        team.fairPlayConfig.minimumFieldingInnings = 4

        var assignments: [UUID: FieldPosition] = [:]
        for (player, position) in zip(players, [FieldPosition.pitcher, .catcher, .firstBase]) {
            assignments[player.id] = position
        }
        let log = makeLog(
            inningsPlayed: 2,
            players: players,
            innings: innings([assignments, assignments])
        )

        let recap = GameRecapBuilder.build(log: log, team: team)
        XCTAssertTrue(recap.fieldingMinimumSkipped)
        XCTAssertTrue(recap.isFairPlayClean, "Nobody should be flagged by a rule we couldn't apply")
        XCTAssertTrue(recap.spokenSummary.contains("too short"), "Got: \(recap.spokenSummary)")
    }

    func testAFullLengthGameStillAppliesTheFieldingMinimum() {
        let played = makePlayer("Cam", "Torres")
        let benched = makePlayer("Leo", "Huang")
        var team = teamWithNoRules()
        team.fairPlayConfig.minimumFieldingInnings = 4

        let onField: [UUID: FieldPosition] = [played.id: .pitcher, benched.id: .bench]
        let log = makeLog(
            inningsPlayed: 4,
            players: [played, benched],
            innings: innings([onField, onField, onField, onField])
        )

        let recap = GameRecapBuilder.build(log: log, team: team)
        XCTAssertFalse(recap.fieldingMinimumSkipped)
        XCTAssertEqual(recap.fairPlayIssues.count, 1)
        XCTAssertEqual(recap.fairPlayIssues[0].names, ["Leo Huang"],
                       "Cam Torres played all four and must not be swept in")
    }

    func testIssueSentencesNamePlayersRatherThanCounting() {
        // "3 fair play issues" is something the coach has to open the app to
        // decode. Spoken output has to be actionable on its own.
        let leo = makePlayer("Leo", "Huang")
        let cam = makePlayer("Cam", "Torres")
        let findings = FairPlayFindings(
            withoutInfield: [leo, cam],
            withoutOutfield: [],
            underFieldingMinimum: [],
            backToBackBench: [leo],
            catcherThenPitcher: [],
            pitcherThenCatcher: [],
            minimumFieldingInnings: 4
        )

        let sentences = GameRecapBuilder.issueSentences(findings).map { $0.sentence() }
        XCTAssertEqual(sentences, [
            "Leo Huang and Cam Torres never played the infield.",
            "Leo Huang sat two innings in a row.",
        ])
    }

    func testASpokenIssueNamesAFewPlayersAndCountsTheRest() {
        // A real 5-inning game flagged six players for one rule. Read aloud,
        // that's a list nobody can hold onto — so the dialog caps and counts,
        // while the snippet (sentence() with no limit) still names everyone.
        let issue = RecapIssue(
            names: ["Jake Rivera", "Tyler Nguyen", "Drew Santos",
                    "Eli Park", "Nate Coleman", "Leo Huang"],
            predicate: "never played the outfield"
        )

        XCTAssertEqual(
            issue.sentence(namingAtMost: 3),
            "Jake Rivera, Tyler Nguyen, Drew Santos, and 3 others never played the outfield."
        )
        XCTAssertTrue(issue.sentence().contains("Leo Huang"),
                      "Uncapped must still name everyone")
    }

    func testTheBattingOrderRendersAsOneNumberedLine() {
        // Snippet views clip at a fixed height instead of scrolling, so ten
        // stacked rows pushed the fair-play verdict off the bottom.
        let recap = GameRecap(
            teamName: "Tigers", opponent: "Eagles", gameDate: Date(), inningsPlayed: 5,
            battingOrder: ["Jake R.", "Connor W.", "Tyler N."],
            pitching: [], fairPlayIssues: [], fieldingMinimumSkipped: false
        )
        XCTAssertEqual(recap.numberedBattingOrder, "1 Jake R. · 2 Connor W. · 3 Tyler N.")
    }

    func testTheSpokenSummaryItselfIsCapped() {
        // Guards the wiring, not just RecapIssue: spokenSummary has to pass the
        // limit through, and the snippet has to not.
        let recap = GameRecap(
            teamName: "Tigers", opponent: "Eagles", gameDate: Date(), inningsPlayed: 5,
            battingOrder: [], pitching: [],
            fairPlayIssues: [
                RecapIssue(names: ["Jake Rivera", "Tyler Nguyen", "Drew Santos",
                                   "Eli Park", "Nate Coleman", "Leo Huang"],
                           predicate: "never played the outfield")
            ],
            fieldingMinimumSkipped: false
        )
        XCTAssertTrue(recap.spokenSummary.contains("and 3 others never played the outfield."),
                      "Got: \(recap.spokenSummary)")
        XCTAssertFalse(recap.spokenSummary.contains("Leo Huang"))
    }

    func testCappingIsSkippedWhenItWouldNotShortenAnything() {
        // Four names capped at three would read "…and 1 other" — one word
        // longer than just saying the name.
        let issue = RecapIssue(names: ["A", "B", "C"], predicate: "sat two innings in a row")
        XCTAssertEqual(issue.sentence(namingAtMost: 3), "A, B, and C sat two innings in a row.")
    }

    func testTwoNamesTakeABareAndButTwoClausesKeepTheComma() {
        // Spoken aloud, a comma is a pause. "Leo Huang, and Cam Torres" puts
        // one in the middle of what should be a single breath.
        XCTAssertEqual(GameRecap.list(of: ["Leo", "Cam"]), "Leo and Cam")
        XCTAssertEqual(GameRecap.list(of: ["Leo", "Cam", "Nate"]), "Leo, Cam, and Nate")
        XCTAssertEqual(GameRecap.list(of: ["Leo"]), "Leo")
        XCTAssertEqual(GameRecap.sentence(joining: ["Leo pitched", "Cam caught"]),
                       "Leo pitched, and Cam caught.")
    }

    // MARK: - FairPlayFindings

    func testRulesSwitchedOffProduceNoFindings() {
        // Every surface used to re-derive this from the config by hand, and the
        // copies disagreed. This is the behaviour they were all supposed to have.
        let benched = makePlayer("Leo", "Huang")
        let onField: [UUID: FieldPosition] = [benched.id: .bench]
        let lineup = Lineup(
            battingOrder: [benched.id],
            innings: innings([onField, onField, onField, onField])
        )

        let findings = lineup.fairPlayFindings(
            players: [benched], config: teamWithNoRules().fairPlayConfig
        )
        XCTAssertTrue(findings.isEmpty)
        XCTAssertTrue(findings.underFieldingMinimum.isEmpty)
        XCTAssertTrue(findings.withoutInfield.isEmpty)
        XCTAssertTrue(findings.backToBackBench.isEmpty)
    }

    func testAPlayerBreakingTwoRulesCountsOnce() {
        // The badges count coaches' worth of work, not violations — one player
        // missing both infield and outfield is one person to go fix.
        let leo = makePlayer("Leo", "Huang")
        var team = teamWithNoRules()
        team.fairPlayConfig.minimumInfieldInnings = 1
        team.fairPlayConfig.minimumOutfieldInnings = 1

        let benchAllGame: [UUID: FieldPosition] = [leo.id: .bench]
        let lineup = Lineup(
            battingOrder: [leo.id],
            innings: innings([benchAllGame, benchAllGame])
        )

        let findings = lineup.fairPlayFindings(players: [leo], config: team.fairPlayConfig)
        XCTAssertEqual(findings.withoutInfield.count, 1)
        XCTAssertEqual(findings.withoutOutfield.count, 1)
        XCTAssertEqual(findings.implicatedPlayerIDs.count, 1)
    }

    // MARK: - Phrasing

    func testClauseJoining() {
        XCTAssertEqual(GameRecap.sentence(joining: []), "")
        XCTAssertEqual(GameRecap.sentence(joining: ["A"]), "A.")
        XCTAssertEqual(GameRecap.sentence(joining: ["A", "B"]), "A, and B.")
        XCTAssertEqual(GameRecap.sentence(joining: ["A", "B", "C"]), "A, B, and C.")
    }

    func testRecentDatesReadTheWayCoachesSayThem() {
        let now = Date()
        XCTAssertEqual(GameRecap.datePhrase(now, relativeTo: now), "today")

        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        XCTAssertEqual(GameRecap.datePhrase(yesterday, relativeTo: now), "yesterday")

        // Older than a week, a weekday name stops being unambiguous.
        let longAgo = Calendar.current.date(byAdding: .day, value: -30, to: now)!
        let phrase = GameRecap.datePhrase(longAgo, relativeTo: now)
        XCTAssertTrue(phrase.contains(","), "Expected a dated phrase, got: \(phrase)")
    }

    func testDateVerbPhraseDoesNotSayOnToday() {
        let now = Date()
        XCTAssertEqual(GameRecap.dateVerbPhrase(now, relativeTo: now), "today")
        let longAgo = Calendar.current.date(byAdding: .day, value: -30, to: now)!
        XCTAssertTrue(GameRecap.dateVerbPhrase(longAgo, relativeTo: now).hasPrefix("on "))
    }

    func testHeadlineSurvivesAGameWithNoOpponentNamed() {
        // Scrimmages routinely get archived with the opponent blank.
        let recap = GameRecap(
            teamName: "Tigers", opponent: "", gameDate: Date(), inningsPlayed: 1,
            battingOrder: [], pitching: [], fairPlayIssues: [], fieldingMinimumSkipped: false
        )
        XCTAssertEqual(recap.headline, "Game · 1 inning · today")
        XCTAssertTrue(recap.spokenSummary.hasPrefix("Your game today went 1 inning."),
                      "Got: \(recap.spokenSummary)")
    }
}
