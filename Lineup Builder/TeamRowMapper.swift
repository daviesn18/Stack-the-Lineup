//
//  TeamRowMapper.swift
//  Lineup Builder
//
//  Merge 0b: turns a `Team` into its Supabase rows and back.
//
//  The Swift counterpart of web/src/data/teamPayload.ts (Team → rows) and the
//  readers in web/src/data/teamStore.tsx (rows → Team). Keep the cleanup rules
//  in step with teamPayload.ts: the database is strict (composite team keys,
//  one fielder per position, fielding-only template locks) and real iOS data
//  isn't always that tidy, so a bad cell is dropped and reported rather than
//  failing the whole save.
//
//  The lineup model (Merge 2+3 kept it, translating at the edge):
//    * Team.lineup is the lineup being edited. When currentGameID names a game
//      on the schedule, it IS that game's lineup. iOS leaves a stale copy of the
//      open game in gameLineups while it's open, which is ignored here.
//    * Team.gameLineups[gameID] are the other games' saved lineups.
//    * iOS lineups have no id, so `LineupSlots` remembers which row each one is:
//      one id for the ad-hoc working lineup, one per game. It lives with the
//      team's sync state, not in the Team, so swapping lineups around in the
//      stash can never lose or duplicate an id.
//
//  Fields that only mean something on this device (ckRecordName, isReadOnly,
//  isSharedParticipant, updatedAt) are not rows; rows → Team carries them over
//  from the local copy.
//

import Foundation

/// Which lineup row each iOS lineup slot is.
nonisolated struct LineupSlots: Codable, Hashable, Sendable {
    /// The working lineup when it isn't tied to a scheduled game.
    var adhoc: UUID = UUID()
    /// Scheduled game id → that game's lineup row id.
    var games: [UUID: UUID] = [:]
}

