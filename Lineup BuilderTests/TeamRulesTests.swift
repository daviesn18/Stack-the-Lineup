import XCTest
@testable import Lineup_Builder

// MARK: - TeamRules Tests
//
// These answers get spoken in Siri's voice, and two of the topics are pitch
// counts and rest days that exist to protect kids' arms. So the failure that
// matters isn't a crash — it's a number that sounds authoritative and isn't
// the coach's. Most of what's pinned here is therefore the *refusal* paths:
// rules switched off, a missing league age, limits never entered. Every one of
// those must come back saying so, and must not contain a number.
//
// The other half pins agreement with what the app enforces. A spoken "everyone
// needs an inning in the infield" while `fairPlayFindings` declines to check
// that rule is worse than no answer at all.

final class TeamRulesTests: XCTestCase {

    // MARK: - Fixtures

    /// A team with every fair-play rule off and pitching disabled, so each test
    /// switches on exactly the rule it's about.
    private func bareTeam(name: String = "Tigers") -> Team {
        var team = Team()
        team.name = name
        team.fairPlayConfig.minimumFieldingInnings = 0
        team.fairPlayConfig.minimumInfieldInnings = 0
        team.fairPlayConfig.minimumOutfieldInnings = 0
        team.fairPlayConfig.noConsecutiveBench = false
        team.fairPlayConfig.equalBenchTime = false
        team.fairPlayConfig.noConsecutivePosition = false
        team.fairPlayConfig.noRepeatPositions = false
        team.fairPlayConfig.catcherToPitcherThreshold = 0
        team.fairPlayConfig.pitcherToCatcherThreshold = 0
        team.pitchingConfig.rulesEnabled = false
        return team
    }

    /// A team with the Little League preset applied and pitching switched on.
    private func pitchingTeam(name: String = "Tigers") -> Team {
        var team = bareTeam(name: name)
        team.pitchingConfig.rulesEnabled = true
        team.pitchingConfig.applyLittleLeaguePreset()
        return team
    }

    private func player(_ first: String, age: Int?) -> Player {
        Player(firstName: first, lastName: "Reyes", number: "7", leagueAge: age)
    }

    /// Any digit anywhere in the spoken answer.
    private func containsDigit(_ text: String) -> Bool {
        text.rangeOfCharacter(from: .decimalDigits) != nil
    }

    // MARK: - Fair play minimums

    func testInfieldMinimumAnswersTheConfiguredNumber() {
        // The question the ticket was written around: "How many innings do I
        // need to play someone in the infield?"
        var team = bareTeam()
        team.fairPlayConfig.minimumInfieldInnings = 2

        let answer = TeamRulesBuilder.answer(topic: .infieldMinimum, team: team)

        XCTAssertEqual(answer.lines.count, 1)
        XCTAssertEqual(answer.lines[0].value, "2 innings")
        XCTAssertTrue(answer.spokenSummary.contains("at least 2 innings in the infield"),
                      answer.spokenSummary)
        XCTAssertNil(answer.caveat)
    }

    func testSingularInningReadsAsOneInning() {
        // "1 innings" in a spoken sentence is the kind of thing a coach notices
        // and stops trusting.
        var team = bareTeam()
        team.fairPlayConfig.minimumInfieldInnings = 1

        let answer = TeamRulesBuilder.answer(topic: .infieldMinimum, team: team)

        XCTAssertEqual(answer.lines[0].value, "1 inning")
        XCTAssertFalse(answer.spokenSummary.contains("1 innings"), answer.spokenSummary)
    }

    func testMinimumOfZeroReportsTheRuleOffRatherThanZeroInnings() {
        // `fairPlayFindings` treats 0 as "rule off" and skips the check
        // entirely. "Everyone needs at least 0 innings" would be a true
        // sentence describing a rule the app does not enforce.
        let team = bareTeam()

        let answer = TeamRulesBuilder.answer(topic: .infieldMinimum, team: team)

        XCTAssertEqual(answer.lines[0].value, "Off")
        XCTAssertFalse(answer.spokenSummary.contains("0"), answer.spokenSummary)
    }

