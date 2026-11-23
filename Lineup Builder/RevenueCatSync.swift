//
//  RevenueCatSync.swift
//  Lineup Builder
//
//  RevenueCat runs alongside our own StoreKit 2 code, never instead of it
//  (purchasesAreCompletedBy: .myApp). PurchaseManager still sells, finishes
//  and checks purchases exactly as before; RevenueCat only *records* them, so
//  that Pro bought on iPhone reaches the coach's account (and the web) through
//  the revenuecat-webhook Edge Function, and so paying-coach counts for iOS
//  and web live in one place.
//
//  Identity: the RevenueCat app user ID is the Supabase user ID, lower-cased
//  exactly as the web sends it (RevenueCat IDs are case-sensitive, and an
//  upper-cased one would be a second customer). Signed out, RevenueCat uses
//  its own anonymous ID; signing in later moves those purchases to the account.
//
//  Existing subscribers: RevenueCat only learns about an App Store purchase
//  when an app with RevenueCat syncs it, and there's no automatic import. So
//  every coach's first launch of this build syncs once, signed in or not.
//

import Foundation
import RevenueCat
import StoreKit
import TelemetryDeck
import os

@MainActor
enum RevenueCatSync {
    /// RevenueCat's public Apple SDK key (appl_…), from the dashboard's API
    /// keys page. Public by design, like the Supabase publishable key. Empty
    /// turns RevenueCat off entirely; nothing else in the app depends on it.
    nonisolated static let apiKey = "appl_AzASbBTLrowgOIazwOFSFlLQPUN"

    /// Off in the unit-test host: its first-launch sync reads the App Store
    /// transaction, which on a simulator with no sandbox account stalls StoreKit
    /// and hangs any test that reads entitlements.
    nonisolated static var isEnabled: Bool { !apiKey.isEmpty && !LineupStore.isRunningUnitTests }

    /// Once per install: every existing App Store purchase has been sent to RevenueCat.
    private static let initialSyncKey = "stl.revenuecat.initialSyncDone"

    /// Account changes run one at a time and in order, so a quick sign-out and
    /// sign-in can't log the wrong customer in last.
    private static var chain: Task<Void, Never>?
    /// The app user ID RevenueCat was last told about this launch (nil =
    /// signed out), once `hasIdentified`.
    private static var identifiedUserID: String?
    private static var hasIdentified = false

    /// Call once, at launch, before anything that could buy or restore.
    static func configure() {
        guard isEnabled, !Purchases.isConfigured else { return }
        Purchases.logLevel = .warn
        Purchases.configure(
            with: Configuration.Builder(withAPIKey: apiKey)
                .with(purchasesAreCompletedBy: .myApp, storeKitVersion: .storeKit2)
                .build()
        )
    }

    /// Called with every session the app sees: the stored one at launch, then
    /// each sign-in and sign-out. Repeats for the same account are cheap.
    static func accountDidChange(to userID: UUID?) {
        guard isEnabled, Purchases.isConfigured else { return }
        let appUserID = userID?.uuidString.lowercased()
        let previous = chain
        chain = Task {
            await previous?.value
            await identify(appUserID)
            await syncExistingPurchasesOnce()
            setTelemetryAttributes()
        }
    }

    /// Hands a purchase our StoreKit code just made to RevenueCat. Call it with
    /// the raw result, before finishing the transaction. A failure here never
    /// affects the purchase itself: the coach is Pro from StoreKit either way,
    /// and RevenueCat also hears about it from Apple's server notifications.
    static func record(_ result: Product.PurchaseResult) async {
        guard isEnabled, Purchases.isConfigured else { return }
        do {
            _ = try await Purchases.shared.recordPurchase(result)
        } catch {
            Log.purchase.error("RevenueCat recordPurchase failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// After Restore Purchase: send whatever the App Store just restored.
    static func syncPurchases() async {
        guard isEnabled, Purchases.isConfigured else { return }
        do {
            _ = try await Purchases.shared.syncPurchases()
        } catch {
            Log.purchase.error("RevenueCat syncPurchases failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Private

    private static func identify(_ appUserID: String?) async {
        if hasIdentified, identifiedUserID == appUserID { return }
        do {
            if let appUserID {
                _ = try await Purchases.shared.logIn(appUserID)
            } else if !Purchases.shared.isAnonymous {
                _ = try await Purchases.shared.logOut()
            }
            identifiedUserID = appUserID
            hasIdentified = true
        } catch {
            // Offline, most likely. The next session event or launch tries again.
            Log.purchase.error("RevenueCat identify failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func syncExistingPurchasesOnce() async {
        guard !UserDefaults.standard.bool(forKey: initialSyncKey) else { return }
        do {
            _ = try await Purchases.shared.syncPurchases()
            UserDefaults.standard.set(true, forKey: initialSyncKey)
            Log.purchase.info("RevenueCat initial sync done")
        } catch {
            // Not marked done, so the next launch retries.
            Log.purchase.error("RevenueCat initial sync failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Lets TelemetryDeck's RevenueCat integration file purchases under the
    /// same (hashed) user as the app's own signals. Only the hash leaves the
    /// device, the same one every signal already carries.
    private static func setTelemetryAttributes() {
        Purchases.shared.attribution.setAttributes([
            "$telemetryDeckAppId": Analytics.appID,
            "$telemetryDeckUserId": TelemetryManager.shared.hashedDefaultUser,
        ])
    }
}
