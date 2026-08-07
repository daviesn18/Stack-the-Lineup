# Test plan — 3.3 (36) device session

**Written 7 Aug 2026.** Everything that has to happen on real hardware before 3.3 can be submitted, in the order to do it. Covers [`BACKLOG.md`](BACKLOG.md) items **1.5, 1.3, 1.4, 2.3, 2.4**.

Work top to bottom. §0 takes two minutes and can invalidate the whole build, so don't skip ahead to the fun part.

**Build under test:** `3.3 (36)`, from `main`. Confirm in Settings → the Version and Build rows before you start. If the Build row doesn't say **36**, you're testing the wrong upload.

---

## Setup you need before starting

- [ ] **Two devices** — one iPhone, one iPad. §2 can't be done with one.
- [ ] **A real shared team**, with the iPad joined as a **view-only** participant. Set this up first; it gates §2 *and* §3.
- [ ] **A Pro account** on the primary device. Two intents are Pro-gated (Fill Lineup, Game Recap) and three tips in §4 are Pro-only. A TestFlight build uses the sandbox StoreKit account, so buy Pro there if you haven't.
- [ ] **A team with pitch data** — §1 asks Siri about a named player's pitching, which needs a roster with league ages and some archived games.

---

## §0 — Archive checks (backlog 1.5)

**Do this before anything else.** Run every command in **Terminal**, from anywhere — they find the newest archive themselves.

### 0a. Is this even the right build? ← start here

```bash
A=$(ls -td ~/Library/Developer/Xcode/Archives/*/*.xcarchive | head -1)
APP="$A/Products/Applications/Stack the Lineup.app"
echo "app:    $(plutil -extract CFBundleShortVersionString raw "$APP/Info.plist") ($(plutil -extract CFBundleVersion raw "$APP/Info.plist"))"
W=$(ls -d "$APP/PlugIns/"*.appex | head -1)
echo "widget: $(plutil -extract CFBundleShortVersionString raw "$W/Info.plist") ($(plutil -extract CFBundleVersion raw "$W/Info.plist"))"
```

- [ ] Both lines read **`3.3 (36)`**

They must match each other. A mismatch is the 1.1 bug and App Store Connect rejects it at validation. If they differ, or the number isn't 36, **re-archive** — you're looking at a stale build.

*Run 7 Aug: this returned `app 3.3 (35)` / `widget 3.3 (34)` on the 6 Aug 10:03 PM archive — the mismatch, caught here. Re-archive required.*

### 0b. Coverage instrumentation — ✅ settled, no action

```bash
nm "$(ls -td ~/Library/Developer/Xcode/Archives/*/*.xcarchive | head -1)/Products/Applications/Stack the Lineup.app/Stack the Lineup" | grep -c __llvm_prf
```

- [ ] Prints **`0`**

*Run 7 Aug: **0** for both the app and the widget.* This answers the question that was open — a plain `xcodebuild build -configuration Release` instruments with `-profile-generate` and produces ~9,000 profiling symbols, but **the Archive action does not**. Nothing to fix. Keep the check as a cheap regression guard if the scheme's Test options are ever edited.

### 0c. Push environment — check the **export**, not the archive

> ⚠️ **Do not run this against the `.xcarchive`.** It will say `development` even when everything is correct. With automatic signing, Xcode archives using the development certificate and **re-signs at distribution time** — the archive's own entitlements are the pre-signing state. (Confirmed 7 Aug: the archive shows `aps-environment: development` *and* `get-task-allow: true`, which together just mean "development-signed archive," not "broken build.")

Check the artifact that actually ships. In Organizer → **Distribute App** → choose **App Store Connect**, then either **Export** to disk, or upload and use the Export step's copy. Then:

```bash
codesign -d --entitlements :- "/path/to/exported/Payload/Stack the Lineup.app" 2>/dev/null | grep -A1 aps-environment
```

- [ ] Prints **`production`**

If it prints `development`, **stop**. The app registers against sandbox APNs, the tokens it writes to CloudKit are invalid for the production host the Worker uses, and §3 fails in a way that looks exactly like a broken Worker.

**Simpler alternative if you'd rather not export a copy:** skip this and let §3 be the test. If the push arrives, the environment was right. This check only exists to tell a signing problem apart from a Worker problem *before* you spend the device session on it.

---

## §1 — Siri phrases (backlog 1.3)

**Nine shortcuts, 27 phrases, all spoken aloud.** Spoken invocation has never been proven outside a simulator.

**This is a controlled comparison, not a fresh sweep.** A device run on 2 Aug 2026 found that phrases *ending* "…in Stack the Lineup" lose to Siri's own handlers — Siri commits to a system intent before the phrase ever names the app, so `entities(matching:)` is never called. Five shortcuts failed that way and were reworded to lead with the app name. **The four that passed were deliberately left alone.**

Better still: each reworded shortcut kept **one trailing-form phrase** as its third. So every one of those five is its own A/B. Record L and T results separately — that's the whole point.

**L** = app name leads · **T** = app name trails

