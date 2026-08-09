import CloudKit
import Foundation

// MARK: - Share Value Types
//
// Sendable snapshots of CloudKit share state. CKShare is a mutable reference
// type owned by the CloudKitManager actor; these are what cross the boundary
// into SwiftUI, so a view can never mutate a share by holding one.

/// What a coach is allowed to do with a shared team.
enum TeamSharePermission: String, Sendable, CaseIterable, Identifiable {
    case readWrite
    case readOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .readWrite: return "Can edit"
        case .readOnly:  return "View only"
        }
    }

    /// Written from the head coach's point of view — this is what they are
    /// granting, not what the recipient sees.
    var explanation: String {
        switch self {
        case .readWrite:
            return "They can add players and build positions. Finalizing the lineup stays with you."
        case .readOnly:
            return "They can see the roster and the lineup, but can't change anything."
        }
    }

    /// The same permission described to the coach who received the team.
    var participantExplanation: String {
        switch self {
        case .readWrite:
            return "You can add players and build positions. The head coach finalizes the lineup."
        case .readOnly:
            return "You can see the roster and the lineup. Only the head coach can make changes."
        }
    }

    var ckPermission: CKShare.ParticipantPermission {
        self == .readOnly ? .readOnly : .readWrite
    }

    /// `.none` and `.unknown` only reach this from a legacy share; both are
    /// reported as read-write because that is what the repair path sets them to.
    init(_ ckPermission: CKShare.ParticipantPermission) {
        self = (ckPermission == .readOnly) ? .readOnly : .readWrite
    }
}

/// One coach on a shared team, other than the owner.
/// Hashable so it can be a `NavigationLink(value:)` destination.
struct ShareParticipantInfo: Sendable, Hashable, Identifiable {

    /// The participant's iCloud user record name. Stable, and the handle the
    /// manager uses to find them again on a write.
    let id: String
    let displayName: String
    /// Email or phone, when CloudKit knows it and it isn't already the name.
    let contact: String?
    let permission: TeamSharePermission
    let hasAccepted: Bool

    init(
        id: String,
        displayName: String,
        contact: String?,
        permission: TeamSharePermission,
        hasAccepted: Bool
    ) {
        self.id          = id
        self.displayName = displayName
        self.contact     = contact
        self.permission  = permission
        self.hasAccepted = hasAccepted
    }

    init(participant: CKShare.Participant) {
        let identity = participant.userIdentity
        let lookup   = identity.lookupInfo

        self.id = identity.userRecordID?.recordName ?? UUID().uuidString

        let resolved      = CloudKitManager.displayName(for: participant)
        let contactHandle = lookup?.emailAddress ?? lookup?.phoneNumber

        // A pending invite usually has no name yet — CloudKit only learns it once
        // the coach accepts. Falling back to the handle, and then to a generic
        // label, is what keeps this from rendering an empty row.
        self.displayName = resolved ?? "Assistant coach"
        // Only a secondary line when it isn't already the title.
        self.contact     = (resolved == contactHandle) ? nil : contactHandle
        self.permission  = TeamSharePermission(participant.permission)
        self.hasAccepted = participant.acceptanceStatus == .accepted
    }
}

/// A team's sharing state as CloudKit currently reports it.
///
/// Replaces the old `ckRecordName != nil` test, which only ever meant "this team
/// has been pushed to iCloud" and was wrong about sharing for every synced team.
struct TeamShareInfo: Sendable, Equatable {

    enum State: Sendable, Equatable {
        /// No CloudKit record. `staleRecordName` is true when the team carried a
        /// record name for a record the server no longer has, which needs clearing.
        case notSynced(staleRecordName: Bool)
        case notShared
        /// This coach owns the team and has shared it.
        case shared
        /// This coach received the team from someone else. There is nothing to
        /// manage here — the owner holds the share — so the screen reports who
        /// shared it and what this coach is allowed to do.
        case participant
    }

    var state: State
    var url: URL?
    var linkPermission: TeamSharePermission = .readWrite
    var participants: [ShareParticipantInfo] = []

    /// Head coach's name, on a team this coach received. Nil otherwise, and nil
    /// when CloudKit has no discoverable identity for them.
    var ownerName: String?

    /// This coach's own access, on a team they received.
    var myPermission: TeamSharePermission = .readWrite

    var isShared: Bool {
        if case .shared = state { return true }
        return false
    }

    var isParticipant: Bool {
        if case .participant = state { return true }
        return false
    }

    /// Coaches who have actually joined. Pending invites are deliberately not
    /// counted — "1 coach" should mean someone is really there.
    var acceptedCount: Int {
        participants.filter(\.hasAccepted).count
    }

    /// The one-line summary shown on the Edit Team row.
    var summary: String {
        switch state {
        case .notSynced:
            return "Not synced"
        case .notShared:
            return "Not shared"
        case .participant:
            return "Shared with you"
        case .shared:
            let accepted = acceptedCount
            let pending  = participants.count - accepted
            if accepted == 0 {
                return pending > 0 ? "Invite sent" : "Link ready"
            }
            return "\(accepted) \(accepted == 1 ? "coach" : "coaches")"
        }
    }
}

