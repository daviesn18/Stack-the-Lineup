import Foundation

// MARK: - AutoFill Result Types

/// Why a specific field position could not be filled during auto-fill.
enum AutoFillUnfilledReason {
    /// The active roster has fewer players than field slots — all players
    /// were assigned somewhere, but open positions remain.
    case rosterTooSmall
    /// Every remaining unassigned player has this position set to Never
    /// in their preferences.
    case neverPreferences
    /// The pitcher slot could not be filled because all pitcher-eligible
    /// players have already exited the mound (re-entry rule), and the
    /// force-fill pass found no eligible candidates.
    case pitcherReentry
    /// The pitcher slot could not be filled because every pitcher-eligible
    /// player has already been assigned the maximum number of pitcher innings
    /// estimated from their available pitch count (pitches remaining / 20).
    /// Only applies when pitching rules are enabled.
    case pitchCapacityLimited
}

/// A field position that auto-fill could not assign in a given inning.
struct AutoFillUnfilledSlot {
    let inningIndex: Int
    let position: FieldPosition
    let reason: AutoFillUnfilledReason
}

/// The complete result returned by every AutoFillEngine public method.
struct AutoFillResult {
    let lineup: Lineup
    let filledCount: Int
    /// Positions that could not be filled, with a reason for each.
    /// Empty when every open slot was successfully assigned.
    let unfilledSlots: [AutoFillUnfilledSlot]

    var hasUnfilledSlots: Bool { !unfilledSlots.isEmpty }

    /// Returns a coach-readable explanation of why positions could not be filled,
    /// or nil if every slot was assigned. Pass multiInning: true when the fill
    /// covered more than one inning so the message includes inning numbers.
    func incompleteMessage(multiInning: Bool) -> String? {
        guard !unfilledSlots.isEmpty else { return nil }

        func label(for group: [AutoFillUnfilledSlot]) -> String {
            if multiInning {
                var byPos: [FieldPosition: [Int]] = [:]
                for slot in group { byPos[slot.position, default: []].append(slot.inningIndex + 1) }
                return byPos
                    .sorted { $0.key.rawValue < $1.key.rawValue }
                    .map { pos, innings in
                        let numbers = innings.sorted().map { "\($0)" }.joined(separator: ", ")
                        let qualifier = innings.count == 1 ? "Inning \(numbers)" : "Innings \(numbers)"
                        return "\(pos.rawValue) (\(qualifier))"
                    }
                    .joined(separator: ", ")
            } else {
                return group.map { $0.position.rawValue }.joined(separator: ", ")
            }
        }

        var parts: [String] = []

        let rosterSlots = unfilledSlots.filter { $0.reason == .rosterTooSmall }
        if !rosterSlots.isEmpty {
            parts.append("\(label(for: rosterSlots)) could not be filled. Not enough active players to cover every field position. Mark additional players as active on the Lineup tab, or assign these slots manually.")
        }

        let reentrySlots = unfilledSlots.filter { $0.reason == .pitcherReentry }
        if !reentrySlots.isEmpty {
            parts.append("\(label(for: reentrySlots)) could not be filled. All eligible pitchers have already left the mound this game and cannot re-enter. Assign pitcher manually.")
        }

        let capacitySlots = unfilledSlots.filter { $0.reason == .pitchCapacityLimited }
        if !capacitySlots.isEmpty {
            parts.append("\(label(for: capacitySlots)) could not be filled. All eligible pitchers have reached their estimated pitch count limit for today. Assign pitcher manually or adjust pitch counts on the Players tab.")
        }

        let neverSlots = unfilledSlots.filter { $0.reason == .neverPreferences }
        if !neverSlots.isEmpty {
            parts.append("\(label(for: neverSlots)) could not be filled. All remaining players have those positions set to Never in their preferences. Update preferences on the Players tab, or assign manually.")
        }

        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }
}

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
//
// PITCH COUNT AWARENESS:
//   When a PitchingConfig (with rulesEnabled=true) and gameLogs are supplied,
//   the engine estimates how many pitcher innings each player can take based
//   on their available pitch count. Uses a conservative 20 pitches/inning
//   estimate (lower bound of the typical 20–25 range). A player who has
//   already been assigned that many pitcher innings this game will not be
//   auto-assigned pitcher again, even if they are otherwise eligible.
//   The pitcher force-fill pass respects this constraint as well — if all
//   eligible pitchers are at capacity, the slot is reported as unfilled with
//   reason .pitchCapacityLimited.