Say each phrase to Siri out loud. Mark ✓ if the right thing happens, ✗ if Siri answers with something else — and **write down what Siri said instead**, because "I can't find that in Apple Music" and "would you like to use ChatGPT" are diagnostic: they mean Siri never routed to us.

### The five that failed on 2 Aug — the real test

**Open Player** · voice-only (every phrase has an entity slot) · free

- [ ] **L** — "In Stack the Lineup, look up ⟨player⟩"
- [ ] **L** — "In Stack the Lineup, pull up ⟨player⟩"
- [ ] **T** — "Look up ⟨player⟩ in Stack the Lineup"
- Expect: app opens on that player. 2 Aug failure was → *"I can't find that in Apple Music"*

**Open Team** · voice-only · free

- [ ] **L** — "In Stack the Lineup, switch my team to ⟨team⟩"
- [ ] **L** — "In Stack the Lineup, look up ⟨team⟩"
- [ ] **T** — "Switch my team to ⟨team⟩ in Stack the Lineup"
- Expect: switches to that team. 2 Aug failure was → *"it doesn't look like you have an app called that"* (Siri took the team name for an app name)

**Game Recap** · **Pro** · answers by voice without opening the app

- [ ] **L** — "In Stack the Lineup, how did we do"
- [ ] **L** — "In Stack the Lineup, recap my last game"
- [ ] **T** — "Recap my last game in Stack the Lineup"
- Expect: spoken recap of the last archived game. Not Pro → paywall, not an error

**Pitch Limits** · free

- [ ] **L** — "In Stack the Lineup, what's my pitch limit"
- [ ] **L** — "In Stack the Lineup, how many pitches are allowed"
- [ ] **T** — "Pitch limits in Stack the Lineup"
- Expect: your configured pitch limit. This was the only one of the three rules tiles that failed — the other two run the *same intent* with a different topic and both worked, so the intent is sound and the phrasing lost

**Can They Pitch** · voice-only · free

- [ ] **L** — "In Stack the Lineup, can ⟨player⟩ pitch"
- [ ] **L** — "In Stack the Lineup, is ⟨player⟩ rested"
- [ ] **T** — "Can ⟨player⟩ pitch in Stack the Lineup"
- Expect: eligibility answer for that player. 2 Aug failure was → *"would you like to use ChatGPT for that?"*

### The four controls — untouched since they passed

If any of these now **fail**, the rewording broke something that was working, and that matters more than any individual success above.

**Open Lineup** · free

- [ ] **L** — "Open Stack the Lineup"
- [ ] **T** — "Show my lineup in Stack the Lineup"
- [ ] **T** — "Open today's lineup in Stack the Lineup"

**Fill Lineup** · **Pro**

- [ ] **T** — "Fill my lineup in Stack the Lineup"
- [ ] **T** — "Auto-fill positions in Stack the Lineup"
- [ ] **T** — "Fill the positions in Stack the Lineup"
- Expect: positions auto-fill. Not Pro → paywall, not an error

**My Rules** · free

- [ ] **T** — "What are my rules in Stack the Lineup"
- [ ] **T** — "My fair play rules in Stack the Lineup"
- [ ] **T** — "Check my team rules in Stack the Lineup"

**Rest Days** · free

- [ ] **T** — "How many days rest in Stack the Lineup"
- [ ] **T** — "Rest day rules in Stack the Lineup"
- [ ] **T** — "When can my pitcher pitch again in Stack the Lineup"

### How to read the results

| What you see | What it means |
|---|---|
| L works, T fails, across the five | **Placement theory confirmed.** Drop the trailing phrases in 3.4 |
| Both L and T work | Something else was wrong on 2 Aug — possibly the missing `INAlternativeAppNames`, added the same day |
| L still fails | The rewording didn't address it. Record Siri's exact answer; it names which system handler won |
| A control now fails | Regression. Higher priority than any of the above |

**Three shortcuts can only be tested by voice** — Open Player, Open Team, Can They Pitch. Every one of their phrases carries an entity slot, and typed Spotlight matches shortcut *titles*, so they never appear as tiles. If spoken resolution doesn't work for these, they're reachable only by hand-building a shortcut.

> ⚠️ Backlog 1.3 says **two** intents are voice-only and names Open Player and Can They Pitch. It's **three** — Open Team qualifies identically, and 1.3's own list of six parameter-free tiles implies it (9 − 6 = 3). Corrected here; fix 1.3 after the session.

- [ ] **Done:** all 27 spoken, results recorded

---

## §2 — iPad read-only with a real shared team (backlog 1.4)

**Source:** `CLEANUP-AUDIT-2026-08.md`, "Test plan: iPad read-only (2.4a)".

Fixed in code 6 Aug, never verified on hardware. Before the fix, a view-only participant on iPad could reassign positions, reorder the batting order, clear positions, and finalize the lineup — which notifies the whole team.

**Setup:** device A shares a team; the iPad accepts as **view-only**, then opens Positions. Everything below should be **blocked** on iPad, and already is on iPhone.