    func testEveryMinimumTopicTracksItsOwnConfigField() {
        // Three near-identical builders is exactly where a copy-paste slip
        // sends the outfield answer to the infield field.
        var team = bareTeam()
        team.fairPlayConfig.minimumFieldingInnings = 4
        team.fairPlayConfig.minimumInfieldInnings = 1
        team.fairPlayConfig.minimumOutfieldInnings = 2

        XCTAssertEqual(TeamRulesBuilder.answer(topic: .fieldingMinimum, team: team).lines[0].value, "4 innings")
        XCTAssertEqual(TeamRulesBuilder.answer(topic: .infieldMinimum, team: team).lines[0].value, "1 inning")
        XCTAssertEqual(TeamRulesBuilder.answer(topic: .outfieldMinimum, team: team).lines[0].value, "2 innings")
    }

    // MARK: - Battery rules

    func testBatteryThresholdOfZeroReportsNoRule() {
        // Matches `playersViolatingCatcherToPitcher`, which returns [] at 0.
        let answer = TeamRulesBuilder.answer(topic: .batteryRules, team: bareTeam())

        XCTAssertEqual(answer.lines.count, 2)
        XCTAssertTrue(answer.lines.allSatisfy { $0.value == "Off" })
        XCTAssertFalse(containsDigit(answer.spokenSummary), answer.spokenSummary)
    }

    func testBatteryThresholdIsSpokenWithItsInningCount() {
        var team = bareTeam()
        team.fairPlayConfig.catcherToPitcherThreshold = 3

        let answer = TeamRulesBuilder.answer(topic: .batteryRules, team: team)

        XCTAssertTrue(answer.spokenSummary.contains("caught 3 innings, they can't pitch"),
                      answer.spokenSummary)
    }

    // MARK: - Overview

    func testOverviewListsOnlyRulesThatAreOn() {
        var team = bareTeam()
        team.fairPlayConfig.minimumFieldingInnings = 4
        team.fairPlayConfig.noConsecutiveBench = true

        let answer = TeamRulesBuilder.answer(topic: .overview, team: team)

        XCTAssertEqual(answer.lines.count, 2)
        XCTAssertEqual(answer.lines.map(\.label), ["Fielding minimum", "Back-to-back bench"])
        // The three off rules must not appear as "Off" rows — a coach asking
        // what their rules are wants the list they coach to.
        XCTAssertFalse(answer.lines.contains { $0.value == "Off" })
    }

    func testOverviewWithNothingOnDefersInsteadOfClaimingRules() {
        let answer = TeamRulesBuilder.answer(topic: .overview, team: bareTeam())

        XCTAssertTrue(answer.lines.isEmpty)
        XCTAssertTrue(answer.isDeferred)
        XCTAssertTrue(answer.spokenSummary.contains("haven't switched on any fair play rules"),
                      answer.spokenSummary)
        XCTAssertTrue(answer.spokenSummary.contains("Tigers"), answer.spokenSummary)
    }

    // MARK: - Pitching disabled
    //
    // The most important refusal in the file. PitchingConfig ships with the
    // Little League preset one method call away, and quoting those numbers to a
    // coach who never switched pitching rules on would be inventing their rules.

    func testPitchLimitWithRulesOffQuotesNoNumbers() {
        var team = bareTeam()
        team.pitchingConfig.applyLittleLeaguePreset()   // seeded but never enabled
        team.players = [player("Bobby", age: 11)]

        let answer = TeamRulesBuilder.answer(topic: .pitchLimit, team: team,
                                             player: team.players[0])

        XCTAssertTrue(answer.lines.isEmpty)
        XCTAssertTrue(answer.isDeferred)
        XCTAssertFalse(containsDigit(answer.spokenSummary), answer.spokenSummary)
        XCTAssertTrue(answer.spokenSummary.contains("turned off"), answer.spokenSummary)
    }

