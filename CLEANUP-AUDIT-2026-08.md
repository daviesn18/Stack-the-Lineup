# Codebase Cleanup Audit — Stack the Lineup (Lineup Builder)

> **Closed.** The two follow-ups that survive — `PositionSummaryView.pitchingRows()` (2.2a) and the debounced CloudKit push (6.2) — are [`BACKLOG.md`](BACKLOG.md) items 3.1 and 3.2, both deferred by decision. The iPad read-only test plan at the end is backlog item 1.4, and the `stl-worker` deploy in 8.3a is 1.2, a submission blocker.

**Status: all findings actioned — this pass on 1 Aug 2026, the July audit's remaining phases on 6 Aug 2026.** This document is now the record of what was found and what was done about it. The second audit pass; the first is `CLEANUP-AUDIT.md` (19 Jul 2026), whose Phase 2 and Phase 3 lists are also closed out here.

*Addendum, 6 Aug 2026:* the July audit's **Phase 2 and Phase 3** lists are now closed out — see the Follow-ups section. Phase 2 had three items genuinely open: the empty `StackTheLineupTests` target (7.2), the double CloudKit save on every Edit Team submission (6.1a, new), and the last duplicated What's New key literal (1.11). Phase 3 had two: the duplicated bench/absent chip (2.4) and the back-to-back bench triplication (2.5). Consolidating the chip turned up **2.4a — iPad had no read-only enforcement at all**, so a view-only participant in a shared team could edit positions and finalize the lineup. That is the most user-visible thing in this document and the one to verify on a device before shipping.

*Addendum, 2 Aug 2026:* finding 8.3's open question — whether the Cloudflare Worker accepts the four unused event constants — is closed; it does, and they stay. Answering it turned up **8.3a**: the Worker was pinned to the APNs sandbox host, which would have silently killed every shared-team push on the next App Store build. Fixed, along with a stale duplicate of its entry point. Those changes are in `~/Desktop/stl-worker` and **are not live until it is redeployed**.

Verification for every change below: `xcodebuild build` → **BUILD SUCCEEDED**, `Lineup BuilderTests` → **TEST SUCCEEDED**. Fifteen tests were added across the two passes — five for the badge fix, six for the Edit Team save path, four pinning the per-cell bench predicate before it was consolidated. Final run: **295 passed, 0 failed**, on both the iPhone and iPad simulators.

One thing here is **not** verified by that: the iPad read-only fix (2.4a) needs a real shared team on two devices. See the test plan at the end.

## Executive Summary

- **Scope:** 91 Swift files, 33,539 LOC, plus `project.pbxproj`, the shared `.xcscheme`, 2 `.entitlements`, 2 `Info.plist`. Targets: `Lineup Builder`, `STLWidgetExtension`, `Lineup BuilderTests`, `Lineup BuilderUITests`, and — at the time of the audit — a fifth, `StackTheLineupTests`, that compiled nothing; removed 6 Aug 2026 (finding 7.2). Swift/SwiftUI only: no storyboards, no XIBs, no `@IBOutlet`/`@IBAction`. Exactly one selector in the repo (`#selector(iCloudDidUpdate)`, `Models.swift`) and it is live.
- **Method:** target membership was read from Xcode's own `*.SwiftFileList` after a build rather than inferred from the project file — that is what makes finding 7.1 certain, and it corrected a backwards reading of `membershipExceptions`. On top of that: all 333 type declarations, all 726 `func` names and all 1,343 property names reference-counted repo-wide with comment-only matches excluded. That exclusion is what surfaced `clearAll()`, which a naive count missed.

### What changed

| Category | Found | Outcome |
|---|---|---|
| 1. Dead code | 15 | 10 deleted, 5 wired up |
| 2. Duplicate logic | 5 (+1 found during the fix) | 5 consolidated, 1 documented as follow-up |
| 3. Unused UI components | 0 | — |
| 4. Overly complex implementations | 0 | — |
| 5. Legacy code | 0 | — |
| 6. Redundant queries / API calls | 3 | 2 fixed, 1 deferred by decision |
| 7. Abandoned files | 2 | 1 deleted, 1 target removed |
| 8. Tech debt | 5 | 3 fixed, 2 kept — both questions now closed |

