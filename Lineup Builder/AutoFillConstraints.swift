import Foundation

// MARK: - AutoFill NL Constraints
//
// Engine-facing constraint types produced by parsing a coach's natural
// language prompt (see AutoFillNLConstraintService). Deliberately kept free
// of any FoundationModels dependency so AutoFillEngine remains a pure,
// framework-independent, stateless algorithm — the parsing service is
// responsible for resolving player names and position/zone strings into
// these strongly-typed values before handing them to the engine.

/// What a constraint targets: an exact field position, a zone (either
/// infield or outfield position accepted), or the bench.
enum AutoFillConstraintTarget: Equatable {
    case position(FieldPosition)
    case infield
    case outfield
    case bench
}

/// How strongly a constraint should be honored.
enum AutoFillConstraintIntent: Equatable {
    /// Place the player at the target if at all possible. Bypasses Fair Play
    /// soft constraints (bench rotation order, infield/outfield requirement,
    /// no-repeat positions, pitcher 2-inning soft cap). Never bypasses hard
    /// rules (pitcher re-entry, Never preference) — those are real rules,
    /// not fair-play heuristics, so an assign that violates one is rejected
    /// and reported back to the coach rather than silently dropped.
    case assign
    /// Keep the player out of the target for the applicable innings.
    case avoid
    /// Prefer the player for the target over the normal preference-tier
    /// ordering, but don't force it — falls back to normal behavior if the
    /// target isn't available.
    case prioritize
}

/// A single resolved constraint: one player, one target, one intent, over
/// an inclusive inning range (zero-based, matching Lineup.innings indices).
struct AutoFillPlayerConstraint: Equatable {
    let playerID: UUID
    let target: AutoFillConstraintTarget
    let inningRange: ClosedRange<Int>
    let intent: AutoFillConstraintIntent
}

/// Game-wide "pattern" rules that name no specific player — they shape *how*
/// the fill distributes playing time rather than pinning one player to one
/// place. Kept separate from `playerConstraints` because they aren't a
/// per-player, per-inning placement and can't be expressed as one.
///
/// These exist so a coach can activate a niche distribution preference
/// through natural-language Auto-Fill ("have players sit two innings in a
/// row") without it becoming a permanent Team Settings toggle — it applies
/// to the single fill the prompt was typed for and nothing else.
nonisolated struct AutoFillPatternRules: Equatable {
    /// When true, bench time is handed out in consecutive pairs: once a
    /// player sits an inning, the fill keeps them on the bench the following
    /// inning too, rather than rotating them straight back onto the field.
    /// The obligation is exactly one extra inning — a player who has already
    /// sat two in a row is released, not held for a third.
    ///
    /// This is the deliberate inverse of the engine's normal back-to-back
    /// avoidance, so it's opt-in per fill and never the default. It is a soft
    /// rule: the fill will still field a full lineup, only holding a player
    /// back to complete their pair when there are enough others to cover
    /// every open position without them.
    var benchInConsecutivePairs: Bool = false

    static let none = AutoFillPatternRules()

    var isEmpty: Bool { self == .none }
}

/// The full set of constraints for a fill operation. Pass `.empty` (the
/// default on every AutoFillEngine method) to get today's unconstrained
/// behavior unchanged.
nonisolated struct AutoFillConstraintSet {
    let playerConstraints: [AutoFillPlayerConstraint]
    /// Game-wide pattern rules with no single player attached. Defaulted so
    /// every existing call site that passes only `playerConstraints` keeps
    /// its current behavior.
    var patternRules: AutoFillPatternRules = .none

    static let empty = AutoFillConstraintSet(playerConstraints: [])

    /// True only when there is nothing at all for the engine to act on —
    /// neither a player constraint nor an active pattern rule. Used to gate
    /// constraint-only reporting so plain unconstrained Auto-Fill stays
    /// exactly as it was.
    var isEmpty: Bool { playerConstraints.isEmpty && patternRules.isEmpty }

    /// Constraints that apply to a given inning index.
    func constraints(for inningIndex: Int) -> [AutoFillPlayerConstraint] {
        playerConstraints.filter { $0.inningRange.contains(inningIndex) }
    }
}

// MARK: - Constraint Override Reporting
//
// Whenever an .assign constraint is honored by bypassing a Fair Play soft
// constraint, the engine records why so the coach sees a clear, honest
// explanation rather than a silently different lineup than expected.

/// Which fair-play zone requirement (infield or outfield innings) was left
/// unmet — used to give concrete, coach-readable feedback instead of vague
/// "another zone" language.
nonisolated enum AutoFillMissingZone: Equatable {
    case infield
    case outfield
}

nonisolated enum AutoFillConstraintOverrideReason: Equatable {
    /// Assigned pitcher despite the player already being at the 2-inning
    /// soft cap, because of an explicit .assign constraint for that inning.
    case pitcherSoftCapBypassed
    /// Assigned pitcher despite the player already being at the 2-inning
    /// soft cap via the pre-existing pitcher force-fill fallback (no other
    /// eligible pitcher was available this inning) — not a direct result
    /// of an .assign constraint for this specific inning, but surfaced
    /// whenever NL constraints were in play this fill so the coach isn't
    /// left wondering why a pitcher exceeded the usual guideline.
    case pitcherSoftCapBypassedByFallback
    /// Benched a player out of normal rotation order — at least one other
    /// unconstrained, active player had fewer bench innings so far.
    case benchedOutOfTurn
    /// The player still lacks an inning in the given zone by the end of
    /// the fill — determined only after every requested inning has been
    /// filled, since an earlier-looking gap can resolve itself in a later
    /// inning within the same fill operation.
    case fairPlayZoneSkipped(missing: AutoFillMissingZone)
}

nonisolated struct AutoFillConstraintOverride {
    let inningIndex: Int
    let playerID: UUID
    let target: AutoFillConstraintTarget
    let reason: AutoFillConstraintOverrideReason
}

/// A candidate fair-play-zone concern spotted during an inning's
/// pre-assignment pass, not yet confirmed. Deliberately not surfaced as an
/// AutoFillConstraintOverride until the whole requested fill range has been
/// processed — a player who looks like they'll miss infield/outfield after
/// inning 2 may well pick it up naturally in inning 5, and the earlier
/// signal would have been a false alarm.
struct AutoFillPendingZoneCheck {
    let inningIndex: Int
    let playerID: UUID
    let target: AutoFillConstraintTarget
    let missing: AutoFillMissingZone
}

/// A constraint the engine could not honor at all (target was already
/// occupied by another locked assignment, or honoring it would violate a
/// hard pitcher rule). Distinct from a regular unfilled slot — this is
/// about a specific coach instruction, not a generic fair-play gap.
struct AutoFillConstraintRejection {
    let inningIndex: Int
    let playerID: UUID
    let target: AutoFillConstraintTarget
    let reason: String
}
