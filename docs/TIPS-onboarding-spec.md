# Contextual Tips — Rethink

**Goal:** a first-run coach gets a guided, page-by-page walkthrough that covers adding players, building the lineup, setting positions, and exporting — and that names both Free and Pro features along the way.

**Decisions:** TipKit popovers (not a custom spotlight overlay). iPhone and iPad authored together.

---

## Status

**Built, run, and fixed. Arc 1 verified on iPhone.**

| | |
|---|---|
| Build | ✅ `BUILD SUCCEEDED`, iOS Simulator, Debug |
| Tests | ✅ 28 passed, 0 failed |
| Visual verification | 🟡 **Both platforms fully walked.** iPhone: arc 1, arc 2, skip path, Pro history. iPad: arc 1 (Players + Lineup + Positions), skip-path re-entry, and Pro history. Ten bugs fixed total — five found on iPad (arc-1 tips firing over the welcome cover; skip-path `TourInSettingsTip` never presenting on the gear; the History pane having no navigation container, which made archived-game detail unreachable; `ReuseSaveTemplateTip` not advancing; **"Take the Tour" in Settings never actually replaying the tour**). One item still open: the **live in-place advance** of `ReuseSaveTemplateTip` is unverified on device — see the iPad Pro-history section |
| Layer 3 (checklist relocation) | ⛔️ dropped — checklist removed instead (see below) |

### Verification pass — 2026-07-23 (iPhone 17 Pro, iOS 26)

Walked the first-run flow. Confirmed working: welcome trimmed to 2 cards; the Players arc fires in order (Start with your roster → Already have it in a file? → Set up your team) properly anchored; "Take the Tour" is in Settings; copy reads cleanly at default Dynamic Type; the Lineup arc advances (Set the game → Build the order) properly anchored.

**Two bugs found and fixed during the pass:**

1. **Tour was invisible on first launch.** Every Lineup/Positions tip is gated on `hasPlayers == true`, but the app opened on the Lineup tab (`selectedTab = 1` default) where only those tips live — so a fresh coach saw *nothing* until they wandered to Players. **Fix:** `ContentView.onAppear` now sends first-run coaches (`!arcOneSuppressed && players.isEmpty`) to the Players tab.

2. **A Lineup tip misfired on the Players tab.** TipKit's `.immediate` frequency presents an eligible tip the instant its rules pass, even when the anchor lives in a sibling tab that's instantiated but off-screen. Adding the roster on the Players tab flipped `hasPlayers` and popped `LineupGameInfoTip` ("Set the game") mispositioned, clipped at the top edge, over Players. **Fix:** each tab's tour anchors are gated on the tab being selected via the existing `.tourTip(enabled:)` param — a new `isTourTabActive` (Players/Lineup/History) / `tourEnabled && selectedTab == 2` (Positions), threaded from `iPhoneTabView`. A `tourEnabled` flag also holds every tip while the welcome/what's-new cover is up (Fix 1 makes Players "visible" under the welcome cover, and a popover would otherwise render on top of it).

Both re-verified in the simulator: first-run now lands on Players with the first tip showing; adding a roster no longer misfires on Players; "Set the game" fires correctly anchored once the coach reaches the Lineup tab.

> **Gotcha for future anchors:** any new `.tourTip()` on a tab-body view (Players/Lineup/Positions/History) must be gated on that tab being active, or it will present mispositioned over whatever tab is showing when its rules pass. Anchors inside modal sheets (PlayerFormView, team edit) are naturally gated by presentation and need no `enabled:`. This is separate from — and stacks with — the iPad `horizontalSizeClass != .regular` guard.

### ✅ Positions tips bug — FIXED & VERIFIED (2026-07-24)

**Resolved.** Both toolbar-anchored tips were re-anchored to on-screen content in `DefensiveGridView.swift`:
- `PositionsViewModeTip` → the portrait inning-selector strip (`ScrollView(.horizontal)` ~line 251).
- `PositionsWarningsTip` → the portrait `LineupStatusStrip` / "Finalize lineup →" (~line 216).

Verified on a clean install (iPhone 17 Pro, iOS 26): all four Positions tips now present in order — **Two ways to look at it** (inning strip) → **Assign anyone** (diamond) → **Fill it in one tap** with the PRO badge rendering (bolt button) → **Check before you go** (finalize strip). The Warnings tip correctly waits for `hasPositions == true` (fired only after a position was assigned) and closes arc 1 cleanly with no misfires. The historical root-cause writeup below is kept for reference.

---

**Original symptom:** the entire Positions arc (all 4 tips) never presented. On the Positions tab, no popover ever appeared.

**Root cause (confirmed by experiment):** `popoverTip` does not present when anchored on a **navigation-bar `ToolbarItem`** (iOS 26). Two of the four Positions tips are toolbar-anchored:

