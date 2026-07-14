# Handoff — Data Wipe Recovery + Sync Hardening (2026-07-13)

## TL;DR

A debug build install replaced the real teams/history on Nick's iPhone with dev-test data. **The real data is not destroyed**: it exists in production CloudKit, and the iPad (unused for weeks, app NOT launched since) still holds an uncorrupted local copy. Recovery is blocked only on unlocking the iPad to pull its container. Two sync-hardening fixes must ship before any build touches a physical device again.

---

## 1. Incident summary (root-caused, confirmed with evidence)

**Mechanism:** `applyStoredData()` in `Lineup Builder/Models.swift:1230-1277` reads the `stl_teams` blob from `NSUbiquitousKeyValueStore` **in preference to** local `UserDefaults`. The iCloud KV store is shared across *every* install of the bundle ID on the same Apple ID — including debug builds and simulators — with no dev/prod split (unlike CloudKit) and **no freshness check**. A dev run (with test teams `TeamA`, `TeamB`, and `DebugDataSeeder`'s `Test Team`) saved and pushed that blob to iCloud KV. When the new build launched on the iPhone, the KV blob was preferred over the phone's good local data, and the next save persisted it locally.

**Evidence** (pulled from the iPhone via `devicectl`, snapshot preserved):
- `~/Desktop/stl-recovery-2026-07-13/iphone-prefs-snapshot.plist` — the phone's current UserDefaults.
- Its `stl_teams` blob = 3 teams: `TeamA` (empty), `TeamB` (empty), `Test Team` (10 players, 5 game logs — exact `DebugDataSeeder` output).
- Orphaned keys `lastNotifiedFinalize_39309E35-4CBF-4A34-AACD-CA120400EE22` and `nudge_dismissed_date_39309E35-...` prove a real team with that UUID existed and is now missing from the blob.
- `hasCompletedCloudKitMigration = True` → real teams were uploaded to **production** CloudKit. Debug builds talk to the **Development** CloudKit environment, so production records are untouched.

**Not the cause:** this session's working-tree changes. Bundle ID and app entitlements file are unchanged (`Lineup_Builder.entitlements` with underscore exists but is NOT referenced by any target — app still uses `Lineup Builder/Lineup Builder.entitlements`). CloudKitManager diffs are analytics-only; model decoding changes are defensive both directions. This is a latent v3.0 design flaw that the install triggered.

**Nick's standing rule (saved to memory):** debug builds run on **simulators only**, never his physical iPhone/iPad.

---

## 2. Recovery — next steps, in order

1. **Pull the iPad container FIRST** (blocked on device unlock last session). iPad = `Nick's iPad`, identifier `28DC5FC7-51F0-5538-AE71-5B8A4455B830`, paired over network. Nick must unlock it to the home screen and **not open Lineup Builder on it** (data on disk is safe until the app launches and applies the poisoned KV sync). Then:
   ```
   xcrun devicectl device copy from \
     --device 28DC5FC7-51F0-5538-AE71-5B8A4455B830 \
     --domain-type appDataContainer \
     --domain-identifier "com.nickdavies.LineupBuilder.Lineup-Builder" \
     --source Library/Preferences/com.nickdavies.LineupBuilder.Lineup-Builder.plist \
     --destination ~/Desktop/stl-recovery-2026-07-13/ipad-prefs-snapshot.plist
   ```
   Decode and verify with python `plistlib` + `json` (same as done for the phone: check team names, player counts, gameLog counts in `stl_teams`). This is the complete offline backup.
2. **Verify production CloudKit** (Nick, in browser): [CloudKit Console](https://icloud.developer.apple.com) → container `iCloud.com.nickdavies.LineupBuilder.Lineup-Builder` → **Production** → private database (act as own iCloud account) → zone `STLTeams`. Expect records like `team-39309E35-4CBF-4A34-AACD-CA120400EE22`.
3. **Ship the hardening fixes (section 3) BEFORE running the app anywhere signed into Nick's Apple ID.** Otherwise recovery can be re-clobbered by the same mechanism — the poisoned blob is still in the iCloud KV cloud.
4. **Restore the iPhone.** Preferred path: install the TestFlight/App Store build → it reads production CloudKit → `fetchCloudKitChanges` merges the real teams back in (they append by `ckRecordName`; the junk teams remain and can be deleted in-app). Alternative if TestFlight isn't handy: temporarily add `com.apple.developer.icloud-container-environment = Production` to `Lineup Builder/Lineup Builder.entitlements` for a device run — but only after the fixes in section 3, and remove it afterward.
5. **Clean up:** delete `TeamA`/`TeamB`/`Test Team` in-app after real teams are back; a subsequent save overwrites the poisoned iCloud KV blob with good data. Consider also deleting the junk `team-...` records from CloudKit Development env (cosmetic).

**Standing cautions until recovery is done:**
- Do NOT open the app on the iPad.
- Do NOT edit anything in the app on the iPhone (each save re-persists the junk state; the KV cloud blob is already poisoned so launches alone add no new damage on the phone).
- `Micah's iPhone` (family member device) may also run the app — same caution applies if it shares the Apple ID (unlikely, but check).

---

## 3. Fixes to implement (agreed direction, not yet written)

Both in `Lineup Builder/Models.swift` (`LineupStore`):

1. **Freshness-stamped sync blob.** Alongside `stl_teams`, write `stl_teams_saved_at` (Date/epoch) to both UserDefaults and KV in `saveLocalOnly()`/`save()`. In `applyStoredData()`, choose between the KV copy and the local copy by newest timestamp instead of always preferring KV. Treat a missing timestamp as oldest (legacy blobs). This also fixes the pre-existing staleness trap: the >800KB KV skip (`saveLocalOnly`, `Models.swift:1156-1162`) freezes KV at its last small value forever, and that frozen copy currently shadows newer local data on every launch.
2. **Debug builds must not write shared sync state.** Gate the `NSUbiquitousKeyValueStore` writes (and ideally reads) behind `#if !DEBUG`, or use a `stl_teams_debug` key in DEBUG. `DebugDataSeeder` output must never be able to reach production devices again.

Also worth considering while in there (lower priority):
- Guard in `applyStoredData`/merge: log an Analytics signal when an incoming blob has dramatically less data (fewer teams / fewer total game logs) than the current one — cheap detection for any future variant of this bug.
- The empty-teams first-launch path (`migrateOrCreateDefaultTeam`, `Models.swift:1429`) is already safe (doesn't save unless legacy data found) — verified, no change needed.

Existing tests to keep green: `DataIntegrityTests`, `LineupStoreTests` (all 91 unit tests passed at session end). Add tests for the timestamp-preference logic if practical (LineupStore is UserDefaults-backed; follow the existing `LineupStoreTests` pattern).

---

## 4. Separate work completed this session (NL Auto-Fill) — done, unreleased

Context: applied/verified the spec in `~/Downloads/NL-AutoFill-View-Changes-2.md`. All spec changes were already present in `DefensiveGridView.swift`, `iPadDashboardView.swift`; no changes needed in `PositionSummaryView.swift`.

Bug fixes made in `Lineup Builder/AutoFillNLConstraintService.swift`:
1. `respond(to:schema:)` requires `GenerationSchema` — `dynamicSchema()` now returns `try GenerationSchema(root:dependencies:)` instead of the raw `DynamicGenerationSchema` (was a compile error; verified against current FoundationModels docs).
2. Dropped `ObservableObject` conformance (no Combine import, nothing observes it — views hold it as plain `@State`).
3. Dropped-clause heuristic: ambiguous abbreviations `OF/IF/P/C` now match **case-sensitively uppercase only** (bare lowercase "of"/"if" in ordinary English was a false-positive source); other placement phrases match case-insensitively.
4. Heuristic parsed-count now subtracts exactly the implicit avoid-Pitcher constraints added by `withImplicitPitcherAvoids` (recomputed via `complementRanges`), instead of filtering all avoid-Pitcher constraints — a coach's explicit "don't let Sam pitch" no longer causes a false alert.

State: builds clean, 91/91 unit tests pass, heuristic validated against 8 representative prompts via RunCodeSnippet. **Everything is uncommitted working-tree changes** (along with the larger pre-existing uncommitted 3.1 feature work: templates, schedule import, widget, game log notes). The dynamic-schema path still needs a real-device Apple Intelligence run — which is blocked on the recovery + hardening above, per the simulator-only rule.

## 5. Memory files (already saved, auto-loaded next session)

- `data-wipe-incident-2026-07` — incident + recovery pointers
- `debug-builds-simulator-only` — Nick's device rule
- `nl-autofill-deferred-items` — pre-existing deferred NL Auto-Fill items
