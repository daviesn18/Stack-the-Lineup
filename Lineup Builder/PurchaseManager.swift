import StoreKit
import SwiftUI
import Combine

// MARK: - PurchaseManager
// Handles the "Stack the Lineup Pro" entitlement.
//
// Pro can be held two ways, and either one grants full Pro:
//   1. Legacy one-time purchase — the non-consumable com.stackthelineup.pro,
//      sold at $4.99 before the subscription move. These buyers are grandfathered
//      into full Pro permanently; they are never asked to subscribe.
//   2. Active subscription — the auto-renewable product sold going forward.
//
// The legacy clause (1) is a hard product requirement: anyone who paid the
// one-time fee keeps every Pro feature, including features shipped after the
// subscription launch. See checkEntitlement() and PurchaseManagerTests.

@MainActor
class PurchaseManager: ObservableObject {

    // Legacy one-time non-consumable. Still honored forever for grandfathering.
    static let legacyProProductID = "com.stackthelineup.pro"

    // Auto-renewable subscription sold going forward.
    static let subscriptionProductID = "com.stackthelineup.pro.yearly"

    @Published var isPro: Bool = false
    @Published var subscriptionProduct: Product? = nil
    @Published var purchaseError: String? = nil
    @Published var isLoading: Bool = false

    /// True when the current Apple Account is eligible for the introductory
    /// free trial. A coach who already used and cancelled the trial is not,
    /// so the CTA and legal copy must not promise a trial they won't get.
    @Published var isEligibleForIntroOffer: Bool = true

    var lastPaywallSource: String = "unknown"

    /// Long-lived task that watches for entitlement changes during the session
    /// (renewals, expirations, billing failures, refunds, family-sharing changes).
    /// Without this, a lapsed subscription would keep Pro until the app relaunched.
    private var updatesListener: Task<Void, Never>? = nil

    init() {
        updatesListener = Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { continue }
                if case .verified(let tx) = update {
                    await tx.finish()
                }
                // Any transaction change can grant or revoke access — re-derive
                // from the current entitlement set rather than trusting the delta.
                await self.checkEntitlement()
            }
        }
    }

    deinit {
        updatesListener?.cancel()
    }

    // MARK: - Entitlement Check
    // Order matters only for short-circuiting; both paths grant full Pro.

    /// Whether a product ID grants Pro. The legacy non-consumable is included
    /// here permanently — that inclusion is the grandfathering guarantee for
    /// $4.99 buyers, and removing it would silently revoke their access.
    /// Covered by PurchaseManagerEntitlementTests.
    static func productGrantsPro(_ productID: String) -> Bool {
        productID == legacyProProductID || productID == subscriptionProductID
    }

    func checkEntitlement() async {

        // Any active/owned entitlement for the legacy purchase OR the
        // subscription grants Pro. currentEntitlements already excludes expired
        // subscriptions and refunded purchases, so presence here is sufficient.
        for await result in Transaction.currentEntitlements {
            guard case .verified(let tx) = result else { continue }
            if Self.productGrantsPro(tx.productID) {
                isPro = true
                return
            }
        }

        isPro = false
    }

    // MARK: - Display Copy
    // One source of truth for price/CTA/legal strings so the main paywall and
    // the two inline locked-feature prompts never drift apart or hardcode a
    // stale price. All derive from the loaded product when available.

    /// Localized "price/period" for the subscription, e.g. "$9.99/year".
    /// Falls back to a period-less price if the subscription unit is unknown,
    /// and to a plain placeholder if the product hasn't loaded yet.
    var priceText: String {
        guard let product = subscriptionProduct else { return "$9.99/year" }
        guard let period = product.subscription?.subscriptionPeriod else {
            return product.displayPrice
        }
        return "\(product.displayPrice)/\(period.unitLabel)"
    }

    /// Primary button label. Promises the free trial only when the account is
    /// actually eligible for it.
    var ctaLabel: String {
        isEligibleForIntroOffer ? "Start 7-day free trial" : "Subscribe — \(priceText)"
    }

    /// Plan-summary headline shown above the button.
    var planHeadline: String {
        isEligibleForIntroOffer ? "7 days free, then \(priceText)" : priceText
    }

    /// Auto-renew disclosure required by App Review 3.1.2. Terms/Privacy links
    /// are appended by the view so they remain tappable.
    var legalText: String {
        if isEligibleForIntroOffer {
            return "After the 7-day free trial, \(priceText) is charged to your Apple Account. Renews automatically unless canceled at least 24 hours before the period ends. Manage in Settings."
        }
        return "\(priceText) is charged to your Apple Account. Renews automatically unless canceled at least 24 hours before the period ends. Manage in Settings."
    }

    // MARK: - Load Product (fetches live price + trial eligibility from StoreKit)

    func loadProduct() async {
        isLoading = true
        do {
            let products = try await Product.products(for: [Self.subscriptionProductID])
            subscriptionProduct = products.first
            await refreshIntroEligibility()
        } catch {
            purchaseError = "Couldn't load the price. Try again."
        }
        isLoading = false
    }

    /// A coach is eligible for the intro offer only if the subscription defines
    /// one and StoreKit confirms this Apple Account hasn't used it before.
    private func refreshIntroEligibility() async {
        guard
            let sub = subscriptionProduct?.subscription,
            sub.introductoryOffer != nil
        else {
            isEligibleForIntroOffer = false
            return
        }
        isEligibleForIntroOffer = await sub.isEligibleForIntroOffer
    }

    // MARK: - Purchase

    func purchase() async {
        guard let product = subscriptionProduct else {
            purchaseError = "The upgrade isn't available right now. Try again in a bit."
            return
        }

        isLoading = true
        purchaseError = nil

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let tx) = verification {
                    await tx.finish()
                    isPro = true
                    Analytics.signal("paywall.converted", parameters: ["source": lastPaywallSource])
                } else {
                    purchaseError = "Couldn't verify that purchase. Try Restore Purchase, and contact support if it still doesn't unlock."
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

// MARK: - Subscription Period Formatting

private extension Product.SubscriptionPeriod {
    /// Singular period word for a "price/period" string, e.g. "year", "month".
    /// StoreKit periods are usually value 1 (1 year); if a product ever uses a
    /// multi-unit period (e.g. every 6 months) we fall back to a plural form.
    var unitLabel: String {
        let base: String
        switch unit {
        case .day:   base = "day"
        case .week:  base = "week"
        case .month: base = "month"
        case .year:  base = "year"
        @unknown default: base = "period"
        }
        return value == 1 ? base : "\(value) \(base)s"
    }
}
