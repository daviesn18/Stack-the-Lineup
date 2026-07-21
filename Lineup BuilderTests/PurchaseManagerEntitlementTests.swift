import XCTest
@testable import Lineup_Builder

// MARK: - Purchase Entitlement Tests
//
// These guard the grandfathering guarantee: anyone who paid the $4.99 one-time
// Pro unlock keeps full Pro after the move to a subscription. The entitlement
// decision is split into a pure function on PurchaseManager so it can be tested
// without a StoreKit session — the async checkEntitlement() just calls it.

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

}
