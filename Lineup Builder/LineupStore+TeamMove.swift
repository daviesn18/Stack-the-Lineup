//
//  LineupStore+TeamMove.swift
//  Lineup Builder
//
//  Merge 1: moves an existing team into the signed-in coach's account. The
//  rules, the order of steps and the recovery story are in TeamMove.swift;
//  this file runs them against the store, SupabaseTeamSync and CloudKit.
//

import Foundation
import os

extension LineupStore {

    enum TeamMoveResult: Equatable, Sendable {
        case moved
        case blocked(TeamMove.Block)
        /// Rolled back: the team is where it was. A fixed, friendly message.
        case failed(String)
    }

    /// Moves a team into the account: backup, upload, read-back, then the
    /// CloudKit marker. Returns once the team is moved, blocked, or rolled back.
    func moveTeamToAccount(_ id: UUID) async -> TeamMoveResult {
        guard let sync = accountSync else { return blocked(.signedOut) }
        guard teams.contains(where: { $0.id == id }) else {
            return .failed("This team isn't on this device any more.")
        }

        // The checks that need no network first, so a blocked move doesn't
        // wait on CloudKit; then the share state, and everything again, since
        // the coach could have changed the team while CloudKit answered.
        let hasRecord = await sync.moveRecords()[id] != nil
        if let block = preflight(id, hasRecord: hasRecord, shareState: .notShared) { return blocked(block) }
        guard let candidate = teams.first(where: { $0.id == id }) else { return .failed("This team isn't on this device any more.") }
        let shareState = await Self.moveShareState(of: candidate)
        if let block = preflight(id, hasRecord: hasRecord, shareState: shareState) { return blocked(block) }
        guard let team = teams.first(where: { $0.id == id }) else { return .failed("This team isn't on this device any more.") }

        movingTeamID = id
        defer { movingTeamID = nil }
        Analytics.signal("team.move.started", parameters: [
            "from": team.ckRecordName == nil ? "device" : "cloudkit",
        ])

        // 2. The raw backup. Without one, the move doesn't go ahead.
        guard let backupFile = await sync.backupForMove(team) else {
            Analytics.signal("team.move.failed", parameters: ["reason": "backup", "resumed": "no"])
            return .failed("Couldn't save a backup of this team, so it wasn't moved. Try again in a moment.")
        }

        // 3. The move record, before the team changes.
        let record = TeamMoveRecord(phase: .uploading, startedAt: Date(),
                                    ckRecordName: team.ckRecordName, backupFile: backupFile)
        await sync.beginMove(id, record: record)

        // 4. It becomes an account team. From here CloudKit pushes and fetches
        // skip it (Merge 0b), and the next pass sends it.
        guard let idx = teams.firstIndex(where: { $0.id == id }) else {
            await sync.endMove(id)
            return .failed("This team isn't on this device any more.")
        }
        teams[idx].ckRecordName = nil
        accountTeamIDs.insert(id)
        saveLocalOnly()
        Log.sync.notice("Moving team \(id, privacy: .public) to the account")

        return await continueMove(id, record: record, sync: sync, resumed: false)
    }

    /// Moves cut short by the app being killed: each resumes or rolls back.
    /// Runs on sign-in, which includes every launch with a stored session.
    func resumeTeamMoves() async {
        guard let sync = accountSync else { return }
        for (id, record) in await sync.moveRecords() where movingTeamID != id {
            // Killed before the team was tagged (or it's gone since): nothing
            // changed on this device, so there's nothing to finish or undo.
            guard teams.contains(where: { $0.id == id }),
                  record.phase == .verified || accountTeamIDs.contains(id) else {
                await sync.endMove(id)
                Log.sync.notice("Cleared an unstarted move of team \(id, privacy: .public)")
                continue
            }
            Log.sync.notice("Resuming the move of team \(id, privacy: .public) (\(record.phase.rawValue, privacy: .public))")
            movingTeamID = id
            _ = await continueMove(id, record: record, sync: sync, resumed: true)
            movingTeamID = nil
        }
    }

    /// A team imported into the account: a raw backup, a sync pass, then the
    /// same read-back as a move. There's nowhere to roll back to (the team
    /// never lived anywhere else), so a failed read-back leaves it in the
    /// account with its changes pending, and the next pass sends them again.
    func confirmImportedTeam(_ id: UUID) async {
        guard let sync = accountSync, let team = teams.first(where: { $0.id == id }) else { return }
        if await sync.backupForImport(team) == nil {
            Log.sync.error("Imported team \(id, privacy: .public) has no backup")
        }
        await syncAccountAndWait()
        guard let sent = teams.first(where: { $0.id == id }), accountTeamIDs.contains(id) else { return }
        let verify = await sync.verify(sent)
        Analytics.signal(verify == .match ? "team.import.verified" : "team.import.unconfirmed",
                         parameters: ["reason": verify.reason])
        if verify == .match {
            Log.sync.notice("Imported team \(id, privacy: .public) confirmed in the account")
        } else {
            Log.sync.error("Imported team \(id, privacy: .public) not confirmed yet: \(verify.reason, privacy: .public)")
        }
    }

