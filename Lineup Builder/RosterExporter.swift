import Foundation

// MARK: - RosterExporter
// Exports a team's roster to the .stlroster JSON format (v1).
// Pure stateless — no SwiftUI, no side effects.
// The exported file can be imported back via RosterImporter to restore
// all player data including league age and position preferences.
//
// Schema v1:
// {
//   "version": 1,
//   "exportedAt": "ISO8601 date string",
//   "teamName": "Yankees",
//   "players": [
//     {
//       "firstName": "Connor",
//       "lastName": "Walsh",
//       "jerseyNumber": "7",
//       "leagueAge": 10,
//       "positionPreferences": {
//         "Pitcher": "Strength",
//         "Catcher": "Capable"
//       }
//     }
//   ]
// }
//
// positionPreferences keys are FieldPosition.displayName values (e.g. "Pitcher",
// not "P") so the file is human-readable and survives rawValue changes.
// Tier values are PositionPreferenceTier.rawValue strings (e.g. "Strength").

enum RosterExporter {

    // MARK: - Codable Schema

    private struct ExportFile: Encodable {
        let version: Int
        let exportedAt: String
        let teamName: String
        let players: [ExportedPlayer]
    }

    private struct ExportedPlayer: Encodable {
        let firstName: String
        let lastName: String
        let jerseyNumber: String
        let leagueAge: Int?
        let positionPreferences: [String: String]
    }

    // MARK: - Public Entry Point

    /// Encodes the given players to .stlroster JSON data.
    /// Returns nil only if JSON encoding fails (practically impossible).
    static func export(players: [Player], teamName: String) -> Data? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        let exportedPlayers = players.map { player -> ExportedPlayer in
            // Convert positionPreferences dict to [displayName: tierRawValue]
            let prefs: [String: String] = Dictionary(
                uniqueKeysWithValues: player.positionPreferences.map { position, tier in
                    (position.displayName, tier.rawValue)
                }
            )
            return ExportedPlayer(
                firstName: player.firstName,
                lastName: player.lastName,
                jerseyNumber: player.number,
                leagueAge: player.leagueAge,
                positionPreferences: prefs
            )
        }

        let file = ExportFile(
            version: 1,
            exportedAt: formatter.string(from: Date()),
            teamName: teamName,
            players: exportedPlayers
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(file)
    }

    /// Generates a filename for the export based on team name and today's date.
    static func filename(teamName: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let date = formatter.string(from: Date())
        let safe = teamName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "_")
            .filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
        let prefix = safe.isEmpty ? "Roster" : safe
        return "\(prefix)_\(date).stlroster"
    }
}
