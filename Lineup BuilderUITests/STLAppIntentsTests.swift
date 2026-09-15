import XCTest
import AppIntentsTesting

// MARK: - STLAppIntentsTests
//
// Validates the shipped App Intents through the REAL App Intents stack.
// AppIntentsTesting runs each intent out-of-process, the same way Siri,
// Shortcuts, and Spotlight do — so a broken registration, a bad parameter
// shape, or a mis-gated intent fails here instead of silently working only
// when called in-process.
//
// Deliberately NO `@testable import Lineup_Builder`: intents are addressed by
// name against the app's own App Intents surface (via the app bundle id), which
// is the point of this framework. Importing the app target would let the app
// module compile-check pass while the intent surface is broken.
//
// AppIntentsTesting is iOS 27+ only, so the whole suite is gated. It lives in
// the UI-test bundle (not the unit suite) because the framework requires an
// XCUITest host that launches the app. Run it scoped to avoid the UI target's
// known full-run hang:
//   -only-testing:"Lineup BuilderUITests/STLAppIntentsTests"
//
// Pro path note: these run against a fresh simulator, which is NOT Pro, so they
// cover the LOCKED path. Exercising the Pro-success path needs a StoreKit test
// configuration or a FORCE_PRO launch argument (see the [P1] card) and is a
// follow-up.

@available(iOS 27.0, *)
final class STLAppIntentsTests: XCTestCase {

    private var definitions: IntentDefinitions {
        IntentDefinitions(bundleIdentifier: "com.nickdavies.LineupBuilder.Lineup-Builder")
    }

    // MARK: The Pro-gate asymmetry
    //
    // This is the whole reason FillLineupIntent and GameRecapIntent are shaped
    // differently, and the easiest thing to regress. Two intents, opposite
    // correct behavior when a non-Pro coach runs them:

    /// FillLineupIntent has `openAppWhenRun = true`. The app is already
    /// foregrounded by the time perform() returns, so throwing a Pro error would
    /// leave the coach staring at a tab with no explanation. It must route to the
    /// paywall and RETURN — never throw. The Pro check runs before any team/roster
    /// lookup, so this holds even on an empty simulator.
    func testFillLineupWhenNotProRoutesToPaywallInsteadOfThrowing() async throws {
        _ = try await definitions.intents["FillLineupIntent"].makeIntent().run()
        // Reaching here (no throw) is the assertion: the locked path returned
        // rather than dead-ending. If this throws, the paywall routing regressed.
    }

    /// GameRecapIntent has `openAppWhenRun = false`. Nothing foregrounds, so
    /// throwing `needsPro` IS the correct locked behavior — the error is spoken
    /// back. This is the inverse guard to the FillLineup case above.
    func testGameRecapWhenNotProThrows() async throws {
        do {
            _ = try await definitions.intents["GameRecapIntent"].makeIntent().run()
            XCTFail("GameRecapIntent should throw for a non-Pro coach (openAppWhenRun = false)")
        } catch {
            // Expected. Out-of-process the error is bridged, so we assert that it
            // throws rather than matching STLIntentError.needsPro specifically.
        }
    }

    // MARK: Entity resolution
    //
    // Player/Team entity queries feed every intent that takes a player or team
    // parameter, plus Spotlight. A throwing query breaks all of them at once.
    // Data-independent smoke: the query path executes without throwing (matches
    // may be empty on a fresh simulator — a data-backed assertion needs a seed
    // intent, tracked as a follow-up).

    func testPlayerEntityQueryExecutes() async throws {
        _ = try await definitions.entities["PlayerEntity"].entities(matching: "a")
    }

    func testTeamEntitySuggestionsExecute() async throws {
        _ = try await definitions.entities["TeamEntity"].suggestedEntities()
    }
}