    // MARK: - Moved on another device (slice 4)
    //
    // Another of the coach's devices moved a CloudKit team this device also
    // holds; the record now carries movedToAccountAt. Signed in to that
    // account, this device adopts the account copy (one team, not two).
    // Otherwise the team goes read-only with a notice, so edits here can't pile
    // up on a copy nobody reads. Old app versions can't see the marker and keep
    // editing the CloudKit copy; those edits don't reach the account.

    /// After a CloudKit fetch: records the teams whose record is marked moved.
    func noteTeamsMovedElsewhere(_ changes: CloudKitManager.FetchChangesResult) {
        let moved = Set(changes.modifiedTeams
            .filter { $0.ckRecordName.map(changes.movedRecordNames.contains) ?? false }
            .map(\.id))
            .subtracting(accountTeamIDs)
        let newlySeen = moved.subtracting(movedAwayTeamIDs)
        if !newlySeen.isEmpty {
            movedAwayTeamIDs.formUnion(newlySeen)
            for id in newlySeen {
                Log.sync.notice("Team \(id, privacy: .public) was moved to an account on another device")
            }
            Analytics.signal("team.move.seen_elsewhere", parameters: [
                "signed_in": accountSync == nil ? "no" : "yes",
            ])
        }
        enforceMovedElsewhere()
    }

    /// Moved teams not adopted yet are read-only. Signed in, a pass is started
    /// so the account copy can replace them.
    func enforceMovedElsewhere() {
        movedAwayTeamIDs.formIntersection(teams.map(\.id))
        let waiting = movedAwayTeamIDs.subtracting(accountTeamIDs)
        guard !waiting.isEmpty else { return }
        var changed = false
        for id in waiting {
            if let idx = teams.firstIndex(where: { $0.id == id }), !teams[idx].isReadOnly {
                teams[idx].isReadOnly = true
                changed = true
            }
        }
        if changed { saveLocalOnly() }
        if accountSync != nil { syncAccount() }
    }

    /// Whether a team is read-only because it moved to an account elsewhere.
    func isMovedElsewhere(_ id: UUID) -> Bool {
        movedAwayTeamIDs.contains(id) && !accountTeamIDs.contains(id)
    }

    /// The account copy of a team this device holds as a moved CloudKit team:
    /// it takes the local copy's place. Returns false if the team isn't one.
    func adoptMovedTeam(_ accountCopy: Team) -> Bool {
        guard isMovedElsewhere(accountCopy.id),
              let idx = teams.firstIndex(where: { $0.id == accountCopy.id }) else { return false }
        var adopted = accountCopy
        adopted.coachName = teams[idx].coachName   // local-only, as everywhere
        adopted.ckRecordName = nil
        adopted.isReadOnly = false
        adopted.isSharedParticipant = false
        teams[idx] = adopted
        accountTeamIDs.insert(adopted.id)
        movedAwayTeamIDs.remove(adopted.id)
        Log.sync.notice("Adopted the account copy of moved team \(adopted.id, privacy: .public)")
        Analytics.signal("team.move.adopted")
        return true
    }

    // MARK: - Steps 4 to 6

    private func continueMove(_ id: UUID, record: TeamMoveRecord,
                              sync: SupabaseTeamSync, resumed: Bool) async -> TeamMoveResult {
        let resumedParam = resumed ? "yes" : "no"

        if record.phase == .uploading {
            // 4. Send it, then 5. read it back.
            await syncAccountAndWait()
            guard let team = teams.first(where: { $0.id == id }), accountTeamIDs.contains(id) else {
                // Deleted while it was moving: the delete has its own path.
                await sync.endMove(id)
                return .failed("This team was deleted while it was moving.")
            }
            let verify = await sync.verify(team)
            switch TeamMove.next(after: verify) {
            case .rollBack:
                rollBackMove(id, record: record)
                await sync.endMove(id)
                Analytics.signal("team.move.failed", parameters: ["reason": verify.reason, "resumed": resumedParam])
                Log.sync.error("Move of team \(id, privacy: .public) rolled back: \(verify.reason, privacy: .public)")
                return .failed(TeamMove.rollbackMessage(verify))
            case .markVerified:
                await sync.setMovePhase(id, .verified)
                Log.sync.notice("Move of team \(id, privacy: .public) verified")
            }
        }

        // 6. Verified: the account copy is the team now, and it doesn't roll
        // back, so the coach is told it's moved. A resumed verified move sent
        // its completed signal the first time.
        if record.phase == .uploading {
            Analytics.signal("team.move.completed", parameters: [
                "from": record.ckRecordName == nil ? "device" : "cloudkit",
                "resumed": resumedParam,
            ])
        }
        Log.sync.notice("Moved team \(id, privacy: .public) to the account")

        // The CloudKit marker, so the coach's other devices can tell, goes in
        // the background: CloudKit can take minutes to answer when iCloud is
        // unreachable, and the move doesn't depend on it.
        Task { [weak self] in await self?.writeMovedMarker(id, record: record, sync: sync) }
        return .moved
    }