| Tip | Anchor (`DefensiveGridView.swift`) | Content or toolbar? | Presents? |
|---|---|---|---|
| `PositionsViewModeTip` | By Inning/Summary toggle, `ToolbarItem(.navigationBarLeading)` ~line 311 | **toolbar** | ❌ |
| `PositionsAssignTip` | `diamondField` ~line 1172 | content | ✅ |
| `PositionsAutoFillTip` (PRO) | `boltButton` ~line 994 (used at lines 155 & 220) | content | ✅ (assumed; blocked in testing) |
| `PositionsWarningsTip` | warnings button, `ToolbarItem(.navigationBarTrailing)` ~line 321 | **toolbar** | ❌ |

Because `Tour.positions` is a `TipGroup(.ordered)` and `PositionsViewModeTip` is **first**, its non-presentation blocks every tip behind it — so nothing shows. (Ordered groups stall on a tip that can't present: it stays `currentTip` forever because the coach can't tap Next on an invisible popover.)

**How it was confirmed:** (1) force-enabling the Positions anchors (`enabled: true`) changed nothing → not the tab-gating. (2) Reordering the group to lead with `PositionsAssignTip` (content) made "Assign anyone" appear; tapping Next then stalled at `PositionsViewModeTip` (toolbar) → both facts point at the toolbar anchor. **Pre-existing bug, not caused by the tab-gating work.** Diagnostic changes have been reverted; the repo is at a clean baseline (bug still present).

**Chosen fix (user decision): re-anchor both toolbar tips to on-screen content**, keeping all 4 tips. Plan:
- `PositionsWarningsTip` → the **"Finalize lineup →"** control. Note: it lives inside `LineupStatusStrip` (defined ~line 1490, used at ~lines 103/143/208 across summary/portrait/landscape branches), so anchoring means either threading a tip into that strip or wrapping its call sites — pick the single portrait call site (~208) to avoid triple-anchoring, or gate by layout.
- `PositionsViewModeTip` → the **inning selector strip** (the horizontal `Inn 1 / Inn 2 …` scroll row, portrait layout ~lines 227–248). It's a clean single-instance content view near the top. Copy still reads fine ("Two ways to look at it — By Inning… / Summary…").
- Keep group order `[ViewMode, Assign, AutoFill, Warnings]` once both are content-anchored (all will present), OR lead with `PositionsAssignTip` if that reads better.
- After implementing: clean-install walk (uninstall first — see testing note) and confirm all 4 fire in order.

**Testing gotcha discovered:** `Tips.resetDatastore()` at runtime (Settings → "Take the Tour") + `simctl terminate`/`launch` did **not** reliably flush — tips stayed suppressed. A full **`simctl uninstall` + `install`** is the reliable way to get a pristine datastore for testing. Reinstall-*over* keeps the stale TipKit datastore.

**Also re-verified this session (clean install, current build):** welcome → Players (Fix 1); Players arc in order; full Lineup arc — Set the game → Build the order → Someone out today? → Hand it out — all present and correctly anchored; "Take the Tour" reset alert copy is accurate.

### What shipped

| File | Change |
|---|---|
| `ContextualTips.swift` | **New.** 19 tips, `TourState` parameters, `TipGroup` ordering, `.tourTip()` modifier, migration |
| `LineupBuilderApp.swift` | `TipsConfigurator.configure()` in `init()` |
| `ContentView.swift` | Five grandfathering blocks → `syncTourState()`; first-run lands on Players (Fix 1); `tourEnabled` + per-tab `isTourTabActive` threaded to the tab views (Fix 2) |
| `WelcomeView.swift` | 3 cards → 2; deleted both old tip components and `infoButton(for:)` |
| `PlayersView.swift`, `LineupView.swift`, `DefensiveGridView.swift`, `GameLogsView.swift`, `GameLogDetailView.swift`, `iPadDashboardView.swift` | Anchors; tab-body anchors gated on `isTourTabActive` / `selectedTab == 2` (Fix 2) |
| `SettingsView.swift` | "Take the Tour" row; reset now wipes the TipKit datastore |

32 anchors, 19 tips. Net **−324 / +116 lines** — the tour is smaller than what it replaced.

### Remaining work