    func testRestDaysWithRulesOffQuotesNoNumbers() {
        var team = bareTeam()
        team.pitchingConfig.applyLittleLeaguePreset()
        team.players = [player("Bobby", age: 11)]

        let answer = TeamRulesBuilder.answer(topic: .restDays, team: team,
                                             player: team.players[0], pitchCount: 33)

        XCTAssertTrue(answer.isDeferred)
        XCTAssertFalse(containsDigit(answer.spokenSummary), answer.spokenSummary)
    }

    // MARK: - Pitch limits

    func testPitchLimitForANamedPlayerUsesTheirAgeBracket() {
        var team = pitchingTeam()
        let bobby = player("Bobby", age: 11)
        team.players = [bobby, player("Sam", age: 9)]

        let answer = TeamRulesBuilder.answer(topic: .pitchLimit, team: team, player: bobby)

        // 11 lands in the 11-12 bracket: 85, not the 9-10 bracket's 75.
        XCTAssertEqual(answer.lines.count, 1)
        XCTAssertEqual(answer.lines[0].value, "85 pitches")
        XCTAssertTrue(answer.spokenSummary.contains("Bobby can throw up to 85 pitches"),
                      answer.spokenSummary)
        XCTAssertNil(answer.caveat)
    }

    func testPitchLimitWithoutAPlayerCoversEveryBracketOnTheRoster() {
        // No player named and no roster-wide default that could be right, so
        // the answer covers what's actually on the roster rather than picking.
        var team = pitchingTeam()
        team.players = [player("Bobby", age: 11), player("Sam", age: 9)]

        let answer = TeamRulesBuilder.answer(topic: .pitchLimit, team: team)

        XCTAssertEqual(answer.lines.map(\.label), ["Ages 9-10", "Ages 11-12"])
        XCTAssertEqual(answer.lines.map(\.value), ["75 pitches", "85 pitches"])
    }

    func testPlayerWithNoLeagueAgeAsksForItInsteadOfGuessing() {
        // The whole roster could be 11, and it would still be a guess.
        var team = pitchingTeam()
        let bobby = player("Bobby", age: nil)
        team.players = [bobby, player("Sam", age: 11)]

        let answer = TeamRulesBuilder.answer(topic: .pitchLimit, team: team, player: bobby)

        XCTAssertTrue(answer.isDeferred)
        XCTAssertFalse(containsDigit(answer.spokenSummary), answer.spokenSummary)
        XCTAssertTrue(answer.spokenSummary.contains("league age for Bobby"), answer.spokenSummary)
    }

    func testRosterWithNoAgesAtAllDefers() {
        var team = pitchingTeam()
        team.players = [player("Bobby", age: nil), player("Sam", age: nil)]

        let answer = TeamRulesBuilder.answer(topic: .pitchLimit, team: team)

        XCTAssertTrue(answer.isDeferred)
        XCTAssertTrue(answer.spokenSummary.contains("league age set"), answer.spokenSummary)
    }

    func testBracketWithNoLimitsEnteredDefers() {
        // Rules on, age known, but this bracket was never filled in.
        var team = bareTeam()
        team.pitchingConfig.rulesEnabled = true
        team.pitchingConfig.ageLimits = [
            .u10: PitchingLimits(dailyMax: 75, restDay1Min: 21, restDay2Min: 36)
        ]
        let bobby = player("Bobby", age: 12)
        team.players = [bobby]

        let answer = TeamRulesBuilder.answer(topic: .pitchLimit, team: team, player: bobby)

        XCTAssertTrue(answer.isDeferred)
        // Must not fall back to the one bracket that does have limits.
        XCTAssertFalse(answer.spokenSummary.contains("75"), answer.spokenSummary)
        XCTAssertTrue(answer.spokenSummary.contains("11 to 12"), answer.spokenSummary)
    }

