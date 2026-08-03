# Codebase Cleanup Audit — open items

Original audit run 2026-07-19 against 64 Swift files / ~27,262 LOC. Phase 1 is
done and its findings have been dropped from this doc — what follows is only
what is still outstanding, with line numbers re-verified 2026-08-03.

**Method, for anyone picking this up:** every top-level type (205), every `func`
name (369), and every framework import was reference-counted across all four
targets plus non-code files. The project uses Xcode 16 filesystem-synchronized
groups, so target membership is folder-based — that's what surfaced the
orphaned-file findings. Swift/SwiftUI only: no storyboards, no XIBs, no
`@IBOutlet`/`@IBAction`, no `#selector`, so the usual iOS false-positive traps
don't apply.

---

## Closed since the audit

- **All of Phase 1** — the four dead `DefensiveGridView` views (`PlayerInningRow`,
  `PitchAvailabilityBadge`, `PitcherStripCard`, `PitcherAvailabilityStrip`, −323),
  the unused `import StoreKit`, `StackTheLineupTests/StackTheLineupTests.swift`,
  and both duplicate entitlements files.
- **`InfoToolbarButton` / `View.infoButton(for:)`** — deleted during the TipKit
  tour work. See `TIPS-onboarding-spec.md`.
- **`roadmap.jsx`** — removed from the repo root.
- **`DebugDataSeeder` release gating (8.1)** — trigger changed to 7 taps on the
  Version row with a 2-second inter-tap window. The seeder stays in release
  builds by design (App Store screenshots, no real children's names), and its
  syncing to the author's own devices is accepted (8.4).
- **KV store dev/prod split (8.2)** — `saveLocalOnly()` wraps the KV write in
  `#if !DEBUG`, and `applyStoredData()` now picks by `stl_teams_saved_at`
  timestamp instead of always preferring the cloud blob.

---

## Phase 2 — verify, then remove

**1. `STLWidget/WidgetSnapshot.swift` — byte-identical duplicate (−63)**

Still identical to `Lineup Builder/WidgetSnapshot.swift` (verified with `diff`).
Under Xcode 16 synchronized groups, `project.pbxproj:75–89` declares two
exception sets for `STLWidgetExtension`: one lists `WidgetSnapshot.swift` under
`STLWidget`, one lists it under `Lineup Builder`. Since the widget's own folder
is a member by default the first **excludes** the `STLWidget` copy; since the app
folder is not a member by default the second **includes** the app copy. Net: the
app's copy is what the widget compiles.

Confidence: **Medium** — the reference-counting is solid, but Xcode's
synchronized-group semantics are thinly documented and getting this backwards
breaks the widget build. Verify in Xcode: select the file, check Target
Membership. If both boxes are unchecked, delete it and build `STLWidgetExtension`.

**2. The empty `StackTheLineupTests` target**

Still in `project.pbxproj` (target at :303, product ref at :71, listed at :373,
build configs at :884/:907) with an empty `files = ( )` sources phase. The source
file is already gone. Delete the target via Xcode's project editor — **never** by
hand-editing `project.pbxproj`.

**3. `CloudKitManager.isAccountAvailable()` — `CloudKitManager.swift:104` (−5)**

Zero call sites. Delete and build.

**4. `PDFGenerator.drawColoredDot(color:x:y:)` — `PDFGenerator.swift:499` (−5)**

`private` static helper, zero call sites in its own file — which, being private,
is the whole search space. As certain as this gets in Swift. Siblings `drawText`
and `drawFooter` are both live. Delete.

**5. `LineupStore.clearBattingOrder()` — `Models.swift:1807` (−5)**

Zero call sites. It's a public method on the central store, so confirm no test
exercises it (`grep` across `Lineup BuilderTests` returns nothing), then delete.

**6. `WhatsNewManager.resetForTesting()` — duplicated key literal (finding 8.3)**

`SettingsView.swift:261` clears `"lastSeenWhatsNewVersion"` with a hardcoded
literal, while `WhatsNewManager.resetForTesting()` (`WhatsNewView.swift:213`)
exists to do exactly that and goes uncalled. `WhatsNewView.swift:196` already
holds the key as `private static let lastSeenKey`.

The duplication is the actual defect, not the uncalled method: rename the key in
one place and the reset quietly stops working, with no compile error.
**Consolidate** — have `resetOnboardingFlags()` call the helper.

**7. `PlayersView.commitSave()` — double CloudKit push (`PlayersView.swift:1155`)**

`store.updateGameInningCount(gameInningCount, for: id)` ends with its own
`save()`, and `LineupStore.save()` does a full `CloudKitManager.saveTeam` upload
of the entire team blob. The explicit `store.save()` on the next line fires a
second full upload of the same record. The `.add` branch has the same shape.

**Do not just delete the trailing `save()`.** `updateGameInningCount` early-returns
(`guard clamped != teams[idx].gameInningCount`) when the count is unchanged — in
that case the trailing `save()` is load-bearing, and is the only thing persisting
the name/color/coachName edits made just above it. Restructure so the mutations
happen first and exactly one `save()` follows.

Test the "edit team name without changing inning count" path — the naive delete
breaks it.

---

## Phase 3 — manual review required

**1. `DeviceTokenManager.refreshTokenForCurrentTeam(store:)` — `DeviceTokenManager.swift:52`, and `removeTokens(for:)` — `:108`**

Almost certainly missing wire-ups rather than dead code. Test the join/leave
shared-team notification paths before deciding.

**2. `PitchEligibilityEngine` Coaches Guide section — `PitchEligibilityEngine.swift:301–376` (−79)**

`PitchingGuideSummaryRow` (`:301`) appears only within `coachesGuideSummary`
(`:315`); `coachesGuideSummary` has zero call sites. Its doc comment says it
"Builds rows for the Coaches Guide pitching summary table," and no such table
exists — `PDFGenerator.swift` has no reference to it, and neither does any view.

Confidence is **High** on it being unreferenced, but the *decision* is a product
one: this reads as built-but-unshipped rather than abandoned, and it's the
non-trivial half of a PDF section someone may still intend to ship. **Ship it or
cut it.**

**3. `playerChip(_:badge:badgeColor:)` duplication — `DefensiveGridView.swift:1359` vs `iPadDashboardView.swift:1868` (−48)**

~48-line `@ViewBuilder` functions that differ only in: the inning variable
(`selectedInning` vs `clampedInning`), two read-only guards the iPad copy omits
(`guard !isReadOnly`, `.disabled(isReadOnly)`), the undo reset
(`showingUndo = false`), and cosmetic drift — `HStack(spacing: 6)` vs `7`,
`minHeight: 20` vs `18`.

The cosmetic drift *is* the finding: these were the same view and have already
diverged by hand. Consolidate into one `PlayerChip` taking `inning`, `isReadOnly`,
and an `onTap` closure.

Separately: **the missing `isReadOnly` guard on the iPad copy may be a real bug.**
If it isn't enforced by an enclosing view, a read-only shared-team participant can
tap bench chips on iPad. Check that on its own merits.

This is real UI on the two most-used screens — verify visually on both platforms,
in read-only and editable states, with bench + absent chips.

**4. `parseAutoFillPromptWithTimeout(prompt:timeout:)` duplication — `DefensiveGridView.swift:785` vs `iPadDashboardView.swift:1055` (−33)**

Byte-identical functions. Both build an `AutoFillNLConstraintService` lazily, race
`service.parse(prompt:)` against an 8-second sleep in a `withTaskGroup`, and
return `.empty` on either failure or timeout. Identical down to the comments.
Call sites at `DefensiveGridView.swift:666` and `iPadDashboardView.swift:973`.

Both copies close over `@State private var nlService` and `store`, so extraction
needs either a small `@Observable` helper or a static function taking the service
as a parameter — the latter is the smaller change. Extract onto
`AutoFillNLConstraintService`.

The 8-second timeout and the "proceed unconstrained rather than block the fill"
fallback are product behavior; consolidating must not change either.
`AutoFillEngineTests` covers the engine but not this wrapper, so verify manually
on both iPhone and iPad with a natural-language prompt.

**5. Back-to-back bench detection — reimplemented against an existing helper**

- `DefensiveGridView.swift` — inside `playerChip` (`:1359`)
- `iPadDashboardView.swift` — inside `playerChip` (`:1868`)
- `PositionSummaryView.swift:344` — `isBackToBackBench(player:inning:)`

All compute "is the inning before or after this one also a bench assignment" with
the same `prev || next` shape. `Lineup.hasConsecutiveBench(player:assigningBenchToInning:)`
at `Models.swift:723` is already exactly this logic, and its doc comment at `:731`
explicitly distinguishes the observational and predictive variants — strong
evidence the centralization was intended and these sites were simply missed.
`DefensiveGridView.swift:2174` and `:2234` already call the helper correctly.

Each site's real predicate is `innings[i].position(for: player) == .bench &&
hasConsecutiveBench(player:assigningBenchToInning: i)`; the guards differ only in
how they establish "this cell is bench" (`badge == "BN"` vs an explicit position
check).

Net saving is small (~−15) but the value is correctness: `FairPlayConfig.noConsecutiveBench`
is a per-team toggle, and four implementations is four places to remember when the
rule becomes further configurable. Behavior must stay identical at the boundary
innings. `FairPlayValidationTests` covers the `Lineup` helpers — add a case
pinning the per-cell variant before refactoring.

**6. `CloudKitManager.fetchAllTeams()` — `CloudKitManager.swift:241`**

Sync hardening has since landed. Wire it to a "Force full re-sync" affordance or
delete it.

---

## Deliberately left alone

- **`Models.swift` sync/merge logic** — CloudKit migration, KV-store precedence,
  last-writer-wins merge. Source of the July 2026 production incident, now
  hardened, covered by `LineupStoreTests` and `DataIntegrityTests`. Nothing here
  is dead; it's the last code in the repo that a cleanup pass should touch.
- **`AutoFillEngine.swift`** — dense, but the density is inherent to a constraint
  solver, and it has real coverage in `AutoFillEngineTests`. No dead branches.
- **Overly complex implementations** — checked deliberately, nothing found. The
  large files are large because they hold many small sibling types, not because
  any single function is convoluted. The real structural issue is the
  iPhone/iPad duplication above.
- **`Analytics.swift` signal names** — reference-counted as strings, but whether
  a signal is still consumed in the TelemetryDeck dashboard is outside the repo.

Also worth recording: **zero** `TODO`, `FIXME`, `HACK`, or `XXX` comments in the
repo, no `@available(*, deprecated)`, and no commented-out code blocks. The `v1`
and `legacy` mentions grep surfaces are all live migration paths (`Models.swift`
decode fallbacks, `.stlteam`/`.stlroster` schema docs) that must stay.
