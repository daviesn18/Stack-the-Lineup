# Backlog — Stack the Lineup

**Written 6 Aug 2026.** One place for everything open across the five working documents in this repo, in the order I'd do it. Each item says where it's written down, what "done" looks like, and what it's blocked on — so nothing here needs you to re-read a 60 KB handoff to know what it is.

**The spine is the 3.3 submission.** Version is `3.3 (34)` and `WhatsNewContent` has its 3.3 entry, so the release is real and close. Stages 1 and 2 are what stands between here and the App Store. Everything after that is work you chose to defer, and it should stay deferred until 3.3 is out.

**Nothing here is half-finished code.** The scattered feeling is documentation debt, not code debt: five docs written at different times, three of which describe a state the code left behind. The code is in better shape than the paperwork.

---

## The order

| # | Item | Size | Blocked on |
|---|---|---|---|
| **Stage 0 — restore the record (do first, it's an hour)** ||||
| ~~0.1~~ | ~~Close out or finish `HANDOFF-data-recovery.md`~~ | — | **Done 6 Aug** — recovered; doc closed |
| ~~0.2~~ | ~~Merge this branch to `main`~~ | — | **Done 6 Aug** — `main` at `7219af3` |
| **Stage 1 — blocks the 3.3 submission** ||||
| ~~1.1~~ | ~~Widget bundle version mismatch~~ | — | **Done 6 Aug** — versions now project-level |
| **1.2** | 🔴 **Push is broken in production** — CloudKit 401 | S | CloudKit Console: server-to-server key for Production |
| 1.3 | Siri phrases on a physical device | M | TestFlight build, or an exception to the debug-build rule |
| 1.4 | iPad read-only on two devices | M | A real shared team |
| **Stage 2 — small, and cheap while you're already testing** ||||
| ~~2.1~~ | ~~`LineupView` still titled "Lineup Builder"~~ | — | **Done 6 Aug** |
| ~~2.2~~ | ~~Decide whether to keep the `PRODUCT_NAME` rename~~ | — | **Decided 6 Aug — keeping it** |
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

### ~~0.1 Close out or finish the data-recovery handoff~~ — done 6 Aug 2026

**Recovered.** Nick confirmed the real teams and history came back in July; no device was still holding the only good copy. `HANDOFF-data-recovery.md` now opens with a closing note, its section-2 cautions are struck through, and section 3 records that both hardening fixes shipped in `7a38eb7`. The file is a historical record and nothing in it is live. *Original entry below, for the record.*

**Source:** `HANDOFF-data-recovery.md` (13 Jul, untouched since).

This is first because it's the only document whose *instructions are actively wrong*. It reads as a live incident: "Recovery is blocked only on unlocking the iPad," and step 1 says **do not open the app on the iPad** because the on-disk copy is the last good one. But both sync-hardening fixes it demanded shipped in `7a38eb7` on 14 Jul, and the August audit verified that from source.

So one of two things is true, and the doc can't tell you which: the recovery finished and nobody closed the file, or it never happened and your iPad is still carrying the only uncorrupted copy of the real roster and game history.

**Done when:** you can state which. If recovered, the doc gets a closing note and moves to an archive (or is deleted — it's in git). If not, its steps run first, before anything else in this file.

**Size:** S to close, unknown to finish.

### ~~0.2 Merge to `main`~~ — done 6 Aug 2026

`main` and `feature/app-intents-phase-0` are both at `7219af3` and pushed. 33 commits, no force push, no conflicts.

`main` had quietly diverged — one commit each way. The local-only one (`6b4ce8d`, "Fixed paywall issues") was already reachable through the feature branch, but the remote-only one (`b51f7f6`, the Little League pitching preset for the debug seeder) existed **only** on `origin/main` and the two `claude/*` branches, and would have been lost to a force push. Merging `origin/main` into the feature branch first picked it up cleanly, then `main` fast-forwarded. The suite passed on the merged tree before the push.

*Original entry below.*

The branch is 26 commits ahead of `origin/main` with no open PR, and 2 commits ahead of its own remote right now. That includes today's cleanup and every App Intents phase. Nothing merges itself, and a long-lived branch is how work starts feeling half-finished even when it isn't.

**Done when:** `main` contains it. No CI exists, so the gate is your own review plus the suite (295 passing).

---

## Stage 1 — blocks the 3.3 submission

### ~~1.1 The widget's bundle version doesn't match the app's~~ — done 6 Aug 2026

**Fixed as a single source of truth, not a copied value.** `CURRENT_PROJECT_VERSION = 34` and `MARKETING_VERSION = 3.3` now live in the **project-level** Debug and Release configurations, and the per-target overrides were deleted from both the app and `STLWidgetExtension`. Both targets resolve to `3.3 (34)`, the built `Info.plist`s agree, and a clean build of the app scheme emits **zero** warnings. Bump the version at the project level from now on — editing the Version/Build fields in a target's General tab writes a target-level override and re-opens the drift.

*Original entry below, for the record.*

**Found 6 Aug 2026 while verifying this backlog — not previously written down anywhere.**

`STLWidgetExtension` is at `CURRENT_PROJECT_VERSION = 1` / `MARKETING_VERSION = 1.0`. The app is at `34` / `3.3`. Every build prints it and nobody reads it:

```
warning: The CFBundleVersion of an app extension ('1') must match that of
its containing parent app ('34').
```

App Store Connect **rejects** this at validation. It is a build-settings edit, it costs a minute, and if it's missed it costs a full upload round-trip at the worst possible moment.

**Done when:** the widget target's `MARKETING_VERSION` is `3.3` and `CURRENT_PROJECT_VERSION` is `34`, and the warning is gone from a clean build. Best done as a variable so they can't drift again.

**Size:** XS.

### 1.2 The Worker is deployed and **push is broken in production right now** 🔴

**Root-caused 6 Aug 2026 by probing the live Worker.** Shared-team push notifications do not work. Every attempt fails.

```
CloudKit query failed: 401
{ "serverErrorCode" : "AUTHENTICATION_FAILED", "reason" : "Authentication failed" }
```

The Worker's CloudKit query is rejected before it ever reaches APNs, so `fetchDeviceTokens` throws and the request returns 500. Confirmed twice against the live URL and captured from `wrangler tail`.

**This is not the record-type promotion everyone was worried about.** A missing `DeviceToken` type returns a 400 naming the record type. A 401 `AUTHENTICATION_FAILED` means the **server-to-server key is not valid for the Production environment** — most likely registered against Development only, or the `CLOUDKIT_PRIVATE_KEY` secret no longer matches key ID `77b4dee8…`. Whether the record type was ever promoted is still unknown, because auth fails first and the query never runs.

**What the same probe proved is working:**

- `CLOUDKIT_ENV = production` is live — the logged subpath is `/database/1/iCloud.com.nickdavies.LineupBuilder.Lineup-Builder/**production**/public/records/query`.
- The live bundle matches the current `src/index.ts`, so the `api.push.apple.com` host is deployed too. The 2 Aug fix **is** live, which settles the audit's "not live" claim: it was wrong.

**Why nobody noticed.** Cloudflare reports 0% error rate and 0 errors, because the Worker catches the throw and returns a 500 *response* — Cloudflare only counts unhandled exceptions. The dashboard looks perfectly healthy while every push fails. Workers Logs and Traces are both **Disabled** on this Worker, so nothing was retained either; the diagnosis needed a live `wrangler tail`.

**Fix, in CloudKit Console** (`icloud.developer.apple.com` → container `iCloud.com.nickdavies.LineupBuilder.Lineup-Builder`): confirm the server-to-server key `77b4dee8…` is valid for **Production**, and that the deployed `CLOUDKIT_PRIVATE_KEY` is the matching `.pem`. Then re-check the `DeviceToken` record type in Production Schema — still unverified, and it's the next thing that can fail once auth passes.

**Reproduce any time** — sends no notification, because a nonexistent team matches zero device tokens and the Worker returns before building a payload:

```bash
curl -sS -X POST https://stl-push-worker.stackthelineup.workers.dev \
  -H "Content-Type: application/json" \
  -d '{"teamID":"00000000-0000-0000-0000-000000000000","eventType":"lineup_finalized","triggeredBy":"healthcheck"}' \
  -w "\nHTTP %{http_code}\n"
```

`{"sent":0}` / HTTP 200 means CloudKit auth is fixed. `Internal error` / HTTP 500 means it isn't.

**This blocks 3.3 harder than anything else in Stage 1.** Every shared team is affected, and the failure is invisible from the app.

---

*Earlier notes from 6 Aug, before the root cause was known:*

- **The deploy is done.** Nick deployed from a terminal on 6 Aug; version `edd6d9eb` serves 100% of traffic. Cloudflare shows 0 Worker errors in the following 24 hours.
- **The audit's premise was wrong.** §8.3a says the APNs-host fix was "fixed in the file and **not live**." But the Worker's version history shows an upload at `2026-08-02T15:25:19Z`, five minutes after the mtime on `wrangler.toml` and `src/` — so 2 Aug looks like it was edited *and* deployed. Treat "not live" as unverified rather than true. Nothing recorded what any given upload contained, which is the actual gap.
- **`stl-worker` is now under version control** — `git init` on 6 Aug with a baseline commit, `.gitignore` excluding `node_modules/`, `.wrangler/`, and any key material. No remote yet, and no GitHub repo exists for it (the app's repo, `daviesn18/Stack-the-Lineup`, has never contained the Worker on any branch). Both private keys are Wrangler secrets and are not on disk.
- **Still open: the CloudKit half.** Nobody has confirmed the `DeviceToken` record type was promoted to **Production**. Cloudflare looks healthy either way — if the promotion never happened, the Worker's CloudKit query 400s and no push goes out. `icloud.developer.apple.com` → container `iCloud.com.nickdavies.LineupBuilder.Lineup-Builder` → Production → Schema → Record Types.

*Original entry below.*

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

### ~~2.1 The Lineup tab is still titled "Lineup Builder"~~ — done 6 Aug 2026

Both sites now read "Stack the Lineup": [`LineupView.swift:259`](Lineup%20Builder/LineupView.swift) and the empty-team-name fallback at [`PDFGenerator.swift:391`](Lineup%20Builder/PDFGenerator.swift). A sweep of the Swift sources found no other user-facing use of the old name — the only remaining hit is the Xcode-generated file-header comment in `Analytics.swift`, which is the project name, not copy. *Original entry below.*

**Source:** `HANDOFF-app-intents.md` §9a.1, "Still wrong, and not fixed."

`LineupView.swift:259` hardcodes `.navigationTitle("Lineup Builder")` — the old name, as the large title on the Lineup tab. The handoff notes this is *more* visible than the `ShortcutsLink` button that prompted the whole rename. `PDFGenerator.swift:391` uses it as a fallback header too.

One-word edit each, deliberately left because it's app copy rather than a build setting — and because it depends on 2.2.

**Size:** XS.

### ~~2.2 Decide whether to keep the `PRODUCT_NAME` rename~~ — decided 6 Aug 2026: **keep it**

The app ships as "Stack the Lineup". The one-time crash-report and dSYM naming discontinuity at 3.3 is accepted. No revert; 2.1 was fixed to match. *Original entry below.*

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
| `HANDOFF-data-recovery.md` | **Closed 6 Aug.** Historical record of the July incident; every caution in it has expired. |
| `AppStore-Screenshots*/SCREENSHOT-NOTES.md` | Reference for the store listing. Nothing open. |

---

## How to keep this from happening again

The failure wasn't that work got dropped — almost none did. It's that five documents each held a piece of the picture, and three described a state the code had moved past. Two habits fix it:

1. **One index, many records.** This file is the only place that says what's next. The handoffs stay as deep records of *why*, and they don't need a "next steps" section competing with this one.
2. **Close things out loud.** When an item lands, strike it here and say so in the document it came from. The `HANDOFF-data-recovery.md` situation — a doc telling you not to open an app on a device, four weeks after the reason expired — is what happens otherwise. It's closed now, both here and in the file itself; that's the pattern.
