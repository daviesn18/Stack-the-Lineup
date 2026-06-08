import Foundation

// MARK: - TeamImporter
// Parses a .stlteam file produced by TeamExporter.
// Pure stateless — no SwiftUI, no side effects.

enum TeamImporter {

    // MARK: - Parsed Result

    struct ImportedTeam: Identifiable {
        let id = UUID()
        let team: Team
        let exportedAt: Date
        let appVersion: String

        var exportedAtFormatted: String {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: exportedAt)
        }

        var playerCount: Int { team.players.count }
        var gameCount: Int { team.gameLogs.count }
    }

    // MARK: - Errors

    enum ImportError: LocalizedError {
        case invalidData
        case unsupportedVersion(Int)
        case decodingFailed

        var errorDescription: String? {
            switch self {
            case .invalidData:
                return "The file doesn't look like a valid team file. Make sure it was exported from Stack the Lineup."
            case .unsupportedVersion(let v):
                return "This file was created with a newer version of Stack the Lineup (format v\(v)). Update the app and try again."
            case .decodingFailed:
                return "Couldn't read the team file. It may be corrupted or from an incompatible version."
            }
        }
    }

    // MARK: - Internal Decode Types

    private struct ExportEnvelope: Decodable {
        let version: Int
        let exportedAt: String
        let appVersion: String
        let team: Team
    }

    // MARK: - Public Entry Point

    static func parse(data: Data) -> Result<ImportedTeam, ImportError> {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let envelope = try? decoder.decode(ExportEnvelope.self, from: data) else {
            return .failure(.invalidData)
        }

        guard envelope.version == 1 else {
            return .failure(.unsupportedVersion(envelope.version))
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let exportedAt = formatter.date(from: envelope.exportedAt) ?? Date()

        return .success(ImportedTeam(
            team: envelope.team,
            exportedAt: exportedAt,
            appVersion: envelope.appVersion
        ))
    }
}
