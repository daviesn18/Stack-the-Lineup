# Backlog — Stack the Lineup

**Created 6 Aug 2026. Last updated 8 Aug 2026 (sharing rework, second device round).** One place for everything open across the working documents in this repo, in the order I'd do it. Each item says where it's written down, what "done" looks like, and what it's blocked on — so nothing here needs you to re-read a 60 KB handoff to know what it is.

**The spine is the 3.3 submission.** Version is `3.3 (36)` and `WhatsNewContent` has its 3.3 entry. Stages 1 and 2 are what stands between here and the App Store; everything after that is deferred by choice and should stay deferred until 3.3 is out.

---

## ▶ Start here

**Sharing was reworked into 3.3 on 8 Aug — see 1.7.** That was a deliberate scope call: a release is still weeks out, and device testing on 7 Aug found the whole Shared Team surface unusable. **~~1.4~~ closed the same day — all eight steps of the 2.4a plan pass on hardware**, which was the largest finding in the August audit and had never been exercised on a device.

**Two things stand between here and the submission: 1.7 and 1.5.**

1. **Archive and upload to TestFlight.** The widget version mismatch that would have failed validation (1.1) is fixed, and a Release build for a device was verified on 6 Aug — builds clean, app and widget resolving to the same build number in their built `Info.plist`s. The build has since moved to **36**; both targets resolve to it from the project level. See the 7 Aug note in 1.1 — the drift came back once.
2. **Run the two checks in 1.5 against the finished archive** before you rely on the build. Both are one command, both catch a problem that would otherwise look like something else entirely.
3. **Run 1.7 — the reworked sharing surface.** Steps 1–11 can go from Xcode builds and are the fast loop; **steps 12–13 need TestFlight**, because push cannot work from a Debug build against the current Worker. See the environment note in that item before you start, and make sure all three devices run the same build type.
4. **The push test rides on 1.7 step 12.** It used to hang off 1.4; it was being tracked in three places and now lives in one. It is still the only part of the notification chain never exercised — see the caveat in 1.2.

> **Where the 8 Aug session stopped.** The sharing and notification rework is **written, building, and unit-green, but uncommitted** — 14 modified files plus the new `Lineup Builder/TeamSharingView.swift`, all on `main` at `24dad6f`. **`CURRENT_PROJECT_VERSION` is still 36 and needs bumping to 37** at the project level in Xcode, not by hand — see 1.1, where app/widget drift has already recurred once. Plan for 9 Aug: archive 37, upload to TestFlight, install on **all three devices** so they share one CloudKit environment, then run 1.7 end to end including the push steps.