enum AutoFillEngine {

    /// Conservative estimate of pitches thrown per inning. Used to derive
    /// how many pitcher innings a player's remaining pitch count can support.
    /// Lower bound of the typical 20–25 range — errs toward protecting pitchers.
    private static let pitchesPerInning = 20

    // MARK: - Public API

    /// Fills open slots in a single inning. Returns an AutoFillResult.
    static func fillInning(
        _ inningIndex: Int,
        in lineup: Lineup,
        players: [Player],
        preferences: [UUID: [FieldPosition: PositionPreferenceTier]] = [:],
        config: FairPlayConfig = FairPlayConfig(),
        pitchingConfig: PitchingConfig? = nil,
        gameLogs: [GameLog] = []
    ) -> AutoFillResult {
        var result = lineup
        let (count, unfilled) = fillInning(
            inningIndex, in: &result,
            players: players,
            preferences: preferences,
            config: config,
            pitchingConfig: pitchingConfig,
            gameLogs: gameLogs
        )
        return AutoFillResult(lineup: result, filledCount: count, unfilledSlots: unfilled)
    }

    /// Fills open slots from inning 0 through `lastInning` (inclusive).
    static func fillInnings(
        through lastInning: Int,
        in lineup: Lineup,
        players: [Player],
        preferences: [UUID: [FieldPosition: PositionPreferenceTier]] = [:],
        config: FairPlayConfig = FairPlayConfig(),
        pitchingConfig: PitchingConfig? = nil,
        gameLogs: [GameLog] = []
    ) -> AutoFillResult {
        var result = lineup
        var total = 0
        var allUnfilled: [AutoFillUnfilledSlot] = []
        let clampedLast = max(0, min(lastInning, lineup.innings.count - 1))
        for inning in 0...clampedLast {
            let (count, unfilled) = fillInning(
                inning, in: &result,
                players: players,
                preferences: preferences,
                config: config,
                pitchingConfig: pitchingConfig,
                gameLogs: gameLogs
            )
            total += count
            allUnfilled.append(contentsOf: unfilled)
        }
        return AutoFillResult(lineup: result, filledCount: total, unfilledSlots: allUnfilled)
    }

    /// Fills open slots across all innings. Returns an AutoFillResult.
    static func fillGame(
        in lineup: Lineup,
        players: [Player],
        preferences: [UUID: [FieldPosition: PositionPreferenceTier]] = [:],
        config: FairPlayConfig = FairPlayConfig(),
        pitchingConfig: PitchingConfig? = nil,
        gameLogs: [GameLog] = []
    ) -> AutoFillResult {
        return fillInnings(
            through: lineup.innings.count - 1,
            in: lineup,
            players: players,
            preferences: preferences,
            config: config,
            pitchingConfig: pitchingConfig,
            gameLogs: gameLogs
        )
    }

    // MARK: - Private Core

