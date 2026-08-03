import XCTest
@testable import Lineup_Builder

// MARK: - WhatsNewContentTests
//
// This registry has exactly one failure mode and it is silent. `WhatsNewContent.current`
// matches on an exact `CFBundleShortVersionString`, and `WhatsNewManager.shouldShow()`
// returns false when nothing matches — so bumping MARKETING_VERSION without adding an
// entry means the sheet simply never appears. No crash, no log, nothing to notice until
// someone asks why the release notes didn't show.
//
// That is not hypothetical: 3.3 was bumped on 2 Aug 2026 while the registry still topped
// out at 3.2, and it was caught by reading the code rather than by running it. These
// tests exist so the next one is caught by running it.

@MainActor
final class WhatsNewContentTests: XCTestCase {

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    /// The guard. Fails the build whenever the version moves ahead of the registry.
    func testTheRunningVersionHasAnEntry() {
        XCTAssertFalse(
            appVersion.isEmpty,
            "CFBundleShortVersionString is missing — the test host isn't the app bundle"
        )
        XCTAssertNotNil(
            WhatsNewContent.current,
            """
            No What's New entry for version \(appVersion), so the sheet will never appear \
            for this build. Add one to WhatsNewContent.all whenever MARKETING_VERSION changes.
            """
        )
    }

    /// `current` uses `first(where:)`, so a duplicate version silently shadows the later one.
    func testVersionsAreUnique() {
        let versions = WhatsNewContent.all.map(\.version)
        XCTAssertEqual(
            versions.count,
            Set(versions).count,
            "Duplicate version in WhatsNewContent.all — one of the entries is unreachable"
        )
    }

    /// The three-feature cap is checked against the entry that will actually present,
    /// not the whole registry: 2.3 shipped with four and that history isn't worth
    /// rewriting to satisfy a test.
    func testTheCurrentEntryFitsTheSheet() throws {
        let content = try XCTUnwrap(
            WhatsNewContent.current,
            "No entry for \(appVersion) — see testTheRunningVersionHasAnEntry"
        )
        XCTAssertFalse(
            content.features.isEmpty,
            "Version \(content.version) has no features; the sheet would present blank"
        )
        XCTAssertLessThanOrEqual(
            content.features.count,
            3,
            "Version \(content.version) has \(content.features.count) features; past three the sheet stops being dismissible on small screens"
        )
    }

    /// An entry with no features presents an empty sheet the coach still has to dismiss.
    func testNoEntryIsEmpty() {
        for entry in WhatsNewContent.all {
            XCTAssertFalse(
                entry.features.isEmpty,
                "Version \(entry.version) has no features"
            )
        }
    }
}
