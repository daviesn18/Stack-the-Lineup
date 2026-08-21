# Backlog — Stack the Lineup

**Created 6 Aug 2026. Last updated 17 Aug 2026 (build 41 verified on device — every open item is closed. `3.3 (41)` is ready to submit to the App Store).** One place for everything open across the working documents in this repo, in the order I'd do it. Each item says where it's written down, what "done" looks like, and what it's blocked on — so nothing here needs you to re-read a 60 KB handoff to know what it is.

**The spine is the 3.3 submission.** Version is `3.3 (41)` and `WhatsNewContent` has its 3.3 entry. Stages 1 and 2 are both empty — everything after that is deferred by choice and should stay deferred until 3.3 is out.

---

## ▶ Start here

**Push works on real hardware, both directions, as of 12 Aug 2026.** That closes the longest-running thread in this file. It took five separate faults to get there — 1.2 (the Worker's CloudKit auth), 1.9 (the cold-launch token race), 1.11 fix 1 (an exclusion rule keyed on a display name that is "iPhone" on every device), and the two sharing bugs (b) and (c) under 1.7 — and no single one of them was visible from the others. **~~1.7~~, ~~1.9~~, ~~1.10~~ and 1.11's delivery half are all closed on build 39.**

**Nothing is open. Build 41 is verified on device and `3.3 (41)` is ready to submit.**

Build 40 went to TestFlight on 17 Aug and both remaining device passes ran against it in Production CloudKit. **~~1.12~~ passes** — an assistant is asked their name when they join, and the head coach's notification and "Finalized by" both read it, which closes the display-name half of **~~1.11~~** and with it the whole push-identity thread. **~~1.13~~ passes**, airplane-mode step included: a deleted or unshared team leaves the assistant's device with a notice, and a shared fetch that *throws* leaves every received team alone.

Also in 40: **~~3.9~~**, fixed 17 Aug — the subscription disclosure no longer truncates at the paywall's opening detent. It was the one open item that could have mattered to App Review, and it landed before the archive, so the build number never moved. **~~3.6~~ closed 12 Aug** — several clean seeds on TestFlight. **~~3.8~~** fixed the iPad peek detent.

**~~3.10~~ is fixed and verified on build 41.** A tapped push opened the app without switching to the team it was about. The Worker turned out to need nothing — it has always sent `teamID` — so this was app-only. Fixing it also turned up a second, larger fault the first fix hid: the notification delegate was installed too late to receive a **cold-launch** tap, so the routing worked on a backgrounded app and did nothing on a terminated one, which is the common case. **Both paths pass on device, cold start included.**

**Build 41 went to TestFlight on 17 Aug and its device check passed**, warm and cold. That was the last thing standing between this file and the App Store: **nothing here blocks the submission.** Everything remaining is Stage 3 and Stage 4, deferred by choice until 3.3 is out. **4.5 (Swift 6 language mode) landed 20 Aug** — all four targets are on Swift 6. The next cheap-early item is **4.3**, the paywall's Dynamic Type pass, which the 3.9 work showed is larger than a colour calibration.

> **Three Stage 4 decisions were taken on 20 Aug 2026**, which is what they were waiting on rather than any engineering. **~~4.2~~** — no change, the free-tier upsell tip is rejected and principle 3 stands. **~~4.7~~** — **keep the Worker**; the trade was evaluated on its merits and settled, so do not reopen it after the next bad push day. **~~4.1~~** — a Pro coach must never see a paywall, and acting on that turned a product question into a real fix: eight gates were testing `!isPro`, which is `true` while StoreKit is still `.undetermined`. Read 4.1 before writing any new entitlement check.

> **Standing decision, 12 Aug 2026: device testing happens on TestFlight, not on Xcode builds.** Taken after the 11–12 Aug session, and it retires a recurring source of wasted time rather than a single bug.
>
> CloudKit sharing is per-environment — Xcode builds talk to **Development**, TestFlight to **Production** — and a share created in one is invisible in the other. Push cannot work from a Debug build at all, for two independent reasons (see the subsection under 1.7). The KV-store path that 3.6 turns on is `#if !DEBUG`. Three separate mechanisms behave differently, and every one of them fails in a way that reads as an app bug.
>
> It has already cost real time twice: **1.4 closed with an open question about which build type each device ran**, which is why its result had to be qualified, and 3.6's one data point came from a Debug build where the mechanism it blames is compiled out. Neither ambiguity can arise again under this rule.
>
> **The cost, accepted:** the loop is a TestFlight round trip rather than a rebuild, and Pro needs the simctl workaround or a run from Xcode instead of the scheme's `.storekit` config. Worth it — a failure you can trust is cheaper than a fast one you can't.

> ⚠️ **1.13's device pass has a step that is easy to skip and is the one that matters:** put the assistant's device in airplane mode and foreground the app. A thrown shared fetch must leave every shared team alone. The failure mode if that guard is wrong is every received team disappearing the first time iCloud is unreachable — a worse bug than the one being fixed.

**Decisions made on 8 Aug that are not derivable from the code** are recorded in [`PAYWALL-design-handoff.md`](PAYWALL-design-handoff.md) under "What a shared team's recipient pays for" — who pays for what on a shared team, and the accepted consequence that one Pro coach can equip any number of free read-write assistants.

> **What the 11–12 Aug session settled.** The Worker's 1.11 half was deployed (`88f4db3`), build 39 went to TestFlight, and the sharing surface was walked end to end on three devices. Pushes arrive in both directions, on a cold-launched device and on a warm one. 1.10's honest-UI rework was confirmed on screen: link permission is the single authority and says so.
>
> **The one habit that paid off:** 1.11 was found by reading the Worker's own log rather than inferring from the app. `Sending to 0 recipient(s) after filtering out iPhone` is a sentence no amount of app-side debugging would have produced.

State of the repo: `main` is at `9cb6625` and **pushed** — `0a34cd3` the 3.10 routing fix, `fff1c60` the build 41 bump, `68b2407` and `9cb6625` documentation. Earlier in the thread: `9a8e5dc` the 1.11 app-side fix and `6f585fd` the coach-name prompt.

**`feature/app-intents-phase-0` is gone**, deleted 20 Aug 2026 — `git branch --merged` showed it fully contained in `main` with a zero-line diff, so the decision it was waiting on had already made itself. `fix/pitching-window-sunday` and `claude/little-league-pitching-rules-hn7237` went the same way for the same reason. Suite green — **336 of 336**, measured 20 Aug (it was 322 when 3.7 restored it on 9 Aug; fourteen have been added since). Static analyzer clean. A Release build emits 14 warnings, all pre-existing and none blocking — see the correction under 1.1 and item 4.5. The Worker lives in its own repo now — [`daviesn18/stl-worker`](https://github.com/daviesn18/stl-worker), private — with its own README covering the push architecture.

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
| ~~1.5~~ | ~~Is the shipped build's push environment `production`?~~ | — | ✅ **9 Aug** — `production` on the exported IPA; coverage settled 7 Aug |
| ~~1.6~~ | ~~What's New quotes Siri phrases that can't work~~ | — | ✅ **7 Aug** — copy rewritten; ships in 36 |
| ~~1.7~~ | ~~Verify the reworked sharing surface on device~~ | — | ✅ **12 Aug** — all steps pass on build 39, push included |
| ~~1.8~~ | ~~iPad nav bar read-only gating~~ | — | ✅ **9 Aug** — step 9 passes both ways on device |
| ~~1.9~~ | ~~A cold-launched device never registers for push~~ | — | ✅ **12 Aug** — token cached before any view exists; verified on repeated cold launches |
| ~~1.10~~ | ~~Link permission overrides an assistant's own permission~~ | — | ✅ **12 Aug** — honest UI confirmed on device |
| ~~1.11~~ | ~~Push identity is a display name, and every device's is "iPhone"~~ | — | ✅ **17 Aug** — delivery fix 12 Aug, display-name half closed with 1.12 |
| ~~1.12~~ | ~~An assistant is never asked their name when they join~~ | — | ✅ **17 Aug** — all steps pass on build 40 |
| ~~1.13~~ | ~~A team the head coach deletes never leaves the assistant's device~~ | — | ✅ **17 Aug** — all steps pass on build 40, airplane mode included |
| **Stage 2 — cheap while you're already on a device** ||||
| ~~2.1~~ | ~~`LineupView` titled "Lineup Builder"~~ | — | ✅ **6 Aug** |
| ~~2.2~~ | ~~Keep the `PRODUCT_NAME` rename?~~ | — | ✅ **6 Aug** — decided: keeping it |
| ~~2.3~~ | ~~`ReuseSaveTemplateTip` live advance~~ | — | ❌ **7 Aug — failed on device.** Cause found; fix is **3.4** |
| ~~2.4~~ | ~~Tip copy at real size / large Dynamic Type~~ | — | ✅ **7 Aug** — all tips walked at large type; nothing truncates |
| **Stage 3 — deferred engineering (after 3.3 ships)** ||||
| ~~3.0~~ | ~~Calendar-week window is empty on Sundays~~ | — | ✅ **6 Aug** — found and fixed; 4 copies now share one derivation |
| ~~3.1~~ | ~~`PositionSummaryView.pitchingRows()` — third copy of the pitch maths~~ | — | ✅ **20 Aug** — folded into `PitchEligibilityEngine.pitchingSummaryRows`; numbers unchanged |
| 3.2 | Debounced CloudKit push | M | A design pass, not a cleanup |
| 3.4 | TipKit live advance on the History screens (from 2.3) | M | A device round-trip to verify any fix |
| ~~3.10~~ | ~~Tapping a push lands on whatever team was already open~~ | — | ✅ **17 Aug** — app-only fix; warm and cold launch both pass on device (build 41) |
| ~~3.5~~ | ~~iPad has no PDF export at all~~ | — | ✅ **8 Aug** — built and pulled into 3.3; locked path unverified at iPad size |
| ~~3.6~~ | ~~A seed produced no team; cause unknown~~ | — | ✅ **12 Aug** — several clean seeds on TestFlight; closed unreproduced, tripwire left armed |
| ~~3.7~~ | ~~Two `STLRouteTests` fail — the suite is not green~~ | — | ✅ **9 Aug** — isolated deinit crash; 322/322 now |
| **Stage 4 — decisions and long poles** ||||
| ~~3.8~~ | ~~`ProGate` is broken at iPad size~~ | — | ✅ **12 Aug** — peek detent is compact-width only now; verified in the simulator |
| ~~3.9~~ | ~~Subscription terms truncate mid-word at the paywall's default detent~~ | — | ✅ **17 Aug** — the disclosure is incompressible now; verified at the peek in the simulator |
| ~~4.1~~ | ~~History paywall auto-opens~~ | — | ✅ **20 Aug** — decided: a Pro coach never sees a paywall; 8 gates fixed |
| ~~4.2~~ | ~~Arc 2 gives free coaches 2 tips of 6~~ | — | ✅ **20 Aug** — decided: no change, principle 3 stands |
| 4.3 | Paywall dark mode + Dynamic Type calibration | S | Design |
| 4.4 | Localization / string catalog | **L** | A design decision on assembled strings |
| ~~4.5~~ | ~~Swift 6 language mode~~ | — | ✅ **20 Aug** — all four targets on Swift 6; pure types marked `nonisolated`; 340/0 |
| 4.6 | iOS 27 App Intents readiness — `indexingKey`, App Schemas | M | An iOS 27 beta to verify against |
| ~~4.7~~ | ~~Should `CKSubscription` replace the Worker entirely?~~ | — | ✅ **20 Aug** — decided: **keep the Worker** |

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

> **Resolved 12 Aug 2026.** The question below was whether the sync path had actually been exercised, or whether the iPad had been reading a locally cached copy. It no longer matters: **1.7's steps 9–13 passed on TestFlight build 39 with all three devices in Production CloudKit**, which exercises that path directly. The ambiguity itself is retired by the standing decision under ▶ Start here — this is one of the two times it cost real time.

**Open question about the 8 Aug run, carried to 1.7:** which build type each device ran. If the iPad ran an Xcode build while the assistant's phone was on TestFlight, the two were in different CloudKit environments and the iPad was reading a locally cached copy rather than a live share. **The result above stands either way** — the gating reads `isReadOnly` off local state — but the sync path would not have been exercised, and 1.7's steps 9–13 depend on it.

### ~~1.8 The iPad nav bar has no read-only gating~~ — ✅ **step 9 passes both ways on device, 9 Aug 2026**

**Found and fixed 8 Aug 2026, reading `iPadDashboardView.swift` while scoping 3.5.** Same class as 2.4a, and it survived both the fix and the device test.

> **Fixed and verified.** Import Schedule and Archive Game are now wrapped in `if !isReadOnly` in `iPadNavBar`, matching `LineupView`. The new Export menu is deliberately outside that guard. **Step 9 ran on device 9 Aug 2026 and passes in both directions** — the two buttons are absent on a shared read-only team and come back on a team the coach owns.

`iPadNavBar` (lines 149–309) contains **zero** references to `isReadOnly`. The 6 Aug fix gated `SidebarRosterView` (740), `DetailPaneView` (1008) and `iPadPositionsPane` (1255) — every surface the test plan walks — and never touched the bar above them.

So a view-only participant on iPad can still tap:

| Button | What it does | iPhone |
|---|---|---|
| **Import Schedule** (line 253) | `mergeScheduledGames` + `setCalendarSubscriptionURL` — writes to the shared team and syncs back to the head coach | Gated: `LineupView` wraps both in `if !isReadOnly` |
| **Archive Game** (line 264) | Opens the archive flow, which writes a `GameLog` and clears the lineup | Gated, same block |

Neither `ArchiveGameSheet` nor `ScheduleImportView` guards internally — confirmed, both are clean of `isReadOnly`. iPhone gates them at the call site, which is exactly the pattern 2.4a's write-up identified as the trap: *"the picker sheets don't carry their own — iPhone gates their call sites instead."* The same sentence explains this.

**Why the device test passed anyway.** The eight steps cover the banner and strip, By Inning, By Position, Pitching, the sidebar, Clear positions, the owned-team regression, and chip cosmetics. **None of them touch the nav bar.** The plan tested the panes because that is where the fix was; the gap is one level up.

Settings and the team switcher stay — reading and switching are not mutations. The Export menu added by 3.5 also stays: exports must remain reachable for a view-only assistant, which is the entire point of the Coaches Guide unlock.

**Step 9 of the 2.4a plan — ✅ ran 9 Aug 2026:** on the shared read-only team, Import Schedule and Archive Game are **absent** from the iPad nav bar while Export and Settings remain. Switching to a team the coach owns brings both back. Same shape as step 7 — the gate releases as well as engages, so the fix did not over-reach.

**Size:** S. **Closed 9 Aug.**

### ~~1.9 A cold-launched device never registers for push~~ — ✅ **verified on device 12 Aug 2026**

> **Closed on build 39.** Repeated cold launches on the assistant's device show `Received APNs device token` followed by `DeviceToken saved for team …` every time, which is step 11a's bar of three clean launches rather than one lucky one. The fix below is what the device confirmed; the diagnosis is kept because the *shape* of this bug — a launch-time hand-off posted through NotificationCenter with nobody durably holding it — is the one this codebase keeps producing.
>
> **It was necessary and not sufficient.** Fixing this made a token exist; 1.11 was underneath it, filtering that token straight back out. Neither was visible while the other stood.


**Diagnosed 9 Aug 2026 from the device session, fixed the same day.** This is why 1.7 steps 12 and 13 both failed. It is the **second and last** instance of one bug class: a launch-time hand-off posted through NotificationCenter with nobody durably holding it.

> **Correction to what this item first said.** It claimed this was the *fourth* instance, conflating the class with 1.7's "four separate ways" — which were four unrelated sharing faults, only one of them (bug (b), share acceptance) a dropped post. A sweep on 9 Aug found **exactly two `NotificationCenter.default.post` call sites in the whole app**, both in `LineupBuilderApp.swift`: share acceptance, made durable on 8 Aug, and this one, made durable now. **There is no third to hunt for**, and the class is closed rather than merely reduced.

**What the device showed, and why it is conclusive.** The owner finalized and the read-only assistant got nothing. Then the assistant — by then Can edit — finalized, and **the owner did get a notification.** That direction proves the Worker, production APNs, the signing from 1.5, and the owner's own `DeviceToken` record are all healthy. The asymmetry is only explicable if **the assistant's device has no `DeviceToken` record for that team.**

The two directions differ because `triggeredBy` is `team.coachName` (`NotificationManager.swift:114`) and a received team's `coachName` is overwritten with the participant's own device name (`Models.swift:1678`), so the Worker's self-exclusion lands on a different record each way.

**The cause.** `AppDelegate.didRegisterForRemoteNotificationsWithDeviceToken` posts `.apnsTokenReceived` through NotificationCenter (`LineupBuilderApp.swift:75`) and `ContentView.onReceive` is the only listener (`ContentView.swift:292`). On a **cold start** the APNs callback routinely fires before that subscription exists, so the post goes to nobody and `cachedTokenHex` stays `nil` for the whole session. Every writer then no-ops on its own `guard let hex else { return }` — `registerToken`, `refreshTokenForCurrentTeam` and `saveTokenForAllTeams` alike. **No token record is written at all that launch, for any team.**

**Why the 8 Aug fix didn't cover it.** Bug (b) got `PendingShareAcceptance`, a durable hand-off drained exactly once. The APNs post was left on the old pattern — and the 8 Aug write-up of bug (c) reasoned that `didRegister` would cover a mid-session team "when it arrives," which is true only if the token arrives at all.

> **The test instruction is what exposed it.** 1.7 step 9 requires accepting the invite **cold**, to exercise `PendingShareAcceptance`. A warm accept would very likely have passed step 12 and hidden this entirely. Worth remembering when a step looks pedantic.

**Fixed 9 Aug.** The token had no home outside the notification: `cachedTokenHex` was only ever set inside `didRegister`, which needed a `LineupStore`, which needed a view. Receiving is now separated from writing.

- `receiveToken(_:)` takes **no store**, so `AppDelegate` calls it before any view exists and the hex is cached the instant APNs answers. It arms a `needsFlush` flag, held separately from the token because the token stays cached all session and so cannot double as the "still needs writing" signal.
- `flushPendingRegistration(store:)` performs the CloudKit write, guarded on that flag so it is safe to call repeatedly.
- `ContentView` calls the flush from **two** places — `scenePhase == .active`, after `store.load()` so `teams` is populated, and the token notification. Whichever wins does the work; the other finds nothing. Same contract as share acceptance.

**The knock-on matters as much as the direct fix.** `registerToken` and `refreshTokenForCurrentTeam` both guard on `cachedTokenHex`; neither was broken, both were starved. With the token cached immediately, bug (c)'s mid-session registration works for the first time — the other half of why the assistant never heard anything.

**No unit test.** The failure is a launch-ordering race against UIKit and APNs; the test target cannot reach it. **Verification is the device**, below.

**Confirm before fixing** (either is enough, neither needs the CloudKit dashboard):

- Assistant's device on Console: a cold launch should show **no** `Received APNs device token` line, and no `DeviceToken saved for team`.
- Or CloudKit Dashboard → **Production** → Public Database → `DeviceToken`, filtered on `teamID` — one record, not two.

**Size:** M. **Blocked on:** nothing.

### ~~1.10 Changing the link permission overrides an assistant's own permission~~ — ✅ **verified on device 12 Aug 2026**

> **Closed on build 39.** The honest-UI rework holds up on hardware: a participant's access shows as read-only text, the Invite Link section is the single authority, changing it visibly changes an already-joined coach, and Remove Coach still works from the participant row. The escalation is no longer silent because it is no longer denied.
>
> The record below is kept whole. It is the only place that says *why* a screen presents one permission where an earlier one presented two, and the alternative (invite by Apple ID, option 1) is still the route to real per-coach permissions if that trade ever needs revisiting.


**Found 9 Aug 2026 on device, running 1.7 step 6.** The assistant had been set to a specific permission; changing the **link** permission changed *him* too.

**The app's code is innocent, which is what makes this worth writing down.** `setLinkPermission` writes only `share.publicPermission` (`CloudKitManager.swift:829`) and `setPermission` writes only `participant.permission` (`CloudKitManager.swift:852`). Neither touches the other. The bug is in the assumption, stated as fact in the comment above `setLinkPermission`:

> *"Coaches who already accepted keep the permission they joined with — CloudKit stores theirs per participant, which is why the UI states the two separately."*

**The device disproved that comment.** The assistant joined by **tapping a link** rather than being invited by iCloud address, which makes him a *public* participant — and a public participant's access is governed by the share's `publicPermission`. There is no independent per-participant permission for him to keep. The UI presents two separate controls; CloudKit has one.

**Why this is more than a wording problem.** A head coach who sets the link to **Can edit** — to invite a second assistant — **silently grants write access to every link-joined assistant already on the team, including ones deliberately set to View only.** That defeats the read-only guarantee from a screen that never mentions it. 1.4, 1.8 and audit finding 2.4a exist to make view-only mean something; this undoes it from the side.

It also casts doubt on step 5. Setting the participant to Can edit appeared to stick, but on a public participant that may have been `publicPermission` agreeing by coincidence rather than a per-participant value being honoured. **Re-test step 5 with the link set to View only** before trusting it.

> **Decided 9 Aug: option 2, the honest UI — fixed in code, needs a device pass.** The per-participant picker is gone; a participant's access is now shown read-only, and the Invite Link section is the single authority. The false footer is replaced by copy that states the real rule: *"Coaches join by tapping your link, and iCloud gives them all the same access — so changing this changes it for everyone, including coaches who already joined."*
>
> `CloudKitManager.setPermission` is **kept and deliberately unreferenced.** It is correct, and it becomes the mechanism the day coaches are invited by Apple ID — which is option 1 and the only route that makes per-coach permissions real. Delete it if that route is ruled out.
>
> **The cost, accepted:** a team cannot mix a view-only assistant with a can-edit one. Everyone who joins by link shares one level. That was judged the right trade for 3.3 against losing the forward-a-link flow, which the 8 Aug rework chose deliberately.
>
> **On device:** change the link permission with a coach already joined and confirm the screen no longer claims they are unaffected; confirm the participant detail shows access read-only; confirm removing a coach still works. Then re-run 1.7 step 5 knowing the per-participant control is gone — **that step needs rewriting**, since it tests a control that no longer exists.
>
> **The share default stays `.readWrite` — decided 9 Aug, deliberately.** A coach who doesn't touch the picker shares their team as **Can edit**. This was raised because 1.10 makes one value govern everyone who joins by link, so the default now decides more than it did when it looked adjustable per-participant afterwards.
>
> **Kept because read-write assistants are the expected case, not the edge case.** `PAYWALL-design-handoff.md` already accepts that a read-write assistant is a co-coach and that one Pro head coach can equip any number of them. Defaulting to View only would put a tap in front of the common path to protect against a rarer one, and the picker is on screen at invite time either way.
>
> **The accepted consequence:** the least-attention path is also the most permissive one, and access can no longer be narrowed for one person after the fact — only for everyone. If that turns out to bite, the fix is option 1 above (invite by Apple ID), not a change to this default.

**Three ways out, and this is a product decision, not a cleanup:**

1. **Invite by iCloud address.** Participants become private, per-participant permissions become real, and the current UI becomes true. Costs the forward-a-link flow, which the 8 Aug rework deliberately chose — see the comment at `CloudKitManager.swift:804`.
2. **Make the UI honest.** One permission for "anyone with the link", no per-participant control while link sharing is in use. Cheapest, and it stops the silent escalation.
3. **Both:** link sharing for convenience, per-participant control only for address-invited coaches, with the difference stated on screen.

**Worth treating as a 3.3 blocker.** It is a silent privilege escalation on the exact guarantee the release spent two device sessions verifying. That is a judgement call, but it should be made deliberately rather than by shipping.

**Size:** M. **Blocked on:** the decision above.

### ~~1.11 Push identity is a display name, and every device's is "iPhone"~~ — ✅ **both fixes closed 17 Aug 2026**

> **Fix 1 is done and verified.** The app sends `triggeredByToken` (`9a8e5dc`), the Worker excludes on `apnsToken` with a `coachName` fallback for older installs (`stl-worker 88f4db3`, **deployed 12 Aug**), and pushes now arrive on real hardware in both directions. **This is the change that made notifications work at all.**
>
> **The `Fetched 1, not 2` loose end is closed by outcome.** It asked whether a registration gap remained underneath the name collision. Delivery to the assistant now works, which requires their `DeviceToken` record to exist *and* survive the filter — so the answer is that 1.9's fix had already covered it and the collision was the only remaining fault.
>
> **Fix 2 is done too, as of 17 Aug.** Build 39 asked the owner for a real name on both invite paths but never the assistant, which is the direction the name actually travels. Build 40 closes it and **1.12 passed on device** — the head coach's notification and "Finalized by" both read the assistant's real name. Nothing in this item is open.


**Found 10 Aug 2026 from the Worker's own logs**, after 1.9's fix was confirmed working and the notification *still* didn't arrive. Read, not inferred — this is what the Worker printed:

```
Fetched 1 device token(s) for team A5331C3F-CBAD-4975-A4AF-824DDBD24E87
Sending to 0 recipient(s) after filtering out iPhone
```

**One root cause, three symptoms.** The Worker excludes the sender so they aren't notified of their own action (`stl-worker/src/index.ts:55`):

```ts
t => t.coachName.toLowerCase() !== triggeredBy.toLowerCase()
```

`triggeredBy` is `team.coachName`, which is set from `UIDevice.current.name` for both a received team (`Models.swift:1678`) and a new one (`Models.swift:2482`). **Since iOS 16 that API no longer returns the user's device name** — it returns the model, `"iPhone"`, unless the app holds the user-assigned-device-name entitlement, which this one does not.

So every device writes `coachName: "iPhone"`, every event sends `triggeredBy: "iPhone"`, and a rule meant to exclude *one* device excludes *all* of them. Confirmed on both devices: the name reads "iPhone" in the app on the owner's phone and the assistant's.

| Symptom | Where |
|---|---|
| **No push ever arrives on a shared team** | Worker filter, above |
| **"iPhone finalized the lineup for…"** in the notification body | `stl-worker/src/index.ts:144` |
| **"Finalized by iPhone"** in the app | `lastFinalizedBy`, `Models.swift:1806` |

**Why 1.9 looked like the whole story and wasn't.** Yesterday the assistant had no `DeviceToken` record at all, which was real and is fixed. This sat underneath it and could not surface until a token existed to be filtered out.

**The fix is two independent changes; don't conflate them.**

1. **Stop keying identity on a display name.** The app already holds something unique per device — the APNs token hex it just wrote to `apnsToken`. Send it as `triggeredByToken` and have the Worker exclude on `apnsToken` instead. **No CloudKit schema change**: the field already exists. The Worker should fall back to the `coachName` comparison when `triggeredByToken` is absent, so installs on older builds keep behaving as they do now rather than notifying senders of their own actions.
2. **Give `coachName` a real value.** It is user-facing in two places and currently reads "iPhone" for everyone. Options: prompt for it during team setup, seed it from the CloudKit participant name where one is discoverable, or leave it empty and fall back to something honest like "Your assistant". **A product decision, not a cleanup** — and worth checking how many existing teams already carry "iPhone".

> ⚠️ **Fix 1 spans two repos and needs a Worker deploy.** Shipping the app half alone changes nothing; shipping the Worker half alone breaks nothing but helps nothing. Redeploy carries the 1.2 caveat: watch Observability → Events and the `sent` count, never the error rate.

**`Fetched 1`, not 2 — a loose end.** Only one token existed for that team at 16:20. With both devices registering, there should be two. Either the assistant's record landed under a different `teamID` or it was written after those requests. This decides whether fix 1 is sufficient or merely necessary.

> **Read the count off the Worker log, not the CloudKit dashboard.** `Fetched N device token(s) for team …` *is* this query — the Worker runs it with its own credentials, environment and predicate, which makes it better evidence than the console rather than a substitute for it. Install on both devices, launch both, finalize once, read N. **2** means the name collision was the only fault; **1** means a registration gap remains.
>
> The dashboard route was tried on 10 Aug and abandoned. Querying `DeviceToken` there fails with **"Field 'recordName' is not marked queryable"** — the console sorts by `recordName` when no predicate is set, and that field has no index in Production. Adding one means a schema change in Development plus a deploy, which is not worth it mid-release when the Worker already prints the answer.

**Size:** M across both repos. **Blocked on:** nothing — fix 1 shipped and verified, fix 2 continues in 1.12.

### ~~1.12 An assistant is never asked their name when they join~~ — ✅ **all steps pass on build 40, 17 Aug 2026**

**Written 12 Aug 2026**, after the device session. The receiving-side half of 1.11 fix 2, and the reason the head coach can still be told "iPhone finalized the lineup" on build 39.

**Why 39 only fixed half of it.** `TeamSharingView` asks for a name on both invite paths, which covers the coach sending the invite. It does not cover the coach receiving one — and that is the direction the name actually travels. A received team's `coachName` is seeded from `UIDevice.current.name` in `mergeCloudKitChanges` (`Models.swift:1713`), which is "iPhone", and nothing ever asked the assistant to change it. The Edit Team field has always been there; as with the owner's side, nothing pointing at it means nobody fills it in.

Two places read the result, both on the *head coach's* screen: the push body the Worker builds from `triggeredBy`, and `lastFinalizedBy` in "Finalized by …".

**Built 12 Aug.** `CoachNamePrompt`, a modifier on `ContentView`'s root, fired from `handleShareAcceptanceIfPending` once the joined team is in front. Skipping still joins the team — joining is what the coach came to do.

**The placeholder rule now lives in one place.** `LineupStore.isPlaceholderCoachName(_:deviceName:)`, used by both askers. Empty is the obvious case; equal to the device name is the one that matters, because that is the seeded default and it looks like a real value. `deviceName` is a parameter so the rule is testable without UIKit — see `CoachNamePlaceholderTests`.

**Applied once, not twice.** `RemoteDeletionPrompt` is applied to both `ContentView` and `iPadDashboardView`, and since the dashboard renders *inside* `ContentView` on iPad, that modifier is mounted twice against one piece of store state. This one is applied only to the outer root, which covers both platforms. **Worth deciding whether the older one should be too** — it isn't obviously wrong, both instances read the same state and answering either resolves it, but it is not what its own comment says it is doing.

**Not done, deliberately: seeding the name from another team.** `coachName` is per-team, so a coach on their third shared team is asked a third time. The obvious shortcut is to reuse a real name from any other team they hold, either silently or as a pre-filled field. Left out because the silent version applies a name the coach never sees applied, and the pre-filled version is more plumbing than the nag is worth today. Revisit if anyone is on enough shared teams to notice.

**On device (build 40) — run 17 Aug, all steps pass.** Accepted an invite on a device whose team name had never been set: the prompt appears once the team is in front, after the switch, not during it. Entered a name, finalized as the assistant, and the head coach's notification and "Finalized by" both read that name rather than "iPhone". A second invite on a device that already had a real name set was **not** asked again, so `isPlaceholderCoachName` is discriminating correctly against a live device name and not just against empty.

That closes the display-name half of ~~1.11~~, and with it the whole push-identity thread.

**Still open, and not urgent:** the note above about `RemoteDeletionPrompt` being applied to both `ContentView` and `iPadDashboardView` — two mounts against one piece of store state. Not wrong, since both instances read the same state and answering either resolves it, but not what its own comment says it does. Worth settling in a quiet moment; nothing observed on device points at it.

**Size:** S. **Blocked on:** nothing — closed.

### ~~1.13 A team the head coach deletes never leaves the assistant's device~~ — ✅ **all steps pass on build 40, 17 Aug 2026**

**Written 12 Aug 2026.** When a head coach deletes a shared team, or stops sharing it, the assistant keeps a copy indefinitely. It cannot sync, cannot be edited, and will never receive another lineup — and nothing tells the assistant any of that.

**The rule for this was written a week ago and could never fire.** `classifyRemoteDeletions` (`Models.swift:2528`) says a read-only shared team is removed outright while an owned team asks first, and the comment above the call site states it as fact. Its input is `changes.deletedRecordNames`, which comes from `fetchChanges()` — and that reads the **private** database's own `STLTeams` zone (`CloudKitManager.swift:524`). A received team's record lives in the **owner's** zone in the **shared** database. It can never appear in that list. The shared path only ever adds and updates; nothing removes.

`RemoteDeletionClassificationTests.testASharedTeamIsRemovedWithoutAsking` passes, and always has, because it calls the pure function directly. **A green test for a branch production cannot reach** — the same species as the comment corrected in `92de588`.

**Decided 12 Aug: remove it, and say why.** Not a prompt: "Keep" would preserve a team that does nothing. Not silent either — an assistant who opens the app before a game and finds the team gone cannot tell that from the app having lost it, which is the more alarming reading and the wrong one.

**Built 12 Aug.** Absence from a **successful** shared fetch is the signal. Three details carry the safety:

1. **A thrown fetch is not an empty one.** `fetchCloudKitChanges` now tracks whether `fetchSharedTeams` succeeded, because the catch leaves the array empty either way — and treating that as an empty shared database would remove every received team the first time iCloud was unreachable.
2. **`Team.isSharedParticipant` cannot be the test.** It is forced to `false` on every decode (`Models.swift:1191`) and only re-stamped for teams *present* in a shared fetch — so it is accurate only for teams that are still shared, which is the opposite of what this looks for. A revoked team decodes as an ordinary owned team on the next cold launch. The durable form is a local ledger of received record names, `TeamStorage.receivedSharesKey`, written as they arrive. **Note this makes the flag's own doc comment wrong twice over:** it says "never persisted to the server blob", but there are no explicit `CodingKeys`, so the synthesized encoder writes it and only the hand-written `init(from:)` discards it. Worth correcting; do not "fix" it by decoding the value, which is what forcing it false is protecting against.
3. **Deliberately not tombstoned**, unlike every other removal on that path. A tombstone would make a false positive permanent. Without one, a genuine deletion still never returns — the record is gone from the server — while a spurious removal repairs itself at the next fetch.

**On device (build 40) — run 17 Aug, all steps pass.** With a shared team joined and visible on the assistant's device, the head coach deleted it: the team goes from the switcher with the notice explaining why. Same for **Stop Sharing**, same copy, true for both readings. Then the step that had to hold: a fresh share accepted, **airplane mode on, app backgrounded and brought back** — the shared fetch throws and **every shared team is still there**. The guard under (1) does what it claims.

> **Clarification the run turned up, worth keeping in the step.** Nothing happens while the app is already in the foreground — the removal only appears after a background → foreground cycle. That is by design and not a defect: `fetchCloudKitChanges()` runs on the `scenePhase → .active` transition (`ContentView.swift:292`) and after accepting a share (`:352`), and nowhere else. There is no timer, and the Worker's pushes are for finalization, not deletion. So an assistant watching the app while the head coach deletes the team sees nothing until they switch away and back. Acceptable for a deletion; simply not what "foreground the app" reads like if the app never left the foreground.
>
> **The airplane-mode step needs a live shared team, which steps 1 and 2 have just removed.** Re-share and re-accept before running it, or it passes vacuously against an empty shared set and proves nothing.

**Size:** M. **Blocked on:** nothing — closed.

### ~~1.7 Verify the reworked sharing surface on device~~ — ✅ **all steps pass on build 39, 12 Aug 2026**

> **Closed.** Every step below was run on TestFlight build 39 across three devices in Production CloudKit, including the two that had never passed: **step 12** (the push arrives on a newly joined device with no relaunch) and **step 13** (it still arrives after a cold start). The four original faults, the three receiving-side faults from 8 Aug, and the rewritten steps 5 and 6 from 1.10 are all confirmed.
>
> **What the sequencing note bought.** Accepting the invite cold — required by step 9 to exercise `PendingShareAcceptance` — is what exposed 1.9 on the previous round. A warm accept would have passed step 12 and hidden a launch-ordering race that shipped. Worth remembering the next time a test step reads as pedantic.
>
> The write-up below is kept as the record of what was wrong and why the current design is shaped the way it is.

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
5. **Rewritten 9 Aug for 1.10 — the old step tested a control that no longer exists.** It used to read *"change the participant to Can edit, pop back, reopen. It sticks."* There is no per-participant picker any more. Instead: open the coach's row and confirm **Access is read-only text**, not a picker, and that the footer points at Invite Link. Confirm **Remove Coach still works** from that screen — it is the only action left on it, so nothing else covers it.
6. **Also rewritten — this one now asserts the opposite of what it used to.** It used to say *"change the link permission and confirm the already-joined coach is unaffected."* That was the bug. Change the **link** permission with a coach already joined and confirm the joined coach **does** change with it, and that the screen said so before you tapped. This is the check that the app and CloudKit finally agree.
7. Remove the coach. Then Stop Sharing. The team, roster, and history all survive on the owner's device.
8. **Stale record path:** this is the one that produced the original alert and is worth forcing. Delete the team's record from the CloudKit dashboard while the app holds its `ckRecordName`, then open sharing. Expect the plain "This team isn't in iCloud yet" screen and a cleared record name — not a `CKRecordID` in an alert.

**Then run 1.4 against the view-only share from step 2** rather than making a second one.

**Blocked on:** a second iCloud account, and — for the push steps only — a TestFlight build. **Size:** M.

#### Xcode builds cover most of this; the push steps need TestFlight

> **Superseded 12 Aug 2026 — device testing is on TestFlight now, full stop.** See the standing decision under ▶ Start here. The section below is kept because it is the clearest statement of *why* the two environments differ, which is the part worth understanding; the recommendation at the top of it is no longer the one to follow.

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
11a. **Cold-launch token check — added 9 Aug for 1.9, and do this before 12.** With the assistant's device on Console (or `idevicesyslog`, as used on 7 Aug), force-quit the app and cold-launch it. `Log.push` must show **`Received APNs device token`**, followed by **`DeviceToken saved for team …`** for each team including the shared one.

> **Repeat the cold launch two or three times.** 1.9 is a race, and the *old* code won it sometimes — so a single pass proves less than it looks like it does. Three clean launches is the bar. This log line is better evidence than the notification arriving, because it tests the mechanism directly instead of the whole chain; if it is present and the push still doesn't come, the fault is downstream and the Worker's `triggeredBy` exclusion is the next thing to check (see 1.9 — that mechanism is inferred from the 9 Aug asymmetry, not read from the Worker source).

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

### ~~1.5 Is the shipped build's push environment `production`?~~ — ✅ **yes, 9 Aug 2026**

**Source:** found 6 Aug while verifying the Release build. Both halves are now answered, and neither found a problem. The commands live in [`TESTPLAN-3.3.md`](TESTPLAN-3.3.md) §0 — §0b for coverage, §0c for the push environment — and are worth keeping as regression guards.

**a — push environment: `production`.** Read off the **exported IPA** for build 37, not the archive:

| Key | Value |
|---|---|
| `aps-environment` | **`production`** |
| `get-task-allow` | `false` |
| `com.apple.developer.icloud-container-environment` | `Production` |
| `beta-reports-active` | `true` |
| Authority | `Apple Distribution: NICHOLAS EDWARD DAVIES (6R6HA6RU2S)` |

**The consequence that matters for the device session: a 1.7 step 12 push failure is not a signing problem.** That was the whole point of the check — 1.2 spent a day on the Worker, and the failure this was guarding against would have looked identical to a Worker fault. Signing is now ruled out in advance, and the Worker health-checked clean the same morning, so a silent push points at the app's own registration path — bugs (b) and (c) in 1.7, which is what steps 12–13 are for.

**b — coverage instrumentation: none.** 0 `__llvm_prf` symbols in the app binary and 0 in `STLWidgetExtension.appex`. `ENABLE_CODE_COVERAGE` resolves to `YES` for Release and reaches a plain `xcodebuild build` — ~9,000 profiling symbols across both targets — but **Product → Archive does not inherit it**. Settled 7 Aug on build 35, re-confirmed 9 Aug on build 36. Nothing to change in the scheme.

**The trap this item leaves behind, which is the part worth remembering.** The original command pointed at the `.xcarchive`, and **every archive this project produces is signed `Apple Development` with `get-task-allow: true`** — builds 34 through 37 alike. Its entitlements therefore read `aps-environment: development` *whether or not anything is wrong*. The distribution re-sign happens at **Distribute App**, after the point an archive-level check can see. A check that returns the same answer in the healthy and broken cases is worse than no check, because `development` reads as a finding. Anyone re-verifying this after a signing or capability change must use the export.

> ⚠️ **This entry was stale from 7 Aug to 9 Aug, and that is the second thing worth keeping.** TESTPLAN §0 had both halves right on **7 Aug**, including the warning not to run the push check against the archive. This file went on telling you to do exactly that for two more days, and the 9 Aug re-run against the 8 Aug archive reproduced TESTPLAN's results and discovered nothing. **The test plan was right and the index was stale** — the precise failure the closing section of this file exists to prevent, recurring inside the file that describes it.

> Practical note for anything that touches these paths: **archive directory names contain a narrow no-break space (U+202F) before AM/PM.** A path pasted out of `ls` output as a plain space silently won't resolve — and `find` will report the archive missing while `ls` shows it present. Every command in TESTPLAN §0 uses the `$(ls -td … | head -1)` form, which sidesteps it.

**Size:** S. **Closed 9 Aug** on build 37.

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

### ~~3.1 `PositionSummaryView.pitchingRows()`~~ — ✅ **consolidated 20 Aug 2026**

**Source:** `CLEANUP-AUDIT-2026-08.md` §2.2a.

The third copy of the pitch-window arithmetic, now folded in. It differed in ways that matter — it adds `assignedInnings`, doesn't filter `.never` itself, and renders with rules disabled — so rather than force those onto the guide, the shared maths was extracted to `PitchEligibilityEngine.pitchingSummaryRows(...)` (policy-free: no rules guard, no `.never` filter, no sort) and both callers build on it. `coachesGuideSummary` adds its filter/guard/stable-sort; the view adds `assignedInnings` and its own sort. The window numbers are provably unchanged — the engine's `windowStartDate`/`pitchesInWindow` compute the identical window the view did inline. Extracting the core also made it testable for the first time (the view method was `private`); four new tests pin the divergences the tab relies on. Build + suite green.

**The blocker is cleared.** `PitchingSummaryTests.swift` landed 6 Aug: 23 tests over `coachesGuideSummary`, covering the window boundaries, the `available` ceiling, rest days, the sort order, and agreement with `PitchEligibilityEngine.status`. The four known divergences each carry a `DIVERGENCE` note in the test that pins this side's behavior, so the fold-in is a choice made with the consequences written down rather than rediscovered.

**Closed 20 Aug.** **Size:** M as estimated.

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

### ~~3.6 A seed produced no team, and the cause is still unknown~~ — ✅ **closed unreproduced, 12 Aug 2026**

> **Closed on the evidence, not on a diagnosis.** Several teams were seeded on **TestFlight** during the 11–12 Aug notification session — the environment where the KV-store path is live — and every one of them worked. The symptom has not returned.
>
> **This is a "did not recur", not a "fixed".** The 8 Aug incident was never explained. What makes several clean seeds meaningful rather than merely quiet is the pair of fixes that landed the same day: `DebugDataSeeder.seed` returns the new team's ID and the alert only claims success if the count actually rose, so a seed that did nothing can no longer look like one that worked. Before those, "it worked" was not an observation.
>
> **What would have made this conclusive and wasn't done:** the theory's failure is *create-then-clobber*, not create-fail. Catching it needs the team to survive an external KV write from another device on the same Apple ID — that notification is what replaces `teams` wholesale. Ordinary seeding may never trigger it. So the theory is unconfirmed rather than disproved.
>
> **The tripwire stays.** `Analytics.signal("sync.blob_shrank")` (`Models.swift:1542`) still fires on any sync that reduces the team or game-log count. If this was real and merely dormant, that is what will say so, and it costs nothing to leave armed. Reopen this item if it ever fires.
>
> The investigation below is kept because the leading theory is a data-loss shape and the reasoning would otherwise have to be rebuilt from scratch.

**Open investigation, 8 Aug 2026.** Not reproduced, not diagnosed. Recorded because the leading theory is a data-loss path, and because the next data point costs nothing — it either recurs on TestFlight or it doesn't.

**What happened.** On the assistant's device, after deleting down to one team, 7 taps → Create Test Team produced the confirmation and **no team**. Confirmed afterwards by the header button reading "Add Team" rather than "Switch", so the count really was 1. The device was running an **Xcode (Debug)** build.

**Ruled out.**

- *The alert lied.* It fired unconditionally, so it never meant anything. Fixed — `DebugDataSeeder.seed` now returns the new team's ID and the alert only claims success if the count actually rose. That change is why the failure would now be visible rather than silent, but it is not the cause.
- *The seeder switched away.* It used to end by switching back to the previous team, so a successful seed looked like a no-op. Also fixed — it stays on the new team. Not the cause either: "Add Team" proves the team was genuinely absent.
- *A `#if DEBUG` guard hiding the seeder.* There is none; it ships in Release.
- *Tombstones.* `addTeam` builds a fresh UUID, and tombstones only refuse *incoming* server teams.
- *`classifyRemoteDeletions`.* Needs an exact `ckRecordName` match, and a new team's is unique.
- *Reproduction.* Seeding works cleanly in the simulator (2 teams → 3), so it needs iCloud to appear at all.

**The leading theory — and why it may already be dead.** `saveLocalOnly()` writes the iCloud KV store behind `if data.count < 800_000`, and skips the whole write including `savedAt` above that. `TeamStorage.shouldPreferCloudBlob` then arbitrates on one line, `cloudSavedAt > localSavedAt`, and `applyStoredData()` runs on every `didChangeExternallyNotification`. A seeded team is heavy — 10 players, 5 archived games, templates, a schedule — so the local blob can cross the cap, the KV store keeps a pre-seed copy, and a write from another device on the same Apple ID then replaces `teams` wholesale with a blob that never contained the new team.

That is the same shape as the July 2026 wipe those comments reference, and there is already a detector for it: `Analytics.signal("sync.blob_shrank")` in `mergeCloudKitChanges`.

**But the KV store is `#if !DEBUG` in both directions** — `saveLocalOnly` does not write it and `TeamStorage.load()` does not read it. On the Debug build this happened on, there was no cloud blob to clobber. **So either the theory is wrong, or the build type was not what we think.**

**The one cheap discriminator:** seed on TestFlight, where the KV path is live.

- Recurs there but not from Xcode → the theory is right and this is a real data-loss path worth fixing properly.
- Does not recur at all → it was something about the Development environment, and this starts over.
- Recurs from Xcode too → the KV store is not involved and the cause is elsewhere entirely.

**Also worth capturing when it happens:** whether `sync.blob_shrank` fired, and the `Log.storage` output around the seed.

**Live risk while testing:** the iPhone and iPad share an Apple ID, so they share one KV store and can clobber each other by this same path. Xcode builds on both sidesteps it.

**Size:** unknown until reproduced. **Blocked on:** one TestFlight seed.

### ~~3.7 Two `STLRouteTests` fail, and the backlog said the suite was green~~ — ✅ fixed 9 Aug 2026

> **Cause: an isolated `deinit` aborting in the Swift runtime. Not an assertion failure — both tests were crashing the host process.**
>
> `xcodebuild`'s console output says only "failed", which is what made this look like a logic or ordering problem for most of a session. The `.xcresult` says `Crash: Stack the Lineup`, and the exported `.ips` gives the real stack: `AppRouter.__deallocating_deinit` → `swift_task_deinitOnExecutorImpl` → `___BUG_IN_CLIENT_OF_LIBMALLOC_POINTER_BEING_FREED_WAS_NOT_ALLOCATED` → `SIGABRT`.
>
> `AppRouter` is `@MainActor`, so under this project's concurrency settings its deinit is isolated and deallocation is routed through the concurrency runtime, where it aborts. **The app never hit it because `AppRouter.shared` is a static that is never deallocated** — the only code in the entire project that releases an `AppRouter` is these two tests, which is exactly why only they failed.
>
> **Fixed** with an explicit `nonisolated deinit {}` on `AppRouter` (`STLRoute.swift`). The class holds three optional value-typed `@Published` properties and owns no resources, so there is no isolated cleanup to skip. **322 of 322 pass.**
>
> **Two things to carry forward.** This is a workaround for runtime misbehaviour, not a defect in `AppRouter` — if the class ever gains a resource needing main-actor teardown, that comment is what has to be revisited. And it is the same territory as **4.5**: `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` plus `SWIFT_APPROACHABLE_CONCURRENCY` is what makes the deinit isolated at all, so expect more of this shape during that migration.
>
> **Method worth reusing:** when a test "fails" with no assertion text, go to the `.xcresult` before theorising. Two hypotheses died on the way here — parallel-clone contention, then test ordering — and both were disproved by evidence that cost a couple of minutes to fetch.

---

*Original finding, kept for the reasoning:*


**Found 9 Aug 2026** while checking whether 1.9's fix regressed anything. It did not — but the check turned up that **`Lineup BuilderTests` has been failing**, and this file has been asserting "Suite green" regardless.

```
STLRouteTests.testHandleRejectsForeignURLsWithoutSettingARequest()
STLRouteTests.testRepeatingTheSameRouteProducesADistinctRequest()
```

**320 of 322 pass.** These two fail **on a clean tree with 1.9's changes stashed**, so they are nothing to do with the push work.

**They are deterministic, not flaky.** The first read of the full-suite run suggested parallel-clone contention — both failures landed on one simulator clone while sibling cases passed on others, which is the classic shape of shared static state across a parallelized run. **The baseline disproved that:** run alone, as the only test class, both still fail. Whatever this is, it reproduces in isolation.

Both names describe `AppRouter`/pending-request state rather than pure URL parsing — one asserts a rejected URL leaves *no* pending request, the other that a repeat produces a *distinct* one — so the likely area is `STLRoute.handle` and the nonce, not `STLRoute` parsing, which passes everywhere else in the class.

**Why this matters more than two tests.** The suite is the gate every other item in this file leans on when it says "unit-green", and it has been reporting a state that isn't true. Until this is fixed, "the tests pass" is not evidence of anything.

**First step:** open the `.xcresult` for the assertion text — `xcodebuild`'s console output does not carry it.

```
~/Library/Developer/Xcode/DerivedData/Lineup_Builder-*/Logs/Test/
```

**Size:** S to diagnose, unknown to fix. **Blocked on:** nothing.

### ~~3.5 iPad has no PDF export at all~~ — built 8 Aug 2026, pulled into 3.3

> **Built and pulled into 3.3** by decision on 8 Aug: this is cleanup of bad design from before, not new scope, and the assistant-printing story only works whole with it.
>
> **What landed.** `LineupPDFExport.swift` now owns the entitlement, both generator calls, and the whole presentation — preview sheet, paywall cover, and the promotion that swaps a locked document for the real one on purchase — behind a `lineupPDFExports(request:)` modifier. `LineupView` lost its two `@State` PDFs, its two export methods, and three modifiers; it now sets a request and nothing else. `iPadNavBar` gained an Export menu on `Cmd+P`.
>
> **Verified in the iPad simulator:** the menu opens, the Coaches Guide renders with the full grid and pitch counts, and `PDFPreviewView` survives presentation from the dashboard — the detail-pane inertness trap does not apply.
>
> **Still unverified: the locked path on iPad.** That simulator holds a Pro entitlement, so `ProGate` as a full-screen cover has still never been seen at iPad size. It was designed against iPhone. **Check it on a non-Pro device before shipping.**

**Found 8 Aug 2026** while making the Coaches Guide free for view-only assistants.

`PDFGenerator.generate` has exactly two callers, both in `LineupView` — which renders only at compact width. `iPadDashboardView` has no export affordance of any kind. **An iPad coach cannot print a Batting Order or a Coaches Guide.**

**Why it matters more than it used to.** The 8 Aug change unlocks the Coaches Guide for a view-only assistant precisely so a head coach running late can ask someone to print it for the dugout. If that assistant is on an iPad, there is still no button. The feature is half-delivered until this lands.

**Scope.** Additive; nothing existing changes behaviour.

1. **Share the entitlement, don't copy it.** `canExportCoachesGuide` (`isPro || (isSharedParticipant && isReadOnly)`) currently lives in `LineupView`. Lift it somewhere both idioms call. This is the whole theme of finding 2.4 — `playerChip` was duplicated across `DefensiveGridView` and `iPadDashboardView` and silently drifted — and a paywall rule drifting is worse than 1pt of spacing.
2. **Share the generator call.** `.battingOrder` and `.coachesGuide` take different argument lists (the guide also needs `gameLogs` and `pitchingConfig`). Wrap both so a future field can't be added to one caller only.
3. **Placement:** one **Export** menu in `iPadNavBar` with two items, rather than two more icons — the bar already carries the team switcher, game context, violations pill, import, archive and settings. Give it `Cmd+P`, alongside the existing `Cmd+Shift+S` and `Cmd+Shift+A`.
4. **Presentation:** `.sheet(item:)` → `PDFPreviewView`, `.fullScreenCover(item:)` → `ProGate` wrapping `PDFKitView`, plus the `onChange(of: isPro)` promotion that swaps a locked PDF for a real one on purchase. Mirror `LineupView` lines 181–195.

**Two things already checked:**

- `PDFPreviewView` wraps itself in a `NavigationStack`, so it survives presentation from the dashboard — the trap that makes iPad detail-pane views go inert does not apply.
- **This export must NOT be read-only gated.** See 1.8: the rest of that nav bar should be, and this is the exception.

**Worth verifying on device:** `ProGate` was designed against iPhone. Check it reads sanely as a full-screen cover on an iPad before trusting the locked path.

> ### ❌ Checked 12 Aug 2026 in the iPad simulator — **it does not.** This is now 3.8.
>
> Run on a clean iPad Pro 13-inch simulator with no StoreKit transaction, owned team, `isPro == false`. The menu label is correct — **"Coaches Guide (Pro)"** — and tapping it presents `ProGate` as designed. The presentation is what fails.
>
> **At the peek detent, which is what a coach sees first.** `ProGate` opens `PaywallView` as a sheet at `.fraction(0.6)` (`ProGate.swift:61`). On iPhone that is a bottom-anchored peek with the preview above it. **On iPad a sheet is a centered floating card**, so the peek concept does not exist: the locked PDF shows above *and* below, the "YOU JUST TRIED / Coaches Guide PDF" block is cut in half by the pricing panel overlapping it, and the legal footer truncates mid-word at *"Renews automatically unless c…"*.
>
> **Dragged to `.large` it is right** — blue block intact, feature list visible, footer complete and legible.
>
> **Fixed 12 Aug, and verified.** `ProGate` now offers the peek only at compact width; at regular width `.large` is the only detent, read through a computed binding so the first frame is correct rather than corrected in `onAppear`. `presentationBackgroundInteraction` had to move with it: it was capped at the peek, which on iPad would have scrimmed `.large` and made the nav-bar **Close** button — the one non-committal exit — unreachable. Re-checked on the same clean simulator: opens at `.large`, upsell block whole, footer complete, backdrop undimmed. iPhone still opens at the peek and still drags to `.large`.
>
> **A correction, because it was written here as fact.** This item first recorded a second defect: the feature list "bisected", with the "Lineup Templates" row sliced by the pinned pricing panel. **That was a misreading — the list simply scrolls.** Dragging it reveals the row in full, then Shared Teams and Game History below. On iPhone at `.large` the whole list fits without scrolling, which is the only reason the two looked different. Nothing to fix.
>
> ### ⚠️ The iPhone comparison turned up something separate — see 3.9
>
> Checking whether the bisection was iPad-only meant looking at iPhone at both detents, and **at the peek detent the subscription legal text is truncated mid-word**: *"…is charged to your Apple Accou…"*. It is one ellipsised line there and four full lines at `.large`. The peek is iPhone's **default** state, so this is what a coach sees unless they drag the sheet up. Not iPad-specific and not caused by anything here. Recorded as **3.9**.
>
> **Why the first attempt at this test proved nothing, worth knowing for next time:** the iPad simulator it was run on turned out to be **Pro**, from a StoreKit-testing transaction left by an earlier Xcode run. Those persist per simulator. It rendered a full unlocked PDF and looked like a pass. The tell was the menu reading "Coaches Guide" rather than "Coaches Guide (Pro)"; History being unlocked confirmed it. **Verify the device is actually non-Pro before testing a locked path** — a fresh simulator, or check that History is paywalled.

**Size:** M. **Blocked on:** nothing. Can be pulled into 3.3 if the assistant-printing story should ship whole — the iPhone path works today, so it is a judgement call, not a blocker.

---

### ~~3.9 The subscription terms truncate mid-word at the paywall's default detent~~ — ✅ **fixed 17 Aug 2026**

**Found 12 Aug 2026 on iPhone**, while checking whether 3.8's suspected second defect was iPad-specific. It wasn't, and this is what the comparison actually turned up.

At the peek detent — `.fraction(0.6)`, which is what `ProGate` opens at on iPhone and therefore **the default state a coach sees** — the legal line under Restore Purchase renders as a single ellipsised line:

> *"After the 7-day free trial, $9.99/year is charged to your Apple Accou…"*

Dragged to `.large` the same text wraps to four full lines and reads completely: price, renewal, cancellation window, where to manage it, and the Terms/Privacy links. So the copy is right and the room for it is not.

**Why this is worth more than a cosmetic ticket.** App Review's guidelines on auto-renewable subscriptions expect the price, duration and renewal terms to be legible before purchase, and here the "Start 7-day free trial" button is fully visible while the sentence explaining what happens after the trial is cut mid-word. **I have not confirmed how the current guidelines word this** — worth reading them rather than taking the risk on my summary — but a truncated terms line directly above a purchase button is the shape of thing that draws a rejection.

**Not caused by 3.8's fix and not fixed by it.** 3.8 removed the peek at regular width, so iPad now opens at `.large` and reads correctly. iPhone still opens at the peek by design, which is where this shows.

**Options, cheapest first:** give the footer room at the peek (it is the pinned block, so the space is a layout constant, not a scroll problem); or raise the peek fraction; or open at `.large` everywhere and drop the peek entirely — though that would throw away the preview-above-paywall idea the peek exists for, which is worth keeping.

**Fixed 17 Aug 2026.** None of the three options above: the room was never the problem.

**The cause is one missing modifier.** Every other wrapping `Text` in `PaywallView` carries `.fixedSize(horizontal: false, vertical: true)` — the hero description, the free-tier card, the feature rows. The legal block did not. A plain `Text` is vertically *compressible*: offered too little height it truncates rather than insisting. The footer is pinned beside a `ScrollView`, which takes everything it is offered, so the scroll content won the space and the disclosure gave it up — one ellipsised line. `fixedSize` makes its wrapped height a minimum the stack has to grant, and the scroll content absorbs the difference. It has somewhere to put the loss; the disclosure does not.

That also explains the shape of the symptom. A layout too short by a few points would have dropped one line; a *compressible* text collapses to one line, which is what was seen.

**Verified in the simulator (iPhone 17, iOS 26.4, 17 Aug), at the peek detent:** the disclosure reads completely — price, renewal, cancellation window, where to manage it, and both links — at the default type size and at xxxL, the largest non-accessibility size. The same modifier is on the purchase-error text, which sits in the same footer and had the same trap.

**Deliberately released at the accessibility type sizes,** where the footer wants more height than the whole sheet. Held rigid there it pushes the price and the purchase button off the bottom — a legible disclosure describing a purchase you cannot reach, which is worse than what it replaced. Those sizes now truncate exactly as they did before this change, so nothing regressed; the paywall's Dynamic Type calibration is **4.3**, and this is the second finding pointing at it.

> **Worth recording, because it cost most of the time here.** A bounded, internally scrolling footer was built first — `ViewThatFits`, a measured height budget, `layoutPriority` — so the disclosure could be complete at *every* type size. It works, but wrapping the stack in a `GeometryReader` pins the content to the safe-area height, and the footer's background then stops short of the home indicator with the sheet's own colour showing through as a band. Two attempts at `ignoresSafeArea` did not shift it. Reverted for the one-line version. If 4.3 revisits this, the scrolling footer is the right shape and the safe-area seam is the thing to solve first — not an afterthought.

**Size:** S. **Blocked on:** nothing.

### ~~3.10 Tapping a push notification lands on whatever team was already open~~ — ✅ **fixed 17 Aug 2026**

**Found on device 17 Aug 2026**, after 1.12's steps had passed — by tapping the notification, which is not one of them. A push about **Team C** arrived while **Team A** was active; tapping it opened the app still on Team A. The coach has to find the switcher and change teams themselves, having just been told something happened somewhere else.

**Cause: the tap handler does nothing with the tap.** `userNotificationCenter(_:didReceive:)` (`NotificationManager.swift:51`) fires a `push.received` analytics signal and calls `completionHandler()`. It never reads `response.notification.request.content.userInfo` and never navigates. Opening the app is iOS's doing, not the app's.

**Everything needed already exists**, which is what makes this cheap:

- The app already sends `"teamID": team.id.uuidString` to the Worker (`NotificationManager.swift:121`).
- `STLRoute.team(UUID)` already exists, commented *"Make a team active without targeting anything inside it"* — written for exactly this shape of request.
- `applyRoute` already handles it: `store.switchTeam(to:)` then the tab (`ContentView.swift:560`). `.team` resolves to the Lineup tab, which is where a `lineup_finalized` push should land.
- `AppRouter.shared` exists to carry a route from a producer that may run *before* the view hierarchy does — precisely the cold-launch case a notification tap usually is.

So the app-side change is close to one call: pull `teamID` out of `userInfo`, hand it to `AppRouter.shared.route(to: .team(id))`.

**The unknown, and the reason the size is S–M: does the Worker forward `teamID` into the APNs payload's `userInfo`?** The app POSTs it, but the payload the Worker *builds* lives in [`daviesn18/stl-worker`](https://github.com/daviesn18/stl-worker). If it already carries it, this is an app-only change. If not, it spans both repos and needs a Worker deploy — the same shape as ~~1.11~~, and worth checking the Worker's `buildPayload` before estimating anything.

**Same species as the Spotlight tap-through fault:** the mechanism delivers, and the tap goes nowhere because nothing was wired to receive it. Worth a look at whether any *other* producer has the same gap.

**Not a regression.** Pushes did not work end to end in any shipping build before 3.3, so no coach has ever tapped one. That cuts both ways: nothing is being taken away, and 3.3 is the first release where a coach can tap a notification at all.

**Blast radius is narrow.** It only bites a coach with **more than one team** who receives a push about a team that isn't the active one. A single-team coach — presumably most — sees correct behaviour, because the team they land on is the team the push was about.

**The Worker needs nothing.** `sendAPNs` already puts `teamID` at the top level of the payload beside `aps`, which is where APNs lifts custom keys into `userInfo`. Every push build 40 has already delivered carries it. App-only fix, no deploy, no compatibility question in either direction.

**Fixed 17 Aug 2026, in two parts — and the second only surfaced because the first was tested properly.**

**Part one, the routing.** `didReceive` now reads `teamID` from `userInfo` and calls `AppRouter.shared.route(to: .team(id))`. `applyRoute` does the rest, and ignores a team the device no longer holds, so a push for a team since left cannot select a phantom.

**Part two, the delegate was not installed early enough to receive a cold-launch tap.** `NotificationManager` registers itself as the `UNUserNotificationCenter` delegate in its `init`, but it is a **lazy static** whose first touch was `ContentView`'s `requestPermissionIfNeeded()` — a view lifecycle. A tap that cold-launches the app has its response delivered before any view exists; with no delegate registered, iOS discards it. So part one worked on a *backgrounded* app, where the delegate survived from the previous launch, and did nothing at all on a terminated one — **which is the common case for a push.** Now installed from `application(_:didFinishLaunchingWithOptions:)`, via an explicit `installDelegate()` so the call site reads as intent.

> **This is the third instance of one pattern in this app.** ~~1.9~~: the APNs token arrived before there was a view to receive it. The Spotlight tap-through: the entity was indexed but nothing handled the activity. Now this. **Anything iOS hands back at launch needs a receiver that exists at launch, not one a view happens to create later.** Worth checking any remaining launch-time callback against that rule rather than waiting for the next one to be found on a device.

**Verified in the simulator (iPhone 17, iOS 26.4, 17 Aug)** with `xcrun simctl push`, which delivers a real payload through the same delegate path. Two teams; the push always names the one that is *not* active, and `stl_active_team_id` is read from the app's own preferences afterwards rather than inferred from the screen:

| Case | Before | Push targets | After |
|---|---|---|---|
| Warm — app backgrounded | Tigers | unnamed team | **unnamed team** ✅, lands on Lineup |
| Cold — app terminated, *before* part two | unnamed team | Tigers | unnamed team ❌ — no switch |
| Cold — app terminated, *after* part two | unnamed team | Tigers | **Tigers** ✅ |

Suite green, 336/336.

**Confirmed on device 17 Aug, TestFlight build 41 — warm and cold both pass.** The cold case is the one that mattered: a terminated app, tapped from the lock screen, lands on the team the push was about. The simulator predicted device behaviour exactly here, which is worth knowing for next time — but only because part two moved delegate registration to `didFinishLaunchingWithOptions`. The launch-timing fault it fixed is precisely the kind that a simulator *can* hide, so the device check earned its keep rather than merely confirming what was already known.

**Noticed while fixing, not acted on:** `postEvent` has five event-type constants and the Worker builds bodies for all five, but the app only ever sends **`lineup_finalized`** — from `finalizeLineup` (`Models.swift:1906`), the single call site. `game_archived`, `archive_prompt`, `team_invite` and `tip` are dead as far as the app is concerned. That is why `.team` is the right route for every push today, and it is worth deciding whether those are unbuilt features or leftovers before someone builds against them.

**Size:** S. **Blocked on:** nothing — closed.

## Stage 4 — decisions and long poles

### ~~4.1 The History paywall auto-opens~~ — ✅ **decided 20 Aug 2026: a Pro coach must never see a paywall**

**The decision, in Nick's words:** *"I don't want my pro users to face any friction. Let's do whatever so they don't accidentally see a paywall."*

`GameLogsView` presented `ProGate` unprompted 0.35s after a free coach opened the tab. That behavior had already drawn blood once: `isPro` is `false` while StoreKit is still `.undetermined`, so on a slow or offline cold launch a **paying** coach fell into the locked branch and was asked to buy something they already owned. `ProStatus` — three states, with `isResolved` — was built to fix exactly that, and `GameLogsView` was given the guard.

**The audit that followed found the guard was applied in one place and the rule broken in eight.** Every other gate still tested `!isPro`, which is the natural thing to write and is wrong: it is true during the launch window. A Pro coach who tapped Auto-Fill, the bolt, Save as Template (either surface), or Export → Coaches Guide, or who opened a player's Position Preferences or Settings, could be shown a paywall, a locked screen, a PRO badge or an upgrade pitch before StoreKit answered.

**Fixed 20 Aug 2026.** `PurchaseManager.showsLockedUI` (`status == .free`) now expresses "may show a lock", and all eight sites use it. The point of the property is that the *correct* test is now also the shortest one to write. Where the gate is a tap handler, an unresolved entitlement does nothing rather than guessing — a dead button for a fraction of a second is recoverable; a paywall shown to a subscriber is not. `TemplateLockEditorView.attemptSave()` was the worst of them: it both gated the coach and silently discarded the template they had just built.

> **Residual, and deliberately still open: the unprompted auto-open itself, for genuinely free coaches.** The decision above is about who must never see the paywall, not about whether entering a tab should present one. Removing it is a conversion trade-off; it is a two-line change whenever it is wanted.

**Size:** S as scoped, M as it turned out. **Closed 20 Aug** on the terms above.

### ~~4.2 Arc 2 gives free coaches 2 tips of 6~~ — ✅ **decided 20 Aug 2026: no change**

**The decision, in Nick's words:** *"I don't want to interrupt more. I want this to be a friction-free experience for all my users."*

Free coaches keep the two tips they get. The alternative on the table was a free-tier tip pointing at what archiving builds toward, and it is **rejected** — it would have cost principle 3 of this app's own Free-vs-Pro rules: *no tour tip opens the paywall*, because this app gets used twenty minutes before first pitch, the worst possible moment to interrupt with an upsell.

Worth keeping in view if this is ever reopened: 2 of 6 is already a **fix**, not an oversight. On 24 Jul arc 2 gave free coaches **zero** — the group stalled behind a paywalled anchor — and Pro-gating `ReuseSaveTemplateTip` unstuck it.

**Closed 20 Aug. No code change.**

### 4.3 Paywall dark mode + Dynamic Type

Implemented with semantic colors and a large-type-tolerant footer, but the *visual* calibration was never done on device. The build ships 8 feature rows; 9 is the ceiling. (`PAYWALL-design-handoff.md`, "Still on Design.") **Size: S.**

**"Large-type-tolerant" overstates it, measured 17 Aug** in the simulator while closing 3.9. At the accessibility sizes the whole footer degrades, not just one line: the plan headline, the subtitle, the CTA label and Restore Purchase all truncate mid-word, the CTA because `buyButton` is pinned to `.frame(height: 52)` regardless of type size. None of that is new and none of it regressed — but it is more than a colour pass, and the note under 3.9 records the layout approach already tried and where it snagged.

### 4.4 Localization

**Source:** `HANDOFF-app-intents.md` §9b.1 — "the long pole and it's overdue."

There is **no string catalog in the repo** (`find . -name "*.xcstrings"` returns nothing) and all four App Intents phases shipped `LocalizedStringResource` literals inline. Phase 4 added the most strings of any phase.

The hard part isn't the mechanical pass. `TeamRulesBuilder` **assembles** its sentences — "Everyone active needs at least \(innings) in the infield" — and that doesn't translate by swapping a table: plural rules and word order differ per language. That's a design decision to settle before any Spanish work starts, not a chore to schedule.

**Size: L.** Genuinely a project. Don't start it inside a release.

### ~~4.5 Swift 6 language mode~~ — ✅ **done 20 Aug 2026: all four targets on Swift 6, 340/0**

**Source:** the Release build of 6 Aug. Detail in the correction under 1.1.

The app builds at `SWIFT_VERSION = 5.0` with `SWIFT_APPROACHABLE_CONCURRENCY = YES` and `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. That combination is why a Release build emits 12 actor-isolation warnings: with everything MainActor by default, any synchronous nonisolated context that reaches into ordinary model code is a violation. Two of the twelve already say *"this is an error in the Swift 6 language mode."* **Moving `SWIFT_VERSION` to 6.0 turns all twelve into build errors.**

Where they live: `TeamRules` (4), `PitchEligibility` (2), `GameRecap` (2), `AutoFillCoordinator` (2), `PurchaseManager` (2).

The shape of the work isn't silencing warnings — it's deciding what is genuinely main-actor state and what is pure computation. Most of the offenders are the second kind: `PitchingLimits.restDaysRequired(for:)`, `PitchingAgeBracket.bracket(for:)`, `PitchEligibilityEngine.status(...)` are stateless maths that got swept into MainActor by the project-wide default rather than because they need it. Marking those `nonisolated` is likely most of the fix.

**One trap.** `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` is set on the **app target only** — not the widget, not the tests. `WidgetSnapshot.swift` and `STLWidget.swift` compile into *both* the app and `STLWidgetExtension` (confirmed from the build's `SwiftFileList`s, not the project file), so the same source compiles MainActor-by-default in one target and nonisolated-by-default in the other. Any isolation annotation added to those two has to hold under both.

**Size: M**, and unusually front-loaded — the diagnosis is most of it, the edits are small. Do it at the *start* of a cycle: the failure mode is flipping the language mode late, hitting twelve errors in five files, and reverting under time pressure.

**Done 20 Aug 2026 — and the live error set was not the 2-Aug list.** Reproduced before touching anything (the count was stale): the `TeamRules`/`GameRecap` offenders had already been marked `nonisolated` since, and the errors that actually surfaced under `SWIFT_VERSION = 6.0` were a different set — `PurchaseManager` (2 static product-ID constants), the two App Intent entities' `urlRepresentation` (a non-Sendable stored `static let`, fixed by making it computed), the `PitchEligibility` → engine maths, the whole **AutoFill** result payload, **CloudKitManager**'s share snapshots (`TeamSharePermission`/`ShareParticipantInfo`/`TeamShareInfo`, added since the note), every `Tip`'s shared builders (`tourTitle`/`nextAction`/`doneAction` + `TourState`), and finally the **model layer** itself (`Player`, `Lineup`, `Team`, `FairPlayConfig`, `GameLog`, and the `Color(hex:)`/`toHex()` helpers). The backlog's own thesis held: nearly every fix was `nonisolated` on a pure-data or pure-computation type; `LineupStore` (the real `@MainActor ObservableObject`) was left alone. One real restructure: `AutoFillCoordinator.parseWithTimeout` raced a task group of `@MainActor` closures capturing the non-Sendable NL service, which trips a region-isolation-checker limitation — rewritten to race the parse **Task handle** (Sendable) instead, behaviour identical.

**All four targets moved to Swift 6, not just the app.** The test target is nonisolated-default (an `@MainActor` XCTestCase breaks — `XCTestCase`'s inits are nonisolated, so a MainActor-default test target conflicts with every subclass; a brief attempt at that was reverted). Making the data models `nonisolated` is what lets the nonisolated logic tests build; three `@MainActor` test classes with synchronous `setUp()`/`tearDown()` moved to the `async` form. See [[swift6-mainactor-default-migration]].

**Verified:** app + widget + both test targets compile under Swift 6, `Lineup BuilderTests` **340/0**, no isolation warnings remain. **Closed 20 Aug.**

### 4.7 Should CloudKit send the pushes itself, and the Worker go away?

**Opened 10 Aug 2026**, after a day in which the push chain produced three separate faults (1.9, 1.11, and 1.2 back on 6 Aug). Worth asking deliberately rather than drifting into.

**The Worker exists for one reason: CloudKit offers no server-side hook.** Everything painful about push on this project traces to reaching into CloudKit *from outside* — per-environment server-to-server keys, SEC1 vs PKCS#8, a Development share being **invisible** rather than stale in Production, and a `DeviceToken` mirror of state CloudKit already knows.

`CKSubscription` on the shared zone would delete that whole surface: no device tokens, no `DeviceToken` records, no sender-exclusion rule, no S2S key, no environment mismatch, no Worker, no second repo, no deploy step. Every one of 1.9, 1.11 and 1.2 lives in machinery that would stop existing.

**Two things to settle before believing any of that:**

1. **Does CloudKit notify the device that made the change?** The entire 1.11 defect was a hand-rolled answer to that question. If CloudKit suppresses the originator, the problem disappears; if not, it comes back in a new costume.
2. **Can the alert say what it needs to say?** Subscription-driven alerts have constrained content. "Nick finalized the lineup vs the Rockhounds" likely needs a **silent** push plus a locally composed notification — and silent pushes are throttled by iOS and **do not arrive at all when the app has been force-quit**. A coach who swipes the app away and misses the lineup is a worse outcome than any bug fixed today.

**That second point is probably why the Worker was built**, and it may well be the right answer. Rich, immediate, reliable alert text is a genuine benefit, not an accident. **Do not treat this item as a foregone conclusion** — it is a question, and "keep the Worker" is a legitimate answer to write down.

**What is *not* worth doing: switching providers.** Reviewed 10 Aug against the day's actual defects. 1.9 and 3.7 were app-side and toolchain, and would have followed any stack. Cloudflare caused essentially nothing — two minor gotchas, the 0%-error-rate trap in 1.2 and `crypto.subtle` needing PKCS#8. Firebase would have prevented 1.9 (its SDK owns token persistence) and made 1.11 unlikely (it hands you an installation ID), but at the price of an account system, a second datastore or a CloudKit→Firebase mapping, privacy disclosures and cost — more moving parts, in an app that is serverless and authless *because* it is CloudKit.

**Size:** M to evaluate, L if adopted. ~~**Blocked on:** 3.3 shipping.~~

> ## ✅ Decided 20 Aug 2026: **keep the Worker.**
>
> Nick's call, and it is the answer this item said was legitimate. The two questions above no longer need answering, because the second one was always the load-bearing half: subscription-driven alerts have constrained content, so *"Nick finalized the lineup vs the Rockhounds"* would need a silent push plus a locally composed notification — and silent pushes are throttled by iOS and **do not arrive at all when the app has been force-quit.** A coach who swipes the app away and misses the lineup is a worse outcome than any bug the migration would retire.
>
> The Worker's cost is real and is accepted: a second repo, a deploy step, per-environment server-to-server keys, and the `DeviceToken` mirror. What it buys is rich, immediate, reliable alert text — a genuine benefit, not an accident of how this got built.
>
> **Do not reopen this on the strength of another bad push day.** Three faults in one day (1.9, 1.11, 1.2) is what prompted the question, and all three are fixed. The trade was evaluated on its merits and settled.

### 4.6 iOS 27 App Intents readiness

**Source:** WWDC 2026, read on 7 Aug against the 1.3 device results. Not verified against a beta — see the caveat at the end.

**The good news first: nothing here is on a deprecation path.** WWDC 2026 deprecated SiriKit outright and made App Intents the only route into Siri, with a two-to-three-year migration window. This app is already all App Intents. There is no migration to do.

What's open is *adoption*, and it matters because it's the most plausible fix for the one thing 1.3 couldn't solve. The iOS 27 Siri is rebuilt on Apple Intelligence and Apple's framing is that it resolves spoken references to real entities — which is precisely the sentence that isn't true today. 1.3 proved Siri never binds a spoken name into a phrase slot at all. That's a template-parser limitation, and a reasoning-based router is the thing that removes it.

Two concrete gaps, checked in the code on 7 Aug:

1. **`indexingKey` on the entities — rolled into gap 2 (part 2), 20 Aug 2026.** This was framed as a standalone S that pays off on iOS 26. On a closer read it's smaller-value than it looked: `PlayerEntity` and `TeamEntity` already carry a rich hand-rolled `attributeSet` (name, first/last, jersey as `12`/`#12`/`number 12`, team, strengths) and are actively published via `indexAppEntities`, so a coach can already find a player in Spotlight by all of those. What `@Property(indexingKey:)` adds is *structured* attribute mapping, whose real payoff is the iOS 26+ semantic layer and the iOS 27 reasoning router — i.e. part 2's territory. It's also not a one-liner: these entities are plain `let` structs with no `@Property` wrappers, so it means reshaping them, and the exact current API should be checked against Apple's docs first. **Do it alongside part 2, on the same iOS-27 pass, not as a standalone.**
2. **No App Schema conformance.** The iOS 27 guidance is to conform entities to a schema so Siri understands the *category* of content. ⚠️ **Open question: whether a schema exists that fits a youth-sports roster.** The schema list is domain-specific. If nothing fits, this lever may not be available at all, and that's worth ten minutes of checking before anyone plans around it.

**Keep `PlayerSearch` and `TeamSearch`.** 1.3 established they're dead on the voice path — Siri never calls `entities(matching:)`. Do **not** conclude they should be deleted. `EntityStringQuery` is explicitly retained in iOS 27 for live state that can't be pre-indexed, which is exactly a roster that changes weekly. That code is the part a smarter Siri would finally start calling. Leave it alone and don't tune it either — tuning a matcher nothing calls is how you spend a day for nothing.

> ⚠️ **This is read from session titles and secondary coverage, not from observed behavior.** No one has run this app against an iOS 27 beta. The 2 Aug phrase rework was also a well-reasoned theory that the device contradicted — see 1.3. Treat the whole item as a hypothesis until §1 of [`TESTPLAN-3.3.md`](TESTPLAN-3.3.md) is re-run on a beta.

**Size: M.** Not for a release cycle. `indexingKey` alone is S and could go any time.

> **The blocker is softer than this item assumes, noticed 20 Aug 2026.** The suite now runs against an **iOS 27.0 simulator** (build `24A5380i`) — one is already installed on this machine, so "an iOS 27 beta to verify against" is not the wall the order table calls it.
>
> **It does not unblock everything.** Gap 2 — whether an App Schema fits a youth-sports roster — is a code-and-SDK question a simulator answers perfectly well, and it is the ten-minute check this item asks for before anyone plans around it. Gap 1, `indexingKey`, never needed a beta at all.
>
> **What a simulator still cannot settle is 1.3**, which is the reason to care: spoken entity resolution needs speech on real hardware. Re-running §1 of `TESTPLAN-3.3.md` remains a device job.

---

## Already done — stop carrying these

Things one of the docs still half-implies are open, that aren't:

- **Both cleanup audits, all phases.** July's Phase 1/2/3 and the August pass are complete. The only survivors are 3.1 and 3.2 above, both deferred by decision.
- **The `StackTheLineupTests` target** — removed from the project and the scheme.
- **`cleanup-phase1.sh` / `.patch`** — deleted; they'd have failed if run.
- **`roadmap.jsx`** — gone from the repo.
- **3.3 ship-readiness** (`HANDOFF-app-intents.md` §9b.3) — that item says `MARKETING_VERSION` is still 3.2 with no 3.3 What's New entry. Both are done: version is `3.3 (41)` and the registry has its 3.3 entry, guarded by a test that fails the build if the version moves ahead of the registry. **That doc has been corrected at the source** — §9b.3 now reads as done rather than outstanding.
- **`AskSiriTip` discovery** — verified on screen 1 Aug.
- **The app-name cleanup** — `ShortcutsLink` and the `navigationTitle` (2.1) are both done. Nothing still says "Lineup Builder" in user-facing copy.
- **The `stl-worker` housekeeping** — it's under version control, has a GitHub repo, a README, current tooling (wrangler 4.119), and Workers Logs enabled. The backlog used to note "not under version control" as a to-do; that's closed.

## Document status

| Document | State |
|---|---|
| `BACKLOG.md` | This file. The index — the only place that says what's next. |
| [`TESTPLAN-3.3.md`](TESTPLAN-3.3.md) | **Closed 12 Aug.** Every section passed or was triaged. Historical record of the 7–12 Aug device sessions. The two device passes still outstanding are 1.12 and 1.13 here, not there. |
| `HANDOFF-app-intents.md` | **Live.** The 3.3 reference; §9 is the open part (1.3, 4.4). |
| `CLEANUP-AUDIT-2026-08.md` | **Closed**, except 3.1 / 3.2 and the iPad test plan for 1.4. ⚠️ **§8.3a is factually wrong** — see 1.2. |
| `TIPS-onboarding-spec.md` | **Mostly closed.** 2.3, 2.4, 4.1, 4.2 come from here. |
| `PAYWALL-design-handoff.md` | **Closed** except 4.3. Reference for the paywall's content rules. |
| `AppStore-Screenshots*/SCREENSHOT-NOTES.md` | Reference for the store listing. Nothing open. |
| [`stl-worker/README.md`](https://github.com/daviesn18/stl-worker) | **Live**, separate repo. The record for push: architecture, the environment trap, deploy and debugging. |

> **Deleted 20 Aug 2026, both fully closed:** `CLEANUP-AUDIT.md` (19 Jul, all three phases done) and `HANDOFF-data-recovery.md` (the July incident). Neither had anything open and nothing live pointed into them. **They are still in git history** — `git show 9cb6625:CLEANUP-AUDIT.md` — if the evidence behind an old finding is ever wanted. The one caution from the recovery handoff that still matters was never doc-only: it sits at the point of danger in `Models.swift`, above the `#if !DEBUG` guard on the iCloud KV write.

---

## How to keep this from happening again

The failure wasn't that work got dropped — almost none did. It's that five documents each held a piece of the picture, and three described a state the code had moved past. Two habits fix it:

1. **One index, many records.** This file is the only place that says what's next. The handoffs stay as deep records of *why*, and they don't need a "next steps" section competing with this one.
2. **Close things out loud.** When an item lands, strike it here and say so in the document it came from — and **delete the superseded instructions rather than layering new notes on top of them.** A closed item should read as one paragraph of "here's what happened," not as an archaeology of what people believed at each stage. `HANDOFF-data-recovery.md` telling you not to open an app on a device, four weeks after the reason expired, is what happens otherwise. (That file was deleted on 20 Aug once it was fully spent — see the note under Document status.)

**The 6 Aug lesson worth carrying:** the two worst problems that day — the widget version mismatch and the CloudKit outage — were both *invisible from where you'd normally look*. One printed a warning in a build log nobody reads. The other showed a 0% error rate on a dashboard while failing 100% of the time. Neither was in any document. When something matters and it's cheap, **check the live thing instead of the note about it.**
