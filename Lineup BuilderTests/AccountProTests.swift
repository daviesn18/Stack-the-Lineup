//
//  AccountProTests.swift
//  Lineup BuilderTests
//
//  Pro recorded on the coach's account (web purchases, lifetime, hand grants)
//  and how PurchaseManager combines it with StoreKit.
//

import XCTest
@testable import Lineup_Builder

final class AccountProTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "AccountProTests"
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let coach = "3f1c2b4a-1111-4222-8333-444455556666"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func snapshot(isPro: Bool = true, expiresIn seconds: TimeInterval?) -> AccountPro.Snapshot {
        AccountPro.Snapshot(userID: coach, isPro: isPro,
                            expiresAt: seconds.map { now.addingTimeInterval($0) }, store: isPro ? "stripe" : nil)
    }

    func testNothingCachedIsNotPro() {
        XCTAssertFalse(AccountPro.cachedGrantsPro(now: now, defaults: defaults))
    }

    func testAnUnexpiredSubscriptionIsPro() {
        AccountPro.save(snapshot(expiresIn: 86_400), defaults: defaults)
        XCTAssertTrue(AccountPro.cachedGrantsPro(now: now, defaults: defaults))
    }

    func testLifetimeHasNoEndAndIsPro() {
        AccountPro.save(snapshot(expiresIn: nil), defaults: defaults)
        XCTAssertTrue(AccountPro.cachedGrantsPro(now: now, defaults: defaults))
    }

    func testALapsedSubscriptionStopsEvenOffline() {
        // Cached while it was active; the clock alone ends it, no network needed.
        AccountPro.save(snapshot(expiresIn: -1), defaults: defaults)
        XCTAssertFalse(AccountPro.cachedGrantsPro(now: now, defaults: defaults))
    }

    func testAFreeAccountIsNotPro() {
        AccountPro.save(snapshot(isPro: false, expiresIn: nil), defaults: defaults)
        XCTAssertFalse(AccountPro.cachedGrantsPro(now: now, defaults: defaults))
    }

    func testSigningOutForgetsTheAccountsPro() {
        AccountPro.save(snapshot(expiresIn: nil), defaults: defaults)
        AccountPro.forget(unlessBelongingTo: nil, defaults: defaults)
        XCTAssertNil(AccountPro.cached(defaults: defaults))
    }

    func testAnotherCoachSigningInForgetsThePreviousCoachsPro() {
        AccountPro.save(snapshot(expiresIn: nil), defaults: defaults)
        AccountPro.forget(unlessBelongingTo: "9e8d7c6b-aaaa-4bbb-8ccc-ddddeeeeffff", defaults: defaults)
        XCTAssertNil(AccountPro.cached(defaults: defaults))
    }

    func testTheSameCoachKeepsTheirCachedPro() {
        AccountPro.save(snapshot(expiresIn: nil), defaults: defaults)
        AccountPro.forget(unlessBelongingTo: coach, defaults: defaults)
        XCTAssertEqual(AccountPro.cached(defaults: defaults), snapshot(expiresIn: nil))
    }
}

/// "Free" must wait for the account to answer, or a coach who paid on the web
/// sees a paywall on every cold launch while the network catches up.
@MainActor
final class PurchaseManagerAccountTests: XCTestCase {
    override func setUp() async throws {
        AccountPro.save(nil)
        #if DEBUG
        PurchaseManager.setProTestingOverride(nil)
        #endif
    }

    override func tearDown() async throws {
        AccountPro.save(nil)
    }

    func testStoreKitAloneDoesNotSettleFree() async {
        let manager = PurchaseManager()
        await manager.checkEntitlement()
        XCTAssertEqual(manager.status, .undetermined, "no StoreKit Pro, but the account hasn't answered yet")
    }

    func testSignedOutSettlesFree() async {
        let manager = PurchaseManager()
        await manager.refreshAccountPro(userID: nil)
        XCTAssertEqual(manager.status, .free)
    }

    func testSigningOutDropsAccountPro() async {
        AccountPro.save(.init(userID: "3f1c2b4a-1111-4222-8333-444455556666", isPro: true, expiresAt: nil, store: "stripe"))
        let manager = PurchaseManager()
        await manager.refreshAccountPro(userID: nil)
        XCTAssertEqual(manager.status, .free)
        XCTAssertNil(AccountPro.cached())
    }

    func testCachedAccountProGrantsProBeforeTheNetworkAnswers() async {
        AccountPro.save(.init(userID: "3f1c2b4a-1111-4222-8333-444455556666", isPro: true, expiresAt: nil, store: "stripe"))
        let manager = PurchaseManager()
        await manager.checkEntitlement()
        XCTAssertEqual(manager.status, .pro)
    }
}
