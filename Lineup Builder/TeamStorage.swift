import Foundation

// MARK: - TeamStorage
//
// Single source of truth for READING the persisted `[Team]` blob.
//
// Both LineupStore.applyStoredData() and the App Intents layer read through here.
// An intent that decoded storage on its own path would silently drift from the
// app the first time the local-vs-iCloud arbitration rules changed, so there is
// deliberately only one implementation of that logic.
//
// Read-only by design. Writes stay in LineupStore.saveLocalOnly(), which owns the
// CloudKit push, the KV-store safety threshold, and the widget snapshot bridge.
//
// `nonisolated` because App Intents `perform()` runs off the main actor and must
// be able to call this. Nothing here touches UI state.

nonisolated enum TeamStorage {

    // MARK: - Storage Keys
    // LineupStore.saveLocalOnly() writes these same keys.

    static let teamsKey      = "stl_teams"
    static let savedAtKey    = "stl_teams_saved_at"
    static let activeTeamKey = "stl_active_team_id"

    /// Teams this device deleted. Local-only and deliberately NOT mirrored to
    /// the iCloud KV store: it guards this device against its own delete failing
    /// or being deferred, and pushing it to the shared KV blob would let a debug
    /// build's tombstones suppress teams on a real device.
    static let tombstonesKey = "stl_deleted_teams"

    // MARK: - Tombstones

    static func loadTombstones(defaults: UserDefaults = .standard) -> TeamTombstones {
        guard let data = defaults.data(forKey: tombstonesKey),
              let decoded = try? JSONDecoder().decode(TeamTombstones.self, from: data)
        else { return TeamTombstones() }
        return decoded
    }

    static func saveTombstones(_ tombstones: TeamTombstones, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(tombstones) else { return }
        defaults.set(data, forKey: tombstonesKey)
    }

    /// Record names for teams deleted elsewhere that the coach chose to keep
    /// here. Local-only for the same reason as the tombstones.
    static let declinedDeletionsKey = "stl_declined_remote_deletions"

    static func loadDeclinedDeletions(defaults: UserDefaults = .standard) -> Set<String> {
        Set(defaults.stringArray(forKey: declinedDeletionsKey) ?? [])
    }

    static func saveDeclinedDeletions(_ names: Set<String>, defaults: UserDefaults = .standard) {
        defaults.set(Array(names), forKey: declinedDeletionsKey)
    }

    /// Record names this device has seen arrive through the shared database —
    /// the durable form of `Team.isSharedParticipant`.
    ///
    /// THE FLAG CANNOT DO THIS JOB. `Team.init(from:)` forces
    /// `isSharedParticipant` to false on every decode and only `fetchSharedTeams`
    /// stamps it true again, so it is accurate only for teams that are *still*
    /// shared. A team the head coach deleted is by definition absent from that
    /// fetch, so it decodes as an ordinary owned team on the next cold launch and
    /// the deletion becomes undetectable. Writing the record name down at the
    /// moment it arrives is what survives the relaunch.
    ///
    /// Local-only, like the tombstones: this is one device's record of what it
    /// received, not state to synchronise.
    static let receivedSharesKey = "stl_received_share_records"

    static func loadReceivedShares(defaults: UserDefaults = .standard) -> Set<String> {
        Set(defaults.stringArray(forKey: receivedSharesKey) ?? [])
    }

    static func saveReceivedShares(_ names: Set<String>, defaults: UserDefaults = .standard) {
        defaults.set(Array(names), forKey: receivedSharesKey)
    }

    // MARK: - Load Result

    /// The three outcomes callers must handle differently.
    ///
    /// `empty` and `decodeFailed` are deliberately NOT collapsed into "no teams".
    /// Treating a decode failure as an empty store is exactly what would let a
    /// schema mismatch cascade into migrateOrCreateDefaultTeam() and overwrite
    /// iCloud with a blank team — see the SAFETY RULE on applyStoredData().
    enum LoadResult {
        /// Storage held a blob and it decoded cleanly.
        case loaded(teams: [Team], activeID: UUID?)
        /// Genuine first launch — no blob in either store.
        case empty(activeID: UUID?)
        /// A blob exists but will not decode. Callers must leave existing state alone.
        case decodeFailed
    }

    // MARK: - Source Arbitration

    /// Whether the iCloud KV copy should win over the local one.
    /// Cloud wins only when it exists and is strictly newer; ties go local.
    static func shouldPreferCloudBlob(cloudData: Data?, cloudSavedAt: TimeInterval,
                                      localData: Data?, localSavedAt: TimeInterval) -> Bool {
        guard cloudData != nil else { return false }
        guard localData != nil else { return true }
        return cloudSavedAt > localSavedAt
    }

    // MARK: - Load

    /// Reads the teams blob from UserDefaults and the iCloud KV store and returns
    /// whichever copy has the newer save-timestamp, decoded. Safe to call repeatedly.
    ///
    /// DEBUG builds read local data only: the KV store is shared across every
    /// install of the bundle ID on the same Apple ID with no dev/prod split, so a
    /// debug read/write pair can clobber real devices. This caused the July 2026
    /// data wipe.
    ///
    /// `defaults` is injectable **for tests only**; production always wants
    /// `.standard`. The unit tests run inside the real app as their test host, so
    /// `.standard` there is the *live app's* store — and `LineupStore.saveLocalOnly()`
    /// writes these same three keys from a detached `Task`. A test that cleared the
    /// keys could have the app write them back before it read, which is exactly what
    /// made `testNoStoredDataReportsEmpty` fail on any simulator that had ever held a
    /// roster. Passing a private suite removes the shared mutable state rather than
    /// trying to out-race it. Note this injects the *local* store only: the KV store
    /// is untouched because DEBUG never reads it.
    static func load(defaults: UserDefaults = .standard) -> LoadResult {
        let localData = defaults.data(forKey: teamsKey)

        #if DEBUG
        let teamsData = localData
        let savedID   = defaults.string(forKey: activeTeamKey)
        #else
        let icloud = NSUbiquitousKeyValueStore.default
        let preferCloud = shouldPreferCloudBlob(
            cloudData:    icloud.data(forKey: teamsKey),
            cloudSavedAt: icloud.double(forKey: savedAtKey),
            localData:    localData,
            localSavedAt: defaults.double(forKey: savedAtKey)
        )
        let teamsData = preferCloud ? icloud.data(forKey: teamsKey) : localData
        let savedID = preferCloud
            ? (icloud.string(forKey: activeTeamKey) ?? defaults.string(forKey: activeTeamKey))
            : (defaults.string(forKey: activeTeamKey) ?? icloud.string(forKey: activeTeamKey))
        #endif

        let activeID = savedID.flatMap { UUID(uuidString: $0) }

        guard let data = teamsData else { return .empty(activeID: activeID) }

        guard let decoded = try? JSONDecoder().decode([Team].self, from: data) else {
            return .decodeFailed
        }

        // Sort each team's game logs by gameDate descending — corrects any logs
        // stored out of order due to the archive-order bug.
        let normalized = decoded.map { team -> Team in
            var t = team
            t.gameLogs = t.gameLogs.sorted { $0.gameDate > $1.gameDate }
            return t
        }

        return .loaded(teams: normalized, activeID: activeID)
    }

    // MARK: - Intent Convenience

    /// Flat read for callers that only need the data, with no interest in the
    /// first-launch/decode-failure distinction — i.e. every App Intent, which
    /// should report "no teams yet" identically in both cases rather than
    /// attempting recovery. Never mutates storage.
    ///
    /// `defaults` is injectable for tests on the same terms as `load(defaults:)`.
    static func loadTeamsForReading(defaults: UserDefaults = .standard) -> (teams: [Team], activeTeam: Team?) {
        guard case .loaded(let teams, let activeID) = load(defaults: defaults) else {
            return ([], nil)
        }
        let active = teams.first { $0.id == activeID } ?? teams.first
        return (teams, active)
    }
}
