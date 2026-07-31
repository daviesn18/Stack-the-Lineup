# Handoff — v3.3 Siri & App Intents (2026-07-31)

## TL;DR

**Phases 0, 1 and 2 are built, verified end to end on iPhone and iPad, and covered by 172 passing unit tests. Phases 3–4 are not started.**

Players and teams are searchable from the home screen today: type a name in Spotlight, tap the result, and the app opens that player on their Position Preferences — from a cold start. The ticket's open question is answered: **Spotlight surfacing is free** once entities are registered. `1216544711240780` is delivered.

Auto-Fill is now reachable without touching the app: "Fill my lineup in Stack the Lineup" fills every inning, opens on the Positions grid, and reads the result back including any slot it couldn't cover. `1215519098776981` Phase 2 is delivered. The three-way duplication that ticket flagged is collapsed — `AutoFillCoordinator` is the single implementation the iPhone grid, the iPad summary pane and the intent all run through.

Three blockers stood between this app and any App Intent, and all three are now cleared: intents can read team data (`TeamStorage`), check Pro without the SwiftUI environment (`PurchaseManager.isProNow()`), and navigate to a specific player or game on both iPhone and iPad (`STLRoute` + `AppRouter`).

Two planning assumptions turned out to be wrong, both in our favor:
- **No Siri entitlement is needed.** `com.apple.developer.siri` is a *SiriKit* entitlement; SiriKit is deprecated and App Intents is the sole path forward. No developer-portal capability, no provisioning change.
- **"iOS 27" is a marketing label, not a technical gate.** Everything in 3.3 scope builds on the installed iOS 26.5 SDK today.

Committed on branch **`feature/app-intents-phase-0`**, branched from `main`. Not pushed — no remote branch, no PR.

```
c1d73c2 Add FillLineupIntent on a shared AutoFillCoordinator
dee85d2 Document Phase 1 in the handoff doc
c16c39d Add Phase 1 App Intents: entities, Spotlight index, Siri phrases
ea93652 Bring the App Intents handoff doc up to date
a60736d Fix deep links being dropped when they cold-launch the app
3c6de3f Add App Intents foundations: shared read path, Pro check, deep-link routing
```

---

## 1. Scope

Source: Asana section **"3.3 - Siri AI"** (`1217027047050411`) in *Stack the Lineup — Roadmap*, plus **Phase 2** of the completed *Natural Language Auto-Fill* ticket (`1215519098776981`), which the other tickets all depend on.

**In scope**

| Deliverable | Asana | Gating |
|---|---|---|
| `PlayerEntity` / `TeamEntity` + Spotlight index — **DONE** | `1216544711240780` | Free |
| `FillLineupIntent` — **DONE** | `1215519098776981` (Phase 2) | Pro |
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

Build clean and verified end to end on both device idioms (section 6). Test count at the time of this phase was 135; the suite now stands at **157 passing, 0 failures**.

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

### 2d-bis. THE COLD-START BUG (found during verification — read this before Phase 1)

The first cut of the router wired both consumers with `.onChange(of: router.request)` only. That works when the app is **already running** and silently drops the route when the deep link **cold-launches** the app.

`onOpenURL` fires during scene connection, which sets `router.request` *before* `iPadDashboardView` is constructed. `.onChange` only fires for changes observed after a view is installed, so a route that is already pending when the view appears is never seen.

**This is the common case for Siri and Spotlight** — they nearly always launch the app cold. Left unfixed, every Phase 1 entity tap would have looked broken while every manual test on a warm app passed.

Fix: `consumePendingRoute()` in both `ContentView` and `iPadDashboardView`, called from **both** `.onAppear` and `.onChange`, guarded by a `lastHandledRouteNonce` so a re-appearance can't re-apply the last route and yank the coach off a tab they just picked by hand.

Verified on device idioms after the fix — see section 6.

### 2e. Player route destination

