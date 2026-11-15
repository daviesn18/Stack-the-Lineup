//
//  TeamRowsSync.swift
//  Lineup Builder
//
//  Merge 0b: the two pure halves of syncing one team with Supabase.
//
//  * `TeamRowsDiff` compares the rows the server last confirmed (the base) with
//    the rows of the team as it is on the device, and says what to send. The
//    queue is this diff: nothing is recorded per edit, so a burst of edits
//    collapses into one change set, and a crash mid-push loses nothing (the next
//    launch diffs again). Every write it implies is idempotent.
//
//  * `TeamRowsMerge` folds the server's current rows into the device's, against
//    the same base, row by row (field by field for the team row, inning by
//    inning for the grid). Whichever side changed a row since the base wins; if
//    both did, the device wins, except that an edit always beats a delete, so a
//    merge never silently loses data.
//
//  Both are pure and `nonisolated`; the network layer is SupabaseTeamSync.
//

import Foundation

// MARK: - Change set

/// Everything one push sends for one team, in the order it must be sent.
nonisolated struct TeamChangeSet: Equatable, Sendable {
    /// The team row, when new or changed. Sent without its two pointers, which
    /// go last (`pointersChanged`), once the rows they point at exist.
    var team: TeamRecord?
    /// No base: the team isn't on the server yet, so it's inserted, not updated.
    var isNewTeam = false
    var pointersChanged = false

    var players: [PlayerRecord] = []
    var scheduledGames: [ScheduledGameRecord] = []
    var templates: [TemplateRecord] = []
    var locks: [TemplateLockRecord] = []
    var lineups: [LineupRecord] = []
    /// lineup id → inning → its cells; an empty inning clears it. Sent through
    /// save_innings, one call per lineup.
    var innings: [UUID: [Int: TeamRows.Inning]] = [:]
    /// lineup id → new inning count, where the lineup got shorter and cells past
    /// the end have to go (save_innings refuses innings past the count).
    var trimmedLineups: [UUID: Int] = [:]
    var gameLogs: [GameLogRecord] = []
    /// game log id → its complete pitch counts (replace_pitch_counts).
    var pitchCounts: [UUID: [String: Int]] = [:]

    /// Soft deletes (deleted_at): the web keeps reading these tables that way.
    var deletedPlayers: [UUID] = []
    var deletedTemplates: [UUID] = []
    var deletedLineups: [UUID] = []
    var deletedGameLogs: [UUID] = []
    /// Hard deletes. Scheduled games are unique per (team, ical_uid) including
    /// soft-deleted rows, so a cleared and re-imported schedule (new ids, same
    /// UIDs) would collide with its own ghosts. Locks have no deleted_at.
    var deletedScheduledGames: [UUID] = []
    var deletedLocks: [UUID] = []

    var isEmpty: Bool { self == TeamChangeSet() }

    /// Rows this push writes or deletes, for the sync log and diagnostics.
    var rowCount: Int {
        (team == nil ? 0 : 1) + players.count + scheduledGames.count + templates.count + locks.count
            + lineups.count + innings.values.reduce(0) { $0 + $1.count } + gameLogs.count + pitchCounts.count
            + deletedPlayers.count + deletedTemplates.count + deletedLineups.count + deletedGameLogs.count
            + deletedScheduledGames.count + deletedLocks.count + trimmedLineups.count
    }
}

// MARK: - Diff

nonisolated enum TeamRowsDiff {

    /// What to send so the server holds `working`, given it holds `base`
    /// (nil: the server has nothing for this team yet).
    static func changes(from base: TeamRows?, to working: TeamRows) -> TeamChangeSet {
        var c = TeamChangeSet()
        let b = base

        c.isNewTeam = b == nil
        var bareTeam = working.team
        bareTeam.currentLineupID = nil
        bareTeam.defaultTemplateID = nil
        var bareBase = b?.team
        bareBase?.currentLineupID = nil
        bareBase?.defaultTemplateID = nil
        if bareBase != bareTeam { c.team = working.team }
        c.pointersChanged = b?.team.currentLineupID != working.team.currentLineupID
            || b?.team.defaultTemplateID != working.team.defaultTemplateID

        func split<V: Equatable>(_ old: [UUID: V], _ new: [UUID: V]) -> (upserts: [V], deletes: [UUID]) {
            let upserts = new.filter { old[$0.key] != $0.value }.sorted { $0.key.uuidString < $1.key.uuidString }.map(\.value)
            let deletes = old.keys.filter { new[$0] == nil }.sorted { $0.uuidString < $1.uuidString }
            return (upserts, deletes)
        }

        (c.players, c.deletedPlayers) = split(b?.players ?? [:], working.players)
        (c.scheduledGames, c.deletedScheduledGames) = split(b?.scheduledGames ?? [:], working.scheduledGames)
        (c.templates, c.deletedTemplates) = split(b?.templates ?? [:], working.templates)
        (c.locks, c.deletedLocks) = split(b?.locks ?? [:], working.locks)
        (c.lineups, c.deletedLineups) = split(b?.lineups ?? [:], working.lineups)
        (c.gameLogs, c.deletedGameLogs) = split(b?.gameLogs ?? [:], working.gameLogs)

        // The grid, inning by inning.
        for (id, lineup) in working.lineups {
            let newCells = working.cells[id] ?? [:]
            guard let old = b?.lineups[id] else {
                // A lineup the server doesn't have (or has only as a deleted
                // row, whose old cells may still be there): send every inning,
                // empty ones as clears.
                c.innings[id] = Dictionary(uniqueKeysWithValues: (0..<lineup.inningCount).map { ($0, newCells[$0] ?? [:]) })
                continue
            }
            let oldCells = b?.cells[id] ?? [:]
            var changed: [Int: TeamRows.Inning] = [:]
            for i in 0..<lineup.inningCount where (oldCells[i] ?? [:]) != (newCells[i] ?? [:]) {
                changed[i] = newCells[i] ?? [:]
            }
            if !changed.isEmpty { c.innings[id] = changed }
            if lineup.inningCount < old.inningCount,
               oldCells.keys.contains(where: { $0 >= lineup.inningCount }) {
                c.trimmedLineups[id] = lineup.inningCount
            }
        }

        for (id, counts) in working.pitchCounts where b?.pitchCounts[id] != counts {
            c.pitchCounts[id] = counts
        }
        // A log whose counts were all removed: replace with an empty set.
        for (id, _) in b?.pitchCounts ?? [:] where working.pitchCounts[id] == nil && working.gameLogs[id] != nil {
            c.pitchCounts[id] = [:]
        }

        return c
    }
}

