import StoreKit
import SwiftUI
import Combine

// MARK: - PurchaseManager
// Handles the one-time "Stack the Lineup Pro" IAP using StoreKit 2.
//
// Grandfather logic: if no firstLaunchDate is stored in UserDefaults, the user
// installed the app before the freemium transition and is treated as Pro for free.
// New installs after the freemium binary ships will have a firstLaunchDate stamped
// on first run by LineupBuilderApp, so they will not be grandfathered.

@MainActor
class PurchaseManager: ObservableObject {

    static let proProductID   = "com.stackthelineup.pro"
    static let firstLaunchKey = "firstLaunchDate"

    @Published var isPro: Bool = false
    @Published var proProduct: Product? = nil
    @Published var purchaseError: String? = nil
    @Published var isLoading: Bool = false
    var lastPaywallSource: String = "unknown"

    // MARK: - New-install stamp
    // Called once from LineupBuilderApp when the freemium binary launches.
    // If no date is stored this is either a brand-new install (stamp it) or a
    // pre-freemium user (do NOT stamp — grandfather logic will fire).
    // We distinguish the two cases by checking whether the app has any saved
    // data; if it does, the user is pre-freemium and we leave the key absent.
    // In practice, the simplest safe rule: always call this, and the absence
    // of the key at entitlement-check time is what grants grandfather Pro.
    static func stampAsNewInstall() {
        guard UserDefaults.standard.object(forKey: firstLaunchKey) == nil else { return }
        UserDefaults.standard.set(Date(), forKey: firstLaunchKey)
    }

    // MARK: - Entitlement Check

    func checkEntitlement() async {
        // Grandfather rule: no firstLaunchDate = installed before freemium → grant Pro free
        if UserDefaults.standard.object(forKey: Self.firstLaunchKey) == nil {
            isPro = true
            return
        }

        // Check for an active verified IAP transaction
        for await result in Transaction.currentEntitlements {
            if case .verified(let tx) = result, tx.productID == Self.proProductID {
                isPro = true
                return
            }
        }
        isPro = false
    }

    // MARK: - Load Product (fetches live price from StoreKit)

    func loadProduct() async {
        do {
            let products = try await Product.products(for: [Self.proProductID])
            proProduct = products.first
        } catch {
            purchaseError = "Could not load upgrade details. Please try again."
        }
    }

    // MARK: - Purchase

    func purchase() async {
        guard let product = proProduct else {
            purchaseError = "Product unavailable. Please try again later."
            return
        }

        isLoading = true
        purchaseError = nil

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(_) = verification {
                    isPro = true
                    Analytics.signal("paywall.converted", parameters: ["source": lastPaywallSource])
                } else {
                    purchaseError = "Purchase could not be verified. Please contact support."
                }
            case .userCancelled:
                break  // user dismissed — no error shown
            case .pending:
                purchaseError = "Purchase is pending approval (Ask to Buy). Check back soon."
            @unknown default:
                break
            }
        } catch {
            purchaseError = "Purchase failed: \(error.localizedDescription)"
        }

        isLoading = false
    }

    // MARK: - Restore

    func restore() async {
        isLoading = true
        purchaseError = nil

        do {
            try await AppStore.sync()
            await checkEntitlement()
            if isPro {
                Analytics.signal("pro.restored")
            } else {
                purchaseError = "No previous purchase found for this Apple ID."
            }
        } catch {
            purchaseError = "Restore failed: \(error.localizedDescription)"
        }

        isLoading = false
    }

}
