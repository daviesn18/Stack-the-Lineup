# Handoff — v3.3 Siri & App Intents (2026-07-30)

## TL;DR

**Phase 0 (foundations) is built, building clean, and covered by 133 passing unit tests. Phases 1–4 are not started.**

Three blockers stood between this app and any App Intent, and all three are now cleared: intents can read team data (`TeamStorage`), check Pro without the SwiftUI environment (`PurchaseManager.isProNow()`), and navigate to a specific player or game on both iPhone and iPad (`STLRoute` + `AppRouter`).

Two planning assumptions turned out to be wrong, both in our favor:
- **No Siri entitlement is needed.** `com.apple.developer.siri` is a *SiriKit* entitlement; SiriKit is deprecated and App Intents is the sole path forward. No developer-portal capability, no provisioning change.
- **"iOS 27" is a marketing label, not a technical gate.** Everything in 3.3 scope builds on the installed iOS 26.5 SDK today.

Nothing is committed yet — all changes are in the working tree on `main`.

---

## 1. Scope

Source: Asana section **"3.3 - Siri AI"** (`1217027047050411`) in *Stack the Lineup — Roadmap*, plus **Phase 2** of the completed *Natural Language Auto-Fill* ticket (`1215519098776981`), which the other tickets all depend on.

**In scope**

| Deliverable | Asana | Gating |
|---|---|---|
| `PlayerEntity` / `TeamEntity` + Spotlight index | `1216544711240780` | Free |
| `FillLineupIntent` | `1215519098776981` (Phase 2) | Pro |
| `GameRecapIntent` | `1216544711115108` | Pro |
| `FairPlayRuleIntent` | `1216543825469858` | Free |
| Localization (Spanish, then French) | `1214429900445010` | Parallel track |

**Cut entirely** (Nick, 2026-07-30 — "remove any ticket about in-game or mid-game"): `1216545022075375` Voice-driven mid-game substitution, and its prerequisite `1215510622693227` Mid-game substitution tracking. Nick is moving both back to *Future Consideration* himself.

Why they were cut: `InningAssignment` is `[UUID: FieldPosition]` — one position per player per inning. There is no way to record "pitched innings 1–3, then moved to LF," so a voice sub has nothing to write to. The prerequisite is Large, free-tier, and touches archive accuracy, fair-play math, and CloudKit sync.

**Key decisions**
- **Hybrid data access** — read-only intents answer without foregrounding the app; write intents open it.
- **Free discovery, Pro actions** — Spotlight surfacing and rules Q&A are free (a funnel); Auto-Fill and recap inherit their existing gates.
- **Intents live in the main app target**, not a separate App Intents extension. With `openAppWhenRun = false` the system background-launches the app, giving direct `UserDefaults.standard` access — so no App Group projection to keep in sync and no pbxproj target surgery. `TeamStorage` is the seam if Siri latency later justifies a real extension.

---

## 2. Phase 0 — DONE

Build clean, **133 unit tests passing, 0 failures**.

### 2a. `Lineup Builder/TeamStorage.swift` (new)

Single read path for the persisted `[Team]` blob. `LineupStore.applyStoredData()` now delegates decode and local-vs-iCloud arbitration here, so an intent can't drift from the app.

`LoadResult` has three cases and the distinction is load-bearing:

```swift
case loaded(teams: [Team], activeID: UUID?)
case empty(activeID: UUID?)   // genuine first launch → migration may run
case decodeFailed             // blob exists but won't decode → leave state ALONE
```

Collapsing `empty` and `decodeFailed` into "no teams" is exactly what would let a schema mismatch cascade into `migrateOrCreateDefaultTeam()` and overwrite iCloud with a blank team. This preserves the SAFETY RULE that was already documented on `applyStoredData()`.

`loadTeamsForReading()` is the flat convenience entry point for intents — returns `([], nil)` for both no-data and corrupt-data, because an intent should say "no teams yet" rather than attempt recovery.

Incidental fix: `teamsKey` / `savedAtKey` / `activeTeamKey` existed as `private let`s on `LineupStore` but the write path used raw string literals, so the constants were dead and the two sides could silently diverge. Both now reference `TeamStorage`.

`LineupStore.shouldPreferCloudBlob` is kept as a thin forwarder to `TeamStorage.shouldPreferCloudBlob` so the existing `LineupStoreTests` cases are untouched.

### 2b. `Lineup Builder/PurchaseManager.swift`

```swift
nonisolated static func isProNow() async -> Bool
```

Walks `Transaction.currentEntitlements` with the existing `productGrantsPro`. `checkEntitlement()` now delegates to it, so the grandfathering rule has one implementation — two copies would eventually disagree, and the drifted copy would silently revoke Pro from a $4.99 buyer.

