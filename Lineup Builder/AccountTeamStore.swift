//
//  AccountTeamStore.swift
//  Lineup Builder
//
//  Merge 0b: where teams that live in the coach's Supabase account are kept on
//  the device, so they work offline.
//
//  One folder per account, Application Support/Accounts/<user-id>/:
//    teams.json  the account's teams as the app edits them ([Team], the same
//                encoding as the UserDefaults blob)
//    sync.json   per team: the rows the server last confirmed (the base), the
//                lineup row ids, and the last push/pull; plus team deletes
//                still waiting to reach the server
//
//  Why not the UserDefaults blob: the blob is mirrored to the iCloud KV store,
//  which is per Apple ID, not per account. On a shared iPad that would leak one
//  coach's account teams into another's, and the KV store is where the July
//  2026 wipe came from. Account teams never touch the KV store or CloudKit.
//
//  Which account is signed in is a UserDefaults key, not the Supabase session,
//  so App Intents and TeamStorage can read it without the token. It is set on
//  sign-in and cleared only by an explicit sign-out or account deletion, which
//  also delete the folder: a session that merely lapses keeps the teams on
//  screen, waiting to sync.
//
//  Each file has one writer: teams.json is written only by LineupStore (through
//  `AccountTeamWriter`, which keeps saves in order), sync.json only by the sync
//  actor. Both are written atomically with file protection that still lets
//  background App Intents read after the first unlock.
//

import Foundation
import os

/// Per-team sync bookkeeping, persisted in sync.json.
nonisolated struct TeamSyncState: Codable, Equatable, Sendable {
    /// The rows the server last confirmed. Nil: never pushed.
    var base: TeamRows?
    var slots = LineupSlots()
    var lastPushAt: Date?
    var lastPullAt: Date?
    /// A friendly, name-free description of the last failure, if it hasn't
    /// been followed by a success.
    var lastError: String?
    /// The server refused this coach's writes (removed from a shared team, or
    /// the team is gone). Retrying won't help; the team is shown read-only.
    var refused = false
    /// Conflicts settled for the device since install, for diagnostics.
    var conflicts = 0
    /// The rows the server last rejected as invalid. While the team still maps
    /// to exactly these, the push isn't retried; the next edit retries it.
    var stuckRows: TeamRows?
    /// This coach's role when the team was last fetched (Merge 4). Lets a pass
    /// tell "the owner deleted it" from "I lost access to someone else's team".
    var role: TeamRole?
}

nonisolated struct AccountSyncFile: Codable, Equatable, Sendable {
    var teams: [UUID: TeamSyncState] = [:]
    /// Teams deleted on this device whose delete hasn't reached the server.
    var pendingDeletes: Set<UUID> = []
    /// Moves into the account not finished yet (Merge 1; see TeamMove).
    /// Optional so a sync.json written before Merge 1 still decodes: the
    /// synthesized decoder would reject a missing non-optional key, and a
    /// file that doesn't decode is read as empty.
    var moves: [UUID: TeamMoveRecord]?
}

nonisolated struct AccountTeamStore: Sendable {

    // MARK: - Signed-in account

    /// UserDefaults key holding the signed-in account's user id (lower-case).
    static let accountKey = "stl_account_user_id"

    static func signedInAccount(defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: accountKey)
    }

    static func setSignedInAccount(_ userID: String?, defaults: UserDefaults = .standard) {
        if let userID { defaults.set(userID.lowercased(), forKey: accountKey) }
        else { defaults.removeObject(forKey: accountKey) }
    }

    // MARK: - Location

    /// Application Support/Accounts. Injectable for tests.
    static var defaultRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Accounts", isDirectory: true)
    }

    let userID: String
    let directory: URL

    init(userID: String, root: URL = AccountTeamStore.defaultRoot) {
        self.userID = userID.lowercased()
        directory = root.appendingPathComponent(userID.lowercased(), isDirectory: true)
    }

    /// The store for the signed-in account, or nil when signed out.
    static func current(defaults: UserDefaults = .standard, root: URL = AccountTeamStore.defaultRoot) -> AccountTeamStore? {
        signedInAccount(defaults: defaults).map { AccountTeamStore(userID: $0, root: root) }
    }

    private var teamsURL: URL { directory.appendingPathComponent("teams.json") }
    private var syncURL: URL { directory.appendingPathComponent("sync.json") }

    // MARK: - Teams

    enum LoadResult: Equatable {
        case loaded([Team])
        /// No file yet: this account has no teams on this device.
        case empty
        /// A file exists but won't decode. Callers must leave it alone.
        case decodeFailed

        static func == (a: LoadResult, b: LoadResult) -> Bool {
            switch (a, b) {
            case (.empty, .empty), (.decodeFailed, .decodeFailed): return true
            case (.loaded(let x), .loaded(let y)): return x.map(\.id) == y.map(\.id)
            default: return false
            }
        }
    }

    func loadTeams() -> LoadResult {
        guard let data = try? Data(contentsOf: teamsURL) else { return .empty }
        guard let teams = try? JSONDecoder().decode([Team].self, from: data) else { return .decodeFailed }
        return .loaded(teams)
    }

    func saveTeams(_ teams: [Team]) throws {
        try write(JSONEncoder().encode(teams), to: teamsURL)
    }

    // MARK: - Sync state

    func loadSync() -> AccountSyncFile {
        guard let data = try? Data(contentsOf: syncURL),
              let file = try? JSONDecoder().decode(AccountSyncFile.self, from: data)
        else { return AccountSyncFile() }
        return file
    }

    func saveSync(_ file: AccountSyncFile) throws {
        try write(JSONEncoder().encode(file), to: syncURL)
    }

    // MARK: - Wipe

    /// Deletes everything this account keeps on the device. Sign-out and
    /// account deletion only.
    func wipe() throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }

    // MARK: - Writing

    private func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

/// Writes teams.json in the order saves happen. LineupStore encodes off the
/// main thread, one detached task per save, and two of those can finish out of
/// order; this drops any write older than the newest one already written.
actor AccountTeamWriter {
    static let shared = AccountTeamWriter()

    private var written: UInt64 = 0

    /// - Parameter isSignedIn: whether `store`'s account is still the signed-in
    ///   one. Injectable for tests; production reads UserDefaults.standard.
    func write(_ teams: [Team], sequence: UInt64, to store: AccountTeamStore,
               isSignedIn: (@Sendable (String) -> Bool)? = nil) {
        guard sequence > written else { return }
        // A save that was in flight when the coach signed out must not
        // recreate the folder sign-out just deleted.
        let signedIn = isSignedIn?(store.userID) ?? (AccountTeamStore.signedInAccount() == store.userID)
        guard signedIn else { return }
        do {
            try store.saveTeams(teams)
            written = sequence
        } catch {
            Log.storage.error("Couldn't write account teams: \(error.localizedDescription, privacy: .public)")
        }
    }
}
