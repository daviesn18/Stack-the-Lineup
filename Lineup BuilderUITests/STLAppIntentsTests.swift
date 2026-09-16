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
// Pro path: a fresh simulator is NOT Pro, so intents run here see the LOCKED
// path by default. AppIntentsTesting has no launch-argument/-environment hook, so
// to exercise the Pro path (and to seed roster data) we drive DEBUG-only
// test-control intents — SetProForTesting / SeedTestRoster / ResetTestData — which
// set state inside the same out-of-process app. See DebugTestControlIntents.swift.

@available(iOS 27.0, *)
final class STLAppIntentsTests: XCTestCase {

    private var definitions: IntentDefinitions {
        IntentDefinitions(bundleIdentifier: "com.nickdavies.LineupBuilder.Lineup-Builder")
    }

    /// Always leave the app process clean: ResetTestData removes the seed roster
    /// and clears any Pro override, so tests can't leak state into each other.
    override func tearDown() async throws {
        _ = try? await definitions.intents["ResetTestDataIntent"].makeIntent().run()
        try await super.tearDown()
    }

    private func currentProStatus() async throws -> Bool {
        let result = try await definitions.intents["ProStatusForTestingIntent"].makeIntent().run()
        return try result.value
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

    // MARK: Pro-success path (via the DEBUG override)
    //
    // Proves the override is honored by the REAL gate, end-to-end through the
    // intent stack: SetPro(true) -> isProNow() reports Pro; ResetTestData ->
    // back to the real (non-Pro) StoreKit answer. This is the seam that lets a
    // future test assert a specific gated intent's Pro perform.

    func testProOverrideIsHonoredByTheRealGate() async throws {
        _ = try await definitions.intents["SetProForTestingIntent"].makeIntent(enabled: true).run()
        let proOn = try await currentProStatus()
        XCTAssertTrue(proOn, "Pro override = true should make isProNow() report Pro")

        _ = try await definitions.intents["ResetTestDataIntent"].makeIntent().run()
        let proOff = try await currentProStatus()
        XCTAssertFalse(proOff, "Reset should clear the override back to the real (non-Pro) StoreKit answer")
    }

    // MARK: Data-backed entity resolution
    //
    // Seeds a known player, then asserts the real PlayerEntity string query
    // actually resolves them by name — the query that feeds every player-parameter
    // intent and Spotlight. tearDown removes the seed.

    func testSeededPlayerResolvesByName() async throws {
        let seedResult = try await definitions.intents["SeedTestRosterIntent"].makeIntent().run()
        let query: String = try seedResult.value

        let matches = try await definitions.entities["PlayerEntity"].entities(matching: query)
        XCTAssertFalse(matches.isEmpty, "Seeded player should be resolvable by \"\(query)\"")
    }

    // MARK: Free background answer intents
    //
    // FairPlayRuleIntent answers in place with supportedModes `.background` and,
    // unlike Fill/Recap, is Free — there is no Pro gate to route or throw. The
    // regression it guards is the opposite one: an answer intent must run its
    // answer path end-to-end through the real out-of-process stack (team
    // resolution + the structured TeamRulesBuilder lookup) and RETURN a result,
    // never foreground the app and never throw on a coach who simply has no rules
    // switched on ("you haven't turned rules on" is a valid spoken answer). The
    // structured-lookup contract itself — that these numbers come from
    // FairPlayConfig/PitchingLimits and never from a generated model — is pinned
    // exhaustively in the unit target's TeamRulesTests.

    func testFairPlayRuleAnswersOnSeededTeamWithoutThrowing() async throws {
        // Seed makes a known team active, so the no-parameter intent resolves it
        // via the active-team path rather than throwing noTeam.
        _ = try await definitions.intents["SeedTestRosterIntent"].makeIntent().run()
        _ = try await definitions.intents["FairPlayRuleIntent"].makeIntent().run()
        // Reaching here (a returned result, no throw) is the assertion.
    }
}