Net: **−115 lines of dead code, −1 file, −1 build target, 4 user-facing bugs fixed, 15 new tests.**

Counts include the 6 Aug 2026 pass that closed the July audit's Phase 2 and Phase 3 (findings 2.4, 2.4a, 2.5, 6.1a, and the rewritten 7.2).

### The four that mattered

1. **A view-only coach could edit anything on iPad** (2.4a). `iPadDashboardView` had no read-only enforcement at all, and the picker sheets it presents don't carry their own — iPhone gates their call sites instead. A participant with view-only access to a shared team could reassign positions, reorder the batting order, clear positions and finalize the lineup, which notifies the whole team. Found by consolidating a duplicated chip; the biggest thing in this document, and the only one still unverified on hardware.
2. **The iPhone warnings badge was wrong two ways** (2.1). Both terms of `inningIssues + gameIssues` counted the selected inning's open slots, so one missing shortstop in the inning you were looking at read as 2. And `gameWideIssueCount` summed per-rule counts where every other surface counts distinct players — the same lineup showed a different number on iPhone than iPad. Both fixed; the sheet behind the badge now lists exactly what the badge counts.
3. **Deleting a shared team never stopped its push notifications** (1.10). `removeTokens(for:)` existed, documented for exactly this, and had no caller. Wired into `deleteTeam(id:)` — and see 1.10a, because wiring it up exposed a worse bug inside it.
4. **`STLWidget/WidgetSnapshot.swift` was in no build target** (7.1). Flagged in July, still present, byte-identical to the copy the widget actually compiles. Deleted.

### Left alone deliberately

- **`Models.swift` sync/merge and `TeamStorage.load()`** — the July 2026 data-wipe path. Nothing dead; nothing touched beyond adding a logger.
- **`AutoFillEngine.swift`** — dense, but that's a constraint solver. No dead branches, real coverage.
- **`DebugDataSeeder.swift`** (452 lines, ships in Release) — deliberate: it's the App Store screenshot data source, behind a 7-tap gate.
- **`PitchEligibility.dayPhrase` vs `GameRecap.datePhrase`** — looks duplicated, isn't. One faces backwards only, the other both ways; the doc comment already explains it.
- **`ContentView.consumePendingRoute()` / `iPadDashboardView.consumePendingRoute()`** — five duplicated lines, but this is the cold-launch path that makes Siri and Spotlight work, and the shared part is the trivial half. Noted so a third idiom doesn't become a third copy.

---

## Findings and resolutions

### 1. Dead Code — 10 deleted, 5 wired up

**Deleted** (all verified unreferenced across source, tests, previews and non-code files; build confirms):

| Symbol | File | Lines |
|---|---|---|
| `allWarningCount` | `DefensiveGridView.swift` | 4 |
| `clearBattingOrder()`, `clearAll()` | `Models.swift` | 14 |
| `drawColoredDot(color:x:y:)` | `PDFGenerator.swift` | 6 |
| `benchOnlyPlayers` | `GameLogDetailView.swift` | 5 |
| `shortVerdict` | `PitchEligibility.swift` | 10 |
| `RuleTopic.isPitching` | `TeamRules.swift` | 8 |
| `hasDiagnostics` | `AutoFillNLConstraintService.swift` | 2 |
| `import StoreKit` | `LockedHistoryView.swift` | 1 |

`clearAll()` also had a stale doc reference on `Team.gameInningCount`, corrected in the same change. `drawColoredDot` and `benchOnlyPlayers` were `private`, which makes those two airtight rather than merely well-evidenced.

**1.10 — `DeviceTokenManager.removeTokens(for:)` and `refreshTokenForCurrentTeam(store:)`: wired up, not deleted.**

