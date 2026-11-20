import XCTest
@testable import Lineup_Builder

// MARK: - TeamRowMapper tests (Merge 0b)
//
// The mapper is the vocabulary of the Supabase save queue: every push and pull
// compares rows built from a Team. So the property that matters most is
// stability: Team → rows → Team → rows must give identical rows, or every sync
// would see a phantom change and push forever. The rest pin the cleanup rules
// shared with web/src/data/teamPayload.ts and the lineup-slot bookkeeping.
//
// The base fixture is the web's sample fall team (a real 3.4.1 export), so the
// two platforms are tested against the same data.

@MainActor
final class TeamRowMapperTests: XCTestCase {

    // MARK: - Fixtures

    private func sampleTeam() throws -> Team {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("web/fixtures/sample-fall-team.stlteam")
        let data = try Data(contentsOf: url)
        guard case .success(let imported) = TeamImporter.parse(data: data) else {
            XCTFail("sample fixture didn't parse"); throw CocoaError(.fileReadCorruptFile)
        }
        return imported.team
    }

    /// The sample team plus what it lacks: a template with locks, a game log
    /// with pitch counts, and a working lineup with cells.
    private func richTeam() throws -> Team {
        var team = try sampleTeam()
        let p = team.players
        team.lineupTemplates = [LineupTemplate(
            name: "Opening day", battingOrder: p.map(\.id),
            positionLocks: [PositionLock(playerID: p[0].id, position: .pitcher, innings: 0...1),
                            PositionLock(playerID: p[1].id, position: .catcher, innings: 2...3)],
            createdAt: Date(timeIntervalSince1970: 1_790_000_000.123_456))]
        var inning = InningAssignment()
        inning.assignments = [p[0].id: .pitcher, p[1].id: .catcher, p[2].id: .bench]
        team.lineup.innings[0] = inning
        team.lineup.battingOrder = p.map(\.id)
        team.gameLogs = [GameLog(
            gameDate: Date(timeIntervalSince1970: 1_790_100_000.5), opponent: "Rays", inningsPlayed: 6,
            battingOrder: p.map(\.id), innings: Array(repeating: inning, count: 7),
            playerSnapshot: p.map(PlayerSnapshot.init(from:)),
            archivedAt: Date(timeIntervalSince1970: 1_790_100_500.25),
            pitchCounts: [p[0].id.uuidString: 42], archivedBy: "Coach", notes: "Good game")]
        return team
    }

    // MARK: - Stability

    func testRoundTripIsStable() throws {
        let team = try richTeam()
        var slots = LineupSlots()
        let first = TeamRowMapper.rows(from: team, slots: &slots).rows

        let (back, backSlots) = TeamRowMapper.team(from: first, local: team)
        var slots2 = backSlots
        let second = TeamRowMapper.rows(from: back, slots: &slots2, base: first).rows

        XCTAssertEqual(first, second, "Team → rows → Team → rows must not change the rows")
        XCTAssertEqual(slots2, backSlots, "a second mapping must reuse every lineup id")
    }

    func testRoundTripKeepsTheTeam() throws {
        let team = try richTeam()
        var slots = LineupSlots()
        let rows = TeamRowMapper.rows(from: team, slots: &slots).rows
        let back = TeamRowMapper.team(from: rows, local: team).team

        XCTAssertEqual(back.id, team.id)
        XCTAssertEqual(back.name, team.name)
        XCTAssertEqual(back.players, team.players)
        XCTAssertEqual(back.scheduledGames.map(\.id), team.scheduledGames.sorted { $0.date < $1.date }.map(\.id))
        XCTAssertEqual(back.lineupTemplates.first?.positionLocks.count, 2)
        XCTAssertEqual(back.gameLogs.first?.pitchCounts, team.gameLogs.first?.pitchCounts)
        XCTAssertEqual(back.gameLogs.first?.notes, "Good game")
        XCTAssertEqual(back.currentGameID, team.currentGameID)
        XCTAssertEqual(back.lineup.innings[0].assignments, team.lineup.innings[0].assignments)
        XCTAssertEqual(back.ckRecordName, team.ckRecordName, "local-only fields come from the local copy")
        XCTAssertEqual(back.updatedAt, team.updatedAt)
        XCTAssertEqual(TeamRowMapper.pitchingJSON(back.pitchingConfig), TeamRowMapper.pitchingJSON(team.pitchingConfig))
        XCTAssertEqual(try JSONValue.encoding(back.fairPlayConfig), try JSONValue.encoding(team.fairPlayConfig))
    }

    func testServerRowsWithLowerCaseIDsAndMicrosecondsCompareEqual() throws {
        let team = try richTeam()
        var slots = LineupSlots()
        let rows = TeamRowMapper.rows(from: team, slots: &slots).rows

        // What Postgres hands back: lower-case UUID strings inside jsonb and
        // pitch counts, and timestamps with sub-millisecond noise.
        var server = rows
        server.gameLogs = server.gameLogs.mapValues {
            var g = $0
            g.innings = g.innings.map { Dictionary(uniqueKeysWithValues: $0.map { ($0.key.lowercased(), $0.value) }) }
            g.playerSnapshot = g.playerSnapshot.map { var s = $0; s.id = s.id.lowercased(); return s }
            g.archivedAt = g.archivedAt.addingTimeInterval(0.000_2)
            return g
        }
        server.pitchCounts = server.pitchCounts.mapValues {
            Dictionary(uniqueKeysWithValues: $0.map { ($0.key.lowercased(), $0.value) })
        }
        server.team.createdAt = server.team.createdAt.addingTimeInterval(0.000_3)

        XCTAssertEqual(server.normalized(), rows)
    }

