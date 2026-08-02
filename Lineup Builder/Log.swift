import Foundation
import os

// MARK: - Log
//
// The app's os.Logger instances, one per subsystem worth filtering on in
// Console.app.
//
// These replace 23 `print()` calls that shipped in Release. print() writes to
// stdout unconditionally, with no level, no category, no way to filter, and —
// the reason this mattered — no redaction. DeviceTokenManager was printing the
// first 16 hex characters of the APNs device token on every launch.
//
// Privacy: os.Logger redacts interpolated dynamic strings by default and leaves
// literals public, which is the right default. Where an error description is
// worth reading in a Release log it's marked `.public` explicitly — those are
// framework-generated strings ("The Internet connection appears to be
// offline"), not coach or player data. Anything derived from user content, team
// identifiers, or credentials is left to the default.
//
// `nonisolated` because the project defaults types to `@MainActor` and Logger
// is Sendable; the detached save task and off-main App Intents both log.

nonisolated enum Log {

    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.nickdavies.LineupBuilder"

    /// CloudKit push/fetch, the iCloud KV store, migration.
    static let sync = Logger(subsystem: subsystem, category: "sync")

    /// Reading and writing the local teams blob.
    static let storage = Logger(subsystem: subsystem, category: "storage")

    /// APNs registration, device token records, the notification Worker.
    static let push = Logger(subsystem: subsystem, category: "push")

    /// CoreSpotlight indexing.
    static let spotlight = Logger(subsystem: subsystem, category: "spotlight")
}
