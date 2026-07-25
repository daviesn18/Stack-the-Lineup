import CloudKit
import SwiftUI
import TelemetryDeck

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
    // Posts the token via NotificationCenter so ContentView can forward it to
    // DeviceTokenManager with full LineupStore context.

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        print("📲 APNs registration succeeded")
        NotificationCenter.default.post(
            name: .apnsTokenReceived,
            object: deviceToken
        )
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("⚠️ APNs registration failed: \(error.localizedDescription)")
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
        print("🔵 windowScene userDidAcceptCloudKitShareWith fired")
        Task {
            do {
                try await CloudKitManager.shared.acceptShare(metadata: cloudKitShareMetadata)
                await MainActor.run {
                    NotificationCenter.default.post(name: .cloudKitShareAccepted, object: nil)
                }
            } catch {
                print("⚠️ Failed to accept CloudKit share: \(error.localizedDescription)")
            }
        }
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
