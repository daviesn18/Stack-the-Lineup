# Handoff — v3.3 Siri & App Intents (2026-07-31)

> **What's still open lives in [`BACKLOG.md`](BACKLOG.md), not here.** This document is the record of *why* — the dead ends, the measurements, the rules that came out of them. Section 9's remaining items are backlog 1.3 (Siri on a device — a submission blocker), 2.1, 2.2 and 4.4. Note that §9b.3's ship-readiness item is **done**: the version is `3.3 (36)` and the What's New registry has its 3.3 entry.

## TL;DR

**Phases 0–4 are built, verified end to end on iPhone and iPad, and covered by 248 passing unit tests (0 failures — see 6ter). Every intent in 3.3 scope is delivered, plus a follow-on pitch-eligibility intent and the discovery surfaces (section 6bis).**

> **One thing is still waiting on Nick — see 9a.2.** Parameterized Siri phrases don't surface in typed Spotlight, which makes the physical-device voice check a blocker rather than a nice-to-have.
>
> **9a.1 (`ShortcutsLink` app name) is fixed and verified on screen**, but it cost more than the doc predicted: the prescribed `INFOPLIST_KEY_CFBundleName` fix does nothing, and the only lever is `PRODUCT_NAME` — which also renames the executable and the `.app` wrapper. **Read 9a.1 before shipping it**; backing it out is one `git revert`.

A coach can now ask what their own rules are without opening the app: "How many innings do I need to play someone in the infield?" and "how many days rest does 33 pitches buy?" both answer by voice, free, from that team's stored config. `1216543825469858` is delivered — but note it shipped **team-scoped rather than league-scoped**, which is a scope change from the original ticket; see section 6.

Players and teams are searchable from the home screen today: type a name in Spotlight, tap the result, and the app opens that player on their Position Preferences — from a cold start. The ticket's open question is answered: **Spotlight surfacing is free** once entities are registered. `1216544711240780` is delivered.

Auto-Fill is now reachable without touching the app: "Fill my lineup in Stack the Lineup" fills every inning, opens on the Positions grid, and reads the result back including any slot it couldn't cover. `1215519098776981` Phase 2 is delivered. The three-way duplication that ticket flagged is collapsed — `AutoFillCoordinator` is the single implementation the iPhone grid, the iPad summary pane and the intent all run through.

"How did we do" is answered **without the app opening at all** — innings, who pitched and on how many pitches, and which fair-play rules the game missed. `1216544711115108` is delivered.

Three blockers stood between this app and any App Intent, and all three are now cleared: intents can read team data (`TeamStorage`), check Pro without the SwiftUI environment (`PurchaseManager.isProNow()`), and navigate to a specific player or game on both iPhone and iPad (`STLRoute` + `AppRouter`).

Two planning assumptions turned out to be wrong, both in our favor:
- **No Siri entitlement is needed.** `com.apple.developer.siri` is a *SiriKit* entitlement; SiriKit is deprecated and App Intents is the sole path forward. No developer-portal capability, no provisioning change.
- **"iOS 27" is a marketing label, not a technical gate.** Everything in 3.3 scope builds on the installed iOS 26.5 SDK today.

Committed on branch **`feature/app-intents-phase-0`**, branched from `main`. Not pushed — no remote branch, no PR.