    func testPartiallyConfiguredRosterAnswersAndSaysWhatsMissing() {
        // Answering only for the configured bracket without flagging the gap
        // would read as a complete answer for the whole roster.
        var team = bareTeam()
        team.pitchingConfig.rulesEnabled = true
        team.pitchingConfig.ageLimits = [
            .u10: PitchingLimits(dailyMax: 75, restDay1Min: 21, restDay2Min: 36)
        ]
        team.players = [player("Sam", age: 9), player("Bobby", age: 12)]

        let answer = TeamRulesBuilder.answer(topic: .pitchLimit, team: team)

        XCTAssertEqual(answer.lines.map(\.label), ["Ages 9-10"])
        XCTAssertNotNil(answer.caveat)
        XCTAssertTrue(answer.caveat?.contains("11 to 12") == true, answer.caveat ?? "")
    }

    func testWeeklyCapIsIncludedOnlyWhenEnabled() {
        var team = pitchingTeam()
        team.players = [player("Bobby", age: 11)]

        XCTAssertEqual(TeamRulesBuilder.answer(topic: .pitchLimit, team: team).lines.count, 1)

        team.pitchingConfig.weeklyLimitEnabled = true
        team.pitchingConfig.weeklyLimit = 100

        let answer = TeamRulesBuilder.answer(topic: .pitchLimit, team: team)
        XCTAssertEqual(answer.lines.count, 2)
        XCTAssertTrue(answer.spokenSummary.contains("100 pitches per rolling 7 days"),
                      answer.spokenSummary)
    }

    // MARK: - Rest days

    func testRestDaysForAPitchCountUsesTheStoredLadder() {
        // The ticket's other worked example. 33 sits between the 11-12
        // bracket's 21 (1 day) and 36 (2 days) thresholds.
        var team = pitchingTeam()
        let bobby = player("Bobby", age: 11)
        team.players = [bobby]

        let answer = TeamRulesBuilder.answer(topic: .restDays, team: team,
                                             player: bobby, pitchCount: 33)

        XCTAssertEqual(answer.lines.count, 1)
        XCTAssertEqual(answer.lines[0].value, "1 day")
        XCTAssertTrue(answer.spokenSummary.contains("At 33 pitches, Bobby needs 1 day of rest"),
                      answer.spokenSummary)
    }

    func testRestDaysMatchesTheEngineAcrossEveryTier() {
        // The answer and the engine that blocks a pitcher assignment must not
        // be able to disagree, so this checks the same ladder both read.
        let team = pitchingTeam()
        let limits = team.pitchingConfig.ageLimits[.u12]!
        let bobby = player("Bobby", age: 11)

        for count in [1, 20, 21, 35, 36, 50, 51, 65, 66, 90] {
            var withPlayer = team
            withPlayer.players = [bobby]
            let answer = TeamRulesBuilder.answer(topic: .restDays, team: withPlayer,
                                                 player: bobby, pitchCount: count)
            let expected = limits.restDaysRequired(for: count)
            let expectedValue = expected == 0 ? "No rest"
                : expected == 1 ? "1 day" : "\(expected) days"
            XCTAssertEqual(answer.lines[0].value, expectedValue,
                           "\(count) pitches should require \(expected) days")
        }
    }

    func testPitchCountOverTheDailyMaxIsCalledOut() {
        var team = pitchingTeam()
        let bobby = player("Bobby", age: 11)
        team.players = [bobby]

        let answer = TeamRulesBuilder.answer(topic: .restDays, team: team,
                                             player: bobby, pitchCount: 90)

        XCTAssertTrue(answer.spokenSummary.contains("over your 85-pitch game limit"),
                      answer.spokenSummary)
    }

    func testRestDaysWithoutAPitchCountGivesTheWholeLadder() {
        // A question asked without a number in it gets the thresholds, not a
        // prompt — the ladder is the honest answer to "what are the rest rules".
        var team = pitchingTeam()
        team.players = [player("Bobby", age: 11)]

        let answer = TeamRulesBuilder.answer(topic: .restDays, team: team)

        XCTAssertEqual(answer.lines.count, 1)
        for threshold in ["21", "36", "51", "66"] {
            XCTAssertTrue(answer.spokenSummary.contains(threshold),
                          "ladder should mention \(threshold): \(answer.spokenSummary)")
        }
    }