Both read as dead code. Both said in their own doc comments what should have been calling them:

- `removeTokens(for:)` — "Call when a coach leaves a shared team so they stop receiving its notifications." `deleteTeam(id:)` didn't. The record stayed in the public database and the Worker kept finding it. Now called from `deleteTeam(id:)`, fire-and-forget so a CloudKit failure can't block the local delete.
- `refreshTokenForCurrentTeam(store:)` — "Called when the coach switches teams." `switchTeam` didn't. Tokens were only written by `didRegister` at launch, so a team created or joined mid-session had no token record until the next cold start. Now called from `switchTeam(to:)`.

**1.10a — a worse bug inside `removeTokens(for:)`, found by wiring it up.**

It queried `teamID == %@` and deleted every result. DeviceToken records live in the **public** database, so that query returns *every coach's* token for the team — one person leaving would have silenced notifications for the whole roster. Shipping the caller without fixing this would have been strictly worse than leaving the function dead.

Rewritten to delete by the deterministic record name (`devicetoken-<teamID>-<token prefix>`), which addresses this device's record and only this device's. The name construction is now a single `recordName(teamID:tokenHex:)` shared by the write and delete paths, so they can't drift. No-ops when APNs hasn't delivered a token — without it we can't name our own record, and if it never registered there's nothing to remove.

Also corrected: the file header said these records live in `privateDB`. They're in the public database, which is the entire reason 1.10a was dangerous.

**1.11 — `WhatsNewManager.resetForTesting()`: wired up, renamed `reset()`.**

Settings → "Reset Welcome and Tips" cleared `hasCompletedTutorial` and restarted the tour but left `lastSeenWhatsNewVersion` set, so What's New stayed suppressed with no way to bring it back. Now called from `resetOnboardingFlags()`; the confirmation copy mentions What's New.

*Finished 6 Aug 2026:* the July audit's point (its finding 8.3) was the duplicated key literal, not just the missing call, and `SettingsView.resetAllData()` still cleared `"lastSeenWhatsNewVersion"` by hand. It calls `WhatsNewManager.reset()` now too, so the key exists in exactly one place and renaming it can't silently break a reset path.

**1.12 — Coaches Guide summary: shipped (see 2.2, which is what it turned into).**

**1.9 — `CloudKitManager.fetchAllTeams()` / `isAccountAvailable()`: kept untouched, by decision.**

33 lines, no call sites, clearly the two halves of a manual iCloud re-sync. Building that affordance touches the path that caused the July data wipe and belongs in its own change, not a cleanup pass. `fetchAllTeams` also carries a hard-won comment about `MainActor.run` trailing-closure syntax on iOS 26 that is worth keeping.

### 2. Duplicate Logic — 5 consolidated

**2.1 — The fair-play rule set had three implementations. Now one.**

`Lineup.fairPlayFindings(players:config:)` exists to be the single evaluation, and four surfaces already used it. `DefensiveGridView` never got migrated and held two more copies. Three concrete defects came out of that:

- **`gameWideIssueCount` summed per-rule counts.** A player missing both infield and outfield counted as 2 on iPhone, 1 on iPad — `iPadNavBar.violationCount`'s comment already described this as a fixed bug. Now `fairPlayFindings.implicatedPlayerIDs.count`, matching every other surface.
- **The selected inning was counted twice.** `warningsToolbarLabel` renders `inningIssues + gameIssues`; `currentInningIssueCount` counted the selected inning's open slots and `gameWideIssueCount` looped every inning including that one. `openPositionCount(excludingInning:)` now makes the split explicit.
- **Back-to-back bench counted but never listed.** `gameWideIssueCount` counted it game-wide; `computeOverallWarnings()` omitted it entirely and `computeInningWarnings()` only covered the selected inning. A violation at innings 4–5 while viewing inning 1 contributed to "Game Issues (N)" and appeared nowhere in the sheet. `computeOverallWarnings()` is now built from `FairPlayFindings` and includes it.

