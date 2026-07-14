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
    /// NL constraints that were honored but bypassed a Fair Play soft
    /// constraint to do so (e.g. exceeded the pitcher 2-inning soft cap).
    /// Always empty when no constraints were supplied.
    let constraintOverrides: [AutoFillConstraintOverride]
    /// NL constraints that could not be honored at all (no open target, or
    /// honoring it would have violated a hard pitcher rule).
    /// Always empty when no constraints were supplied.
    let constraintRejections: [AutoFillConstraintRejection]

    init(
        lineup: Lineup,
        filledCount: Int,
        unfilledSlots: [AutoFillUnfilledSlot],
        constraintOverrides: [AutoFillConstraintOverride] = [],
        constraintRejections: [AutoFillConstraintRejection] = []
    ) {
        self.lineup = lineup
        self.filledCount = filledCount
        self.unfilledSlots = unfilledSlots
        self.constraintOverrides = constraintOverrides
        self.constraintRejections = constraintRejections
    }

    var hasUnfilledSlots: Bool { !unfilledSlots.isEmpty }
    var hasConstraintNotices: Bool { !constraintOverrides.isEmpty || !constraintRejections.isEmpty }

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

    /// Returns a coach-readable explanation of any NL constraint overrides
    /// or rejections, or nil if there are none. Needs the roster to resolve
    /// player names, since the engine only tracks player IDs internally.
    /// Groups by player so multiple affected innings read as one line
    /// rather than one line per inning, and uses bullets once there's more
    /// than one line total.
    func constraintNoticeMessage(players: [Player]) -> String? {
        guard hasConstraintNotices else { return nil }

        func name(for id: UUID) -> String {
            players.first(where: { $0.id == id })?.shortName ?? "A player"
        }

        func targetLabel(_ target: AutoFillConstraintTarget) -> String {
            switch target {
            case .position(let pos): return pos.rawValue
            case .infield: return "an infield position"
            case .outfield: return "an outfield position"
            case .bench: return "Bench"
            }
        }

        func inningList(_ innings: [Int]) -> String {
            let numbers = innings.sorted().map { "\($0 + 1)" }
            switch numbers.count {
            case 1: return "inning \(numbers[0])"
            case 2: return "innings \(numbers[0]) and \(numbers[1])"
            default:
                let allButLast = numbers.dropLast().joined(separator: ", ")
                return "innings \(allButLast), and \(numbers.last!)"
            }
        }

        var lines: [String] = []

        // Pitcher soft-cap overrides — grouped by player so 2 affected
        // innings read as one line instead of two.
        for reason in [AutoFillConstraintOverrideReason.pitcherSoftCapBypassed, .pitcherSoftCapBypassedByFallback] {
            let matches = constraintOverrides.filter { $0.reason == reason }
            let byPlayer = Dictionary(grouping: matches, by: { $0.playerID })
            for (playerID, items) in byPlayer.sorted(by: { $0.key.uuidString < $1.key.uuidString }) {
                let list = inningList(items.map { $0.inningIndex })
                switch reason {
                case .pitcherSoftCapBypassed:
                    lines.append("\(name(for: playerID)) also pitched \(list) — past the usual 2-inning guideline.")
                case .pitcherSoftCapBypassedByFallback:
                    lines.append("\(name(for: playerID)) ended up pitching \(list) since no one else was eligible — past the usual 2-inning guideline.")
                default:
                    break
                }
            }
        }

        // Bench-out-of-turn overrides.
        let benchMatches = constraintOverrides.filter { $0.reason == .benchedOutOfTurn }
        let benchByPlayer = Dictionary(grouping: benchMatches, by: { $0.playerID })
        for (playerID, items) in benchByPlayer.sorted(by: { $0.key.uuidString < $1.key.uuidString }) {
            let list = inningList(items.map { $0.inningIndex })
            lines.append("\(name(for: playerID)) sat out \(list) ahead of the normal rotation turn.")
        }

        // Fair-play zone gaps — the engine already dedupes these to one
        // entry per player per missing zone, and they're a whole-game
        // concept rather than tied to one inning, so no inning is named.
        for o in constraintOverrides {
            if case .fairPlayZoneSkipped(let missing) = o.reason {
                let zone = missing == .infield ? "infield" : "outfield"
                lines.append("\(name(for: o.playerID)) still hasn't played \(zone) this game.")
            }
        }

        for r in constraintRejections {
            lines.append("Couldn't put \(name(for: r.playerID)) at \(targetLabel(r.target)) in \(inningList([r.inningIndex])) — \(r.reason)")
        }

        guard !lines.isEmpty else { return nil }
        if lines.count > 1 {
            return lines.map { "• \($0)" }.joined(separator: "\n")
        }
        return lines[0]
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
        gameLogs: [GameLog] = [],
        constraints: AutoFillConstraintSet = .empty
    ) -> AutoFillResult {
        var result = lineup
        let (count, unfilled, overrides, rejections, pendingZoneChecks) = fillInning(
            inningIndex, in: &result,
            players: players,
            preferences: preferences,
            config: config,
            pitchingConfig: pitchingConfig,
            gameLogs: gameLogs,
            constraints: constraints
        )
        let confirmedZoneOverrides = reconcileZoneChecks(pendingZoneChecks, players: players, finalLineup: result)
        return AutoFillResult(
            lineup: result, filledCount: count, unfilledSlots: unfilled,
            constraintOverrides: overrides + confirmedZoneOverrides, constraintRejections: rejections
        )
    }

    /// Fills open slots from inning 0 through `lastInning` (inclusive).
    static func fillInnings(
        through lastInning: Int,
        in lineup: Lineup,
        players: [Player],
        preferences: [UUID: [FieldPosition: PositionPreferenceTier]] = [:],
        config: FairPlayConfig = FairPlayConfig(),
        pitchingConfig: PitchingConfig? = nil,
        gameLogs: [GameLog] = [],
        constraints: AutoFillConstraintSet = .empty
    ) -> AutoFillResult {
        var result = lineup
        var total = 0
        var allUnfilled: [AutoFillUnfilledSlot] = []
        var allOverrides: [AutoFillConstraintOverride] = []
        var allRejections: [AutoFillConstraintRejection] = []
        var allPendingZoneChecks: [AutoFillPendingZoneCheck] = []
        let clampedLast = max(0, min(lastInning, lineup.innings.count - 1))
        for inning in 0...clampedLast {
            let (count, unfilled, overrides, rejections, pendingZoneChecks) = fillInning(
                inning, in: &result,
                players: players,
                preferences: preferences,
                config: config,
                pitchingConfig: pitchingConfig,
                gameLogs: gameLogs,
                constraints: constraints
            )
            total += count
            allUnfilled.append(contentsOf: unfilled)
            allOverrides.append(contentsOf: overrides)
            allRejections.append(contentsOf: rejections)
            allPendingZoneChecks.append(contentsOf: pendingZoneChecks)
        }
        // Zone-requirement gaps are only confirmed now, against the fully
        // filled lineup — a gap flagged after inning 2 may have resolved
        // itself by inning 6 within this same fill operation.
        let confirmedZoneOverrides = reconcileZoneChecks(allPendingZoneChecks, players: players, finalLineup: result)
        return AutoFillResult(
            lineup: result, filledCount: total, unfilledSlots: allUnfilled,
            constraintOverrides: allOverrides + confirmedZoneOverrides, constraintRejections: allRejections
        )
    }

    /// Fills open slots across all innings. Returns an AutoFillResult.
    static func fillGame(
        in lineup: Lineup,
        players: [Player],
        preferences: [UUID: [FieldPosition: PositionPreferenceTier]] = [:],
        config: FairPlayConfig = FairPlayConfig(),
        pitchingConfig: PitchingConfig? = nil,
        gameLogs: [GameLog] = [],
        constraints: AutoFillConstraintSet = .empty
    ) -> AutoFillResult {
        return fillInnings(
            through: lineup.innings.count - 1,
            in: lineup,
            players: players,
            preferences: preferences,
            config: config,
            pitchingConfig: pitchingConfig,
            gameLogs: gameLogs,
            constraints: constraints
        )
    }

    // MARK: - Private Core

    /// Confirms which pending zone-requirement concerns are still real
    /// once the entire requested fill range has been processed, using the
    /// FINAL lineup state rather than the in-progress one. Deduped to at
    /// most one override per (player, missing zone) — the underlying
    /// concern is "hasn't played this zone at all," a whole-game fact, not
    /// something worth repeating per inning.
    private static func reconcileZoneChecks(
        _ pending: [AutoFillPendingZoneCheck],
        players: [Player],
        finalLineup: Lineup
    ) -> [AutoFillConstraintOverride] {
        var seenInfield: Set<UUID> = []
        var seenOutfield: Set<UUID> = []
        var result: [AutoFillConstraintOverride] = []

        for p in pending {
            guard let player = players.first(where: { $0.id == p.playerID }) else { continue }
            let stillMissing: Bool
            switch p.missing {
            case .infield:
                guard !seenInfield.contains(p.playerID) else { continue }
                stillMissing = !finalLineup.innings.contains(where: { $0.position(for: player)?.isInfield == true })
                if stillMissing { seenInfield.insert(p.playerID) }
            case .outfield:
                guard !seenOutfield.contains(p.playerID) else { continue }
                stillMissing = !finalLineup.innings.contains(where: { $0.position(for: player)?.isOutfield == true })
                if stillMissing { seenOutfield.insert(p.playerID) }
            }
            guard stillMissing else { continue }
            result.append(AutoFillConstraintOverride(
                inningIndex: p.inningIndex, playerID: p.playerID, target: p.target,
                reason: .fairPlayZoneSkipped(missing: p.missing)
            ))
        }

        return result
    }

    @discardableResult
    private static func fillInning(
        _ inningIndex: Int,
        in lineup: inout Lineup,
        players: [Player],
        preferences: [UUID: [FieldPosition: PositionPreferenceTier]],
        config: FairPlayConfig,
        pitchingConfig: PitchingConfig?,
        gameLogs: [GameLog],
        constraints: AutoFillConstraintSet
    ) -> (
        filled: Int,
        unfilled: [AutoFillUnfilledSlot],
        overrides: [AutoFillConstraintOverride],
        rejections: [AutoFillConstraintRejection],
        pendingZoneChecks: [AutoFillPendingZoneCheck]
    ) {
        let active = lineup.activePlayers(from: players)
        guard !active.isEmpty else { return (0, [], [], [], []) }

        var unassigned = active.filter {
            lineup.innings[inningIndex].position(for: $0) == nil
        }
        guard !unassigned.isEmpty else { return (0, [], [], [], []) }

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

        // MARK: - NL Constraint-Aware Position Resolution
        //
        // Wraps preferredPosition to honor .avoid (excludes positions/zones
        // for this player, this inning) and .prioritize (tries the
        // requested position ahead of the normal preference-tier order,
        // falling back to normal behavior if it isn't available).

        let inningConstraints = constraints.constraints(for: inningIndex)

        func avoidedPositions(for player: Player) -> Set<FieldPosition> {
            var result: Set<FieldPosition> = []
            for c in inningConstraints where c.playerID == player.id && c.intent == .avoid {
                switch c.target {
                case .position(let pos): result.insert(pos)
                case .infield: result.formUnion(FieldPosition.fieldPositions.filter { $0.isInfield })
                case .outfield: result.formUnion(FieldPosition.fieldPositions.filter { $0.isOutfield })
                case .bench: break // avoiding the bench isn't a position-candidate filter
                }
            }
            return result
        }

        func prioritizedPosition(for player: Player) -> FieldPosition? {
            for c in inningConstraints where c.playerID == player.id && c.intent == .prioritize {
                if case .position(let pos) = c.target { return pos }
            }
            return nil
        }

        func resolvePosition(for player: Player, from candidates: [FieldPosition]) -> FieldPosition? {
            let avoided = avoidedPositions(for: player)
            let filtered = avoided.isEmpty ? candidates : candidates.filter { !avoided.contains($0) }
            guard !filtered.isEmpty else { return nil }
            if let prioritized = prioritizedPosition(for: player), filtered.contains(prioritized) {
                let prefs = preferences[player.id] ?? [:]
                if prefs[prioritized] != .never { return prioritized }
            }
            return preferredPosition(for: player, from: filtered)
        }

        // MARK: - No-Repeat Position Helpers
        //
        // When config.noRepeatPositions is true, auto-fill tries to assign each
        // player a position they haven't played earlier this game.  This is a
        // SOFT constraint: if every available position has already been played,
        // the full candidate list is returned unchanged so the engine never
        // leaves a slot unfilled just to avoid a repeat.

        /// Non-bench positions this player has already been assigned in innings
        /// 0..<inningIndex (earlier innings only, not the current one).
        func positionsAlreadyPlayedThisGame(_ player: Player) -> Set<FieldPosition> {
            Set(lineup.innings.prefix(inningIndex)
                .compactMap { $0.position(for: player) }
                .filter { !$0.isNonFielding })
        }

        /// Returns `candidates` with already-played positions filtered out.
        /// Falls back to the full `candidates` list when the filtered result
        /// would be empty, so zone requirements are never violated.
        func freshCandidates(_ candidates: [FieldPosition], for player: Player) -> [FieldPosition] {
            guard config.noRepeatPositions else { return candidates }
            let played = positionsAlreadyPlayedThisGame(player)
            let fresh = candidates.filter { !played.contains($0) }
            return fresh.isEmpty ? candidates : fresh
        }

        // MARK: - NL Constraint Pre-Assignment Pass
        //
        // .assign constraints are honored before the normal algorithm runs —
        // exactly like a coach's manual assignment, so everything below
        // treats the slot as already locked. Zone targets (.infield/
        // .outfield) resolve to the best open position in that zone using
        // the same preference-tier logic as the main loop. .bench targets
        // are handled separately below by excluding the player from the
        // field queue, since "bench" isn't a member of openPositions.
        //
        // Hard pitcher rules (re-entry, Never) are never bypassed — an
        // assign that would violate one is rejected and reported via
        // constraintRejections rather than silently dropped.

        var forcedBenchPlayerIDs: Set<UUID> = []
        var constraintOverrides: [AutoFillConstraintOverride] = []
        var constraintRejections: [AutoFillConstraintRejection] = []
        // Zone-requirement concerns spotted here aren't confirmed yet — a
        // player who "still needs infield" after this assignment may well
        // get an infield inning later in the same fill operation, which
        // would make this a false alarm. Resolved for real by the caller
        // once the whole requested range has been filled (see
        // fillInning/fillInnings/fillGame below).
        var pendingZoneChecks: [AutoFillPendingZoneCheck] = []

        for constraint in inningConstraints where constraint.intent == .assign {
            guard let player = active.first(where: { $0.id == constraint.playerID }) else { continue }
            // Respect any assignment already present (manual, or an earlier
            // constraint this same pass) — first one wins.
            guard lineup.innings[inningIndex].position(for: player) == nil else { continue }

            if case .bench = constraint.target {
                forcedBenchPlayerIDs.insert(player.id)
                continue
            }

            let candidatePositions: [FieldPosition]
            switch constraint.target {
            case .position(let pos):
                candidatePositions = [pos]
            case .infield:
                candidatePositions = openPositions.filter { $0.isInfield }
            case .outfield:
                candidatePositions = openPositions.filter { $0.isOutfield }
            case .bench:
                candidatePositions = [] // handled above
            }

            guard let target = candidatePositions.first(where: { openPositions.contains($0) }) else {
                constraintRejections.append(AutoFillConstraintRejection(
                    inningIndex: inningIndex, playerID: player.id, target: constraint.target,
                    reason: "No open position was available to honor this instruction."
                ))
                continue
            }

            // Hard pitcher rules are never bypassed, even for an explicit assign.
            if target == .pitcher && !isPitcherBaseEligible(player) {
                constraintRejections.append(AutoFillConstraintRejection(
                    inningIndex: inningIndex, playerID: player.id, target: constraint.target,
                    reason: "Already exited the mound this game (re-entry rule), or marked Never for Pitcher."
                ))
                continue
            }

            lineup.innings[inningIndex].assign(player: player, position: target)
            openPositions.removeAll { $0 == target }
            unassigned.removeAll { $0.id == player.id }
            filled += 1

            // Pitcher soft-cap is a real-time fact (already happened, not
            // future-dependent), so it's confirmed immediately. Zone
            // requirements are queued for later verification instead.
            if target == .pitcher && pitcherInningsSoFar(player) > maxPitcherInningsSoftCap {
                constraintOverrides.append(AutoFillConstraintOverride(
                    inningIndex: inningIndex, playerID: player.id, target: constraint.target,
                    reason: .pitcherSoftCapBypassed
                ))
            }
            if !target.isInfield && needsInfield(player) {
                pendingZoneChecks.append(AutoFillPendingZoneCheck(
                    inningIndex: inningIndex, playerID: player.id, target: constraint.target, missing: .infield
                ))
            }
            if !target.isOutfield && needsOutfield(player) {
                pendingZoneChecks.append(AutoFillPendingZoneCheck(
                    inningIndex: inningIndex, playerID: player.id, target: constraint.target, missing: .outfield
                ))
            }
        }

        // Forced-bench players: flag when it puts them ahead of their normal
        // rotation turn (some other still-active, non-forced player has
        // fewer bench innings so far and is about to play the field).
        for playerID in forcedBenchPlayerIDs {
            guard let player = active.first(where: { $0.id == playerID }) else { continue }
            let thisBenchCount = benchInningsSoFar(player)
            let othersWithFewerBench = active.contains { other in
                other.id != playerID &&
                !forcedBenchPlayerIDs.contains(other.id) &&
                benchInningsSoFar(other) < thisBenchCount
            }
            if othersWithFewerBench {
                constraintOverrides.append(AutoFillConstraintOverride(
                    inningIndex: inningIndex, playerID: playerID, target: .bench,
                    reason: .benchedOutOfTurn
                ))
            }
        }

        // MARK: - Field Assignment Queue

        let benchedLast = unassigned.filter { !forcedBenchPlayerIDs.contains($0.id) && benchedLastInning($0) }.shuffled()
        let needsIF = unassigned.filter { !forcedBenchPlayerIDs.contains($0.id) && !benchedLastInning($0) && needsInfield($0) }.shuffled()
        let needsOF = unassigned.filter { !forcedBenchPlayerIDs.contains($0.id) && !benchedLastInning($0) && !needsInfield($0) && needsOutfield($0) }.shuffled()
        let rest    = unassigned.filter { !forcedBenchPlayerIDs.contains($0.id) && !benchedLastInning($0) && !needsInfield($0) && !needsOutfield($0) }.shuffled()

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
                let rawInfield = openPositions.filter { $0.isInfield }
                let infieldCandidates = filteringPitcher(for: player, candidates: freshCandidates(rawInfield, for: player))
                if infieldCandidates.isEmpty {
                    // No open infield slots left at all — not a Never issue
                } else if let pos = resolvePosition(for: player, from: infieldCandidates) {
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
                let outfieldCandidates = freshCandidates(openPositions.filter { $0.isOutfield }, for: player)
                if outfieldCandidates.isEmpty {
                    // No open outfield slots left at all
                } else if let pos = resolvePosition(for: player, from: outfieldCandidates) {
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
                fallbackCandidates = freshCandidates(fallbackCandidates, for: player)
                fallbackCandidates = filteringPitcher(for: player, candidates: fallbackCandidates)

                if let pos = resolvePosition(for: player, from: fallbackCandidates) {
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
            // Players the coach explicitly asked to keep off Pitcher this
            // inning are excluded from the fallback too — this is what
            // actually stops "Connor pitches the first 2 innings" from
            // having Connor reappear at Pitcher in inning 4 just because
            // no one else was left. (An .assign for Pitcher outside its
            // own range is turned into an implicit .avoid for the rest of
            // the game by AutoFillNLConstraintService — see there.)
            let avoidPitcherPlayerIDs = Set(
                inningConstraints
                    .filter { $0.intent == .avoid && $0.target == .position(.pitcher) }
                    .map { $0.playerID }
            )
            let pitcherFallback = active.filter {
                lineup.innings[inningIndex].position(for: $0) == nil &&
                isPitcherEligible($0) &&
                !avoidPitcherPlayerIDs.contains($0.id)
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

                // This fallback has always been allowed to bypass the
                // 2-inning soft cap (better to fill the slot than leave it
                // open), but it was previously silent about doing so. Now
                // that NL constraints exist, surface it — but only when
                // constraints were actually supplied this fill, so plain
                // unconstrained Auto-Fill behavior stays unchanged.
                if !constraints.isEmpty && pitcherInningsSoFar(pick) > maxPitcherInningsSoftCap {
                    constraintOverrides.append(AutoFillConstraintOverride(
                        inningIndex: inningIndex, playerID: pick.id, target: .position(.pitcher),
                        reason: .pitcherSoftCapBypassedByFallback
                    ))
                }
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

        return (filled, unfilledSlots, constraintOverrides, constraintRejections, pendingZoneChecks)
    }
}
