//
//  SupabaseRows.swift
//  Lineup Builder
//
//  Merge 0b: the Supabase row shapes for one team, as plain values.
//
//  A team in the coach's account is held twice on the device: as the `Team`
//  the app edits, and as the `TeamRows` the server last confirmed (the "base").
//  Sync compares rows, never Teams, so these types are the vocabulary of the
//  whole save queue: `TeamRowMapper` turns a Team into rows and back,
//  `TeamRowsDiff` says what to send, and `TeamRowsMerge` folds in what another
//  device changed.
//
//  Rules (shared with the web, see web/supabase/migrations):
//    * IDs are the iOS UUIDs. Swift encodes them upper-case; Postgres hands them
//      back lower-case. `UUID` compares by value, so case never matters here,
//      and string keys (pitch counts, jsonb) are normalised to upper-case.
//    * Timestamps are rounded to whole milliseconds everywhere, so a value that
//      went to Postgres (microseconds) and came back compares equal.
//    * Server-managed columns (owner_id, created_at on children, updated_at,
//      deleted_at) are not modelled. Deleted rows are filtered out on fetch.
//
//  Everything here is `nonisolated` and pure, so the unit test target (which is
//  not MainActor-by-default) and the background sync actor can both use it.
//

import Foundation

// MARK: - JSON value

/// A JSON value, for the jsonb columns (fair play and pitching config, game-log
/// innings and snapshots). Kept local rather than using Supabase's `AnyJSON` so
/// the pure layer and its tests don't depend on the SDK.
nonisolated enum JSONValue: Codable, Hashable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Int.self) { self = .int(v) }
        else if let v = try? c.decode(Double.self) { self = .double(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }

    var objectValue: [String: JSONValue]? {
        if case .object(let o) = self { return o }
        return nil
    }

    var arrayValue: [JSONValue]? {
        if case .array(let a) = self { return a }
        return nil
    }

    /// The value Swift's own encoder produces for `value`.
    static func encoding<T: Encodable>(_ value: T) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
    }

    /// Decodes this value as `T` with Swift's own decoder.
    func decoded<T: Decodable>(as type: T.Type) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONEncoder().encode(self))
    }
}

// MARK: - Helpers

nonisolated extension Date {
    /// This date rounded to whole milliseconds: what survives a trip through
    /// Postgres and JavaScript unchanged.
    var roundedToMilliseconds: Date {
        Date(timeIntervalSince1970: (timeIntervalSince1970 * 1000).rounded() / 1000)
    }
}

/// ISO 8601 with milliseconds, the form every timestamp is sent in.
nonisolated enum RowTimestamp {
    static func string(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date.roundedToMilliseconds)
    }
}

nonisolated extension Dictionary where Key == String {
    /// The same dictionary with UUID-shaped keys upper-cased.
    func upperCasingUUIDKeys() -> [String: Value] {
        Dictionary(map { (UUID(uuidString: $0.key)?.uuidString ?? $0.key, $0.value) },
                   uniquingKeysWith: { first, _ in first })
    }
}

// MARK: - Rows

nonisolated struct TeamRecord: Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var colorHex: String
    var coachName: String
    var gameInningCount: Int
    var fairPlayConfig: JSONValue
    var pitchingConfig: JSONValue
    var calendarSubscriptionURL: String?
    var defaultTemplateID: UUID?
    var currentLineupID: UUID?
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name
        case colorHex = "color_hex"
        case coachName = "coach_name"
        case gameInningCount = "game_inning_count"
        case fairPlayConfig = "fair_play_config"
        case pitchingConfig = "pitching_config"
        case calendarSubscriptionURL = "calendar_subscription_url"
        case defaultTemplateID = "default_template_id"
        case currentLineupID = "current_lineup_id"
        case createdAt = "created_at"
    }
}

nonisolated struct PlayerRecord: Codable, Hashable, Sendable {
    var id: UUID
    var teamID: UUID
    var firstName: String
    var lastName: String
    var number: String
    var leagueAge: Int?
    /// {"SS": "Strength"}: a normal object, not Swift's flat [key, value] array.
    var positionPreferences: [String: String]
    var hittingStyle: String?
    var speed: String?
    var onBase: String?
    var rosterOrder: Int

    enum CodingKeys: String, CodingKey {
        case id, number, speed
        case teamID = "team_id"
        case firstName = "first_name"
        case lastName = "last_name"
        case leagueAge = "league_age"
        case positionPreferences = "position_preferences"
        case hittingStyle = "hitting_style"
        case onBase = "on_base"
        case rosterOrder = "roster_order"
    }
}

nonisolated struct ScheduledGameRecord: Codable, Hashable, Sendable {
    var id: UUID
    var teamID: UUID
    var icalUID: String
    var startsAt: Date
    var opponent: String?
    var location: String?
    var rawSummary: String
    var isCancelled: Bool
    var lastSyncedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, opponent, location
        case teamID = "team_id"
        case icalUID = "ical_uid"
        case startsAt = "starts_at"
        case rawSummary = "raw_summary"
        case isCancelled = "is_cancelled"
        case lastSyncedAt = "last_synced_at"
    }
}

nonisolated struct TemplateRecord: Codable, Hashable, Sendable {
    var id: UUID
    var teamID: UUID
    var name: String
    var battingOrder: [UUID]
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name
        case teamID = "team_id"
        case battingOrder = "batting_order"
        case createdAt = "created_at"
    }
}

