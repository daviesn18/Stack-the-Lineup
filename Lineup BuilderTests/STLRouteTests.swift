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
