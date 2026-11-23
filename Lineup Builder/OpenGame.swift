//
//  OpenGame.swift
//  Lineup Builder
//
//  Merge 3: which lineup a device has open is the device's own choice.
//
//  teams.current_lineup_id used to say which lineup was open for the whole
//  team, so opening Game 2 on the iPad moved the iPhone off Game 1, and on a
//  shared team one coach moved every coach. Now each device keeps its own open
//  game and the sync never reads or writes that column. Lineups themselves
//  still sync: only the choice of which one is open stays here.
//
//  This file is the rule, kept pure so it's unit-tested. The web has the same
//  rule in web/src/core/openGame.ts; keep the two in step.
//

import Foundation

/// Who archived a game log, as the server stamped it (20261123000000_game_log_archiver).
nonisolated struct GameLogArchiver: Hashable, Sendable {
    var userID: UUID?
    /// The archiving coach's name when they archived it. May be empty.
    var name: String
}

nonisolated enum OpenGame {

    /// The game this device had open was archived somewhere else.
    struct Archived: Equatable, Sendable {
        /// The coach who archived it, or nil when the server doesn't know.
        var byName: String?
        /// Archived by this same account, on another device.
        var byMe: Bool
        var opponent: String

        /// "Sam archived the game vs Tigers. Showing your next game."
        var message: String {
            let game = opponent.isEmpty ? "the game" : "the game vs \(opponent)"
            let who = byMe ? "You archived \(game) on another device"
                : byName.map { "\($0) archived \(game)" } ?? "Another coach archived \(game)"
            return "\(who). Showing your next game."
        }
    }

    /// The lineup a device opens when it has no choice of its own (a new
    /// device, or its open game is gone): the next game from the start of today
    /// that has a lineup, else the latest past one, else an ad-hoc lineup.
    /// Cancelled games are skipped. nil means there's no lineup at all yet.
    static func defaultLineup(in rows: TeamRows, preferredAdhoc: UUID? = nil,
                              now: Date = Date(), calendar: Calendar = .current) -> UUID? {
        let today = calendar.startOfDay(for: now)
        var upcoming: (id: UUID, at: Date)?
        var past: (id: UUID, at: Date)?
        for l in rows.lineups.values {
            guard let gameID = l.scheduledGameID, let game = rows.scheduledGames[gameID], !game.isCancelled else { continue }
            if game.startsAt >= today {
                if upcoming.map({ (game.startsAt, l.id.uuidString) < ($0.at, $0.id.uuidString) }) ?? true { upcoming = (l.id, game.startsAt) }
            } else {
                if past.map({ (game.startsAt, l.id.uuidString) > ($0.at, $0.id.uuidString) }) ?? true { past = (l.id, game.startsAt) }
            }
        }
        if let upcoming { return upcoming.id }
        if let past { return past.id }
        let adhoc = rows.lineups.values.filter { $0.scheduledGameID == nil }.map(\.id)
        if let preferredAdhoc, adhoc.contains(preferredAdhoc) { return preferredAdhoc }
        return adhoc.min { $0.uuidString < $1.uuidString }
    }

    /// Which lineup to keep open after a sync brings in `rows`.
    ///
    /// - Parameters:
    ///   - openLineupID: the lineup this device had open, and
    ///   - openGameID: the game it belonged to (nil for an ad-hoc lineup).
    ///     It stays open while that lineup still exists for that same game.
    ///   - archivers: who archived each game log, by log id.
    ///   - me: the signed-in account, to say "you" rather than a name.
    /// - Returns: the lineup to open, and the note to show when the open game
    ///   was archived elsewhere. A game that simply left the schedule moves on
    ///   quietly.
    static func resolve(rows: TeamRows, openLineupID: UUID?, openGameID: UUID?,
                        archivers: [UUID: GameLogArchiver] = [:], me: UUID? = nil,
                        preferredAdhoc: UUID? = nil, now: Date = Date(),
                        calendar: Calendar = .current) -> (lineupID: UUID?, archived: Archived?) {
        if let open = openLineupID, let l = rows.lineups[open], l.scheduledGameID == openGameID {
            return (open, nil)
        }
        let next = defaultLineup(in: rows, preferredAdhoc: preferredAdhoc, now: now, calendar: calendar)
        guard let openGameID,
              let log = rows.gameLogs.values.first(where: { $0.scheduledGameID == openGameID }) else {
            return (next, nil)
        }
        let who = archivers[log.id]
        let byMe = me != nil && who?.userID == me
        let name = who.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
        return (next, Archived(byName: name, byMe: byMe, opponent: log.opponent))
    }
}
