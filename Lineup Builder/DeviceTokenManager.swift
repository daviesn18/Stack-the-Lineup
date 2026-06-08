import CloudKit
import UIKit

// MARK: - DeviceTokenManager
//
// Registers for APNs, receives the device token, and writes it to CloudKit
// so the Cloudflare Worker can look it up when sending push notifications.
//
// CloudKit schema — record type "DeviceToken" in privateDB:
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

    // MARK: - APNs Registration

    /// Call once on launch. Registers for remote notifications so iOS delivers
    /// the device token via AppDelegate.didRegisterForRemoteNotificationsWithDeviceToken.
    func registerForRemoteNotifications() {
        UIApplication.shared.registerForRemoteNotifications()
    }

    /// Called by AppDelegate when iOS provides (or refreshes) the device token.
    /// Writes the token to CloudKit for every team the coach is on.
    func didRegister(deviceToken: Data, store: LineupStore) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        cachedTokenHex = hex
        print("📲 APNs device token: \(hex.prefix(16))...")
        Task {
            await saveTokenForAllTeams(tokenHex: hex, store: store)
        }
    }

    /// Called when the coach switches teams — ensures the new team also has
    /// a token record so it can send notifications to this device.
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

        // Use a deterministic record name so the same device always updates
        // the same record rather than creating duplicates.
        let recordName = "devicetoken-\(teamID)-\(tokenHex.prefix(16))"
        let recordID   = CKRecord.ID(recordName: recordName)

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
            print("✅ DeviceToken saved to CloudKit for team \(teamID.prefix(8))...")
        } catch {
            print("⚠️ DeviceToken save failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Token Cleanup

    /// Removes all device token records for a specific team from this device.
    /// Call when a coach leaves a shared team so they stop receiving its notifications.
    func removeTokens(for teamID: String) async {
        let db = CKContainer(identifier: containerID).publicCloudDatabase

        // Query for all tokens belonging to this team on this device.
        let predicate = NSPredicate(format: "teamID == %@", teamID)
        let query = CKQuery(recordType: recordType, predicate: predicate)

        do {
            let (results, _) = try await db.records(matching: query)
            for (recordID, result) in results {
                if case .success = result {
                    try? await db.deleteRecord(withID: recordID)
                }
            }
            print("🗑️ Removed DeviceToken records for team \(teamID.prefix(8))...")
        } catch {
            print("⚠️ DeviceToken removal failed: \(error.localizedDescription)")
        }
    }
}
