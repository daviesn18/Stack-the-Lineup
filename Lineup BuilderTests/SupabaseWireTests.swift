import XCTest
@testable import Lineup_Builder

// MARK: - Supabase wire-format tests (Merge 0b)
//
// Two easy-to-miss facts are pinned here. Swift's synthesized encoder leaves a
// nil optional out, and PostgREST keeps the old value of an omitted column, so
// clearing an opponent would never reach the server; payloads must send null.
// And the nested fetch must decode what PostgREST actually returns:
// lower-case ids, microsecond timestamps, children embedded.

final class SupabaseWireTests: XCTestCase {

    func testPayloadSendsNullForNilColumnsAndISODates() throws {
        let game = ScheduledGameRecord(
            id: UUID(), teamID: UUID(), icalUID: "uid-1",
            startsAt: Date(timeIntervalSince1970: 1_790_000_000.123), opponent: nil, location: nil,
            rawSummary: "vs Rays", isCancelled: false, lastSyncedAt: nil)
        let p = try Payload.of(game)
        XCTAssertEqual(p["opponent"], .null)
        XCTAssertEqual(p["last_synced_at"], .null)
        XCTAssertEqual(p["starts_at"], .string("2026-09-21T14:13:20.123Z"))
        XCTAssertEqual(p["ical_uid"], .string("uid-1"))
    }

    func testPayloadOmitsWhatItsTold() throws {
        let team = TeamRecord(
            id: UUID(), name: "Cubs", colorHex: "0000FF", coachName: "", gameInningCount: 6,
            fairPlayConfig: .object([:]), pitchingConfig: .object([:]), calendarSubscriptionURL: nil,
            defaultTemplateID: nil, currentLineupID: UUID(), createdAt: Date())
        let p = try Payload.of(team, omitting: ["current_lineup_id", "default_template_id"])
        XCTAssertNil(p["current_lineup_id"])
        XCTAssertNil(p["default_template_id"])
        XCTAssertEqual(p["calendar_subscription_url"], .null)
    }

    func testNestedFetchDecodes() throws {
        let teamID = "6f1d2c34-1111-4aaa-8bbb-0123456789ab"
        let playerID = "a1b2c3d4-2222-4ccc-8ddd-0123456789ab"
        let lineupID = "b1b2c3d4-3333-4eee-8fff-0123456789ab"
        let logID = "c1b2c3d4-4444-4aaa-8bbb-0123456789ab"
        let json = """
        [{"id":"\(teamID)","owner_id":"\(teamID)","name":"Cubs","color_hex":"0000FF","coach_name":"",
          "game_inning_count":6,"fair_play_config":{"pausedRules":{"noPitcher":true}},"pitching_config":{},
          "calendar_subscription_url":null,"default_template_id":null,"current_lineup_id":"\(lineupID)",
          "created_at":"2026-09-21T13:46:40.123456+00:00","updated_at":"2026-09-21T13:46:40.123456+00:00",
          "deleted_at":null,
          "players":[{"id":"\(playerID)","team_id":"\(teamID)","first_name":"Ava","last_name":"","number":"7",
            "league_age":null,"position_preferences":{"SS":"Strength"},"hitting_style":null,"speed":"Fast",
            "on_base":null,"roster_order":0,"created_at":"2026-09-21T13:46:40+00:00","deleted_at":null}],
          "scheduled_games":[],"lineup_templates":[],
          "lineups":[{"id":"\(lineupID)","team_id":"\(teamID)","scheduled_game_id":null,
            "game_date":"2026-09-21T13:46:40.5+00:00","opponent":"","inning_count":6,
            "batting_order":["\(playerID)"],"absent_player_ids":[],"status":"draft","last_finalized_by":null,
            "last_finalized_at":null,"default_template_id":null,
            "lineup_cells":[{"inning":0,"player_id":"\(playerID)","position":"SS"}]}],
          "game_logs":[{"id":"\(logID)","team_id":"\(teamID)","game_date":"2026-09-20T13:00:00+00:00",
            "opponent":"Rays","innings_played":6,"batting_order":[],"innings":[{"\(playerID)":"SS"}],
            "player_snapshot":[{"id":"\(playerID)","firstName":"Ava","lastName":"","number":"7"}],
            "archived_at":"2026-09-20T15:00:00+00:00","archived_by":"","notes":"",
            "pitch_counts":[{"player_id":"\(playerID)","pitches":42}]}]}]
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { d in
            let s = try d.singleValueContainer().decode(String.self)
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = f.date(from: s) { return date }
            f.formatOptions = [.withInternetDateTime]
            if let date = f.date(from: s) { return date }
            throw DecodingError.dataCorruptedError(in: try d.singleValueContainer(), debugDescription: s)
        }
        let rows = try XCTUnwrap(decoder.decode([ServerTeam].self, from: Data(json.utf8)).first).rows.normalized()

        let pid = try XCTUnwrap(UUID(uuidString: playerID))
        let lid = try XCTUnwrap(UUID(uuidString: lineupID))
        let gid = try XCTUnwrap(UUID(uuidString: logID))
        XCTAssertEqual(rows.players[pid]?.speed, "Fast")
        XCTAssertEqual(rows.cells[lid]?[0], [pid: "SS"])
        XCTAssertEqual(rows.pitchCounts[gid], [pid.uuidString: 42], "pitch-count keys upper-cased")
        XCTAssertEqual(rows.gameLogs[gid]?.innings.first, [pid.uuidString: "SS"])
        XCTAssertEqual(rows.gameLogs[gid]?.playerSnapshot.first?.id, pid.uuidString)
        XCTAssertEqual(rows.team.createdAt.timeIntervalSince1970, 1_789_998_400.123, accuracy: 0.000_01)

        // And the web-only config key survives into a Team and back.
        let (team, slots) = TeamRowMapper.team(from: rows)
        var s = slots
        let again = TeamRowMapper.rows(from: team, slots: &s, base: rows).rows
        XCTAssertEqual(again.team.fairPlayConfig.objectValue?["pausedRules"], .object(["noPitcher": .bool(true)]))
        XCTAssertEqual(again.cells, rows.cells)
    }
}
