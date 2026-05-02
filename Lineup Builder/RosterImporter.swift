import Foundation

// MARK: - RosterImporter
// Pure parsing logic. No SwiftUI, no side effects, no analytics.
// Easily unit-testable: pass Data + filename, get a Result back.
//
// Supported formats:
//   .csv         — GameChanger Stats export (most common path) and any
//                   roster CSV with first/last/jersey columns.
//   .stlroster   — Stack the Lineup native export (JSON; defined in next task).
//
// CSV parsing handles:
//   - RFC 4180 quoted fields ("Smith, Jr." stays one cell)
//   - Multi-row preambles (GameChanger Stats CSVs have a "Batting/Pitching/
//     Fielding" group row above the actual headers)
//   - Mixed line endings (\r\n, \n, \r)
//   - "Totals" summary row at the bottom
//   - Generic CSVs with First Name + Last Name columns or a single Name column

enum RosterImporter {

    // MARK: - Public Types

    struct ImportedPlayer: Identifiable, Hashable {
        let id = UUID()
        let firstName: String
        let lastName: String
        let jerseyNumber: String
        /// Only present when importing from a .stlroster file
        let leagueAge: Int?
        /// Only present when importing from a .stlroster file.
        /// Keys are FieldPosition.displayName, values are PositionPreferenceTier.rawValue
        let positionPreferences: [String: String]

        init(firstName: String, lastName: String, jerseyNumber: String,
             leagueAge: Int? = nil, positionPreferences: [String: String] = [:]) {
            self.firstName = firstName
            self.lastName = lastName
            self.jerseyNumber = jerseyNumber
            self.leagueAge = leagueAge
            self.positionPreferences = positionPreferences
        }

        var displayName: String {
            let trimmed = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? "(unnamed)" : trimmed
        }

        /// Lowercased, whitespace-trimmed full name. Used for duplicate detection.
        var matchKey: String {
            "\(firstName) \(lastName)"
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
        }
    }

    enum ImportError: Error, LocalizedError {
        case unreadableFile
        case emptyFile
        case noValidPlayersFound
        case malformedHeader
        case unsupportedExtension(String)

        var errorDescription: String? {
            switch self {
            case .unreadableFile:
                return "Couldn't read the file. It may be corrupted."
            case .emptyFile:
                return "The file is empty."
            case .noValidPlayersFound:
                return "No players were found in this file. Check that it has player names."
            case .malformedHeader:
                return "Couldn't find a column for player names. The file may be in an unexpected format."
            case .unsupportedExtension(let ext):
                return "Files with the \(ext) extension aren't supported. Use a .csv or .stlroster file."
            }
        }
    }

    // MARK: - Public Entry Point

    static func parse(data: Data, filename: String) -> Result<[ImportedPlayer], ImportError> {
        let ext = (filename as NSString).pathExtension.lowercased()

        switch ext {
        case "csv":
            return parseCSV(data: data)
        case "stlroster":
            return parseSTLRoster(data: data)
        case "":
            let csvResult = parseCSV(data: data)
            if case .success = csvResult { return csvResult }
            return parseSTLRoster(data: data)
        default:
            return .failure(.unsupportedExtension(ext))
        }
    }

    // MARK: - CSV Parsing

