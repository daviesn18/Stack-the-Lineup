import XCTest
@testable import Lineup_Builder

// MARK: - Purchase Entitlement Tests
//
// These guard the grandfathering guarantee: anyone who paid the $4.99 one-time
// Pro unlock, and anyone who installed before the freemium transition, keeps
// full Pro after the move to a subscription. The entitlement decision is split
// into two pure functions on PurchaseManager so it can be tested without a
// StoreKit session — the async checkEntitlement() just calls these.

@MainActor
final class PurchaseManagerEntitlementTests: XCTestCase {

    // MARK: Legacy purchase is honored forever

    func testLegacyProProductStillGrantsPro() {
        // If this fails, a $4.99 buyer loses Pro on the subscription build.
        XCTAssertTrue(
            PurchaseManager.productGrantsPro(PurchaseManager.legacyProProductID),
            "The legacy non-consumable must always grant Pro — this is the grandfathering guarantee."
        )
    }

    func testSubscriptionProductGrantsPro() {
        XCTAssertTrue(
            PurchaseManager.productGrantsPro(PurchaseManager.subscriptionProductID)
        )
    }

    func testUnrelatedProductDoesNotGrantPro() {
        XCTAssertFalse(PurchaseManager.productGrantsPro("com.stackthelineup.something.else"))
        XCTAssertFalse(PurchaseManager.productGrantsPro(""))
    }

    func testLegacyAndSubscriptionIDsAreDistinct() {
        // A regression guard: the subscription must be a NEW product ID. Apple
        // cannot convert the non-consumable in place, so if these ever match,
        // the subscription was misconfigured.
        XCTAssertNotEqual(
            PurchaseManager.legacyProProductID,
            PurchaseManager.subscriptionProductID
        )
    }

    // MARK: Pre-freemium grandfather (no firstLaunchDate)

    func testPreFreemiumUserIsGrandfathered() {
        let defaults = makeIsolatedDefaults()
        // No firstLaunchDate stored → installed before freemium → Pro.
        XCTAssertTrue(PurchaseManager.isPreFreemiumGrandfathered(defaults: defaults))
    }

    func testNewInstallIsNotGrandfathered() {
        let defaults = makeIsolatedDefaults()
        defaults.set(Date(), forKey: PurchaseManager.firstLaunchKey)
        XCTAssertFalse(PurchaseManager.isPreFreemiumGrandfathered(defaults: defaults))
    }

    // MARK: Helpers

    /// A throwaway UserDefaults suite so tests never touch the real store.
    private func makeIsolatedDefaults() -> UserDefaults {
        let suite = "PurchaseManagerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
