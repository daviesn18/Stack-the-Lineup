#!/usr/bin/env bash
#
# Phase 1 cleanup — Stack the Lineup codebase audit
# Generated from CLEANUP-AUDIT.md. See that report for the evidence behind
# every item below.
#
# WHAT THIS DOES
#   Removes ~447 lines of code that nothing in the repo references:
#     - 3 dead files (2 duplicate .entitlements, 1 never-compiled test file)
#     - 4 unreachable SwiftUI views in DefensiveGridView.swift
#     - 1 unused import
#   Applies one patch (cleanup-phase1.patch) to DefensiveGridView.swift.
#
# WHAT THIS DOES *NOT* DO
#   Phase 2 and Phase 3 items are excluded by design. Nothing here touches
#   CloudKit, DeviceTokenManager, DebugDataSeeder, Models.swift, the Xcode
#   project file, or any file with uncommitted working-tree changes.
#
# BEFORE YOU MERGE
#   1. Build the "Lineup Builder" scheme (Cmd+B).
#   2. Build the "STLWidgetExtension" scheme.
#   3. Run the "Lineup BuilderTests" suite (Cmd+U).
#   4. Read `git diff --cached` — this touches real UI files.
#
# Everything is staged, not committed. Nothing here is irreversible.

set -euo pipefail

cd "$(dirname "$0")"

if ! git diff --quiet -- "Lineup Builder/DefensiveGridView.swift"; then
  echo "ERROR: DefensiveGridView.swift has uncommitted changes." >&2
  echo "The patch was built against the committed version. Commit or stash first." >&2
  exit 1
fi

if [ ! -f cleanup-phase1.patch ]; then
  echo "ERROR: cleanup-phase1.patch not found next to this script." >&2
  exit 1
fi

echo "==> Verifying patch applies cleanly..."
git apply --check cleanup-phase1.patch

# ---------------------------------------------------------------------------
# File deletions
# ---------------------------------------------------------------------------

# Finding 5.1 — superseded first-draft test suite. Never compiled: it imports
# module "LineupBuilder" (placeholder comment still says "replace with your
# actual module name"; the real module is Lineup_Builder), and the
# StackTheLineupTests target has an empty Sources build phase with no
# synchronized root group. Superseded by Lineup BuilderTests/DataIntegrityTests.swift.
git rm --quiet "StackTheLineupTests/StackTheLineupTests.swift"

# Finding 7.1 — byte-identical duplicate of "Lineup Builder/Lineup Builder.entitlements",
# which is the file referenced by CODE_SIGN_ENTITLEMENTS (project.pbxproj:672, :723).
# Zero references to this underscore variant anywhere.
git rm --quiet "Lineup Builder/Lineup_Builder.entitlements"

# Finding 7.2 — byte-identical duplicate of the root STLWidgetExtension.entitlements,
# which is the file referenced by CODE_SIGN_ENTITLEMENTS (project.pbxproj:484, :517).
# Zero references to this copy.
git rm --quiet "STLWidget/STLWidget.entitlements"

# ---------------------------------------------------------------------------
# Line-level edits — Lineup Builder/DefensiveGridView.swift
# ---------------------------------------------------------------------------
#
# The patch makes four changes, all verified against the current file contents:
#
#   line 2         Remove `import StoreKit`. No StoreKit symbol appears in the
#                  file; `purchaseManager` is the app's own PurchaseManager type.
#
#   lines 1870-2003  Remove `PlayerInningRow` and its MARK header. One repo-wide
#                    reference: the declaration itself.
#
#   line 2502      Correct the "Pitch Availability Helpers" section comment,
#                  which claims the section "provides badge + strip card views"
#                  — no longer true once the cluster below is gone.
#
#   lines 2551-2739  Remove PitchAvailabilityBadge, PitcherStripCard, and
#                    PitcherAvailabilityStrip. Reachable only from each other.
#                    The range deliberately starts AFTER the closing brace of
#                    pitchesRemaining() at line 2549 — that function is live
#                    (AutoFillEngine.swift:516, PositionSummaryView.swift:1002,
#                    DefensiveGridView.swift:2037) and must stay.

echo "==> Applying DefensiveGridView.swift patch..."
git apply cleanup-phase1.patch
git add "Lineup Builder/DefensiveGridView.swift"

# ---------------------------------------------------------------------------

echo
echo "==> Staged. Summary:"
git diff --cached --stat
echo
echo "Next: build both schemes, run the test suite, then review 'git diff --cached'."
echo "To undo everything: git reset --hard HEAD"
