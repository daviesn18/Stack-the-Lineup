# Backlog — Stack the Lineup

**Created 6 Aug 2026. Last updated 7 Aug 2026 (at the archive).** One place for everything open across the working documents in this repo, in the order I'd do it. Each item says where it's written down, what "done" looks like, and what it's blocked on — so nothing here needs you to re-read a 60 KB handoff to know what it is.

**The spine is the 3.3 submission.** Version is `3.3 (36)` and `WhatsNewContent` has its 3.3 entry. Stages 1 and 2 are what stands between here and the App Store; everything after that is deferred by choice and should stay deferred until 3.3 is out.

---

## ▶ Start here

**Everything left before you can submit 3.3 is one TestFlight build and one device session.** Four items — 1.3, 1.4, 2.3, 2.4 — all want the same build on real hardware, plus 1.5, which is two commands against the archive itself. Nothing else blocks them; the build-settings and backend blockers were cleared on 6 Aug.

1. **Archive and upload to TestFlight.** The widget version mismatch that would have failed validation (1.1) is fixed, and a Release build for a device was verified on 6 Aug — builds clean, app and widget resolving to the same build number in their built `Info.plist`s. The build has since moved to **36**; both targets resolve to it from the project level. See the 7 Aug note in 1.1 — the drift came back once.
2. **Run the two checks in 1.5 against the finished archive** before you rely on the build. Both are one command, both catch a problem that would otherwise look like something else entirely.
3. **On device, in one sitting:** 1.3 (nine Siri phrases spoken aloud), 1.4 (iPad read-only with a real shared team, don't skip step 7), 2.3 (one tip transition), 2.4 (read tip copy at large Dynamic Type).
4. **While a real shared team is set up for 1.4**, finalize a lineup and confirm a push actually arrives. That's the one part of the notification chain never exercised — see the caveat in 1.2.

State of the repo: `main` is at the 7 Aug tip and pushed; **`feature/app-intents-phase-0` is behind at `6324df3`** and needs a decision — it was at parity with `main` before the 6 Aug evening work. Suite green (`Lineup BuilderTests`, including the new `PitchingSummaryTests`). Static analyzer clean. A Release build emits 14 warnings, all pre-existing and none blocking — see the correction under 1.1 and item 4.5. The Worker lives in its own repo now — [`daviesn18/stl-worker`](https://github.com/daviesn18/stl-worker), private — with its own README covering the push architecture.

---

## The order

| # | Item | Size | Blocked on |
|---|---|---|---|
| **Stage 0 — restore the record** ||||
| ~~0.1~~ | ~~Close out `HANDOFF-data-recovery.md`~~ | — | ✅ **6 Aug** — recovered; doc closed |
| ~~0.2~~ | ~~Merge to `main`~~ | — | ✅ **6 Aug** — both branches at `4cb258c` |
| **Stage 1 — blocks the 3.3 submission** ||||
| ~~1.1~~ | ~~Widget bundle version mismatch~~ | — | ✅ **6 Aug** — versions now project-level |
| ~~1.2~~ | ~~Worker deploy + Production CloudKit~~ | — | ✅ **6 Aug** — was silently broken; fixed and verified |
| **1.3** | **Siri phrases on a physical device** | M | **A TestFlight build** — nothing else now |
| **1.4** | **iPad read-only on two devices** | M | **A TestFlight build + a real shared team** |
| **1.5** | **Two checks on the finished archive** | S | **An archive existing.** Both are one command |
| **Stage 2 — cheap while you're already on a device** ||||
| ~~2.1~~ | ~~`LineupView` titled "Lineup Builder"~~ | — | ✅ **6 Aug** |
| ~~2.2~~ | ~~Keep the `PRODUCT_NAME` rename?~~ | — | ✅ **6 Aug** — decided: keeping it |
| **2.3** | `ReuseSaveTemplateTip` live advance | S | A manual Xcode pass |
| **2.4** | Tip copy at real size / large Dynamic Type | S | Device time |
| **Stage 3 — deferred engineering (after 3.3 ships)** ||||
| ~~3.0~~ | ~~Calendar-week window is empty on Sundays~~ | — | ✅ **6 Aug** — found and fixed; 4 copies now share one derivation |
| 3.1 | `PositionSummaryView.pitchingRows()` — third copy of the pitch maths | M | ~~Tests first~~ — ✅ tests landed 6 Aug; ready to do |
| 3.2 | Debounced CloudKit push | M | A design pass, not a cleanup |
| **Stage 4 — decisions and long poles** ||||
| 4.1 | History paywall auto-opens | S | Product decision |
| 4.2 | Arc 2 gives free coaches 2 tips of 6 | S | Product decision |
| 4.3 | Paywall dark mode + Dynamic Type calibration | S | Design |
| 4.4 | Localization / string catalog | **L** | A design decision on assembled strings |
| 4.5 | Swift 6 language mode — 12 warnings become errors | M | Nothing. Do it early in a cycle, not late |

---

## Stage 1 — blocks the 3.3 submission

### 1.3 Verify the Siri phrases on a physical device

**Source:** `HANDOFF-app-intents.md` §9a.2 and §9b.2, where it is explicitly marked a blocker.

Nine App Shortcuts ship in 3.3. Spoken invocation has **never** been proven outside a simulator, and two of them — `PitchEligibilityIntent` and `OpenPlayerIntent` — are voice-only: every one of their phrases carries an entity slot, and typed Spotlight matches shortcut *titles*, so they don't surface as tiles at all. If spoken entity resolution doesn't work, those two are reachable only by hand-building a shortcut.

The parameter-free tiles (Open Lineup, Fill Lineup, Game Recap, My Rules, Pitch Limits, Rest Days) are confirmed working in typed Spotlight.

**Blocked on:** a TestFlight build, because of your standing rule against debug builds on your own devices. *The prerequisites for that build (1.1, 1.2) are now done* — this is no longer waiting on anything but the upload.

**Done when:** each of the nine phrases is spoken to a real device and the right thing happens, with the two parameterized ones resolving a spoken player name.

**Size:** M.

### 1.4 Verify iPad read-only with a real shared team

**Source:** `CLEANUP-AUDIT-2026-08.md` §2.4a and its test plan.

Fixed in code on 6 Aug, unverified on hardware. Before that fix, a view-only participant on iPad could reassign positions, reorder the batting order, clear positions and finalize the lineup — which notifies the whole team.

The eight-step plan is at the end of the audit. **Step 7 is the one not to skip:** switch back to a team you own on the same iPad and confirm editing still works. The gating is per-team, not per-device, and the plausible way to get this wrong is to over-gate and lock a coach out of their own team.

**Blocked on:** two devices and an accepted view-only share. Pairs naturally with 1.3 — same TestFlight build.

**Also do this here:** finalize a lineup from the owning device and confirm the push arrives on the other. That's the only way to exercise APNs (see 1.2).

**Size:** M.

### 1.5 Two checks on the finished archive

**Source:** found 6 Aug while verifying the Release build. Neither is visible in Xcode's Issue navigator — one is a signing outcome, the other a build-setting consequence, and **neither shows up as a warning**.

Run both once the `.xcarchive` exists, before trusting the build for 1.3/1.4.

**a. Is the push environment `production`?**

```bash
codesign -d --entitlements :- "$(ls -td ~/Library/Developer/Xcode/Archives/*/*.xcarchive | head -1)/Products/Applications/Stack the Lineup.app" 2>/dev/null | grep -A1 aps-environment
```

`Lineup Builder.entitlements` says `development`. Xcode's automatic signing normally rewrites this to `production` when archiving with a distribution profile, so it's very often fine as-is — but it has never been confirmed on this project. **Why it matters here specifically:** TestFlight builds talk to production APNs, and 1.2 pointed the Worker at `api.push.apple.com`. If the archive embeds `development`, the app registers against sandbox APNs, the device tokens it writes to CloudKit are invalid for the production host, and 1.4's push test fails **looking exactly like a Worker fault** — which is the failure you'd waste the most time on, having just spent a day fixing the Worker for real.

Expected: `production`.

**b. Is code-coverage instrumentation riding along?**

```bash
nm "$(ls -td ~/Library/Developer/Xcode/Archives/*/*.xcarchive | head -1)/Products/Applications/Stack the Lineup.app/Stack the Lineup" | grep -c __llvm_prf
```

`ENABLE_CODE_COVERAGE` resolves to `YES` for Release. It is **not** in the pbxproj — it comes from the scheme, whose Test action has coverage enabled, and it reaches further than it should. A plain `xcodebuild build -configuration Release` compiles *both* the app and the widget with `-profile-generate -profile-coverage-mapping`, and the resulting binary carries **9,080** profiling symbols at 22 MB. Instrumented code links the profiling runtime, attempts to write `.profraw` files at runtime, inflates the binary and runs slower — not what you want under a Siri latency test.

**Unverified:** that was the `build` action. Product → Archive may well not instrument. This check settles it.

Expected: `0`. Anything else — Edit Scheme → Test → Options → uncheck Code Coverage, or scope it to the test targets, then re-archive.

**Size:** S. Two commands.

### ~~1.1 The widget's bundle version doesn't match the app's~~ — ✅ done 6 Aug 2026

`STLWidgetExtension` was at `1` / `1.0` while the app was at `34` / `3.3`. App Store Connect rejects that at validation, so it would have cost an upload round-trip at the worst moment.

Fixed as a single source of truth rather than a copied value: `CURRENT_PROJECT_VERSION` and `MARKETING_VERSION = 3.3` now live in the **project-level** Debug and Release configurations, and the per-target overrides were deleted from both the app and the widget. Both targets resolve to the same values and the built `Info.plist`s agree — confirmed 6 Aug against a Release build for a device, which is the form validation actually sees. The build is now **36**.

> 🔁 **The trap below fired, on 7 Aug, at the archive.** Bumping the build from 34 in **General → Identity** wrote `CURRENT_PROJECT_VERSION = 35` as a *target-level* override on the app (both configs) while the widget kept inheriting the project-level 34 — the identical validation-failing mismatch this item had already fixed once, roughly twelve hours later. Caught before upload by diffing `project.pbxproj`, not by anything Xcode said: the app's General tab reads `35`, the widget's reads `34`, and **nothing warns you**. Re-fixed by setting the project level to 36 and deleting both overrides.
>
> Worth knowing: there is **no** auto-increment anywhere — no run-script phases, no scheme pre/post actions, no `agvtool`. Every bump is manual, so every bump is a chance to re-open this.

> **Correction (6 Aug, later):** this entry used to claim a clean build emits **zero** warnings. It doesn't. A Release build for `generic/platform=iOS` emits **14**, all pre-existing and none of them version-related: 12 Swift 6 actor-isolation warnings across `TeamRules`, `PitchEligibility`, `GameRecap`, `AutoFillCoordinator` and `PurchaseManager` — two of which say outright *"this is an error in the Swift 6 language mode"* — plus 2 `Text` `+` deprecations in `ContextualTips.swift:58` and `PaywallView.swift:177`. None block validation. The version work was clean; the build as a whole was never warning-free, and the original claim was probably scoped to the version warnings or measured in Debug.
>
> The Swift 6 dozen are a real future wall — a language-mode migration turns them into errors — but they belong after 3.3, not in it.

> ⚠️ **Bump the version at the project level from now on.** Editing the Version or Build field in a target's General tab in Xcode writes a target-level override and silently re-opens the drift this removed.
>
> **How, concretely** — this is the part the warning was missing the first time, and it's why the trap fired anyway:
>
> 1. Project navigator → the blue **project** icon at the top.
> 2. Editor sidebar → **"Lineup Builder" under PROJECT**, *not* under TARGETS.
> 3. **Build Settings** → filter **All** → search `Current Project Version` → set it. Check Debug and Release both.
> 4. If a target already overrides it: select that target → Build Settings → the value renders **bold** → select the row and press **Delete** to restore inheritance.
>
> Switch Build Settings from **Combined** to **Levels** to see this directly — done right, the value sits in the *Project* column and the *Target* column is empty. Treat General → Identity as read-only; it shows the resolved value, so it will look correct either way, and typing in it is what creates the override.
>
> Verify from the shell, which reads what the build actually resolves rather than what a text field displays:
>
> ```bash
> for t in "Lineup Builder" "STLWidgetExtension"; do echo "$t: $(xcodebuild -project "Lineup Builder.xcodeproj" -target "$t" -configuration Release -showBuildSettings 2>/dev/null | grep -E "^\s+CURRENT_PROJECT_VERSION " | awk '{print $3}')"; done
> ```
>
> Both must print the same number.

### ~~1.2 The Worker, and Production CloudKit~~ — ✅ fixed 6 Aug 2026

**Push works.** Health check returns `{"sent":0}` / HTTP 200 and the CloudKit query succeeds. Everything below is the record of a live outage that no longer exists — **there is nothing to do here.**

**What was actually wrong.** There was no Production CloudKit server-to-server key at all, only a Development one. CloudKit rejected every Production query with `401 AUTHENTICATION_FAILED`, the Worker threw before reaching APNs, and **every shared-team notification had been failing silently.** This was not the `DeviceToken` record-type promotion the backlog had been tracking — that turned out to be fine.

The fix needed three coupled parts. Missing any one keeps push broken:

1. **A Production server-to-server key** in CloudKit Console. Keys are per-environment; a Development key is not valid in Production.
2. **`CLOUDKIT_KEY_ID` updated and redeployed.** The Worker sends whatever is in `wrangler.toml` — creating the key changes nothing until you deploy.
3. **The private key in PKCS#8, not SEC1.** `openssl ecparam -genkey` emits SEC1 (`BEGIN EC PRIVATE KEY`, 121-byte DER); `crypto.subtle.importKey("pkcs8", …)` needs PKCS#8 (`BEGIN PRIVATE KEY`, 138-byte DER). `importECKey` strips both header styles, so a SEC1 key *looks* accepted and then fails at import. `openssl pkcs8 -topk8 -nocrypt` converts it.

**Questions this closed along the way:**

- **The `DeviceToken` record type is in Production** with `teamID` queryable — a successful query proves it, since an unknown record type or non-queryable filter field would both error. Open since 2 Aug, now answered.
- **`CLOUDKIT_ENV = production` and the `api.push.apple.com` host are both live.** `CLEANUP-AUDIT-2026-08.md` §8.3a claims the 2 Aug fix was "fixed in the file and **not live**" — **that claim is wrong**; the version history shows it deployed the same day.

> ⚠️ **One thing is still unproven: APNs has never sent a real push.** The health check uses a nonexistent team, which matches zero device tokens, so the Worker returns before contacting Apple. The production APNs host is deployed but unexercised. **First real test is 1.4's device session.**

**Why it went unnoticed, and what to watch instead.** Cloudflare reported 0 errors and a **0% error rate** for the entire outage, because the Worker catches its own throw and returns a 500 *response* — only unhandled exceptions count as errors. **Don't trust the error rate.** Watch Observability → Events, or the `sent` count. Workers Logs are now **enabled** (declared in `wrangler.toml`, so it's version controlled rather than a dashboard toggle that can drift), so output is retained and searchable after the fact. Traces remain off.

**Health check** — safe to run any time, sends no notification:

```bash
curl -sS -X POST https://stl-push-worker.stackthelineup.workers.dev \
  -H "Content-Type: application/json" \
  -d '{"teamID":"00000000-0000-0000-0000-000000000000","eventType":"lineup_finalized","triggeredBy":"healthcheck"}' \
  -w "\nHTTP %{http_code}\n"
```

`{"sent":0}` / 200 = healthy. `Internal error` / 500 = CloudKit auth is broken again.

**Full detail** — architecture, event types, the environment trap, deploy notes — is in the [`stl-worker` README](https://github.com/daviesn18/stl-worker). That repo is the record now; this entry is just the summary.

---

## Stage 2 — cheap while you're already on a device

### 2.3 The one unverified tip transition

**Source:** `TIPS-onboarding-spec.md`, "Not verified / still open."

`ReuseSaveTemplateTip`'s live in-place advance (dismiss tip 2 → tip 3 appears without leaving `GameLogDetailView`). It uses the identical pattern already verified on the lead history tip on both platforms, so this is confirmation, not investigation. It was blocked on re-seeding a fresh install; now that "Take the Tour" actually works, a reset and re-walk is enough.

**Size:** S, manual pass from Xcode.

### 2.4 Read the tip copy at real size

**Source:** `TIPS-onboarding-spec.md`, Open questions.

Tip copy has never been read on a device. Popover width is narrower than the spec tables suggest, and some messages may want trimming — especially at large Dynamic Type. Cheap to fold into the device session for 1.3/1.4.

**Size:** S.

### ~~2.1 The Lineup tab was titled "Lineup Builder"~~ — ✅ done 6 Aug 2026

Both sites now read "Stack the Lineup": `LineupView.swift:259` (the large navigation title) and the empty-team-name fallback at `PDFGenerator.swift:391`. A sweep of the Swift sources found no other user-facing use of the old name — the only remaining hit is the Xcode-generated file-header comment in `Analytics.swift`, which is the project name, not copy.

### ~~2.2 Whether to keep the `PRODUCT_NAME` rename~~ — ✅ decided 6 Aug 2026: **keep it**

The app ships as "Stack the Lineup". The one-time crash-report and dSYM naming discontinuity at 3.3 is accepted. No revert; 2.1 was fixed to match.

---

## Stage 3 — deferred engineering (after 3.3)

3.1 and 3.2 were deferred **on purpose**, with reasons that still hold. Neither should jump the queue.

### ~~3.0 The calendar-week window was empty on Sundays~~ — ✅ fixed 6 Aug 2026

Found while writing 3.1's tests. Every copy of the window arithmetic derived Monday by taking the reference date's `weekOfYear` and setting `weekday = 2`, which assumes the calendar's week starts on Monday. On the US default it starts Sunday, so the week containing a Sunday ran Sun–Sat, `weekday = 2` resolved to **the following Monday**, and `windowStart` landed a day in the future.

**What it cost, on Sundays, for teams set to Calendar Week:** `pitchesInWindow` returned 0 no matter what was thrown that week, the weekly cap stopped applying, `.limited` and `.mustRest` never fired, and the Coaches Guide and PDF both showed a full ceiling. Sunday is a game day.

`PitchEligibilityEngine.startOfPitchingWeek` is now the single derivation, counting back from the weekday rather than asking the locale where the week begins. **The audit called `pitchingRows()` the third copy of the pitch maths; there were four** — `DefensiveGridView.pitchesRemaining`, behind the inline pitcher-slot display, had it too. All four now route through the helper, which is a down payment on 3.1.

Guarded by four tests, including one that sweeps `firstWeekday` 1–7 and one that pins the rolling window as untouched.

> The pattern from 6 Aug held for a third time: every surface duplicated the same wrong arithmetic, so they all agreed with each other and nothing looked wrong from inside the app.

### 3.1 `PositionSummaryView.pitchingRows()`

**Source:** `CLEANUP-AUDIT-2026-08.md` §2.2a.

The third copy of the pitch-window arithmetic. It differs in ways that matter — it adds `assignedInnings`, doesn't filter `.never` pitcher preferences itself, and behaves differently with rules disabled.

**The blocker is cleared.** `PitchingSummaryTests.swift` landed 6 Aug: 23 tests over `coachesGuideSummary`, covering the window boundaries, the `available` ceiling, rest days, the sort order, and agreement with `PitchEligibilityEngine.status`. The four known divergences each carry a `DIVERGENCE` note in the test that pins this side's behavior, so the fold-in is a choice made with the consequences written down rather than rediscovered.

One thing the tests can't reach: `pitchingRows()` is `private` inside a SwiftUI `View`, so it isn't callable from the test target at all. Extracting it is the first step of the consolidation, not a prerequisite. **Size:** M.

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

### 4.5 Swift 6 language mode

**Source:** the Release build of 6 Aug. Detail in the correction under 1.1.

The app builds at `SWIFT_VERSION = 5.0` with `SWIFT_APPROACHABLE_CONCURRENCY = YES` and `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. That combination is why a Release build emits 12 actor-isolation warnings: with everything MainActor by default, any synchronous nonisolated context that reaches into ordinary model code is a violation. Two of the twelve already say *"this is an error in the Swift 6 language mode."* **Moving `SWIFT_VERSION` to 6.0 turns all twelve into build errors.**

Where they live: `TeamRules` (4), `PitchEligibility` (2), `GameRecap` (2), `AutoFillCoordinator` (2), `PurchaseManager` (2).

The shape of the work isn't silencing warnings — it's deciding what is genuinely main-actor state and what is pure computation. Most of the offenders are the second kind: `PitchingLimits.restDaysRequired(for:)`, `PitchingAgeBracket.bracket(for:)`, `PitchEligibilityEngine.status(...)` are stateless maths that got swept into MainActor by the project-wide default rather than because they need it. Marking those `nonisolated` is likely most of the fix.

**One trap.** `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` is set on the **app target only** — not the widget, not the tests. `WidgetSnapshot.swift` and `STLWidget.swift` compile into *both* the app and `STLWidgetExtension` (confirmed from the build's `SwiftFileList`s, not the project file), so the same source compiles MainActor-by-default in one target and nonisolated-by-default in the other. Any isolation annotation added to those two has to hold under both.

**Size: M**, and unusually front-loaded — the diagnosis is most of it, the edits are small. Do it at the *start* of a cycle: the failure mode is flipping the language mode late, hitting twelve errors in five files, and reverting under time pressure.

---

## Already done — stop carrying these

Things one of the docs still half-implies are open, that aren't:

- **Both cleanup audits, all phases.** July's Phase 1/2/3 and the August pass are complete. The only survivors are 3.1 and 3.2 above, both deferred by decision.
- **The `StackTheLineupTests` target** — removed from the project and the scheme.
- **`cleanup-phase1.sh` / `.patch`** — deleted; they'd have failed if run.
- **`roadmap.jsx`** — gone from the repo.
- **3.3 ship-readiness** (`HANDOFF-app-intents.md` §9b.3) — that item says `MARKETING_VERSION` is still 3.2 with no 3.3 What's New entry. Both are done: version is `3.3 (36)` and the registry has its 3.3 entry, guarded by a test that fails the build if the version moves ahead of the registry.
- **`AskSiriTip` discovery** — verified on screen 1 Aug.
- **The app-name cleanup** — `ShortcutsLink` and the `navigationTitle` (2.1) are both done. Nothing still says "Lineup Builder" in user-facing copy.
- **The `stl-worker` housekeeping** — it's under version control, has a GitHub repo, a README, current tooling (wrangler 4.119), and Workers Logs enabled. The backlog used to note "not under version control" as a to-do; that's closed.

## Document status

| Document | State |
|---|---|
| `BACKLOG.md` | This file. The index — the only place that says what's next. |
| [`TESTPLAN-3.3.md`](TESTPLAN-3.3.md) | **Live.** The device session, step by step: 1.5, 1.3, 1.4, 2.3, 2.4 in the order to run them. Written 7 Aug. |
| `HANDOFF-app-intents.md` | **Live.** The 3.3 reference; §9 is the open part (1.3, 4.4). |
| `CLEANUP-AUDIT-2026-08.md` | **Closed**, except 3.1 / 3.2 and the iPad test plan for 1.4. ⚠️ **§8.3a is factually wrong** — see 1.2. |
| `CLEANUP-AUDIT.md` | **Closed.** All three phases. Historical record. |
| `TIPS-onboarding-spec.md` | **Mostly closed.** 2.3, 2.4, 4.1, 4.2 come from here. |
| `PAYWALL-design-handoff.md` | **Closed** except 4.3. Reference for the paywall's content rules. |
| `HANDOFF-data-recovery.md` | **Closed 6 Aug.** Historical record of the July incident; every caution in it has expired. |
| `AppStore-Screenshots*/SCREENSHOT-NOTES.md` | Reference for the store listing. Nothing open. |
| [`stl-worker/README.md`](https://github.com/daviesn18/stl-worker) | **Live**, separate repo. The record for push: architecture, the environment trap, deploy and debugging. |

---

## How to keep this from happening again

The failure wasn't that work got dropped — almost none did. It's that five documents each held a piece of the picture, and three described a state the code had moved past. Two habits fix it:

1. **One index, many records.** This file is the only place that says what's next. The handoffs stay as deep records of *why*, and they don't need a "next steps" section competing with this one.
2. **Close things out loud.** When an item lands, strike it here and say so in the document it came from — and **delete the superseded instructions rather than layering new notes on top of them.** A closed item should read as one paragraph of "here's what happened," not as an archaeology of what people believed at each stage. `HANDOFF-data-recovery.md` telling you not to open an app on a device, four weeks after the reason expired, is what happens otherwise.

**The 6 Aug lesson worth carrying:** the two worst problems that day — the widget version mismatch and the CloudKit outage — were both *invisible from where you'd normally look*. One printed a warning in a build log nobody reads. The other showed a 0% error rate on a dashboard while failing 100% of the time. Neither was in any document. When something matters and it's cheap, **check the live thing instead of the note about it.**
