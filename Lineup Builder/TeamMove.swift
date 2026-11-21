//
//  TeamMove.swift
//  Lineup Builder
//
//  Merge 1: the rules for moving an existing team into the coach's account.
//  Pure, so they can be tested without CloudKit or Supabase. The steps
//  themselves run in LineupStore+TeamMove.swift.
//
//  A move, in order:
//    1. Preflight: the coach's own team (CloudKit or device-only), signed in,
//       online, and not shared. Shared teams wait for Merge 4.
//    2. A raw backup of the team in Accounts/<user>/backups.
//    3. A move record in sync.json (phase "uploading"), so a crash at any
//       later point resumes or rolls back on the next launch.
//    4. The team becomes an account team and a sync pass sends it. If the
//       account already has this id (a web-pilot import), the pass merges by
//       id with the device winning conflicts. Never replace.
//    5. Read-back: the server's copy must match the device's exactly.
//       Match: phase "verified", and from here the move never rolls back.
//       Anything else: roll back. The team is a CloudKit team again with its
//       record name restored; the server copy stays, and a retry merges.
//    6. The move is reported done. In the background, the CloudKit record
//       gets movedToAccountAt (its own field, so old app versions' saves keep
//       it), then the move record is removed. Not waited for: CloudKit can
//       take minutes when iCloud is unreachable. If the marker can't be
//       written yet, it's retried on the next launch.
//

import Foundation

/// A move in progress, persisted in sync.json until it's finished.
nonisolated struct TeamMoveRecord: Codable, Equatable, Sendable {
    enum Phase: String, Codable, Sendable {
        /// Tagged as an account team and being sent; not yet confirmed.
        case uploading
        /// The server's copy matched. Only the CloudKit marker is left.
        case verified
    }

    var phase: Phase
    var startedAt: Date
    /// The team's CloudKit record before the move: restored on rollback, and
    /// where the moved marker is written. Nil for a device-only team.
    var ckRecordName: String?
    /// The raw backup's file name in the account's backups folder.
    var backupFile: String?
}

nonisolated enum TeamMove {

    // MARK: Preflight

    /// Why a team can't be moved right now.
    enum Block: Equatable, Sendable {
        case signedOut
        case alreadyInAccount
        case receivedShare
        case readOnly
        case shared
        case offline
        case shareCheckFailed
        case moveInProgress

        /// What the coach sees. Fixed strings only.
        var message: String {
            switch self {
            case .signedOut: return "Sign in to move this team to your account."
            case .alreadyInAccount: return "This team is already in your account."
            case .receivedShare, .readOnly: return "Only the head coach can move this team."
            case .shared: return "Shared teams can move once co-coaching comes to accounts."
            case .offline: return "Connect to the internet to move this team."
            case .shareCheckFailed: return "Couldn't check whether this team is shared. Try again in a moment."
            case .moveInProgress: return "This team is already moving to your account."
            }
        }

        /// For the team.move.failed signal.
        var reason: String {
            switch self {
            case .signedOut: return "signedOut"
            case .alreadyInAccount: return "alreadyInAccount"
            case .receivedShare: return "receivedShare"
            case .readOnly: return "readOnly"
            case .shared: return "shared"
            case .offline: return "offline"
            case .shareCheckFailed: return "shareCheckFailed"
            case .moveInProgress: return "moveInProgress"
            }
        }
    }

    /// The team's CloudKit sharing, as far as a move cares.
    enum ShareState: Equatable, Sendable {
        /// Device-only, or synced and not shared.
        case notShared
        /// The coach owns a CKShare for it.
        case shared
        /// Another coach's team, received through a share.
        case participant
        /// CloudKit couldn't be asked.
        case unknown
    }

    /// The checks that need no network, then the share state. Order matters
    /// only for which message the coach sees first.
    static func preflight(team: Team,
                          signedIn: Bool,
                          isAccountTeam: Bool,
                          isReceivedShare: Bool,
                          hasMoveRecord: Bool,
                          online: Bool,
                          shareState: ShareState) -> Block? {
        if !signedIn { return .signedOut }
        if isAccountTeam { return .alreadyInAccount }
        if hasMoveRecord { return .moveInProgress }
        if isReceivedShare || team.isSharedParticipant || shareState == .participant { return .receivedShare }
        if team.isReadOnly { return .readOnly }
        if !online { return .offline }
        switch shareState {
        case .shared: return .shared
        case .unknown: return .shareCheckFailed
        case .notShared, .participant: return nil
        }
    }

    // MARK: Read-back

    /// The server's copy compared with the device's after the pass.
    enum Verify: Equatable, Sendable {
        case match
        /// The server holds something else: a push failed part-way, or the
        /// coach edited during the pass and it hasn't gone out yet.
        case mismatch
        /// The server has no copy at all.
        case missing
        case offline
        case failed(String)

        var reason: String {
            switch self {
            case .match: return "match"
            case .mismatch: return "mismatch"
            case .missing: return "missing"
            case .offline: return "offline"
            case .failed: return "failed"
            }
        }
    }

    /// What an uploading move does after a read-back. A verified move never
    /// comes here: once the server's copy matched, it doesn't roll back.
    enum Next: Equatable, Sendable {
        case markVerified
        case rollBack
    }

    static func next(after verify: Verify) -> Next {
        verify == .match ? .markVerified : .rollBack
    }

    /// What the coach sees when a move rolls back. Fixed strings only.
    static func rollbackMessage(_ verify: Verify) -> String {
        switch verify {
        case .offline:
            return "The connection dropped before the move finished. Your team is unchanged; try again when you're online."
        case .match:
            return ""
        case .mismatch, .missing, .failed:
            return "The move couldn't be confirmed, so your team stays where it was. Try again in a moment."
        }
    }
}

// MARK: - Retiring the CloudKit copy (slice 6)
//
// After a move the CloudKit record stays as a backup, and old app versions
// on the coach's other devices can keep editing it. Once nothing has touched
// it for 90 days, the moving device deletes it. "Touched" is the record's
// server modification date, so an old-version edit, or the marker itself,
// restarts the clock. The record goes through the pending-deletions queue
// and gets a tombstone, like any other deleted team.

nonisolated struct MovedCloudKitRecord: Codable, Equatable, Sendable {
    let teamID: UUID
    let recordName: String
    /// Not worth asking CloudKit before this. Starts 90 days after the move
    /// and moves out whenever a check finds the record was touched since.
    var notBefore: Date
}

nonisolated enum MovedRecordCleanup {
    static let idleDays = 90
    static var idleInterval: TimeInterval { TimeInterval(idleDays) * 24 * 60 * 60 }

    static func entry(teamID: UUID, recordName: String, movedAt: Date) -> MovedCloudKitRecord {
        MovedCloudKitRecord(teamID: teamID, recordName: recordName,
                            notBefore: movedAt.addingTimeInterval(idleInterval))
    }

    /// The entries worth checking with CloudKit now.
    static func due(_ entries: [MovedCloudKitRecord], now: Date) -> [MovedCloudKitRecord] {
        entries.filter { $0.notBefore <= now }
    }

    enum Decision: Equatable {
        /// The record is already gone: drop the entry.
        case forget
        /// Idle for 90 days: delete it.
        case delete
        /// Touched since: check again 90 days after that.
        case wait(until: Date)
    }

    /// `lastModified` is nil when the record no longer exists.
    static func decide(lastModified: Date?, now: Date) -> Decision {
        guard let lastModified else { return .forget }
        let idleUntil = lastModified.addingTimeInterval(idleInterval)
        return idleUntil <= now ? .delete : .wait(until: idleUntil)
    }
}
