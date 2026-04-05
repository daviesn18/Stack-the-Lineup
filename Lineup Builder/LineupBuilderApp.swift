import SwiftUI
import TelemetryDeck

@main
struct LineupBuilderApp: App {
    @StateObject private var purchaseManager = PurchaseManager()

    init() {
        PurchaseManager.stampAsNewInstall()

        let config = TelemetryDeck.Config(appID: "F6A09F00-2EFC-4DAD-9137-3350F267E78A")
        TelemetryDeck.initialize(config: config)
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
