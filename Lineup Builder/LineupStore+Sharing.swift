//
//  LineupStore+Sharing.swift
//  Lineup Builder
//
//  Merge 4: Shared Teams on the account. The calls to the sharing functions
//  in 20261124000000_shared_teams, and what the screens ask the store: this
//  coach's role, whether they can change settings or finalize, and an invite
//  link waiting to be opened.
//
//  CloudKit teams keep CloudKitManager / TeamSharingView. Nothing here applies
//  to them.
//

import Foundation
import Supabase

// MARK: - Server calls

nonisolated enum AccountSharing {

    struct InvitePreview: Decodable, Equatable, Sendable {
        let teamID: UUID
        let teamName: String
        let colorHex: String
        let ownerName: String
        let role: TeamRole
        let isMember: Bool

        enum CodingKeys: String, CodingKey {
            case teamID = "team_id", teamName = "team_name", colorHex = "color_hex"
            case ownerName = "owner_name", role, isMember = "is_member"
        }
    }

    struct LiveLink: Decodable, Equatable, Sendable {
        let token: String
        let role: TeamRole
        var url: URL { InviteLink.url(token: token) }
    }

    enum Failure: LocalizedError, Equatable {
        case proRequired, rateLimited, notOwner, offline, other(String)

        var errorDescription: String? {
            switch self {
            case .proRequired: return "Sharing a team needs Stack the Lineup Pro."
            case .rateLimited: return "Too many tries. Wait a few minutes and try again."
            case .notOwner:    return "Only the head coach can do that."
            case .offline:     return "You're offline. Try again when you're connected."
            case .other(let m): return m
            }
        }
    }

    private struct TeamParam: Encodable { let p_team: UUID }
    private struct TeamRoleParams: Encodable { let p_team: UUID; let p_role: String }
    private struct MemberParams: Encodable { let p_team: UUID; let p_user: UUID }
    private struct TokenParam: Encodable { let p_token: String }
    private struct AcceptParams: Encodable { let p_token: String; let p_name: String }

    /// Makes the team's link (replacing any live one) and returns it.
    static func createInvite(team: UUID, role: TeamRole) async throws -> LiveLink {
        try await call {
            let token: String = try await supabase.rpc("create_team_invite",
                                                       params: TeamRoleParams(p_team: team, p_role: role.rawValue))
                .execute().value
            return LiveLink(token: token, role: role)
        }
    }

    /// The live link, to send it again. Nil when the team has none.
    static func liveLink(team: UUID) async throws -> LiveLink? {
        try await call {
            let rows: [LiveLink] = try await supabase.rpc("team_invite_link", params: TeamParam(p_team: team))
                .execute().value
            return rows.first
        }
    }

    static func setRole(team: UUID, role: TeamRole) async throws {
        try await call {
            try await supabase.rpc("set_invite_role", params: TeamRoleParams(p_team: team, p_role: role.rawValue)).execute()
        }
    }

    static func remove(coach: UUID, team: UUID) async throws {
        try await call {
            try await supabase.rpc("remove_team_member", params: MemberParams(p_team: team, p_user: coach)).execute()
        }
    }

    static func stopSharing(team: UUID) async throws {
        try await call { try await supabase.rpc("stop_sharing", params: TeamParam(p_team: team)).execute() }
    }

    /// Nil for a link that's unknown, revoked, or for a deleted team.
    static func preview(token: String) async throws -> InvitePreview? {
        try await call {
            let rows: [InvitePreview] = try await supabase.rpc("team_invite_preview", params: TokenParam(p_token: token))
                .execute().value
            return rows.first
        }
    }

    /// Joins and returns the team id; nil when the link no longer works.
    static func accept(token: String, name: String) async throws -> UUID? {
        try await call {
            let id: UUID? = try await supabase.rpc("accept_team_invite", params: AcceptParams(p_token: token, p_name: name))
                .execute().value
            return id
        }
    }

    /// Turns the server's refusals into what a coach can act on.
    private static func call<T>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch let e as PostgrestError {
            switch e.hint {
            case "pro_required":  throw Failure.proRequired
            case "rate_limited":  throw Failure.rateLimited
            default: break
            }
            if e.code == "42501" { throw Failure.notOwner }
            throw Failure.other("Something went wrong. Try again in a moment.")
        } catch let e as URLError {
            _ = e
            throw Failure.offline
        }
    }
}

// MARK: - What the screens ask the store

extension LineupStore {

    nonisolated private static let teamAccessKey = "accountTeamAccess.v1"

    nonisolated static func loadTeamAccess() -> [UUID: TeamAccess] {
        guard let data = UserDefaults.standard.data(forKey: teamAccessKey),
              let decoded = try? JSONDecoder().decode([UUID: TeamAccess].self, from: data) else { return [:] }
        return decoded
    }

    func setTeamAccess(_ access: [UUID: TeamAccess]) {
        guard access != teamAccess else { return }
        teamAccess = access
        if access.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.teamAccessKey)
        } else if let data = try? JSONEncoder().encode(access) {
            UserDefaults.standard.set(data, forKey: Self.teamAccessKey)
        }
    }

    /// Nil for device-only and CloudKit teams, and before the first sync.
    func access(for teamID: UUID) -> TeamAccess? {
        accountTeamIDs.contains(teamID) ? teamAccess[teamID] : nil
    }

    /// Team settings (name, color, rules, inning count, schedule) are the
    /// owner's on a shared account team (decision 1). Everyone else's teams:
    /// whoever has them can change them, as before.
    func canChangeTeamSettings(_ teamID: UUID) -> Bool {
        access(for: teamID)?.canChangeSettings ?? true
    }

    /// The head coach's name when this coach can't finalize the open team's
    /// lineup (decision 4), or nil when they can.
    var finalizeWaitingOn: String? {
        guard let a = access(for: activeTeam.id), !a.isOwner else { return nil }
        return a.ownerDisplayName
    }

    /// Opens the team a coach just joined, once the sync has brought it down.
    /// False when it hasn't arrived (offline, or the pass failed).
    @discardableResult
    func openJoinedTeam(_ teamID: UUID) async -> Bool {
        await syncAccountAndWait()
        guard teams.contains(where: { $0.id == teamID }) else { return false }
        activeTeamID = teamID
        return true
    }
}
