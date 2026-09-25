import Foundation
import UIKit

// MARK: - DiagnosticsReport
//
// A plain-text snapshot a coach can email to support when sharing or sync
// misbehaves. It is deliberately a HAND-CURATED snapshot, not a dump of the
// os_log stream: every field here is chosen by name, so there is no path for a
// player's or coach's name — or any other roster content — to ride along. This
// app holds rosters of minors; that constraint outranks completeness.
//
// What it carries is the state that actually diagnoses the sharing/sync bugs we
// see in support: per-team the record name, the participant/read-only flags,
// whether the durable received-share ledger knows about the team — the exact
// mismatch behind "This team isn't in iCloud yet" — and the owner-side share
// state (shared/not, link permission, joined vs. invited), the counterpart the
// report was missing when a head coach's team "isn't importing" for an assistant.
// Everything is an id, a record name ("team-<uuid>"), a count, a flag, or an
// enum. Never a name — not the coach's, not a participant's.

@MainActor
enum DiagnosticsReport {

    /// Builds the report. Async because the iCloud account status is a CloudKit
    /// round-trip — the single most useful field when a share never arrives.
    static func generate(store: LineupStore, purchaseManager: PurchaseManager) async -> String {
        let accountStatus = await CloudKitManager.shared.accountStatusDescription()

        var lines: [String] = []

        lines.append("Stack the Lineup — Diagnostics")
        lines.append("Generated: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("")

        // Environment
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build   = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        lines.append("App: \(version) (build \(build))")
        lines.append("iOS: \(UIDevice.current.systemVersion) · \(hardwareModelIdentifier())")
        lines.append("Pro: \(purchaseManager.isPro ? "yes" : "no")")
        lines.append("iCloud account: \(accountStatus)")
        lines.append("")

        // Teams — no names, only the fields sharing/sync bugs turn on.
        lines.append("Teams (\(store.teams.count)):")
        for (i, team) in store.teams.enumerated() {
            let active = team.id == store.activeTeamID ? " [ACTIVE]" : ""
            lines.append("  #\(i + 1)\(active)")
            lines.append("     id: \(team.id.uuidString)")
            lines.append("     record: \(team.ckRecordName ?? "none")")
            lines.append("     sharedParticipant: \(team.isSharedParticipant)   readOnly: \(team.isReadOnly)   inReceivedLedger: \(store.isReceivedShare(team))")
            lines.append("     players: \(team.players.count)   games: \(team.gameLogs.count)")
            lines.append("     \(await shareStateLine(for: team))")
        }
        lines.append("")

        // Durable ledgers and pending queues — the state that outlives a launch.
        lines.append("Received-share ledger (\(store.receivedShareRecordNames.count)):")
        for name in store.receivedShareRecordNames.sorted() {
            lines.append("  - \(name)")
        }

        lines.append("Tombstones (\(store.tombstones.entries.count)):")
        for entry in store.tombstones.entries {
            lines.append("  - team \(entry.teamID.uuidString) record \(entry.recordName ?? "none")")
        }

        lines.append("Declined remote deletions: \(store.declinedRemoteDeletions.count)")
        lines.append("Pending remote deletions: \(store.pendingRemoteDeletions.count)")
        lines.append("Pending share revocations: \(store.pendingShareRevocations.count)")
        lines.append("Active team id: \(store.activeTeamID?.uuidString ?? "none")")

        // The most recent share acceptance. This is the field that turns an
        // assistant's "I tapped Join and nothing happened" from a guess into a
        // fact: a FAILED line with a CKError-derived reason means the accept never
        // took (so the received-share ledger above will be empty for good reason),
        // while an "ok" line means the accept worked and any missing team is a
        // surfacing problem, not an acceptance one. detail is name-free.
        if let accept = TeamStorage.loadLastShareAccept() {
            let when   = ISO8601DateFormatter().string(from: accept.at)
            let status = accept.succeeded ? "ok" : "FAILED — \(accept.detail)"
            let root   = accept.rootRecordName.map { " root \($0)" } ?? ""
            lines.append("Last share accept: \(status) at \(when)\(root)")
        } else {
            lines.append("Last share accept: none recorded")
        }

        return lines.joined(separator: "\n")
    }

    /// A name-free, one-line summary of a team's CloudKit share state.
    ///
    /// This is the field the owner's report was missing when a shared team
    /// "isn't importing": the receiver flags above are read from the team blob and
    /// only ever describe a team this device *received*. Nothing told us, from the
    /// head coach's phone, whether the team they meant to share is actually shared,
    /// at what link permission, and how many coaches have joined versus been
    /// invited. This asks CloudKit that directly, per team.
    ///
    /// Privacy holds the same line as the rest of the report. `TeamShareInfo`
    /// carries participant and owner *names, emails, and phone numbers* — NONE of
    /// them are printed here. Only the state enum, the link permission, and counts.
    /// A CloudKit round-trip per team, so this runs only on the manual export.
    private static func shareStateLine(for team: Team) async -> String {
        let info: TeamShareInfo
        do {
            info = try await CloudKitManager.shared.shareInfo(for: team)
        } catch {
            // friendlyMessage is fixed strings / record names only — never a person.
            return "share: lookup failed (\(CloudKitManager.friendlyMessage(for: error)))"
        }

        switch info.state {
        case .notSynced(let stale):
            return "share: notSynced (staleRecordName: \(stale))"
        case .notShared:
            return "share: notShared"
        case .shared:
            let joined = info.acceptedCount
            let total  = info.participants.count
            let url    = info.url != nil ? "yes" : "none"
            let base   = "share: shared   link: \(info.linkPermission.rawValue)   joined: \(joined)/\(total)   url: \(url)"
            // A public link (the Messages "share link" flow) grants access through
            // the public permission without adding a participant, so joined/total
            // stays 0/0 even when coaches have joined. Say so, or the count reads
            // as "nobody accepted" when the share is actually working.
            return info.isPublicLink ? base + "   (public link — joiners not counted here)" : base
        case .participant:
            return "share: participant   myPermission: \(info.myPermission.rawValue)"
        }
    }

    /// The hardware model identifier (e.g. "iPhone15,2"), which helps reproduce
    /// device-specific issues. Deliberately NOT `UIDevice.current.name`, which is
    /// user-set and routinely personal ("Nick's iPhone").
    private static func hardwareModelIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafeBytes(of: &systemInfo.machine) { raw -> String in
            let bytes = raw.prefix { $0 != 0 }
            return String(decoding: bytes, as: UTF8.self)
        }
        return machine.isEmpty ? "unknown" : machine
    }
}
