import Foundation

// MARK: - AutoFillEngine
// Pure, stateless algorithm for filling unassigned positions in a Lineup.
// Never modifies any slot that already has a coach assignment — those are
// always treated as locked.
//
// FIELD SLOT ORDERING (who gets field positions first):
//   1. Players who were benched last inning (they need out most)
//      — within that group, fair play need honoured: missing infield first,
//        then missing outfield, then no constraint
//   2. Players still missing an infield inning
//   3. Players still missing an outfield inning
//   4. Everyone else
//
// BENCH SLOT ORDERING (who sits when roster > 9 field slots):
//   Sorted ascending by bench innings so far (fewest bench innings sits next).
//   Ties broken by: no back-to-back risk preferred, then consecutive field
//   innings played (longer streak → more eligible for a rest).
//   Back-to-back bench is avoided where possible but assigned anyway if
//   unavoidable — the Fair Play warning system surfaces it.
//
// POSITION PREFERENCES:
//   When a preferences dict is supplied, position selection within each fair-play
//   tier is preference-aware:
//     1. Strength positions tried first (within the required zone when applicable)
//     2. Capable positions tried second
//     3. Untagged (—) positions tried third
//     4. Emergency positions tried last
//     5. Never positions are always excluded — player falls to bench if all
//        remaining open positions are Never for them

enum AutoFillEngine {

    // MARK: - Public API

    /// Fills open slots in a single inning. Returns (updatedLineup, filledCount).
    static func fillInning(
        _ inningIndex: Int,
        in lineup: Lineup,
        players: [Player],
        preferences: [UUID: [FieldPosition: PositionPreferenceTier]] = [:]
    ) -> (lineup: Lineup, filledCount: Int) {
        var result = lineup
        let count = fillInning(inningIndex, in: &result, players: players, preferences: preferences)
        return (result, count)
    }

    /// Fills open slots from inning 0 through `lastInning` (inclusive).
    static func fillInnings(
        through lastInning: Int,
        in lineup: Lineup,
        players: [Player],
        preferences: [UUID: [FieldPosition: PositionPreferenceTier]] = [:]
    ) -> (lineup: Lineup, filledCount: Int) {
        var result = lineup
        var total = 0
        let clampedLast = max(0, min(lastInning, lineup.innings.count - 1))
        for inning in 0...clampedLast {
            total += fillInning(inning, in: &result, players: players, preferences: preferences)
        }
        return (result, total)
    }

    /// Fills open slots across all 7 innings. Returns (updatedLineup, filledCount).
    static func fillGame(
        in lineup: Lineup,
        players: [Player],
        preferences: [UUID: [FieldPosition: PositionPreferenceTier]] = [:]
    ) -> (lineup: Lineup, filledCount: Int) {
        return fillInnings(through: lineup.innings.count - 1, in: lineup, players: players, preferences: preferences)
    }

    // MARK: - Private Core