`nonisolated` so a background-launched intent doesn't hop to the main actor just to read an entitlement. `productGrantsPro` was made `nonisolated` for the same reason.

### 2c. `Lineup Builder/STLRoute.swift` (new)

`STLRoute` enum (`.players`, `.lineup`, `.positions`, `.history`, `.player(UUID)`, `.gameLog(UUID)`, `.team(UUID)`), URL parse + build, and `AppRouter`.

Before this, `ContentView.onOpenURL` mapped **every** `stackthelineup://` URL to `selectedTab = 1`, and **iPad ignored deep links entirely** — `iPadDashboardView` drives its own `DetailTab` and never read `selectedTab`.

- `ContentView.applyRoute(_:)` owns team switching (a Spotlight hit for a player on another roster is otherwise a silent no-op), the iPhone tab index, and the player sheet.
- `iPadDashboardView` observes `router.request` and maps to `DetailTab` via `DetailTab.init(_ tab: STLRoute.Tab)`.
- `AppRouter.Request` carries a nonce so `.onChange` fires even when the same route is requested twice — asking Siri for the same player twice should navigate both times.
- Unknown hosts fall back to `.lineup`, and `stackthelineup://lineup` is preserved verbatim, so **the widget already on someone's home screen keeps working**. There's a regression test pinning this.

### 2d. Target config — NOT NEEDED

The original plan called for adding `com.apple.developer.siri`. That was wrong: it's a SiriKit entitlement. Pure App Intents need no entitlement and no `INIntentsSupported`. `NSUserActivityTypes` is only needed if we later adopt `NSUserActivity` donation, which this scope doesn't.

### 2e. Player route destination

