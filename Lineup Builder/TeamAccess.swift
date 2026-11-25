//
//  TeamAccess.swift
//  Lineup Builder
//
//  Merge 4: who this coach is on an account team, and who else coaches it.
//
//  The server decides access (can_read_team / can_edit_team, 20261124000000_
//  shared_teams). The app only mirrors it so it can show the right controls:
//  a viewer's team is read-only, only the owner changes team settings or
//  finalizes, and the sharing screen lists the coaches. Pure, so it's
//  unit-tested; the sync fills it in on every pass.
//

import Foundation

nonisolated enum TeamRole: String, Codable, Sendable, CaseIterable {
    case owner, editor, viewer
}

/// A coach on a shared team, as the owner and other coaches see them.
nonisolated struct TeamCoach: Codable, Hashable, Sendable, Identifiable {
    var userID: UUID
    var role: TeamRole
    /// Their name when they joined. May be empty.
    var name: String
    var joinedAt: Date?

    var id: UUID { userID }
    var displayName: String {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? "Coach" : n
    }
}

nonisolated struct TeamAccess: Codable, Hashable, Sendable {
    /// This coach's role on the team.
    var role: TeamRole
    var ownerID: UUID
    /// The head coach's name: the team's coach name, which is the owner's.
    var ownerName: String
    /// Everyone who joined (never the owner), oldest first.
    var coaches: [TeamCoach]

    var isOwner: Bool { role == .owner }
    var isShared: Bool { !coaches.isEmpty }
    /// Team settings (name, color, rules, inning count, schedule) are the owner's (decision 1).
    var canChangeSettings: Bool { isOwner }
    /// Roster, positions and lineups.
    var canEdit: Bool { role != .viewer }

    var ownerDisplayName: String {
        let n = ownerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? "the head coach" : n
    }

    /// This coach's access from the server's rows. Nil when they're neither the
    /// owner nor a member, which RLS shouldn't let happen for a fetched team.
    static func resolve(ownerID: UUID, ownerName: String, coaches: [TeamCoach], me: UUID) -> TeamAccess? {
        let sorted = coaches.sorted {
            ($0.joinedAt ?? .distantPast, $0.userID.uuidString) < ($1.joinedAt ?? .distantPast, $1.userID.uuidString)
        }
        let role: TeamRole
        if ownerID == me {
            role = .owner
        } else if let mine = coaches.first(where: { $0.userID == me }) {
            role = mine.role
        } else {
            return nil
        }
        return TeamAccess(role: role, ownerID: ownerID, ownerName: ownerName, coaches: sorted)
    }
}

/// An invite link: https://app.stackthelineup.com/join/<token>, or the app's
/// own stackthelineup://join/<token> (for testing on a simulator).
nonisolated enum InviteLink {
    static let host = "app.stackthelineup.com"

    static func url(token: String) -> URL {
        URL(string: "https://\(host)/join/\(token)")!
    }

    /// The token in an invite link, or nil for any other URL.
    static func token(from url: URL) -> String? {
        let parts: [String]
        switch url.scheme?.lowercased() {
        case "https" where url.host?.lowercased() == host:
            parts = url.pathComponents.filter { $0 != "/" }
        case "stackthelineup":
            parts = ([url.host ?? ""] + url.pathComponents.filter { $0 != "/" }).filter { !$0.isEmpty }
        default:
            return nil
        }
        guard parts.count == 2, parts[0].lowercased() == "join" else { return nil }
        return token(fromToken: parts[1])
    }

    /// A bare token, lower-cased; nil unless it's 64 hex characters, as the server makes them.
    static func token(fromToken token: String) -> String? {
        guard token.count == 64, token.allSatisfy(\.isHexDigit) else { return nil }
        return token.lowercased()
    }
}