    /// Writes the moved marker, then retires the move record. If CloudKit
    /// can't be reached, the record stays and the next launch tries again.
    private func writeMovedMarker(_ id: UUID, record: TeamMoveRecord, sync: SupabaseTeamSync) async {
        if let recordName = record.ckRecordName {
            do {
                try await CloudKitManager.shared.markMovedToAccount(recordName: recordName)
            } catch {
                Log.sync.error("Moved marker for team \(id, privacy: .public) not written yet: \(error.localizedDescription, privacy: .public)")
                return
            }
        }
        await sync.endMove(id)
        Log.sync.notice("Move of team \(id, privacy: .public) finished (marker \(record.ckRecordName == nil ? "not needed" : "written", privacy: .public))")
    }

    /// The team goes back to being a CloudKit (or device-only) team with its
    /// own record name. The server copy stays: a retry merges with it by id,
    /// and until then the sync pass leaves it alone (its id is excluded).
    private func rollBackMove(_ id: UUID, record: TeamMoveRecord) {
        accountTeamIDs.remove(id)
        accountEditCounts[id] = nil
        guard let idx = teams.firstIndex(where: { $0.id == id }) else { saveLocalOnly(); return }
        teams[idx].ckRecordName = record.ckRecordName
        // A full save: back to the blob, and any edit made during the move
        // goes to CloudKit.
        save(changedTeamID: id)
    }

    // MARK: - Preflight

    private func preflight(_ id: UUID, hasRecord: Bool, shareState: TeamMove.ShareState) -> TeamMove.Block? {
        guard let team = teams.first(where: { $0.id == id }) else { return .alreadyInAccount }
        return TeamMove.preflight(team: team,
                                  signedIn: accountSync != nil,
                                  isAccountTeam: accountTeamIDs.contains(id),
                                  isReceivedShare: isReceivedShare(team),
                                  hasMoveRecord: hasRecord || movingTeamID != nil,
                                  online: AccountNetworkWatcher.shared.isOnline,
                                  shareState: shareState)
    }

    private func blocked(_ block: TeamMove.Block) -> TeamMoveResult {
        Analytics.signal("team.move.blocked", parameters: ["reason": block.reason])
        return .blocked(block)
    }

    /// How long the share check may take. CloudKit can sit on a request for
    /// minutes when iCloud is unreachable but the network is up (211 s in a
    /// test), which would leave the coach watching a spinner.
    static let moveShareCheckTimeout: Duration = .seconds(15)

    /// Asks CloudKit whether the coach shares this team. A device-only team
    /// can't be shared, so it doesn't ask. No answer in time counts as unknown,
    /// which blocks the move with "try again".
    static func moveShareState(of team: Team) async -> TeamMove.ShareState {
        guard team.ckRecordName != nil else { return .notShared }
        return await firstOf(timeout: moveShareCheckTimeout, fallback: .unknown) {
            do {
                switch try await CloudKitManager.shared.shareInfo(for: team).state {
                case .shared: return .shared
                case .participant: return .participant
                case .notShared, .notSynced: return .notShared
                }
            } catch {
                Log.sync.error("Move share check failed: \(error.localizedDescription, privacy: .public)")
                return .unknown
            }
        }
    }

    /// `operation`'s result, or `fallback` once `timeout` passes, whichever
    /// comes first. Not a task group: a group waits for every child before
    /// returning, so it would still wait out CloudKit. The slow call is left
    /// to finish on its own and its result is ignored.
    nonisolated static func firstOf<T: Sendable>(timeout: Duration, fallback: T,
                                                 _ operation: @escaping @Sendable () async -> T) async -> T {
        await withCheckedContinuation { continuation in
            let resumed = OSAllocatedUnfairLock(initialState: false)
            let finish: @Sendable (T) -> Void = { value in
                let first = resumed.withLock { done -> Bool in
                    defer { done = true }
                    return !done
                }
                if first { continuation.resume(returning: value) }
            }
            Task { finish(await operation()) }
            Task {
                try? await Task.sleep(for: timeout)
                finish(fallback)
            }
        }
    }
}
