import Foundation

// MARK: - TeamPreviewSummary
//
// A minimal, dependency-free reader for the `.stlteam` export envelope written by
// TeamExporter (schema v1). It is deliberately independent of the app's `Team` /
// `TeamImporter` / `Models.swift` types.
//
// A Quick Look preview extension is a separate, sandboxed target that must stay
// tiny and load fast. Pulling in Models.swift would drag the whole app graph
// (SwiftUI Color, CloudKit, PurchaseManager, MainActor-isolated stores…) into the
// appex — heavy, and prone to breaking the preview whenever the app model changes.
// Instead we read just the handful of fields the card shows, straight off the JSON
// via JSONSerialization, and tolerate anything else. If the model gains fields,
// this keeps working untouched.
//
// Envelope shape (see TeamExporter.ExportFile):
// { "version": 1, "exportedAt": "ISO8601", "appVersion": "3.x", "team": { … } }

struct TeamPreviewSummary {
    let teamName: String
    let colorHex: String
    let playerCount: Int
    let gameCount: Int          // archived game logs
    let scheduledCount: Int
    let exportedAt: Date?
    let appVersion: String?
    let formatVersion: Int?

    /// Parses just enough of the envelope to describe the file. Returns nil only
    /// when the payload isn't a JSON object at all (i.e. not one of our files).
    static func parse(_ data: Data) -> TeamPreviewSummary? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }

        let team = root["team"] as? [String: Any] ?? [:]

        let exportedAt: Date?
        if let stamp = root["exportedAt"] as? String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            exportedAt = formatter.date(from: stamp)
        } else {
            exportedAt = nil
        }

        let rawName = (team["name"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return TeamPreviewSummary(
            teamName: rawName.isEmpty ? "Untitled Team" : rawName,
            colorHex: (team["colorHex"] as? String) ?? "0000FF",
            playerCount: (team["players"] as? [Any])?.count ?? 0,
            gameCount: (team["gameLogs"] as? [Any])?.count ?? 0,
            scheduledCount: (team["scheduledGames"] as? [Any])?.count ?? 0,
            exportedAt: exportedAt,
            appVersion: root["appVersion"] as? String,
            formatVersion: root["version"] as? Int
        )
    }

    var exportedAtFormatted: String? {
        guard let exportedAt else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: exportedAt)
    }
}
