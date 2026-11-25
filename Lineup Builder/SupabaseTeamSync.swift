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
    /// Teams whose writes the server refuses: shown read-only.
    var refusedTeamIDs: Set<UUID> = []
    /// Teams whose open game was archived elsewhere this pass (Merge 3): the
    /// pass moved them on, and the app says so.
    var archivedOpenGames: [UUID: OpenGame.Archived] = [:]
    /// This coach's access to each account team the server returned (Merge 4).
    var access: [UUID: TeamAccess] = [:]
    /// Teams this coach didn't own that the server stopped returning: removed
    /// from the team, the team was deleted, or they left on another device.
    var lostAccessTeamIDs: Set<UUID> = []
    /// The pass reached the server, so `access` is complete (an offline pass
    /// leaves it empty, and that mustn't erase what the device knows).
    var accessFetched = false
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
    /// Set by sign-out before the folder is wiped, so a pass still running
    /// can't write sync.json back into it.
    private var closed = false
    /// Who archived each game log, from the last full fetch (Merge 3). Kept
    /// out of TeamRows: the server stamps it, and the device never sends it.
    private var archivers: [UUID: GameLogArchiver] = [:]
    /// Each fetched team's owner and coaches, from the last full fetch (Merge 4).
    private var memberships: [UUID: ServerTeam.Membership] = [:]

    init(store: AccountTeamStore, client: SupabaseClient = supabase) {
        self.store = store
        self.client = client
        self.file = store.loadSync()
    }

    /// The persisted state for a team; for tests and diagnostics.
    func state(for id: UUID) -> TeamSyncState? { file.teams[id] }

    /// Stops this actor writing anything more. Sign-out and account deletion.
    func close() { closed = true }

    /// Name-free lines for the diagnostics report.
    func diagnostics() -> [String] {
        var lines = ["  pending team deletes: \(file.pendingDeletes.count)"]
        for (id, s) in file.teams.sorted(by: { $0.key.uuidString < $1.key.uuidString }) {
            lines.append("  team \(id.uuidString): pushed \(s.lastPushAt.map(ISO8601DateFormatter().string) ?? "never")   pulled \(s.lastPullAt.map(ISO8601DateFormatter().string) ?? "never")   conflicts \(s.conflicts)   refused \(s.refused)   error \(s.lastError ?? "none")")
        }
        return lines
    }

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

        guard let session = try? await client.auth.session else {
            status.state = .signInNeeded
            return TeamSyncOutcome(status: status)
        }
        let me = session.user.id

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
        outcome.accessFetched = true
        for (id, m) in memberships where server[id] != nil {
            if let a = TeamAccess.resolve(ownerID: m.ownerID, ownerName: m.ownerName, coaches: m.coaches, me: me) {
                outcome.access[id] = a
            }
        }
        var pending = 0
        var lastFailure: AccountSyncStatus.State?

        for team in teams where !file.pendingDeletes.contains(team.id) && !closed {
            var state = file.teams[team.id] ?? TeamSyncState()
            if state.refused {
                outcome.refusedTeamIDs.insert(team.id)
                continue
            }

            var slots = state.slots
            let snapshot = TeamRowMapper.rows(from: team, slots: &slots, base: state.base).rows
            // The open lineup is this device's own (Merge 3): the server's
            // pointer, and the one in the last base, never move it.
            let openLineupID = snapshot.team.currentLineupID
            let openGameID = openLineupID.flatMap { snapshot.lineups[$0]?.scheduledGameID }
            let serverRows = server[team.id].map { r in var r = r; r.team.currentLineupID = openLineupID; return r }
            state.base?.team.currentLineupID = openLineupID

            // The server has no copy.
            if serverRows == nil, state.base != nil, let role = state.role, role != .owner {
                // Not ours: the coach lost access (removed, left, or the owner
                // deleted it). Their edits can't be sent anywhere; recreating it
                // would make a copy they own of someone else's team.
                Log.sync.notice("Team \(team.id, privacy: .public): no longer shared with this coach; removing it")
                outcome.removedTeamIDs.insert(team.id)
                outcome.lostAccessTeamIDs.insert(team.id)
                file.teams[team.id] = nil
                continue
            }
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
                var mergedRows = merge.rows
                // Team settings are the owner's (Merge 4, decision 1): a coach's
                // device always takes the server's team row and never sends one.
                if let access = outcome.access[team.id], !access.canChangeSettings {
                    let open = mergedRows.team.currentLineupID
                    mergedRows.team = serverRows.team
                    mergedRows.team.currentLineupID = open
                }
                let open = OpenGame.resolve(rows: mergedRows, openLineupID: openLineupID, openGameID: openGameID,
                                            archivers: archivers, me: me, preferredAdhoc: slots.adhoc)
                if open.lineupID != openLineupID {
                    mergedRows.team.currentLineupID = open.lineupID
                }
                // Not only when the lineup changes: "Archive and start new game"
                // keeps the same row open, carried forward to the next game.
                // The next pass sees it as ad-hoc, so the note shows once.
                if let archived = open.archived {
                    outcome.archivedOpenGames[team.id] = archived
                    Log.sync.notice("Team \(team.id, privacy: .public): the open game was archived elsewhere; opening the next one")
                }
                var rebuilt = TeamRowMapper.team(from: mergedRows, local: team)
                slots = rebuilt.slots
                rebuilt.team.updatedAt = team.updatedAt
                mergedTeam = rebuilt.team
                working = TeamRowMapper.rows(from: mergedTeam, slots: &slots, base: serverRows).rows
            }
            state.slots = slots
            let access = outcome.access[team.id]
            state.role = access?.role

            // 4. Push what the server doesn't have. A viewer has nothing to send
            // (the server would refuse it); a coach never sends the team row.
            var changes = TeamRowsDiff.changes(from: serverRows, to: working)
            if let access, !access.isOwner {
                changes.team = nil
                changes.pointersChanged = false
                if !access.canEdit { changes = TeamChangeSet() }
            }
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
                        outcome.refusedTeamIDs.insert(team.id)
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
            // A device seeing a team for the first time opens the default game.
            var rows = rows
            rows.team.currentLineupID = OpenGame.defaultLineup(in: rows)
            let (team, slots) = TeamRowMapper.team(from: rows, local: nil)
            var state = TeamSyncState()
            state.role = outcome.access[id]?.role
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

    /// lineups and lineup_templates are each linked to teams twice (their
    /// team_id, and the team's current_lineup_id / default_template_id), so
    /// PostgREST needs the foreign key named or it answers 300 (ambiguous).
    private static let teamSelect = """
        *, players(*), scheduled_games(*), \
        lineup_templates!lineup_templates_team_id_fkey(*, template_locks(*)), \
        lineups!lineups_team_id_fkey(*, lineup_cells(inning, player_id, position)), \
        game_logs(*, pitch_counts(player_id, pitches)), \
        team_members(user_id, role, name, joined_at)
        """

    private func fetchAllTeams() async throws -> [UUID: TeamRows] {
        try await fetchTeams(id: nil)
    }

    /// Every team this coach can read, or just one.
    private func fetchTeams(id: UUID?) async throws -> [UUID: TeamRows] {
        var query = client.from("teams").select(Self.teamSelect)
        if let id { query = query.eq("id", value: id.uuidString) }
        let fetched: [ServerTeam] = try await query
            .is("deleted_at", value: nil)
            .is("players.deleted_at", value: nil)
            .is("scheduled_games.deleted_at", value: nil)
            .is("lineup_templates.deleted_at", value: nil)
            .is("lineups.deleted_at", value: nil)
            .is("game_logs.deleted_at", value: nil)
            .execute()
            .value
        if id == nil {
            archivers = fetched.reduce(into: [:]) { $0.merge($1.archivers) { a, _ in a } }
            memberships = Dictionary(fetched.compactMap { t in t.membership.map { (t.rows.teamID, $0) } },
                                     uniquingKeysWith: { a, _ in a })
        }
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

        // teams.current_lineup_id is never written: which lineup is open is each
        // device's own choice (Merge 3, OpenGame).
        if c.pointersChanged || c.isNewTeam {
            let pointers: [String: JSONValue] = [
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
                // A coach "deleting" a shared team leaves it (Merge 4); for the
                // owner there's no membership, so it does nothing. Best effort:
                // a database without 20261124000000_shared_teams has no
                // leave_team, and that mustn't hold up the owner's delete.
                _ = try? await client.rpc("leave_team", params: ["p_team": id.uuidString]).execute()
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
        guard !closed else { return }
        do { try store.saveSync(file) } catch {
            Log.sync.error("Couldn't save sync state: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// A copy of a team kept before anything else happens to it: one the
    /// server rejected, or one about to move into the account. Support can
    /// recover it from the device if it comes to that. Returns the file name,
    /// or nil if it couldn't be written.
    @discardableResult
    private func backup(_ team: Team, tag: String? = nil) -> String? {
        let dir = store.directory.appendingPathComponent("backups", isDirectory: true)
        let name = "\(team.id.uuidString)\(tag.map { "-\($0)" } ?? "")-\(Int(Date().timeIntervalSince1970)).json"
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try JSONEncoder().encode(team).write(to: dir.appendingPathComponent(name),
                                                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return name
        } catch {
            Log.sync.error("Couldn't back up team: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Moves (Merge 1; see TeamMove)

    /// Moves not finished yet.
    func moveRecords() -> [UUID: TeamMoveRecord] { file.moves ?? [:] }

    /// The raw backup a move keeps before it starts. Nil if it couldn't be
    /// written, in which case the move doesn't go ahead.
    func backupForMove(_ team: Team) -> String? { backup(team, tag: "move") }

    /// A raw copy of a team imported from a .stlteam file, kept before its
    /// first upload.
    func backupForImport(_ team: Team) -> String? { backup(team, tag: "import") }

    /// A raw copy of an account team about to be replaced by a .stlteam
    /// import, so the coach's data before the replace isn't lost.
    func backupBeforeReplace(_ team: Team) -> String? { backup(team, tag: "replace") }

    /// Records a move before the team changes, so a crash can be recovered.
    func beginMove(_ id: UUID, record: TeamMoveRecord) {
        var moves = file.moves ?? [:]
        moves[id] = record
        file.moves = moves
        persist()
    }

    func setMovePhase(_ id: UUID, _ phase: TeamMoveRecord.Phase) {
        guard var record = file.moves?[id] else { return }
        record.phase = phase
        file.moves?[id] = record
        persist()
    }

    /// Finished or rolled back. A rolled-back team's sync state is kept on
    /// purpose: it's the base a retry merges against.
    func endMove(_ id: UUID) {
        file.moves?[id] = nil
        if file.moves?.isEmpty == true { file.moves = nil }
        persist()
    }

    /// The read-back: fetches the server's copy of one team and compares it
    /// with the device's, the same comparison a pass uses to decide there's
    /// nothing left to send.
    func verify(_ team: Team) async -> TeamMove.Verify {
        do {
            guard let rows = try await fetchTeams(id: team.id)[team.id] else { return .missing }
            var slots = file.teams[team.id]?.slots ?? LineupSlots()
            let device = TeamRowMapper.rows(from: team, slots: &slots, base: rows).rows
            return device == rows ? .match : .mismatch
        } catch {
            Log.sync.error("Move read-back of team \(team.id, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            return Self.isOffline(error) ? .offline : .failed(Self.friendly(error))
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
    /// Who archived each game log (stamped by the server), by log id.
    let archivers: [UUID: GameLogArchiver]
    /// Nil only when the row came without owner_id (test fixtures).
    let membership: Membership?

    /// The team's owner and coaches (Merge 4).
    struct Membership: Sendable {
        var ownerID: UUID
        var ownerName: String
        var coaches: [TeamCoach]
    }

    private struct ServerMember: Decodable {
        let user_id: UUID
        let role: String
        let name: String?
        let joined_at: Date?
    }

    private enum Keys: String, CodingKey {
        case ownerID = "owner_id"
        case coachName = "coach_name"
        case members = "team_members"
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
        let archiver: GameLogArchiver
        enum K: String, CodingKey {
            case counts = "pitch_counts"
            case archivedByUser = "archived_by_user"
            case archivedByName = "archived_by_name"
        }
        init(from decoder: Decoder) throws {
            record = try GameLogRecord(from: decoder)
            let c = try decoder.container(keyedBy: K.self)
            counts = try c.decodeIfPresent([ServerPitchCount].self, forKey: .counts) ?? []
            // Absent on a database without 20261123000000_game_log_archiver.
            archiver = GameLogArchiver(userID: try c.decodeIfPresent(UUID.self, forKey: .archivedByUser),
                                       name: try c.decodeIfPresent(String.self, forKey: .archivedByName) ?? "")
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
        var archivers: [UUID: GameLogArchiver] = [:]
        for g in try c.decodeIfPresent([ServerLog].self, forKey: .gameLogs) ?? [] {
            rows.gameLogs[g.record.id] = g.record
            archivers[g.record.id] = g.archiver
            if !g.counts.isEmpty {
                rows.pitchCounts[g.record.id] = Dictionary(g.counts.map { ($0.player_id.uuidString, $0.pitches) },
                                                           uniquingKeysWith: { a, _ in a })
            }
        }
        self.rows = rows
        self.archivers = archivers
        // Absent on a database without 20261124000000_shared_teams: then the
        // owner is the only coach.
        let members = (try? c.decodeIfPresent([ServerMember].self, forKey: .members)) ?? nil
        membership = try c.decodeIfPresent(UUID.self, forKey: .ownerID).map { owner in
            Membership(
                ownerID: owner,
                ownerName: try c.decodeIfPresent(String.self, forKey: .coachName) ?? "",
                coaches: (members ?? []).compactMap { m in
                    TeamRole(rawValue: m.role).map { TeamCoach(userID: m.user_id, role: $0, name: m.name ?? "", joinedAt: m.joined_at) }
                })
        }
    }
}
