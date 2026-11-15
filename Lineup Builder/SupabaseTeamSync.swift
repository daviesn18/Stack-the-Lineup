//
//  SupabaseTeamSync.swift
//  Lineup Builder
//
//  Merge 0b: syncs the signed-in coach's account teams with Supabase.
//
//  One pass, per team:
//    1. Map the device's Team to rows (TeamRowMapper).
//    2. Fetch the server's rows: every account team in one nested query.
//       Teams are small, so a whole-team fetch is cheaper to get right than
//       incremental cursors: it sees hard deletes, and Postgres's now() (the
//       transaction's start, not its commit) can't make it miss a row.
//    3. Merge the two against the base (TeamRowsMerge), rebuild the Team, and
//       map it again so the database's cleanup rules apply to merged data too.
//    4. Push the diff between the server's rows and the result (TeamRowsDiff),
//       in an order the foreign keys and unique indexes accept.
//    5. Only then move the base forward and save sync.json.
//
//  Nothing is ever dropped silently. A network failure keeps everything for
//  the next pass. A refused write (row-level security) marks the team so it
//  isn't retried forever. A write the database rejects as invalid saves a raw
//  backup, keeps the device copy, and waits for the next edit before trying
//  again.
//
//  The actor owns sync.json. It never writes teams.json: merged teams go back
//  to LineupStore, which applies them on the main actor and saves.
//

import Foundation
import os
import Supabase

// MARK: - Outcome

/// What one sync pass hands back to LineupStore.
nonisolated struct TeamSyncOutcome: Sendable {
    /// One merged team, with what's needed to re-apply edits made while the
    /// pass was running (see `LineupStore.applySyncOutcome`).
    struct Merged: Sendable {
        var team: Team
        /// The rows of the Team as it was when the pass started.
        var snapshotRows: TeamRows
        var slots: LineupSlots
    }

    var merged: [Merged] = []
    /// Account teams the server no longer has, untouched here since the last
    /// sync: remove them from the device.
    var removedTeamIDs: Set<UUID> = []
    /// Teams in the account this device didn't have yet.
    var addedTeams: [Team] = []
    var status: AccountSyncStatus
}

/// What Settings and the diagnostics report show.
nonisolated struct AccountSyncStatus: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case upToDate
        case pending(Int)          // teams with changes not yet on the server
        case offline
        case signInNeeded
        case failed(String)        // friendly, name-free
    }
    var state: State = .upToDate
    var lastSyncAt: Date?
    var conflictCount = 0
}

// MARK: - Sync actor

