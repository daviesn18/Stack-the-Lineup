import XCTest
@testable import Lineup_Builder

// MARK: - STLRoute Tests
//
// Deep links are the surface Spotlight results and App Intents hand back to the
// app, so parsing is load-bearing. Before STLRoute existed, `.onOpenURL` mapped
// every stackthelineup:// URL to the Lineup tab and iPad ignored links entirely.

final class STLRouteTests: XCTestCase {

    // MARK: - Foreign schemes

    func testForeignSchemeIsRejected() {
        // Must return nil, not a fallback route — ContentView relies on nil to
        // fall through to the .stlteam / .stlroster file import handlers.
        XCTAssertNil(STLRoute(url: URL(string: "file:///roster.stlroster")!))
        XCTAssertNil(STLRoute(url: URL(string: "https://stackthelineup.com/lineup")!))
    }

    // MARK: - Widget backwards compatibility

    func testShippedWidgetLinkStillResolvesToLineup() {
        // STLWidget ships `stackthelineup://lineup` as its .widgetURL. A build of
        // the widget already on someone's home screen must keep working.
        XCTAssertEqual(STLRoute(url: URL(string: "stackthelineup://lineup")!), .lineup)
    }

    func testUnknownHostFallsBackToLineupRatherThanFailing() {
        // An older app build meeting a newer link should land somewhere sensible
        // instead of dead-ending.
        XCTAssertEqual(STLRoute(url: URL(string: "stackthelineup://someFutureScreen")!), .lineup)
    }

    // MARK: - Tab routes

    func testTabRoutes() {
        XCTAssertEqual(STLRoute(url: URL(string: "stackthelineup://players")!), .players)
        XCTAssertEqual(STLRoute(url: URL(string: "stackthelineup://positions")!), .positions)
        XCTAssertEqual(STLRoute(url: URL(string: "stackthelineup://history")!), .history)
    }

    // MARK: - Entity routes

    func testPlayerRouteCarriesIdentifier() {
        let id = UUID()
        XCTAssertEqual(
            STLRoute(url: URL(string: "stackthelineup://player/\(id.uuidString)")!),
            .player(id)
        )
    }

    func testGameLogRouteCarriesIdentifier() {
        let id = UUID()
        XCTAssertEqual(
            STLRoute(url: URL(string: "stackthelineup://history/\(id.uuidString)")!),
            .gameLog(id)
        )
    }

    func testPlayerRouteWithoutIdentifierIsRejected() {
        // Better to fall through to import handling than to open an arbitrary player.
        XCTAssertNil(STLRoute(url: URL(string: "stackthelineup://player")!))
        XCTAssertNil(STLRoute(url: URL(string: "stackthelineup://player/not-a-uuid")!))
    }

    // MARK: - Round trip
    //
    // App Intents and Spotlight build links from `route.url`; the app parses them
    // back with `init(url:)`. If these ever diverge, every Spotlight tap breaks.

    func testEveryRouteRoundTripsThroughItsURL() {
        let routes: [STLRoute] = [
            .players, .lineup, .positions, .history,
            .player(UUID()), .gameLog(UUID()), .team(UUID()),
        ]
        for route in routes {
            guard let url = route.url else {
                XCTFail("\(route) produced no URL")
                continue
            }
            XCTAssertEqual(STLRoute(url: url), route, "\(route) did not round trip via \(url)")
        }
    }

    // MARK: - Tab mapping

    func testEntityRoutesResolveToTheirHostTab() {
        XCTAssertEqual(STLRoute.player(UUID()).tab, .players)
        XCTAssertEqual(STLRoute.gameLog(UUID()).tab, .history)
    }

    // MARK: - AppRouter request identity
    //
    // The nonce does double duty: it makes .onChange fire for a repeated route,
    // and it lets each consumer apply a pending route exactly once via
    // consumePendingRoute(). Both behaviours break if requests compare equal.

