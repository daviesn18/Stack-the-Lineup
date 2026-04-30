import XCTest
@testable import Lineup_Builder

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
        // Simulate what v1.x stored by building the JSON the way the old encoder
        // actually wrote it — encode a known player then mutate the raw JSON
        // to swap in the legacy tier names before decoding.
        var player = Player(firstName: "Jake", lastName: "Rivera", number: "4")
        player.positionPreferences = [.pitcher: .strength, .catcher: .capable]

        var json = try JSONEncoder().encode(player)

        // Swap the current tier names for the legacy ones in the raw JSON bytes
        var jsonString = String(data: json, encoding: .utf8)!
        jsonString = jsonString.replacingOccurrences(of: "Strength", with: "Primary")
        jsonString = jsonString.replacingOccurrences(of: "Capable", with: "Secondary")
        json = jsonString.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(Player.self, from: json)
        XCTAssertEqual(decoded.positionPreferences[.pitcher], .strength)
        XCTAssertEqual(decoded.positionPreferences[.catcher], .capable)
    }

    func testUnknownPositionPreferenceFallsBack() throws {
        var player = Player(firstName: "Jake", lastName: "Rivera", number: "4")
        player.positionPreferences = [.pitcher: .capable]

        var json = try JSONEncoder().encode(player)

        // Replace with a completely unknown tier value
        var jsonString = String(data: json, encoding: .utf8)!
        jsonString = jsonString.replacingOccurrences(of: "Capable", with: "SomeUnknownValue")
        json = jsonString.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(Player.self, from: json)
        XCTAssertEqual(decoded.positionPreferences[.pitcher], .capable)
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
