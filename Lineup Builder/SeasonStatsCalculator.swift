import Foundation

// MARK: - SeasonStatsCalculator
// Pure static functions. No side effects. Easily unit-testable.
// Critical correctness rule: only innings[0..<log.inningsPlayed] count toward stats.
//
// The `players` parameter is the live roster. It serves two purposes:
//   1. Filter out deleted players — only snapshot IDs that still exist in the
//      live roster are included in results.
//   2. Source position preferences for gap detection. Preferences are read from
//      the current Player, not the snapshot, so coaching decisions made after
//      the fact (e.g. marking a position Never) are respected immediately.
//
// positionGaps: positions a player has never played this season, excluding any
//   position marked .never in their current preferences. Only populated when
//   gamesPlayed >= 3 to avoid early-season noise.
//
// neverPositionRawValues: raw values (e.g. "P", "C") of positions currently
//   marked .never, so the UI can render the stripe pattern without re-computing.

enum SeasonStatsCalculator {

    // MARK: - Primary entry point (UI + AI)

    nonisolated static func compute(from logs: [GameLog], players: [Player] = []) -> SeasonStats {
        guard !logs.isEmpty else {
            return SeasonStats(players: [], gameCount: 0, dateRange: "")
        }

        // Build a lookup of live players by ID for preference access and
        // deleted-player filtering. If players array is empty (legacy AI call
        // path that doesn't pass players) we skip filtering so nothing breaks.
        let livePlayerMap: [UUID: Player] = Dictionary(
            uniqueKeysWithValues: players.map { ($0.id, $0) }
        )
        let filterByLiveRoster = !players.isEmpty

        // Build snapshot map — later games win for name/number updates.
        // Only include IDs that exist in the live roster (if roster was supplied).
        var snapshotMap: [UUID: PlayerSnapshot] = [:]
        for log in logs {
            for snap in log.playerSnapshot {
                if filterByLiveRoster {
                    guard livePlayerMap[snap.id] != nil else { continue }
                }
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
            // Only count players that made it into the filtered snapshot map
            let activeIDs = Set(log.playerSnapshot.map { $0.id })
                .filter { snapshotMap[$0] != nil }

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

                gamesPlayedMap[playerID, default: 0] += 1
            }
        }

        // All field position display names for neverPlayed (AI prompt use)
        let allFieldPositionNames = FieldPosition.fieldPositions.map { $0.displayName }

        let playerStats: [PlayerSeasonStats] = snapshotMap.values.map { snap in
            let counts = posCountMap[snap.id] ?? [:]
            let gamesPlayed = gamesPlayedMap[snap.id] ?? 0

            // neverPlayed: for the AI prompt — all field positions not yet played.
            // Intentionally not filtered by preferences so the AI has full picture.
            let neverPlayed = allFieldPositionNames.filter { (counts[$0] ?? 0) == 0 }

            // neverPositionRawValues: current .never preferences from live player.
            // Used by the UI to render the stripe pattern on Never positions.
            let livePlayer = livePlayerMap[snap.id]
            let neverRawValues: [String] = livePlayer.map { player in
                player.positionPreferences
                    .filter { $0.value == .never }
                    .map { $0.key.rawValue }
            } ?? []

            // positionGaps: positions never played AND not marked Never,
            // only surfaced after 3+ games to avoid early-season noise.
            let positionGaps: [String]
            if gamesPlayed >= 3, let player = livePlayer {
                let neverPrefDisplayNames = Set(
                    player.positionPreferences
                        .filter { $0.value == .never }
                        .map { $0.key.displayName }
                )
                positionGaps = FieldPosition.fieldPositions
                    .filter { pos in
                        let notPlayed = (counts[pos.displayName] ?? 0) == 0
                        let notNever  = !neverPrefDisplayNames.contains(pos.displayName)
                        return notPlayed && notNever
                    }
                    .map { $0.rawValue }   // Raw values ("SS", "CF") for UI chip display
            } else {
                positionGaps = []
            }

            return PlayerSeasonStats(
                playerID: snap.id,
                playerName: snap.displayName,
                posCounts: counts,
                gamesPlayed: gamesPlayed,
                totalInnings: totalInningsMap[snap.id] ?? 0,
                benchInnings: benchInningsMap[snap.id] ?? 0,
                neverPlayed: neverPlayed,
                infieldInnings: infieldMap[snap.id] ?? 0,
                outfieldInnings: outfieldMap[snap.id] ?? 0,
                positionGaps: positionGaps,
                neverPositionRawValues: neverRawValues
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

    nonisolated private static func dateRange(from logs: [GameLog]) -> String {
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