    private static func parseCSV(data: Data) -> Result<[ImportedPlayer], ImportError> {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            return .failure(.unreadableFile)
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.emptyFile) }

        let rows = splitCSV(text: text)
        guard !rows.isEmpty else { return .failure(.emptyFile) }

        guard let headerIndex = findHeaderRowIndex(in: rows) else {
            return .failure(.malformedHeader)
        }

        let header = rows[headerIndex]
        guard let mapping = ColumnMapping.resolve(from: header) else {
            return .failure(.malformedHeader)
        }

        var imported: [ImportedPlayer] = []
        for rowIndex in (headerIndex + 1)..<rows.count {
            let row = rows[rowIndex]
            guard !isEmptyRow(row) else { continue }
            guard !isTotalsRow(row) else { continue }
            if let player = mapping.player(from: row) {
                imported.append(player)
            }
        }

        guard !imported.isEmpty else { return .failure(.noValidPlayersFound) }
        return .success(imported)
    }

    // MARK: - .stlroster Parsing (v1 schema)

    private struct STLRosterFile: Decodable {
        struct PlayerEntry: Decodable {
            let name: String?
            let firstName: String?
            let lastName: String?
            let jerseyNumber: String?
            let leagueAge: Int?
            let positionPreferences: [String: String]?
        }
        let version: Int?
        let teamName: String?
        let players: [PlayerEntry]
    }

    private static func parseSTLRoster(data: Data) -> Result<[ImportedPlayer], ImportError> {
        do {
            let file = try JSONDecoder().decode(STLRosterFile.self, from: data)
            let imported: [ImportedPlayer] = file.players.compactMap { entry in
                let first: String
                let last: String
                if let f = entry.firstName, let l = entry.lastName {
                    first = f.trimmingCharacters(in: .whitespaces)
                    last = l.trimmingCharacters(in: .whitespaces)
                } else if let combined = entry.name {
                    let split = splitFullName(combined)
                    first = split.first
                    last = split.last
                } else {
                    return nil
                }
                guard !first.isEmpty || !last.isEmpty else { return nil }
                return ImportedPlayer(
                    firstName: first,
                    lastName: last,
                    jerseyNumber: (entry.jerseyNumber ?? "").trimmingCharacters(in: .whitespaces),
                    leagueAge: entry.leagueAge,
                    positionPreferences: entry.positionPreferences ?? [:]
                )
            }
            guard !imported.isEmpty else { return .failure(.noValidPlayersFound) }
            return .success(imported)
        } catch {
            return .failure(.unreadableFile)
        }
    }

    // MARK: - CSV Tokenization (RFC 4180-ish)

    static func splitCSV(text: String) -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentCell = ""
        var inQuotes = false

        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let c = chars[i]

            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" {
                        currentCell.append("\"")
                        i += 2
                        continue
                    }
                    inQuotes = false
                    i += 1
                    continue
                }
                currentCell.append(c)
                i += 1
                continue
            }

            if c == "\"" {
                inQuotes = true
                i += 1
                continue
            }
            if c == "," {
                currentRow.append(currentCell)
                currentCell = ""
                i += 1
                continue
            }
            if c == "\n" || c == "\r" {
                currentRow.append(currentCell)
                currentCell = ""
                rows.append(currentRow)
                currentRow = []
                if c == "\r" && i + 1 < chars.count && chars[i + 1] == "\n" {
                    i += 2
                } else {
                    i += 1
                }
                continue
            }
            currentCell.append(c)
            i += 1
        }

        if !currentCell.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentCell)
            rows.append(currentRow)
        }

        return rows
    }

    // MARK: - Header Detection

    private static let headerKeywords: Set<String> = [
        "number", "#", "jersey", "jersey number", "jersey#",
        "first", "firstname", "first name",
        "last", "lastname", "last name", "surname",
        "name", "player", "player name", "full name"
    ]

    private static func findHeaderRowIndex(in rows: [[String]]) -> Int? {
        for (index, row) in rows.enumerated() {
            let cellsToCheck = row.prefix(5).map { normalize($0) }
            let hasKnownKeyword = cellsToCheck.contains { headerKeywords.contains($0) }
            if hasKnownKeyword { return index }
        }
        return nil
    }

    // MARK: - Column Mapping

    private struct ColumnMapping {
        let firstNameIndex: Int?
        let lastNameIndex: Int?
        let combinedNameIndex: Int?
        let jerseyIndex: Int?

        static func resolve(from header: [String]) -> ColumnMapping? {
            var firstIdx: Int?
            var lastIdx: Int?
            var combinedIdx: Int?
            var jerseyIdx: Int?

            for (i, raw) in header.enumerated() {
                let cell = normalize(raw)
                switch cell {
                case "first", "firstname", "first name":
                    if firstIdx == nil { firstIdx = i }
                case "last", "lastname", "last name", "surname":
                    if lastIdx == nil { lastIdx = i }
                case "name", "player", "player name", "full name":
                    if combinedIdx == nil { combinedIdx = i }
                case "number", "#", "jersey", "jersey number", "jersey#":
                    if jerseyIdx == nil { jerseyIdx = i }
                default:
                    break
                }
            }

            if firstIdx != nil && lastIdx != nil {
                return ColumnMapping(firstNameIndex: firstIdx, lastNameIndex: lastIdx, combinedNameIndex: nil, jerseyIndex: jerseyIdx)
            }
            if combinedIdx != nil {
                return ColumnMapping(firstNameIndex: nil, lastNameIndex: nil, combinedNameIndex: combinedIdx, jerseyIndex: jerseyIdx)
            }
            return nil
        }

        func player(from row: [String]) -> ImportedPlayer? {
            let first: String
            let last: String

            if let firstIdx = firstNameIndex, let lastIdx = lastNameIndex {
                first = cell(row, firstIdx)
                last = cell(row, lastIdx)
            } else if let combinedIdx = combinedNameIndex {
                let split = splitFullName(cell(row, combinedIdx))
                first = split.first
                last = split.last
            } else {
                return nil
            }

            guard !(first.isEmpty && last.isEmpty) else { return nil }

            let jersey = jerseyIndex.map { cell(row, $0) } ?? ""
            return ImportedPlayer(firstName: first, lastName: last, jerseyNumber: jersey)
        }

        private func cell(_ row: [String], _ index: Int) -> String {
            guard index < row.count else { return "" }
            return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    // MARK: - Row Filters

    private static func isEmptyRow(_ row: [String]) -> Bool {
        row.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private static func isTotalsRow(_ row: [String]) -> Bool {
        guard let first = row.first?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else { return false }
        return first == "totals" || first == "total"
    }

    // MARK: - Helpers

    private static func normalize(_ s: String) -> String {
        let lowered = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lowered.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private static func splitFullName(_ full: String) -> (first: String, last: String) {
        let trimmed = full.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        if parts.count <= 1 { return (first: trimmed, last: "") }
        let last = parts.last ?? ""
        let first = parts.dropLast().joined(separator: " ")
        return (first: first, last: last)
    }
}