nonisolated enum TeamRowMapper {

    struct Mapped {
        var rows: TeamRows
        /// Coach-readable notes about anything cleaned up. Empty when clean.
        var notes: [String]
    }

    // MARK: - Team → rows

    /// The rows for `team`.
    ///
    /// - Parameters:
    ///   - slots: lineup row ids, updated in place: a lineup seen for the first
    ///     time gets a new id, and games no longer on the schedule are dropped.
    ///   - base: the rows the server last confirmed, if any. Two things carry
    ///     over from it: config keys iOS doesn't know (the web's `pausedRules`),
    ///     and lineup rows iOS has no slot for, so iOS never deletes them.
    static func rows(from team: Team, slots: inout LineupSlots, base: TeamRows? = nil) -> Mapped {
        var notes: [String] = []
        let teamID = team.id
        let playerIDs = Set(team.players.map(\.id))
        let gameIDs = Set(team.scheduledGames.map(\.id))
        let templateIDs = Set(team.lineupTemplates.map(\.id))

        var rows = TeamRows(team: TeamRecord(
            id: teamID,
            name: team.name,
            colorHex: team.colorHex.range(of: "^[0-9A-Fa-f]{6}$", options: .regularExpression) != nil
                ? team.colorHex : "0000FF",
            coachName: team.coachName,
            gameInningCount: min(max(team.gameInningCount, 3), 9),
            fairPlayConfig: overlay(fairPlayJSON(team.fairPlayConfig), onto: base?.team.fairPlayConfig),
            pitchingConfig: overlay(pitchingJSON(team.pitchingConfig), onto: base?.team.pitchingConfig),
            calendarSubscriptionURL: team.calendarSubscriptionURL,
            defaultTemplateID: team.defaultTemplateID.flatMap { templateIDs.contains($0) ? $0 : nil },
            currentLineupID: nil,
            createdAt: team.createdAt.roundedToMilliseconds
        ))

        // Players, in roster order.
        for (i, p) in team.players.enumerated() {
            rows.players[p.id] = PlayerRecord(
                id: p.id, teamID: teamID,
                firstName: p.firstName, lastName: p.lastName, number: p.number,
                leagueAge: p.leagueAge,
                positionPreferences: Dictionary(
                    p.positionPreferences.map { ($0.key.rawValue, $0.value.rawValue) },
                    uniquingKeysWith: { a, _ in a }),
                hittingStyle: p.hittingArchetype?.hitting?.rawValue,
                speed: p.hittingArchetype?.speed?.rawValue,
                onBase: p.hittingArchetype?.onBase?.rawValue,
                rosterOrder: i
            )
        }

        for g in team.scheduledGames {
            rows.scheduledGames[g.id] = ScheduledGameRecord(
                id: g.id, teamID: teamID, icalUID: g.icalUID,
                startsAt: g.date.roundedToMilliseconds,
                opponent: g.opponent, location: g.location,
                rawSummary: g.rawSummary, isCancelled: g.isCancelled,
                lastSyncedAt: g.lastSyncedAt.roundedToMilliseconds
            )
        }

        var droppedLocks = 0
        for t in team.lineupTemplates {
            rows.templates[t.id] = TemplateRecord(
                id: t.id, teamID: teamID, name: t.name,
                battingOrder: t.battingOrder, createdAt: t.createdAt.roundedToMilliseconds)
            for l in t.positionLocks {
                guard !l.position.isNonFielding, playerIDs.contains(l.playerID) else {
                    droppedLocks += 1
                    continue
                }
                let first = min(max(l.innings.lowerBound, 0), 8)
                let last = min(max(l.innings.upperBound, 0), 8)
                rows.locks[l.id] = TemplateLockRecord(
                    id: l.id, templateID: t.id, teamID: teamID, playerID: l.playerID,
                    position: l.position.rawValue,
                    firstInning: min(first, last), lastInning: max(first, last))
            }
        }
        if droppedLocks > 0 {
            notes.append("\(droppedLocks) template lock(s) pointed at a removed player and were skipped.")
        }

        // Lineups.
        var droppedCells = 0
        var dedupedCells = 0
        func addLineup(_ l: Lineup, id: UUID, gameID: UUID?) {
            let hasCells = l.innings.contains { !$0.assignments.isEmpty }
            // A lineup with no positions takes the team's game length (iOS seeds
            // a blank Lineup() at 7); one with positions keeps its own length.
            let inningCount = min(max(hasCells && !l.innings.isEmpty ? l.innings.count : team.gameInningCount, 1), 9)
            var cells: [Int: TeamRows.Inning] = [:]
            for i in 0..<inningCount where i < l.innings.count {
                var known = InningAssignment()
                for (pid, pos) in l.innings[i].assignments {
                    if playerIDs.contains(pid) { known.assignments[pid] = pos } else { droppedCells += 1 }
                }
                let kept = known.deduplicatingFieldingPositions(preferring: l.battingOrder)
                dedupedCells += known.assignments.count - kept.assignments.count
                if !kept.assignments.isEmpty {
                    cells[i] = kept.assignments.mapValues(\.rawValue)
                }
            }
            rows.lineups[id] = LineupRecord(
                id: id, teamID: teamID, scheduledGameID: gameID,
                gameDate: l.gameDate.roundedToMilliseconds, opponent: l.opponent,
                inningCount: inningCount, battingOrder: l.battingOrder,
                absentPlayerIDs: l.absentPlayerIDs, status: l.status.rawValue,
                lastFinalizedBy: l.lastFinalizedBy,
                lastFinalizedAt: l.lastFinalizedAt?.roundedToMilliseconds,
                defaultTemplateID: l.defaultTemplateID.flatMap { templateIDs.contains($0) ? $0 : nil })
            if !cells.isEmpty { rows.cells[id] = cells }
        }

        slots.games = slots.games.filter { gameIDs.contains($0.key) }
        func slot(forGame gameID: UUID) -> UUID {
            if let id = slots.games[gameID] { return id }
            let id = UUID()
            slots.games[gameID] = id
            return id
        }

        let currentGame = team.currentGameID.flatMap { gameIDs.contains($0) ? $0 : nil }
        let workingID = currentGame.map(slot(forGame:)) ?? slots.adhoc
        addLineup(team.lineup, id: workingID, gameID: currentGame)
        rows.team.currentLineupID = workingID

        var orphanLineups = 0
        for (gameID, l) in team.gameLineups where gameID != currentGame {
            guard gameIDs.contains(gameID) else { orphanLineups += 1; continue }
            addLineup(l, id: slot(forGame: gameID), gameID: gameID)
        }

        // Lineup rows the web made that iOS has no slot for (not current, not a
        // game's). Carried as they are, so iOS never deletes what it can't show.
        if let base {
            let ownIDs = Set(slots.games.values).union([slots.adhoc])
            for (id, l) in base.lineups where l.scheduledGameID == nil && !ownIDs.contains(id) && rows.lineups[id] == nil {
                rows.lineups[id] = l
                if let c = base.cells[id] { rows.cells[id] = c }
            }
        }

        if orphanLineups > 0 {
            notes.append("\(orphanLineups) saved lineup(s) belonged to games no longer on the schedule and were skipped.")
        }
        if droppedCells > 0 {
            notes.append("\(droppedCells) lineup cell(s) referred to players no longer on the roster and were skipped.")
        }
        if dedupedCells > 0 {
            notes.append("\(dedupedCells) lineup cell(s) doubled up a position in the same inning; the player higher in the batting order kept it, and the rest are left open.")
        }

        for g in team.gameLogs {
            rows.gameLogs[g.id] = GameLogRecord(
                id: g.id, teamID: teamID,
                gameDate: g.gameDate.roundedToMilliseconds, opponent: g.opponent,
                inningsPlayed: min(max(g.inningsPlayed, 1), 9),
                battingOrder: g.battingOrder,
                innings: g.innings.map { inning in
                    Dictionary(inning.assignments.map { ($0.key.uuidString, $0.value.rawValue) },
                               uniquingKeysWith: { a, _ in a })
                },
                playerSnapshot: g.playerSnapshot.map {
                    SnapshotEntry(id: $0.id.uuidString, firstName: $0.firstName,
                                  lastName: $0.lastName, number: $0.number)
                },
                archivedAt: g.archivedAt.roundedToMilliseconds,
                archivedBy: g.archivedBy, notes: g.notes,
                scheduledGameID: g.scheduledGameID)
            let counts = g.pitchCounts.filter { (0...200).contains($0.value) }.upperCasingUUIDKeys()
            if !counts.isEmpty { rows.pitchCounts[g.id] = counts }
        }

        return Mapped(rows: rows, notes: notes)
    }

    // MARK: - Rows → Team

    /// The Team for `rows`, with this device's local-only fields taken from
    /// `local` (the copy being replaced), and the lineup slots the rows imply.
    static func team(from rows: TeamRows, local: Team? = nil) -> (team: Team, slots: LineupSlots) {
        let r = rows.team

        let players = rows.players.values
            .sorted { ($0.rosterOrder, $0.id.uuidString) < ($1.rosterOrder, $1.id.uuidString) }
            .map { p in
                var prefs: [FieldPosition: PositionPreferenceTier] = [:]
                for (k, v) in p.positionPreferences {
                    if let pos = FieldPosition(rawValue: k), let tier = PositionPreferenceTier(rawValue: v) {
                        prefs[pos] = tier
                    }
                }
                let archetype = HittingArchetype(
                    hitting: p.hittingStyle.flatMap(HittingStyle.init(rawValue:)),
                    speed: p.speed.flatMap(SpeedRating.init(rawValue:)),
                    onBase: p.onBase.flatMap(OnBaseRating.init(rawValue:)))
                return Player(id: p.id, firstName: p.firstName, lastName: p.lastName, number: p.number,
                              leagueAge: p.leagueAge, positionPreferences: prefs,
                              hittingArchetype: archetype.isEmpty ? nil : archetype)
            }

        let games = rows.scheduledGames.values
            .sorted { ($0.startsAt, $0.id.uuidString) < ($1.startsAt, $1.id.uuidString) }
            .map { g in
                ScheduledGame(id: g.id, icalUID: g.icalUID, date: g.startsAt, opponent: g.opponent,
                              location: g.location, rawSummary: g.rawSummary, isCancelled: g.isCancelled,
                              lastSyncedAt: g.lastSyncedAt ?? g.startsAt)
            }

        let locksByTemplate = Dictionary(grouping: rows.locks.values, by: \.templateID)
        let templates = rows.templates.values
            .sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
            .map { t in
                LineupTemplate(
                    id: t.id, name: t.name, battingOrder: t.battingOrder,
                    positionLocks: (locksByTemplate[t.id] ?? [])
                        .sorted { ($0.firstInning, $0.id.uuidString) < ($1.firstInning, $1.id.uuidString) }
                        .map {
                            PositionLock(id: $0.id, playerID: $0.playerID,
                                         position: FieldPosition(rawValue: $0.position) ?? .bench,
                                         innings: $0.firstInning...$0.lastInning)
                        },
                    createdAt: t.createdAt)
            }

        func lineup(_ id: UUID) -> Lineup? {
            guard let l = rows.lineups[id] else { return nil }
            var innings = Array(repeating: InningAssignment(), count: l.inningCount)
            for (i, cells) in rows.cells[id] ?? [:] where i < innings.count {
                for (pid, raw) in cells {
                    innings[i].assignments[pid] = FieldPosition(rawValue: raw) ?? .bench
                }
            }
            return Lineup(gameDate: l.gameDate, opponent: l.opponent, battingOrder: l.battingOrder,
                          innings: innings, absentPlayerIDs: l.absentPlayerIDs,
                          status: LineupStatus(rawValue: l.status) ?? .draft,
                          lastFinalizedBy: l.lastFinalizedBy, lastFinalizedAt: l.lastFinalizedAt,
                          defaultTemplateID: l.defaultTemplateID)
        }

        var slots = LineupSlots()
        let current = r.currentLineupID.flatMap { rows.lineups[$0] }
        let working = r.currentLineupID.flatMap(lineup)
            ?? Lineup(innings: Array(repeating: InningAssignment(), count: r.gameInningCount))
        let currentGameID = current?.scheduledGameID
        if let current {
            if let g = current.scheduledGameID { slots.games[g] = current.id } else { slots.adhoc = current.id }
        }

        var gameLineups: [UUID: Lineup] = [:]
        for l in rows.lineups.values {
            guard let g = l.scheduledGameID, g != currentGameID, let built = lineup(l.id) else { continue }
            gameLineups[g] = built
            slots.games[g] = l.id
        }

        let logs = rows.gameLogs.values
            .sorted { ($0.gameDate, $0.id.uuidString) > ($1.gameDate, $1.id.uuidString) }
            .map { g in
                GameLog(
                    id: g.id, gameDate: g.gameDate, opponent: g.opponent, inningsPlayed: g.inningsPlayed,
                    battingOrder: g.battingOrder,
                    innings: g.innings.map { inning in
                        var a = InningAssignment()
                        for (k, v) in inning {
                            if let pid = UUID(uuidString: k) { a.assignments[pid] = FieldPosition(rawValue: v) ?? .bench }
                        }
                        return a
                    },
                    playerSnapshot: g.playerSnapshot.compactMap { s in
                        UUID(uuidString: s.id).map {
                            PlayerSnapshot(from: Player(id: $0, firstName: s.firstName,
                                                        lastName: s.lastName, number: s.number))
                        }
                    },
                    archivedAt: g.archivedAt,
                    pitchCounts: rows.pitchCounts[g.id] ?? [:],
                    archivedBy: g.archivedBy, notes: g.notes,
                    scheduledGameID: g.scheduledGameID)
            }

        let team = Team(
            id: r.id, name: r.name, colorHex: r.colorHex,
            players: players, lineup: working, gameLogs: logs, createdAt: r.createdAt,
            gameInningCount: r.gameInningCount, scheduledGames: games,
            calendarSubscriptionURL: r.calendarSubscriptionURL,
            fairPlayConfig: (try? r.fairPlayConfig.decoded(as: FairPlayConfig.self)) ?? FairPlayConfig(),
            pitchingConfig: pitchingConfig(from: r.pitchingConfig),
            coachName: r.coachName,
            ckRecordName: local?.ckRecordName,
            isReadOnly: local?.isReadOnly ?? false,
            isSharedParticipant: local?.isSharedParticipant ?? false,
            lineupTemplates: templates,
            defaultTemplateID: r.defaultTemplateID,
            gameLineups: gameLineups,
            currentGameID: currentGameID,
            updatedAt: local?.updatedAt ?? Date())
        return (team, slots)
    }

    // MARK: - Config JSON

    /// FairPlayConfig as the object the database stores (iOS's own keys).
    static func fairPlayJSON(_ config: FairPlayConfig) -> JSONValue {
        (try? JSONValue.encoding(config)) ?? .object([:])
    }

    /// PitchingConfig as the database stores it: Swift writes `ageLimits` (an
    /// enum-keyed dictionary) as a flat [key, value, …] array; the database and
    /// the web hold a normal object.
    static func pitchingJSON(_ config: PitchingConfig) -> JSONValue {
        guard case .object(var o) = (try? JSONValue.encoding(config)) ?? .object([:]) else { return .object([:]) }
        if let flat = o["ageLimits"]?.arrayValue {
            var limits: [String: JSONValue] = [:]
            var i = 0
            while i + 1 < flat.count {
                if case .string(let key) = flat[i] { limits[key] = flat[i + 1] }
                i += 2
            }
            o["ageLimits"] = .object(limits)
        }
        return .object(o)
    }

    /// The reverse of `pitchingJSON`. Falls back to defaults field by field, as
    /// PitchingConfig's own decoder does.
    static func pitchingConfig(from json: JSONValue) -> PitchingConfig {
        guard case .object(var o) = json else { return PitchingConfig() }
        if let limits = o["ageLimits"]?.objectValue {
            o["ageLimits"] = .array(limits.sorted { $0.key < $1.key }.flatMap { [.string($0.key), $0.value] })
        }
        return (try? JSONValue.object(o).decoded(as: PitchingConfig.self)) ?? PitchingConfig()
    }

    /// `fresh` with any top-level keys only `base` has kept, so a key the web
    /// added (fair play's `pausedRules`) survives an iOS save.
    static func overlay(_ fresh: JSONValue, onto base: JSONValue?) -> JSONValue {
        guard case .object(let f) = fresh, case .object(let b)? = base else { return fresh }
        return .object(b.merging(f) { _, new in new })
    }
}