    @MainActor
    func testRepeatingTheSameRouteProducesADistinctRequest() {
        let router = AppRouter()
        router.route(to: .lineup)
        let first = router.request
        router.route(to: .lineup)
        let second = router.request

        XCTAssertEqual(first?.route, second?.route)
        XCTAssertNotEqual(first, second,
            "Asking Siri for the same screen twice must navigate twice — equal requests would not fire .onChange")
        XCTAssertNotEqual(first?.nonce, second?.nonce)
    }

    @MainActor
    func testHandleRejectsForeignURLsWithoutSettingARequest() {
        let router = AppRouter()
        let handled = router.handle(URL(string: "file:///roster.stlroster")!)

        XCTAssertFalse(handled, "ContentView relies on false to fall through to file import")
        XCTAssertNil(router.request)
    }

    // MARK: - Spotlight selection
    //
    // Tapping an indexed entity does NOT arrive through onOpenURL — verified on
    // iOS 26.5, adding URLRepresentableEntity changed nothing. It comes back as a
    // CSSearchableItemActionType activity carrying an identifier whose encoding
    // AppIntents owns and does not document, hence resolving by UUID content
    // rather than by parsing a format.

    func testSpotlightIdentifierResolvesToThePlayerItNames() {
        let player = UUID()
        let team   = UUID()

        // Shapes Apple has used or plausibly could; all must resolve the same.
        for identifier in [
            player.uuidString,
            "PlayerEntity/\(player.uuidString)",
            "com.nickdavies.LineupBuilder.PlayerEntity.\(player.uuidString)",
        ] {
            XCTAssertEqual(
                STLRoute.fromSpotlightIdentifier(identifier, playerIDs: [player], teamIDs: [team]),
                .player(player),
                "\(identifier) did not resolve"
            )
        }
    }

    func testSpotlightIdentifierResolvesToATeam() {
        let team = UUID()
        XCTAssertEqual(
            STLRoute.fromSpotlightIdentifier("TeamEntity/\(team.uuidString)",
                                             playerIDs: [], teamIDs: [team]),
            .team(team)
        )
    }

    func testSpotlightIdentifierForSomethingWeNoLongerHaveIsDropped() {
        // A player deleted since the index was last written. Opening an arbitrary
        // screen would be worse than doing nothing.
        XCTAssertNil(
            STLRoute.fromSpotlightIdentifier(UUID().uuidString,
                                             playerIDs: [UUID()], teamIDs: [UUID()])
        )
        XCTAssertNil(
            STLRoute.fromSpotlightIdentifier("no-uuid-here", playerIDs: [UUID()], teamIDs: [])
        )
    }

    func testUUIDExtractionFindsEmbeddedIdentifiers() {
        let first  = UUID()
        let second = UUID()
        XCTAssertEqual(
            STLRoute.uuids(in: "x/\(first.uuidString)::\(second.uuidString)!"),
            [first, second]
        )
        XCTAssertTrue(STLRoute.uuids(in: "short").isEmpty)
    }

    // MARK: - Request freshness
    //
    // AppRouter.shared outlives every view, and requests are never cleared after
    // handling. Both consumers use `isFresh` to decide whether a first-ever drain
    // — a newly opened iPad window — should replay whatever is still sitting there.

    @MainActor
    func testANewRequestIsFresh() {
        XCTAssertTrue(AppRouter.Request(.lineup).isFresh,
            "A cold-launch request is milliseconds old and must always be applied")
    }

    @MainActor
    func testAnOldRequestIsNotFresh() {
        let stale = AppRouter.Request(.player(UUID()), createdAt: Date(timeIntervalSinceNow: -600))
        XCTAssertFalse(stale.isFresh,
            "A route asked for ten minutes ago must not hijack a window opening now")
    }

    func testTabTagsMatchTheShippedTabViewOrder() {
        // These tags are the .tag() values in iPhoneTabView. Reordering the tabs
        // without updating this mapping would send every deep link to the wrong
        // screen, silently.
        XCTAssertEqual(STLRoute.Tab.players.iPhoneTag,   0)
        XCTAssertEqual(STLRoute.Tab.lineup.iPhoneTag,    1)
        XCTAssertEqual(STLRoute.Tab.positions.iPhoneTag, 2)
        XCTAssertEqual(STLRoute.Tab.history.iPhoneTag,   3)
    }
}
