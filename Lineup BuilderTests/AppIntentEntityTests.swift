import XCTest
@testable import Lineup_Builder

// MARK: - App Intent Entity Tests
//
// Covers the two things Siri and Spotlight depend on that nothing else in the
// app exercises: the FieldPosition <-> AppEnum bridge, and the ranking that turns
// a transcribed string like "number 12" into the player the coach meant.
//
// Deliberately no storage access — PlayerSearch and the entity initializers are
// pure, so these run without touching UserDefaults.

final class AppIntentEntityTests: XCTestCase {

    // MARK: - Helpers

    private func makePlayer(_ first: String, _ last: String, number: String = "",
                            strengths: [FieldPosition] = []) -> Player {
        Player(
            firstName: first,
            lastName: last,
            number: number,
            positionPreferences: Dictionary(uniqueKeysWithValues: strengths.map { ($0, .strength) })
        )
    }

    private func makeTeam(_ name: String, players: [Player] = []) -> Team {
        Team(name: name, players: players)
    }

    private func entity(_ first: String, _ last: String, number: String = "",
                        team: String = "Tigers") -> PlayerEntity {
        PlayerEntity(firstName: first, lastName: last, jerseyNumber: number, teamName: team)
    }

    // MARK: - FieldPosition Bridge
    //
    // The bridge is a hand-written exhaustive switch in both directions. These
    // guard the half the compiler can't: that the switch arms actually pair up,
    // and that every case has something Siri can say.

    func testEveryFieldPositionRoundTripsThroughTheAppEnum() {
        for position in FieldPosition.allCases {
            XCTAssertEqual(
                FieldPositionAppEnum(position).fieldPosition,
                position,
                "\(position.rawValue) did not survive the AppEnum round trip"
            )
        }
    }

    func testEveryAppEnumCaseHasADisplayRepresentation() {
        // A missing entry compiles fine and shows as a blank row in Shortcuts.
        for value in FieldPositionAppEnum.allCases {
            XCTAssertNotNil(
                FieldPositionAppEnum.caseDisplayRepresentations[value],
                "\(value.rawValue) has no display representation"
            )
        }
    }

    func testAppEnumCoversEveryFieldPosition() {
        XCTAssertEqual(
            FieldPositionAppEnum.allCases.count,
            FieldPosition.allCases.count,
            "A position was added to FieldPosition without a spoken equivalent"
        )
    }

    // MARK: - PlayerEntity Construction

    func testEntityCarriesJerseyNumberAndTeamName() {
        let player = makePlayer("Caleb", "Davies", number: "12")
        let team   = makeTeam("Tigers", players: [player])
        let entity = PlayerEntity(player, team: team)

        XCTAssertEqual(entity.id, player.id)
        XCTAssertEqual(entity.name, "Caleb Davies")
        XCTAssertEqual(entity.displayNameWithNumber, "#12 Caleb Davies")
        XCTAssertEqual(entity.teamName, "Tigers")
        XCTAssertEqual(entity.teamID, team.id)
    }

    func testEntityWithoutAJerseyNumberOmitsTheHash() {
        let player = makePlayer("Sam", "Reyes")
        let entity = PlayerEntity(player, team: makeTeam("Tigers"))
        XCTAssertEqual(entity.displayNameWithNumber, "Sam Reyes")
    }

    func testOnlyStrengthPreferencesBecomeKeywords() {
        // Spotlight keywords say what a player is good at. Surfacing a "Never"
        // position as a searchable strength would be actively misleading.
        var player = makePlayer("Caleb", "Davies", strengths: [.pitcher, .shortstop])
        player.positionPreferences[.catcher]   = .never
        player.positionPreferences[.leftField] = .emergency

        let entity = PlayerEntity(player, team: makeTeam("Tigers"))
        let names  = Set(entity.strengths.map(\.displayName))

        XCTAssertEqual(names, ["Pitcher", "Shortstop"])
    }

    // MARK: - Player Search Ranking

    func testExactNameOutranksEveryOtherMatch() {
        let exact  = entity("Sam", "Reyes")
        let prefix = entity("Sammy", "Cole")
        let ranked = PlayerSearch.matches(query: "Sam", in: [prefix, exact])

        XCTAssertEqual(ranked.first?.id, exact.id)
        XCTAssertEqual(ranked.count, 2)
    }

