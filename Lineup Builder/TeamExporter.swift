import Foundation

// MARK: - TeamExporter
// Exports a Team to the .stlteam JSON format (v1).
// Pure stateless — no SwiftUI, no side effects.
// The active lineup is excluded; the importing device starts with a fresh Lineup().
//
// Schema v1:
// {
//   "version": 1,
//   "exportedAt": "ISO8601 date string",
//   "appVersion": "3.0",
//   "team": { /* Team struct with lineup reset to Lineup() */ }
// }

enum TeamExporter {

    // MARK: - Codable Schema

    private struct ExportFile: Encodable {
        let version: Int
        let exportedAt: String
        let appVersion: String
        let team: Team
    }

    // MARK: - Public Entry Point

    /// Encodes the given team to .stlteam JSON data.
    /// The active lineup is excluded — reset to a fresh Lineup() before encoding.
    /// Returns nil only if JSON encoding fails (practically impossible).
    static func export(team: Team) -> Data? {
        var exportableTeam = team
        exportableTeam.lineup = Lineup()

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "3.0"

        let file = ExportFile(
            version: 1,
            exportedAt: formatter.string(from: Date()),
            appVersion: appVersion,
            team: exportableTeam
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
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
        let prefix = safe.isEmpty ? "Team" : safe
        return "\(prefix)_\(date).stlteam"
    }
}
