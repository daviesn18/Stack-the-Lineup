import CloudKit
import Foundation

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
    
    // MARK: - CKShare Creation
    
    /// Creates a CKShare for the given team. The team must already have a ckRecordName.
    ///
    /// If the record is already shared, returns the existing CKShare without error.
    /// Public permission is .readWrite so any coach who receives the link can accept
    /// it without being explicitly added as a participant first. The head coach
    /// shares the URL via UIActivityViewController; recipients tap to accept.
    ///
    /// - Returns: (share, container) ready to pass to CloudKitSharingView.
    func createShare(for team: Team) async throws -> (CKShare, CKContainer) {
        guard let recordName = team.ckRecordName else {
            throw CloudKitError.recordNotFound("(unsaved team — call saveTeam first)")
        }
        
        let recordID   = CKRecord.ID(recordName: recordName, zoneID: ckZone.zoneID)
        let teamRecord = try await privateDB.record(for: recordID)
        recordCache[recordName] = teamRecord
        
        if let shareRef = teamRecord.share {
            let existingRecord = try await privateDB.record(for: shareRef.recordID)
            if let existingShare = existingRecord as? CKShare {
                // Patch permission if the share was created before .readWrite was
                // adopted. Without this, shares created under the old .none policy
                // continue to reject recipients even after a code update.
                if existingShare.publicPermission != .readWrite {
                    existingShare.publicPermission = .readWrite
                    let (patchResults, _) = try await privateDB.modifyRecords(
                        saving: [existingShare],
                        deleting: []
                    )
                    if case .success(let patched) = patchResults[existingShare.recordID],
                       let patchedShare = patched as? CKShare {
                        return (patchedShare, ckContainer)
                    }
                }
                return (existingShare, ckContainer)
            }
        }
        
        let share = CKShare(rootRecord: teamRecord)
        // .readWrite allows anyone with the link to accept the share.
        // This is intentional — coaches forward the link to assistants without
        // a per-participant invite step. The team JSON is not sensitive data.
        share.publicPermission = .readWrite
        
        let (saveResults, _) = try await privateDB.modifyRecords(
            saving: [teamRecord, share],
            deleting: []
        )
        
        if case .success(let savedRoot) = saveResults[teamRecord.recordID] {
            recordCache[recordName] = savedRoot
        }
        
        if case .success(let savedRecord) = saveResults[share.recordID],
           let savedShare = savedRecord as? CKShare {
            return (savedShare, ckContainer)
        }
        return (share, ckContainer)
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
}