nonisolated struct TemplateLockRecord: Codable, Hashable, Sendable {
    var id: UUID
    var templateID: UUID
    var teamID: UUID
    var playerID: UUID
    var position: String
    var firstInning: Int
    var lastInning: Int

    enum CodingKeys: String, CodingKey {
        case id, position
        case templateID = "template_id"
        case teamID = "team_id"
        case playerID = "player_id"
        case firstInning = "first_inning"
        case lastInning = "last_inning"
    }
}

nonisolated struct LineupRecord: Codable, Hashable, Sendable {
    var id: UUID
    var teamID: UUID
    var scheduledGameID: UUID?
    var gameDate: Date
    var opponent: String
    var inningCount: Int
    var battingOrder: [UUID]
    /// A set on iOS; order carries no meaning, so it is compared as one.
    var absentPlayerIDs: Set<UUID>
    var status: String
    var lastFinalizedBy: String?
    var lastFinalizedAt: Date?
    var defaultTemplateID: UUID?

    enum CodingKeys: String, CodingKey {
        case id, opponent, status
        case teamID = "team_id"
        case scheduledGameID = "scheduled_game_id"
        case gameDate = "game_date"
        case inningCount = "inning_count"
        case battingOrder = "batting_order"
        case absentPlayerIDs = "absent_player_ids"
        case lastFinalizedBy = "last_finalized_by"
        case lastFinalizedAt = "last_finalized_at"
        case defaultTemplateID = "default_template_id"
    }
}

/// One entry of game_logs.player_snapshot, in the web's shape (upper-case id).
nonisolated struct SnapshotEntry: Codable, Hashable, Sendable {
    var id: String
    var firstName: String
    var lastName: String
    var number: String
}

nonisolated struct GameLogRecord: Codable, Hashable, Sendable {
    var id: UUID
    var teamID: UUID
    var gameDate: Date
    var opponent: String
    var inningsPlayed: Int
    var battingOrder: [UUID]
    /// One object per inning, upper-case player id to position raw value.
    var innings: [[String: String]]
    var playerSnapshot: [SnapshotEntry]
    var archivedAt: Date
    var archivedBy: String
    var notes: String

    enum CodingKeys: String, CodingKey {
        case id, opponent, innings, notes
        case teamID = "team_id"
        case gameDate = "game_date"
        case inningsPlayed = "innings_played"
        case battingOrder = "batting_order"
        case playerSnapshot = "player_snapshot"
        case archivedAt = "archived_at"
        case archivedBy = "archived_by"
    }
}

// MARK: - One team's rows

/// Every row of one team, keyed by id, plus the two child sets that have no id
/// of their own: lineup cells (per lineup, per inning) and pitch counts (per
/// game log). Equatable, so "did anything change" is `==`.
nonisolated struct TeamRows: Codable, Hashable, Sendable {
    /// Player id → position raw value, for one inning.
    typealias Inning = [UUID: String]

    var team: TeamRecord
    var players: [UUID: PlayerRecord] = [:]
    var scheduledGames: [UUID: ScheduledGameRecord] = [:]
    var templates: [UUID: TemplateRecord] = [:]
    var locks: [UUID: TemplateLockRecord] = [:]
    var lineups: [UUID: LineupRecord] = [:]
    /// lineup id → inning index → cells. An inning with no cells is absent.
    var cells: [UUID: [Int: Inning]] = [:]
    var gameLogs: [UUID: GameLogRecord] = [:]
    /// game log id → upper-case player id → pitches. A log with none is absent.
    var pitchCounts: [UUID: [String: Int]] = [:]

    var teamID: UUID { team.id }

    /// The same rows with every timestamp at millisecond precision and every
    /// empty child set removed. Rows decoded from the server go through this
    /// before they are compared with rows built from a Team.
    func normalized() -> TeamRows {
        var r = self
        r.team.createdAt = r.team.createdAt.roundedToMilliseconds
        r.scheduledGames = r.scheduledGames.mapValues {
            var g = $0
            g.startsAt = g.startsAt.roundedToMilliseconds
            g.lastSyncedAt = g.lastSyncedAt?.roundedToMilliseconds
            return g
        }
        r.templates = r.templates.mapValues {
            var t = $0
            t.createdAt = t.createdAt.roundedToMilliseconds
            return t
        }
        r.lineups = r.lineups.mapValues {
            var l = $0
            l.gameDate = l.gameDate.roundedToMilliseconds
            l.lastFinalizedAt = l.lastFinalizedAt?.roundedToMilliseconds
            return l
        }
        r.gameLogs = r.gameLogs.mapValues {
            var g = $0
            g.gameDate = g.gameDate.roundedToMilliseconds
            g.archivedAt = g.archivedAt.roundedToMilliseconds
            g.innings = g.innings.map { $0.upperCasingUUIDKeys() }
            g.playerSnapshot = g.playerSnapshot.map {
                var s = $0
                s.id = UUID(uuidString: s.id)?.uuidString ?? s.id
                return s
            }
            return g
        }
        r.cells = r.cells
            .mapValues { $0.filter { !$0.value.isEmpty } }
            .filter { !$0.value.isEmpty }
        r.pitchCounts = r.pitchCounts
            .mapValues { $0.upperCasingUUIDKeys() }
            .filter { !$0.value.isEmpty }
        return r
    }
}
