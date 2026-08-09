import CloudKit
import UIKit
import os

// MARK: - DeviceTokenManager
//
// Registers for APNs, receives the device token, and writes it to CloudKit
// so the Cloudflare Worker can look it up when sending push notifications.
//
// CloudKit schema — record type "DeviceToken" in the PUBLIC database (the
// Worker has to be able to read it, which it can't do in a user's private DB):
//   teamID    (String) — the team this token belongs to
//   coachName (String) — display name of the coach on this device
//   apnsToken (String) — hex-encoded APNs device token
//   updatedAt (Date)   — last registration time
//
// One record per (teamID, device). On re-registration the record is updated
// in place so there are no duplicates. Stale tokens are cleaned up by the
// Worker when APNs returns 410.

@MainActor
final class DeviceTokenManager {

    static let shared = DeviceTokenManager()
    private init() {}

    private let recordType = "DeviceToken"
    private let containerID = "iCloud.com.nickdavies.LineupBuilder.Lineup-Builder"

    // Cached token string so we can register for all teams after a team switch.
    private var cachedTokenHex: String?

    /// Set when a token arrives, cleared when it has been written to CloudKit.
    /// Held separately from the token itself: the token stays cached for the
    /// whole session, so it can't double as the "still needs writing" flag.
    private var needsFlush = false

    // MARK: - APNs Registration

    /// Call once on launch. Registers for remote notifications so iOS delivers
    /// the device token via AppDelegate.didRegisterForRemoteNotificationsWithDeviceToken.
    func registerForRemoteNotifications() {
        UIApplication.shared.registerForRemoteNotifications()
    }

    /// Called by AppDelegate the moment iOS provides (or refreshes) the token.
    ///
    /// Caches it and nothing else. **Deliberately takes no `LineupStore`**, so
    /// it can run before there is a view — which is the whole point: on a cold
    /// launch APNs calls back before `ContentView` has subscribed to anything,
    /// and the token used to be posted through NotificationCenter with
    /// `ContentView` as its only listener. A post with no subscriber is lost,
    /// `cachedTokenHex` stayed nil for the entire session, and every writer
    /// below then no-opped on its own `guard let hex` — so the device wrote no
    /// `DeviceToken` record at all and silently received no notifications.
    /// That was backlog 1.9, found on device 9 Aug 2026.
    ///
    /// Same shape as `PendingShareAcceptance`, and for the same reason.
    func receiveToken(_ deviceToken: Data) {
        cachedTokenHex = deviceToken.map { String(format: "%02x", $0) }.joined()
        needsFlush = true
        Log.push.info("Received APNs device token")
    }

    /// Writes the cached token to CloudKit for every team the coach is on.
    ///
    /// Call from anywhere a `LineupStore` is in hand — `ContentView` does it
    /// both on becoming active and on the token notification, so whichever
    /// happens first performs the write and the other finds nothing to do.
    /// No-ops when no token has arrived yet; `receiveToken` arms it when one
    /// does, and the next call through either entry point picks it up.
    func flushPendingRegistration(store: LineupStore) {
        guard needsFlush, let hex = cachedTokenHex else { return }
        needsFlush = false
        Task {
            await saveTokenForAllTeams(tokenHex: hex, store: store)
        }
    }

    /// Called from `LineupStore.switchTeam(to:)` — ensures the newly active team
    /// also has a token record so it can send notifications to this device.
    ///
    /// No-ops before APNs has handed us a token. That's the launch ordering, not
    /// an error: `didRegister` writes every team the coach already had, and this
    /// covers the ones added afterwards.
    func refreshTokenForCurrentTeam(store: LineupStore) {
        guard let hex = cachedTokenHex else { return }
        Task {
            await saveToken(
                tokenHex: hex,
                teamID: store.activeTeam.id.uuidString,
                coachName: store.activeTeam.coachName
            )
        }
    }

    /// Registers this device for a specific team, whether or not it is active.
    ///
    /// Called when a shared team first arrives from the shared database. Until
    /// this existed, the only writers were `didRegister` — which iterates the
    /// teams that exist *at launch* — and `refreshTokenForCurrentTeam`, which
    /// covers the active team only. A team joined mid-session therefore had no
    /// DeviceToken record at all, so the Worker had nothing to push to and the
    /// coach silently received no notifications for it until the next cold start.
    ///
    /// No-ops before APNs has handed us a token; the flush covers that case when
    /// one arrives, because by then the team is in `store.teams`. Since 1.9 the
    /// token is cached the instant APNs provides it, so this guard now means
    /// "APNs hasn't answered yet" rather than "the token was dropped".
    func registerToken(forTeamID teamID: UUID, coachName: String) {
        guard let hex = cachedTokenHex else { return }
        Task {
            await saveToken(tokenHex: hex, teamID: teamID.uuidString, coachName: coachName)
        }
    }

    // MARK: - CloudKit Write

    private func saveTokenForAllTeams(tokenHex: String, store: LineupStore) async {
        for team in store.teams {
            await saveToken(
                tokenHex: tokenHex,
                teamID: team.id.uuidString,
                coachName: team.coachName
            )
        }
    }

    private func saveToken(tokenHex: String, teamID: String, coachName: String) async {
        let db = CKContainer(identifier: containerID).publicCloudDatabase

        let recordID = CKRecord.ID(recordName: Self.recordName(teamID: teamID, tokenHex: tokenHex))

        // Fetch existing record or create new one.
        let record: CKRecord
        do {
            record = try await db.record(for: recordID)
        } catch {
            record = CKRecord(recordType: recordType, recordID: recordID)
        }

        record["teamID"]    = teamID as CKRecordValue
        record["coachName"] = coachName as CKRecordValue
        record["apnsToken"] = tokenHex as CKRecordValue
        record["updatedAt"] = Date() as CKRecordValue

        do {
            try await db.save(record)
            Log.push.info("DeviceToken saved for team \(teamID)")
        } catch {
            Log.push.error("DeviceToken save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Token Cleanup

    /// Removes **this device's** token record for a team.
    ///
    /// Called from `LineupStore.deleteTeam(id:)`. Skipping it leaves the record
    /// in the public database, and the Worker keeps finding it — so a coach who
    /// leaves a shared team goes on receiving that team's notifications.
    ///
    /// Deletes by the deterministic record name rather than querying on
    /// `teamID`. That is not a micro-optimization: the DeviceToken record type
    /// lives in the PUBLIC database, so a `teamID == %@` query returns every
    /// coach's token for that team, and deleting the results would silence
    /// notifications for the whole roster because one person left.
    ///
    /// No-ops when APNs hasn't handed us a token this launch — without it we
    /// can't name our own record, and there is nothing to remove anyway if this
    /// device never registered.
    func removeTokens(for teamID: String) async {
        guard let hex = cachedTokenHex else {
            Log.push.info("No APNs token held; nothing to remove for this team")
            return
        }

        let db = CKContainer(identifier: containerID).publicCloudDatabase
        let recordID = CKRecord.ID(recordName: Self.recordName(teamID: teamID, tokenHex: hex))

        do {
            _ = try await db.deleteRecord(withID: recordID)
            Log.push.info("Removed this device's DeviceToken for team \(teamID)")
        } catch {
            Log.push.error("DeviceToken removal failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// One record per (team, device). Deterministic so re-registering updates in
    /// place instead of creating duplicates — and so removal can address the
    /// record directly.
    private static func recordName(teamID: String, tokenHex: String) -> String {
        "devicetoken-\(teamID)-\(tokenHex.prefix(16))"
    }
}
