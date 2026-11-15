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
import os
import Supabase
import UIKit

extension LineupStore {

    // MARK: - Account changes

    /// Follows the signed-in account. Called once, from init.
    func startFollowingAccount() {
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

        if changed { saveLocalOnly() }
        if editedDuringPass, let id = accountTeamIDs.first { accountSyncDebouncer.schedule(id) }
    }
}