    func testLastNameAloneMatches() {
        let target = entity("Caleb", "Davies")
        let ranked = PlayerSearch.matches(query: "Davies", in: [target, entity("Sam", "Reyes")])
        XCTAssertEqual(ranked.map(\.id), [target.id])
    }

    func testSearchIgnoresCaseAndAccents() {
        let target = entity("José", "Núñez")
        XCTAssertEqual(PlayerSearch.matches(query: "jose", in: [target]).count, 1)
        XCTAssertEqual(PlayerSearch.matches(query: "NUNEZ", in: [target]).count, 1)
    }

    func testJerseyNumberIsFoundThroughEverySpokenForm() {
        // Siri transcribes "number twelve" as "number 12"; Spotlight passes "12";
        // a coach typing uses "#12". All three have to land on the same player.
        let target = entity("Caleb", "Davies", number: "12")
        let other  = entity("Sam", "Reyes", number: "7")

        for query in ["12", "number 12", "#12"] {
            XCTAssertEqual(
                PlayerSearch.matches(query: query, in: [other, target]).first?.id,
                target.id,
                "\"\(query)\" did not resolve to the player wearing 12"
            )
        }
    }

    func testTeamNameMatchesButNeverOutranksAPlayerName() {
        // "Tigers" should list the roster. It must not push a player literally
        // named Tiger below their teammates.
        let named    = PlayerEntity(firstName: "Tiger", lastName: "Woods", teamName: "Cubs")
        let teammate = entity("Sam", "Reyes", team: "Tigers")

        let ranked = PlayerSearch.matches(query: "tigers", in: [teammate, named])
        XCTAssertEqual(ranked.map(\.id), [teammate.id],
            "Only the roster whose name matches should come back for a team query")

        let byName = PlayerSearch.matches(query: "tiger", in: [teammate, named])
        XCTAssertEqual(byName.first?.id, named.id,
            "A player named Tiger must outrank a player merely on the Tigers")
    }

    func testNoMatchReturnsNothingRatherThanEveryone() {
        // Returning the whole roster on a miss would make Siri disambiguate over
        // 14 children instead of admitting it didn't catch the name.
        let ranked = PlayerSearch.matches(query: "Zzzz", in: [entity("Sam", "Reyes")])
        XCTAssertTrue(ranked.isEmpty)
    }

    func testEmptyQueryReturnsTheWholeRosterSortedByName() {
        // Shortcuts' parameter picker sends an empty string for the initial list.
        let reyes  = entity("Sam", "Reyes")
        let davies = entity("Caleb", "Davies")

        let ranked = PlayerSearch.matches(query: "  ", in: [reyes, davies])
        XCTAssertEqual(ranked.map(\.name), ["Caleb Davies", "Sam Reyes"])
    }

    // MARK: - Team Entity

    func testUnnamedTeamFallsBackToThePlaceholderRatherThanABlankRow() {
        XCTAssertEqual(TeamEntity(name: "").displayName, "My Team")
    }

    func testTeamEntityCountsPlayersAndGames() {
        let team = makeTeam("Tigers", players: [makePlayer("Sam", "Reyes"), makePlayer("Caleb", "Davies")])
        let entity = TeamEntity(team)

        XCTAssertEqual(entity.name, "Tigers")
        XCTAssertEqual(entity.playerCount, 2)
        XCTAssertEqual(entity.gameCount, 0)
    }

    func testTeamSearchPrefersExactThenPrefix() {
        let tigers    = TeamEntity(name: "Tigers")
        let tigersFall = TeamEntity(name: "Tigers Fall Ball")

        let ranked = TeamSearch.matches(query: "tigers", in: [tigersFall, tigers])
        XCTAssertEqual(ranked.map(\.id), [tigers.id, tigersFall.id])
    }

    func testTeamSearchReturnsNothingForAMiss() {
        XCTAssertTrue(TeamSearch.matches(query: "Cubs", in: [TeamEntity(name: "Tigers")]).isEmpty)
    }
}
