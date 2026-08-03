import Foundation

// MARK: - TeamTombstones
//
// A record of teams this device deleted, so a delete can't be undone by a sync.
//
// The bug this exists for: `deleteTeam(id:)` removed a team locally and never
// touched CloudKit, so the CKRecord survived. `mergeCloudKitChanges` appends any
// server team with no local match — which is every team on a fresh install — so
// every team a coach had ever deleted came back. Deleting the record fixes the
// common case; this fixes the rest of it.
//
// Two IDs per tombstone, because either can be the one we have:
//   * `ckRecordName` is what a server team arrives carrying.
//   * `teamID` is all we have for a team deleted before it was ever uploaded,
//     and it survives a record being re-created under a new name.
//
// Deliberately device-local. This guards *this* device against a delete that
// failed or was deferred (offline, CloudKit throttling). It is not a
// synchronization mechanism — another device that still holds the team learns
// about the deletion through CloudKit, not through this.
//
// `forget` matters as much as `remember`: a coach who leaves a shared team and
// is later re-invited, or who deletes a team and re-imports it from a file, must
// not be silently blocked by a tombstone from a month ago.

nonisolated struct TeamTombstones: Codable, Equatable {

    /// One deleted team. Stored as a pair rather than two independent lists so
    /// that clearing a tombstone clears *all* of it — share acceptance only
    /// knows the record name, and forgetting that while leaving the team UUID
    /// behind would keep the team blocked with nothing to show why.
    struct Entry: Codable, Equatable {
        let teamID: UUID
        let recordName: String?

        func matches(teamID: UUID, recordName: String?) -> Bool {
            if self.teamID == teamID { return true }
            if let mine = self.recordName, !mine.isEmpty,
               let theirs = recordName, !theirs.isEmpty,
               mine == theirs { return true }
            return false
        }
    }

    /// Newest last. Capped so a long-lived install can't grow without bound — a
    /// coach deletes teams a handful of times a season, so the limit is far past
    /// any real usage and exists only to bound the worst case.
    private(set) var entries: [Entry] = []

    static let limit = 200

    init() {}

    init(entries: [Entry] = []) {
        self.entries = entries
    }

    var isEmpty: Bool { entries.isEmpty }

    /// Whether a team arriving from CloudKit should be refused.
    ///
    /// Matching on *either* identifier is deliberate. A team deleted locally
    /// before its first upload has no record name; a record re-created by
    /// another device has a new record name but the same team UUID.
    func blocks(teamID: UUID, recordName: String?) -> Bool {
        entries.contains { $0.matches(teamID: teamID, recordName: recordName) }
    }

    mutating func remember(teamID: UUID, recordName: String?) {
        guard !entries.contains(where: { $0.teamID == teamID }) else { return }
        entries.append(Entry(teamID: teamID, recordName: recordName))
        if entries.count > Self.limit {
            entries.removeFirst(entries.count - Self.limit)
        }
    }

    /// Clears a tombstone so the team can come back. Called whenever the coach
    /// deliberately re-adds one: accepting a share again, importing a team file,
    /// or restoring from a backup. Either identifier clears the whole entry.
    mutating func forget(teamID: UUID?, recordName: String?) {
        entries.removeAll { entry in
            if let teamID, entry.teamID == teamID { return true }
            if let mine = entry.recordName, !mine.isEmpty,
               let theirs = recordName, !theirs.isEmpty,
               mine == theirs { return true }
            return false
        }
    }
}