// MARK: - Three-way merge

nonisolated enum TeamRowsMerge {

    struct Result: Equatable, Sendable {
        var rows: TeamRows
        /// Rows (or team fields, or innings) both sides changed differently.
        /// Settled for the device; counted for the sync log and diagnostics.
        var conflicts: Int
    }

    /// The server's rows folded into the device's.
    ///
    /// - Parameters:
    ///   - base: what both sides last agreed on.
    ///   - local: the device's rows now (built from the Team being edited).
    ///   - server: the server's rows now.
    static func merge(base: TeamRows, local: TeamRows, server: TeamRows) -> Result {
        var conflicts = 0

        func pick<V: Equatable>(_ b: V?, _ l: V?, _ s: V?) -> V? {
            if l == b { return s }          // only the server moved (or nobody did)
            if s == b || s == l { return l } // only the device moved, or both agree
            conflicts += 1
            if l == nil { return s }        // device deleted, server edited: keep the edit
            return l                        // otherwise the device wins
        }

        func mergeMap<K: Hashable, V: Equatable>(_ b: [K: V], _ l: [K: V], _ s: [K: V]) -> [K: V] {
            var out: [K: V] = [:]
            for k in Set(b.keys).union(l.keys).union(s.keys) {
                if let v = pick(b[k], l[k], s[k]) { out[k] = v }
            }
            return out
        }

        var rows = local
        rows.team = mergeTeam(base.team, local.team, server.team, conflicts: &conflicts)
        rows.players = mergeMap(base.players, local.players, server.players)
        rows.scheduledGames = mergeMap(base.scheduledGames, local.scheduledGames, server.scheduledGames)
        rows.templates = mergeMap(base.templates, local.templates, server.templates)
        rows.locks = mergeMap(base.locks, local.locks, server.locks)
        rows.lineups = mergeMap(base.lineups, local.lineups, server.lineups)
        rows.gameLogs = mergeMap(base.gameLogs, local.gameLogs, server.gameLogs)
        rows.pitchCounts = mergeMap(base.pitchCounts, local.pitchCounts, server.pitchCounts)

        // The grid merges per (lineup, inning).
        struct CellKey: Hashable { let lineup: UUID; let inning: Int }
        func flat(_ cells: [UUID: [Int: TeamRows.Inning]]) -> [CellKey: TeamRows.Inning] {
            var out: [CellKey: TeamRows.Inning] = [:]
            for (l, innings) in cells { for (i, v) in innings { out[CellKey(lineup: l, inning: i)] = v } }
            return out
        }
        var cells: [UUID: [Int: TeamRows.Inning]] = [:]
        for (k, v) in mergeMap(flat(base.cells), flat(local.cells), flat(server.cells))
        where rows.lineups[k.lineup] != nil && !v.isEmpty {
            cells[k.lineup, default: [:]][k.inning] = v
        }
        rows.cells = cells

        // One lineup per scheduled game. If both sides started one for the same
        // game, keep the device's and drop the other with its cells.
        var byGame: [UUID: [LineupRecord]] = [:]
        for l in rows.lineups.values { if let g = l.scheduledGameID { byGame[g, default: []].append(l) } }
        for (_, ls) in byGame where ls.count > 1 {
            conflicts += 1
            let keep = ls.first { local.lineups[$0.id] != nil && server.lineups[$0.id] == nil }
                ?? ls.min { $0.id.uuidString < $1.id.uuidString }!
            for l in ls where l.id != keep.id {
                rows.lineups[l.id] = nil
                rows.cells[l.id] = nil
                if rows.team.currentLineupID == l.id { rows.team.currentLineupID = keep.id }
            }
        }

        return Result(rows: rows, conflicts: conflicts)
    }

    /// The team row merges field by field: a rename on the web and a fair-play
    /// change on the phone are not a conflict. Each jsonb config is one field.
    private static func mergeTeam(_ b: TeamRecord, _ l: TeamRecord, _ s: TeamRecord, conflicts: inout Int) -> TeamRecord {
        guard let bo = try? JSONValue.encoding(b).objectValue,
              let lo = try? JSONValue.encoding(l).objectValue,
              let so = try? JSONValue.encoding(s).objectValue
        else { return l }
        var out: [String: JSONValue] = [:]
        for k in Set(bo.keys).union(lo.keys).union(so.keys) {
            let (bv, lv, sv) = (bo[k], lo[k], so[k])
            if lv == bv { out[k] = sv }
            else if sv == bv || sv == lv { out[k] = lv }
            else { conflicts += 1; out[k] = lv }
        }
        return (try? JSONValue.object(out.compactMapValues { $0 }).decoded(as: TeamRecord.self)) ?? l
    }
}
