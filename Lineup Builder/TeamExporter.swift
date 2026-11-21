import Foundation
import os

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

// MARK: - Fresh IDs for an imported copy (Merge 1)
//
// Every row of a team in the account (players, scheduled games, templates,
// template locks, lineups, game logs) is keyed by its own id across the whole
// database, not per team. A .stlteam keeps those ids, so a file imported as a
// new team, alongside the team it came from or a second time, would push rows
// whose ids already belong to another team, and the push fails every pass.
//
// So an imported copy gets fresh ids: the value of every object's own "id" is
// replaced, and so is every other occurrence of that same value (batting
// orders, absences, per-game lineup keys), keeping the team's internal
// references intact. Values that aren't some object's id, such as a calendar
// feed's icalUID, are left alone.

extension Team {
    nonisolated func withFreshIDs() -> Team {
        do {
            let data = try JSONEncoder().encode(self)
            let object = try JSONSerialization.jsonObject(with: data)
            var mapping: [String: String] = [:]
            Self.collectIDs(in: object, into: &mapping)
            let remapped = Self.replacing(in: object, mapping: mapping)
            let out = try JSONSerialization.data(withJSONObject: remapped)
            return try JSONDecoder().decode(Team.self, from: out)
        } catch {
            // Unreachable in practice (it round-trips its own encoding). The
            // copy keeps its ids, and the push reports the collision if any.
            Log.sync.error("Couldn't give an imported team fresh ids: \(error.localizedDescription, privacy: .public)")
            var copy = self
            copy.id = UUID()
            return copy
        }
    }

    private nonisolated static func collectIDs(in object: Any, into mapping: inout [String: String]) {
        if let dict = object as? [String: Any] {
            if let id = dict["id"] as? String, UUID(uuidString: id) != nil, mapping[id.uppercased()] == nil {
                mapping[id.uppercased()] = UUID().uuidString
            }
            for value in dict.values { collectIDs(in: value, into: &mapping) }
        } else if let array = object as? [Any] {
            for value in array { collectIDs(in: value, into: &mapping) }
        }
    }

    private nonisolated static func replacing(in object: Any, mapping: [String: String]) -> Any {
        if let string = object as? String {
            return mapping[string.uppercased()] ?? string
        } else if let dict = object as? [String: Any] {
            var out: [String: Any] = [:]
            for (key, value) in dict {
                out[mapping[key.uppercased()] ?? key] = replacing(in: value, mapping: mapping)
            }
            return out
        } else if let array = object as? [Any] {
            return array.map { replacing(in: $0, mapping: mapping) }
        }
        return object
    }
}
