import Foundation
import WidgetKit

/// Builds and writes a WidgetSnapshot to the shared App Group UserDefaults
/// after every LineupStore.save() so the STLWidget extension stays in sync
/// without needing CloudKit or full data model access.
///
/// Add this file to the MAIN APP TARGET ONLY (not the widget extension).
struct WidgetDataBridge {

    static func writeSnapshot(from team: Team) {
        let lineup  = team.lineup
        let players = team.players
        let config  = team.fairPlayConfig
        let games   = team.scheduledGames

        let cal     = Calendar.current
        let today   = cal.startOfDay(for: Date())
        let gameDay = cal.startOfDay(for: lineup.gameDate)
        let isToday = gameDay == today

        let activePlayers = lineup.activePlayers(from: players)
        let activeCount   = activePlayers.count

        // Count innings where every active field position has a player assigned.
        // openPositions returns positions with no assignment under the current config.
        // An empty result means the inning is fully set.
        let filledCount: Int
        if activeCount > 0 {
            filledCount = lineup.innings.indices.filter { idx in
                lineup.openPositions(inning: idx, players: players, config: config).isEmpty
            }.count
        } else {
            filledCount = 0
        }

        // Find the next scheduled game when the active lineup date is not today.
        var nextGameDate:     Date?   = nil
        var nextGameOpponent: String? = nil
        if !isToday {
            if let upcoming = games
                .filter({ !$0.isCancelled && $0.date >= Date() })
                .sorted(by: { $0.date < $1.date })
                .first {
                nextGameDate     = upcoming.date
                nextGameOpponent = upcoming.opponent
            }
        }

        let snapshot = WidgetSnapshot(
            teamName:          team.name.isEmpty ? "My Team" : team.name,
            teamColorHex:      team.colorHex,
            lineupStatus:      lineup.status.rawValue,
            activePlayerCount: activeCount,
            totalInnings:      lineup.innings.count,
            filledInningCount: filledCount,
            gameDate:          lineup.gameDate,
            opponent:          lineup.opponent,
            isToday:           isToday,
            nextGameDate:      nextGameDate,
            nextGameOpponent:  nextGameOpponent,
            hasRoster:         !players.isEmpty,
            updatedAt:         Date()
        )

        guard
            let defaults = UserDefaults(suiteName: WidgetSnapshot.appGroupID),
            let data     = try? JSONEncoder().encode(snapshot)
        else { return }

        defaults.set(data, forKey: WidgetSnapshot.defaultsKey)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
