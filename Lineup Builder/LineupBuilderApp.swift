import CloudKit
import SwiftUI
import TelemetryDeck
import os

// MARK: - App

@main
struct LineupBuilderApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var purchaseManager = PurchaseManager()

    init() {
        let config = TelemetryDeck.Config(appID: "F6A09F00-2EFC-4DAD-9137-3350F267E78A")
        TelemetryDeck.initialize(config: config)

        // Must run before any tip can be displayed. Also migrates coaches off
        // the pre-TipKit onboarding flags.
        TipsConfigurator.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(purchaseManager)
                .task {
                    await purchaseManager.checkEntitlement()
                }
                .task {
                    // Covers the first launch after installing a build that adds
                    // indexing, and any roster change made while the app was gone
                    // (a CloudKit pull from another device). Subsequent edits are
                    // picked up by the hook in LineupStore.saveLocalOnly().
                    await STLSpotlightIndexer.reindexIfNeeded()
                }
        }
    }
}

// MARK: - AppDelegate
//
// Wires up SceneDelegate so UIKit routes CloudKit share acceptance to the
// scene-level handler. In iOS 13+ scene-based apps (which SwiftUI WindowGroup
// always creates), iOS calls windowScene(_:userDidAcceptCloudKitShareWith:) on
// the UIWindowSceneDelegate — NOT application(_:userDidAcceptCloudKitShareWith:)
// on UIApplicationDelegate. Without a registered SceneDelegate, that call is
// silently dropped and share acceptance never fires.

class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let config = UISceneConfiguration(
            name: "Default Configuration",
            sessionRole: connectingSceneSession.role
        )
        config.delegateClass = SceneDelegate.self
        return config
    }

    // MARK: - APNs Token Registration
    //
    // Called by iOS after UIApplication.registerForRemoteNotifications() succeeds.
    //
    // Hands the token to DeviceTokenManager *first*, then posts. The post alone
    // could not carry this: on a cold launch this callback beats ContentView's
    // subscription, and a post with no subscriber is lost — which left the
    // device with no token cached and no DeviceToken record for the whole
    // session. See backlog 1.9. The notification stays for the already-running
    // case, where it prompts the write; the cached token is what makes a cold
    // launch survive.

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Log.push.info("APNs registration succeeded")
        MainActor.assumeIsolated {
            DeviceTokenManager.shared.receiveToken(deviceToken)
        }
        NotificationCenter.default.post(
            name: .apnsTokenReceived,
            object: deviceToken
        )
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Log.push.error("APNs registration failed: \(error.localizedDescription, privacy: .public)")
    }
}

// MARK: - SceneDelegate
//
// Handles the CloudKit share acceptance entry point for scene-based SwiftUI apps.
// When a coach taps a share link, iOS calls windowScene(_:userDidAcceptCloudKitShareWith:)
// here. We accept the metadata via CKContainer, then post a notification so
// ContentView's onReceive observer can call fetchCloudKitChanges() and surface
// the shared team.

class SceneDelegate: NSObject, UIWindowSceneDelegate {

    func windowScene(
        _ windowScene: UIWindowScene,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        Log.sync.info("Accepting CloudKit share from windowScene")
        Task {
            do {
                try await CloudKitManager.shared.acceptShare(metadata: cloudKitShareMetadata)
                // Accepting an invite is the coach deliberately re-adding a team.
                // If they had left this one before, its tombstone would make the
                // merge refuse the share — silently, and forever. Clear it before
                // the refresh runs.
                let rootRecordName = cloudKitShareMetadata.hierarchicalRootRecordID?.recordName
                await MainActor.run {
                    // Record it before posting. Tapping an invite usually cold-starts
                    // the app, and this callback can land before ContentView has
                    // subscribed to the notification — in which case the post goes
                    // nowhere, the fetch never runs, and the team turns up minutes
                    // later via ordinary sync without ever becoming active. The
                    // notification stays for the already-running case; the stored
                    // value is what ContentView drains on first appear.
                    PendingShareAcceptance.record(rootRecordName: rootRecordName)
                    NotificationCenter.default.post(
                        name: .cloudKitShareAccepted,
                        object: nil,
                        userInfo: rootRecordName.map { ["rootRecordName": $0] }
                    )
                }
            } catch {
                Log.sync.error("Failed to accept CloudKit share: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

// MARK: - PendingShareAcceptance
//
// A just-accepted share invitation, held until ContentView can act on it.
//
// NotificationCenter alone can't carry this: the accept callback and the first
// render race on a cold launch, and a post with no subscriber is simply lost.

@MainActor
enum PendingShareAcceptance {

    struct Accepted {
        /// Nil when CloudKit gave us no hierarchical root — the team is then
        /// identified by being the one that wasn't there before.
        let rootRecordName: String?
    }

    /// Held separately from the record name: the name is optional, so it can't
    /// double as the "something is waiting" flag.
    private static var pending: Accepted?

    static func record(rootRecordName: String?) {
        pending = Accepted(rootRecordName: rootRecordName)
    }

    /// Returns the pending acceptance exactly once, so the already-running path
    /// and the cold-launch path can't both act on it.
    static func take() -> Accepted? {
        defer { pending = nil }
        return pending
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// Posted after a CloudKit share invitation is accepted.
    /// ContentView observes this to refresh the teams list.
    static let cloudKitShareAccepted = Notification.Name("cloudKitShareAccepted")

    /// Posted when APNs provides a device token.
    /// ContentView observes this to forward the token to DeviceTokenManager.
    static let apnsTokenReceived = Notification.Name("apnsTokenReceived")
}
