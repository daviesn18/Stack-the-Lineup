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

    // MARK: - Launch
    //
    // Installs the notification delegate before launching finishes.
    //
    // A tap that cold-launches the app has its response delivered almost
    // immediately, and iOS discards it if no delegate is registered yet.
    // `NotificationManager` registers itself on init, but it is a lazy static
    // and its first touch was `ContentView`'s requestPermissionIfNeeded() — a
    // view lifecycle, which has not run this early. So a tap on a *backgrounded*
    // app worked, because the delegate survived from the previous launch, while
    // a tap on a terminated one silently did nothing. That is the common case
    // for a push, and it is the half of backlog 3.10 that the simulator caught
    // and the warm test did not.
    //
    // Same shape as ~~1.9~~, where the APNs token arrived before there was a
    // view to receive it. Anything iOS hands back at launch needs a receiver
    // that exists at launch, not one a view happens to create later.

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        NotificationManager.shared.installDelegate()
        return true
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
                    TeamStorage.saveLastShareAccept(
                        ShareAcceptOutcome(
                            succeeded: true,
                            at: Date(),
                            detail: "",
                            rootRecordName: rootRecordName
                        )
                    )
                    NotificationCenter.default.post(
                        name: .cloudKitShareAccepted,
                        object: nil,
                        userInfo: rootRecordName.map { ["rootRecordName": $0] }
                    )
                }
            } catch {
                // A failed accept used to only reach the log, which made it
                // invisible: the coach saw the join sheet, tapped Join, the app
                // opened, and nothing arrived — indistinguishable from success.
                // Record it durably (for the diagnostics report) and surface it,
                // so "I tapped Join and nothing happened" has an on-device answer.
                Log.sync.error("Failed to accept CloudKit share: \(error.localizedDescription, privacy: .public)")
                let friendly = CloudKitManager.friendlyMessage(for: error)
                let rootRecordName = cloudKitShareMetadata.hierarchicalRootRecordID?.recordName
                await MainActor.run {
                    TeamStorage.saveLastShareAccept(
                        ShareAcceptOutcome(
                            succeeded: false,
                            at: Date(),
                            detail: friendly,
                            rootRecordName: rootRecordName
                        )
                    )
                    // Same cold-launch race as the success path: the accept can
                    // land before ContentView subscribes, so the stored value is
                    // what a fresh launch drains, and the post covers the
                    // already-running case.
                    PendingShareAcceptFailure.record(message: friendly)
                    NotificationCenter.default.post(
                        name: .cloudKitShareAcceptFailed,
                        object: nil,
                        userInfo: ["message": friendly]
                    )
                }
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

// MARK: - PendingShareAcceptFailure
//
// A just-failed share acceptance, held until ContentView can alert the coach.
// Mirrors PendingShareAcceptance: on a cold launch the accept callback beats the
// first render, so a posted notification reaches nobody and the failure would go
// unseen — the very thing this is meant to end.

@MainActor
enum PendingShareAcceptFailure {

    /// A friendly, name-free message. Nil means nothing is waiting.
    private static var message: String?

    static func record(message: String) {
        Self.message = message
    }

    /// Returns the pending failure exactly once, so the already-running path and
    /// the cold-launch path can't both alert for the same failure.
    static func take() -> String? {
        defer { message = nil }
        return message
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// Posted after a CloudKit share invitation is accepted.
    /// ContentView observes this to refresh the teams list.
    static let cloudKitShareAccepted = Notification.Name("cloudKitShareAccepted")

    /// Posted when accepting a CloudKit share invitation fails.
    /// ContentView observes this to tell the coach the invite didn't take.
    static let cloudKitShareAcceptFailed = Notification.Name("cloudKitShareAcceptFailed")

    /// Posted when APNs provides a device token.
    /// ContentView observes this to forward the token to DeviceTokenManager.
    static let apnsTokenReceived = Notification.Name("apnsTokenReceived")
}