    @discardableResult
    private static func fillInning(
        _ inningIndex: Int,
        in lineup: inout Lineup,
        players: [Player],
        preferences: [UUID: [FieldPosition: PositionPreferenceTier]],
        config: FairPlayConfig,
        pitchingConfig: PitchingConfig?,
        gameLogs: [GameLog]
    ) -> (filled: Int, unfilled: [AutoFillUnfilledSlot]) {
        let active = lineup.activePlayers(from: players)
        guard !active.isEmpty else { return (0, []) }

        var unassigned = active.filter {
            lineup.innings[inningIndex].position(for: $0) == nil
        }
        guard !unassigned.isEmpty else { return (0, []) }

        let occupiedPositions = Set(
            lineup.innings[inningIndex].assignments.values.filter { !$0.isBench }
        )

        // Build the valid position pool respecting config restrictions.
        // noPitcher/noCatcher remove those positions entirely.
        // outfielderCount=4 adds LCF/RCF and removes CF from the pool.
        var validFieldPositions = FieldPosition.fieldPositions
        if config.noPitcher       { validFieldPositions.removeAll { $0 == .pitcher } }
        if config.noCatcher       { validFieldPositions.removeAll { $0 == .catcher } }
        if config.outfielderCount == 4 {
            validFieldPositions.removeAll { $0 == .centerField }
            // LCF and RCF are already in fieldPositions via isOutfield — no additions needed
        } else {
            // Standard 3-OF: remove the 4-OF positions if somehow present
            validFieldPositions.removeAll { $0 == .leftCenterField || $0 == .rightCenterField }
        }

        var openPositions = validFieldPositions
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

        // MARK: - Pitcher Rule Helpers
        //
        // These enforce pitching rules in two tiers:
        //
        //   HARD RULES (always enforced):
        //     1. Re-entry restriction — once a player exits pitcher, they can't
        //        pitch again. Scans ALL innings, not just earlier ones, so manual
        //        assignments later in the game are respected.
        //
        //   SOFT RULES (enforced in the main pass, bypassed in force-fill):
        //     2. Two-inning cap — try to keep any single player at 2 max pitcher
        //        innings, but allow more if no other eligible pitcher remains.
        //
        //   PITCH COUNT RULES (enforced when pitchingConfig.rulesEnabled):
        //     3. Capacity check — estimated innings available = pitches remaining
        //        divided by pitchesPerInning (20). If the player has already been
        //        assigned that many pitcher innings this game, they are skipped.
        //        This is enforced in both the main pass AND the force-fill pass —
        //        there is no bypass for capacity, unlike the 2-inning soft cap.
        //
        // When config.noPitcher is true the entire pitcher block is a no-op
        // because .pitcher was already removed from openPositions above.

        /// Hard-coded soft cap for pitcher innings per player.
        let maxPitcherInningsSoftCap = 2

        func pitcherInningsSoFar(_ player: Player) -> Int {
            lineup.innings.filter { $0.position(for: player) == .pitcher }.count
        }

        /// True if the player pitched in some inning AND was assigned a
        /// non-pitcher position in any later inning. Once true, they are
        /// permanently locked out of pitcher (real Little League rule).
        func hasExitedPitcher(_ player: Player) -> Bool {
            var pitchedAt: Int?
            for (i, inning) in lineup.innings.enumerated() {
                let pos = inning.position(for: player)
                if pos == .pitcher {
                    pitchedAt = i
                } else if pos != nil, pos != .bench, pos != .absent, pitchedAt != nil, i > pitchedAt! {
                    return true
                }
            }
            return false
        }

        /// Estimated maximum pitcher innings for this game based on remaining
        /// pitch count. Returns nil when pitching rules are off or the player's
        /// limits can't be determined (unknown age, Never preference).
        /// Uses a conservative 20 pitches/inning floor so auto-fill doesn't
        /// over-assign innings to pitchers with limited availability.
        func estimatedPitcherInningsCapacity(_ player: Player) -> Int? {
            guard let pc = pitchingConfig, pc.rulesEnabled else { return nil }
            guard let remaining = pitchesRemaining(for: player, gameLogs: gameLogs, config: pc) else {
                return nil
            }
            return remaining / pitchesPerInning
        }

        /// True when the player passes all hard pitcher rules (re-entry and
        /// Never preference) without considering pitch count capacity.
        /// Used by the unfilled classifier to distinguish capacity blocks from
        /// re-entry blocks.
        func isPitcherBaseEligible(_ player: Player) -> Bool {
            if hasExitedPitcher(player) { return false }
            let prefs = preferences[player.id] ?? [:]
            if prefs[.pitcher] == .never { return false }
            return true
        }

        /// True when the player can be assigned pitcher in this inning.
        /// Enforces hard rules (re-entry, Never) and, when pitching rules are
        /// enabled, the pitch count capacity check.
        func isPitcherEligible(_ player: Player) -> Bool {
            guard isPitcherBaseEligible(player) else { return false }
            // Capacity check: don't assign more pitcher innings than the player's
            // estimated pitch budget supports.
            if let capacity = estimatedPitcherInningsCapacity(player) {
                if pitcherInningsSoFar(player) >= capacity {
                    return false
                }
            }
            return true
        }

        /// Filters a candidate position list to remove pitcher when the player
        /// can't take it. Two modes:
        ///   - allowSoftCapBypass=false (default) — exclude pitcher for any
        ///     ineligible player, AND for anyone already at the soft cap.
        ///   - allowSoftCapBypass=true — only the hard rules + capacity apply
        ///     (used when pitcher would otherwise go unfilled). Note: capacity
        ///     is never bypassed even in this mode.
        func filteringPitcher(for player: Player, candidates: [FieldPosition], allowSoftCapBypass: Bool = false) -> [FieldPosition] {
            guard candidates.contains(.pitcher) else { return candidates }
            if !isPitcherEligible(player) {
                return candidates.filter { $0 != .pitcher }
            }
            if !allowSoftCapBypass && pitcherInningsSoFar(player) >= maxPitcherInningsSoftCap {
                return candidates.filter { $0 != .pitcher }
            }
            return candidates
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
                let infieldCandidates = filteringPitcher(for: player, candidates: openPositions.filter { $0.isInfield })
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
                fallbackCandidates = filteringPitcher(for: player, candidates: fallbackCandidates)

                if let pos = preferredPosition(for: player, from: fallbackCandidates) {
                    lineup.innings[inningIndex].assign(player: player, position: pos)
                    openPositions.removeAll { $0 == pos }
                    unassigned.removeAll { $0.id == player.id }
                    filled += 1
                }
                // If still not assigned, all remaining positions are Never for this
                // player — they fall through to the bench queue below.
            }
        }