`.player(uuid)` opens `PlayerFormView` scrolled to **Position Preferences** (Nick's call, 2026-07-30). Position Preferences is a *section inside* `PlayerFormView`, not a standalone screen, so this is a new `focusPositionPreferences: Bool = false` parameter plus a `ScrollViewReader` anchor.

The scroll is deferred ~0.35s: scrolling during the sheet's presentation transition is dropped and the form opens at the top instead.

Note: Position Preferences is Pro-gated, so a routed non-Pro coach lands on `lockedPreferencesSection`. That's intended — Spotlight is a free discovery surface and this is the natural upsell.

### Files touched

```
new:  Lineup Builder/TeamStorage.swift
new:  Lineup Builder/STLRoute.swift                (STLRoute + AppRouter)
new:  Lineup BuilderTests/TeamStorageTests.swift   (8 tests)
new:  Lineup BuilderTests/STLRouteTests.swift      (12 tests)
mod:  Lineup Builder/Models.swift                  (applyStoredData delegates; key constants)
mod:  Lineup Builder/PurchaseManager.swift         (isProNow)
mod:  Lineup Builder/ContentView.swift             (router, onOpenURL, applyRoute,
                                                    routed sheet, consumePendingRoute)
mod:  Lineup Builder/iPadDashboardView.swift       (DetailTab.init, consumePendingRoute)
mod:  Lineup Builder/PlayersView.swift             (focusPositionPreferences)
new:  HANDOFF-app-intents.md                       (this file)
```

Untouched and deliberately left out of both commits: the two untracked `AppStore-Screenshots*` directories, which predate this work.

---

## 3. Phase 1 — DONE

All in `Lineup Builder/AppIntents/`. New **files** in a synchronized root group join the app target automatically — no pbxproj edit was needed.

### 3a. Entities

`PlayerEntity` and `TeamEntity` conform to `AppEntity, IndexedEntity, URLRepresentableEntity`. Both are **flattened snapshots** — a player carries their team's name so a result can say which roster it came from. Only `id` is authoritative; everything else is display data, and callers re-read the live record through the store by id.

`PlayerEntity.allFromStorage()` reads **every** team, not just the active one. This deviates from the original plan ("exclude players not on the active roster"), which was written before `ContentView.applyRoute` learned to switch teams. It switches now, so a hit on another roster resolves correctly — and a coach running a spring and a fall team expects to find a name either way. The team name in the subtitle disambiguates.

### 3b. Search ranking

`PlayerSearch` / `TeamSearch` (in the entity files) are pure and unit-tested — Siri hands over a transcribed string with no structure, so this scoring *is* "did the coach mean this player."

- `"12"`, `"number 12"` and `"#12"` all resolve to the same jersey. Siri transcribes the spoken form; Spotlight passes the typed one.
- Case- and diacritic-insensitive, so "jose" finds "José".
- A team-name match scores **below every player-name match**: "Tigers" lists the roster, but a player actually named Tiger still outranks their teammates.
- No match returns nothing. Returning the whole roster on a miss would make Siri disambiguate over 14 children instead of admitting it didn't catch the name.

### 3c. `FieldPositionAppEnum`

A wrapper, **not** a conformance on `FieldPosition` — `Models.swift` and `AutoFillEngine.swift` stay framework-independent, per the architecture note in `1215519098776981`. The bridge is a hand-written exhaustive switch in both directions, so adding a position to `FieldPosition` fails the build here until it's given a spoken name. Synonyms carry what coaches actually say ("short", "first", "left"), which the formal display names don't cover.

### 3d. Spotlight indexing

`STLSpotlightIndexer.reindexIfNeeded()` runs at launch (`LineupBuilderApp`) and at the tail of `LineupStore.saveLocalOnly()`.

**The signature guard is load-bearing.** `save()` fires on every position drag; an unconditional reindex would hammer CoreSpotlight throughout a game. The signature hashes only what the index displays — inning assignments, schedules and pitch counts are excluded; the game *count* is included because it appears in a team's subtitle. The save path passes its existing snapshot rather than re-reading storage.

The signature is recorded **only after a fully successful pass**. Delete-then-index means a throw partway would otherwise cache a signature against an empty index, leaving Spotlight blank until the roster happened to change again.

### 3e. THE SPOTLIGHT TAP-THROUGH TRAP (read this before Phases 2–4)

`IndexedEntity` gets an entity **listed** in Spotlight. Tapping the result **only launches the app** — it lands on whatever tab was last open, which reads exactly like the feature being broken. Indexing alone is half a feature.

`URLRepresentableEntity` looks like the fix and **is not**. Verified on iOS 26.5: adding `static let urlRepresentation: URLRepresentation = "stackthelineup://player/\(.id)"` changed nothing about tap-through — the result still just launched the app. (The conformance is kept: it's still correct for Shortcuts' Open-URL flows and for a future `OpenIntent`.)

What actually fires is the **`CSSearchableItemActionType` user activity**. `ContentView.onContinueUserActivity` handles it and calls `STLRoute.fromSpotlightIdentifier`, which resolves by pulling any UUID out of the identifier and checking it against rosters we actually hold — rather than parsing an encoding AppIntents owns and doesn't document. An id matching nothing returns nil instead of guessing.

### 3f. `AppRouter` is now a singleton

Intents set routes from **outside the view tree**, often before `ContentView` exists — Siri and Spotlight almost always cold-launch. `AppRouter.shared` is what lets a request survive that gap; `ContentView` uses `@ObservedObject`, not `@StateObject`, because it no longer owns the object.

That makes a request outlive its window, so `Request` now carries `createdAt` and a **first-ever** drain (`lastHandledRouteNonce == nil`) ignores anything older than 60s. Without it a second iPad window would open replaying a route from an hour ago. Live routing is untouched — the cold-launch case is milliseconds old.

### Files added / touched in Phase 1

```
new:  Lineup Builder/AppIntents/PlayerEntity.swift        (entity, query, PlayerSearch)
new:  Lineup Builder/AppIntents/TeamEntity.swift          (entity, query, TeamSearch)
new:  Lineup Builder/AppIntents/FieldPositionAppEnum.swift
new:  Lineup Builder/AppIntents/OpenIntents.swift         (Player / Team / Lineup)
new:  Lineup Builder/AppIntents/STLShortcuts.swift
new:  Lineup Builder/AppIntents/STLSpotlightIndexer.swift
new:  Lineup BuilderTests/AppIntentEntityTests.swift      (17 tests)
mod:  Lineup Builder/STLRoute.swift        (AppRouter.shared, Request.createdAt/isFresh,
                                            fromSpotlightIdentifier, uuids(in:))
mod:  Lineup Builder/ContentView.swift     (@ObservedObject router, onContinueUserActivity,
                                            handleSpotlightSelection, freshness guard)
mod:  Lineup Builder/iPadDashboardView.swift            (freshness guard)
mod:  Lineup Builder/Models.swift                       (reindex hook in saveLocalOnly)
mod:  Lineup Builder/LineupBuilderApp.swift             (reindex on launch)
mod:  Lineup BuilderTests/STLRouteTests.swift           (12 -> 17 tests)
```

### Isolation gotcha

`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, and `nonisolated` on a struct propagates to `@Parameter`'s mutable stored property — a warning today, a hard error in Swift 6 mode. So: **entities, queries and the AppEnum are `nonisolated`; the intents are not.** Leaving intents on the default actor is also honest, since every `perform()` touches `AppRouter`.

---

## 4. Phase 2 — DONE

### 4a. `Lineup Builder/AutoFillCoordinator.swift` (new)

The prerequisite refactor, and the bulk of the phase. One place that runs a fill end to end: parse the coach's prompt (racing an 8s timeout), call `AutoFillEngine`, compose the messages, emit analytics. It owns **no UI state and never touches `LineupStore`** — it takes a `Team` in and hands an `AutoFillOutcome` back, which is exactly what lets an intent use it with no view hierarchy.

The two existing copies had already drifted, which is the argument against letting a third appear:
- The iPhone one rebuilt the "couldn't fill" text in a private `buildAutoFillIncompleteMessage` that duplicated `AutoFillResult.incompleteMessage(multiInning:)` almost line for line — and joined paragraphs with `\n` instead of `\n\n` and never sorted the inning numbers. **Both are now fixed on iPhone by deletion**, since everything routes through the shared version.
- The alert-sequencing delays differed (0.7s vs 0.35s stacking).
- Only the iPhone copy captured an undo snapshot.

`DefensiveGridView.FillScope` is gone, replaced by a top-level `AutoFillScope` (`.inning(Int)` / `.through(Int)`). `AutoFillPopover` now takes a `currentInning` so it can emit `.inning(n)` rather than a context-free `.thisInning`.

What stayed with the views: alerts, the undo toast, popover state.

### 4b. `Lineup Builder/AppIntents/FillLineupIntent.swift` (new)

Params `team: TeamEntity?`, `throughInning: Int?`, `instructions: String?`. `openAppWhenRun = true`.

**The intent computes but does not write.** It reads the target team through `TeamStorage`, runs the coordinator, then stages the finished lineup on `AppRouter.stageFill(_:teamID:)`; `ContentView.consumePendingFill()` applies it to the store. It cannot write storage itself — whenever the app is running, `LineupStore` holds the authoritative in-memory copy and its next `save()` silently overwrites anything written to `UserDefaults` behind its back.

Computing in the intent rather than deferring the whole operation is what lets `spokenSummary` report a real result ("Filled 70 positions in innings 1–7…") instead of "opening the app". The alternative — awaiting a continuation the view fulfils — risks hanging on the app-foregrounding order, which App Intents does not document.

`consumePendingFill` switches to the owning team *before* applying, because `LineupStore.save()` only pushes the **active** team to CloudKit; mutating an inactive one would persist locally and never sync.

Defaults `throughInning` to the team's `gameInningCount`, not the popover's "last inning that already has assignments" — a coach asking by voice with no inning named wants the game filled. Clamped to the innings that exist, so a spoken "12" fills 7.

### 4c. THE PRO-GATE TRAP (read this before Phases 3–4)

**A Pro-gated intent must not just `throw`.** With `openAppWhenRun = true`, iOS brings the app forward whether `perform()` succeeds or fails. Verified on iOS 26.5: throwing `needsPro` left the app open on whatever tab was last used, with nothing on screen explaining why nothing happened — the same dead end as a Spotlight result that opens the app and goes nowhere (3e).

The fix is `AppRouter.requestPaywall(source:)` + a `.sheet(item:)` in `ContentView`, so the intent does what tapping the bolt button does. Siri says "Auto-Fill is part of Pro. I've opened the upgrade options for you." and the paywall is already up behind it. Deliberately **not** an `STLRoute` case: routes round-trip through `stackthelineup://` URLs, and a paywall nobody navigated to shouldn't be summonable by an arbitrary link.

`STLIntentError` (in `FillLineupIntent.swift`) still covers the genuinely terminal cases — no such team, read-only shared team, nobody marked active. Those read as complete sentences because App Intents speaks `localizedStringResource` verbatim.

### 4d. Shortcut phrases

The `FillLineupIntent` phrases are deliberately **parameter-free** ("Fill my lineup in ⟨app⟩"). Both params are optional, so a bare sentence works and the coach adjusts on screen. A spoken *number* in a phrase slot resolves far less reliably than an entity does — a bad trade for a Pro action that rewrites the whole game.

### Files added / touched in Phase 2

```
Lineup Builder/AutoFillCoordinator.swift            NEW  AutoFillScope, AutoFillOutcome, the coordinator
Lineup Builder/AppIntents/FillLineupIntent.swift    NEW  the intent + STLIntentError
Lineup Builder/AppIntents/STLShortcuts.swift        +1 AppShortcut
Lineup Builder/STLRoute.swift                       AppRouter.PendingFill + PaywallRequest
Lineup Builder/ContentView.swift                    consumePendingFill(), paywall sheet
Lineup Builder/DefensiveGridView.swift              -292 lines: two helpers deleted, FillScope removed
Lineup Builder/iPadDashboardView.swift              -147 lines: its whole copy deleted
Lineup BuilderTests/AutoFillCoordinatorTests.swift  NEW  15 tests
```

Net −185 lines in the two views.

---

## 5. Phases 3–4 — NOT STARTED

### Phase 3 — `GameRecapIntent` (Pro)

`openAppWhenRun = false`. Reads the most recent `GameLog` via `TeamStorage`; composes from `SeasonStatsCalculator.compute` (`SeasonStatsCalculator.swift:30`), the `nonisolated` fair-play helpers on `Lineup` (`Models.swift` ~622–790), and `GameLog.pitchCounts`. Returns `ProvidesDialog & ShowsSnippetView`.

Reuse `GameLogInsightsService`'s availability gating so an unsupported device degrades to the structured summary rather than failing. Disambiguate multiple same-day games by prompting on `team`.

### Phase 4 — `FairPlayRuleIntent` (free)

`openAppWhenRun = false`. Params: `LeagueRulesetAppEnum` (Little League / Cal Ripken / Babe Ruth) + rule topic.

**Answer from structured lookup against `FairPlayConfig` and `PitchingLimits` — NOT a freeform Foundation Models generation.** These are pitch-count and rest-day limits that exist to protect kids' arms; a hallucinated number spoken in Siri's voice is materially worse than "I don't have that rule." Foundation Models may phrase a retrieved fact conversationally, but must not be the source of the fact.

### Parallel — Localization (`1214429900445010`)

Gated on Xcode 27's native tooling. Only stays cheap if Phases 1–4 are built localizable from day one: every `AppEnum` `DisplayRepresentation`, `IntentDescription`, parameter title, `AppShortcuts` phrase, and dialog string through a string catalog as written. Retrofitting `AppShortcutsProvider` phrases across two languages is markedly more expensive. Spanish first.

---

## 6. Environment facts

- **Xcode 26.6, iOS 26.5 SDK. No iOS 27 SDK installed** — and it isn't needed. `AppIntent`/`AppEnum`/`EntityQuery`/`AppShortcutsProvider` are iOS 16; `AppEntity`/`IndexedEntity` (Spotlight semantic index) are iOS 18. Deployment target is already 26.x. Only *View Annotations* (Phase 3 of the parent ticket, out of scope) needs iOS 27.
  - Don't be misled by `xcrun simctl list runtimes`: an **iOS 27.0 beta runtime** (`24A5380i`) is installed. That's a runtime, not an SDK. `Platforms/iPhoneOS.platform/Developer/SDKs/` still holds only `iPhoneOS26.5.sdk`, so everything above stands.
- Xcode project uses `PBXFileSystemSynchronizedRootGroup` — new **files** are free (confirmed: the whole `AppIntents/` subfolder joined the app target with no pbxproj edit); a new **target** means editing exception sets. Another reason intents stay in the app target.
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Types callable from intents must be explicitly `nonisolated` (`TeamStorage`, `STLRoute`, both entities, both queries, the AppEnum). **The intents themselves must not be** — see the isolation gotcha at the end of section 3.
- Debug builds run on **simulators only, never Nick's physical devices** (standing rule from the July 2026 data wipe).

---

## 7. Verification performed

**Unit:** full suite green on every change.

**End-to-end, iPhone 17 Pro (erased simulator, fresh install):**
- Started on Players → `stackthelineup://history` → History tab selected. ✅
- → `stackthelineup://lineup` (the shipped widget's link) → Lineup tab selected. ✅ No regression.

**End-to-end, iPad Pro 13-inch (M5), seeded Test Team, 10 players:**
- Warm app → `stackthelineup://history` → History pane selected. ✅
- **Cold launch** (app terminated first) → `stackthelineup://history` → launched straight into History. ✅ *This is the case that exposed the bug in 2d-bis; it failed before the fix and passes after.*
- `stackthelineup://player/<uuid>` → switched to Players, opened Edit Player scrolled to **Position Preferences**, values matching that player's roster row. ✅ Confirms both the route and the 0.35s scroll deferral on a real roster.

**Phase 1, end to end on iPad Pro 13-inch (M5), seeded Test Team, 10 players:**
- Launched the app once (indexes on `.task`), then **terminated it**. Home → Spotlight → typed "Drew Santos".
- "Stack the Lineup → #9 Drew Santos / Test Team" appeared as its own section, above web results. ✅ **Spotlight surfacing is free** — no entitlement, no extra configuration beyond `IndexedEntity`.
- Tapped the result **with the app terminated** → cold launch straight into Edit Player, scrolled to Position Preferences, values matching Drew's roster row (1B Strength, P/3B Capable, CF Emergency). ✅
- *Before* the `CSSearchableItemActionType` handler, this same tap launched the app and went nowhere — see 3e. Both the plain `IndexedEntity` build and the `URLRepresentableEntity` build failed it.
- Spotlight → "Stack the Lineup" → the **"Open Lineup" App Shortcut** appears as a tile in Top Hit. ✅ `STLShortcuts` is registered.
- `xcrun simctl openurl` with `stackthelineup://player/<uuid>`, cold → same destination. ✅ Phase 0 routing unregressed.

**Phase 2, end to end on iPhone 17 Pro and iPad Pro 13-inch (M5), seeded Test Team, 10 players:**
- **Not Pro:** Spotlight → "Fill Lineup" tile → app opens with the **paywall sheet already presented** and Siri showing "Auto-Fill is part of Pro. I've opened the upgrade options for you." ✅ Before this, a thrown error opened the app to a silently unchanged screen — see 4c.
- **Pro** (temporary `FORCE_PRO` env hook in `isProNow()`, since `simctl` bypasses the scheme's `.storekit` config — hook removed before commit): Spotlight → "Fill Lineup" → **"Filled 70 positions in innings 1–7. C (Inning 2), P (Inning 5) could not be filled. Not enough active players…"**, app landed on the **Positions** tab with the grid populated and innings 2 and 5 flagged. ✅ Confirms staging → `consumePendingFill` → store write → route, and that `spokenSummary` flattens the alert copy's paragraph breaks.
- **iPhone UI, unregressed:** cleared all positions → bolt → *Fill This Inning* on inning 1 → "Auto-filled 10 positions (inning 1)" toast with Undo. Switched to inning 3, filled again → "Auto-filled 10 positions (**inning 3**)". ✅ Confirms `currentInning` reaches `AutoFillScope.inning(_:)` rather than a hardcoded 0.
- **iPad UI, unregressed:** cleared all positions → *Auto-Fill Open Positions* → *Fill Innings 1–7* → grid filled, "Some Positions Not Filled" alert rendering the shared `incompleteMessage(multiInning: true)`. ✅

**Not verifiable in a simulator** (needs a device): Siri *voice* invocation of the phrases, and whether the parameterized phrases ("Open ⟨player⟩ in Stack the Lineup") resolve a spoken name through `EntityStringQuery` as intended. The phrase set compiles and registers; only the speech path is unproven.

**Simulator gotcha that cost time:** `mcp__Claude_Code_iOS_Simulator__control` takes coordinates in **device points** (the `attach` call reports the space, e.g. 402×874 for iPhone 17 Pro, 1032×1376 for iPad Pro 13"), *not* screenshot pixels. Passing screenshot coordinates makes every tap silently miss — they get clamped and land in a corner, which looks exactly like an unresponsive simulator. Convert: `point = pixel / screenshot_dimension × point_dimension`.

## 8. Next session

1. **Start Phase 3** (`GameRecapIntent`). It's the first `openAppWhenRun = false` intent, so it's also the first real test of whether background-launching the whole app answers inside Siri's window — time it on a device (section 5).
2. **Test every new intent cold, and every Pro gate without Pro.** Terminate the app first. See 2d-bis, 3e and 4c — all three bugs found so far were invisible warm or invisible with Pro, and Siri/Spotlight almost always cold-launch.
3. **Verify the Siri phrases on a physical device.** The only Phase 1 claim not proven in the simulator (section 6). Do it before building more phrases on the same assumption.
4. **Localization is now overdue.** Phases 1 and 2 shipped with `LocalizedStringResource` literals inline and **no string catalog in the repo** (`find . -name "*.xcstrings"` returns nothing). That was the cheap moment to add one. Phase 2 added the first dialog strings; it's still cheaper now than after Phases 3–4 add more — see `1214429900445010`.

### Verification commands

Build:
```bash
xcodebuild -project "Lineup Builder.xcodeproj" -scheme "Lineup Builder" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug build
```

Unit tests:
```bash
xcodebuild -project "Lineup Builder.xcodeproj" -scheme "Lineup Builder" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:"Lineup BuilderTests" test
```

Suppress the welcome + tour covers so the tab bar is reachable on a fresh install
(they otherwise sit on top of everything and make deep-link results unreadable):
```bash
xcrun simctl spawn booted defaults write com.nickdavies.LineupBuilder.Lineup-Builder hasCompletedTutorial -bool YES
```

Pull a real player/team UUID out of a booted simulator to build a `://player/<uuid>` link:
```bash
python3 -c "import plistlib,json,subprocess;c=subprocess.check_output(['xcrun','simctl','get_app_container','booted','com.nickdavies.LineupBuilder.Lineup-Builder','data']).decode().strip();d=plistlib.load(open(c+'/Library/Preferences/com.nickdavies.LineupBuilder.Lineup-Builder.plist','rb'));[print(t['name'],t['id'],[ (p['firstName'],p['id']) for p in t['players'][:3]]) for t in json.loads(bytes(d['stl_teams']))]"
```

Deep link:
```bash
xcrun simctl openurl booted "stackthelineup://history"
```

Pro-gated intents: `simctl` bypasses the scheme's `.storekit` config — use a temporary `FORCE_PRO` `#if DEBUG` hook or launch from Xcode.
