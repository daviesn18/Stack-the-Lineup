import Foundation

// MARK: - ICalParser
// Pure stateless parser for .ics / iCalendar files (RFC 5545).
// No SwiftUI, no side effects, no network. Easily unit-testable.
//
// Handles:
//   - Line folding (continuation lines starting with space/tab)
//   - DTSTART in UTC (20260510T140000Z)
//   - DTSTART with TZID param (DTSTART;TZID=America/New_York:20260510T100000)
//   - DTSTART as date-only (20260510) — treated as midnight local time
//   - SUMMARY opponent parsing: "Yankees @ Red Sox", "Yankees vs Red Sox",
//     "Yankees vs. Red Sox", "Yankees versus Red Sox", "@ Red Sox",
//     "vs Red Sox". Falls back to raw SUMMARY if no pattern matches.
//   - STATUS:CANCELLED events — included with isCancelled = true
//   - Multiple VEVENTs in one file

enum ICalParser {

    // MARK: - Public Types

    struct ParsedEvent {
        let uid: String
        let date: Date
        let opponent: String?
        let location: String?
        let rawSummary: String
        let isCancelled: Bool
    }

    enum ParseError: Error, LocalizedError {
        case emptyFile
        case noEventsFound
        case unreadableData

        var errorDescription: String? {
            switch self {
            case .emptyFile:        return "The calendar file is empty."
            case .noEventsFound:    return "No games were found in this calendar file."
            case .unreadableData:   return "Couldn't read the calendar file."
            }
        }
    }

    // MARK: - Public Entry Point

    static func parse(data: Data) -> Result<[ParsedEvent], ParseError> {
        guard let text = String(data: data, encoding: .utf8)
                      ?? String(data: data, encoding: .isoLatin1) else {
            return .failure(.unreadableData)
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.emptyFile) }