// MARK: - CloudKitManager

/// Manages all CloudKit operations for Stack the Lineup v3.0 shared teams.
///
/// Architecture:
///   Container : iCloud.com.nickdavies.LineupBuilder.Lineup-Builder (existing)
///   Zone      : STLTeams (custom — required for CKShare)
///   Record    : type "Team", one record per team
///     teamJSON        CKAsset   — full JSON-encoded Team blob
///     localModifiedAt Date      — timestamp for last-write-wins conflict resolution
///
/// Persistence path:
///   Private database  — teams owned by this device's iCloud account
///   Shared database   — teams shared TO this device by another coach (read-only)
///
/// Migration:
///   On first launch after v3.0, all teams in NSUbiquitousKeyValueStore are written
///   to CloudKit. The KV store is kept as a fallback for one version. Gated by
///   hasCompletedCloudKitMigration in UserDefaults so it runs exactly once.
///
/// Sync:
///   Foreground incremental sync on scenePhase == .active via fetchChanges().
///   Server change token persisted in UserDefaults. Push notifications deferred to v3.1.
///
/// Conflict resolution:
///   Last-write-wins by localModifiedAt. On CKError.serverRecordChanged, the local
///   and server timestamps are compared; the newer record wins. LineupStore performs
///   the same comparison when merging fetchChanges() results.
///
/// Swift 6 concurrency notes:
///   Team's Codable conformance is @MainActor-isolated (inferred from SwiftUI types
///   in Models.swift). All encode/decode operations hop to the main actor.
///   In iOS 26, MainActor.run requires trailing-closure syntax — passing a closure
///   inside parens ({ }) matches the resultType: parameter instead of body:.
///   Analytics.signal is @MainActor — fired via Task { @MainActor in }.