State of the repo: `main` is at the 7 Aug tip and pushed, **with the 8 Aug sharing rework uncommitted on top**; **`feature/app-intents-phase-0` is behind at `6324df3`** and needs a decision — it was at parity with `main` before the 6 Aug evening work. Suite green (`Lineup BuilderTests`). Static analyzer clean. A Release build emits 14 warnings, all pre-existing and none blocking — see the correction under 1.1 and item 4.5. The Worker lives in its own repo now — [`daviesn18/stl-worker`](https://github.com/daviesn18/stl-worker), private — with its own README covering the push architecture.

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
| ~~1.3~~ | ~~Siri phrases on a physical device~~ | — | ✅ **7 Aug** — 6 of 9 pass; 3 entity ones accepted picker-degraded |
| ~~1.4~~ | ~~iPad read-only on two devices~~ | — | ✅ **8 Aug** — all 8 steps pass; 2.4a confirmed both ways |
| **1.5** | **Two checks on the finished archive** | S | **An archive existing.** Both are one command |
| ~~1.6~~ | ~~What's New quotes Siri phrases that can't work~~ | — | ✅ **7 Aug** — copy rewritten; ships in 36 |
| **1.7** | **Verify the reworked sharing surface on device** | M | **A second iCloud account.** Steps 1–11 run from Xcode; 12–13 need TestFlight |
| **Stage 2 — cheap while you're already on a device** ||||
| ~~2.1~~ | ~~`LineupView` titled "Lineup Builder"~~ | — | ✅ **6 Aug** |
| ~~2.2~~ | ~~Keep the `PRODUCT_NAME` rename?~~ | — | ✅ **6 Aug** — decided: keeping it |
| ~~2.3~~ | ~~`ReuseSaveTemplateTip` live advance~~ | — | ❌ **7 Aug — failed on device.** Cause found; fix is **3.4** |
| ~~2.4~~ | ~~Tip copy at real size / large Dynamic Type~~ | — | ✅ **7 Aug** — all tips walked at large type; nothing truncates |
| **Stage 3 — deferred engineering (after 3.3 ships)** ||||
| ~~3.0~~ | ~~Calendar-week window is empty on Sundays~~ | — | ✅ **6 Aug** — found and fixed; 4 copies now share one derivation |
| 3.1 | `PositionSummaryView.pitchingRows()` — third copy of the pitch maths | M | ~~Tests first~~ — ✅ tests landed 6 Aug; ready to do |
| 3.2 | Debounced CloudKit push | M | A design pass, not a cleanup |
| 3.4 | TipKit live advance on the History screens (from 2.3) | M | A device round-trip to verify any fix |
| **Stage 4 — decisions and long poles** ||||
| 4.1 | History paywall auto-opens | S | Product decision |
| 4.2 | Arc 2 gives free coaches 2 tips of 6 | S | Product decision |
| 4.3 | Paywall dark mode + Dynamic Type calibration | S | Design |
| 4.4 | Localization / string catalog | **L** | A design decision on assembled strings |
| 4.5 | Swift 6 language mode — 12 warnings become errors | M | Nothing. Do it early in a cycle, not late |
| 4.6 | iOS 27 App Intents readiness — `indexingKey`, App Schemas | M | An iOS 27 beta to verify against |

---

## Stage 1 — blocks the 3.3 submission

### 1.3 Verify the Siri phrases on a physical device

**Source:** `HANDOFF-app-intents.md` §9a.2 and §9b.2, where it is explicitly marked a blocker.

Nine App Shortcuts ship in 3.3. **Run on device 7 Aug 2026** (ND iPhone, iPhone 15 Pro, iOS 26.6, TestFlight build 35). Results below; the raw pass/fail sheet is §1 of [`TESTPLAN-3.3.md`](TESTPLAN-3.3.md).

**Six of nine pass completely — 18 of 18 phrases.** Open Lineup, Fill Lineup, My Rules, Rest Days, Game Recap, Pitch Limits. That includes Game Recap and Pitch Limits, which *failed* on 2 Aug and are genuinely fixed.

**The three that don't are exactly the three with an entity slot:**

| Shortcut | Result |
|---|---|
| `OpenPlayerIntent` | 0 of 3 — never routed to the app once |
| `OpenTeamIntent` | Routes inconsistently; when it routes, works via a picker |
| `PitchEligibilityIntent` | Trailing form works via a picker; both leading forms go to web search |

**Correction to what this item used to say:** it named **two** voice-only intents. It's **three** — `OpenTeamIntent` qualifies identically, every one of its phrases carries an entity slot. This item's own list of six parameter-free tiles implied it (9 − 6 = 3), and the device results land on exactly that boundary.

**What a log capture proved (7 Aug, `idevicesyslog` against the device).** Across four representative phrases, including the two that *worked*: **zero `Player lookup:` and zero `Team lookup:` lines.** `entities(matching:)` is never called. Siri matches the phrase, routes to the intent, and then treats the parameter as **unfilled** — the picker is the framework falling back to `suggestedEntities()`, which is why it lists the whole roster instead of a narrowed match.

So the spoken name never reaches this code at all. Not mistranscribed, not unmatched — discarded upstream. Three things follow:

- **`PlayerSearch` / `TeamSearch` are dead on the voice path.** Still live for Shortcuts and typed Spotlight. **Don't delete them and don't tune them** — see 4.6.
- **The 2 Aug rework can't be credited for the two fixes.** One success was a *trailing* phrase and one a *leading* one, so placement doesn't explain the split. "Test Team" routed in both forms while "10u All Stars", "Rockhounds" and "Drew Santos" didn't. Routing is inconsistent and placement isn't the variable. The parameter-free fixes are better explained by `INAlternativeAppNames`, added the same day.
- **New, minor:** "switch my team to" draws an app-disambiguation prompt against Wallet.

**Decision — ship 3.3 as-is.** Six shortcuts are flawless. The three entity ones, when they route, degrade to a picker that still answers in two taps. Degraded, not broken. Chasing Siri's slot-binding is unbounded work on a platform behavior you don't control.

> **Before anyone spends more effort on phrasing, re-run §1 on an iOS 27 beta.** The iOS 27 Siri is rebuilt on Apple Intelligence and is meant to resolve spoken references to entities — the exact thing failing here. Tuning phrases against iOS 26's template matcher is likely to be wasted work, and the 2 Aug rework is the cautionary example: a good theory the device disproved. See **4.6**.

**Done when:** ~~each of the nine phrases spoken and the right thing happens~~ — met for 6 of 9. The remaining three are **accepted as picker-degraded for 3.3**, not fixed and not deferred silently.

**Size:** M. **Closed 7 Aug** on the terms above.

### ~~1.4 Verify iPad read-only with a real shared team~~ — ✅ all 8 steps pass, 8 Aug 2026

**Source:** `CLEANUP-AUDIT-2026-08.md` §2.4a and its test plan.

Before the 6 Aug fix, a view-only participant on iPad could reassign positions, reorder the batting order, clear positions and finalize the lineup — which notifies the whole team. `iPadDashboardView` had no read-only enforcement at all.

**Run on device 8 Aug 2026.** The assistant's device created the team and granted read-only; the iPad ran the reworked build. **All eight steps pass.**

- **Steps 1–6 — the gate engages.** Banner and strip, By Inning, By Position, Pitching, sidebar, and Clear positions all held read-only exactly as specified.
- **Step 7 — the gate releases.** The check the audit called the one that matters most. An owned team on the same iPad still edits normally, so the fix did not over-reach and lock a coach out of their own team. Gating is per-team, not per-device, and that is now confirmed rather than assumed.
- **Step 8 — cosmetics.** The unified `PlayerChip` reads as one component on both devices.

**2.4a is confirmed in both directions.** It was the largest finding in the August audit and the only one that had never been exercised on hardware.

**Note on the run:** the view-only share this needed could not be created at all until 1.7 landed — `createShare` forced every share back to read-write.

**Left deliberately out of this item:** the push test that used to hang off it. It is not part of 2.4a and was being tracked in three places at once; it now lives in **1.7 step 12**, with the build-environment caveat attached. See also 1.2's standing caveat that APNs has never delivered a real push.

**Open question about the 8 Aug run, carried to 1.7:** which build type each device ran. If the iPad ran an Xcode build while the assistant's phone was on TestFlight, the two were in different CloudKit environments and the iPad was reading a locally cached copy rather than a live share. **The result above stands either way** — the gating reads `isReadOnly` off local state — but the sync path would not have been exercised, and 1.7's steps 9–13 depend on it.

### 1.7 Verify the reworked sharing surface on device

**Written 8 Aug 2026.** Device testing on 7 Aug found the Shared Team surface broken in four separate ways. All four are fixed in code; none of the fixes can be confirmed without a real iCloud account and a second one to accept with.

**What was wrong, and where.**

1. **"Shared" meant nothing.** The badge and the Manage Access row were both gated on `ckRecordName != nil`, which only ever meant "this team reached iCloud". Every synced team therefore read as shared and offered access management for a share that did not exist. Nothing on `Team` recorded owner-side share state at all — `isSharedParticipant` is the receiving side.
2. **"Couldn't Prepare Share — Record not found"** was the same bug one step later. Manage Access called `createShare`, which fetches the record first; the team held a `ckRecordName` for a record the server did not have. The alert also printed `error.localizedDescription` raw, so a coach saw a `CKRecordID` and a pointer address.
3. **`UICloudSharingController` could not be made presentable.** Generic document icon, an "(Owner)" row for the coach themselves with no name attached — CloudKit has no discoverable name for your own identity — and no way to configure any of it.
4. **View Only did save, and then got overwritten.** `createShare` unconditionally forced `publicPermission` back to `.readWrite` on every call. The comment said it was repairing legacy shares stuck at `.none`; because it was unconditional it also reverted every deliberate `.readOnly`. **This is what made 1.4 impossible** — a view-only participant could not be created, because the share was forced back to read-write before the invite went out.

**What replaced it.** One `Assistant Coaches` row under a `Sharing` header in Edit Team, pushing `TeamSharingView.swift` — a native screen covering invite, participant list, per-participant permission, link permission, and stop sharing. `UICloudSharingController` is gone; the system share sheet is kept only for sending the link. `CloudKitManager` now splits `shareInfo(for:)` (read, never mutates) from `createShare(for:permission:)`, and returns Sendable `TeamShareInfo` snapshots so no `CKShare` reaches the view layer. The legacy repair survives but only fires on `.none`/`.unknown`. `CKError` is mapped to coach-readable copy via `CloudKitManager.friendlyMessage(for:)`.

**Verified in the simulator on 8 Aug:** all four screen states render — not-synced, not-shared, shared with two participants, participant detail. That is layout only. **Everything below needs hardware.**

**On device, with a second iCloud account:**

1. Owning account: open Edit Team → Sharing. The row should read **Not shared**, not "Shared". This is the regression that started all of this.
2. Tap in, choose **View only**, tap Invite. Send the link to the second account.
3. Accept on the second device. Back on the owner: the coach appears with a real name or email, and **View only** — confirm it does *not* silently read "Can edit". That single check is bug 4.
4. Reopen Edit Team. The row now reads **1 coach**. Reopen sharing — the permission is still View only after a round trip. Bug 4 only showed itself on the second visit.
5. Change the participant to Can edit, pop back, reopen. It sticks.
6. Change the **link** permission and confirm the already-joined coach is unaffected — the two are separate in CloudKit and the screen claims they are.
7. Remove the coach. Then Stop Sharing. The team, roster, and history all survive on the owner's device.
8. **Stale record path:** this is the one that produced the original alert and is worth forcing. Delete the team's record from the CloudKit dashboard while the app holds its `ckRecordName`, then open sharing. Expect the plain "This team isn't in iCloud yet" screen and a cleared record name — not a `CKRecordID` in an alert.

**Then run 1.4 against the view-only share from step 2** rather than making a second one.

**Blocked on:** a second iCloud account, and — for the push steps only — a TestFlight build. **Size:** M.

#### Xcode builds cover most of this; the push steps need TestFlight

Direct-from-Xcode installs are fine for everything except push, and are worth using: the loop is a rebuild rather than a TestFlight round trip, and running from Xcode picks up the scheme's `.storekit` config, so Pro works without the simctl workaround.

**All three devices must run the same build type.** CloudKit sharing is per-environment — Xcode builds talk to **Development**, TestFlight to **Production** — and a share created in one is not visible in the other at all. Not stale, not read-only: invisible. Mixing build types across the three devices is the fastest way to produce a failure that looks like a sharing bug and isn't.

**Push cannot work from an Xcode build against the current Worker**, for two independent reasons:

1. The Worker runs `CLOUDKIT_ENV = production` (see 1.2). A Debug build writes its `DeviceToken` records to Development, so the Worker's query matches nothing and it returns before ever contacting Apple.
2. `aps-environment` is `development` in the entitlements, so a Debug build registers against **sandbox** APNs. Those tokens are invalid for `api.push.apple.com`, which is the host 1.2 deployed.

Either one alone produces silence that looks exactly like a Worker fault — the failure 1.5a warns costs the most time. Repointing the Worker at Development + `api.sandbox.push.apple.com` would work but means two redeploys and risks leaving it in the state 1.2 just fixed. Not worth it.

**So:** steps 1–11 and all of 1.4 except its push step from Xcode; steps 12–13 and 1.4's push step from a TestFlight build. That TestFlight pass is needed for 1.5a anyway.

#### 8 Aug, second device round — three more, all on the receiving side

The first device test covered the owner. Sharing *to* this device found three separate faults, two of which share a cause.

**a. A received team rendered "This team isn't in iCloud yet".** `shareInfo(for:)` always read `privateDB`. A participant's record isn't there — it lives in the owner's zone in the **shared** database — so the fetch threw `unknownItem` and the screen reported the team as unsynced. Worse, that path then called `clearStaleRecordName`, wiping the record name the shared-database merge uses to match the local copy.

Fixed by branching on `isSharedParticipant` into a new `.participant` state that names the head coach and states this coach's own access, and by never clearing a record name for a received team. The share is cached during `fetchSharedTeams`, which is the only place the owner's zone is enumerated.

**b. Accepting an invite left the team in the background — and cost the push.** `SceneDelegate` posted `.cloudKitShareAccepted` through NotificationCenter and nothing held it. Tapping an invite usually **cold-starts** the app, and the accept callback lands before `ContentView` subscribes, so the post went to nobody: no fetch, no `switchTeam`, and the team surfaced later via ordinary sync without becoming active.

`switchTeam` is also what calls `refreshTokenForCurrentTeam`. **So the dropped notification explains the missing notification too** — the switch never ran, so this device never registered a token for that team. Fixed with `PendingShareAcceptance`, a durable hand-off both the running and cold-launch paths drain exactly once.

**c. Device tokens were only ever written at launch or on switch.** `didRegister` iterates the teams that exist *at that moment*; `refreshTokenForCurrentTeam` covers the active team. A team that arrives mid-session had no `DeviceToken` record at all, so the Worker had nothing to push to. Now registered when a shared team is appended in `mergeCloudKitChanges` — a coach can be sent a team, never open it, and still expect to hear when the lineup is final.

**The build version was a red herring.** The iPad received the finalize push on an old build and the iPhone didn't on the new one; the variable was not the version but *when each device acquired the team relative to its last cold start*. The iPad had it from a previous session, so its launch-time registration covered it.

**Extra device steps, on the receiving device:**

9. Accept an invite with the app **fully closed** — not backgrounded. The team should be active and in front when the app opens, not sitting in the switcher.
10. On that team, open Edit Team → Sharing. The row reads **Shared With You**, and the screen names the head coach and your access level. This is the screenshot from 8 Aug.
11. Confirm the received team still has its `ckRecordName` after visiting that screen — bug (a) silently cleared it.
12. Without relaunching, have the owner finalize a lineup. **The push must arrive on the newly joined device.** That is bugs (b) and (c) together and is the one that needs no relaunch to be a fair test.
13. Repeat 12 after a cold start, to confirm the launch-time path still works.

### ~~1.6 The What's New sheet quotes Siri phrases that can't work~~ — ✅ rewritten 7 Aug 2026

**Fixed in `WhatsNewView.swift`.** Every quoted phrase is now one that passed on device 7 Aug, with the app name in it. "Can Jake pitch?" is gone — it pointed at `PitchEligibilityIntent`, which fails even when phrased correctly. The untested "Players and teams turn up in Search now too" claim is dropped until someone verifies it; it slots back onto the end of feature 1 unchanged if it holds.

The load-bearing change is that feature 1 now **states the app-name rule once**: *"Siri needs to hear the app's name, so keep it in the sentence."* That single sentence is what stops a coach concluding the feature is broken when a bare question falls through to a web search.

Build 35 still carries the old copy. **This reaches coaches in build 36.**

---

*Original finding, kept for the reasoning:*

**Source:** found 7 Aug reading `WhatsNewView.swift` against the 1.3 device results. **This is already in the shipping build** — build 35 contains this copy, so fixing it means a code change and build 36.

**Every Siri phrase quoted in the 3.3 entry omits the app name.** An `AppShortcut` phrase is *required* to contain `\(.applicationName)` — the framework rejects a provider without it at build time. So none of these are registered phrases, and a coach who says them verbatim gets nothing:

| Quoted in What's New | Registered phrase | Works? |
|---|---|---|
| "What's my pitch limit?" | "**In Stack the Lineup,** what's my pitch limit" | ✅ with app name |
| "How many days rest?" | "How many days rest **in Stack the Lineup**" | ✅ with app name |
| "How did we do?" | "**In Stack the Lineup,** how did we do" | ✅ with app name |
| "Can Jake pitch?" | "**In Stack the Lineup,** can ⟨player⟩ pitch" | ❌ **see below** |
| "Open Stack the Lineup" | same | ✅ — the one that's already right |

**"Can Jake pitch?" is the worst of the five**, and not only for the missing app name. It's `PitchEligibilityIntent`, one of the three entity-slot intents that 1.3 found picker-degraded: the leading form goes to web search, and only the trailing form works — after Siri lists the entire roster to pick from. Quoting it as a one-liner promises something that doesn't happen even when phrased correctly.

There's a second-order problem. The copy teaches coaches that bare questions work. When "What's my pitch limit?" returns a web search, the reasonable conclusion is *the Siri feature is broken*, not *I needed to say the app name* — so the copy actively creates the impression of a broken feature out of one that mostly works well.

**Fix:** rewrite the quoted examples using only phrases confirmed working on 7 Aug, with the app name included, and drop "Can Jake pitch?" until the entity path is solid (see 1.3, 4.6). Everything else in the three feature blocks is accurate — "Open Stack the Lineup" is already correct, and the Pro gating on Game Recap is right.

⚠️ **Check "Players and teams turn up in Search now too"** in the same entry while you're there. That's Spotlight indexing via `IndexedEntity`, a different mechanism from the voice path, and 1.3 didn't test it. Verify before shipping the claim.

**Size:** S — copy only, no logic. But it's user-facing text in a shipping build, so it rides on 36.

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

> 🔁 **The trap below fired, on 6–7 Aug, at the archive.** Bumping the build from 34 in **General → Identity** wrote `CURRENT_PROJECT_VERSION = 35` as a *target-level* override on the app (both configs) while the widget kept inheriting the project-level 34. Spotted by diffing `project.pbxproj`, not by anything Xcode said: each target's General tab shows its own resolved value and they simply disagree, with **no warning anywhere**. Re-fixed by setting the project level to 36 and deleting both overrides.
>
> **But it did not fail validation, and that's the useful part.** Build 35 archived and uploaded to TestFlight with the widget at 34, and App Store Connect took it. The difference from the original bug: in 35 the *marketing* version matched (`3.3` on both) and only `CFBundleVersion` differed. The bug this item was opened for had widget `1` / `1.0` against app `34` / `3.3` — **the marketing version differed too**, which is the case that actually gets rejected. Treat "App Store Connect rejects that at validation" above as accurate for a `MARKETING_VERSION` mismatch and unproven for a build-number-only one.
>
> TestFlight 35 is therefore a usable test build; the widget version is cosmetic and nothing in [`TESTPLAN-3.3.md`](TESTPLAN-3.3.md) exercises the widget. **36 exists because TestFlight won't accept a build number twice**, so the next upload has to be 36 regardless — and it will have a matching widget.
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

### ~~2.3 The one unverified tip transition~~ — ❌ **failed on device 7 Aug 2026**

**Source:** `TIPS-onboarding-spec.md`, "Not verified / still open." Expected to be confirmation rather than investigation. It was investigation.

**What happens.** In History, `HistorySeasonViewsTip` ("Your season is building") and `HistoryCopyGameTip` ("Or start from a game you played") both present. Dismissing tip 2 with **Next** produces nothing. **Quitting the app and returning shows tip 3** ("Don't build that twice") on the Save-as-template row.

So tip 2 *is* invalidated and tip 3 *does* become the group's current tip — the live in-place advance is what fails. Exactly the thing the spec flagged as never re-verified: the fix was *"verified via the seed path… the live in-place advance was not re-verified on device."* The seed path turns out to be the only path.

**Ruled out on the way** — all cheap, all checked in code before touching the device:

- All three history tips carry **identical** rules (`hasArchivedGame`, `isPro`), so tip 3 isn't filtered
- `displayFrequency` is `.immediate`, so it isn't rate-limited
- The Save-as-template row renders **unconditionally** — the anchor always exists
- `TourTipModifier` calls `tip?.invalidate(reason: .actionPerformed)`, which is what advances an ordered group

**Cause.** The two History screens are the only ones using the `currentTipUpdates` → `@State` mirror. Every screen whose arc advances in place reads `currentTip` synchronously in the body:

| Screen | Pattern | Live advance |
|---|---|---|
| `LineupView`, `PlayersView`, `DefensiveGridView` | synchronous `Tour.<group>.currentTip` | ✅ works |
| `GameLogsView`, `GameLogDetailView` | `currentTipUpdates` → `@State` mirror | ❌ fails |

`currentTipUpdates` appears not to yield when the current tip is **invalidated** while the view stays alive, so nothing updates the mirror. Re-entering re-runs the `.task`, which re-seeds from `currentTip` — hence the quit-and-return behaviour. The mirror was added to fix a *first-render* bug (the tip missing on landing) and it does fix that; it just doesn't cover the advance. The other screens get away with the synchronous read because ordinary interaction re-renders them constantly and they pick up the new `currentTip` incidentally. The History screens are static enough that they don't.

**Impact: the tip is deferred, not lost.** "Don't build that twice" appears the next time the coach opens any archived game's detail view. It's the last tip in arc 2's Pro path, so nothing stalls behind it.

**Not fixed for 3.3 — deliberately.** See **3.4**. Both candidate fixes are speculative against TipKit internals and need another device round-trip; the payoff is a tip arriving now rather than on the next visit. Not a trade worth making on the release being closed.

### ~~2.4 Read the tip copy at real size~~ — ✅ **passed 7 Aug 2026**

**Source:** `TIPS-onboarding-spec.md`, Open questions.

**Walked on device at large Dynamic Type, after a "Take the Tour" reset, across every tip. Nothing truncates, wraps badly, or overflows its popover. No copy needs trimming.**

That closes both halves of the question. Default Dynamic Type was already confirmed in the 24 Jul walk (`TIPS-onboarding-spec.md` line 24, "copy reads cleanly at default Dynamic Type"); large type was the outstanding half and is now done on real hardware.

The concern behind this item — that popover width is narrower than the spec tables suggest — turned out not to bite. Worth knowing for future copy: the four longest strings in the app all clear a maximum-size popover, so **112 characters is a demonstrated safe ceiling** rather than a guess.

| Chars | Tip |
|---|---|
| 112 | `PlayersTeamSetupTip` — "Tap your team name for color, game length…" |
| 107 | `HistorySeasonViewsTip` — "Players for season stats, Team for roster coverage…" |
| 103 | `ReuseApplyTemplateTip` — "Pick your template when you set the next game…" |
| 100 | `HistoryCopyGameTip` — "Open any archived game and copy its lineup…" |

**Size:** S. **Closed 7 Aug.**

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

### 3.4 The TipKit live advance on the History screens

**Source:** 2.3, failed on device 7 Aug 2026. Full diagnosis is there; this item is just the fix.

*(Numbered 3.4 rather than 3.3 so no item number collides with the release version.)*

Dismissing a tip on `GameLogsView` or `GameLogDetailView` doesn't advance the group in place. The next tip only appears on re-entry, when `.task` re-seeds the mirror from `Tour.history.currentTip`.

**Two candidate fixes, neither obviously right:**

1. **Re-read `currentTip` after the action fires.** `TourTipModifier` invalidates but doesn't know its group, so this needs a hook — an optional `onAdvance` closure on `tourTip(_:)` that lets the call site refresh its own mirror. The catch: `currentTip` lags a cycle after a status change, so a naive re-read returns the tip that was just dismissed. Probably needs a delay, and a delay tuned by trial is the kind of fix that works on one device and not another.
2. **Move both screens to the synchronous read** that every working screen uses. Simpler and consistent — but it reintroduces the first-render bug the mirror was added to fix, where the tip is missing on landing until an unrelated re-render. That bug was worse than this one.

A third option worth ten minutes first: find out whether `currentTipUpdates` yields on invalidation at all, or only on eligibility changes. If it genuinely never yields on invalidation, option 1 is the only real candidate and option 2 is a regression waiting to happen.

**Verify on a device, not the simulator** — 2.3 was called "confirmation, not investigation" on the strength of a simulator-verified pattern, and the device disagreed.

**Size:** M. Small diff, most of the cost in figuring out which fix is real and proving it.

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

### 4.6 iOS 27 App Intents readiness

**Source:** WWDC 2026, read on 7 Aug against the 1.3 device results. Not verified against a beta — see the caveat at the end.

**The good news first: nothing here is on a deprecation path.** WWDC 2026 deprecated SiriKit outright and made App Intents the only route into Siri, with a two-to-three-year migration window. This app is already all App Intents. There is no migration to do.

What's open is *adoption*, and it matters because it's the most plausible fix for the one thing 1.3 couldn't solve. The iOS 27 Siri is rebuilt on Apple Intelligence and Apple's framing is that it resolves spoken references to real entities — which is precisely the sentence that isn't true today. 1.3 proved Siri never binds a spoken name into a phrase slot at all. That's a template-parser limitation, and a reasoning-based router is the thing that removes it.

Two concrete gaps, checked in the code on 7 Aug:

1. **No `indexingKey` anywhere.** `PlayerEntity` and `TeamEntity` already conform to `IndexedEntity` — that part is done — but no properties are marked as searchable. Small, safe, and it pays off on iOS 26 for Spotlight regardless of what iOS 27 turns out to do. **Do this one first; it stands on its own.**
2. **No App Schema conformance.** The iOS 27 guidance is to conform entities to a schema so Siri understands the *category* of content. ⚠️ **Open question: whether a schema exists that fits a youth-sports roster.** The schema list is domain-specific. If nothing fits, this lever may not be available at all, and that's worth ten minutes of checking before anyone plans around it.

**Keep `PlayerSearch` and `TeamSearch`.** 1.3 established they're dead on the voice path — Siri never calls `entities(matching:)`. Do **not** conclude they should be deleted. `EntityStringQuery` is explicitly retained in iOS 27 for live state that can't be pre-indexed, which is exactly a roster that changes weekly. That code is the part a smarter Siri would finally start calling. Leave it alone and don't tune it either — tuning a matcher nothing calls is how you spend a day for nothing.

> ⚠️ **This is read from session titles and secondary coverage, not from observed behavior.** No one has run this app against an iOS 27 beta. The 2 Aug phrase rework was also a well-reasoned theory that the device contradicted — see 1.3. Treat the whole item as a hypothesis until §1 of [`TESTPLAN-3.3.md`](TESTPLAN-3.3.md) is re-run on a beta.

**Size: M.** Not for a release cycle. `indexingKey` alone is S and could go any time.

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