actor SupabaseTeamSync {

    private let store: AccountTeamStore
    private let client: SupabaseClient
    private var file: AccountSyncFile

    init(store: AccountTeamStore, client: SupabaseClient = supabase) {
        self.store = store
        self.client = client
        self.file = store.loadSync()
    }

    /// The persisted state for a team; for tests and diagnostics.
    func state(for id: UUID) -> TeamSyncState? { file.teams[id] }

    /// Records a team deleted on this device. The delete goes out on the next
    /// pass and is retried until the server confirms it.
    func queueDelete(_ id: UUID) {
        file.pendingDeletes.insert(id)
        file.teams[id] = nil
        persist()
    }

    /// Does any team have changes the server doesn't have? Cheap: no network.
    func pendingCount(teams: [Team]) -> Int {
        var n = file.pendingDeletes.count
        for team in teams {
            var slots = file.teams[team.id]?.slots ?? LineupSlots()
            let base = file.teams[team.id]?.base
            let rows = TeamRowMapper.rows(from: team, slots: &slots, base: base).rows
            if base != rows { n += 1 }
        }
        return n
    }

    // MARK: - One pass

    /// Syncs `teams` (the device's account teams) both ways.
    ///
    /// - Parameter excluding: ids the device holds outside the account (the
    ///   CloudKit and device-only teams). A server team with one of these ids is
    ///   not adopted: deciding which copy wins is Merge 1's cutover rule.
    func sync(teams: [Team], excluding: Set<UUID> = []) async -> TeamSyncOutcome {
        var status = AccountSyncStatus(lastSyncAt: nil, conflictCount: file.teams.values.reduce(0) { $0 + $1.conflicts })

        guard (try? await client.auth.session) != nil else {
            status.state = .signInNeeded
            return TeamSyncOutcome(status: status)
        }

        await pushPendingDeletes()

        // 2. Fetch every team this coach can read, in one request.
        let server: [UUID: TeamRows]
        do {
            server = try await fetchAllTeams()
        } catch {
            status.state = Self.isOffline(error) ? .offline : .failed(Self.friendly(error))
            Log.sync.error("Account fetch failed: \(String(describing: error), privacy: .public)")
            return TeamSyncOutcome(status: status)
        }

        var outcome = TeamSyncOutcome(status: status)
        var pending = 0
        var lastFailure: AccountSyncStatus.State?

        for team in teams where !file.pendingDeletes.contains(team.id) {
            var state = file.teams[team.id] ?? TeamSyncState()
            if state.refused { continue }

            var slots = state.slots
            let snapshot = TeamRowMapper.rows(from: team, slots: &slots, base: state.base).rows
            let serverRows = server[team.id]

            // The server has no copy.
            if serverRows == nil, let base = state.base {
                if snapshot == base {
                    // Deleted elsewhere, untouched here: remove it here too.
                    outcome.removedTeamIDs.insert(team.id)
                    file.teams[team.id] = nil
                    continue
                }
                // Deleted elsewhere but edited here: an edit beats a delete,
                // so it's sent again as a new team.
                Log.sync.notice("Team \(team.id, privacy: .public) was deleted on the server but edited here; re-creating it")
                state.base = nil
                state.conflicts += 1
            }

            // 3. Merge.
            var working = snapshot
            var mergedTeam = team
            if let serverRows {
                let base = state.base ?? serverRows
                let merge = TeamRowsMerge.merge(base: base, local: snapshot, server: serverRows)
                if merge.conflicts > 0 {
                    Log.sync.notice("Team \(team.id, privacy: .public): \(merge.conflicts, privacy: .public) conflict(s) settled for this device")
                }
                state.conflicts += merge.conflicts
                var rebuilt = TeamRowMapper.team(from: merge.rows, local: team)
                slots = rebuilt.slots
                rebuilt.team.updatedAt = team.updatedAt
                mergedTeam = rebuilt.team
                working = TeamRowMapper.rows(from: mergedTeam, slots: &slots, base: serverRows).rows
            }
            state.slots = slots

            // 4. Push what the server doesn't have.
            let changes = TeamRowsDiff.changes(from: serverRows, to: working)
            if !changes.isEmpty {
                if state.lastError != nil, state.stuckRows == working {
                    // Rejected before and unchanged since: don't hammer the server.
                    pending += 1
                    file.teams[team.id] = state
                    continue
                }
                do {
                    try await push(changes, rows: working)
                    state.lastPushAt = Date()
                    Log.sync.notice("Pushed team \(team.id, privacy: .public) to the account: \(changes.rowCount, privacy: .public) row(s)")
                } catch {
                    switch Self.classify(error) {
                    case .offline:
                        lastFailure = .offline
                    case .auth:
                        lastFailure = .signInNeeded
                    case .refused:
                        state.refused = true
                        lastFailure = .failed("This team can't be changed from this account.")
                    case .rejected:
                        state.stuckRows = working
                        backup(team)
                        lastFailure = .failed(Self.friendly(error))
                    }
                    state.lastError = Self.friendly(error)
                    Log.sync.error("Push of team \(team.id, privacy: .public) failed: \(String(describing: error), privacy: .public)")
                    // The server may hold part of the push; the next pass
                    // fetches it, so the base stays where it was.
                    if serverRows != nil { state.base = serverRows }
                    pending += 1
                    file.teams[team.id] = state
                    outcome.merged.append(.init(team: mergedTeam, snapshotRows: snapshot, slots: slots))
                    continue
                }
            }

            // 5. The server now holds `working`.
            state.base = working
            state.lastPullAt = Date()
            state.lastError = nil
            state.stuckRows = nil
            file.teams[team.id] = state
            outcome.merged.append(.init(team: mergedTeam, snapshotRows: snapshot, slots: slots))
        }

        // Teams in the account this device doesn't have yet.
        let known = Set(teams.map(\.id)).union(excluding).union(file.pendingDeletes)
        for (id, rows) in server where !known.contains(id) {
            let (team, slots) = TeamRowMapper.team(from: rows, local: nil)
            var state = TeamSyncState()
            state.base = rows
            state.slots = slots
            state.lastPullAt = Date()
            file.teams[id] = state
            outcome.addedTeams.append(team)
        }

        persist()
        outcome.status.lastSyncAt = Date()
        outcome.status.conflictCount = file.teams.values.reduce(0) { $0 + $1.conflicts }
        outcome.status.state = lastFailure ?? (pending > 0 ? .pending(pending) : .upToDate)
        return outcome
    }

    // MARK: - Fetch

    private static let teamSelect = """
        *, players(*), scheduled_games(*), lineup_templates(*, template_locks(*)), \
        lineups(*, lineup_cells(inning, player_id, position)), \
        game_logs(*, pitch_counts(player_id, pitches))
        """

    private func fetchAllTeams() async throws -> [UUID: TeamRows] {
        let fetched: [ServerTeam] = try await client.from("teams")
            .select(Self.teamSelect)
            .is("deleted_at", value: nil)
            .is("players.deleted_at", value: nil)
            .is("scheduled_games.deleted_at", value: nil)
            .is("lineup_templates.deleted_at", value: nil)
            .is("lineups.deleted_at", value: nil)
            .is("game_logs.deleted_at", value: nil)
            .execute()
            .value
        return Dictionary(fetched.map { ($0.rows.teamID, $0.rows.normalized()) }, uniquingKeysWith: { a, _ in a })
    }

    // MARK: - Push

    /// Sends one change set. The order matters:
    ///   1. the team row (insert when new: an upsert would hit the insert
    ///      policy on a team someone else owns), without its two pointers;
    ///   2. lineup and scheduled-game deletes first, so a replacement can't
    ///      collide with the one-lineup-per-game and (team, ical_uid) indexes;
    ///   3. players, games, templates and locks, which lineups point at;
    ///   4. lineups, then their cells (save_innings), then finalized lineups
    ///      again, because save_innings returns a lineup to draft;
    ///   5. game logs and pitch counts; 6. soft deletes; 7. the pointers.
    private func push(_ c: TeamChangeSet, rows: TeamRows) async throws {
        let teamID = rows.teamID.uuidString

        if c.isNewTeam {
            try await client.from("teams").insert(Payload.of(rows.team, omitting: ["current_lineup_id", "default_template_id"]),
                                                  returning: .minimal).execute()
        } else if let team = c.team {
            let updated: [IDOnly] = try await client.from("teams")
                .update(Payload.of(team, omitting: ["id", "current_lineup_id", "default_template_id", "created_at"]))
                .eq("id", value: teamID).select("id").execute().value
            if updated.isEmpty { throw SyncError.refused }
        }

        if !c.deletedLineups.isEmpty { try await softDelete("lineups", c.deletedLineups) }
        if !c.deletedScheduledGames.isEmpty {
            try await client.from("scheduled_games").delete(returning: .minimal)
                .in("id", values: c.deletedScheduledGames.map(\.uuidString)).execute()
        }
        if !c.deletedLocks.isEmpty {
            try await client.from("template_locks").delete(returning: .minimal)
                .in("id", values: c.deletedLocks.map(\.uuidString)).execute()
        }

        try await upsert("players", c.players, softDeletable: true)
        try await upsert("scheduled_games", c.scheduledGames, softDeletable: true)
        try await upsert("lineup_templates", c.templates, softDeletable: true)
        try await upsert("template_locks", c.locks, softDeletable: false)
        try await upsert("lineups", c.lineups, softDeletable: true)

        for (lineupID, count) in c.trimmedLineups {
            try await client.from("lineup_cells").delete(returning: .minimal)
                .eq("lineup_id", value: lineupID.uuidString).gte("inning", value: count).execute()
        }
        for (lineupID, innings) in c.innings.sorted(by: { $0.key.uuidString < $1.key.uuidString }) {
            var body: [String: JSONValue] = [:]
            for (i, cells) in innings {
                body[String(i)] = .object(Dictionary(uniqueKeysWithValues: cells.map { ($0.key.uuidString, .string($0.value)) }))
            }
            try await client.rpc("save_innings", params: SaveInningsParams(p_lineup_id: lineupID, p_innings: .object(body)))
                .execute()
        }
        let refinalize = rows.lineups.values.filter { $0.status == "finalized" && c.innings[$0.id] != nil }
        try await upsert("lineups", refinalize, softDeletable: true)

        try await upsert("game_logs", c.gameLogs, softDeletable: true)
        for (logID, counts) in c.pitchCounts.sorted(by: { $0.key.uuidString < $1.key.uuidString }) {
            try await client.rpc("replace_pitch_counts", params: PitchCountParams(
                p_game_log_id: logID, p_counts: .object(counts.mapValues { .int($0) }))).execute()
        }

        if !c.deletedPlayers.isEmpty { try await softDelete("players", c.deletedPlayers) }
        if !c.deletedTemplates.isEmpty { try await softDelete("lineup_templates", c.deletedTemplates) }
        if !c.deletedGameLogs.isEmpty { try await softDelete("game_logs", c.deletedGameLogs) }

        if c.pointersChanged || c.isNewTeam {
            let pointers: [String: JSONValue] = [
                "current_lineup_id": rows.team.currentLineupID.map { .string($0.uuidString) } ?? .null,
                "default_template_id": rows.team.defaultTemplateID.map { .string($0.uuidString) } ?? .null,
            ]
            try await client.from("teams").update(pointers, returning: .minimal).eq("id", value: teamID).execute()
        }
    }

    private func upsert<R: Encodable & SupabaseColumns>(_ table: String, _ records: [R], softDeletable: Bool) async throws {
        guard !records.isEmpty else { return }
        let payload = try records.map { r -> [String: JSONValue] in
            var p = try Payload.of(r)
            if softDeletable { p["deleted_at"] = .null }   // revives a row deleted earlier
            return p
        }
        try await client.from(table).upsert(payload, onConflict: "id", returning: .minimal).execute()
    }

    private func softDelete(_ table: String, _ ids: [UUID]) async throws {
        try await client.from(table)
            .update(["deleted_at": JSONValue.string(RowTimestamp.string(Date()))], returning: .minimal)
            .in("id", values: ids.map(\.uuidString)).execute()
    }

    private func pushPendingDeletes() async {
        guard !file.pendingDeletes.isEmpty else { return }
        for id in file.pendingDeletes {
            do {
                // A hard delete (cascades), as on the web. Zero rows (already
                // gone, or not ours) is done too.
                try await client.from("teams").delete(returning: .minimal).eq("id", value: id.uuidString).execute()
                file.pendingDeletes.remove(id)
                Log.sync.notice("Deleted team \(id, privacy: .public) from the account")
            } catch {
                Log.sync.error("Team delete failed, will retry: \(String(describing: error), privacy: .public)")
            }
        }
        persist()
    }

    // MARK: - Persistence and backup

    private func persist() {
        do { try store.saveSync(file) } catch {
            Log.sync.error("Couldn't save sync state: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// A copy of a team the server rejected, kept before anything else happens
    /// to it. Support can recover it from the device if it comes to that.
    private func backup(_ team: Team) {
        let dir = store.directory.appendingPathComponent("backups", isDirectory: true)
        let name = "\(team.id.uuidString)-\(Int(Date().timeIntervalSince1970)).json"
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try JSONEncoder().encode(team).write(to: dir.appendingPathComponent(name),
                                                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            Log.sync.error("Couldn't back up team: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Errors

    enum SyncError: Error { case refused }

    enum Failure { case offline, auth, refused, rejected }

    static func classify(_ error: Error) -> Failure {
        if isOffline(error) { return .offline }
        if case SyncError.refused = error { return .refused }
        if let pg = error as? PostgrestError {
            switch pg.code {
            case "42501": return .refused                  // row-level security
            case "PGRST301", "PGRST302": return .auth      // JWT expired / missing
            default: return .rejected
            }
        }
        if let http = error as? HTTPError, http.response.statusCode == 401 { return .auth }
        return .rejected
    }

    static func isOffline(_ error: Error) -> Bool {
        if let url = error as? URLError {
            return [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost,
                    .cannotConnectToHost, .dataNotAllowed, .internationalRoamingOff].contains(url.code)
        }
        return false
    }

    /// Fixed strings only: these reach the screen and the support report.
    static func friendly(_ error: Error) -> String {
        switch classify(error) {
        case .offline: return "Waiting for a connection."
        case .auth: return "Sign in again to sync."
        case .refused: return "This team can't be changed from this account."
        case .rejected:
            if let pg = error as? PostgrestError, let code = pg.code { return "The server didn't accept a change (\(code))." }
            return "The server didn't accept a change."
        }
    }
}

// MARK: - Wire shapes

/// A record whose CodingKeys list every column, so a payload can send an
/// explicit null for each nil one (Swift's synthesized encoder leaves nil
/// optionals out, and an omitted column keeps its old value on the server).
nonisolated protocol SupabaseColumns {
    static var columns: [String] { get }
}

extension TeamRecord: SupabaseColumns { static var columns: [String] { CodingKeys.allCases.map(\.stringValue) } }
extension PlayerRecord: SupabaseColumns { static var columns: [String] { CodingKeys.allCases.map(\.stringValue) } }
extension ScheduledGameRecord: SupabaseColumns { static var columns: [String] { CodingKeys.allCases.map(\.stringValue) } }
extension TemplateRecord: SupabaseColumns { static var columns: [String] { CodingKeys.allCases.map(\.stringValue) } }
extension TemplateLockRecord: SupabaseColumns { static var columns: [String] { CodingKeys.allCases.map(\.stringValue) } }
extension LineupRecord: SupabaseColumns { static var columns: [String] { CodingKeys.allCases.map(\.stringValue) } }
extension GameLogRecord: SupabaseColumns { static var columns: [String] { CodingKeys.allCases.map(\.stringValue) } }

nonisolated enum Payload {
    /// `record` as a JSON object for PostgREST: timestamps as ISO 8601 with
    /// milliseconds, and every column present, nil ones as null.
    static func of<R: Encodable & SupabaseColumns>(_ record: R, omitting: Set<String> = []) throws -> [String: JSONValue] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, enc in
            var c = enc.singleValueContainer()
            try c.encode(RowTimestamp.string(date))
        }
        guard case .object(var o) = try JSONDecoder().decode(JSONValue.self, from: encoder.encode(record)) else {
            return [:]
        }
        for column in R.columns where o[column] == nil { o[column] = .null }
        for column in omitting { o[column] = nil }
        return o
    }
}

private nonisolated struct IDOnly: Decodable { let id: UUID }

private nonisolated struct SaveInningsParams: Encodable {
    let p_lineup_id: UUID
    let p_innings: JSONValue
}

private nonisolated struct PitchCountParams: Encodable {
    let p_game_log_id: UUID
    let p_counts: JSONValue
}

/// The nested fetch: a team row with its children embedded.
nonisolated struct ServerTeam: Decodable {
    let rows: TeamRows

    private enum Keys: String, CodingKey {
        case players
        case scheduledGames = "scheduled_games"
        case templates = "lineup_templates"
        case lineups
        case gameLogs = "game_logs"
    }

    private struct ServerTemplate: Decodable {
        let record: TemplateRecord
        let locks: [TemplateLockRecord]
        enum K: String, CodingKey { case locks = "template_locks" }
        init(from decoder: Decoder) throws {
            record = try TemplateRecord(from: decoder)
            locks = try decoder.container(keyedBy: K.self).decodeIfPresent([TemplateLockRecord].self, forKey: .locks) ?? []
        }
    }

    private struct ServerCell: Decodable {
        let inning: Int
        let player_id: UUID
        let position: String
    }

    private struct ServerLineup: Decodable {
        let record: LineupRecord
        let cells: [ServerCell]
        enum K: String, CodingKey { case cells = "lineup_cells" }
        init(from decoder: Decoder) throws {
            record = try LineupRecord(from: decoder)
            cells = try decoder.container(keyedBy: K.self).decodeIfPresent([ServerCell].self, forKey: .cells) ?? []
        }
    }

    private struct ServerPitchCount: Decodable {
        let player_id: UUID
        let pitches: Int
    }

    private struct ServerLog: Decodable {
        let record: GameLogRecord
        let counts: [ServerPitchCount]
        enum K: String, CodingKey { case counts = "pitch_counts" }
        init(from decoder: Decoder) throws {
            record = try GameLogRecord(from: decoder)
            counts = try decoder.container(keyedBy: K.self).decodeIfPresent([ServerPitchCount].self, forKey: .counts) ?? []
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        var rows = TeamRows(team: try TeamRecord(from: decoder))
        for p in try c.decodeIfPresent([PlayerRecord].self, forKey: .players) ?? [] { rows.players[p.id] = p }
        for g in try c.decodeIfPresent([ScheduledGameRecord].self, forKey: .scheduledGames) ?? [] { rows.scheduledGames[g.id] = g }
        for t in try c.decodeIfPresent([ServerTemplate].self, forKey: .templates) ?? [] {
            rows.templates[t.record.id] = t.record
            for l in t.locks { rows.locks[l.id] = l }
        }
        for l in try c.decodeIfPresent([ServerLineup].self, forKey: .lineups) ?? [] {
            rows.lineups[l.record.id] = l.record
            for cell in l.cells { rows.cells[l.record.id, default: [:]][cell.inning, default: [:]][cell.player_id] = cell.position }
        }
        for g in try c.decodeIfPresent([ServerLog].self, forKey: .gameLogs) ?? [] {
            rows.gameLogs[g.record.id] = g.record
            if !g.counts.isEmpty {
                rows.pitchCounts[g.record.id] = Dictionary(g.counts.map { ($0.player_id.uuidString, $0.pitches) },
                                                           uniquingKeysWith: { a, _ in a })
            }
        }
        self.rows = rows
    }
}