```
8ac8905 Fix three iPad fair-play checks that had drifted from the rules
ee98c6f Document Phase 3 in the handoff doc
7f0642b Add GameRecapIntent, answering by voice without opening the app
48569d4 Document Phase 2 in the handoff doc
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
| `GameRecapIntent` — **DONE** | `1216544711115108` | Pro |
| `FairPlayRuleIntent` — **DONE** | `1216543825469858` | Free |
| Localization (Spanish, then French) | `1214429900445010` | Parallel track |

**Cut entirely** (Nick, 2026-07-30 — "remove any ticket about in-game or mid-game"): `1216545022075375` Voice-driven mid-game substitution, and its prerequisite `1215510622693227` Mid-game substitution tracking. Nick is moving both back to *Future Consideration* himself.

Why they were cut: `InningAssignment` is `[UUID: FieldPosition]` — one position per player per inning. There is no way to record "pitched innings 1–3, then moved to LF," so a voice sub has nothing to write to. The prerequisite is Large, free-tier, and touches archive accuracy, fair-play math, and CloudKit sync.

**Key decisions**
- **Hybrid data access** — read-only intents answer without foregrounding the app; write intents open it.
- **Free discovery, Pro actions** — Spotlight surfacing and rules Q&A are free (a funnel); Auto-Fill and recap inherit their existing gates.
- **Intents live in the main app target**, not a separate App Intents extension. With `openAppWhenRun = false` the system background-launches the app, giving direct `UserDefaults.standard` access — so no App Group projection to keep in sync and no pbxproj target surgery. `TeamStorage` is the seam if Siri latency later justifies a real extension.

---

## 2. Phase 0 — DONE

Build clean and verified end to end on both device idioms (section 6). Test count at the time of this phase was 135; the suite now stands at **248 passing, 0 failures**.

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

## 5. Phase 3 — DONE

### 5a. `Lineup Builder/GameRecap.swift` (new)

`GameRecap` plus `GameRecapBuilder` — the whole answer, computed from one `GameLog`, with no UI and no store.

**Deliberately not a Foundation Models summarization.** `GameLogInsightsService` already does season-level prose across many games, which is the right shape for "what patterns do you see". A single-game recap is a set of facts a coach repeats to a parent — who pitched, how many pitches, who came up short on innings — and a model paraphrasing those is a way to get them subtly wrong. Everything here is counted.

Two choices about *which* roster the recap describes, both load-bearing:
- Players come from `log.playerSnapshot`, **not** the live roster. A coach who has since removed a player still wants to hear that they pitched. `SeasonStatsCalculator` filters by the live roster for the opposite and equally correct reason.
- `absentPlayerIDs` on the synthetic lineup is left **empty**, even though some players carry `.absent` innings for a late arrival. That's what the app's own Fair Play rail does with a live lineup — only `playersUnderFieldingMinimum` exempts them. Making the recap kinder than the rail would be the recap being wrong.

One guard worth knowing about: a rain-shortened game (2 innings against a 4-inning minimum) would put the whole roster "under", which is true and useless. `fieldingMinimumSkipped` reports the rule as un-appliable instead.

### 5b. `Lineup.fairPlayFindings(players:config:)` (new, `Models.swift`)

The prerequisite extraction, and the same story as `AutoFillCoordinator`. The "which fair-play rules are switched on, at what thresholds" logic had been copy-pasted onto **five** surfaces, and the copies have already drifted:

| Surface | State |
|---|---|
| `LineupView.fairPlayWarningCount` | correct — now uses the shared helper |
| `PositionSummaryView.fairPlaySection` | correct — now uses the shared helper |
| `iPadDashboardView.matrixFairPlayFooter` | ~~omitted both battery rules~~ — fixed in `8ac8905` |
| `iPadDashboardView.violationCount` (~line 160) | ~~ignored the config entirely, and double-counted a player in two rules~~ — fixed in `8ac8905` |
| `iPadDashboardView.FairPlayRailView` | ~~same as above~~ — fixed in `8ac8905` |

The recap would have been the sixth copy, and a recap reporting a clean game while the rail shows a violation is worse than no recap. The three iPad divergences were fixed in a separate change (`8ac8905`) rather than riding along inside Phase 3, since they change visible iPad badge counts. All five surfaces now share the helper, and the rail gained the two battery warning cards it never had.

### 5c. THE PRO-GATE RULE, INVERTED (read alongside 4c)

`GameRecapIntent` is `openAppWhenRun = false`, and that flips the Phase 2 rule exactly:

- **`openAppWhenRun = true`** → **must not throw** on a failed entitlement check. The app comes forward regardless, and the coach lands on an unchanged screen with no explanation. Route to the paywall (4c).
- **`openAppWhenRun = false`** → **must throw**. Nothing comes forward, so the thrown `localizedStringResource` *is* the entire answer. Verified: Spotlight shows "Game recaps are part of Pro. Open Stack the Lineup to upgrade." and the app never opens.

`STLIntentError.needsPro(feature:)` exists for the second case only. Its doc comment says so, because the two intents doing opposite things looks like an inconsistency until you know why.

### 5d. Writing for the ear, and for a box that clips

Both of these were found by *looking at the result*, not by reading the code — neither is visible in a unit test that only checks the facts are right.

- A spoken issue naming six players ("Jake Rivera, Tyler Nguyen, Drew Santos, Eli Park, Nate Coleman, and Leo Huang never played the outfield") is not something anyone can hold onto. The dialog now names three and counts the rest; the snippet still names everyone. Hence `RecapIssue` carrying names-plus-predicate rather than a finished sentence.
- **A snippet view clips at a fixed height — it does not scroll.** Ten stacked batting-order rows pushed the fair-play verdict off the bottom entirely. The batting order is now one wrapping line, fair play sits *above* it (the reverse of the spoken order, for the opposite reason: spoken, nothing gets cut and last is what people remember), and the issue list caps at two with "+N more in the app".

**Known limit — RESOLVED in Phase 4, see 6e.** In the Spotlight presentation the snippet gets whatever height is left after the dialog, and a recap with several fair-play issues clipped partway through the fair-play block. The cause was the dialog itself: it restated the entire recap in a paragraph above the snippet, eating the height. Moving to `IntentDialog(full:supporting:)` shrank the dialog to one line, and the same recap (Test Team vs Eagles, 3 pitchers, 3 issues) now renders the whole pitching table and both shown issues without clipping. Re-verified on iPhone 17 Pro.

The batting order is still below the fold in this presentation, which is by design — it's last precisely because it's the least load-bearing thing to lose. The snippet is still not the place to put anything critical. Not checked in the Shortcuts app's (taller) result card.

### 5e. `GameLogEntity`

Added for the `game` parameter and for same-day disambiguation — a doubleheader is two logs on one date where "the newest" is a coin flip the coach can't see, so the intent prompts. Deliberately **not** `IndexedEntity`: indexing promises tap-through, and tap-through needs a `CSSearchableItemActionType` handler per type (3e). If games get indexed later, index and tap-through ship together or not at all.

### 5f. `Analytics` is now `nonisolated`

It only forwards to TelemetryDeck and reads no state; it was main-actor-isolated purely by the project default. A background-answering intent shouldn't hop to the main actor to record a signal.

### Files added / touched in Phase 3

```
Lineup Builder/GameRecap.swift                    NEW  GameRecap, RecapIssue, RecapPitchingLine, builder
Lineup Builder/AppIntents/GameRecapIntent.swift   NEW  the intent + GameRecapSnippetView
Lineup Builder/AppIntents/GameLogEntity.swift     NEW  entity + query
Lineup Builder/Models.swift                       FairPlayFindings + Lineup.fairPlayFindings
Lineup Builder/LineupView.swift                   -18 lines, now shares the helper
Lineup Builder/PositionSummaryView.swift          -14 lines, now shares the helper
Lineup Builder/AppIntents/FillLineupIntent.swift  STLIntentError gains .needsPro/.noGames/.noSuchGame
Lineup Builder/AppIntents/STLShortcuts.swift      +1 AppShortcut
Lineup Builder/Analytics.swift                    nonisolated
Lineup BuilderTests/GameRecapTests.swift          NEW  21 tests
```

---

## 6. Phase 4 — DONE

### 6a. THE SCOPE CHANGE: team rules, not league rules

The plan called for a `LeagueRulesetAppEnum` parameter (Little League / Cal Ripken / Babe Ruth). **The codebase can't answer that question, and building it that way would have meant inventing numbers** — the exact failure the ticket was written to prevent:

- `LeagueRuleset` (`Models.swift:113`) is documented as **informational only**: it stores the coach's selection and applies no presets. It defaults to `.custom`.
- The only rule table in the app is `PitchingConfig.applyLittleLeaguePreset()`, and it seeds a **team's own** `ageLimits`, which the coach then edits freely. There is no Cal Ripken table and no Babe Ruth table anywhere.

So two of the three cases had nothing to read. Nick's call (2026-07-31): *"Asking about rules should be about that specific team… They don't need to be tied to a governing body."* The intent answers from the team's own `FairPlayConfig` and `PitchingConfig`, which is also the more useful question — those are the rules this app will hold their lineup to tonight.

If league presets are ever wanted, that's a separate piece of work: build the rule tables first, then teach this intent to read them.

### 6b. `Lineup Builder/TeamRules.swift` (new)

`RuleTopic` (9 cases), `RuleLine`, `TeamRulesAnswer`, `TeamRulesBuilder`. Pure — no UI, no store, Foundation only, same shape as `GameRecap.swift`.

Nothing is generated. Every number is read from the stored config, and the "is this rule on" test in each builder matches `fairPlayFindings` exactly (`> 0` for the three minimums, the flag for bench, `> 0` for the two battery thresholds). An answer that says a rule is on while the Fair Play rail declines to enforce it would be worse than no answer.

`RuleLine` carries `label` / `value` / `spoken` because the two renderings want different things — "Infield minimum / 1 inning" is unreadable aloud, and a full sentence is a wasteful row in a box that clips.

### 6c. THE REFUSAL PATHS ARE THE FEATURE

Most of the file, and most of its 34 tests, are about **declining to answer**. `PitchingConfig` ships with the Little League preset one method call away, so the tempting bug is quoting it to a coach who never switched pitching rules on. Four cases return a caveat and **no numbers at all**:

| Situation | Answer |
|---|---|
| `rulesEnabled == false` | "Pitching rules are turned off for Tigers…" |
| Named player has no `leagueAge` | "I don't have a league age for Bobby…" |
| Nobody on the roster has an age | "No one on Tigers has a league age set…" |
| Bracket exists but has no limits entered | "You haven't set pitch limits for 11 to 12 year olds yet." |

Three tests assert the spoken answer contains **no digit** in these states. A partially configured roster answers for the brackets it can *and* names the ones it can't, because answering only for the configured brackets reads as a complete answer.

### 6d. The split between throwing and answering (refines 5c)

`openAppWhenRun = false`, so 5c's rule applies — but it needed one more distinction:

- **Throw** when the intent can't tell *who* is being asked about: `.noTeam`, `.noSuchPlayer` (new case).
- **Answer normally** when it knows who but the rule isn't there to quote. "You haven't turned pitching rules on" is the correct answer to "what's my pitch limit", not an error, and it comes back as a dialog plus snippet rather than an error banner.

### 6e. Two things only looking at it caught

Both passed every unit test and were still wrong on screen.

- **The rest ladder read the same four thresholds three times.** A roster of 9-to-13-year-olds resolves to three brackets that share one ladder under the preset, so the spoken answer was ~90 words of near-identical text. `grouped(_:by:)` now collapses *adjacent* brackets whose answer is word-for-word identical into one "Ages 9-14" line. Adjacency is load-bearing: if 9-10 differs while 7-8 and 13-14 match, merging them would produce "7 to 14", which would be a lie about 9-10. There's a test pinning that.
- **The dialog and the snippet were saying everything twice.** Spotlight renders the dialog as a paragraph *above* the table, so every number appeared twice and the table was buried (Nick, on seeing it: *"This is a ton of words… redundant and overwhelming"*). Fixed with `IntentDialog(full:supporting:)` — `full` is the complete spoken answer for a voice-only surface with no table to read, `supporting` is one short line ("Your rest day thresholds for Test Team.") for when the snippet is on screen. `TeamRulesAnswer` exposes both as `spokenSummary` and `shortSummary`.

**`GameRecapIntent` had the identical bug and is now fixed the same way** (`GameRecap.shortSummary` → "Your recap of the Eagles game."). This is the general rule for **any** intent returning `ProvidesDialog & ShowsSnippetView`, not a quirk of one screen. It also turned out to be the cause of the snippet clipping recorded as a known limit in 5d: the dialog was eating the height the table needed. Both are re-verified on device idiom — the same recap that used to cut off mid-sentence now renders its whole fair-play block.

### 6f. Shortcut phrases: three tiles, no topic slot

`topic` has nine cases with names no coach says out loud ("fielding minimum"), so transcribing one into a phrase slot would be the least reliable part of the feature. Instead there are three tiles with the topic preset — My Rules, Pitch Limits, Rest Days — each with phrases someone would actually say. The synonyms on `RuleTopicAppEnum` still cover all nine for anyone building their own shortcut.

Rest Days is deliberately preset **without** a pitch count, so it answers with the whole ladder — the right answer to a question asked without a number in it. A coach with a specific count sets it in Shortcuts, where a typed number doesn't have to survive transcription.

### 6g. The master Fair Play toggle is derived, not stored

Worth knowing before touching this: `FairPlayRulesView`'s "Fair Play Rules Enabled" switch looks like a persisted master flag and isn't. It's a computed binding that zeroes every individual field. So reading the individual fields — which is what `TeamRules` and `fairPlayFindings` both do — is already correct, and there is no master flag to check.

### Files added / touched in Phase 4

```
Lineup Builder/TeamRules.swift                       NEW  RuleTopic, RuleLine, TeamRulesAnswer, builder
Lineup Builder/AppIntents/FairPlayRuleIntent.swift   NEW  intent + RuleTopicAppEnum + snippet
Lineup Builder/AppIntents/STLShortcuts.swift         +3 AppShortcuts
Lineup Builder/AppIntents/FillLineupIntent.swift     STLIntentError gains .noSuchPlayer
Lineup BuilderTests/TeamRulesTests.swift             NEW  34 tests
```

No changes to `Models.swift` — `PitchingAgeBracket` gained `spokenRange` / `lowAge` / `highAge` via an extension in `TeamRules.swift`.

### Parallel — Localization (`1214429900445010`)

Gated on Xcode 27's native tooling. Only stays cheap if Phases 1–4 are built localizable from day one: every `AppEnum` `DisplayRepresentation`, `IntentDescription`, parameter title, `AppShortcuts` phrase, and dialog string through a string catalog as written. Retrofitting `AppShortcutsProvider` phrases across two languages is markedly more expensive. Spanish first.

---

## 6bis. Follow-on — Pitch eligibility and discovery (DONE, commit `b542805`)

Not part of the original 3.3 scope. Item 3 of the old next-session list, plus the discovery gap that list didn't mention.

### 6bis-a. THE `.eligible` CONFLATION — the reason `PitchEligibility.swift` exists

`PitchEligibilityEngine.status(for:...)` returns `.eligible` for **three different situations**:

1. genuinely rested,
2. `config.rulesEnabled == false` — nothing was checked,
3. no `ageLimits` entry for their bracket — nothing was checked.

For the roster badge that conflation is harmless: no rules configured, no warning to show. **Spoken it is not**, because all three come out as "Yes, Bobby can pitch" — a sentence that sounds like the app checked when in two of the three cases it didn't, and the consequence lands on a kid's arm.

`EligibilityVerdict` splits them into `.clear` / `.limited` / `.blocked` / `.notTracked`, and `PitchEligibilityAnswerBuilder` decides which applies **before** consulting the engine rather than trying to read it back out of an `.eligible`. Six of the sixteen tests sit on that boundary. A `.notTracked` answer also drops `lastOuting`, because reciting "they last threw 55 pitches" under "I'm not tracking pitch counts" contradicts the sentence it's attached to.

If the engine ever grows a fourth meaning for `.eligible`, this file is what has to change with it.

### 6bis-b. Discovery: the tip is arc 2, deliberately

`AskSiriTip` anchors on the Auto-Fill bolt, joining `PositionsAutoFillTip` (arc 1) and `AutoFillConstraintsTip` (arc 2) — three `.tourTip` modifiers on one control, reading as one progression: here's the button, here's what you can tell it, here's how to skip it entirely.

Arc 2 rather than arc 1 because every voice action is worth more once a season is underway: Game Recap needs an archived game to recap, and the pitching answers need recorded counts to be about anything. Arc 1 is a tight path to a first game.

Safe by construction on the triple anchor: both arc-2 tips read `Tour.secondGame.currentTip as? <Type>`, so at most one is ever non-nil.

`SiriShortcutsView` (Settings › Help & Support › Siri Shortcuts) is the permanent home for the phrase list — a tour tip fires once. **Its phrase strings are hand-copied from `STLShortcuts` and there is no way to read an `AppShortcut`'s phrases back at runtime, so the two files have to be edited together.** That warning is in the file header too.

### Files added / touched

```
Lineup Builder/PitchEligibility.swift                    NEW  verdict, answer, builder
Lineup Builder/AppIntents/PitchEligibilityIntent.swift   NEW  intent + snippet
Lineup Builder/SiriShortcutsView.swift                   NEW  the phrase list
Lineup Builder/AppIntents/STLShortcuts.swift             +1 AppShortcut (9 total)
Lineup Builder/ContextualTips.swift                      AskSiriTip, added to Tour.secondGame
Lineup Builder/DefensiveGridView.swift                   third .tourTip on the bolt
Lineup Builder/SettingsView.swift                        Siri Shortcuts row + sheet
Lineup BuilderTests/PitchEligibilityAnswerTests.swift    NEW  16 tests
```

---

## 6ter. `TeamStorageTests` shared a mutable store with the running app (FIXED 2026-08-01)

`testNoStoredDataReportsEmpty()` failed on every simulator that had ever held a roster, and passed on a fresh one — which is how earlier phases could honestly report "0 failures" while this sat there.

**The race.** `TeamStorage.load()` hardcoded `UserDefaults.standard`. The test host *is* the real app, so `.standard` in these tests was the live app's store — and `LineupStore.saveLocalOnly()` writes the same three keys from a `Task.detached` hopping to `MainActor.run` (`Models.swift:1297`), fired on launch by the dedup/normalize pass at `Models.swift:1610`. `setUp()` cleared the keys synchronously; a pending app write could land before the assertion read. The xcresult confirms the branch: `TeamStorageTests.swift:78`, the `XCTFail` — `load()` returned `.loaded`, so the keys were repopulated between the clear and the read.

**Why the old guard could never work.** The file carried a `setUp`/`tearDown` snapshot-restore billed as SAFETY. It was guarding against a *synchronous* writer while the actual writer was *asynchronous*. It also meant every run mutated the developer's real simulator roster and relied on `tearDown` running to put it back.

**The fix.** `load(defaults:)` and `loadTeamsForReading(defaults:)` now take an injectable store defaulting to `.standard`, so no production call site changed. The tests use a private suite (`com.stackthelineup.tests.TeamStorage`), cleared in `setUp` as well as `tearDown` because a crashed run can leave the domain populated. The snapshot dance is gone — there is nothing left to protect.

Only the *local* store is injectable. The KV store is untouched, which is fine because DEBUG never reads it (the July 2026 wipe rule).

`testNoStoredDataReportsEmpty` was the only test asserting *absence*, which is why it lost most often — but the whole class was racy, since a stray app write could equally overwrite another test's fixture. Verified after the fix: 248 passed / 0 failed on the same simulator that had been failing, and the Test Team roster was still intact afterwards.

**If you add storage tests, do not reach for `UserDefaults.standard`** — take the suite. Any future test that asserts on the absence of app-written state will hit this same race.

---

## 7. Environment facts

- **Xcode 26.6, iOS 26.5 SDK. No iOS 27 SDK installed** — and it isn't needed. `AppIntent`/`AppEnum`/`EntityQuery`/`AppShortcutsProvider` are iOS 16; `AppEntity`/`IndexedEntity` (Spotlight semantic index) are iOS 18. Deployment target is already 26.x. Only *View Annotations* (Phase 3 of the parent ticket, out of scope) needs iOS 27.
  - Don't be misled by `xcrun simctl list runtimes`: an **iOS 27.0 beta runtime** (`24A5380i`) is installed. That's a runtime, not an SDK. `Platforms/iPhoneOS.platform/Developer/SDKs/` still holds only `iPhoneOS26.5.sdk`, so everything above stands.
- Xcode project uses `PBXFileSystemSynchronizedRootGroup` — new **files** are free (confirmed: the whole `AppIntents/` subfolder joined the app target with no pbxproj edit); a new **target** means editing exception sets. Another reason intents stay in the app target.
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Types callable from intents must be explicitly `nonisolated` (`TeamStorage`, `STLRoute`, both entities, both queries, the AppEnum). **The intents themselves must not be** — see the isolation gotcha at the end of section 3.
- Debug builds run on **simulators only, never Nick's physical devices** (standing rule from the July 2026 data wipe).

---

## 8. Verification performed

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

**Phase 3, end to end on iPhone 17 Pro, real archived game (Test Team vs Eagles, 5 innings, 3 pitchers with recorded pitch counts):**
- **Not Pro:** Spotlight → "Game Recap" → banner reading "Game recaps are part of Pro. Open Stack the Lineup to upgrade." and **the app never opened**. ✅ Confirms both `openAppWhenRun = false` and that throwing is the right channel here (5c).
- **Pro** (temporary DEBUG return in `isProNow()`, removed before commit): the full recap read back innings, all three pitchers with pitch counts, and the fair-play misses — with the app still closed. ✅
- Snippet rendered team, headline, the pitching table with pitch counts, and the fair-play block. Batting order present but below the fold in this presentation — see the known limit in 5d.
- Pluralization verified on the real data: "1 inning · 12 P" for a one-inning pitcher against "3 innings · 55 P".

**iPad fair-play fix (`8ac8905`), end to end on iPad Pro 13-inch (M5).** One lineup arranged to trip both bugs at once: Tyler catches innings 1–4, pitches inning 5, and has zero outfield innings.
- Outfield minimum set to **Off** → the "Missing outfield inning — Tyler" card disappears and the toolbar violation badge clears. ✅ The old `violationCount` and `FairPlayRailView` called `playersWithoutOutfield` unconditionally, so both would still have flagged him.
- Catcher-to-pitcher set to **3** → a "Caught, then pitched — Tyler" card appears and the matrix footer shows **no** green all-clear. ✅ The old footer found its four checked rules clear and would have rendered "All players meet fair play requirements" over a live battery violation.
- Badge no longer double-counts: a player missing both infield and outfield reads as 1, matching what iPhone already showed.

**Simulator gotcha, data seeding:** writing `stl_teams` into the app's defaults (`simctl spawn … defaults write`, or editing the plist directly) gets **silently clobbered** — a running or recently-running app re-saves its in-memory copy over it, and the app then shows pre-seed state that looks like the seed was wrong. Terminating first is not reliably enough. Two attempts were lost to this before switching to driving the app's own UI, which is slower but is also the only way to be sure the state under test is the state the app actually holds. Seeding is fine for *read-only* fixtures on a cold install (Phase 1/3 used it successfully); it is not fine for anything the app will write back to.

**Simulator gotcha that cost several round-trips:** after changing intent code, `simctl install` — *and even `simctl uninstall` followed by a fresh install* — can leave the **old intent binary running**. The dialog kept coming back with pre-fix copy while a unit test proved the new code was correct and `strings` proved it was in the installed dylib. Only `simctl shutdown` + `boot` picked up the change. **When verifying an App Intent, reboot the simulator after installing**, or you will "fix" code that was already right.

**Not verifiable in a simulator** (needs a device): Siri *voice* invocation of the phrases, and whether the parameterized phrases ("Open ⟨player⟩ in Stack the Lineup") resolve a spoken name through `EntityStringQuery` as intended. The phrase set compiles and registers; only the speech path is unproven.

**Phase 4, end to end on iPhone 17 Pro (reinstalled, simulator rebooted, app terminated), seeded Test Team, 10 players aged 10–13, Little League pitch preset on, fair play at 4/1/1 with no back-to-back bench:**
- Spotlight → **"Pitch Limits"** tile → answered with the app closed: "9 to 10 year olds can throw up to 75 pitches in a game. 11 to 12… 85. 13 to 14… 95." Snippet showed the three rows. ✅ Free — no Pro prompt, unlike Recap.
- Note what it *didn't* say: the preset also defines 7-8 (50) and 15-16 (95), and neither appeared, because nobody on the roster is that age. Roster-scoped bracket resolution confirmed on real data.
- Spotlight → **"Rest Days"** → first run read the same four thresholds three times, ~90 words (see 6e). After the fix: one line, "Ages 9-14 · 21+ → 1d, 36+ → 2d, 51+ → 3d, 66+ → 4d". ✅
- Spotlight → **"My Rules"** → five rows (fielding 4, infield 1, outfield 1, back-to-back bench Not allowed, pitching On), matching the app's own Fair Play and Pitching screens field for field. No clipping. ✅
- All three answered **without the app opening**, from a cold start, after a simulator reboot.

**Simulator gotcha that cost time:** `mcp__Claude_Code_iOS_Simulator__control` takes coordinates in **device points** (the `attach` call reports the space, e.g. 402×874 for iPhone 17 Pro, 1032×1376 for iPad Pro 13"), *not* screenshot pixels. Passing screenshot coordinates makes every tap silently miss — they get clamped and land in a corner, which looks exactly like an unresponsive simulator. Convert: `point = pixel / screenshot_dimension × point_dimension`.

## 9. Next session

### 9a. OPEN — needs Nick's decision (2026-07-31)

**1. `ShortcutsLink` shows the wrong app name. — DONE 2026-08-01, but read the correction.**

The button at the bottom of Settings › Siri Shortcuts read **"Lineup Builder shortcuts"** — the Xcode target name — while every phrase above it says "Stack the Lineup". On a screen whose whole job is teaching the name a coach has to say out loud, that was the one wrong word on it. It now reads **"Stack the Lineup shortcuts"**, verified on screen (iPhone 17 Pro, fresh install, simulator rebooted). At 16 characters it renders in full — no truncation, no ellipsis.

**The fix this doc previously prescribed does not work, and the "one-line build setting" framing was wrong.** Both dead ends were tried and measured:

- `INFOPLIST_KEY_CFBundleName = "Stack the Lineup"` — **no effect.** Built `Info.plist` still read `Lineup Builder`.
- Adding `CFBundleName` directly to `Lineup-Builder-Info.plist` — **also no effect.** With `GENERATE_INFOPLIST_FILE = YES` the build system writes `CFBundleName` from `PRODUCT_NAME` and that write wins over both the source plist and the `INFOPLIST_KEY_` injection.

The only lever is **`PRODUCT_NAME`**, which is why this is bigger than it looked. What actually shipped:

```
PRODUCT_NAME        = "Stack the Lineup"   (was $(TARGET_NAME))   Debug + Release
PRODUCT_MODULE_NAME = Lineup_Builder       (NEW — pin)            Debug + Release
TEST_HOST           → "Stack the Lineup.app/…/Stack the Lineup"   ×4
Lineup Builder.xcscheme  BuildableName → "Stack the Lineup.app"   ×3
```

- **`PRODUCT_MODULE_NAME` must be pinned.** It defaults to `PRODUCT_NAME`, so renaming without the pin renames the Swift module and breaks every `@testable import Lineup_Builder`.
- **`CFBundleExecutable` and the `.app` wrapper name change too** — from `Lineup Builder` to `Stack the Lineup`. That is shipping bundle metadata on a released app. Allowed on an App Store update, but it changes crash-report and dSYM naming. **This is the part that exceeds the original "add one build setting" decision; back it out if you'd rather not carry it.**
- No Swift source references the bundle or executable name, so the blast radius is entirely build settings + the scheme.
- Reverting is `git revert` of this commit — nothing else depends on it.

**Test result after the rename: 247 passed, 1 failed** — `TeamStorageTests.testNoStoredDataReportsEmpty()`, **pre-existing, not caused by the rename** (verified against unmodified `HEAD` 99ae3bc in a separate worktree, where it failed identically). **Fixed separately — see 6ter. The suite is now 248 / 0.**

**Still wrong, and not fixed:** `LineupView.swift:259` hardcodes `.navigationTitle("Lineup Builder")` — the old name, as the large title on the Lineup tab, which is far more visible than the `ShortcutsLink` button ever was. (`PDFGenerator.swift:457` uses it as a fallback header too.) Left alone deliberately: same product-identity call, and it's app copy rather than a build setting, so it's a one-word edit whenever you want it.

**2. Parameterized phrases don't surface in typed Spotlight — and two shortcuts now depend on them.**

Typing "Can Jake Rivera pitch" into Spotlight returns nothing, and "Can They Pitch" isn't a tile either. Typed Spotlight matches App Shortcut **titles**; a shortcut whose every phrase carries an entity slot only surfaces through **spoken** Siri.

- **This is not new and not a bug in Phase 4 or the follow-on.** `OpenPlayerIntent` and `OpenTeamIntent` have had the same shape since Phase 1, and section 8 has always recorded the voice path as unverified. What changed is the stake: two of the nine shortcuts are now voice-only, so "the phrases compile and register" no longer implies a coach can reach them.
- Confirmed working the other way round: every **parameter-free** tile (Open Lineup, Fill Lineup, Game Recap, My Rules, Pitch Limits, Rest Days) resolves by title in typed Spotlight.
- This makes item 2 below a blocker rather than a nice-to-have. Until a physical device proves spoken entity resolution, `PitchEligibilityIntent` and `OpenPlayerIntent` are only reachable by building a shortcut by hand.

**`AskSiriTip` — VERIFIED ON SCREEN 2026-08-01.** Previously the one discovery claim resting on a static argument rather than a sighting. iPhone 17 Pro, existing Test Team with an archived game: `ReuseApplyTemplateTip` presented on the Lineup tab's game-info header → *Got it* → Positions tab → `AutoFillConstraintsTip` on the Auto-Fill bolt → *Got it* → **`AskSiriTip` ("Or just ask", mic glyph) presented on the same bolt immediately**, no navigation away and back required.

Two things that had been flagged as risks and turned out not to be:

- The triple anchor on the bolt holds — three `.tourTip` modifiers on one control, and only the expected one presented.
- The one-cycle `currentTip` lag did **not** bite here, but do not read that as "dismissal is safe." `GameLogDetailView` hit exactly this bug on iPad (fixed 2026-07-26): two anchors from one ordered group, reading `currentTip` synchronously in body, and dismissing the first left the second permanently unpresented because nothing re-rendered the view. `DefensiveGridView` gets away with the synchronous read only because the popover dismissal happens to re-render it. **The standing rule still holds — a view hosting two or more anchors from the same ordered group should mirror `currentTip` through `currentTipUpdates` into `@State` rather than read it in body.** The bolt's three anchors are working on luck, not on design, and should be converted if that view's rendering ever changes.

Getting there needed no saved template — the header anchor renders whenever `hasArchivedGame` is true, so the earlier "needs a saved template" theory for why it wouldn't present was wrong. The likelier reason it was never seen before is that the earlier attempt reset the tour and went straight to Positions without dismissing `ReuseApplyTemplateTip` on the Lineup tab first.

### 9b. Standing work

1. **Localization is the long pole and it's overdue.** All four phases shipped `LocalizedStringResource` literals inline with **no string catalog in the repo** (`find . -name "*.xcstrings"` still returns nothing). Phase 4 added the most strings of any phase — nine `AppEnum` cases with synonyms, nine `shortLead` strings, and every sentence in `TeamRulesBuilder`. Note that the builder's phrasing is **assembled**, not literal ("Everyone active needs at least \(innings) in the infield"), which does not translate by swapping a table: plural rules and word order differ per language. That's a real design question to settle before Spanish, not a mechanical pass. See `1214429900445010`.
2. **Verify the Siri phrases on a physical device — now a blocker, see 9a.2.** Still the only claim never proven in a simulator (section 8), and there are now **9** shortcuts resting on it, two of which are voice-only. Blocked by the standing rule against debug builds on Nick's devices — needs a TestFlight build or an explicit exception.
3. **Ship-readiness, not in any Asana ticket.** `MARKETING_VERSION` is still **3.2** (build 33), and `WhatsNewContent.all` tops out at a 3.2 entry. The registry is keyed on `CFBundleShortVersionString`, so shipping 3.3 without adding an entry means the What's New sheet **silently never appears**. Nothing user-facing mentions Siri except the new tip and Settings row.
4. **Test every new intent cold, without Pro, and after rebooting the simulator.** See 2d-bis, 3e, 4c and the reboot gotcha in section 8 — every bug found across four phases was invisible warm, invisible with Pro, or invisible without a reboot.
5. **Look at every intent's result, don't just test it.** Both Phase 4 bugs (6e) passed the full unit suite and were still wrong on screen. Two of the three Phase 3 findings were the same. A green suite says the facts are right, not that the answer is usable.

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
