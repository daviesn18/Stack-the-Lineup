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

    // MARK: Undetermined is not "free"
    //
    // StoreKit answers asynchronously, so every cold launch starts before the
    // entitlement is known. Collapsing that into a plain false meant a paying
    // coach could be shown the History paywall on a slow or offline launch —
    // `GameLogsView` read `isPro == false` as "locked" and auto-presented.

    func testUndeterminedDoesNotGrantPro() {
        // The safe direction: never unlock a paid feature before we know.
        XCTAssertFalse(PurchaseManager.ProStatus.undetermined.grantsPro)
    }

    func testUndeterminedIsNotResolved() {
        // The whole point. If this ever returns true, paywalls come back.
        XCTAssertFalse(
            PurchaseManager.ProStatus.undetermined.isResolved,
            "Undetermined must not read as resolved — locked screens gate on this."
        )
    }

    func testFreeIsResolvedAndDoesNotGrantPro() {
        XCTAssertTrue(PurchaseManager.ProStatus.free.isResolved)
        XCTAssertFalse(PurchaseManager.ProStatus.free.grantsPro)
    }

    func testProIsResolvedAndGrantsPro() {
        XCTAssertTrue(PurchaseManager.ProStatus.pro.isResolved)
        XCTAssertTrue(PurchaseManager.ProStatus.pro.grantsPro)
    }

    func testUndeterminedAndFreeAreDistinct() {
        // They differ only where it matters — `grantsPro` agrees, `isResolved`
        // does not. A refactor that made them equal would restore the bug while
        // leaving every `isPro` check looking correct.
        XCTAssertNotEqual(PurchaseManager.ProStatus.undetermined, .free)
        XCTAssertEqual(
            PurchaseManager.ProStatus.undetermined.grantsPro,
            PurchaseManager.ProStatus.free.grantsPro
        )
        XCTAssertNotEqual(
            PurchaseManager.ProStatus.undetermined.isResolved,
            PurchaseManager.ProStatus.free.isResolved
        )
    }

    func testAFreshManagerHasNotResolvedYet() {
        // The precondition for the bug: a manager that has never been asked
        // must report undetermined, not free.
        let manager = PurchaseManager()
        XCTAssertEqual(manager.status, .undetermined)
        XCTAssertFalse(manager.isPro)
        XCTAssertFalse(manager.isResolved)
    }

}
