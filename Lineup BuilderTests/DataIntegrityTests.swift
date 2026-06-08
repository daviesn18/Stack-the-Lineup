import XCTest
@testable import Lineup_Builder

// MARK: - Data Integrity Tests
//
// Covers encode/decode safety for all model types across schema versions.
// Every test here represents a real migration risk — old data must never crash
// or silently corrupt when decoded by a newer build.

@MainActor
final class DataIntegrityTests: XCTestCase {

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

    // MARK: - Lineup v3.0 Fields

    /// Old lineup without lastFinalizedBy or lastFinalizedAt should decode with both nil
    func testLineupDecodesWithoutV30FinalizeFields() throws {
        let json = """
        {
            "gameDate": 0,
            "opponent": "Giants",
            "battingOrder": [],
            "innings": [],
            "absentPlayerIDs": [],
            "status": "finalized"
        }
        """.data(using: .utf8)!

        let lineup = try JSONDecoder().decode(Lineup.self, from: json)
        XCTAssertNil(lineup.lastFinalizedBy,
                     "lastFinalizedBy should be nil for pre-v3.0 lineups")
        XCTAssertNil(lineup.lastFinalizedAt,
                     "lastFinalizedAt should be nil for pre-v3.0 lineups")
    }

    /// A lineup with both v3.0 finalization fields should round-trip cleanly
    func testLineupV30FinalizeFieldsRoundTrip() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        var lineup = Lineup()
        lineup.status = .finalized
        lineup.lastFinalizedBy = "Coach Nick"
        lineup.lastFinalizedAt = date

        let data = try JSONEncoder().encode(lineup)
        let decoded = try JSONDecoder().decode(Lineup.self, from: data)

        XCTAssertEqual(decoded.lastFinalizedBy, "Coach Nick")
        XCTAssertEqual(
            decoded.lastFinalizedAt?.timeIntervalSince1970 ?? 0,
            date.timeIntervalSince1970,
            accuracy: 1.0
        )
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

    /// A team decoded without fairPlayConfig should get default config values
    func testTeamDecodesWithoutFairPlayConfig() throws {
        let json = """
        [{
            "id": "00000000-0000-0000-0000-000000000001",
            "name": "Cubs",
            "colorHex": "0000FF",
            "createdAt": 0,
            "players": [],
            "gameLogs": [],
            "lineup": {
                "gameDate": 0,
                "opponent": "",
                "battingOrder": [],
                "innings": [],
                "absentPlayerIDs": []
            }
        }]
        """.data(using: .utf8)!

        let teams = try JSONDecoder().decode([Team].self, from: json)
        let config = teams[0].fairPlayConfig
        // Defaults must match previously hardcoded behavior
        XCTAssertFalse(config.noPitcher)
        XCTAssertFalse(config.noCatcher)
        XCTAssertEqual(config.outfielderCount, 3)
        XCTAssertTrue(config.noConsecutiveBench)
        XCTAssertFalse(config.equalBenchTime)
        XCTAssertEqual(config.minimumFieldingInnings, 4)
        XCTAssertEqual(config.minimumInfieldInnings, 1)
        XCTAssertEqual(config.minimumOutfieldInnings, 1)
        XCTAssertEqual(config.catcherToPitcherThreshold, 0)
        XCTAssertEqual(config.pitcherToCatcherThreshold, 0)
        XCTAssertEqual(config.leagueRuleset, .custom)
    }

    /// A team with all fairPlayConfig fields should round-trip cleanly
    func testTeamFairPlayConfigRoundTrip() throws {
        var config = FairPlayConfig()
        config.noPitcher = true
        config.outfielderCount = 4
        config.minimumFieldingInnings = 3
        config.catcherToPitcherThreshold = 2
        config.leagueRuleset = .littleLeague

        var team = Team()
        team.fairPlayConfig = config

        let data = try JSONEncoder().encode([team])
        let decoded = try JSONDecoder().decode([Team].self, from: data)
        let decodedConfig = decoded[0].fairPlayConfig

        XCTAssertTrue(decodedConfig.noPitcher)
        XCTAssertEqual(decodedConfig.outfielderCount, 4)
        XCTAssertEqual(decodedConfig.minimumFieldingInnings, 3)
        XCTAssertEqual(decodedConfig.catcherToPitcherThreshold, 2)
        XCTAssertEqual(decodedConfig.leagueRuleset, .littleLeague)
    }