- [ ] **1. Banner and strip** — read-only banner above the status strip; strip reads "View only" where Finalize/Reopen would be. Neither Finalize nor Reopen reachable.
- [ ] **2. By Inning** — tapping a field slot does nothing, no picker sheet. Bench and absent chips don't respond. "+ Bench", "+ Absent" and Auto-Fill are absent.
- [ ] **3. By Position** — tapping any matrix cell does nothing, including benched-player chips in the gray wells.
- [ ] **4. Pitching** — tapping a row does not open the pitching assignment sheet.
- [ ] **5. Sidebar** — no "+" add-players menu; batting-order rows can't be dragged.
- [ ] **6. Clear positions** — the button is absent below the pane.
- [ ] **7. ⚠️ Regression, same iPad, editable team** — switch to a team you own and confirm **every one of the above works normally.**
- [ ] **8. Chip cosmetics** — bench/absent chips on iPad are 1pt tighter with a 2pt taller badge. Compare against iPhone; they should look like the same component, because now they are.

> **Step 7 is the one not to skip.** The gating is per-team, not per-device, and the plausible way to get this wrong is to over-gate and lock a coach out of their own team. A pass on 1–6 with a fail on 7 is worse than the bug you're testing for.

---

## §3 — The push that has never been sent (backlog 1.4 / 1.2)

Do this while the shared team is still set up. **APNs has never delivered a real push from this app.** The Worker's health check uses a nonexistent team, so it matches zero device tokens and returns before ever contacting Apple. The production APNs host is deployed but completely unexercised.

- [ ] From the **owning** device, finalize a lineup
- [ ] Confirm the notification **arrives on the other device**

If nothing arrives, check in this order — cheapest first, and note that the first two are far more likely than the third:

1. **§0a** — did the archive embed `development`? Sandbox tokens can't receive production pushes.
2. **Notification permission** granted on the receiving device, and the app has been launched there at least once so it has registered a token.
3. Only then the Worker. Health check (sends nothing, safe any time):

```bash
curl -sS -X POST https://stl-push-worker.stackthelineup.workers.dev \
  -H "Content-Type: application/json" \
  -d '{"teamID":"00000000-0000-0000-0000-000000000000","eventType":"lineup_finalized","triggeredBy":"healthcheck"}' \
  -w "\nHTTP %{http_code}\n"
```

`{"sent":0}` / 200 = CloudKit auth is fine and the fault is elsewhere. `Internal error` / 500 = CloudKit auth is broken again.

> **Don't trust Cloudflare's error rate.** It read 0% through the entire 6 Aug outage, because the Worker catches its own throw and returns a 500 *response* — only unhandled exceptions count. Watch Observability → Events, or the `sent` count. Workers Logs are enabled.

---

## §4 — Tips (backlog 2.3, 2.4)

### 4a. The one unverified tip transition (2.3)

`ReuseSaveTemplateTip`'s live **in-place** advance: dismiss tip 2 → tip 3 appears **without leaving `GameLogDetailView`**. It uses the identical pattern already verified on the lead history tip on both platforms, so this is confirmation, not investigation.

**Needs Pro** — all three history tips live behind the paywall.

- [ ] Settings → Help & Support → **"Take the Tour"** to reset the tip datastore
- [ ] Archive a game so arc 2 is eligible
- [ ] Open a game in History → `GameLogDetailView`
- [ ] `HistoryCopyGameTip` ("Or start from a game you played") presents on the first Reuse row
- [ ] Tap **Next** — `ReuseSaveTemplateTip` ("Don't build that twice") appears on the second row **without navigating away**

> **Gotcha:** if tips stay suppressed, a reset from a *live* session can get silently undone. "Take the Tour" now works, so a reset + re-walk should be enough — but if it misbehaves, a full **uninstall + reinstall** is the reliable way to a pristine datastore. Reinstalling *over* keeps the stale TipKit datastore.
>
> The 7-tap debug seeder needs each tap within 2s of the last — easy by hand, impossible to automate.

### 4b. Tip copy at real size (2.4)

Tip copy has **never** been read on a device. Popover width is narrower than the spec tables suggest.

- [ ] Walk the tips at **default** Dynamic Type — copy reads cleanly, nothing truncates
- [ ] Settings → Accessibility → Display & Text Size → Larger Text, near **maximum**
- [ ] Re-walk — note every tip whose copy truncates, wraps badly, or overflows its popover

Record the ones that need trimming; the edit itself is a follow-up, not part of this session.

---

## When you're done

- [ ] Update `BACKLOG.md`: strike 1.5, 1.3, 1.4, 2.3, 2.4 as they pass
- [ ] Fix 1.3's "two intents are voice-only" → **three** (see §1)
- [ ] Record any Siri phrases that still fail, with **Siri's exact wording** — that text identifies which system handler won
- [ ] Log 2.4's trim list somewhere durable
- [ ] If §0 failed: re-archive before doing anything else with this build

**Then 3.3 is submittable.** Everything in Stages 3 and 4 is deferred by choice and should stay deferred until it ships.