`.player(uuid)` opens `PlayerFormView` scrolled to **Position Preferences** (Nick's call, 2026-07-30). Position Preferences is a *section inside* `PlayerFormView`, not a standalone screen, so this is a new `focusPositionPreferences: Bool = false` parameter plus a `ScrollViewReader` anchor.

The scroll is deferred ~0.35s: scrolling during the sheet's presentation transition is dropped and the form opens at the top instead.

Note: Position Preferences is Pro-gated, so a routed non-Pro coach lands on `lockedPreferencesSection`. That's intended — Spotlight is a free discovery surface and this is the natural upsell.

### Files touched

```
new:  Lineup Builder/TeamStorage.swift
new:  Lineup Builder/STLRoute.swift
new:  Lineup BuilderTests/TeamStorageTests.swift   (8 tests)
new:  Lineup BuilderTests/STLRouteTests.swift      (10 tests)
mod:  Lineup Builder/Models.swift                  (applyStoredData delegates; key constants)
mod:  Lineup Builder/PurchaseManager.swift         (isProNow)
mod:  Lineup Builder/ContentView.swift             (router, onOpenURL, applyRoute, routed sheet)
mod:  Lineup Builder/iPadDashboardView.swift       (DetailTab.init, router observation)
mod:  Lineup Builder/PlayersView.swift             (focusPositionPreferences)
```

---

## 3. Phases 1–4 — NOT STARTED

### Phase 1 — Entities + Spotlight (free)

New files in the app target:
- `PlayerEntity: AppEntity, IndexedEntity` — id `UUID`, display from `Player.displayNameWithNumber`, jersey + team name as subtitle. `PlayerEntityQuery: EntityQuery & EntityStringQuery` backed by `TeamStorage`, so Siri resolves "Caleb" by name.
- `TeamEntity: AppEntity, IndexedEntity`.
- `FieldPositionAppEnum: AppEnum` mirroring `FieldPosition` (`Models.swift:20`, already a `String` enum with `displayName`). **A wrapper, not a conformance on `FieldPosition` itself** — `Models.swift` and `AutoFillEngine.swift` stay framework-independent, per the architecture note in `1215519098776981`.
- `STLShortcuts: AppShortcutsProvider`.
- `OpenPlayerIntent` / `OpenTeamIntent` — `openAppWhenRun = true`, route via `AppRouter`.

Index on launch and after roster mutations. Exclude players not on the active roster. **Open question the ticket flags:** confirm during implementation whether Spotlight surfacing really is free once entities are registered.

### Phase 2 — `FillLineupIntent` (Pro)

Params: `team: TeamEntity?`, `innings: Int?`, `constraints: String?`. `openAppWhenRun = true` — it mutates the lineup and the coach should see the resulting grid.

The constraints string feeds the **existing** `AutoFillNLConstraintService.parse(prompt:)` (`AutoFillNLConstraintService.swift:211`) — no duplicate parsing logic. `AutoFillResult.incompleteMessage(multiInning:)` (`AutoFillEngine.swift:67`) and `constraintNoticeMessage(players:)` (`:118`) already produce coach-facing prose and become the intent's `ProvidesDialog` verbatim.

**Prerequisite refactor:** `DefensiveGridView.performAutoFill(scope:)` (`DefensiveGridView.swift:657`) interleaves parse, engine call, store write, undo snapshot, and toast/alert sequencing — and `iPadDashboardView.swift:921–932` holds a second copy. Extract an `AutoFillCoordinator` used by all three callers. This collapses existing duplication rather than adding a third copy. Regression-test it against the Bug 3 and Bug 6 prompts recorded in `1215519098776981`.

### Phase 3 — `GameRecapIntent` (Pro)

`openAppWhenRun = false`. Reads the most recent `GameLog` via `TeamStorage`; composes from `SeasonStatsCalculator.compute` (`SeasonStatsCalculator.swift:30`), the `nonisolated` fair-play helpers on `Lineup` (`Models.swift` ~622–790), and `GameLog.pitchCounts`. Returns `ProvidesDialog & ShowsSnippetView`.

Reuse `GameLogInsightsService`'s availability gating so an unsupported device degrades to the structured summary rather than failing. Disambiguate multiple same-day games by prompting on `team`.

### Phase 4 — `FairPlayRuleIntent` (free)

`openAppWhenRun = false`. Params: `LeagueRulesetAppEnum` (Little League / Cal Ripken / Babe Ruth) + rule topic.

**Answer from structured lookup against `FairPlayConfig` and `PitchingLimits` — NOT a freeform Foundation Models generation.** These are pitch-count and rest-day limits that exist to protect kids' arms; a hallucinated number spoken in Siri's voice is materially worse than "I don't have that rule." Foundation Models may phrase a retrieved fact conversationally, but must not be the source of the fact.

### Parallel — Localization (`1214429900445010`)

Gated on Xcode 27's native tooling. Only stays cheap if Phases 1–4 are built localizable from day one: every `AppEnum` `DisplayRepresentation`, `IntentDescription`, parameter title, `AppShortcuts` phrase, and dialog string through a string catalog as written. Retrofitting `AppShortcutsProvider` phrases across two languages is markedly more expensive. Spanish first.

---

## 4. Environment facts

- **Xcode 26.6, iOS 26.5 SDK. No iOS 27 SDK installed** — and it isn't needed. `AppIntent`/`AppEnum`/`EntityQuery`/`AppShortcutsProvider` are iOS 16; `AppEntity`/`IndexedEntity` (Spotlight semantic index) are iOS 18. Deployment target is already 26.x. Only *View Annotations* (Phase 3 of the parent ticket, out of scope) needs iOS 27.
- Xcode project uses `PBXFileSystemSynchronizedRootGroup` — new **files** are free; a new **target** means editing exception sets. Another reason intents stay in the app target.
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. New types callable from intents must be explicitly `nonisolated` (`TeamStorage`, `STLRoute` both are).
- Debug builds run on **simulators only, never Nick's physical devices** (standing rule from the July 2026 data wipe).

---

## 5. Next session

1. **Commit Phase 0** — still uncommitted on `main`. Branch first.
2. **Finish the deep-link simulator check.** Unit tests cover URL parsing, round-tripping, and tab mapping, but the end-to-end confirmation (does `stackthelineup://history` actually select the History tab in the running app?) **did not complete** — the simulator's input pipe became unresponsive mid-check and the "Open in Stack the Lineup?" confirmation couldn't be dismissed. Redo on a fresh simulator, on **both** iPhone and iPad — iPad is where this historically breaks.
3. **Verify the Position Preferences scroll** with a real roster. The 0.35s deferral is tuned by eye, not measured.
4. **Start Phase 1.** `TeamStorage.loadTeamsForReading()` is the entry point for `PlayerEntityQuery`.
5. **Confirm Spotlight surfacing is free** with registered entities — this is the ticket's open question and determines whether `1216544711240780` is a byproduct or its own build.

### Verification commands

Build:
```bash
xcodebuild -project "Lineup Builder.xcodeproj" -scheme "Lineup Builder" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug build
```

Unit tests:
```bash
xcodebuild -project "Lineup Builder.xcodeproj" -scheme "Lineup Builder" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:"Lineup BuilderTests" test
```

Deep link:
```bash
xcrun simctl openurl booted "stackthelineup://history"
```

Pro-gated intents: `simctl` bypasses the scheme's `.storekit` config — use a temporary `FORCE_PRO` `#if DEBUG` hook or launch from Xcode.