        let unfolded = unfold(trimmed)
        let events = extractEvents(from: unfolded)
        guard !events.isEmpty else { return .failure(.noEventsFound) }
        return .success(events)
    }

    // MARK: - Line Unfolding (RFC 5545 §3.1)
    // A long property value may be split across multiple lines.
    // Continuation lines start with a single space or tab character.

    private static func unfold(_ text: String) -> String {
        // Replace CRLF + (space|tab) and LF + (space|tab) with nothing
        var result = text
        result = result.replacingOccurrences(of: "\r\n ", with: "")
        result = result.replacingOccurrences(of: "\r\n\t", with: "")
        result = result.replacingOccurrences(of: "\n ", with: "")
        result = result.replacingOccurrences(of: "\n\t", with: "")
        return result
    }

    // MARK: - Event Extraction

    private static func extractEvents(from text: String) -> [ParsedEvent] {
        var events: [ParsedEvent] = []
        let lines = text.components(separatedBy: .newlines)

        var inEvent = false
        var properties: [String: String] = [:]

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line == "BEGIN:VEVENT" {
                inEvent = true
                properties = [:]
            } else if line == "END:VEVENT" {
                inEvent = false
                if let event = buildEvent(from: properties) {
                    events.append(event)
                }
            } else if inEvent, let (key, value) = parseLine(line) {
                // For properties with parameters (e.g. DTSTART;TZID=...) we
                // store under both the full key and the base key so lookups work.
                properties[key] = value
                let baseKey = key.components(separatedBy: ";").first ?? key
                if baseKey != key { properties[baseKey] = value }
            }
        }

        return events
    }

    // MARK: - Line Parsing

    private static func parseLine(_ line: String) -> (key: String, value: String)? {
        guard let colonIdx = line.firstIndex(of: ":") else { return nil }
        let key = String(line[line.startIndex..<colonIdx]).uppercased()
        let value = String(line[line.index(after: colonIdx)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !value.isEmpty else { return nil }
        return (key, value)
    }

    // MARK: - Event Builder

    private static func buildEvent(from props: [String: String]) -> ParsedEvent? {
        guard let uid = props["UID"], !uid.isEmpty else { return nil }

        // --- Date parsing ---
        // Try DTSTART with TZID parameter first, then plain DTSTART
        let dtstart = props.first(where: { $0.key.hasPrefix("DTSTART;TZID=") })?.value
                   ?? props["DTSTART"]
        guard let dtstart, let date = parseDate(dtstart, tzid: tzid(from: props)) else {
            return nil
        }

        let rawSummary = unescape(props["SUMMARY"] ?? "")
        let location   = props["LOCATION"].map(unescape)?.nonEmpty
        let cancelled  = props["STATUS"]?.uppercased() == "CANCELLED"
        let opponent   = parseOpponent(from: rawSummary)

        return ParsedEvent(
            uid: uid,
            date: date,
            opponent: opponent,
            location: location,
            rawSummary: rawSummary,
            isCancelled: cancelled
        )
    }

    // MARK: - TZID Extraction

    private static func tzid(from props: [String: String]) -> TimeZone? {
        // Find the DTSTART;TZID=... key and extract the timezone identifier
        guard let key = props.keys.first(where: { $0.hasPrefix("DTSTART;TZID=") }) else {
            return nil
        }
        let tzString = String(key.dropFirst("DTSTART;TZID=".count))
        return TimeZone(identifier: tzString)
    }

    // MARK: - Date Parsing

    private static func parseDate(_ value: String, tzid: TimeZone?) -> Date? {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)

        // UTC datetime: 20260510T140000Z
        if v.hasSuffix("Z"), v.count >= 15 {
            return parseDateTime(String(v.dropLast()), timeZone: TimeZone(identifier: "UTC")!)
        }

        // Local datetime with TZID: 20260510T100000
        if v.contains("T"), v.count >= 15 {
            return parseDateTime(v, timeZone: tzid ?? TimeZone.current)
        }

        // Date-only: 20260510 → midnight local time
        if v.count == 8 {
            return parseDateOnly(v, timeZone: tzid ?? TimeZone.current)
        }

        return nil
    }

    private static func parseDateTime(_ value: String, timeZone: TimeZone) -> Date? {
        let s = value
        guard s.count >= 15 else { return nil }
        // Format: YYYYMMDDTHHMMSS
        var comps = DateComponents()
        comps.timeZone = timeZone
        comps.year     = Int(s.prefix(4))
        comps.month    = Int(s.dropFirst(4).prefix(2))
        comps.day      = Int(s.dropFirst(6).prefix(2))
        // Skip the "T"
        comps.hour     = Int(s.dropFirst(9).prefix(2))
        comps.minute   = Int(s.dropFirst(11).prefix(2))
        comps.second   = Int(s.dropFirst(13).prefix(2))
        return Calendar(identifier: .gregorian).date(from: comps)
    }

    private static func parseDateOnly(_ value: String, timeZone: TimeZone) -> Date? {
        guard value.count == 8 else { return nil }
        var comps = DateComponents()
        comps.timeZone = timeZone
        comps.year   = Int(value.prefix(4))
        comps.month  = Int(value.dropFirst(4).prefix(2))
        comps.day    = Int(value.dropFirst(6).prefix(2))
        comps.hour   = 0
        comps.minute = 0
        comps.second = 0
        return Calendar(identifier: .gregorian).date(from: comps)
    }

    // MARK: - Practice Filter

    /// Keywords used to identify practice, clinic, and non-game events in a
    /// calendar SUMMARY. Shared across ScheduleImportView, SchedulePickerView,
    /// and LineupView so the filter stays consistent everywhere.
    static let practiceKeywords: [String] = [
        "practice", "batting practice", "bp", "team practice",
        "infield", "skills", "clinic", "workout", "scrimmage",
        "tryout", "try-out", "warm-up", "warmup"
    ]

    /// Returns true if the given SUMMARY string looks like a practice or
    /// non-game event rather than a scheduled game.
    static func isPractice(_ summary: String) -> Bool {
        let lower = summary.lowercased()
        return practiceKeywords.contains(where: { lower.contains($0) })
    }

    // MARK: - Opponent Parsing

    /// Extracts opponent name from SUMMARY using common baseball game patterns.
    /// Examples:
    ///   "Yankees @ Red Sox"      → "Red Sox"
    ///   "@ Red Sox"              → "Red Sox"
    ///   "Yankees vs Red Sox"     → "Red Sox"
    ///   "Yankees vs. Red Sox"    → "Red Sox"
    ///   "Yankees versus Red Sox" → "Red Sox"
    ///   "Red Sox Game"           → nil (no pattern found, return nil)
    static func parseOpponent(from summary: String) -> String? {
        let s = summary.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }

        // Patterns in priority order
        let patterns: [String] = ["@", " vs. ", " vs ", " versus "]

        for pattern in patterns {
            if let range = s.range(of: pattern, options: .caseInsensitive) {
                let after = String(s[range.upperBound...])
                    .trimmingCharacters(in: .whitespaces)
                // "@" at the very start with nothing before it — the whole team is the opponent
                if pattern == "@" && s.hasPrefix("@") {
                    return after.nonEmpty
                }
                // Pattern found in middle — everything after is the opponent
                if !after.isEmpty {
                    return after.nonEmpty
                }
            }
        }

        return nil
    }

    // MARK: - iCal String Unescaping

    /// RFC 5545: TEXT values escape commas, semicolons, backslashes, and newlines.
    private static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\,", with: ",")
         .replacingOccurrences(of: "\\;", with: ";")
         .replacingOccurrences(of: "\\n", with: "\n")
         .replacingOccurrences(of: "\\N", with: "\n")
         .replacingOccurrences(of: "\\\\", with: "\\")
    }
}

// MARK: - Helpers

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