    /// FairPlayConfig with unknown leagueRuleset value should fall back to .custom
    func testFairPlayConfigUnknownLeagueRulesetFallsBack() throws {
        let json = """
        {
            "leagueRuleset": "SomeUnknownLeague"
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(FairPlayConfig.self, from: json)
        XCTAssertEqual(config.leagueRuleset, .custom)
    }

    /// FairPlayConfig decoded with no fields should produce all defaults
    func testFairPlayConfigEmptyJsonProducesDefaults() throws {
        let json = "{}".data(using: .utf8)!
        let config = try JSONDecoder().decode(FairPlayConfig.self, from: json)
        XCTAssertEqual(config.minimumFieldingInnings, 4)
        XCTAssertEqual(config.outfielderCount, 3)
        XCTAssertTrue(config.noConsecutiveBench)
    }

    // MARK: - Team v3.0 CloudKit Fields

    /// Old team JSON without v3.0 fields should decode with safe defaults
    func testTeamDecodesWithoutV30CloudKitFields() throws {
        let json = """
        [{
            "id": "00000000-0000-0000-0000-000000000001",
            "name": "Reds",
            "colorHex": "FF0000",
            "createdAt": 0,
            "players": [],
            "gameLogs": [],
            "lineup": {
                "gameDate": 0,
                "opponent": "",
                "battingOrder": [],
                "innings": [],
                "absentPlayerIDs": []
            }
        }]
        """.data(using: .utf8)!

        let teams = try JSONDecoder().decode([Team].self, from: json)
        XCTAssertEqual(teams[0].coachName, "",
                       "coachName should default to empty string for pre-v3.0 teams")
        XCTAssertNil(teams[0].ckRecordName,
                     "ckRecordName should default to nil for teams not yet in CloudKit")
        XCTAssertFalse(teams[0].isReadOnly,
                       "isReadOnly should default to false")
        XCTAssertFalse(teams[0].isSharedParticipant,
                       "isSharedParticipant should always be false after decode")
    }

    /// v3.0 CloudKit fields should round-trip cleanly
    func testTeamV30CloudKitFieldsRoundTrip() throws {
        var team = Team()
        team.coachName = "Coach Nick"
        team.ckRecordName = "abc123def456"
        team.isReadOnly = false

        let data = try JSONEncoder().encode([team])
        let decoded = try JSONDecoder().decode([Team].self, from: data)

        XCTAssertEqual(decoded[0].coachName, "Coach Nick")
        XCTAssertEqual(decoded[0].ckRecordName, "abc123def456")
        XCTAssertFalse(decoded[0].isReadOnly)
    }

    /// isSharedParticipant is runtime-only. Encoding a team with it true and
    /// decoding must always produce false — it is re-derived from the CloudKit
    /// fetch path, never stored in the JSON blob.
    func testIsSharedParticipantNeverPersistedAcrossRoundTrip() throws {
        var team = Team()
        team.isSharedParticipant = true

        let data = try JSONEncoder().encode([team])
        let decoded = try JSONDecoder().decode([Team].self, from: data)

        XCTAssertFalse(decoded[0].isSharedParticipant,
                       "isSharedParticipant must always be false after decode — it is re-derived at runtime")
    }

    /// A read-only shared team should round-trip isReadOnly = true correctly
    func testReadOnlyTeamRoundTrip() throws {
        var team = Team()
        team.coachName = "Other Coach"
        team.ckRecordName = "shared-record-123"
        team.isReadOnly = true

        let data = try JSONEncoder().encode([team])
        let decoded = try JSONDecoder().decode([Team].self, from: data)

        XCTAssertTrue(decoded[0].isReadOnly)
        XCTAssertEqual(decoded[0].coachName, "Other Coach")
        XCTAssertEqual(decoded[0].ckRecordName, "shared-record-123")
    }

    // MARK: - FieldPosition Decode

    /// New FieldPosition cases LCF and RCF round-trip cleanly
    func testNewOutfieldPositionsRoundTrip() throws {
        let positions: [FieldPosition] = [.leftCenterField, .rightCenterField]
        let data = try JSONEncoder().encode(positions)
        let decoded = try JSONDecoder().decode([FieldPosition].self, from: data)
        XCTAssertEqual(decoded, [.leftCenterField, .rightCenterField])
    }

    /// An unknown FieldPosition raw value should fall back to .bench, not crash
    func testUnknownFieldPositionFallsBackToBench() throws {
        let json = """
        ["LF", "UNKNOWN_POSITION", "RF"]
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode([FieldPosition].self, from: json)
        XCTAssertEqual(decoded[0], .leftField)
        XCTAssertEqual(decoded[1], .bench)
        XCTAssertEqual(decoded[2], .rightField)
    }

