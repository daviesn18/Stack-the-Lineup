# HANDOFF — P0: iOS 27 SDK adoption (v3.5)

Date: 2026-09-14. Branch: `fix/shared-teams-reliability` (working tree; not committed).
Asana: "[P0] Phase 0 (3.5) — Xcode 27 SDK adoption + availability-gating baseline".

## Outcome

The app and the unit-test target build and run against the **iOS 27.0 SDK** (Xcode 27.0
/ Swift 6.4). Every error the SDK bump surfaced was the same actor-isolation defect and
is fixed. The runtime floor is unchanged: `IPHONEOS_DEPLOYMENT_TARGET` stays 26.0 (app),
26.2 (widget), 26.5 (extension). No `#available` gates were added — there is no iOS 27
feature code yet; this ticket establishes the baseline and the convention for the tickets
that follow.

## Toolchain (already in place, no change needed)

- Xcode 27.0 (27A266a), Swift 6.4, iOS 27.0 SDK + iOS 27.0 Simulator SDK.
- Only the 27.0 SDK is installed; building against it with a 26.0 deployment target is the
  intended additive model.

## Deprecation audit — clean

None of the four APIs flagged in the iOS 27 notes are used anywhere in the app:
- MetricKit `MXMetricManager` / `MXMetricPayload` (→ `MetricManager`)
- On-Demand Resources `NSBundleResourceRequest` (→ Background Assets)
- `UIApplication` status-bar accessors (→ `UIWindowScene.statusBarManager`)
- `ImageCreator` (removed in 27) / Image Playground

## The one defect the bump surfaced (fixed)

**A plain `extension` on a `nonisolated` type re-inherits the module's `@MainActor`
default under Swift 6.4.** The project builds with `SWIFT_DEFAULT_ACTOR_ISOLATION =
MainActor`. Marking a *type* `nonisolated` does NOT propagate across an `extension`
boundary — members of a separate `extension X { }` block default back to `@MainActor`
unless the extension is itself annotated. The app never noticed (it calls these from the
main actor); the unit tests, which are a nonisolated synchronous context, could not.

Fixed by annotating the extension `nonisolated` (5 files):

- `PitchEligibilityEngine.swift:328` — pitch-summary math (`pitchingSummaryRows`,
  `coachesGuideSummary`). *Broke `PitchingSummaryTests`.*
- `STLRoute.swift:108` — Spotlight identifier parsing (`fromSpotlightIdentifier`,
  `uuids`). *Broke `STLRouteTests`.*
- `AppIntents/GameLogEntity.swift:76`, `AppIntents/PlayerEntity.swift:122`,
  `AppIntents/TeamEntity.swift:76` — `allFromStorage()`. *Preventive: no current test
  calls these, but the P1 AppIntentsTesting work will call entity code from tests and
  would hit the identical wall.*

Checked and deliberately left alone: `extension Lineup` (Models.swift:911) and
`extension PitchingAgeBracket` (TeamRules.swift:665) — their members are already
individually marked `nonisolated`, so there is no defect.

## Availability-gating convention (for the rest of 3.5)

- Gate iOS-27-only API at the call site with `if #available(iOS 27, *) { … } else { …26
  fallback… }`, or put `@available(iOS 27, *)` on a new type/function that is only ever
  reached on 27.
- Do **not** funnel gating through a `Bool` capability flag
  (`var hasPrivateCloudCompute: Bool`). Swift availability does not propagate through a
  `Bool`; the compiler still demands a real `#available` check at the point the 27-only
  symbol is touched, so a Bool helper cannot unlock the API and only adds a second source
  of truth.
- When adding an `extension` to a `nonisolated` type, annotate the extension
  `nonisolated` too (see the defect above).

## Not done here — pre-existing, unrelated, tracked separately

`WhatsNewContentTests.testTheRunningVersionHasAnEntry()` and
`.testTheCurrentEntryFitsTheSheet()` fail. Cause: `MARKETING_VERSION` is 3.4.1 but the
newest `WhatsNewContent.all` entry is 3.4 (WhatsNewView.swift:25), so
`WhatsNewContent.current` (exact `CFBundleShortVersionString` match) is nil. This is the
exact gap those tests exist to catch, left by the 3.4.1 bump on this branch. It predates
this ticket and has no connection to the SDK bump or the isolation fixes. Fix is a product
call: add a 3.4.1 entry, relabel the 3.4 entry, or decide 3.4.1 shows no sheet.

## Verify

```
xcodebuild test -project "Lineup Builder.xcodeproj" -scheme "Lineup Builder" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' \
  -only-testing:"Lineup BuilderTests"
```
Expect: 0 compile errors; only the two WhatsNew failures above. (Unit target only — the
full `test` still hangs in the UI target per the standing LLDB-flake note.)
