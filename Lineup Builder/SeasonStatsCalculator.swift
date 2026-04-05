import Foundation

// MARK: - SeasonStatsCalculator
// Pure static functions. No side effects. Easily unit-testable.
// Critical correctness rule: only innings[0..<log.inningsPlayed] count toward stats.

enum SeasonStatsCalculator {

    static func compute(from logs: [GameLog]) -> SeasonStats {
        guard !logs.isEmpty else {
            return SeasonStats(players: [], gameCount: 0, dateRange: "")
        }

        // Build a unified set of all players seen across all logs
        // using their snapshots so deleted players still appear correctly.
        var snapshotMap: [UUID: PlayerSnapshot] = [:]
        for log in logs {
            for snap in log.playerSnapshot {
                // Later games win if the same player appears in multiple logs
                // (name/number may have been updated between games)
                snapshotMap[snap.id] = snap
            }
        }

        // Accumulate stats per player
        var posCountMap:    [UUID: [String: Int]] = [:]
        var gamesPlayedMap: [UUID: Int]           = [:]
        var totalInningsMap:[UUID: Int]           = [:]
        var benchInningsMap:[UUID: Int]           = [:]
        var infieldMap:     [UUID: Int]           = [:]
        var outfieldMap:    [UUID: Int]           = [:]

        for log in logs {
            let activeIDs = Set(log.playerSnapshot.map { $0.id })

            for playerID in activeIDs {
                // Only count innings that were actually played
                for inningIndex in 0..<log.inningsPlayed {
                    guard inningIndex < log.innings.count else { continue }
                    let inning = log.innings[inningIndex]

                    guard let pos = inning.assignments[playerID] else { continue }

                    // Use display names as keys ("Pitcher" not "P") so AI prompt is readable
                    posCountMap[playerID, default: [:]][pos.displayName, default: 0] += 1
                    totalInningsMap[playerID, default: 0] += 1

                    if pos.isBench {
                        benchInningsMap[playerID, default: 0] += 1
                    } else if pos.isInfield {
                        infieldMap[playerID, default: 0] += 1
                    } else if pos.isOutfield {
                        outfieldMap[playerID, default: 0] += 1
                    }
                }

                // Count games played (player appears in snapshot = they were active)
                gamesPlayedMap[playerID, default: 0] += 1
            }
        }

        // Build PlayerSeasonStats for each player
        // Use display names for neverPlayed so AI gets "Shortstop" not "SS"
        let allFieldPositionNames = FieldPosition.fieldPositions.map { $0.displayName }

        let playerStats: [PlayerSeasonStats] = snapshotMap.values.map { snap in
            let counts = posCountMap[snap.id] ?? [:]
            let neverPlayed = allFieldPositionNames.filter { (counts[$0] ?? 0) == 0 }

            return PlayerSeasonStats(
                playerID: snap.id,
                playerName: snap.displayName,
                posCounts: counts,
                gamesPlayed: gamesPlayedMap[snap.id] ?? 0,
                totalInnings: totalInningsMap[snap.id] ?? 0,
                benchInnings: benchInningsMap[snap.id] ?? 0,
                neverPlayed: neverPlayed,
                infieldInnings: infieldMap[snap.id] ?? 0,
                outfieldInnings: outfieldMap[snap.id] ?? 0
            )
        }
        .sorted { $0.playerName < $1.playerName }

        return SeasonStats(
            players: playerStats,
            gameCount: logs.count,
            dateRange: dateRange(from: logs)
        )
    }

    // MARK: - Helpers

    private static func dateRange(from logs: [GameLog]) -> String {
        let dates = logs.map { $0.gameDate }
        guard let earliest = dates.min(), let latest = dates.max() else { return "" }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"

        if Calendar.current.isDate(earliest, inSameDayAs: latest) {
            return formatter.string(from: earliest)
        }
        return "\(formatter.string(from: earliest)) – \(formatter.string(from: latest))"
    }
}