    func testIdenticalLaddersCollapseIntoOneRange() {
        // Under the Little League preset every bracket from 9 up shares one
        // ladder, and spelling it out per bracket spoke the same four
        // thresholds three times. Found by listening to it, not by reading it.
        var team = pitchingTeam()
        team.players = [player("Sam", age: 9), player("Bobby", age: 11), player("Max", age: 13)]

        let answer = TeamRulesBuilder.answer(topic: .restDays, team: team)

        XCTAssertEqual(answer.lines.map(\.label), ["Ages 9-14"])
        // The thresholds appear once, not once per bracket.
        XCTAssertEqual(answer.spokenSummary.components(separatedBy: "21 or more").count - 1, 1,
                       answer.spokenSummary)
    }

    func testBracketsWithDifferentAnswersStaySeparate() {
        // The three daily maximums differ, so collapsing here would be wrong.
        var team = pitchingTeam()
        team.players = [player("Sam", age: 9), player("Bobby", age: 11), player("Max", age: 13)]

        let answer = TeamRulesBuilder.answer(topic: .pitchLimit, team: team)

        XCTAssertEqual(answer.lines.map(\.label), ["Ages 9-10", "Ages 11-12", "Ages 13-14"])
    }

    func testOnlyAdjacentBracketsMerge() {
        // 7-8 and 13-14 share a ladder here while 9-10 in between doesn't.
        // Merging them would produce "7 to 14", which would be a lie about 9-10.
        var team = bareTeam()
        team.pitchingConfig.rulesEnabled = true
        team.pitchingConfig.ageLimits = [
            .u8:  PitchingLimits(dailyMax: 50, restDay1Min: 21, restDay2Min: 36),
            .u10: PitchingLimits(dailyMax: 75, restDay1Min: 26, restDay2Min: 41),
            .u14: PitchingLimits(dailyMax: 95, restDay1Min: 21, restDay2Min: 36)
        ]
        team.players = [player("Ash", age: 8), player("Sam", age: 9), player("Max", age: 13)]

        let answer = TeamRulesBuilder.answer(topic: .restDays, team: team)

        XCTAssertEqual(answer.lines.map(\.label), ["Ages 7-8", "Ages 9-10", "Ages 13-14"])
    }

    func testLadderSkipsTiersTheCoachLeftUnset() {
        // The 7-8 bracket has no 3 or 4 rest day tier, and nil there means the
        // tier doesn't apply — not that it triggers at zero pitches.
        var team = bareTeam()
        team.pitchingConfig.rulesEnabled = true
        team.pitchingConfig.applyLittleLeaguePreset()
        team.players = [player("Sam", age: 8)]

        let answer = TeamRulesBuilder.answer(topic: .restDays, team: team)

        XCTAssertEqual(answer.lines[0].value, "21+ → 1d, 36+ → 2d")
        XCTAssertFalse(answer.spokenSummary.contains("3 days of rest"), answer.spokenSummary)
    }

    func testZeroPitchCountFallsBackToTheLadder() {
        // restDaysRequired(for: 0) returns 1 when restDay1Min is 0, which would
        // be a rest day for pitches nobody threw.
        var team = pitchingTeam()
        let bobby = player("Bobby", age: 11)
        team.players = [bobby]

        let answer = TeamRulesBuilder.answer(topic: .restDays, team: team,
                                             player: bobby, pitchCount: 0)

        XCTAssertTrue(answer.lines[0].value.contains("21+"), answer.lines[0].value)
    }

    // MARK: - Speech shape