        // MARK: - Pitcher Force-Fill
        //
        // If pitcher is still open after the main field loop, the per-player
        // preference logic didn't land anyone there (e.g., everyone with
        // pitcher in their preferences was already assigned elsewhere, or
        // every unassigned player was at the soft cap).
        //
        // Force-fill it now bypassing only the 2-inning soft cap. The hard
        // re-entry rule and pitch count capacity check are still enforced —
        // better to leave pitcher open and alert the coach than to assign a
        // player who is over their pitch budget.

        if openPositions.contains(.pitcher) {
            let pitcherFallback = active.filter {
                lineup.innings[inningIndex].position(for: $0) == nil &&
                isPitcherEligible($0)
            }
            // Prefer players who haven't pitched yet, then by fewest innings.
            let sorted = pitcherFallback.sorted { a, b in
                let aPitched = pitcherInningsSoFar(a)
                let bPitched = pitcherInningsSoFar(b)
                return aPitched < bPitched
            }
            if let pick = sorted.first {
                lineup.innings[inningIndex].assign(player: pick, position: .pitcher)
                openPositions.removeAll { $0 == .pitcher }
                filled += 1
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

        // MARK: - Unfilled Slot Classification
        //
        // Any positions remaining in openPositions could not be filled.
        // Classify each with the most specific reason available so the caller
        // can surface a useful explanation to the coach.

        var unfilledSlots: [AutoFillUnfilledSlot] = []
        for pos in openPositions {
            let reason: AutoFillUnfilledReason
            if pos == .pitcher {
                let allNeverPitcher = active.allSatisfy {
                    (preferences[$0.id] ?? [:])[.pitcher] == .never
                }
                // Check who passes the hard rules (re-entry + Never) vs full
                // eligibility (hard rules + capacity) to isolate the cause.
                let anyBaseEligible = active.contains { isPitcherBaseEligible($0) }
                let anyFullyEligible = active.contains { isPitcherEligible($0) }

                if allNeverPitcher {
                    reason = .neverPreferences
                } else if anyBaseEligible && !anyFullyEligible {
                    // Players exist who could pitch (pass hard rules) but have
                    // reached their estimated pitch count capacity for today.
                    reason = .pitchCapacityLimited
                } else if !anyBaseEligible {
                    // Everyone either triggered re-entry or has no pitcher eligibility.
                    reason = .pitcherReentry
                } else {
                    // Eligible pitchers exist but were all assigned elsewhere.
                    reason = .rosterTooSmall
                }
            } else {
                let anyCanPlay = active.contains {
                    (preferences[$0.id] ?? [:])[pos] != .never
                }
                reason = anyCanPlay ? .rosterTooSmall : .neverPreferences
            }
            unfilledSlots.append(AutoFillUnfilledSlot(
                inningIndex: inningIndex,
                position: pos,
                reason: reason
            ))
        }

        return (filled, unfilledSlots)
    }
}
