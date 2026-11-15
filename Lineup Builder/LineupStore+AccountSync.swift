//
//  LineupStore+AccountSync.swift
//  Lineup Builder
//
//  Merge 0b: how LineupStore keeps account teams in step with Supabase.
//
//  Account teams are edited exactly like any other team: the ~70 mutators call
//  save(), which writes the account file at once and, for an account team,
//  schedules a sync pass 2 seconds after the last edit (instead of a CloudKit
//  push). A pass also runs on foreground and on sign-in, and is flushed when
//  the app leaves the foreground.
//
//  The pass itself runs in SupabaseTeamSync, off the main actor. The coach can
//  keep editing while it runs; `applySyncOutcome` folds any such edits onto
//  the merged team rather than letting the merge overwrite them, and schedules
//  another pass to send them.
//

import Combine
import Foundation
import Network
import os
import Supabase
import UIKit

extension LineupStore {

    // MARK: - Account changes

    /// Follows the signed-in account. Called once, from init.
    func startFollowingAccount() {
        AccountNetworkWatcher.shared.onReconnect = { [weak self] in
            guard let self, self.accountSync != nil else { return }
            Log.sync.notice("Back online; syncing account teams")
            self.syncAccount()
        }
        accountObserver = AccountManager.shared.$user
            .map { $0?.id.uuidString.lowercased() }
            .removeDuplicates()
            .sink { [weak self] userID in
                guard let userID else { return }
                self?.accountDidSignIn(userID)
            }
    }

    /// A coach is signed in (at launch, or just now). Signing out is not
    /// handled here: only an explicit sign-out may remove account teams from
    /// the device (`AccountManager.signOut`), never a session that lapses.
    func accountDidSignIn(_ userID: String) {
        if AccountTeamStore.signedInAccount() != userID {
            AccountTeamStore.setSignedInAccount(userID)
            // Show this account's teams (an empty folder on a first sign-in;
            // the sync pass below brings the account's teams down).
            load()
        }
        if accountSync == nil, let store = AccountTeamStore.current() {
            accountSync = SupabaseTeamSync(store: store)
        }
        syncAccount()
    }

    /// After an explicit sign-out or account deletion: the account's teams
    /// leave this device and its folder is deleted (a security gate item: no
    /// account data stays behind). Device-only and CloudKit teams stay.
    func removeAccountFromDevice() async {
        let store = AccountTeamStore.current()
        await accountSync?.close()
        accountSync = nil
        accountSyncStatus = nil
        accountSyncDebouncer.flush()   // nothing to send any more; clears the timer
        AccountTeamStore.setSignedInAccount(nil)

        let ids = accountTeamIDs
        accountTeamIDs = []
        accountEditCounts = [:]
        teams.removeAll { ids.contains($0.id) }
        if let id = activeTeamID, ids.contains(id) { activeTeamID = teams.first?.id }
        do { try store?.wipe() } catch {
            Log.storage.error("Couldn't delete the account folder: \(error.localizedDescription, privacy: .public)")
        }
        Log.sync.notice("Removed \(ids.count, privacy: .public) account team(s) from this device")

        if teams.isEmpty {
            // Every team was in the account. Start fresh, as on a first launch.
            load()
        } else {
            saveLocalOnly()
        }
    }

    /// Account teams with changes the server doesn't have yet, plus team
    /// deletes still waiting. What sign-out warns about.
    func accountPendingCount() async -> Int {
        guard let sync = accountSync else { return 0 }
        let ids = accountTeamIDs
        return await sync.pendingCount(teams: teams.filter { ids.contains($0.id) })
    }

    /// Name-free lines for the diagnostics report.
    func accountDiagnosticsLines() async -> [String] {
        guard AccountTeamStore.signedInAccount() != nil else { return ["Account teams: signed out"] }
        var lines = ["Account teams (\(accountTeamIDs.count)): \(accountSyncStatus.map(AccountSyncText.line) ?? "not synced yet")"]
        lines.append("  pending changes: \(await accountPendingCount())   conflicts settled: \(accountSyncStatus?.conflictCount ?? 0)")
        if let sync = accountSync { lines += await sync.diagnostics() }
        return lines
    }

    #if DEBUG
    /// Signed in, and the open team isn't an account team yet.
    var canDebugMoveActiveTeamToAccount: Bool {
        accountSync != nil && !accountTeamIDs.contains(activeTeam.id)
    }

    /// Debug builds only: makes the open team an account team, so account
    /// sync can be tested on staging before Merge 1 decides which teams move.
    /// It leaves CloudKit: no record name, no sharing.
    func debugMoveActiveTeamToAccount() {
        guard canDebugMoveActiveTeamToAccount,
              let idx = teams.firstIndex(where: { $0.id == activeTeamID }) else { return }
        teams[idx].ckRecordName = nil
        teams[idx].isSharedParticipant = false
        teams[idx].isReadOnly = false
        accountTeamIDs.insert(teams[idx].id)
        Log.sync.notice("DEBUG: moved team \(self.teams[idx].id, privacy: .public) to the account")
        saveLocalOnly()
        syncAccount()
    }
    #endif

    // MARK: - Running a pass