The sheet was realigned to match: "Missing Positions" → "Other Innings", excluding the inning that already has its own section, so a single unfilled slot is listed once.

Supporting change in `Models.swift`: `backToBackBenchInnings(player:)` returns the 1-based inning pairs so the warning can say *where*, with `hasBackToBackBench` now built on it. That also fixed a latent trap — the old `0..<innings.count - 1` crashes on an empty innings array, which a truncated blob can produce. Covered by a test.

New tests in `FairPlayValidationTests`: a two-rule player counts once, rules switched off implicate nobody, the bench pairs are named 1-based, alternating bench isn't flagged, and an empty lineup doesn't trap.

**2.2 — The Coaches Guide pitch table had two implementations. Now one — and the "unshipped" feature turned out to be shipped.**

The July audit flagged `PitchEligibilityEngine.coachesGuideSummary` (79 lines) as built-but-never-wired. Wiring it up revealed why it looked orphaned: `PDFGenerator` already had a pitch-count section, built on its own `buildPitchingRows` — self-described as an "exact port of `PositionSummaryView.pitchingRows()`". The feature shipped; the engine's version was the copy that lost.

Rather than adding a second table, `PDFGenerator` now calls `PitchEligibilityEngine.coachesGuideSummary` and the 84-line port is gone. The window arithmetic was verified identical before switching, so the numbers don't move. Two things came with it:

- `PitchingGuideSummaryRow` gained `available` (the lower of daily max and weekly remaining) — the field the PDF needed — and the engine's alphabetical sort was replaced by the PDF's more useful one: unrestricted first, most available first, last name as tiebreak.
- The PDF gained a **Rest** column, the one thing the engine version uniquely computed. Shown only while a player is still inside their rest window; once it elapses the number is noise.

**2.2a — a third copy remains, and I left it.** `PositionSummaryView.pitchingRows()` still hand-rolls the same window maths. It differs in ways that matter: it adds `assignedInnings`, doesn't filter `.never` pitcher preferences itself, and has different rules-disabled behaviour. Folding it in would change a Pro-visible surface that has no test coverage, on the strength of assumptions rather than evidence. That is a change worth making on purpose, not as the tail end of a cleanup pass. **Recommend: consolidate `PositionSummaryView.pitchingRows()` onto `coachesGuideSummary` as its own change, with tests for the Pitching tab first.**

**2.3 — Singular/plural phrasing: one helper.**

`count == 1 ? "inning" : "innings"` and siblings appeared in eight places. New `Plural` enum (`Plural.swift`), promoted from `TeamRulesBuilder`'s private helpers, now used by `GameRecap`, `GameRecapIntent`, `DefensiveGridView`, `PositionSummaryView`, `TemplatePickerView` and `BulkAddPlayersView`. Deliberately not a general pluralization engine — every phrase is written out, because a naive `+ "s"` is how you get "1 catchs". Output is byte-identical, which is what let the existing `GameRecapTests` and `TeamRulesTests` assertions stand unchanged as the regression check.

**2.4 — The bench/absent chip had two implementations, and the iPad one had lost its read-only guards. Fixed (6 Aug 2026).**

The July audit's Phase 3 item 4. `DefensiveGridView.playerChip` and `iPadDashboardView.playerChip` were the same ~48-line `@ViewBuilder` in two files, and they had already drifted by hand — `HStack(spacing: 6)` vs `7`, badge `minHeight: 20` vs `18`. The drift was the finding; what it was hiding was worse (see 2.4a).

Now one `PlayerChip` (`PlayerChip.swift`), taking the player, the inning, `isReadOnly` and an `onTap` closure — the closure is what the two panes actually needed to differ on, since each tracks its own sheet state and the iPhone also dismisses its undo bar. Two incidental cleanups came with it: the stringly-typed `badge: String` compared against `"BN"`/`"ABS"` at four points became a `Kind` enum that owns its label and colour, and the back-to-back-bench check is now `Lineup.hasConsecutiveBench` (see 2.5). Cosmetics unify on the iPhone values, so **iPad chips change very slightly**: 1pt tighter badge spacing, 2pt taller badge.