    // MARK: - Config JSON

    func testPitchingAgeLimitsAreAnObjectInTheDatabase() throws {
        let team = try sampleTeam()
        let json = TeamRowMapper.pitchingJSON(team.pitchingConfig)
        let limits = json.objectValue?["ageLimits"]?.objectValue
        XCTAssertNotNil(limits, "ageLimits must be {bracket: limits}, not Swift's flat array")
        XCTAssertEqual(limits?["7-8"]?.objectValue?["dailyMax"], .int(50))
    }

    func testWebOnlyConfigKeysSurviveAnIOSSave() throws {
        let team = try sampleTeam()
        var slots = LineupSlots()
        var base = TeamRowMapper.rows(from: team, slots: &slots).rows
        guard case .object(var fp) = base.team.fairPlayConfig else { return XCTFail("not an object") }
        fp["pausedRules"] = .object(["noPitcher": .bool(true)])
        base.team.fairPlayConfig = .object(fp)

        let next = TeamRowMapper.rows(from: team, slots: &slots, base: base).rows
        XCTAssertEqual(next.team.fairPlayConfig.objectValue?["pausedRules"], .object(["noPitcher": .bool(true)]))
    }

    // MARK: - Lineups

    func testStaleStashCopyOfTheOpenGameIsIgnored() throws {
        var team = try sampleTeam()
        let game = try XCTUnwrap(team.scheduledGames.first)
        team.currentGameID = game.id
        team.lineup.opponent = "Live copy"
        team.gameLineups[game.id] = Lineup(opponent: "Stale copy")

        var slots = LineupSlots()
        let rows = TeamRowMapper.rows(from: team, slots: &slots).rows
        let forGame = rows.lineups.values.filter { $0.scheduledGameID == game.id }
        XCTAssertEqual(forGame.map(\.opponent), ["Live copy"], "one row per game, from the open lineup")
        XCTAssertEqual(rows.team.currentLineupID, slots.games[game.id])
    }

    func testSwitchingGamesKeepsEachGamesRowID() throws {
        var team = try sampleTeam()
        team.gameLineups = [:]
        let a = team.scheduledGames[0].id, b = team.scheduledGames[1].id
        team.currentGameID = a
        var slots = LineupSlots()
        _ = TeamRowMapper.rows(from: team, slots: &slots)
        let idA = try XCTUnwrap(slots.games[a])

        // What applyScheduledGame does: stash A, open B.
        team.gameLineups[a] = team.lineup
        team.lineup = Lineup(opponent: "B")
        team.currentGameID = b
        let rows = TeamRowMapper.rows(from: team, slots: &slots).rows

        XCTAssertEqual(slots.games[a], idA, "A's lineup is the same row after it's stashed")
        XCTAssertEqual(rows.lineups[idA]?.scheduledGameID, a)
        XCTAssertEqual(rows.team.currentLineupID, slots.games[b])
    }

    func testCellsAreCleanedLikeTheWebImport() throws {
        var team = try sampleTeam()
        team.currentGameID = nil
        team.gameLineups = [:]
        let p = team.players
        var inning = InningAssignment()
        inning.assignments = [p[0].id: .shortstop, p[1].id: .shortstop, UUID(): .pitcher, p[2].id: .bench]
        team.lineup = Lineup(battingOrder: [p[1].id, p[0].id], innings: [inning] + Array(repeating: InningAssignment(), count: 5))

        var slots = LineupSlots()
        let mapped = TeamRowMapper.rows(from: team, slots: &slots)
        let cells = mapped.rows.cells[slots.adhoc]?[0]
        XCTAssertEqual(cells, [p[1].id: "SS", p[2].id: "Bench"],
                       "earlier in the batting order keeps SS; the unknown player is dropped")
        XCTAssertEqual(mapped.notes.count, 2)
    }

    func testBlankLineupTakesTheTeamsGameLength() throws {
        var team = try sampleTeam()
        team.currentGameID = nil
        team.gameLineups = [:]
        team.gameInningCount = 6
        team.lineup = Lineup()   // 7 blank innings, as iOS seeds it
        var slots = LineupSlots()
        let rows = TeamRowMapper.rows(from: team, slots: &slots).rows
        XCTAssertEqual(rows.lineups[slots.adhoc]?.inningCount, 6)
    }

    func testLineupsIOSCantShowAreCarriedFromBase() throws {
        let team = try sampleTeam()
        var slots = LineupSlots()
        var base = TeamRowMapper.rows(from: team, slots: &slots).rows
        let webOnly = UUID()
        base.lineups[webOnly] = LineupRecord(
            id: webOnly, teamID: team.id, scheduledGameID: nil, gameDate: Date().roundedToMilliseconds,
            opponent: "web", inningCount: 6, battingOrder: [], absentPlayerIDs: [], status: "draft",
            lastFinalizedBy: nil, lastFinalizedAt: nil, defaultTemplateID: nil)

        let next = TeamRowMapper.rows(from: team, slots: &slots, base: base).rows
        XCTAssertEqual(next.lineups[webOnly], base.lineups[webOnly])
    }
}
