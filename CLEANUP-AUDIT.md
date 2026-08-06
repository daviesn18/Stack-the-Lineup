# Codebase Cleanup Audit — Stack the Lineup (Lineup Builder)

## Executive Summary

- **Scope:** 64 Swift files, ~27,262 LOC, plus `project.pbxproj`, 4 `.entitlements` files, 2 `Info.plist` files, and one stray `roadmap.jsx`. Targets: `Lineup Builder` (app), `STLWidgetExtension`, `Lineup BuilderTests`, `Lineup BuilderUITests`, `StackTheLineupTests`. Languages: Swift/SwiftUI only — no storyboards, no XIBs, no `@IBOutlet`/`@IBAction`, no `#selector` usage anywhere in the repo, so the usual iOS false-positive traps don't apply here. Sole SPM dependency (TelemetryDeck) is used.
- **Method:** every top-level type (205), every `func` name (369), and every framework import was reference-counted across all four targets plus non-code files. The project uses Xcode 16 filesystem-synchronized groups, so target membership is folder-based — that's what surfaced several of the orphaned-file findings below.

### Findings by category

| Category | Count | Est. LOC removable |
|---|---|---|
| 1. Dead code | 12 | ~515 |
| 2. Duplicate logic | 3 | ~100 (net, after consolidation) |
| 3. Unused UI components | 4 | (counted in #1) |
| 4. Overly complex implementations | 0 | — |
| 5. Legacy code | 1 | 123 |
| 6. Redundant queries / API calls | 1 | ~1 |
| 7. Abandoned files | 4 | ~190 |
| 8. Tech debt opportunities | 4 | — |

### Top 3 highest-impact, lowest-risk wins

1. **324 lines of unreachable SwiftUI views in `DefensiveGridView.swift`** — `PlayerInningRow`, `PitchAvailabilityBadge`, `PitcherStripCard`, `PitcherAvailabilityStrip`. Zero references anywhere including previews and tests. That file is the largest in the repo at 2,765 lines; this is a 12% cut with no behavioral surface.
2. **Four orphaned files that are in no build target at all** — `StackTheLineupTests/StackTheLineupTests.swift`, `Lineup Builder/Lineup_Builder.entitlements`, `STLWidget/STLWidget.entitlements`, `STLWidget/WidgetSnapshot.swift`. Three are byte-identical duplicates of files that *are* referenced; one (the test file) wouldn't even compile.
3. **`DebugDataSeeder` was one accidental long-press away from firing in the App Store build.** Shipping the seeder is intentional — it's the source of screenshot and marketing data with no real children's names — but press-and-hold on a version string is the standard iOS text-selection gesture, so a coach could reach it unintentionally. Now fixed: 7 taps on the Version row. See finding 8.1.

### What was intentionally left alone and why

- **`Models.swift` sync/merge logic (lines ~1270–1580)** — CloudKit migration, KV-store precedence, and last-writer-wins merge. Actively being hardened per `HANDOFF-data-recovery.md`, covered by `LineupStoreTests` and `DataIntegrityTests`, and the source of a recent production incident. Nothing here is dead; it's the last code in the repo that should be touched by a cleanup pass.
- **`AutoFillEngine.swift` (976 lines)** — dense but the density is inherent to a constraint solver, and it has real test coverage in `AutoFillEngineTests`. No dead branches found.
- **Six files with uncommitted working-tree changes** (`ContentView`, `DebugDataSeeder`, `GameLogDetailView`, `LineupView`, `Models`, `TemplateLockEditorView`) — findings against these are reported but none are in the Phase 1 script, so the script can't collide with in-flight edits. Every Phase 1 line-level change targets `DefensiveGridView.swift`, which is clean in the working tree.
- **`Analytics.swift` signal names** — reference-counted as strings, but whether a signal is still consumed in the TelemetryDeck dashboard is outside the repo.

---

## Findings

### 1. Dead Code

**`Lineup Builder/DefensiveGridView.swift:1872` — `PlayerInningRow`**
- Why unnecessary: 134-line SwiftUI view. `grep -rn '\bPlayerInningRow\b'` across all `.swift` files in all four targets returns exactly one hit — the declaration itself. No `#Preview` references it, no test references it, and the repo contains no storyboards/XIBs and no selector-based dispatch that could reach it. The `// MARK: - Player Row in Inning` header above it and its own doc comment describe a per-inning list row that the current grid UI replaced.
- Confidence: **High**
- Impact: −134 lines from the repo's largest file (2,765 → 2,631).
- Risks before deletion: None identified. It declares `@EnvironmentObject var store` / `purchaseManager`, so if it were reachable and unlisted it would crash at runtime, not compile-fail — but it isn't reachable. Build the `Lineup Builder` target to confirm.
- Recommendation: **Delete now** (Phase 1).

**`Lineup Builder/DefensiveGridView.swift:2554` — `PitchAvailabilityBadge`**
**`Lineup Builder/DefensiveGridView.swift:2628` — `PitcherStripCard`**
**`Lineup Builder/DefensiveGridView.swift:2694` — `PitcherAvailabilityStrip`**
- Why unnecessary: an isolated three-view cluster. `PitchAvailabilityBadge` and `PitcherAvailabilityStrip` each have exactly one repo-wide hit (their declarations). `PitcherStripCard` has two — its declaration and one instantiation at line 2721, *inside* `PitcherAvailabilityStrip`. So the whole cluster is reachable only from itself. `PitchAvailabilityBadge.BadgeContent` (line 2602) is likewise used only within the dead badge.
- The shared helper `pitchesRemaining(for:gameLogs:config:referenceDate:)` at line 2507 is **live** — three real call sites (`AutoFillEngine.swift:516`, `PositionSummaryView.swift:1002`, `DefensiveGridView.swift:2037`). Keep it. Its section header comment at line 2502 says it "provides badge + strip card views," which becomes false once the cluster goes.
- Confidence: **High**
- Impact: −189 lines (2551–2739), plus one stale comment line corrected.
- Risks before deletion: The only real risk is deleting `pitchesRemaining` along with them — the cleanup script's line range stops at 2551 and starts *after* the function's closing brace at 2549 precisely to avoid that. Verify `PositionSummaryView` still compiles.
- Recommendation: **Delete now** (Phase 1).

**`Lineup Builder/PitchEligibilityEngine.swift:298–376` — `PitchingGuideSummaryRow` + `coachesGuideSummary(gameLogs:players:config:referenceDate:)`**
- Why unnecessary: the entire `// MARK: - Coaches Guide Summary` section — 79 lines, 21% of the file. `PitchingGuideSummaryRow` appears only within `coachesGuideSummary`; `coachesGuideSummary` has zero call sites. The doc comment says it "Builds rows for the Coaches Guide pitching summary table," and no such table exists — `PDFGenerator.swift` has no reference to it, and neither does any view.
- Confidence: **High** on being unreferenced, but the *decision* is a product one: this looks like a built-but-unshipped feature rather than an abandoned one, and it's the non-trivial half of a PDF section someone may still intend to ship.
- Impact: −79 lines.
- Risks before deletion: `git log` will tell you whether this was written toward an in-flight roadmap item. If the Coaches Guide PDF is still planned, deleting this is throwing away finished work.
- Recommendation: **Flag for manual review** (Phase 3) — decide "ship it or cut it," don't let it sit half-connected.

**`Lineup Builder/CloudKitManager.swift:241` — `fetchAllTeams()`**
- Why unnecessary: 34 lines, zero call sites. Its doc comment prescribes its own use case ("Use for a full re-sync (e.g. after migration, or when the change token is invalidated by a zone reset)") — but the migration path at `Models.swift:1277` calls `migrateFromKVStoreIfNeeded` and the sync path at `Models.swift:1424` calls `fetchChanges()`. Nothing routes to it.
- Confidence: **High** (unreferenced) / **Medium** (should it go)
- Impact: −34 lines.
- Risks before deletion: This is a plausible recovery lever for exactly the class of bug described in `HANDOFF-data-recovery.md`. Deleting a working full-resync path while a data-integrity incident is still open is bad timing.
- Recommendation: **Keep for now, revisit after the sync hardening lands.** If it's genuinely the recovery tool, wire it to something (a Settings "Force full re-sync" row) so it stops reading as dead.

**`Lineup Builder/CloudKitManager.swift:104` — `isAccountAvailable()`**
- Why unnecessary: 3-line wrapper over `ckContainer.accountStatus()`, zero call sites. Every CloudKit entry point in `Models.swift` instead calls `ensureZoneExists()` and handles the throw.
- Confidence: **High**
- Impact: −5 lines.
- Risks before deletion: None.
- Recommendation: **Delete after verifying** the app target builds (Phase 2).

**`Lineup Builder/DeviceTokenManager.swift:52` — `refreshTokenForCurrentTeam(store:)`**
- Why unnecessary: 11 lines, zero call sites. Its doc comment says "Called when the coach switches teams" — but the team-switch path (`LineupStore.activeTeamID` setter and `TeamSwitcherSheet`) never calls it. Only `didRegister(deviceToken:store:)` → `saveTokenForAllTeams` runs, and that fires once per APNs registration.
- Confidence: **High** on zero references. **Medium** on it being safe to delete: this looks less like dead code and more like a **missing wire-up**. If a coach joins a shared team after APNs registration, no token record is written for that team, so they may silently not receive its notifications.
- Impact: −11 lines if deleted — but the correct fix may be to *call* it, not remove it.
- Risks before deletion: Deleting it papers over a possible notification-delivery gap.
- Recommendation: **Manual review** (Phase 3). Test: join a shared team on a device that already registered for APNs, then have another coach finalize a lineup. If no push arrives, this function is the fix, not the cruft.

**`Lineup Builder/DeviceTokenManager.swift:108` — `removeTokens(for:)`**
- Why unnecessary: 22 lines, zero call sites. Doc comment: "Call when a coach leaves a shared team so they stop receiving its notifications." No leave-team flow calls it.
- Confidence: **High** on zero references; same "missing wire-up, not dead code" pattern as above.
- Impact: −22 lines if deleted.
- Risks before deletion: A coach who leaves a shared team keeps receiving its push notifications indefinitely. That's a live privacy/UX bug this function was written to prevent.
- Recommendation: **Manual review** (Phase 3), paired with the finding above.

**`Lineup Builder/Models.swift:1765` — `LineupStore.clearBattingOrder()`**
- Why unnecessary: 5 lines, zero call sites. `clearAll()` (line 1771) does the same thing plus clearing innings, and *is* used. The batting-order-only variant appears to be a leftover from before the combined clear.
- Confidence: **High**
- Impact: −5 lines.
- Risks before deletion: It's a public method on the central store; confirm no test exercises it (`grep` across `Lineup BuilderTests` returns nothing).
- Recommendation: **Delete after verification** (Phase 2).

**`Lineup Builder/PDFGenerator.swift:499` — `drawColoredDot(color:x:y:)`**
- Why unnecessary: 5-line private static helper, zero call sites within its own file (it's `private`, so the file is the whole search space). Sibling helpers `drawText` and `drawFooter` are both used.
- Confidence: **High** — a `private` symbol unreferenced in its own file is as certain as this gets in Swift.
- Impact: −5 lines.
- Risks before deletion: None.
- Recommendation: **Delete after verification** (Phase 2).

**`Lineup Builder/WhatsNewView.swift:213` — `WhatsNewManager.resetForTesting()`**
- Why unnecessary: 3 lines, zero call sites. Its sibling `markAsSeen()` is used. Settings has a "Reset Onboarding?" flow, but that calls `resetOnboardingFlags()` in `SettingsView.swift:223`, which clears `"lastSeenWhatsNewVersion"` via a hardcoded string literal rather than calling this method.
- Confidence: **High**
- Impact: −5 lines. Small, but worth noting that `SettingsView` duplicating the UserDefaults key as a string literal instead of calling this is the actual defect — the key can drift.
- Risks before deletion: None.
- Recommendation: **Consolidate rather than delete** — have `resetOnboardingFlags()` call `WhatsNewManager.resetForTesting()` so the key lives in one place. (Phase 2.)

**`Lineup Builder/WelcomeView.swift:1026` — `InfoToolbarButton` + `View.infoButton(for:)`**
- Why unnecessary: a `ViewModifier` plus the `View` extension that is its only entry point. `infoButton(for:)` has zero call sites, so `InfoToolbarButton` is unreachable — the extension's `modifier(InfoToolbarButton(page:))` at line 1049 is its sole reference. The pattern it wraps (an info button that presents `PageTipsView`) is instead hand-rolled at each call site: `LineupView.swift:236`, `PlayersView.swift:86`, `GameLogsView.swift:74`, `DefensiveGridView.swift:343`.
- Confidence: **High** — extension methods are the classic false-positive trap, so this was searched globally as a bare name, not as a call expression. Still zero.
- Impact: −28 lines.
- Risks before deletion: None to delete. But note the inversion: this modifier exists to prevent exactly the four-way duplication that shipped anyway.
- Recommendation: **Either adopt it at all four sites or delete it** — leaving both is the worst of the three. (Phase 2/3.)

**`Lineup Builder/DefensiveGridView.swift:2` — `import StoreKit`**
- Why unnecessary: no StoreKit symbol appears in the file. Checked for `requestReview`, `SKStoreReview`, `Product.`, `Transaction.`, `AppStore`, `ProductView`, `SubscriptionStoreView`, `manageSubscriptions`, `offerCodeRedemption` — zero hits. The `purchaseManager` referenced throughout is the app's own `PurchaseManager` type. Contrast `ArchiveGameSheet.swift` and `PDFPreviewView.swift`, which import StoreKit for `@Environment(\.requestReview)` and legitimately need it.
- Confidence: **High**
- Impact: 1 line; marginal compile-time win.
- Risks before deletion: None.
- Recommendation: **Delete now** (Phase 1).

---

### 2. Duplicate Logic

**`Lineup Builder/DefensiveGridView.swift:806–838` vs `Lineup Builder/iPadDashboardView.swift:1038–1070` — `parseAutoFillPromptWithTimeout(prompt:timeout:)`**
- Why unnecessary: byte-identical 33-line functions, verified by `diff` of the extracted ranges. Both build an `AutoFillNLConstraintService` lazily, race a `service.parse(prompt:)` task against an 8-second sleep in a `withTaskGroup`, and return `.empty` on either failure or timeout. Identical down to the comments.
- Confidence: **High** on the duplication (mechanically verified). **Medium** on the right home for it — both copies close over `@State private var nlService` and `store`, so extraction needs either a small `@Observable` helper or a static function taking the service as a parameter.
- Impact: −33 lines, and one place instead of two for the timeout constant and the Apple Intelligence fallback policy.
- Risks before deletion: The 8-second timeout and the "proceed unconstrained rather than block the fill" fallback are the product behavior here. Consolidating must not change either. `AutoFillEngineTests` covers the engine but not this wrapper, so verify manually on both iPhone and iPad by entering a natural-language prompt.
- Recommendation: **Consolidate** into a static helper on `AutoFillNLConstraintService`, taking the service as a parameter. (Phase 3.)

**`Lineup Builder/DefensiveGridView.swift:1297–1345` vs `Lineup Builder/iPadDashboardView.swift:1851–1895` — `playerChip(_:badge:badgeColor:)`**
- Why unnecessary: ~48-line `@ViewBuilder` functions that a `diff` shows differ only in: the inning variable (`selectedInning` vs `clampedInning`), two read-only guards the iPad copy omits (`guard !isReadOnly`, `.disabled(isReadOnly)`), the undo reset (`showingUndo = false`), and — tellingly — cosmetic drift: `HStack(spacing: 6)` vs `7`, `minHeight: 20` vs `18`.
- The cosmetic drift *is* the finding. These were the same view; they've already diverged by hand. The missing `isReadOnly` guard on the iPad copy is worth checking on its own: if it's not enforced by an enclosing view, a read-only shared-team participant can tap bench chips on iPad.
- Confidence: **High** on duplication. **Medium** on the read-only gap being a real bug — `iPadDashboardView` may gate it upstream.
- Impact: −48 lines, and the two platforms stop drifting.
- Risks before deletion: This is real UI on the two most-used screens. Consolidation needs visual verification on both iPhone and iPad, in read-only and editable states, with bench + absent chips.
- Recommendation: **Consolidate** into one `PlayerChip` view taking `inning`, `isReadOnly`, and an `onTap` closure. Fix the read-only gap either way. (Phase 3.)

**Back-to-back bench detection — reimplemented three times against an existing helper**
- `Lineup Builder/DefensiveGridView.swift:1298–1304` (inside `playerChip`)
- `Lineup Builder/iPadDashboardView.swift:1852–1858` (inside `playerChip`)
- `Lineup Builder/PositionSummaryView.swift:338–344` (`isBackToBackBench(player:inning:)`)
- Why unnecessary: all three compute "is the inning before or after this one also a bench assignment" with the same `prev || next` shape. `Lineup.hasConsecutiveBench(player:assigningBenchToInning:)` at `Models.swift:698–702` is *already exactly this logic*, and `Lineup.hasBackToBackBench(player:)` / `playersWithBackToBackBench(from:)` at `Models.swift:708–718` already exist for the game-wide case (and `iPadDashboardView.swift:272` correctly uses the latter).
- Each call site's real predicate is `innings[i].position(for: player) == .bench && hasConsecutiveBench(player:assigningBenchToInning: i)` — the guards differ only in how they establish "this cell is bench" (`badge == "BN"` vs an explicit position check).
- Confidence: **High** — the helper's own doc comment at `Models.swift:704–707` explicitly distinguishes the observational and predictive variants, which is strong evidence the centralization was intended and these three sites were simply missed.
- Impact: ~−15 lines net, but the value is correctness: `FairPlayConfig.noConsecutiveBench` is a per-team toggle, and four independent implementations is four places to remember when the rule becomes further configurable.
- Risks before deletion: Behavior must stay identical at the boundary innings (first and last). `FairPlayValidationTests` covers the `Lineup` helpers; add a case pinning the per-cell variant before refactoring.
- Recommendation: **Consolidate** onto `Lineup.hasConsecutiveBench(player:assigningBenchToInning:)`. (Phase 3.)

---

### 3. Unused UI Components

All four are covered in detail under **Dead Code** above: `PlayerInningRow`, `PitchAvailabilityBadge`, `PitcherStripCard`, `PitcherAvailabilityStrip` (all in `DefensiveGridView.swift`).

Worth noting what this category *didn't* turn up: every other view type in the repo traces to a real instantiation. The 50-odd types that showed only two repo-wide hits were each checked individually — in every case the second hit was a genuine call site, not a `#Preview`. Views defined `private` inside their own file (`FairPlayRailView`, `NeverStripeBar`, `CoverageDot`, `TabTipCard`, and others) are all used within that file. `STLWidgetBundle` shows one hit because it's the `@main` widget entry point.

---

### 4. Overly Complex Implementations

Nothing worth flagging. This was checked deliberately, not skipped.

The three files that look alarming by size — `DefensiveGridView.swift` (2,765), `Models.swift` (2,186), `iPadDashboardView.swift` (2,004) — are large because they hold many small sibling types, not because any single function is convoluted. `AutoFillEngine.swift` is dense but that's inherent to constraint solving, and the comments carry the reasoning. `AutoFillNLConstraintService.swift` does substantial index clamping (`max(0, min(rawStart - 1, inningCount - 1))`), which reads defensively rather than convolutedly given the input is LLM-generated. No manual reimplementations of stdlib behavior, no unnecessary abstraction layers, no deep nesting found.

The real structural issue in these files is duplication across the iPhone/iPad pair, which is reported under category 2 instead.

---

### 5. Legacy Code

**`StackTheLineupTests/StackTheLineupTests.swift` — entire file (123 lines), and the `StackTheLineupTests` target**
- Why unnecessary: this is a superseded first draft of the data-integrity test suite, and it has never compiled.
  1. Line 2 reads `@testable import LineupBuilder // replace with your actual module name` — the placeholder was never replaced. The real module is `Lineup_Builder`, as every file in `Lineup BuilderTests/` correctly uses.
  2. The `StackTheLineupTests` target's `PBXSourcesBuildPhase` (`project.pbxproj:446–452`) has an **empty** `files = ( )` list, and unlike the other three test folders, `StackTheLineupTests` has no `PBXFileSystemSynchronizedRootGroup` entry. The file is in no target at all.
  3. Its content is superseded: `StackTheLineupTests.swift:76` and `DataIntegrityTests.swift:310` carry the same "Legacy position preference values (Primary/Secondary) should map forward" test. `Lineup BuilderTests/DataIntegrityTests.swift` (437 lines) is the living version.
  4. Last touched 2026-04-29, in a commit titled "v2.2.1: extract reusable Lineup helpers…" — i.e. it was left behind during that refactor, not maintained through it.
- Confidence: **High** — three independent confirmations (module name, empty build phase, superseding file).
- Impact: −123 lines, −1 dead target, −1 directory. Removes a file that reads like test coverage but provides none.
- Risks before deletion: Verify `DataIntegrityTests` actually covers each case here before dropping it — spot-check the round-trip and legacy-preference tests. The empty `StackTheLineupTests` target should be deleted in Xcode (not by hand-editing `project.pbxproj`).
- Recommendation: **Delete the file now** (Phase 1); **remove the target via Xcode** as a follow-up (Phase 2).

No other legacy code found. Notably: **zero** `TODO`, `FIXME`, `HACK`, or `XXX` comments in the entire repo, and no `@available(*, deprecated)` annotations. No commented-out code blocks — every `//` line checked is genuine prose. The `v1` and `legacy` mentions that grep surfaces are all in live migration paths (`Models.swift` decode fallbacks, `.stlteam`/`.stlroster` schema docs) that must stay.

---

### 6. Redundant Queries / API Calls

**`Lineup Builder/PlayersView.swift:1175–1176` — double CloudKit push in `commitSave()`**
- Why unnecessary: `store.updateGameInningCount(gameInningCount, for: id)` ends with its own `save()` (`Models.swift:1905`), and `LineupStore.save()` (`Models.swift:1158`) does a full `CloudKitManager.saveTeam` upload of the entire team blob. The explicit `store.save()` on the next line fires a second full upload of the same record.
- The nuance that keeps this from being a one-line delete: `updateGameInningCount` early-returns at `Models.swift:1886` (`guard clamped != teams[idx].gameInningCount`) when the inning count is unchanged. In that case the trailing `save()` is **load-bearing** — it's the only thing persisting the name/color/coachName edits made at lines 1171–1174. So it's redundant only when the count actually changed, which is the less common path.
- The `.add` branch (lines 1167–1168) has the same shape: `addTeam` saves (`Models.swift:2116`), then `updateGameInningCount` may save again.
- Confidence: **High** on the double-upload; **Medium** on the fix shape.
- Impact: One redundant full-team CloudKit round-trip per team edit that changes inning count. Not a hot path, but `save()` is called 42 times in `Models.swift` alone, so the "every mutation is a whole-blob upload" pattern is worth a broader look.
- Risks before deletion: **Do not just delete line 1176** — that silently stops persisting team name/color edits. Restructure so the mutations happen first and exactly one `save()` follows.
- Recommendation: **Fix by restructuring, not deleting** (Phase 2). Have the `.edit` branch mutate `teams[idx]`, call a non-saving `updateGameInningCount` variant, then `save()` once.

No N+1 patterns found. `saveTokenForAllTeams` (`DeviceTokenManager.swift:64`) loops per team, but that's one record per team by design, and it runs once per APNs registration.

---

### 7. Abandoned Files

**`Lineup Builder/Lineup_Builder.entitlements`**
- Why unnecessary: byte-identical (`diff` returns clean) to `Lineup Builder/Lineup Builder.entitlements`, which is the file actually referenced — `CODE_SIGN_ENTITLEMENTS = "Lineup Builder/Lineup Builder.entitlements"` at `project.pbxproj:672` and `:723` (Debug and Release). Zero references to the underscore variant anywhere in the project file. `HANDOFF-data-recovery.md` independently reached the same conclusion while ruling out causes of the July 13 incident.
- Confidence: **High**
- Impact: One file. The value is removing a signing-config decoy — two entitlements files with near-identical names is exactly the kind of thing that gets edited in the wrong place at 11pm before a release.
- Risks before deletion: None. Because the files are identical, even a mistaken reference would resolve to the same entitlements.
- Recommendation: **Delete now** (Phase 1).

**`STLWidget/STLWidget.entitlements`**
- Why unnecessary: byte-identical to `STLWidgetExtension.entitlements` at the repo root, which is the referenced one (`CODE_SIGN_ENTITLEMENTS = STLWidgetExtension.entitlements` at `project.pbxproj:484` and `:517`). `STLWidget/STLWidget.entitlements` has zero references. Same app-group payload (`group.com.nickdavies.LineupBuilder`).
- Confidence: **High**
- Impact: One file. Same decoy-removal rationale.
- Risks before deletion: None.
- Recommendation: **Delete now** (Phase 1).

**`STLWidget/WidgetSnapshot.swift`**
- Why unnecessary: byte-identical to `Lineup Builder/WidgetSnapshot.swift`. Under Xcode 16 synchronized groups, `project.pbxproj:75–89` declares two exception sets for the `STLWidgetExtension` target: one listing `WidgetSnapshot.swift` under the `STLWidget` folder, and one listing `WidgetSnapshot.swift` under the `Lineup Builder` folder. Since the widget's own folder is a member by default, the first exception **excludes** `STLWidget/WidgetSnapshot.swift`; since the app folder is not a member by default, the second **includes** `Lineup Builder/WidgetSnapshot.swift`. Net: the app's copy is what the widget compiles, and the `STLWidget` copy is in no target. The `STLWidget` folder isn't in the app target either.
- Confidence: **Medium** — the reference-counting is solid and the exception-set reading is consistent with `Info.plist` appearing in the same list (it's excluded from sources and handled via `INFOPLIST_FILE = STLWidget/Info.plist`). But Xcode's synchronized-group semantics are thinly documented, and getting this backwards breaks the widget build. Not worth guessing on.
- Impact: −63 lines, and removes a duplicate that will silently diverge from the app's copy.
- Risks before deletion: If the reading is inverted, `STLWidgetExtension` loses its `WidgetSnapshot` type and fails to compile.
- Recommendation: **Verify then delete** (Phase 2). Concretely: in Xcode, select `STLWidget/WidgetSnapshot.swift` and check the Target Membership inspector. If both boxes are unchecked, delete it and build the widget target.

**`roadmap.jsx` (repo root, 26 KB)**
- Why unnecessary: a standalone React kanban board of planned work, committed 2026-04-29 ("Add Roadmap") and untouched since. It's in no target, references no app code, and can't run — there's no `package.json`, no `node_modules`, no JS toolchain anywhere in the repo.
- It's also **stale in a way that matters**: its `INITIAL_CARDS` list items `v221-1` "Centralize back-to-back bench detection" and `v221-3` "Inning count constants" as **"Up Next."** Both are substantially done — `Lineup.hasBackToBackBench` / `playersWithBackToBackBench` exist at `Models.swift:708–718`, and `inningCount` is derived from `store.lineup.innings.count` throughout. So it now describes work as pending that has shipped, while (per finding 2) missing the three sites where the back-to-back centralization *wasn't* finished.
- Confidence: **High** that it's not build-reachable. **Low** on whether to remove it — that's a workflow call, not a code one.
- Impact: 26 KB out of the repo root.
- Risks before deletion: It may be the only written record of the planned v2.4/v3.0 work. Don't delete it without reading it first.
- Recommendation: **Manual review** (Phase 3) — move it to a tracker or a `docs/` folder, or refresh it. A roadmap that lies about what's done is worse than no roadmap.

---

### 8. Tech Debt Opportunities

**8.1 — `DebugDataSeeder` ships in release builds, behind an accidentally-discoverable trigger** *(resolved — see below)*
- `Lineup Builder/DebugDataSeeder.swift` (403 lines) has no `#if DEBUG` guard. Neither did its trigger: `SettingsView.swift:118` attached `.onLongPressGesture(minimumDuration: 1.5)` to the Version row, leading to a confirmation dialog whose "Create Test Team" button calls `DebugDataSeeder.seed(into: store)`.
- **Shipping the seeder is intended.** It produces a roster with no real children's names, which is what App Store screenshots and marketing material are built from. So it must stay in release builds — the fix is the trigger, not the code's presence.
- **The seeder is purely additive**, contrary to what an earlier draft of this report implied. `seed()` calls `store.addTeam` (which appends and switches), populates only that new team, and switches back to the previously active team at `DebugDataSeeder.swift:150–152`. It never deletes or mutates another team.
- **It did not cause the July 13 wipe.** Per `HANDOFF-data-recovery.md`, the dev install never held the real teams — its array was `[TeamA, TeamB, Test Team]`, and that whole array went into the shared KV blob, which the phone then preferred over its own good local data. The seeder supplied the blob's *contents*; the loss mechanism was blob-level replacement from an install lacking the real data. Seeding on a device that already has the real teams was never the dangerous case.
- The real residual risk was **accidental discovery**: press-and-hold on a version string is the standard iOS text-selection gesture, so a coach could reach the dialog without meaning to. Seeding from there is recoverable (delete the team), but the new team syncs to their other devices — a confusing thing to happen unprompted.
- Confidence: **High**
- **Status: FIXED.** `SettingsView.swift` now requires 7 taps on the Version row, with a 2-second inter-tap window so a stray tap while scrolling never accumulates. Verified building.
- The seeded team does still sync to the author's other devices via the KV blob and CloudKit push. Reviewed and accepted — see 8.4.

**8.2 — `NSUbiquitousKeyValueStore` has no dev/prod split, unlike CloudKit** *(largely fixed)*
- Root cause of the July 13 incident per `HANDOFF-data-recovery.md` §1: the KV store is shared across every install of the bundle ID on one Apple ID — debug builds and simulators included — and `applyStoredData()` preferred the KV blob over local `UserDefaults` with no freshness check.
- **Both halves have since been addressed**, in commit `7a38eb7` (2026-07-14):
  - `saveLocalOnly()` wraps the KV write in `#if !DEBUG` (`Models.swift:1216`), so debug builds can no longer publish a blob at all.
  - `applyStoredData()` now routes through `shouldPreferCloudBlob(cloudData:cloudSavedAt:localData:localSavedAt:)` (`Models.swift:1300`), a `savedAt` comparison, so a stale cloud blob cannot win. Debug builds read local data only.
  - Two further defenses landed alongside: an early return when stored data exists but fails to decode (preventing a cascade into `migrateOrCreateDefaultTeam()` overwriting iCloud with an empty team), and a `sync.blob_shrank` analytics signal when an incoming blob carries fewer teams or logs than what's loaded.
- Confidence: **High** — read directly from the current source, not inferred from the handoff doc.
- Recommendation: No further action identified. Once the recovery described in the handoff doc is complete, fold that doc into `docs/` or close it out — a top-level `HANDOFF-*.md` describing an open incident goes stale the moment it's resolved.

**8.4 — The seeded Test Team propagates to the author's own devices** *(accepted — no action)*
- `seed()` appends Test Team to `teams`, which is serialized whole into the KV blob by `saveLocalOnly()` and pushed to CloudKit by `save()`. A team created for screenshots therefore syncs to the author's other devices.
- **Decision: accepted as intended behavior.** The devices in question are the author's own, the seeded roster contains no real player data, and the team is disposable — delete and re-seed. Not worth the fix.
- Recorded because the alternative was considered and rejected, not overlooked: an `isLocalOnly` flag on `Team` honored in `save()` and `saveLocalOnly()` would stop the propagation, but it touches the sync path — the highest-risk code in this repo — to solve a problem the owner doesn't have. If a second person ever seeds on a shared Apple ID, revisit.

**8.3 — UserDefaults keys duplicated as string literals**
- `SettingsView.swift:223` clears `"lastSeenWhatsNewVersion"` with a hardcoded literal while `WhatsNewManager.resetForTesting()` (`WhatsNewView.swift:213`) exists to do exactly that and goes uncalled. Same shape as finding 1's `InfoToolbarButton`: a helper written to prevent duplication, then bypassed.
- Confidence: **High**
- Impact: Small, but it's a silent-failure class — rename the key in one place and the reset quietly stops working, with no compile error.
- Recommendation: Call the helper; move the key to a single `static let` (Phase 2).

---

## Prioritized Cleanup Plan

### Phase 1 — Safe to remove now (High confidence, low risk)

| Item | Location | Lines |
|---|---|---|
| `PitchAvailabilityBadge` + `PitcherStripCard` + `PitcherAvailabilityStrip` | `DefensiveGridView.swift:2551–2739` | −189 |
| Stale section comment ("provides badge + strip card views") | `DefensiveGridView.swift:2502` | edit |
| `PlayerInningRow` + its MARK header | `DefensiveGridView.swift:1870–2003` | −134 |
| Unused `import StoreKit` | `DefensiveGridView.swift:2` | −1 |
| Superseded, never-compiled test file | `StackTheLineupTests/StackTheLineupTests.swift` | −123 |
| Unreferenced duplicate entitlements | `Lineup Builder/Lineup_Builder.entitlements` | file |
| Unreferenced duplicate entitlements | `STLWidget/STLWidget.entitlements` | file |

**Total: ~447 lines, 3 files.** All line-level edits are confined to `DefensiveGridView.swift`, which has no uncommitted working-tree changes.

### Phase 2 — Verify, then remove — ✅ **complete, 6 Aug 2026**

Items 1, 3 (`drawColoredDot`), 4 and 7 were done by the August audit; see `CLEANUP-AUDIT-2026-08.md` findings 7.1 and section 1. The rest are resolved below.

1. ~~`STLWidget/WidgetSnapshot.swift`~~ — **deleted** (2026-08 audit, 7.1). Target membership was proven from Xcode's `SwiftFileList` rather than the inspector.
2. ~~Delete the empty `StackTheLineupTests` **target**~~ — **removed 6 Aug 2026**, from `project.pbxproj` and the shared scheme. Done by hand after all, not in Xcode's editor: the ten objects are all reachable from the target's own UUIDs, and the result is checkable (`plutil -lint`, `xcodebuild -list`, then app + widget + device builds and the full test suite). See 7.2 in the August doc.
3. ~~`PDFGenerator.drawColoredDot`~~ — **deleted** (2026-08 audit). `CloudKitManager.isAccountAvailable()` — **kept by decision**: it and `fetchAllTeams()` are the two halves of a manual iCloud re-sync, and building that affordance touches the July data-wipe path (2026-08 audit, 1.9).
4. ~~`LineupStore.clearBattingOrder()`~~ — **deleted** (2026-08 audit).
5. ~~`WhatsNewManager.resetForTesting()`~~ — **done.** Renamed `reset()` and called from `resetOnboardingFlags()` (2026-08 audit, 1.11); the second literal, in `resetAllData()`, was cleaned up 6 Aug 2026. The key now exists in one place.
6. ~~`PlayersView` `commitSave()`~~ — **fixed 6 Aug 2026.** Restructured via a non-saving `applyGameInningCount` plus `LineupStore.updateTeamDetails(...)`, so one `save()` fires on both the add and edit paths. The "edit team name without changing inning count" path is now a test. See 6.1a in the August doc.
7. ~~`InfoToolbarButton` / `View.infoButton(for:)`~~ — **deleted**; neither symbol exists in the repo any more.

### Phase 3 — Manual review required — ✅ **complete, 6 Aug 2026**

1. ~~**`DebugDataSeeder` release gating (8.1)**~~ — **closed.** Trigger changed to a 7-tap sequence on the Version row. The seeder stays in release builds by design (App Store screenshots and marketing material), and its syncing to the author's own devices is accepted behavior (8.4). Nothing outstanding.
2. ~~**`DeviceTokenManager.refreshTokenForCurrentTeam` and `removeTokens`**~~ — **done** (2026-08 audit, 1.10). Both were missing wire-ups, as suspected; wiring `removeTokens` up also exposed a query that deleted *every* coach's token for the team (1.10a).
3. ~~**`PitchEligibilityEngine` Coaches Guide section**~~ — **shipped** (2026-08 audit, 2.2). It turned out the feature was already live via a hand-ported copy in `PDFGenerator`; the engine's version won and the port is gone.
4. ~~**`playerChip` duplication**~~ — **consolidated 6 Aug 2026** into `PlayerChip.swift`, used by both platforms. The read-only gap was real, and far wider than the chip: `iPadDashboardView` had no read-only enforcement anywhere, so a view-only participant could reassign positions, reorder the batting order, clear positions and finalize the lineup. All gated. See 2.4 / 2.4a in the August doc, and its test plan.
5. ~~**`parseAutoFillPromptWithTimeout` duplication**~~ — **done.** Both copies are gone; the parse, engine call and message composition now live in `AutoFillCoordinator`, shared by the iPhone grid, the iPad pane and `FillLineupIntent`.
6. ~~**Back-to-back bench triplication**~~ — **done 6 Aug 2026.** All three sites route through `Lineup.hasConsecutiveBench`, with the per-cell tests written first as this item asked. See 2.5.
7. ~~**`CloudKitManager.fetchAllTeams`**~~ — **kept by decision** (2026-08 audit, 1.9). It and `isAccountAvailable()` are the two halves of a manual re-sync; building that affordance touches the July data-wipe path and belongs in its own change.
8. ~~**`roadmap.jsx`**~~ — **retired**; the file is no longer in the repo.

---

## Cleanup Script — applied and removed

`cleanup-phase1.sh` and `cleanup-phase1.patch` sat in the repo root from 19 Jul 2026. Phase 1 was applied from them, and all three phases are now complete, so both were deleted on 6 Aug 2026.

They had stopped being merely inert: the script deletes files that no longer exist and applies a patch to `DefensiveGridView.swift` written against a version of that file three passes out of date. Its `git apply --check` guard means running it would fail rather than corrupt anything — but a runnable-looking script that can only fail is a trap for whoever finds it next.

Recoverable from git history if the record is ever wanted.