**2.4a — iPad had no read-only enforcement at all. Fixed (6 Aug 2026).**

The July note guessed the missing `isReadOnly` guard on the iPad chip "may be gated upstream." It wasn't, and the gap was much wider than the chip: `iPadDashboardView.swift` contained **zero** references to `isReadOnly`. The picker sheets don't help — `PositionPickerView` and `PlayerPickerView` have no read-only handling of their own, because iPhone gates every one of their call sites instead.

So a coach with view-only access to a shared team could, on iPad: reassign any position (field slots, by-position matrix, bench/absent chips, add-chips), run Auto-Fill, assign pitchers, reorder the batting order, add players, clear all positions, and **finalize the lineup** — which pushes a notification to the whole team. Every one of those is blocked on iPhone.

Gated to match iPhone, per surface:

- `iPadPositionsPane` — new `isReadOnly`; guards plus `.disabled` on matrix cells, bench-well chips, field slots and pitching rows; Auto-Fill and the two add-chips hidden, as the iPhone hides its bolt button.
- `SidebarRosterView` — the Add Player / Bulk Add menu hidden; `.onMove` takes a nil handler, which is what actually removes the drag affordance (`.disabled` on a List row doesn't).
- `DetailPaneView` — "Clear positions" hidden, a `ReadOnlyBanner` above the positions tab, and `isReadOnly` passed to `LineupStatusStrip`, which already knew how to render a "View only" badge in place of Finalize/Reopen and was simply never told.

**Not verified on a device.** The suite passes and both simulators build, but nothing here exercises a real shared-team participant — see the test plan at the end of this document.

**2.5 — Back-to-back bench: three hand-rolled copies, now one helper.**

The July audit's Phase 3 item 6. `Lineup.hasConsecutiveBench(player:assigningBenchToInning:)` already existed and three sites re-derived it as `prev || next`: both `playerChip` copies (now the shared `PlayerChip`) and `PositionSummaryView.isBackToBackBench`, which keeps only its local "this cell is bench" guard.

Pinned before the refactor, as the July note asked: four new `FairPlayValidationTests` cases covering the previous inning, the next inning, the boundary innings, and — the semantic that let the copies drift in the first place — that the predicate deliberately ignores the inning it's asked about.

`AutoFillEngine.benchedLastInning` looks like a fourth copy and isn't: it is backward-only on purpose, because the engine fills innings in order and the next one doesn't exist yet. Left alone.

### 3. Unused UI Components

Checked and clean. All 333 declared types have a real reference; the only single-reference types are `@main` entry points, test classes, and `STLShortcuts` (an `AppShortcutsProvider`, discovered by the system). The July audit's four orphaned views are confirmed gone.

### 4. Overly Complex Implementations

Nothing worth reporting. The dense files are dense because their problems are. The dictionary force-unwraps in `PitchingRulesView.swift` look alarming in a grep but each is immediately preceded by its own `!= nil` guard.

### 5. Legacy Code

Nothing worth reporting. Every `legacy`-marked path is deliberate and documented: grandfathered Pro purchasers, onboarding flag migration, `Codable` fallbacks for shipped blobs. No `_old`/`_v1` files, no commented-out blocks, and **zero TODO/FIXME/HACK comments in 33,539 lines.**

### 6. Redundant Queries / API Calls

**6.1 — QuickSetSheet fired one full persist and one CloudKit push per inning. Fixed.**

Four loops called a per-inning store mutator, each ending in `save()` — which encodes the entire `[Team]` array, writes UserDefaults, writes and `synchronize()`s the iCloud KV store, rewrites the widget snapshot, runs the Spotlight signature check and fires a CloudKit request. A six-inning Quick Set did all of that six times.

`LineupStore` gained `assignPosition(player:innings:position:)` and `removeAssignments(player:innings:)`, modelled on the existing `addPlayers(_:)` (whose doc already said "Bulk-add players in a single save… to avoid triggering an iCloud KV write per player"). The single-inning versions now forward to them, so there's one implementation. Out-of-range innings are skipped rather than trapping — callers derive them from UI state that can lag a game-length change.

The position-clearing path needed care: different innings can hold different occupants at the same position, so it groups by player and issues one save per distinct occupant rather than one per inning.

**6.1a — Edit Team fired two full saves per submission. Fixed (6 Aug 2026).**

Carried over from the July audit's Phase 2 (item 6) and not addressed by the August pass. `PlayersView.commitSave()` mutated `store.teams[idx]` by hand, called `updateGameInningCount` — which ends in `save()` — and then called `save()` again. Two whole-blob CloudKit uploads for one tap of Save. The `.add` branch had the same shape: `addTeam` saves, then `updateGameInningCount` may save again.

Not a line to delete: `updateGameInningCount` early-returns when the count is unchanged, so on that path — the common one — the trailing `save()` is the only thing persisting the name, colour and coach-name edits. Deleting it would have silently stopped Edit Team from saving a rename.

Split the resize half of `updateGameInningCount` into a non-saving `applyGameInningCount(_:at:)` that reports whether it changed anything, so `updateGameInningCount` still saves exactly when it always did. On top of it:

- `updateTeamDetails(id:name:color:coachName:gameInningCount:)` — the whole Edit Team submission in one save. Always saves, because the other three fields have no equivalent early return.
- `addTeam` gained an optional `gameInningCount:`, so creating a team with a non-default game length is also one save. Omitted, it behaves exactly as before (`DebugDataSeeder` is unchanged).

Six new tests in `LineupStoreTests`, including the one the July note called for by name: **editing the team name without changing the inning count still persists the name.**

**6.2 — Debounced CloudKit push: deferred, by decision.**

70 `save()` call sites, no debounce anywhere. Every position drag is a CloudKit round-trip. 6.1 removes the worst burst on its own. A real debounce needs a trailing-edge flush on `scenePhase` and opens a window where a crash loses the last write — on the sync path that caused the July incident. Worth doing deliberately, later.

### 7. Abandoned Files

**7.1 — `STLWidget/WidgetSnapshot.swift`: deleted.**

Proven, not inferred: Xcode's file lists for all four building targets name 90 of the repo's 91 `.swift` files, and never this one. The widget compiles `Lineup Builder/WidgetSnapshot.swift` instead, pulled in by a membership exception; the copy next to `STLWidget.swift` is excluded. Byte-identical (`md5 d8f273e4…`). Build confirms the widget still resolves the type.

**7.2 — `StackTheLineupTests` target: removed (6 Aug 2026).**

Declared in `project.pbxproj` with no `fileSystemSynchronizedGroups` and no source directory — it produced no `SwiftFileList` at all. It was still in `xcodebuild -list` and still carried a `TestableReference` in the shared scheme (`skipped = "YES"`, so it wasn't actually being run — the original note overstated that part).

Removed from `project.pbxproj` and the scheme rather than left for Xcode's UI. Ten objects, all reachable from the target's own UUIDs: the `PBXNativeTarget`, its three empty build phases, its `PBXTargetDependency` and `PBXContainerItemProxy`, the `.xctest` `PBXFileReference` and its entry in the Products group, both `XCBuildConfiguration`s and their `XCConfigurationList`, plus the `TargetAttributes` entry and the `targets` list line. −116 lines, and the diff touches nothing outside that set.

The reason this was safe to do by hand and the July note said not to: the removal is verifiable rather than inspectable. `plutil -lint` parses the file, `xcodebuild -list` now shows four targets, and the app (simulator *and* `generic/platform=iOS`), the widget scheme, and the full `Lineup BuilderTests` suite all build and pass afterwards.

The `STLWidget` exception set the July note expected to go with it doesn't reference this target — it belongs to `STLWidgetExtension`. It does still list `WidgetSnapshot.swift`, which 7.1 deleted, so that one entry is now inert; left alone, since it costs nothing and editing membership exceptions by hand is the part of `project.pbxproj` that actually bites.

### 8. Tech Debt

**8.1 — `DateFormatter` on hot paths: fixed.** `GameLogRow.dateString` built a fresh formatter on every body evaluation of every row in the History list; `GameLogDetailView` and `DefensiveGridView`'s rest-date warning did the same. All three are now `private static let`.

**8.2 — `duplicatePositionErrors` recomputed per field slot: fixed.** `fieldSlot(_:)` called it once per slot (9–11 per render), each time re-scanning the inning's assignments for the same answer. Computed once for the diamond and passed down as a `Set`.

**8.3 — `NotificationManager` event constants: kept. Question now closed (2 Aug 2026).** Four of five are unused in Swift, and the open question was whether the Cloudflare Worker actually accepts them. It does. The Worker is at `~/Desktop/stl-worker`; `buildPayload` in `src/index.ts` has a case for all five — `lineup_finalized`, `game_archived`, `archive_prompt`, `team_invite`, `tip` — each with its own title and body copy. So these aren't dead constants, they're the client half of a contract the server already honours. Deleting the four would have been wrong. Only `Models.swift:1726` sends one today (`eventLineupFinalized`); the rest are the Worker's declared surface.

**8.3a — Two things found in the Worker while answering 8.3. Both fixed (2 Aug 2026).** Outside this repo, but they came out of this audit and one would have shipped broken.

- **`src/index.ts` was pinned to the APNs sandbox host.** `const apnsHost = "api.sandbox.push.apple.com"`, with `CLOUDKIT_ENV = "development"` in `wrangler.toml` alongside it. TestFlight and App Store builds are issued *production* device tokens, and sandbox rejects those with `BadDeviceToken` — no error surfaces in the app, the notification simply never arrives. Every shared-team push would have silently stopped working at submission. Both flipped to production, and the comment above the host now names the pairing in both directions so switching back for a debug build is one edit and its partner.
- **The root `index.ts` was a stale duplicate of `src/index.ts`.** `wrangler.toml` sets `main = "src/index.ts"` and `tsconfig.json` includes only `src/**/*.ts`, so nothing referenced the root copy — but it had diverged in the two places that matter most: it still carried the production APNs host, and its CloudKit request signature was `date:subpath:bodyHash` where the deployed file uses `date:bodyHash:subpath`. The deployed ordering is the one Apple's server-to-server spec specifies; the stale copy was wrong. A dead file that reads like a working reference is the worst kind, so it is retired to `index.ts.superseded-2026-08-02` — renamed rather than deleted, because `stl-worker` is not under version control. `npx tsc --noEmit` is clean afterwards.

  **Neither change is live until someone runs `npm run deploy` in `stl-worker`.** Editing the file does not redeploy the Worker. And `CLOUDKIT_ENV = "production"` points the token lookup at the production CloudKit database, so the `DeviceToken` record type has to have been promoted to Production in the CloudKit Dashboard — if it hasn't, the query 400s and no push goes out. Worth confirming in the dashboard before deploying.

**8.4 — `ScheduledGame.lastSyncedAt`: kept.** Written on every iCal import, read nowhere. Removing it changes the persisted shape for no gain. "Last synced 2h ago" on the schedule screen is the feature it was plainly added for.

**8.5 — 23 `print()` calls in Release: fixed.** New `Log` enum (`Log.swift`) with four `os.Logger` categories — `sync`, `storage`, `push`, `spotlight`. `print()` writes to stdout unconditionally with no level, no filtering and no redaction; `DeviceTokenManager` was printing the first 16 hex characters of the APNs device token on every launch, which now logs nothing but the fact of registration. Framework error descriptions are marked `.public` explicitly where they're worth reading in a Release log; everything derived from user content keeps the default redaction.

---

## Follow-ups

Two things are open, each by a deliberate decision rather than an oversight:

1. **`PositionSummaryView.pitchingRows()`** — the third copy of the pitch-window maths (2.2a). Its own change, with tests first.
2. **Debounced CloudKit push** (6.2) — needs a `scenePhase` trailing flush, and it touches the sync path behind the July incident. A deliberate design pass, not a cleanup.

**Closed 6 Aug 2026 — the July audit's Phase 3, finished.** Six of its eight items were already resolved (`DebugDataSeeder` gating, the `DeviceTokenManager` wire-ups, the Coaches Guide section, the `parseAutoFillPromptWithTimeout` duplication — now `AutoFillCoordinator` — `fetchAllTeams` kept by decision, and `roadmap.jsx`, which is gone from the repo). The two open ones are done: the bench/absent chip is one `PlayerChip` (2.4) and back-to-back bench detection runs through one helper (2.5). Consolidating the chip surfaced 2.4a, the iPad read-only gap, which is fixed but **needs the device test plan below run before submission**. Verification: app builds on iPhone and iPad simulators; `Lineup BuilderTests` → **295 passed, 0 failed**, with four new pinning tests.

**Closed 6 Aug 2026 — the July audit's Phase 2, finished.** Working back through `CLEANUP-AUDIT.md`'s Phase 2 list, four of its seven items had already been resolved by this audit (the duplicate `WidgetSnapshot.swift`, `drawColoredDot`, `clearBattingOrder`, `InfoToolbarButton`) and one was kept by decision (`isAccountAvailable`, 1.9). The remaining three are now done: the `StackTheLineupTests` target is removed (7.2), Edit Team saves once instead of twice (6.1a), and the last hand-written `lastSeenWhatsNewVersion` literal is gone (1.11). Verification: `xcodebuild -list` shows four targets; app, widget and `generic/platform=iOS` builds succeed; `Lineup BuilderTests` → **TEST SUCCEEDED** with six new tests.

**Closed since:** the Worker's event vocabulary (8.3) — answered on 2 Aug 2026 by reading `stl-worker`; all five constants stay. That read also turned up 8.3a, two Worker fixes, one of them a shipping blocker.

**Not done by this audit, and needed before the next submission:** `npm run deploy` in `stl-worker`, after confirming the `DeviceToken` record type exists in **Production** CloudKit. See 8.3a.

Worth a manual look before shipping: the warnings badge on the iPhone Positions tab. The numbers it shows will change for some lineups — that's the fix, but it's user-visible. `Settings → 7 taps on Version → Seed Sample History` gives you a team to check it against.

---

## Test plan: iPad read-only (2.4a)

Nothing in the automated suite exercises a shared-team participant, so this needs two devices and a real share. Everything below is expected to be **blocked** on iPad, and already is on iPhone.

**Setup.** On device A, share a team. On device B (an iPad), accept as a **view-only** participant, then open Positions.

1. **Banner and strip** — a read-only banner sits above the status strip, and the strip shows "View only" where Finalize/Reopen would be. Neither Finalize nor Reopen is reachable.
2. **By Inning** — tapping a field slot does nothing; no picker sheet appears. Bench and absent chips don't respond. "+ Bench" and "+ Absent" are absent. Auto-Fill is absent.
3. **By Position** — tapping any matrix cell does nothing, including the benched-player chips in the gray wells.
4. **Pitching** — tapping a row does not open the pitching assignment sheet.
5. **Sidebar** — no "+" add-players menu; batting-order rows cannot be dragged.
6. **Clear positions** — the button is absent below the pane.
7. **Regression, same iPad, editable team** — switch to a team you own and confirm every one of the above works normally. This is the check that matters most; the gating is per-team, not per-device.
8. **Chip cosmetics** — bench/absent chips on iPad are now 1pt tighter and their badge 2pt taller. Compare against iPhone; they should look like the same component, because now they are.