    @discardableResult
    private static func fillInning(
        _ inningIndex: Int,
        in lineup: inout Lineup,
        players: [Player],
        preferences: [UUID: [FieldPosition: PositionPreferenceTier]]
    ) -> Int {
        let active = lineup.activePlayers(from: players)
        guard !active.isEmpty else { return 0 }

        var unassigned = active.filter {
            lineup.innings[inningIndex].position(for: $0) == nil
        }
        guard !unassigned.isEmpty else { return 0 }

        let occupiedPositions = Set(
            lineup.innings[inningIndex].assignments.values.filter { !$0.isBench }
        )
        var openPositions = FieldPosition.fieldPositions
            .filter { !occupiedPositions.contains($0) }
            .shuffled()

        var filled = 0

        // MARK: - Stat Helpers

        func benchInningsSoFar(_ player: Player) -> Int {
            (0..<inningIndex).filter {
                lineup.innings[$0].position(for: player) == .bench
            }.count
        }

        func benchedLastInning(_ player: Player) -> Bool {
            guard inningIndex > 0 else { return false }
            return lineup.innings[inningIndex - 1].position(for: player) == .bench
        }

        func consecutiveFieldInnings(_ player: Player) -> Int {
            var count = 0
            var i = inningIndex - 1
            while i >= 0 {
                if let pos = lineup.innings[i].position(for: player), !pos.isNonFielding {
                    count += 1
                    i -= 1
                } else {
                    break
                }
            }
            return count
        }

        func needsInfield(_ player: Player) -> Bool {
            !lineup.innings.contains(where: { $0.position(for: player)?.isInfield == true })
        }

        func needsOutfield(_ player: Player) -> Bool {
            !lineup.innings.contains(where: { $0.position(for: player)?.isOutfield == true })
        }

        // MARK: - Preference Helper
        //
        // Given a set of candidate positions and a player, returns the best position
        // using preference tiers: Strength → Capable → untagged → Emergency.
        // Never positions are excluded entirely.
        // Returns nil if all candidates are tagged Never (player should bench instead).
        // Fair play zone constraints (infield/outfield) are applied before this
        // function is called — candidates are already zone-filtered when needed.

        func preferredPosition(for player: Player, from candidates: [FieldPosition]) -> FieldPosition? {
            let prefs = preferences[player.id] ?? [:]
            let allowed = candidates.filter { prefs[$0] != .never }
            guard !allowed.isEmpty else { return nil }

            // Strength
            if let pos = allowed.first(where: { prefs[$0] == .strength }) { return pos }
            // Capable
            if let pos = allowed.first(where: { prefs[$0] == .capable }) { return pos }
            // Untagged (no preference — neutral)
            if let pos = allowed.first(where: { prefs[$0] == nil }) { return pos }
            // Emergency as last resort
            return allowed.first(where: { prefs[$0] == .emergency })
        }

        // MARK: - Field Assignment Queue

        let benchedLast = unassigned.filter { benchedLastInning($0) }.shuffled()
        let needsIF = unassigned.filter { !benchedLastInning($0) && needsInfield($0) }.shuffled()
        let needsOF = unassigned.filter { !benchedLastInning($0) && !needsInfield($0) && needsOutfield($0) }.shuffled()
        let rest    = unassigned.filter { !benchedLastInning($0) && !needsInfield($0) && !needsOutfield($0) }.shuffled()

        let fieldQueue: [Player] = benchedLast + needsIF + needsOF + rest

        for player in fieldQueue {
            guard !openPositions.isEmpty else { break }

            var assigned = false
            // Track which zones were attempted but fully blocked by Never,
            // so the fallthrough pass doesn't re-offer those same positions.
            var neverBlockedInfield = false
            var neverBlockedOutfield = false

            // Try to satisfy the infield fair-play requirement first.
            if needsInfield(player) {
                let infieldCandidates = openPositions.filter { $0.isInfield }
                if infieldCandidates.isEmpty {
                    // No open infield slots left at all — not a Never issue
                } else if let pos = preferredPosition(for: player, from: infieldCandidates) {
                    lineup.innings[inningIndex].assign(player: player, position: pos)
                    openPositions.removeAll { $0 == pos }
                    unassigned.removeAll { $0.id == player.id }
                    filled += 1
                    assigned = true
                } else {
                    // preferredPosition returned nil — all infield candidates are Never
                    neverBlockedInfield = true
                }
            }

            // Try outfield fair-play requirement, preference-aware.
            if !assigned && needsOutfield(player) {
                let outfieldCandidates = openPositions.filter { $0.isOutfield }
                if outfieldCandidates.isEmpty {
                    // No open outfield slots left at all
                } else if let pos = preferredPosition(for: player, from: outfieldCandidates) {
                    lineup.innings[inningIndex].assign(player: player, position: pos)
                    openPositions.removeAll { $0 == pos }
                    unassigned.removeAll { $0.id == player.id }
                    filled += 1
                    assigned = true
                } else {
                    neverBlockedOutfield = true
                }
            }

            // No zone requirement, or zone was blocked by Never.
            // Exclude any zones that were explicitly blocked by Never —
            // this prevents a Never position from being selected in the fallthrough.
            if !assigned {
                var fallbackCandidates = openPositions
                if neverBlockedInfield  { fallbackCandidates = fallbackCandidates.filter { !$0.isInfield } }
                if neverBlockedOutfield { fallbackCandidates = fallbackCandidates.filter { !$0.isOutfield } }

                if let pos = preferredPosition(for: player, from: fallbackCandidates) {
                    lineup.innings[inningIndex].assign(player: player, position: pos)
                    openPositions.removeAll { $0 == pos }
                    unassigned.removeAll { $0.id == player.id }
                    filled += 1
                    assigned = true
                }
                // If still not assigned, all remaining positions are Never for this
                // player — they fall through to the bench queue below.
                _ = assigned // suppress unused warning
            }
        }

        // MARK: - Bench Assignment Queue

        let stillUnassigned = active.filter {
            lineup.innings[inningIndex].position(for: $0) == nil
        }

        let benchQueue = stillUnassigned.sorted { a, b in
            let aBench = benchInningsSoFar(a)
            let bBench = benchInningsSoFar(b)
            if aBench != bBench { return aBench < bBench }

            let aStreak = consecutiveFieldInnings(a)
            let bStreak = consecutiveFieldInnings(b)
            if aStreak != bStreak { return aStreak > bStreak }

            let aRisk = benchedLastInning(a) ? 1 : 0
            let bRisk = benchedLastInning(b) ? 1 : 0
            return aRisk < bRisk
        }

        var backToBackCandidates: [Player] = []
        for player in benchQueue {
            if benchedLastInning(player) {
                backToBackCandidates.append(player)
            } else {
                lineup.innings[inningIndex].assign(player: player, position: .bench)
                filled += 1
            }
        }

        for player in backToBackCandidates {
            lineup.innings[inningIndex].assign(player: player, position: .bench)
            filled += 1
        }

        return filled
    }
}
