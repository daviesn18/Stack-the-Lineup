# Backlog — Stack the Lineup

**Written 6 Aug 2026.** One place for everything open across the five working documents in this repo, in the order I'd do it. Each item says where it's written down, what "done" looks like, and what it's blocked on — so nothing here needs you to re-read a 60 KB handoff to know what it is.

**The spine is the 3.3 submission.** Version is `3.3 (34)` and `WhatsNewContent` has its 3.3 entry, so the release is real and close. Stages 1 and 2 are what stands between here and the App Store. Everything after that is work you chose to defer, and it should stay deferred until 3.3 is out.

**Nothing here is half-finished code.** The scattered feeling is documentation debt, not code debt: five docs written at different times, three of which describe a state the code left behind. The code is in better shape than the paperwork.

---

## The order

| # | Item | Size | Blocked on |
|---|---|---|---|
| **Stage 0 — restore the record (do first, it's an hour)** ||||
| 0.1 | Close out or finish `HANDOFF-data-recovery.md` | S | You — only you know if the recovery happened |
| 0.2 | Merge this branch to `main` | S | — |
| **Stage 1 — blocks the 3.3 submission** ||||
| 1.1 | Widget bundle version mismatch | XS | — |
| 1.2 | Deploy `stl-worker` + confirm Production CloudKit | S | Cloudflare + CloudKit dashboard |
| 1.3 | Siri phrases on a physical device | M | TestFlight build, or an exception to the debug-build rule |
| 1.4 | iPad read-only on two devices | M | A real shared team |
| **Stage 2 — small, and cheap while you're already testing** ||||
| 2.1 | `LineupView` still titled "Lineup Builder" | XS | Product-name decision (1.5) |
| 2.2 | Decide whether to keep the `PRODUCT_NAME` rename | S | You |
| 2.3 | `ReuseSaveTemplateTip` live advance | S | A manual Xcode pass |
| 2.4 | Tip copy at real size / large Dynamic Type | S | Device time |
| **Stage 3 — deferred engineering (after 3.3 ships)** ||||
| 3.1 | `PositionSummaryView.pitchingRows()` — third copy of the pitch maths | M | Tests for the Pitching tab first |
| 3.2 | Debounced CloudKit push | M | A design pass, not a cleanup |
| **Stage 4 — decisions and long poles** ||||
| 4.1 | History paywall auto-opens | S | Product decision |
| 4.2 | Arc 2 gives free coaches 2 tips of 6 | S | Product decision |
| 4.3 | Paywall dark mode + Dynamic Type calibration | S | Design |
| 4.4 | Localization / string catalog | **L** | A design decision on assembled strings |

---

## Stage 0 — restore the record

### 0.1 Close out or finish the data-recovery handoff

**Source:** `HANDOFF-data-recovery.md` (13 Jul, untouched since).

This is first because it's the only document whose *instructions are actively wrong*. It reads as a live incident: "Recovery is blocked only on unlocking the iPad," and step 1 says **do not open the app on the iPad** because the on-disk copy is the last good one. But both sync-hardening fixes it demanded shipped in `7a38eb7` on 14 Jul, and the August audit verified that from source.

So one of two things is true, and the doc can't tell you which: the recovery finished and nobody closed the file, or it never happened and your iPad is still carrying the only uncorrupted copy of the real roster and game history.

**Done when:** you can state which. If recovered, the doc gets a closing note and moves to an archive (or is deleted — it's in git). If not, its steps run first, before anything else in this file.

**Size:** S to close, unknown to finish.

### 0.2 Merge to `main`

The branch is 26 commits ahead of `origin/main` with no open PR, and 2 commits ahead of its own remote right now. That includes today's cleanup and every App Intents phase. Nothing merges itself, and a long-lived branch is how work starts feeling half-finished even when it isn't.

**Done when:** `main` contains it. No CI exists, so the gate is your own review plus the suite (295 passing).

---

## Stage 1 — blocks the 3.3 submission

### 1.1 The widget's bundle version doesn't match the app's

**Found 6 Aug 2026 while verifying this backlog — not previously written down anywhere.**

`STLWidgetExtension` is at `CURRENT_PROJECT_VERSION = 1` / `MARKETING_VERSION = 1.0`. The app is at `34` / `3.3`. Every build prints it and nobody reads it:

```
warning: The CFBundleVersion of an app extension ('1') must match that of
its containing parent app ('34').
```

App Store Connect **rejects** this at validation. It is a build-settings edit, it costs a minute, and if it's missed it costs a full upload round-trip at the worst possible moment.

**Done when:** the widget target's `MARKETING_VERSION` is `3.3` and `CURRENT_PROJECT_VERSION` is `34`, and the warning is gone from a clean build. Best done as a variable so they can't drift again.

**Size:** XS.

### 1.2 Deploy the Worker, and confirm the CloudKit record type is in Production

**Source:** `CLEANUP-AUDIT-2026-08.md` §8.3a. Open since 2 Aug.

The Worker at `~/Desktop/stl-worker` was pinned to the APNs **sandbox** host. TestFlight and App Store builds get production device tokens, which sandbox rejects with `BadDeviceToken` — no error surfaces in the app, the notification simply never arrives. Every shared-team push would have silently stopped working at submission. It's fixed in the file and **not live**: editing does not redeploy.

Two things, in order:

1. Confirm the `DeviceToken` record type exists in **Production** CloudKit (the config now points there; if it hasn't been promoted, the query 400s and no push goes out).
2. `npm run deploy` in `stl-worker`.

This is the highest-stakes item in the file: the failure mode is silent, it hits every shared team, and you'd find out from a user.

**Note:** `stl-worker` is not under version control. Worth fixing while you're in there.

**Size:** S. **Do it before the build goes to TestFlight, not after.**

### 1.3 Verify the Siri phrases on a physical device

**Source:** `HANDOFF-app-intents.md` §9a.2 and §9b.2, where it is explicitly marked a blocker.

Nine App Shortcuts ship in 3.3. Spoken invocation has **never** been proven outside a simulator, and two of them — `PitchEligibilityIntent` and `OpenPlayerIntent` — are voice-only: every one of their phrases carries an entity slot, and typed Spotlight matches shortcut *titles*, so they don't surface as tiles at all. If spoken entity resolution doesn't work, those two are reachable only by hand-building a shortcut.

The parameter-free tiles (Open Lineup, Fill Lineup, Game Recap, My Rules, Pitch Limits, Rest Days) are confirmed working in typed Spotlight.

**Blocked on:** your standing rule against debug builds on your devices. Needs a TestFlight build or an explicit exception — and TestFlight needs 1.1 and 1.2 done first.

**Done when:** each of the nine phrases is spoken to a real device and the right thing happens, with the two parameterized ones resolving a spoken player name.

**Size:** M.

### 1.4 Verify iPad read-only with a real shared team

**Source:** `CLEANUP-AUDIT-2026-08.md` §2.4a and its test plan.

Fixed today, unverified on hardware. Before this, a view-only participant on iPad could reassign positions, reorder the batting order, clear positions and finalize the lineup — which notifies the whole team.

The eight-step plan is at the end of the audit. **Step 7 is the one not to skip:** switch back to a team you own on the same iPad and confirm editing still works. The gating is per-team, not per-device, and the plausible way to get this wrong is to over-gate and lock a coach out of their own team.

**Blocked on:** two devices and an accepted view-only share. Pairs naturally with 1.3 — same TestFlight build.

**Size:** M.

---

## Stage 2 — small, and cheap while you're already on a device

### 2.1 The Lineup tab is still titled "Lineup Builder"

**Source:** `HANDOFF-app-intents.md` §9a.1, "Still wrong, and not fixed."

`LineupView.swift:259` hardcodes `.navigationTitle("Lineup Builder")` — the old name, as the large title on the Lineup tab. The handoff notes this is *more* visible than the `ShortcutsLink` button that prompted the whole rename. `PDFGenerator.swift:391` uses it as a fallback header too.

One-word edit each, deliberately left because it's app copy rather than a build setting — and because it depends on 2.2.

**Size:** XS.

### 2.2 Decide whether to keep the `PRODUCT_NAME` rename

**Source:** `HANDOFF-app-intents.md` §9a.1. Flagged as exceeding the original decision, with an explicit "back it out if you'd rather not carry it."

Renaming `PRODUCT_NAME` to "Stack the Lineup" also renamed `CFBundleExecutable` and the `.app` wrapper. That's shipping bundle metadata on a released app — allowed on an update, but it changes crash-report and dSYM naming. Reverting is a `git revert` of that commit; nothing else depends on it.

**Decide before submitting**, because after 3.3 ships the crash-report discontinuity is already in your history.

**Size:** S (the decision; the revert is mechanical).

### 2.3 The one unverified tip transition

**Source:** `TIPS-onboarding-spec.md`, "Not verified / still open."

`ReuseSaveTemplateTip`'s live in-place advance (dismiss tip 2 → tip 3 appears without leaving `GameLogDetailView`). It uses the identical pattern already verified on the lead history tip on both platforms, so this is confirmation, not investigation. It was blocked on re-seeding a fresh install; now that "Take the Tour" actually works, a reset and re-walk is enough.

**Size:** S, manual pass from Xcode.

### 2.4 Read the tip copy at real size

**Source:** `TIPS-onboarding-spec.md`, Open questions.

Tip copy has never been read on a device. Popover width is narrower than the spec tables suggest, and some messages may want trimming — especially at large Dynamic Type. Cheap to fold into the device session for 1.3/1.4.

**Size:** S.

---

## Stage 3 — deferred engineering (after 3.3)

Both were deferred **on purpose**, with reasons that still hold. Neither should jump the queue.

### 3.1 `PositionSummaryView.pitchingRows()`

**Source:** `CLEANUP-AUDIT-2026-08.md` §2.2a.

The third copy of the pitch-window arithmetic. It differs in ways that matter — it adds `assignedInnings`, doesn't filter `.never` pitcher preferences itself, and behaves differently with rules disabled. Folding it into `coachesGuideSummary` changes a Pro-visible surface with no test coverage.

**Order is the point:** tests for the Pitching tab first, then consolidate. **Size:** M.

### 3.2 Debounce the CloudKit push

**Source:** `CLEANUP-AUDIT-2026-08.md` §6.2.

~70 `save()` call sites, no debounce; every position drag is a CloudKit round-trip. Finding 6.1 removed the worst burst (Quick Set) and 6.1a removed the double-save on team edits, so the pressure is off.

A real debounce needs a trailing-edge flush on `scenePhase` and opens a window where a crash loses the last write — on the sync path behind the July incident. **A design pass, not a cleanup.** **Size:** M, and higher risk than its size suggests.

---

## Stage 4 — decisions and long poles

### 4.1 The History paywall auto-opens

`GameLogsView.swift:66` presents `ProGate` unprompted 0.35s after a free coach opens the tab, whether or not they did anything. Tour arc 2 routes around it — but routing around a behavior isn't the same as deciding it's right. (`TIPS-onboarding-spec.md`, Open questions.) **Product decision. Size: S.**

### 4.2 Arc 2 gives free coaches 2 tips of 6

They get a real path to game 2, but four tips are structurally invisible to them. If the season story matters for conversion, the alternative is a free-tier tip pointing at what archiving builds toward. **Product decision. Size: S.**

### 4.3 Paywall dark mode + Dynamic Type

Implemented with semantic colors and a large-type-tolerant footer, but the *visual* calibration was never done on device. The build ships 8 feature rows; 9 is the ceiling. (`PAYWALL-design-handoff.md`, "Still on Design.") **Size: S.**

### 4.4 Localization

**Source:** `HANDOFF-app-intents.md` §9b.1 — "the long pole and it's overdue."

There is **no string catalog in the repo** (`find . -name "*.xcstrings"` returns nothing) and all four App Intents phases shipped `LocalizedStringResource` literals inline. Phase 4 added the most strings of any phase.

The hard part isn't the mechanical pass. `TeamRulesBuilder` **assembles** its sentences — "Everyone active needs at least \(innings) in the infield" — and that doesn't translate by swapping a table: plural rules and word order differ per language. That's a design decision to settle before any Spanish work starts, not a chore to schedule.

**Size: L.** Genuinely a project. Don't start it inside a release.

---

## Already done — stop carrying these

Things one of the docs still half-implies are open, that aren't:

- **Both cleanup audits, all phases.** July's Phase 1/2/3 and the August pass are complete as of 6 Aug 2026. The only survivors are 3.1 and 3.2 above, both deferred by decision.
- **The `StackTheLineupTests` target** — removed from the project and the scheme.
- **`cleanup-phase1.sh` / `.patch`** — deleted; they'd have failed if run.
- **`roadmap.jsx`** — gone from the repo.
- **3.3 ship-readiness** (`HANDOFF-app-intents.md` §9b.3) — that item says `MARKETING_VERSION` is still 3.2 with no 3.3 What's New entry. Both are now done: version is `3.3 (34)` and the registry has its 3.3 entry, guarded by a test that fails the build if the version moves ahead of the registry.
- **`AskSiriTip` discovery** — verified on screen 1 Aug.
- **The `ShortcutsLink` app name** — fixed; only the `navigationTitle` (2.1) is left.

## Document status

| Document | State |
|---|---|
| `BACKLOG.md` | This file. The index. |
| `HANDOFF-app-intents.md` | **Live.** The 3.3 reference; §9 is the open part. |
| `CLEANUP-AUDIT-2026-08.md` | **Closed**, except 3.1 / 3.2 and the iPad test plan. |
| `CLEANUP-AUDIT.md` | **Closed.** All three phases. Historical record. |
| `TIPS-onboarding-spec.md` | **Mostly closed.** 2.3, 2.4, 4.1, 4.2 come from here. |
| `PAYWALL-design-handoff.md` | **Closed** except 4.3. Reference for the paywall's content rules. |
| `HANDOFF-data-recovery.md` | **Unknown — see 0.1.** Its instructions are wrong either way. |
| `AppStore-Screenshots*/SCREENSHOT-NOTES.md` | Reference for the store listing. Nothing open. |

---

## How to keep this from happening again

The failure wasn't that work got dropped — almost none did. It's that five documents each held a piece of the picture, and three described a state the code had moved past. Two habits fix it:

1. **One index, many records.** This file is the only place that says what's next. The handoffs stay as deep records of *why*, and they don't need a "next steps" section competing with this one.
2. **Close things out loud.** When an item lands, strike it here and say so in the document it came from. The `HANDOFF-data-recovery.md` situation — a doc telling you not to open an app on a device, four weeks after the reason expired — is what happens otherwise.
