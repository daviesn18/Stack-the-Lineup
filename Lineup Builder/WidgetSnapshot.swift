import Foundation
import SwiftUI

/// Lightweight snapshot of the active team's current lineup state.
/// Written by the main app on every save(); read by the widget extension.
/// Add this file to BOTH the main app target and the STLWidget extension target.
struct WidgetSnapshot: Codable {
    var teamName: String
    var teamColorHex: String
    var lineupStatus: String        // "draft" | "finalized"
    var activePlayerCount: Int
    var totalInnings: Int
    var filledInningCount: Int      // innings where all field positions are assigned
    var gameDate: Date
    var opponent: String
    var isToday: Bool               // lineup.gameDate falls on calendar today
    var nextGameDate: Date?         // first future scheduled game when isToday is false
    var nextGameOpponent: String?
    var hasRoster: Bool             // team has at least one player
    var updatedAt: Date

    // MARK: - Shared Constants

    static let appGroupID  = "group.com.nickdavies.LineupBuilder"
    static let defaultsKey = "stl_widget_snapshot"

    // MARK: - Load from App Group

    static func load() -> WidgetSnapshot? {
        guard
            let defaults = UserDefaults(suiteName: appGroupID),
            let data     = defaults.data(forKey: defaultsKey),
            let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
        else { return nil }
        return snapshot
    }

    // MARK: - Derived UI Helpers

    /// Resolves team color hex to a SwiftUI Color without depending on the
    /// Color(hex:) extension in Models.swift, which is not in the widget target.
    var accentColor: Color {
        var h = teamColorHex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h = String(h.dropFirst()) }
        guard h.count == 6, let iv = UInt64(h, radix: 16) else { return .blue }
        return Color(
            red:   Double((iv & 0xFF0000) >> 16) / 255.0,
            green: Double((iv & 0x00FF00) >> 8)  / 255.0,
            blue:  Double(iv & 0x0000FF)          / 255.0
        )
    }

    var displayStatus: LineupDisplayStatus {
        lineupStatus == "finalized" ? .finalized : .draft
    }
}

/// Decoded lineup status for widget views.
/// Named differently from LineupStatus in Models.swift to avoid collision in the main target.
enum LineupDisplayStatus {
    case draft, finalized
    var label: String { self == .finalized ? "Finalized" : "Draft" }
}