    /// Starts a sync pass now, or right after the one running. No-op when
    /// signed out.
    func syncAccount() {
        guard let sync = accountSync else { return }
        if accountSyncRunning {
            accountSyncAgain = true
            return
        }
        accountSyncRunning = true

        let ids = accountTeamIDs
        let accountTeams = teams.filter { ids.contains($0.id) }
        let others = Set(teams.map(\.id)).subtracting(ids)
        let counts = accountEditCounts

        // A pass that starts as the app goes to the background gets the few
        // seconds iOS allows to finish, instead of being frozen mid-push.
        let background = UIApplication.shared.beginBackgroundTask(withName: "account-sync")

        Task { [weak self] in
            let outcome = await sync.sync(teams: accountTeams, excluding: others)
            guard let self else { return }
            self.applySyncOutcome(outcome, editCountsAtStart: counts)
            self.accountSyncRunning = false
            if background != .invalid { UIApplication.shared.endBackgroundTask(background) }
            if self.accountSyncAgain {
                self.accountSyncAgain = false
                self.syncAccount()
            }
        }
    }

    /// Sends any edit still waiting on the debounce. Call when leaving the
    /// foreground.
    func flushAccountSync() {
        accountSyncDebouncer.flush()
    }

    // MARK: - Applying a pass

    func applySyncOutcome(_ outcome: TeamSyncOutcome, editCountsAtStart: [UUID: Int]) {
        accountSyncStatus = outcome.status
        var changed = false
        var editedDuringPass = false

        for m in outcome.merged {
            guard accountTeamIDs.contains(m.team.id),
                  let idx = teams.firstIndex(where: { $0.id == m.team.id }) else { continue }
            let current = teams[idx]
            var result = m.team
            var slots = m.slots

            if accountEditCounts[m.team.id, default: 0] != editCountsAtStart[m.team.id, default: 0] {
                // Edited while the pass ran: the pass merged an older copy.
                // Fold the newer edits onto its result (the same three-way
                // merge, with the pass's starting point as the base).
                let now = TeamRowMapper.rows(from: current, slots: &slots, base: m.snapshotRows).rows
                let passed = TeamRowMapper.rows(from: m.team, slots: &slots, base: m.snapshotRows).rows
                let folded = TeamRowsMerge.merge(base: m.snapshotRows, local: now, server: passed).rows
                result = TeamRowMapper.team(from: folded, local: current).team
                editedDuringPass = true
            }

            var a = slots, b = slots
            let before = TeamRowMapper.rows(from: current, slots: &a).rows
            let after = TeamRowMapper.rows(from: result, slots: &b).rows
            if before != after {
                teams[idx] = result
                changed = true
                Log.sync.notice("Applied account changes to team \(result.id, privacy: .public)")
            }
        }

        for id in outcome.removedTeamIDs where accountTeamIDs.contains(id) {
            // Never remove the last team: the app always has one to show.
            guard teams.count > 1 else {
                Log.sync.notice("Team \(id, privacy: .public) is gone from the account but is the only team; keeping it")
                continue
            }
            teams.removeAll { $0.id == id }
            accountTeamIDs.remove(id)
            accountEditCounts[id] = nil
            if activeTeamID == id { activeTeamID = teams.first?.id }
            changed = true
            Log.sync.notice("Removed team \(id, privacy: .public): deleted from the account elsewhere")
        }

        for team in outcome.addedTeams where !teams.contains(where: { $0.id == team.id }) {
            teams.append(team)
            accountTeamIDs.insert(team.id)
            changed = true
            Log.sync.notice("Added team \(team.id, privacy: .public) from the account")
        }

        // A refused team can't be changed from this account: show it read-only
        // rather than letting edits pile up that will never send.
        for id in outcome.refusedTeamIDs {
            if let idx = teams.firstIndex(where: { $0.id == id }), !teams[idx].isReadOnly {
                teams[idx].isReadOnly = true
                changed = true
            }
        }

        if changed { saveLocalOnly() }
        if editedDuringPass, let id = accountTeamIDs.first { accountSyncDebouncer.schedule(id) }
    }
}


// MARK: - Status text

/// The one-line sync status Settings and diagnostics show. Fixed strings only.
nonisolated enum AccountSyncText {
    static func line(_ status: AccountSyncStatus) -> String {
        switch status.state {
        case .upToDate: return "All changes saved to your account."
        case .pending(let n): return n == 1 ? "1 team has changes waiting to sync." : "\(n) teams have changes waiting to sync."
        case .offline: return "Offline. Changes will sync when you're back online."
        case .signInNeeded: return "Sign in again to sync your changes."
        case .failed(let message): return message
        }
    }
}

// MARK: - Network

/// Calls `onReconnect` when the device comes back online, so edits made
/// offline go out without waiting for the next foreground.
@MainActor
final class AccountNetworkWatcher {
    static let shared = AccountNetworkWatcher()

    var onReconnect: (() -> Void)?
    private let monitor = NWPathMonitor()
    private var wasOnline = true

    /// Nonisolated to avoid the iOS 26.0-26.3 isolated-deinit crash; see
    /// AutoFillNLConstraintService's deinit.
    nonisolated deinit {}

    private init() {
        // @Sendable: the handler runs on the monitor's queue. A main-actor closure
        // here would trap on entry under Swift 6 (see objc-observer trap).
        monitor.pathUpdateHandler = { @Sendable [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in
                guard let self else { return }
                if online && !self.wasOnline { self.onReconnect?() }
                self.wasOnline = online
            }
        }
        monitor.start(queue: DispatchQueue(label: "account-network"))
    }
}