    func testEverySpokenLineIsAWholeSentence() {
        // App Intents reads `spokenSummary` verbatim. A fragment joined onto
        // the next line's fragment is how a spoken answer turns to mush.
        var team = pitchingTeam()
        team.fairPlayConfig.minimumFieldingInnings = 4
        team.fairPlayConfig.minimumInfieldInnings = 1
        team.fairPlayConfig.catcherToPitcherThreshold = 3
        team.players = [player("Bobby", age: 11)]

        for topic in RuleTopic.allCases {
            let answer = TeamRulesBuilder.answer(topic: topic, team: team, pitchCount: 33)
            XCTAssertFalse(answer.spokenSummary.isEmpty, "\(topic) spoke nothing")
            for line in answer.lines {
                XCTAssertTrue(line.spoken.hasSuffix(".") || line.spoken.hasSuffix("!"),
                              "\(topic) line '\(line.label)' isn't a sentence: \(line.spoken)")
                XCTAssertFalse(line.value.isEmpty, "\(topic) line '\(line.label)' has no value")
            }
        }
    }

    func testShortSummaryNamesTheAnswerWithoutRestatingIt() {
        // What Spotlight shows above the table. Repeating the values there
        // prints every number twice and buries the table under a paragraph.
        var team = pitchingTeam()
        team.players = [player("Sam", age: 9), player("Bobby", age: 11)]

        let answer = TeamRulesBuilder.answer(topic: .pitchLimit, team: team)

        XCTAssertEqual(answer.shortSummary, "Your pitch limits for Tigers.")
        XCTAssertFalse(containsDigit(answer.shortSummary), answer.shortSummary)
        // The full answer still carries everything, for a voice-only surface
        // where there is no table to read.
        XCTAssertTrue(answer.spokenSummary.contains("75"), answer.spokenSummary)
    }

    func testShortSummaryCarriesTheCaveatWhenThereIsNoTable() {
        // Nothing to render, so the short line has to be the whole answer.
        let answer = TeamRulesBuilder.answer(topic: .pitchLimit, team: bareTeam())

        XCTAssertEqual(answer.shortSummary, answer.spokenSummary)
        XCTAssertTrue(answer.shortSummary.contains("turned off"), answer.shortSummary)
    }

    func testEveryTopicHasAShortSummary() {
        var team = pitchingTeam()
        team.fairPlayConfig.minimumFieldingInnings = 4
        team.players = [player("Bobby", age: 11)]

        for topic in RuleTopic.allCases {
            let answer = TeamRulesBuilder.answer(topic: topic, team: team)
            XCTAssertFalse(answer.shortSummary.isEmpty, "\(topic) has no short summary")
            XCTAssertTrue(answer.shortSummary.hasSuffix("."), "\(topic): \(answer.shortSummary)")
        }
    }

    func testAgeBracketsAreSpokenAsRangesNotHyphens() {
        // "11-12" gets read as a subtraction or a hyphen by speech synthesis.
        XCTAssertEqual(PitchingAgeBracket.u12.spokenRange, "11 to 12")
        XCTAssertEqual(PitchingAgeBracket.u8.spokenRange, "7 to 8")
    }

    func testUnnamedTeamNeverSpeaksAnEmptyName() {
        var team = bareTeam(name: "")
        team.pitchingConfig.rulesEnabled = false

        let answer = TeamRulesBuilder.answer(topic: .pitchLimit, team: team)

        XCTAssertTrue(answer.spokenSummary.contains("your team"), answer.spokenSummary)
        XCTAssertFalse(answer.spokenSummary.contains("for , "), answer.spokenSummary)
    }

    // MARK: - AppEnum bridge

    func testEveryRuleTopicRoundTripsThroughItsAppEnum() {
        // The exhaustive switches are what make adding a topic a build failure
        // rather than a case Siri silently can't reach.
        for topic in RuleTopic.allCases {
            XCTAssertEqual(RuleTopicAppEnum(topic).topic, topic)
        }
        XCTAssertEqual(RuleTopicAppEnum.allCases.count, RuleTopic.allCases.count)
    }

    func testEveryAppEnumCaseHasADisplayRepresentation() {
        // A case missing from the dictionary is unaddressable by voice and
        // shows up blank in the Shortcuts picker.
        for value in RuleTopicAppEnum.allCases {
            XCTAssertNotNil(RuleTopicAppEnum.caseDisplayRepresentations[value],
                            "\(value) has no display representation")
        }
    }
}