    /// LCF and RCF are correctly identified as outfield positions
    func testLCFandRCFAreOutfield() {
        XCTAssertTrue(FieldPosition.leftCenterField.isOutfield)
        XCTAssertTrue(FieldPosition.rightCenterField.isOutfield)
        XCTAssertFalse(FieldPosition.leftCenterField.isInfield)
        XCTAssertFalse(FieldPosition.rightCenterField.isInfield)
    }

    /// LCF and RCF display names are correct
    func testLCFandRCFDisplayNames() {
        XCTAssertEqual(FieldPosition.leftCenterField.displayName, "Left Center")
        XCTAssertEqual(FieldPosition.rightCenterField.displayName, "Right Center")
    }

    // MARK: - Player Decode

    /// Legacy position preference values (Primary/Secondary) should map forward
    func testLegacyPositionPreferenceDecodes() throws {
        var player = Player(firstName: "Jake", lastName: "Rivera", number: "4")
        player.positionPreferences = [.pitcher: .strength, .catcher: .capable]

        var json = try JSONEncoder().encode(player)
        var jsonString = String(data: json, encoding: .utf8)!
        jsonString = jsonString.replacingOccurrences(of: "Strength", with: "Primary")
        jsonString = jsonString.replacingOccurrences(of: "Capable", with: "Secondary")
        json = jsonString.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(Player.self, from: json)
        XCTAssertEqual(decoded.positionPreferences[.pitcher], .strength)
        XCTAssertEqual(decoded.positionPreferences[.catcher], .capable)
    }

    /// Unknown position preference tier falls back to .capable
    func testUnknownPositionPreferenceFallsBack() throws {
        var player = Player(firstName: "Jake", lastName: "Rivera", number: "4")
        player.positionPreferences = [.pitcher: .capable]

        var json = try JSONEncoder().encode(player)
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

    // MARK: - GameLog v3.0 Fields

    /// Old game logs without archivedBy should decode with empty string default
    func testGameLogArchivedByDefaultsToEmptyForOldLogs() throws {
        let json = """
        {
            "id": "00000000-0000-0000-0000-000000000001",
            "gameDate": 0,
            "opponent": "Yankees",
            "inningsPlayed": 6,
            "battingOrder": [],
            "innings": [],
            "playerSnapshot": [],
            "archivedAt": 0
        }
        """.data(using: .utf8)!

        let log = try JSONDecoder().decode(GameLog.self, from: json)
        XCTAssertEqual(log.archivedBy, "",
                       "archivedBy should default to empty string for pre-v3.0 game logs")
    }

    /// archivedBy should round-trip cleanly for logs archived by a named coach
    func testGameLogArchivedByRoundTrip() throws {
        let log = GameLog(
            gameDate: Date(),
            opponent: "Cubs",
            inningsPlayed: 6,
            battingOrder: [],
            innings: Array(repeating: InningAssignment(), count: 7),
            playerSnapshot: [],
            archivedBy: "Coach Nick"
        )

        let data = try JSONEncoder().encode(log)
        let decoded = try JSONDecoder().decode(GameLog.self, from: data)
        XCTAssertEqual(decoded.archivedBy, "Coach Nick")
    }

    /// A game log archived before v3.0 (no archivedBy key) inside a Team decode
    /// should not prevent the team from loading
    func testTeamDecodesWithLegacyGameLogsMissingArchivedBy() throws {
        let json = """
        [{
            "id": "00000000-0000-0000-0000-000000000001",
            "name": "Sox",
            "colorHex": "FF0000",
            "createdAt": 0,
            "players": [],
            "gameLogs": [{
                "id": "00000000-0000-0000-0000-000000000002",
                "gameDate": 0,
                "opponent": "Cubs",
                "inningsPlayed": 6,
                "battingOrder": [],
                "innings": [],
                "playerSnapshot": [],
                "archivedAt": 0
            }],
            "lineup": {
                "gameDate": 0,
                "opponent": "",
                "battingOrder": [],
                "innings": [],
                "absentPlayerIDs": []
            }
        }]
        """.data(using: .utf8)!

        let teams = try JSONDecoder().decode([Team].self, from: json)
        XCTAssertEqual(teams[0].gameLogs.count, 1)
        XCTAssertEqual(teams[0].gameLogs[0].archivedBy, "")
    }

    // MARK: - Corrupt Data

    /// Corrupt data should fail to decode gracefully
    func testCorruptDataFailsGracefully() {
        let garbage = "this is not json".data(using: .utf8)!
        let result = try? JSONDecoder().decode([Team].self, from: garbage)
        XCTAssertNil(result, "Corrupt data should return nil, not crash")
    }
}
