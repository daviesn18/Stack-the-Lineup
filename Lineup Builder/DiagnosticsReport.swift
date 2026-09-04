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
// see in support: per-team the record name, the participant/read-only flags, and
// whether the durable received-share ledger knows about the team — the exact
// mismatch behind "This team isn't in iCloud yet". Everything is an id, a record
// name ("team-<uuid>"), a count, a flag, or an enum. Never a name.

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

        return lines.joined(separator: "\n")
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
