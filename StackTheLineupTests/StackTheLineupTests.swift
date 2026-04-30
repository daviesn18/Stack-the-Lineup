import XCTest
@testable import LineupBuilder // replace with your actual module name

final class LineupDecodeTests: XCTestCase {

    // MARK: - Lineup Decode

    /// Old data without a `status` field should decode cleanly and default to .draft
    func testLineupDecodesWithoutStatusField() throws {
        let json = """
        {
            "gameDate": 0,
            "opponent": "Test Opponent",
            "battingOrder": [],
            "innings": [],
            "absentPlayerIDs": []
        }
        """.data(using: .utf8)!

        let lineup = try JSONDecoder().decode(Lineup.self, from: json)
        XCTAssertEqual(lineup.opponent, "Test Opponent")
        XCTAssertEqual(lineup.status, .draft)
    }

    /// A fully populated Lineup with status should round-trip cleanly
    func testLineupRoundTrip() throws {
        var lineup = Lineup()
        lineup.opponent = "Giants"
        lineup.status = .finalized

        let data = try JSONEncoder().encode(lineup)
        let decoded = try JSONDecoder().decode(Lineup.self, from: data)

        XCTAssertEqual(decoded.opponent, "Giants")
        XCTAssertEqual(decoded.status, .finalized)
    }

    // MARK: - Team Decode

    /// A team with old-format lineup (no status) should decode without throwing
    func testTeamDecodesWithOldLineupFormat() throws {
        let json = """
        [{
            "id": "00000000-0000-0000-0000-000000000001",
            "name": "Red Sox",
            "colorHex": "FF0000",
            "createdAt": 0,
            "players": [],
            "gameLogs": [],
            "lineup": {
                "gameDate": 0,
                "opponent": "Yankees",
                "battingOrder": [],
                "innings": [],
                "absentPlayerIDs": []
            }
        }]
        """.data(using: .utf8)!

        let teams = try JSONDecoder().decode([Team].self, from: json)
        XCTAssertEqual(teams.count, 1)
        XCTAssertEqual(teams[0].name, "Red Sox")
        XCTAssertEqual(teams[0].lineup.opponent, "Yankees")
        XCTAssertEqual(teams[0].lineup.status, .draft)
    }

    /// Corrupt data should fail to decode — confirming our guard in applyStoredData works
    func testCorruptDataFailsGracefully() {
        let garbage = "this is not json".data(using: .utf8)!
        let result = try? JSONDecoder().decode([Team].self, from: garbage)
        XCTAssertNil(result, "Corrupt data should return nil, not crash")
    }

    // MARK: - Player Decode

    /// Legacy position preference values (Primary/Secondary) should map forward
    func testLegacyPositionPreferenceDecodes() throws {
        let json = """
        {
            "id": "00000000-0000-0000-0000-000000000001",
            "firstName": "Jake",
            "lastName": "Rivera",
            "number": "4",
            "positionPreferences": { "P": "Primary", "C": "Secondary" }
        }
        """.data(using: .utf8)!

        let player = try JSONDecoder().decode(Player.self, from: json)
        XCTAssertEqual(player.positionPreferences[.pitcher], .strength)
        XCTAssertEqual(player.positionPreferences[.catcher], .capable)
    }

    /// Unknown position preference values should fall back to .capable, not crash
    func testUnknownPositionPreferenceFallsBack() throws {
        let json = """
        {
            "id": "00000000-0000-0000-0000-000000000001",
            "firstName": "Jake",
            "lastName": "Rivera",
            "number": "4",
            "positionPreferences": { "P": "SomeUnknownValue" }
        }
        """.data(using: .utf8)!

        let player = try JSONDecoder().decode(Player.self, from: json)
        XCTAssertEqual(player.positionPreferences[.pitcher], .capable)
    }

    /// Missing positionPreferences key entirely should produce empty dict, not crash
    func testMissingPositionPreferencesDecodesAsEmpty() throws {
        let json = """
        {
            "id": "00000000-0000-0000-0000-000000000001",
            "firstName": "Jake",
            "lastName": "Rivera",
            "number": "4"
        }
        """.data(using: .utf8)!

        let player = try JSONDecoder().decode(Player.self, from: json)
        XCTAssertTrue(player.positionPreferences.isEmpty)
    }
}