- ~~**FIRST: fix the Positions arc**~~ ✅ **Done & verified (2026-07-24)** — both toolbar tips re-anchored to content; all 4 fire in order on a clean install. See "Positions tips bug" above.
- **Finish the visual pass.** iPhone: arc 1, arc 2, skip path, and the Pro history group all covered; PRO badge confirmed live. **iPad walked 2026-07-25** (iPad Pro 11" M5, iOS 26) — full arc 1 (Players/Lineup/Positions) and the skip-path re-entry tip verified; two iPad bugs found and fixed (see the iPad section below). iPhone re-smoke-tested after the shared-`tourTip` change — welcome → first tip still fires, no regression. **Pro history on iPad walked 2026-07-26** — all three tips verified, and the assumption that it was low-risk turned out to be wrong: the iPad History pane had no navigation container at all, so archived-game detail was unreachable and two of the three tips could never have been seen. Both that and a second `currentTip` advance bug are fixed (see the iPad Pro-history section). The visual pass is now complete on both platforms; one follow-up remains open there (the unverified live advance of `ReuseSaveTemplateTip`). The "Take the Tour" reset, which turned out to have never worked, is fixed and verified. The first-render timing issue on the lead history tip was fixed and re-verified 2026-07-25 (see the note under Arc 2 · History).
- ~~**Layer 3** — relocate the checklist to a toolbar progress ring.~~ **Dropped.** The "Getting Started" checklist (`FirstGameChecklist`) was redundant with the contextual tips, so it was removed outright rather than relocated (2026-07-23). Deleted: the render in `LineupView`, the `FirstGameChecklist` + `ChecklistRow` structs and preview in `WelcomeView`, the unused `hasCompletedChecklist` `@AppStorage` in `LineupView`, and the checklist mentions in `SettingsView`'s reset. `hasCompletedChecklist` stays in `TipsConfigurator.legacyKeys` for existing-user migration detection only.
- One open design question (below): the History paywall auto-opening on tab entry. (~~arc 2 giving free coaches too few tips~~ — resolved 2026-07-24: it was actually giving them *zero*; fixed by Pro-gating `ReuseSaveTemplateTip` so the free `secondGame` group no longer stalls behind a paywalled anchor.)

---

## Why the old system didn't get there

Five mechanisms, none connected:

| Mechanism | Where | Gate |
|---|---|---|
| `WelcomeCardsView` | Full-screen, first launch | `hasCompletedTutorial` |
| `FirstGameChecklist` | Lineup tab card | `hasCompletedChecklist` |
| `AutoFillContextTip` | Positions tab card | `hasSeenAutoFillTip`, **Pro only** |
| `PDFExportContextTip` | Lineup tab card | 3+ batting order, **Free only** |
| `AppPage.tips` → `PageTipsView` | Info button, 3 tabs | user-initiated |

1. **Nothing was anchored.** Every tip was a card in a `Form` or a sheet of 7–9 bullets. Nothing pointed at the bolt, the `+`, the team name.
2. **No sequence.** The checklist named four steps but never moved the coach between tabs.
3. **Players and History got nothing proactive** — only an info button.
4. **iPad had zero onboarding.** No tip, checklist, or info button of any kind.
5. **Free/Pro was inverted.** Auto-Fill's tip required `isPro`, so free coaches only met Auto-Fill at the paywall. The PDF tip required `!isPro`, so paying coaches got no tour of what they bought.
6. **State didn't scale.** Six loose `UserDefaults` booleans plus five hardcoded grandfathering blocks in `ContentView`.

---

## Structure

**Layer 1 — Welcome.** ✅ Two cards, ending in `Start the tour` / `Skip`.

**Layer 2 — The tour.** ✅ TipKit popovers anchored to real controls, ordered per page by `TipGroup`. 19 tips.

**Layer 3 — Progress.** ⛔️ **Dropped.** The `FirstGameChecklist` "Getting Started" card was redundant with the contextual tips and has been removed (2026-07-23). No progress card ships; the tips carry the walkthrough.

**Layer 4 — Reference.** ✅ `AppPage.tips` untouched, still pull-help behind the info button.

### Free vs Pro

**Principle: the tour's job is to get the coach to game 1. The paywall's job is to sell. They stay separate.**

1. **One copy per tip.** Instructional copy doubles as the value prop — "Auto-Fill covers one inning or the whole game, fair play rules included" teaches a Pro coach and sells a free one in the same words. No forked content to maintain.
2. **The badge is the only fork.** `PRO` renders when `!isPro`. Pro coaches see the identical tip with no badge; labeling something PRO to a coach who already owns it reads as noise.
3. **No tour tip opens the paywall.** Actions are `Next` / `Got it`. The gated controls already fire `ProGate` with the correct source when tapped. Making tips a second funnel turns onboarding into a sales sequence — and this app gets used twenty minutes before first pitch, the worst possible moment to interrupt with an upsell.
4. **No Pro tip is load-bearing.** A free coach can finish game 1 end to end on free features: batting order, manual position assignment, fair play warnings, Batting Order PDF.

The Export tip teaches the split in one breath: Batting Order PDF is free, Coaches Guide is Pro.

---

## The tour — two arcs

**Arc 1 → first game** (12 tips, first launch). **Arc 2 → second game** (6 tips, on first archive). Plus one re-entry tip = 19.

Nothing about the season, stats, or history appears in arc 1. A coach who hasn't played a game yet has no use for it, and it's the longest stretch of Pro-only surface in the app.

### Arc 1 · Players — 4 tips

| # | Type | Copy | Anchor | Tier |
|---|---|---|---|---|
| 1 | `PlayersAddTip` | Add players one at a time, or use Bulk Add to type the whole roster in one pass. | `addPlayersCard`; iPad sidebar `+` menu | FREE |
| 2 | `PlayersImportTip` | Import Roster pulls names, numbers, and position preferences from a GameChanger CSV. | same | FREE |
| 3 | `PlayersTeamSetupTip` | Tap your team name for color, game length, and your league's fair play rules. Name and color print on every PDF. | `TeamCardView`; iPad team switcher | FREE |
| 4 | `PlayersPreferencesTip` | Strength, Capable, Emergency, Never. Auto-Fill works down that list — Never is never assigned. | Preferences section in `PlayerFormView` | PRO |

### Arc 1 · Lineup — 4 tips

| # | Type | Copy | Anchor | Tier |
|---|---|---|---|---|
| 1 | `LineupGameInfoTip` | Tap to set date and opponent, or pull one straight from your imported schedule. | `GameSummaryCard` | FREE |
| 2 | `LineupBattingOrderTip` | Tap + to add a player. Tap Edit, then drag the handle to reorder. | Batting Order header; iPad sidebar header | FREE |
| 3 | `LineupAbsentTip` | The toggle marks a player out for the whole game and pulls them from every inning. | same | FREE |
| 4 | `LineupExportTip` | Batting Order PDF is free. Coaches Guide adds the full inning-by-inning grid for the dugout. | `ExportBar` | FREE + PRO |

> Lineup templates were originally arc 1's fourth Lineup tip. **Cut during build** — you can't reuse a lineup you haven't built yet, and it collided with arc 2's first two tips, which teach the same feature at the moment it becomes useful.

### Arc 1 · Positions — 4 tips

| # | Type | Copy | Anchor | Tier |
|---|---|---|---|---|
| 1 | `PositionsViewModeTip` | By Inning walks one inning at a time. Summary shows the whole game in one grid. | Inning-selector strip (iPhone); iPad mode picker | FREE |
| 2 | `PositionsAssignTip` | Tap any player or open slot to set their position for that inning. | `diamondField`; iPad mode picker | FREE |
| 3 | `PositionsAutoFillTip` | Auto-Fill covers one inning or the whole game, fair play rules included. | `boltButton`; iPad `autoFillButton` | PRO |
| 4 | `PositionsWarningsTip` | The warnings icon lists everything open, doubled up, or against your rules. Then finalize. | "Finalize lineup →" status strip (iPhone); iPad `FairPlayStatusPill` | FREE |

**Arc 1 ends here**, on Finalize. The coach has a complete game.

### Arc 2 — Second game

Fires on first archive. One idea: *you don't have to build this from scratch again.* The route forks by tier, but every coach gets guidance — arc 2 is split across two `TipGroup`s so a Pro-only anchor can never stall a free coach's path.

**On-ramp:** the existing archive nudge bridges arc 1 → arc 2. `ContentView.checkArchiveNudge()` fires a "Game Played?" alert with an **Archive Now** button once a game is finalized; archiving flips `hasArchivedGame`, which retires arc 1 and makes arc 2 eligible. **This nudge fires for every coach, free or Pro** — so a free coach is still prompted to archive their first game (which also lands them on the History paywall, a soft on-ramp to Pro). Removing the Getting Started checklist changed nothing here — the nudge was always the real prompt.

**`Tour.secondGame` — the free-reachable path (ordered), fires for everyone:**

| # | Type | Copy | Anchor | Badge |
|---|---|---|---|---|
| 1 | `ReuseApplyTemplateTip` | Pick your template when you set the next game — batting order and locked positions come back with it. | `GameSummaryCard` (Lineup) | — |
| 2 | `AutoFillConstraintsTip` | "Jack pitches 3 and 4, keep Maya off catcher." It works around your instructions and says so if it can't. | `boltButton` (Positions) | PRO |
| 3 | `ShareTeamTip` | Invite another coach to build positions with you. You still finalize. | Share Team button (team-edit sheet, ordered last) | PRO |

**`Tour.history` — Pro-only (ordered), behind `LockedHistoryView`:**

| # | Type | Copy | Anchor | Rule |
|---|---|---|---|---|
| 1 | `HistorySeasonViewsTip` | Players for season stats, Team for roster coverage, Games for the archive. Insights appear after two games. | History segmented picker (list) | `isPro` |
| 2 | `HistoryCopyGameTip` | Open any archived game and copy its lineup into today's. It lands on the Lineup tab ready to adjust. | "Copy to current game" row (game detail) | `isPro` |
| 3 | `ReuseSaveTemplateTip` | Save this game as a template and rebuild it next week in one tap. | "Save as template" row (game detail) | `isPro` |

Order follows a Pro coach's navigation: the list-anchored `HistorySeasonViewsTip` leads (seen on the History list), then opening a game reveals the two detail-anchored tips in on-screen row order (Copy above Save). Reordered 2026-07-24 — the group previously led with a detail-anchored tip, which would stall it on the list where that anchor isn't on screen. **Verified on-device (2026-07-25, iPhone 17 Pro, iOS 26):** all three fire in order — Your season is building (History picker) → Or start from a game you played (Copy row) → Don't build that twice (Save row) — each with no PRO badge (correct for a Pro coach), and the ordered group advances cleanly through all three. Pro state was faked with a temporary `FORCE_PRO` `#if DEBUG` env hook in `PurchaseManager.checkEntitlement()` (reverted after the walk): `simctl install` bypasses the scheme's `.storekit` config, so an in-sim purchase falls through to a real Apple Account sign-in. Test data came from the Settings debug seeder ("Test Team", 5 archived games).

> **First-render timing (fixed 2026-07-25).** `HistorySeasonViewsTip` leads the group and gates on `TourState.isPro`, which resolves *asynchronously* after the StoreKit entitlement check. TipKit re-evaluates the ordered group a beat after the `@Parameter` flips, so the synchronous `Tour.history.currentTip` getter could still read `nil` when `GameLogsView` rendered — dropping the lead tip until an unrelated re-render (confirmed via a diagnostic print: `currentTip` was `nil` on the sync where `isPro` first became true, then correctly `HistorySeasonViewsTip` on the next sync; and reproduced on-device — the tip did not appear on the first History landing pre-fix). **Fix:** `GameLogsView` no longer reads the synchronous getter for its picker anchor. It mirrors the group's current tip into `@State` from `TipGroup.currentTipUpdates` (an `AsyncSequence` TipKit exposes for exactly this), seeded once with `currentTip`, so the anchor updates the instant the group resolves. `TipGroup` is `Observation.Observable`, but relying on a body read of the static group's `currentTip` was the fragile part; the async-sequence mirror is deterministic. **Re-verified on-device (2026-07-25):** on a fresh Pro install (FORCE_PRO + FORCE_SEED test hooks) the season-views tip now presents on the *first* History landing with no nudge, dismisses cleanly, and the group still advances to the game-detail tips. See tipkit-currenttip-async.

**Why `ReuseSaveTemplateTip` is Pro-gated (fixed 2026-07-24).** It's anchored on the "Save as template" row inside `GameLogDetailView`, which for a free coach sits **entirely behind `LockedHistoryView`'s paywall** — an unreachable anchor. As the *first* tip of the old `secondGame` ordered group it stalled every tip behind it, so a free coach got **zero** arc-2 tips (verified on-device: nothing fired on Lineup after archiving). Same failure mode as the toolbar-anchor bug. Fix (user decision): give it an `isPro` rule and move it into the Pro `history` group next to `HistoryCopyGameTip` (both live in the game-detail view). Its copy dropped "Your first one's free," which only applied to free coaches. A free coach's own save-template path remains the free Positions "Save as Template" banner (`saveAsTemplateBanner`, free while they have no templates) — just not tour-highlighted. **Verified on-device (2026-07-24, free account):** after archiving, `secondGame` now fires in order — Game two in one tap → Tell Auto-Fill what you want (PRO) → Bring in an assistant (PRO) — with no stall.

### Re-entry

- **Settings → Help & Support → "Take the Tour."** Wipes the TipKit datastore so every tip is eligible again.
- **`TourInSettingsTip`** fires once (`MaxDisplayCount(1)`) for a coach who tapped Skip on the welcome cards (skipping only sets `welcomeSkipped` / `hasCompletedTutorial` — **the contextual tour still runs**). The copy names Settings so the coach knows where the tour lives.
  - **Anchor (fixed 2026-07-24).** It originally anchored on the **Settings gear**, but on iPhone that gear is a nav-bar `ToolbarItem`, where `popoverTip` never presents — so the hint was invisible for every iPhone skipper (verified on-device before the fix). On **iPad** the gear is a content button in the custom header (`iPadDashboardView`), so that anchor works and was left as-is. On **iPhone** it now anchors on the **Players team card** (`PlayersView`, `TeamCardView`) just below the gear; the copy still points at Settings. User picked the team card over restructuring the iPhone header into a custom pinned bar (which would have been a disproportionate main-screen redesign, and risked Settings scrolling out of view).
  - **Sequencing.** It shares the team-card anchor with the arc-1 `PlayersTeamSetupTip` and, being a standalone tip, would otherwise fire *alongside* an arc-1 popover. It's gated `enabled: … && Tour.players.currentTip == nil`, so it only appears once the whole Players arc is exhausted. **Verified on-device (2026-07-24):** after Skip, the Players arc runs in order, then `TourInSettingsTip` presents on the team card with no collision and dismisses cleanly.

---

## Implementation notes

**Rules.** `TourState` holds `@Parameter` mirrors of `hasPlayers`, `hasBattingOrder`, `hasPositions`, `hasArchivedGame`, `isPro`, `welcomeSkipped`. `ContentView.syncTourState()` keeps them current, driven by a single `onChange(of: tourSignature)`.

> Four separate `onChange` modifiers on that body pushed it past the Swift type-checker's limit (`unable to type-check this expression in reasonable time`). They're collapsed into one string signature. **Don't split them back out.**

**Sequencing.** One `TipGroup(.ordered)` per page, independent across pages. Page-scoped rather than one arc-wide group on purpose: a tip whose anchor lives inside a sheet the coach never opens can't stall tips on other tabs. Sheet-anchored tips are ordered last within their page.

**Arc gating.** Arc 2's tips carry a `hasArchivedGame == true` rule; arc 1's carry `== false`, so arc 1 self-retires the moment a coach archives a game. A coach who archived without finishing the tour has already learned it by doing.

**Migration.** `TipsConfigurator.migrateLegacyFlagsIfNeeded()` runs once, keyed on `didMigrateToTipKit`. If any old onboarding flag was set, it sets `didSkipArcOne`, and `suppressArcOne()` invalidates all 12 arc-1 tips. This replaces the five grandfathering blocks that were in `ContentView.onAppear`.

**Reset caveat.** TipKit has **no per-tip un-invalidate**. `Tips.resetDatastore()` is the only route, and it only takes effect on next launch, because `Tips.configure` has to run against the cleared store. Do not re-call `configure()` inside `restartTour()` — it's a no-op once the app is configured, and it makes the confirmation alert lie. Both reset paths tell the coach to reopen the app.

**iPad.** Tip definitions are platform-free; only anchors differ. Two wrinkles found during build:

- The dashboard **embeds `PlayersView` and `LineupView`** in its detail pane (`iPadDashboardView.swift:1198`, `:1201`), so their anchors already carry over. `LineupGameInfoTip` and `LineupExportTip` needed no iPad work at all.
- But the **sidebar is always on screen**, so five tips would have fired on two anchors at once whenever the matching detail tab was selected. `.tourTip(_:arrowEdge:enabled:)` takes an `enabled` flag; the embedded views pass `horizontalSizeClass != .regular` so the dashboard's own anchors win on iPad. **Any new anchor added to a view the dashboard embeds needs the same treatment.**

**iPad walk — 2026-07-25 (iPad Pro 11" M5, iOS 26).** Full arc 1 verified with no double-firing: Players (Add/Import on the sidebar `+`, Set-up-team on the "My Team" nav dropdown) → Lineup (Set-the-game and Hand-it-out on the detail pane; Build-the-order and Someone-out on the sidebar) → Positions (view-mode/assign/Auto-Fill **PRO** on the detail pane; Check-before-you-go on the Fair-Play rail). The `horizontalSizeClass != .regular` stand-down works — every sidebar/detail pair fired exactly one tip. Two bugs found and fixed:

- **Arc-1 tips fired over the welcome cards.** The iPhone path holds the tour off the welcome/what's-new covers via `tourEnabled` folded into `isTourTabActive`, but `iPadDashboardView` was created without any such flag and its `.tourTip` anchors defaulted to `enabled: true` — so `PlayersAddTip` popped on the sidebar `+` while the welcome cards were still up (and, being dismissed there, was consumed before the coach ever finished onboarding). **Fix:** a cross-platform `tourActive` **EnvironmentValue** (default `true`), set once on the root `Group` in `ContentView` as `!showingWelcome && !showingWhatsNew`, ANDed inside the `tourTip` modifier with the per-anchor `enabled:`. One gate now covers both platforms; `tourTip` became a `ViewModifier` to read the environment. iPhone re-smoke-tested — no regression.
- **Skip-path `TourInSettingsTip` never presented on the iPad gear.** On iPad it anchors on the header's content gear (`iPadDashboardView.swift:235`) — correct anchor — but it had **no** `enabled:` gate, unlike the iPhone team-card version which is gated on `Tour.players.currentTip == nil`. Without that gate it was eligible the instant `welcomeSkipped` flipped, competed with the still-running arc-1 Players tips, and its single `MaxDisplayCount(1)` was consumed before it could show. **Fix:** gate the iPad anchor on `Tour.players.currentTip == nil` too. Re-verified: after the skip-path Players arc exhausts, "Changed your mind? Take the Tour lives in Settings" now presents on the gear and dismisses cleanly.

Note on **skip behavior** (same on both platforms, confirmed on iPad): tapping **Skip** dismisses the welcome cards but still runs the contextual tips — the arc-1 Players tips play, then `TourInSettingsTip` presents as the re-entry hint. "Skip" skips the intro cards, not the tour.

**iPad Pro-history walk — 2026-07-26 (iPad Pro 11" M5, iOS 26, `FORCE_PRO` build + seeded Test Team).** All three Pro history tips verified present on iPad, none rendering a PRO badge: `HistorySeasonViewsTip` ("Your season is building") on the History segmented picker, on the **first** landing; `HistoryCopyGameTip` ("Or start from a game you played") and `ReuseSaveTemplateTip` ("Don't build that twice") on the two Reuse-this-game rows in `GameLogDetailView`. That closes the visual pass on both platforms. Two more bugs surfaced:

- **✅ FIXED — the iPad History pane had no navigation container, so archived-game detail was unreachable.** `GameLogsView.body` dropped its `NavigationStack` when `horizontalSizeClass == .regular`, on the assumption that a host provides one — but `iPadDashboardView` embeds the pane bare and has no `NavigationStack`/`NavigationSplitView` anywhere in the chain. Consequence on iPad: the "History" title never rendered, the info-button toolbar never rendered, and the `NavigationLink` into `GameLogDetailView` was inert, so **tapping an archived game did nothing** — which also made the last two Pro tips unreachable. **Fix:** wrap unconditionally, matching `PlayersView`, which already wraps in the same detail pane. Verified: title, info button, and game-detail push all work on iPad. Note this was a *product* bug, not just a tour bug — it predates the tour work.
- **✅ FIXED — `ReuseSaveTemplateTip` never advanced after `HistoryCopyGameTip` was dismissed.** Same async-`currentTip` root cause as the lead history tip: `GameLogDetailView` read `Tour.history.currentTip` synchronously in its body, so when the coach tapped Next on tip 2 nothing re-rendered the view and tip 3 never got a chance to present (confirmed on device — scrolling both rows into view did not bring it up). **Fix:** the same `currentTipUpdates` → `@State` mirror used in `GameLogsView`, seeded once from `.currentTip`. Verified via the seed path (tip 3 presents on entering the detail view when it is the pending tip); the live in-place advance was not re-verified on device — see the caveat below.

**✅ FIXED — "Take the Tour" (Settings) did not replay the tips** (2026-07-26). Surfaced while trying to re-run this walk. `TipsConfigurator.restartTour()` called `try? Tips.resetDatastore()` inline and told the coach to reopen the app; doing exactly that replayed **nothing** — not the history tips, not already-consumed arc-1 tips — while a clean reinstall of the same build replayed arc 1 immediately, isolating it to the reset rather than to tip eligibility.

The first theory was that `resetDatastore()` throws once `Tips.configure()` has run and the `try?` swallowed it. **That was measured and proved wrong** — a probe build showed the post-configure call returning cleanly. The actual cause: the reset *does* clear the store, but TipKit is still configured and live in that session and writes its in-memory tip statuses back over the cleared store, so the wipe is undone before the app ever terminates.

**Fix:** make it two-phase. `restartTour()` now only records intent (`tourPendingDatastoreReset` in `UserDefaults`); `TipsConfigurator.configure()` consumes the flag and performs the reset at launch **before** `Tips.configure()`, when no live instance exists to undo it. The flag is cleared regardless of outcome so a stubborn datastore can't wedge the app into resetting every launch, and failures now emit `tour.reset.failed` analytics instead of vanishing under a `try?` — the silence is what made the original bug invisible for so long.

Verified on iPad in both directions: consume `PlayersAddTip` → Take the Tour → relaunch → **`PlayersAddTip` is back at the head of the arc**; then advance the arc and relaunch again → it stays advanced, confirming the reset is one-shot and not a per-launch loop. Note the welcome cards do *not* re-show — matching the alert copy, which promises tips, not the intro cards.

⚠️ **Not verified / still open, as of 2026-07-26:**

- **The live in-place advance of `ReuseSaveTemplateTip`** (dismiss tip 2 → tip 3 appears without leaving `GameLogDetailView`). Blocked on re-seeding a fresh install: the debug seeder needs the Settings **Version** row tapped 7× within 2s of each tap, and simulator-automation round-trips are ~8s, so the counter never accumulates. The fix is the identical pattern already verified working on the lead history tip on both iPhone and iPad, but it has not been observed end-to-end here. **Worth a manual pass from Xcode.** (Now easier: "Take the Tour" actually works, so a reset + re-walk no longer needs a wipe-and-reseed.)

### Deleted

- `AutoFillContextTip`, `PDFExportContextTip` — replaced by `PositionsAutoFillTip` and `LineupExportTip`.
- `InfoToolbarButton` / `infoButton(for:)` — dead before this work started.
- Four of six `UserDefaults` keys; five grandfathering blocks; the third welcome card.

---

## Testing steps

Steps 1–2 (welcome, Players arc, first two Lineup tips) were walked on iPhone on 2026-07-23; the rest are unrun. The xcode-select blocker is resolved (`/var/db/xcode_select_link` is now persisted).

### 1. Arc 1, clean install — the main path

Delete the app from the simulator first; the TipKit datastore survives a reinstall-over otherwise.

1. Launch → **2 welcome cards**, second CTA reads "Start the tour." ✅ walked
2. Complete the welcome → land on **Players** (Fix 1) with `PlayersAddTip` on the Add players card. Tap **Next**. ✅ walked
3. `PlayersImportTip` replaces it on the same anchor → Next → `PlayersTeamSetupTip` on the team card. ✅ walked
4. Add a player. Open their edit sheet → `PlayersPreferencesTip` on the preferences section (**PRO badge** — first pro tip to eyeball).
5. **Lineup tab** → `LineupGameInfoTip` on the game card ✅ walked → Next → `LineupBattingOrderTip` on the Batting Order header ✅ walked.
6. Add someone to the order → `LineupAbsentTip` → Next → `LineupExportTip` on the export bar.
7. **Positions tab** → view mode → assign → bolt (`PositionsAutoFillTip`, **PRO badge**) → warnings, in that order.

**Watch for:** a tip that fires on two anchors at once; a tip firing mispositioned on the *wrong* tab (the Fix 2 regression to guard against); a tip that never appears because its rule never flips; ordering that jumps.

**Note on bulk add:** pasting a roster via Bulk Add also seeds the batting order, so `hasBattingOrder` flips without a manual step. Add players one at a time if you want to test the batting-order tips against an empty order.

### 2. Rules gate correctly

- With **zero players**, tips 4–12 must not fire. Only the three Players tips are eligible.
- `PositionsWarningsTip` requires at least one assignment — it should stay hidden on an empty grid.

### 3. Free vs Pro badge

The app runs against **real StoreKit products** (not a local `.storekit` file), so this needs a sandbox account.

- **Free:** `PlayersPreferencesTip`, `PositionsAutoFillTip`, and all four Pro arc-2 tips show an orange `PRO` after the title.
- **Pro:** identical copy, **no badge**.
- **Neither** should open the paywall. Tapping the underlying control still should.

### 4. Arc 2

Fastest path: **Settings → tap the Version row 7×** → "Create Test Team" seeds 5 archived games. Switch to Test Team.

- `hasArchivedGame` flips → all 12 arc-1 tips go silent, arc 2 becomes eligible.
- Free: only `ReuseSaveTemplateTip` and `ReuseApplyTemplateTip` fire. Confirm the two History tips never appear and the coach hits no dead end.
- Pro: all six, with the two History tips inside `GameLogDetailView` and the History picker.

### 5. Skip path

Fresh install → tap **Skip** on the welcome cards → `TourInSettingsTip` should fire **on the gear icon**, once only. The rest of the tour still runs.

### 6. Migration — existing coach

The regression that matters most.

1. Install the **previous** build, complete the welcome cards, add a player.
2. Install this build over it.
3. **No arc-1 tip should ever appear.** If one does, `migrateLegacyFlagsIfNeeded()` didn't catch that flag.

### 7. Reset paths

- **Settings → Take the Tour** → alert says reopen the app → relaunch → arc 1 runs again.
- **Settings → long-press Build row (1.5s)** → Reset Onboarding → welcome cards return after relaunch.

### 8. iPad

Run on an iPad simulator. Every tip should appear **exactly once** — the duplicate-anchor guard is the specific thing under test.

- Sidebar `+` menu, team switcher, batting order header, mode picker, Auto-Fill button, fair play pill.
- Select the **Players** detail tab with the sidebar visible: `PlayersAddTip` must fire on the sidebar only, not both.
- Same check on the **Lineup** detail tab for `LineupBattingOrderTip`.

---

## Open questions

- **The History paywall auto-opens.** `GameLogsView.swift:66` presents `ProGate` unprompted 0.35s after a free coach opens the tab, whether or not they did anything. Arc 2 routes around it, but routing around a behavior isn't the same as deciding it's right.
- **Arc 2 gives free coaches 2 tips of 6.** They get a real path to game 2, but four are structurally invisible. If the season story matters for conversion, the alternative is one free-tier tip pointing at what archiving builds toward — at the cost of principle 3 above.
- **Tip copy has never been read on a device.** Popover width is narrower than the tables here suggest; some messages may want trimming once seen at real size, especially at large Dynamic Type.
