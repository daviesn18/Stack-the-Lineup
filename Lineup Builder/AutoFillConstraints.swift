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

/// The full set of constraints for a fill operation. Pass `.empty` (the
/// default on every AutoFillEngine method) to get today's unconstrained
/// behavior unchanged.
nonisolated struct AutoFillConstraintSet {
    let playerConstraints: [AutoFillPlayerConstraint]

    static let empty = AutoFillConstraintSet(playerConstraints: [])

    var isEmpty: Bool { playerConstraints.isEmpty }

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
enum AutoFillMissingZone: Equatable {
    case infield
    case outfield
}

enum AutoFillConstraintOverrideReason: Equatable {
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

struct AutoFillConstraintOverride {
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