actor CloudKitManager {
    
    // MARK: - Singleton
    
    static let shared = CloudKitManager()
    private init() {}
    
    // MARK: - Constants
    // nonisolated let — accessible from non-actor closures and static helpers.
    
    nonisolated let containerIdentifier = "iCloud.com.nickdavies.LineupBuilder.Lineup-Builder"
    nonisolated let zoneName            = "STLTeams"
    nonisolated let recordTypeName      = "Team"
    nonisolated let jsonField           = "teamJSON"
    nonisolated let modifiedAtField     = "localModifiedAt"
    
    // UserDefaults keys
    private let migrationKey   = "hasCompletedCloudKitMigration"
    private let changeTokenKey = "ckZoneChangeToken_STLTeams"
    
    // MARK: - CloudKit Handles
    // nonisolated — computed from constants only, callable from any context.
    
    nonisolated var ckContainer: CKContainer { CKContainer.default() }
    nonisolated var privateDB:   CKDatabase   { ckContainer.privateCloudDatabase }
    nonisolated var sharedDB:    CKDatabase   { ckContainer.sharedCloudDatabase }
    nonisolated var ckZone:      CKRecordZone { CKRecordZone(zoneName: zoneName) }
    
    // MARK: - In-Memory Record Cache
    // Maps ckRecordName -> full CKRecord (with system fields / recordChangeTag).
    // Avoids a fetch-before-save for every update within the same app session.
    private var recordCache: [String: CKRecord] = [:]
    
    // MARK: - Errors
    
    enum CloudKitError: Error, LocalizedError {
        case accountUnavailable
        case encodingFailed
        case decodingFailed
        case assetMissing
        case assetReadFailed
        case recordNotFound(String)
        case notSynced
        case notShared
        case shareSaveFailed
        case participantNotFound

        var errorDescription: String? {
            switch self {
            case .accountUnavailable:
                return "iCloud is not available. Check your account in Settings."
            case .encodingFailed:
                return "Unable to encode team data for iCloud."
            case .decodingFailed:
                return "Unable to read team data from iCloud."
            case .assetMissing:
                return "Team record in iCloud is missing its data file."
            case .assetReadFailed:
                return "Unable to read team data file from iCloud."
            case .recordNotFound(let name):
                return "CloudKit record not found: \(name)."
            case .notSynced:
                return "This team hasn't synced to iCloud yet. Try again in a moment."
            case .notShared:
                return "This team isn't shared."
            case .shareSaveFailed:
                return "iCloud couldn't save the change. Try again in a moment."
            case .participantNotFound:
                return "That coach is no longer on this team."
            }
        }
    }
    
    // MARK: - Account Check
    
    /// Returns true when the user has an available iCloud account.
    func isAccountAvailable() async -> Bool {
        (try? await ckContainer.accountStatus()) == .available
    }
    
    // MARK: - Zone Setup
    
    /// Creates the STLTeams zone if it does not already exist.
    /// Idempotent — safe to call on every launch before any record operations.
    func ensureZoneExists() async throws {
        _ = try await privateDB.save(CKRecordZone(zoneName: zoneName))
    }
    
    // MARK: - Save
    
    /// Saves a team to CloudKit, creating or updating its record.
    ///
    /// Conflict resolution — last-write-wins by localModifiedAt:
    ///   On serverRecordChanged, the server record's timestamp is compared to ours.
    ///   If ours is newer the server record's fields are updated and re-saved.
    ///   If the server record is newer the save is skipped silently; the newer
    ///   version arrives on the next fetchChanges() call.
    ///
    /// - Returns: The CKRecord.ID.recordName to persist on team.ckRecordName.
    @discardableResult
    func saveTeam(_ team: Team, useSharedDB: Bool = false) async throws -> String {
        // Team's Encodable is @MainActor-isolated in Swift 6 — hop to main actor.
        let jsonData = try await encodeTeam(team)
        let asset    = try makeAsset(from: jsonData, teamID: team.id)
        let now      = Date()

        // Participants must save via sharedDB using the record's actual zone ID
        // (owned by the head coach, not __defaultOwner__). We fetch the live
        // record from sharedDB first so we have the correct zone ID and
        // recordChangeTag — both required for a valid conflict-free save.
        if useSharedDB, let recordName = team.ckRecordName {
            let record: CKRecord
            if let cached = recordCache[recordName] {
                record = cached
            } else {
                // Cache miss (e.g. after app restart) — fetch from sharedDB to
                // get the correct zone ID with the owner's iCloud record name.
                let sharedZones = try await sharedDB.allRecordZones()
                guard let ownerZone = sharedZones.first(where: { $0.zoneID.zoneName == zoneName }) else {
                    throw CloudKitError.assetMissing // no shared zone found — share not accepted yet
                }
                let recordID = CKRecord.ID(recordName: recordName, zoneID: ownerZone.zoneID)
                record = try await sharedDB.record(for: recordID)
                recordCache[recordName] = record
            }
            record[jsonField]       = asset
            record[modifiedAtField] = now as CKRecordValue
            try await saveRecordWithConflictResolution(record, localModifiedAt: now, useSharedDB: true)
            return recordName
        }

        let recordName: String
        let record: CKRecord

        if let existing = team.ckRecordName {
            recordName = existing
            record = recordCache[recordName]
            ?? CKRecord(
                recordType: recordTypeName,
                recordID: CKRecord.ID(recordName: recordName, zoneID: ckZone.zoneID)
            )
        } else {
            // Derive a stable recordName from the team UUID so re-saves are
            // idempotent if ckRecordName hasn't been persisted yet.
            recordName = "team-\(team.id.uuidString)"
            record = CKRecord(
                recordType: recordTypeName,
                recordID: CKRecord.ID(recordName: recordName, zoneID: ckZone.zoneID)
            )
        }

        record[jsonField]       = asset
        record[modifiedAtField] = now as CKRecordValue

        try await saveRecordWithConflictResolution(record, localModifiedAt: now, useSharedDB: false)
        return recordName
    }
    
    private func saveRecordWithConflictResolution(
        _ record: CKRecord,
        localModifiedAt: Date,
        useSharedDB: Bool = false
    ) async throws {
        do {
            let saved = try await (useSharedDB ? sharedDB : privateDB).save(record)
            recordCache[saved.recordID.recordName] = saved
            
        } catch let ckError as CKError where ckError.code == .serverRecordChanged {
            guard let serverRecord = ckError.serverRecord else { throw ckError }
            let serverModifiedAt = serverRecord[modifiedAtField] as? Date ?? .distantPast
            
            if localModifiedAt > serverModifiedAt {
                // Our version is newer — update the server record's fields and re-save.
                serverRecord[jsonField]       = record[jsonField]
                serverRecord[modifiedAtField] = localModifiedAt as CKRecordValue
                let saved = try await (useSharedDB ? sharedDB : privateDB).save(serverRecord)
                recordCache[saved.recordID.recordName] = saved
            } else {
                // Server is newer — cache it. LineupStore picks up the data on fetchChanges.
                recordCache[serverRecord.recordID.recordName] = serverRecord
            }
            
        } catch let ckError as CKError where ckError.code == .unknownItem {
            // Record was deleted on the server — re-create with a clean record.
            let freshRecord = CKRecord(
                recordType: record.recordType,
                recordID: record.recordID
            )
            freshRecord[jsonField]       = record[jsonField]
            freshRecord[modifiedAtField] = localModifiedAt as CKRecordValue
            let saved = try await (useSharedDB ? sharedDB : privateDB).save(freshRecord)
            recordCache[saved.recordID.recordName] = saved
        } catch {
            // Any other failure. For participant saves (sharedDB) this is the
            // signal that a coach's edit silently failed to reach the head
            // coach's zone — the key "is it working" failure mode.
            if useSharedDB {
                Task { @MainActor in
                    Analytics.signal("sharing.sync.failed", parameters: [
                        "stage": "participantSave",
                        "error": error.localizedDescription
                    ])
                }
            }
            throw error
        }
    }
    
    // MARK: - Fetch All
    
    /// Fetches every Team record from the private STLTeams zone.
    /// Use for a full re-sync (e.g. after migration, or when the change token
    /// is invalidated by a zone reset).
    func fetchAllTeams() async throws -> [Team] {
        let query = CKQuery(
            recordType: recordTypeName,
            predicate: NSPredicate(value: true)
        )
        let (results, _) = try await privateDB.records(
            matching: query,
            inZoneWith: ckZone.zoneID
        )
        
        // Collect raw records first, then decode in a single MainActor.run block.
        // In iOS 26, MainActor.run must use trailing-closure syntax — a closure
        // inside parens ({ }) is matched against resultType: T.Type, not body:.
        var rawRecords: [CKRecord] = []
        for (_, result) in results {
            if let record = try? result.get() {
                recordCache[record.recordID.recordName] = record
                rawRecords.append(record)
            }
        }
        
        let jsonKey = self.jsonField
        let teams: [Team] = await MainActor.run { [rawRecords] in
            rawRecords.compactMap { record in
                try? CloudKitManager.decodeTeam(from: record, jsonField: jsonKey)
            }
        }
        return teams
    }
    
    // MARK: - Fetch Changes (Foreground Sync)
    
    struct FetchChangesResult {
        /// Teams that were added or modified on the server since the last sync.
        var modifiedTeams: [Team]
        /// Record names of teams deleted on the server since the last sync.
        var deletedRecordNames: [String]
    }
    
    /// Fetches incremental record changes from the STLTeams zone since the last sync.
    /// Call when scenePhase transitions to .active.
    ///
    /// Uses a persisted CKServerChangeToken in UserDefaults. On the very first call
    /// (no stored token), fetches all records in the zone. Automatically pages
    /// through batches when moreComing is true.
    func fetchChanges() async throws -> FetchChangesResult {
        var allModified: [Team]   = []
        var allDeleted:  [String] = []
        
        let storedData = UserDefaults.standard.data(forKey: changeTokenKey)
        var token: CKServerChangeToken? = storedData.flatMap {
            try? NSKeyedUnarchiver.unarchivedObject(
                ofClass: CKServerChangeToken.self,
                from: $0
            )
        }
        
        var moreComing = true
        while moreComing {
            let batch = try await fetchBatch(since: token)
            allModified.append(contentsOf: batch.teams)
            allDeleted.append(contentsOf: batch.deleted)
            token      = batch.newToken
            moreComing = batch.moreComing
        }
        
        if let token,
           let tokenData = try? NSKeyedArchiver.archivedData(
            withRootObject: token,
            requiringSecureCoding: true
           ) {
            UserDefaults.standard.set(tokenData, forKey: changeTokenKey)
        }
        
        return FetchChangesResult(modifiedTeams: allModified, deletedRecordNames: allDeleted)
    }
    
    // MARK: - fetchBatch (internal)
    
    /// Holds raw operation output before decoding.
    /// Decoding is deferred because Team's Decodable conformance requires @MainActor,
    /// and CKOperation callbacks are synchronous — they can't await a main-actor hop.
    private final class BatchCollector: @unchecked Sendable {
        var rawRecords: [CKRecord] = []
        var deleted:    [String]   = []
        var newToken:   CKServerChangeToken? = nil
        var moreComing: Bool = false
    }
    
    private struct BatchResult {
        var teams:      [Team]
        var deleted:    [String]
        var newToken:   CKServerChangeToken?
        var moreComing: Bool
    }
    
    private func fetchBatch(since token: CKServerChangeToken?) async throws -> BatchResult {
        let config = CKFetchRecordZoneChangesOperation.ZoneConfiguration(
            previousServerChangeToken: token
        )
        let operation = CKFetchRecordZoneChangesOperation(
            recordZoneIDs: [ckZone.zoneID],
            configurationsByRecordZoneID: [ckZone.zoneID: config]
        )
        
        let db        = self.privateDB
        let collector = BatchCollector()
        
        // Phase 1: collect raw CKRecord objects synchronously inside operation callbacks.
        let rawResult = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<BatchCollector, Error>) in
            operation.recordWasChangedBlock = { _, result in
                if let record = try? result.get(), record.recordType == "Team" {
                    collector.rawRecords.append(record)
                }
            }
            
            operation.recordWithIDWasDeletedBlock = { recordID, _ in
                collector.deleted.append(recordID.recordName)
            }
            
            // Called once per zone with the server token and moreComing flag.
            operation.recordZoneFetchResultBlock = { _, zoneResult in
                if case .success(let (serverToken, _, hasMore)) = zoneResult {
                    collector.newToken   = serverToken
                    collector.moreComing = hasMore
                }
            }
            
            // Single resume point — fires after the entire operation completes.
            operation.fetchRecordZoneChangesResultBlock = { overallResult in
                switch overallResult {
                case .success:
                    continuation.resume(returning: collector)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            
            db.add(operation)
        }
        
        // Phase 2: decode on the main actor using trailing-closure syntax.
        // Team's Decodable is @MainActor-isolated; trailing closure avoids the
        // iOS 26 resultType: matching issue that ({ }) triggers.
        let jsonKey = self.jsonField
        let teams: [Team] = await MainActor.run {
            rawResult.rawRecords.compactMap { record in
                try? CloudKitManager.decodeTeam(from: record, jsonField: jsonKey)
            }
        }
        
        return BatchResult(
            teams:      teams,
            deleted:    rawResult.deleted,
            newToken:   rawResult.newToken,
            moreComing: rawResult.moreComing
        )
    }
    
    // MARK: - Shared Teams

    /// Fetches teams from the shared database accepted by this device.
    ///
    /// Uses CKFetchRecordZoneChangesOperation instead of CKQuery so no queryable
    /// indexes are required on the Team record type. The operation also returns
    /// the CKShare record for each zone, letting us read the current participant's
    /// permission and set isReadOnly correctly rather than hardcoding it.
    func fetchSharedTeams() async throws -> [Team] {
        let zones: [CKRecordZone]
        do {
            zones = try await sharedDB.allRecordZones()
        } catch {
            Task { @MainActor in
                Analytics.signal("sharing.sync.failed", parameters: [
                    "stage": "fetchZones",
                    "error": error.localizedDescription
                ])
            }
            throw error
        }
        guard !zones.isEmpty else { return [] }

        let jsonKey   = self.jsonField
        let sharedDB  = self.sharedDB
        var result: [Team] = []

        for zone in zones {
            // Collector holds raw output from the operation callbacks.
            final class ZoneCollector: @unchecked Sendable {
                var teamRecords: [CKRecord] = []
                var shareRecord: CKShare?
            }
            let collector = ZoneCollector()

            // Fetch all records in this zone from the beginning (no stored token).
            // We always want the full current state for shared teams.
            let config    = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
            let operation = CKFetchRecordZoneChangesOperation(
                recordZoneIDs: [zone.zoneID],
                configurationsByRecordZoneID: [zone.zoneID: config]
            )

            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                operation.recordWasChangedBlock = { _, result in
                    guard let record = try? result.get() else { return }
                    if let share = record as? CKShare {
                        collector.shareRecord = share
                    } else if record.recordType == "Team" {
                        collector.teamRecords.append(record)
                    }
                }
                operation.fetchRecordZoneChangesResultBlock = { overallResult in
                    switch overallResult {
                    case .success:
                        continuation.resume()
                    case .failure(let error):
                        Task { @MainActor in
                            Analytics.signal("sharing.sync.failed", parameters: [
                                "stage": "fetchZoneChanges",
                                "error": error.localizedDescription
                            ])
                        }
                        continuation.resume(throwing: error)
                    }
                }
                sharedDB.add(operation)
            }

            // Determine read-only status from the participant's actual permission.
            // Falls back to true if the share record wasn't returned (safe default).
            let isReadOnly: Bool
            if let share = collector.shareRecord,
               let participant = share.currentUserParticipant {
                isReadOnly = participant.permission == .readOnly
            } else {
                isReadOnly = true
            }

            // Cache raw CKRecords on the actor so participant saves hit recordCache
            // and avoid a redundant sharedDB.record(for:) fetch on first save.
            for record in collector.teamRecords {
                recordCache[record.recordID.recordName] = record
                // Also remember which CKShare each received team came in under.
                // The sharing screen needs it to name the head coach, and there
                // is no way back to it from a record name alone — a participant's
                // record lives in the owner's zone in the shared database.
                if let share = collector.shareRecord {
                    participantShareCache[record.recordID.recordName] = share
                }
            }
            // Decode Team records on the main actor (Team's Decodable is @MainActor-isolated).
            var zoneTeams: [Team] = await MainActor.run { [teamRecords = collector.teamRecords] in
                return teamRecords.compactMap { record in
                    try? CloudKitManager.decodeTeam(from: record, jsonField: jsonKey)
                }
            }
            for i in zoneTeams.indices { zoneTeams[i].isReadOnly = isReadOnly }
            result.append(contentsOf: zoneTeams)
        }

        // Fired whenever shared teams successfully materialize from the shared DB.
        // Pair with team.share.accepted: accepted minus synced surfaces silent
        // join failures (invite accepted but the zone never delivered records).
        let syncedCount = result.count
        Task { @MainActor in
            Analytics.signal("sharing.synced", parameters: ["teamCount": "\(syncedCount)"])
        }

        return result
    }
    
    // MARK: - Sharing
    //
    // The view layer never touches CKShare. Reads return a TeamShareInfo value
    // snapshot; writes name the participant by id and mutate the CKShare held
    // here in shareCache. That split is deliberate — the old code had a single
    // createShare() doing double duty as "open the manage screen", so merely
    // looking at a team's sharing state mutated it.

    /// Live CKShare records for teams this coach owns, keyed by ckRecordName.
    private var shareCache: [String: CKShare] = [:]

    /// CKShares for teams this coach *received*, keyed by ckRecordName.
    /// Populated by fetchSharedTeams, which is the only place the owner's zone
    /// is enumerated. See the note there.
    private var participantShareCache: [String: CKShare] = [:]

    /// Reads a team's share state without creating or modifying anything.
    ///
    /// A record CloudKit no longer has is reported as `.notSynced(staleRecordName: true)`
    /// rather than thrown: a team can carry a ckRecordName from a deleted record or a
    /// different container, and that is a state to recover from, not an error to show.
    func shareInfo(for team: Team) async throws -> TeamShareInfo {
        guard let recordName = team.ckRecordName else {
            return TeamShareInfo(state: .notSynced(staleRecordName: false))
        }

        // A received team is never in this coach's private database — its record
        // sits in the owner's zone in the shared database. Reading it from
        // privateDB throws unknownItem, which is how a perfectly healthy shared
        // team came to render "This team isn't in iCloud yet".
        if team.isSharedParticipant {
            return try await participantShareInfo(recordName: recordName)
        }

        let recordID = CKRecord.ID(recordName: recordName, zoneID: ckZone.zoneID)
        let teamRecord: CKRecord
        do {
            teamRecord = try await privateDB.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            shareCache[recordName] = nil
            return TeamShareInfo(state: .notSynced(staleRecordName: true))
        }
        recordCache[recordName] = teamRecord

        guard let shareRef = teamRecord.share,
              let share = try await privateDB.record(for: shareRef.recordID) as? CKShare else {
            shareCache[recordName] = nil
            return TeamShareInfo(state: .notShared)
        }

        shareCache[recordName] = share
        return Self.makeInfo(from: share)
    }

    /// Reads the state of a team this coach received from another coach.
    ///
    /// There is nothing to manage — the owner holds the share — so this reports
    /// who shared it and what this coach may do. Falls back to a shared-database
    /// refresh when the cache is cold, which is the first launch of a session
    /// before any foreground sync has run.
    private func participantShareInfo(recordName: String) async throws -> TeamShareInfo {
        if participantShareCache[recordName] == nil {
            _ = try? await fetchSharedTeams()
        }

        guard let share = participantShareCache[recordName] else {
            // The share is genuinely gone — the owner stopped sharing or removed
            // this coach. Report it as a received team with no detail rather than
            // as "not synced", which would invite the coach to fix something that
            // isn't theirs to fix.
            return TeamShareInfo(state: .participant)
        }

        return TeamShareInfo(
            state: .participant,
            ownerName: Self.displayName(for: share.owner),
            myPermission: TeamSharePermission(share.currentUserParticipant?.permission ?? .readOnly)
        )
    }

    /// Creates a share for a team at the given link permission and returns the
    /// invite URL along with the new state.
    ///
    /// If the team is already shared this returns the existing share untouched —
    /// it does not silently rewrite the permission the coach chose earlier.
    func createShare(for team: Team, permission: TeamSharePermission) async throws -> TeamShareInfo {
        guard let recordName = team.ckRecordName else {
            throw CloudKitError.notSynced
        }

        let recordID   = CKRecord.ID(recordName: recordName, zoneID: ckZone.zoneID)
        let teamRecord = try await privateDB.record(for: recordID)
        recordCache[recordName] = teamRecord

        if let shareRef = teamRecord.share,
           let existing = try await privateDB.record(for: shareRef.recordID) as? CKShare {
            // Repair only the case the link is genuinely broken by. A share saved
            // under the pre-3.0 `.none` policy rejects everyone who taps the link,
            // so it has to be opened up. A share sitting at `.readOnly` is a coach's
            // deliberate choice and is left exactly as it is — overwriting it here
            // is what made "View only" appear not to save.
            if existing.publicPermission == .none || existing.publicPermission == .unknown {
                existing.publicPermission = permission.ckPermission
                let saved = try await save(share: existing)
                shareCache[recordName] = saved
                return Self.makeInfo(from: saved)
            }
            shareCache[recordName] = existing
            return Self.makeInfo(from: existing)
        }

        let share = CKShare(rootRecord: teamRecord)
        // Titles the invite in the recipient's iCloud sharing UI.
        let shareTitle: String = team.name.isEmpty ? "My Team" : team.name
        share[CKShare.SystemFieldKey.title] = shareTitle
        // Link-based sharing: coaches forward the invite to an assistant rather
        // than pre-adding them by Apple ID, so the link itself has to grant access.
        share.publicPermission = permission.ckPermission

        let (saveResults, _) = try await privateDB.modifyRecords(saving: [teamRecord, share], deleting: [])

        if case .success(let savedRoot) = saveResults[teamRecord.recordID] {
            recordCache[recordName] = savedRoot
        }
        guard case .success(let savedRecord) = saveResults[share.recordID],
              let savedShare = savedRecord as? CKShare else {
            throw CloudKitError.shareSaveFailed
        }

        shareCache[recordName] = savedShare
        Task { @MainActor in
            Analytics.signal("team.share.created", parameters: ["permission": permission.rawValue])
        }
        return Self.makeInfo(from: savedShare)
    }

    /// Changes what a newly tapped invite link grants. Coaches who already
    /// accepted keep the permission they joined with — CloudKit stores theirs
    /// per participant, which is why the UI states the two separately.
    func setLinkPermission(_ permission: TeamSharePermission, teamRecordName: String) async throws -> TeamShareInfo {
        let share = try await share(forTeamRecordName: teamRecordName)
        share.publicPermission = permission.ckPermission
        let saved = try await save(share: share)
        shareCache[teamRecordName] = saved
        Task { @MainActor in
            Analytics.signal("team.share.link_permission_changed", parameters: ["permission": permission.rawValue])
        }
        return Self.makeInfo(from: saved)
    }

    /// Changes one participant's permission.
    func setPermission(
        _ permission: TeamSharePermission,
        forParticipant participantID: String,
        teamRecordName: String
    ) async throws -> TeamShareInfo {
        let share = try await share(forTeamRecordName: teamRecordName)
        guard let participant = share.participants.first(where: {
            $0.userIdentity.userRecordID?.recordName == participantID
        }) else {
            throw CloudKitError.participantNotFound
        }
        participant.permission = permission.ckPermission
        let saved = try await save(share: share)
        shareCache[teamRecordName] = saved
        Task { @MainActor in
            Analytics.signal("team.share.participant_permission_changed", parameters: ["permission": permission.rawValue])
        }
        return Self.makeInfo(from: saved)
    }

    /// Revokes one coach's access. The team itself is untouched.
    func removeParticipant(_ participantID: String, teamRecordName: String) async throws -> TeamShareInfo {
        let share = try await share(forTeamRecordName: teamRecordName)
        guard let participant = share.participants.first(where: {
            $0.userIdentity.userRecordID?.recordName == participantID
        }) else {
            throw CloudKitError.participantNotFound
        }
        share.removeParticipant(participant)
        let saved = try await save(share: share)
        shareCache[teamRecordName] = saved
        Task { @MainActor in
            Analytics.signal("team.share.participant_removed")
        }
        return Self.makeInfo(from: saved)
    }

    /// Deletes the share, revoking access for everyone at once. The root Team
    /// record and the owner's local copy both survive.
    func stopSharing(teamRecordName: String) async throws {
        let share = try await share(forTeamRecordName: teamRecordName)
        do {
            _ = try await privateDB.deleteRecord(withID: share.recordID)
        } catch let error as CKError where error.code == .unknownItem {
            // Already gone — that is the state we wanted.
        }
        shareCache[teamRecordName] = nil
        Task { @MainActor in
            Analytics.signal("team.share.stopped")
        }
    }

    // MARK: - Sharing Helpers

    /// Returns the cached CKShare for a team, fetching it if this is the first
    /// touch of the session.
    private func share(forTeamRecordName recordName: String) async throws -> CKShare {
        if let cached = shareCache[recordName] { return cached }

        let recordID   = CKRecord.ID(recordName: recordName, zoneID: ckZone.zoneID)
        let teamRecord = try await privateDB.record(for: recordID)
        guard let shareRef = teamRecord.share,
              let share = try await privateDB.record(for: shareRef.recordID) as? CKShare else {
            throw CloudKitError.notShared
        }
        shareCache[recordName] = share
        return share
    }

    /// Saves a modified CKShare and returns the server's copy, so the caller
    /// holds a record with a current change tag for the next edit.
    private func save(share: CKShare) async throws -> CKShare {
        let (results, _) = try await privateDB.modifyRecords(saving: [share], deleting: [])
        guard case .success(let saved) = results[share.recordID],
              let savedShare = saved as? CKShare else {
            throw CloudKitError.shareSaveFailed
        }
        return savedShare
    }

    /// Best available human name for a share participant.
    ///
    /// CloudKit only learns a name once someone accepts, and often never learns
    /// one for the current user at all, so this falls back through email/phone
    /// before giving up. Returns nil rather than a placeholder so callers can
    /// decide what an unknown coach should read as in context.
    nonisolated static func displayName(for participant: CKShare.Participant?) -> String? {
        guard let identity = participant?.userIdentity else { return nil }
        if let components = identity.nameComponents {
            let formatted = PersonNameComponentsFormatter.localizedString(from: components, style: .default)
            if !formatted.isEmpty { return formatted }
        }
        return identity.lookupInfo?.emailAddress ?? identity.lookupInfo?.phoneNumber
    }

    /// Flattens a CKShare into the value snapshot the UI renders from.
    private nonisolated static func makeInfo(from share: CKShare) -> TeamShareInfo {
        let others = share.participants
            .filter { $0.role != .owner }
            .map { ShareParticipantInfo(participant: $0) }

        return TeamShareInfo(
            state: .shared,
            url: share.url,
            linkPermission: TeamSharePermission(share.publicPermission),
            participants: others
        )
    }

    // MARK: - Error Presentation

    /// Maps a CloudKit failure onto something a coach can act on.
    ///
    /// The old share path put `error.localizedDescription` straight into an alert,
    /// which showed people a CKRecordID and a pointer address.
    nonisolated static func friendlyMessage(for error: Error) -> String {
        if let stlError = error as? CloudKitError, let message = stlError.errorDescription {
            return message
        }
        guard let ckError = error as? CKError else {
            return "Something went wrong. Try again in a moment."
        }
        switch ckError.code {
        case .networkUnavailable, .networkFailure:
            return "You're offline. Reconnect and try again."
        case .notAuthenticated:
            return "Sign in to iCloud in Settings to share a team."
        case .quotaExceeded:
            return "Your iCloud storage is full. Free up some space and try again."
        case .unknownItem:
            return "This team hasn't finished syncing to iCloud. Try again in a moment."
        case .permissionFailure:
            return "This iCloud account isn't allowed to share. Check iCloud settings for Stack the Lineup."
        case .zoneBusy, .serviceUnavailable, .requestRateLimited:
            return "iCloud is busy right now. Try again in a moment."
        case .managedAccountRestricted:
            return "Sharing is turned off for this iCloud account."
        default:
            return "iCloud couldn't complete that. Try again in a moment."
        }
    }


    // MARK: - One-Time KV Store Migration
    
    /// Migrates all existing teams from NSUbiquitousKeyValueStore to CloudKit.
    /// Runs exactly once, gated by hasCompletedCloudKitMigration in UserDefaults.
    ///
    /// If CloudKit is unavailable, migration is deferred (the gate flag is NOT set)
    /// and the KV store remains the live data source with no data loss.
    ///
    /// - Parameter teams: Current teams from LineupStore.
    /// - Returns: Updated teams with ckRecordName populated. Pass back to
    ///   LineupStore to persist via its normal save() path.
    func migrateFromKVStoreIfNeeded(teams: [Team]) async throws -> [Team] {
        guard !UserDefaults.standard.bool(forKey: migrationKey) else {
            return teams
        }
        guard !teams.isEmpty else {
            UserDefaults.standard.set(true, forKey: migrationKey)
            return teams
        }
        
        let status = try await ckContainer.accountStatus()
        guard status == .available else {
            Task { @MainActor in
                Analytics.signal("cloudkit.migration.deferred", parameters: [
                    "reason": "accountStatus.\(status.rawValue)"
                ])
            }
            throw CloudKitError.accountUnavailable
        }
        
        try await ensureZoneExists()
        
        var updatedTeams = teams
        for i in updatedTeams.indices {
            let recordName = try await saveTeam(updatedTeams[i])
            updatedTeams[i].ckRecordName = recordName
        }
        
        UserDefaults.standard.set(true, forKey: migrationKey)
        Task { @MainActor in
            Analytics.signal("cloudkit.migration.completed", parameters: [
                "teamCount": "\(teams.count)"
            ])
        }
        return updatedTeams
    }
    
    // MARK: - Helpers
    
    /// Encodes a Team to JSON data on the main actor.
    /// Team's Encodable conformance is @MainActor-isolated in Swift 6.
    /// Uses trailing-closure syntax to avoid the iOS 26 resultType: matching issue.
    private func encodeTeam(_ team: Team) async throws -> Data {
        try await MainActor.run {
            guard let data = try? JSONEncoder().encode(team) else {
                throw CloudKitError.encodingFailed
            }
            return data
        }
    }
    
    /// Writes JSON data to a temp file and wraps it in a CKAsset.
    private func makeAsset(from data: Data, teamID: UUID) throws -> CKAsset {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(teamID.uuidString).stlteam.json")
        do {
            try data.write(to: url)
        } catch {
            throw CloudKitError.encodingFailed
        }
        return CKAsset(fileURL: url)
    }
    
    /// Decodes a Team from a CKRecord's teamJSON CKAsset field.
    ///
    /// @MainActor because Team's Decodable conformance is @MainActor-isolated in Swift 6.
    /// Stamps ckRecordName from the record so the model stays in sync with CloudKit.
    /// Call with: try await MainActor.run { try CloudKitManager.decodeTeam(...) }
    @MainActor
    static func decodeTeam(from record: CKRecord, jsonField: String) throws -> Team {
        guard let asset = record[jsonField] as? CKAsset else {
            throw CloudKitError.assetMissing
        }
        guard let fileURL = asset.fileURL,
              let data = try? Data(contentsOf: fileURL) else {
            throw CloudKitError.assetReadFailed
        }
        guard var team = try? JSONDecoder().decode(Team.self, from: data) else {
            throw CloudKitError.decodingFailed
        }
        team.ckRecordName = record.recordID.recordName
        return team
    }
    // MARK: - Share Acceptance
    
    /// Accepts an incoming CKShare invitation. Called from AppDelegate when a
    /// participant taps "Accept" in a share invitation email or message.
    /// After acceptance, ContentView posts cloudKitShareAccepted to trigger a refresh.
    func acceptShare(metadata: CKShare.Metadata) async throws {
        try await ckContainer.accept(metadata)
        Task { @MainActor in
            Analytics.signal("team.share.accepted")
        }
    }

    // MARK: - Deletion

    /// Removes a team's record from the private database.
    ///
    /// Callers must go through `LineupStore.recordNameToDelete(for:)` rather
    /// than passing `team.ckRecordName` directly — a shared team's record
    /// belongs to the coach who created it, and deleting it here would destroy
    /// their team and every other participant's copy.
    ///
    /// A record that is already gone is success, not failure: CloudKit reports
    /// `unknownItem`, and treating that as an error would keep a tombstone
    /// alive for something that no longer exists.
    func deleteTeam(recordName: String) async throws {
        let recordID = CKRecord.ID(recordName: recordName, zoneID: ckZone.zoneID)
        do {
            _ = try await privateDB.deleteRecord(withID: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            return
        }
    }
}
