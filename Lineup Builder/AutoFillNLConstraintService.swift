import Foundation
import FoundationModels

// MARK: - AutoFillNLConstraintService
//
// Parses a coach's free-text Auto-Fill prompt ("Pitch Caleb the first 2
// innings, keep Zachary off the bench") into an engine-ready
// AutoFillConstraintSet, using on-device Apple Intelligence via the
// FoundationModels framework (iOS 26+) — same runtime and availability
// pattern as GameLogInsightsService, no network call, no API key.
//
// ARCHITECTURE NOTE — why this is a class now, not a static enum:
//
// The original version was a stateless enum with a single static parse()
// that built a fresh LanguageModelSession on every call. That meant every
// single Fill tap paid the full cost of model load (cold) plus prefill of
// the entire instruction block before a single token of output could be
// generated. On device that reads as "the parse is slow," when in fact the
// constrained decoding itself is fast — it's the setup that costs.
//
// This version owns its session for the lifetime of an Auto-Fill popover.
// The view creates the service in .onAppear and calls prewarm(), which
// warms the model and prefills the instructions while the coach is still
// typing their prompt. By the time Fill is tapped, generation can start
// almost immediately.
//
// TWO OTHER SPEED LEVERS APPLIED HERE:
//
// 1. Dynamic schema. playerName and target are now runtime-built enums
//    (DynamicGenerationSchema) constrained to the actual active roster and
//    the actual field positions. Previously the roster was pasted into the
//    instructions as prose and the model was asked, in English, to please
//    match it exactly. That approach cost prefill tokens for the roster
//    list AND for the "never invent a player" paragraph, and it still let
//    the model emit a near-miss name that the Swift matcher would then
//    silently drop. Constraining the output space makes a wrong name
//    structurally impossible and shortens the prompt at the same time.
//
// 2. De-duplicated rules. The inning-range rule ("start means inning 1
//    only") used to be stated in BOTH the instructions string AND the
//    @Guide descriptions — both of which get tokenized and prefilled on
//    every call. Each rule now lives in exactly one place. Per-field
//    semantics live in the schema; game-level context lives in the
//    instructions.
//
// DIAGNOSTICS:
//
// resolve() no longer drops unresolvable constraints silently. A prompt
// the coach wrote and the app quietly ignored is the fastest way to lose
// their trust in the feature. Anything that can't be resolved is reported
// back in AutoFillNLParseResult.diagnostics, which the views append to the
// existing "About Your Instructions" alert. A visible miss is correctable.
// An invisible one just looks broken.

// MARK: - Schema (model-facing)

@Generable
enum NLConstraintIntent: String {
    case assign
    case avoid
    case prioritize
}

/// The static half of the schema. `playerName` and `target` are supplied
/// at runtime as constrained enums via `dynamicSchema(...)` below, so they
/// are deliberately NOT declared here — a @Generable String property would
/// let the model write anything it liked.
///
/// Kept as a fallback path for the (unlikely) case where dynamic schema
/// construction fails, so a parse degrades to the old prose-matching
/// behavior rather than to nothing at all.
@Generable
struct NLPlayerConstraintFallback {
    @Guide(description: "The player's name, copied from the roster in the instructions.")
    var playerName: String

    @Guide(description: "One of: Pitcher, Catcher, 1B, 2B, 3B, SS, LF, CF, RF, LCF, RCF, Infield, Outfield, Bench.")
    var target: String

    @Guide(description: "First inning this applies to, one-based. A bare \"start\" or \"begin\" with no duration means inning 1 only.")
    var startInning: Int

    @Guide(description: "Last inning, inclusive, one-based. Equal to startInning unless the coach explicitly gave a range.")
    var endInning: Int

    var intent: NLConstraintIntent
}

@Generable
struct NLAutoFillConstraintsFallback {
    var constraints: [NLPlayerConstraintFallback]

    @Guide(description: "True only if the coach asks that bench time come in consecutive pairs — e.g. \"players sit two innings in a row\", \"if someone sits an inning they sit the next too\", \"double up the bench\". This is a game-wide pattern that names no specific player. False otherwise.")
    var benchInConsecutivePairs: Bool
}

// MARK: - Parse output

/// One coach instruction the parser could not turn into a usable
/// constraint. Surfaced to the coach rather than dropped.
struct AutoFillNLDiagnostic {
    enum Kind {
        /// The model named someone who isn't on the active roster.
        case unmatchedPlayer(String)
        /// The model named a position or zone that isn't recognized.
        case unmatchedTarget(String)
        /// The prompt appears to contain more separate instructions than the
        /// model produced constraints for. This is a heuristic, not a
        /// certainty, so the wording is deliberately soft — but a dropped
        /// clause is otherwise completely invisible to the coach, which is
        /// exactly how "Jake starts on the bench then plays OF" silently
        /// became "Jake plays OF" with no bench assignment and no warning.
        case possibleDroppedClause(parsed: Int, expected: Int)
        /// A game-wide pattern rule was understood and applied. Not a miss —
        /// a positive confirmation. Surfaced through the same channel because
        /// a niche rule that names no player and produces no visible per-player
        /// assignment otherwise leaves the coach unable to tell it registered
        /// at all, which is the exact failure that made the feature look broken.
        case patternRuleApplied(String)
    }
    let kind: Kind

    var message: String {
        switch kind {
        case .unmatchedPlayer(let raw):
            return "Couldn't find \"\(raw)\" on the active roster, so that instruction was skipped."
        case .unmatchedTarget(let raw):
            return "Didn't recognize \"\(raw)\" as a position, so that instruction was skipped."
        case .possibleDroppedClause(let parsed, let expected):
            let picked = parsed == 1 ? "1 instruction" : "\(parsed) instructions"
            return "Your notes looked like they had about \(expected) instructions but only \(picked) came through. Check the lineup, and try putting each instruction on its own line."
        case .patternRuleApplied(let description):
            return description
        }
    }
}

/// What a parse returns: the constraints the engine can act on, plus
/// anything that got dropped along the way.
struct AutoFillNLParseResult {
    let constraints: AutoFillConstraintSet
    let diagnostics: [AutoFillNLDiagnostic]

    static let empty = AutoFillNLParseResult(constraints: .empty, diagnostics: [])

    /// Coach-readable lines, ready to append to the engine's own
    /// constraint-notice message in the existing alert.
    var diagnosticMessage: String? {
        guard !diagnostics.isEmpty else { return nil }
        let lines = diagnostics.map { $0.message }
        if lines.count > 1 {
            return lines.map { "• \($0)" }.joined(separator: "\n")
        }
        return lines[0]
    }
}

enum AutoFillNLParseError: Error {
    /// Apple Intelligence isn't available on this device/OS.
    case unsupported
}

// MARK: - Service

/// Owns a LanguageModelSession for the lifetime of one Auto-Fill popover.
/// Create in .onAppear, call prewarm(), then call parse() on Fill.
///
/// Not a singleton on purpose: the instructions embed the inning count, and
/// the dynamic schema embeds the active roster. Both can change between
/// popover opens (roster edits, inning-count changes in Fair Play rules), so
/// a long-lived shared session would go stale. Popover-scoped is the right
/// lifetime — long enough to pay off the prewarm, short enough to stay
/// correct.
@MainActor
final class AutoFillNLConstraintService {

    private let activePlayers: [Player]
    private let inningCount: Int
    private var session: LanguageModelSession?

    /// True when the on-device model is available. Views can use this to
    /// hide the prompt field entirely on unsupported hardware rather than
    /// letting a coach type into a box that will never do anything.
    var isAvailable: Bool {
        switch SystemLanguageModel.default.availability {
        case .available: return true
        case .unavailable: return false
        @unknown default: return false
        }
    }

    init(activePlayers: [Player], inningCount: Int) {
        self.activePlayers = activePlayers
        self.inningCount = inningCount
    }

    // MARK: Prewarm

    /// Builds the session and asks the model to warm up. Call this when the
    /// Auto-Fill popover appears, NOT when Fill is tapped — the whole point
    /// is to spend the model-load and prefill cost during the seconds the
    /// coach is typing, so that tapping Fill starts generating immediately.
    ///
    /// Safe to call more than once; subsequent calls are no-ops. Safe to
    /// call on unsupported devices; it just returns.
    func prewarm() {
        guard isAvailable, session == nil else { return }
        let session = LanguageModelSession(instructions: instructions)
        session.prewarm()
        self.session = session
    }

    // MARK: Parse

    /// Parses `prompt` into constraints plus diagnostics. Returns `.empty`
    /// for a blank prompt without doing any inference. Throws
    /// `.unsupported` if Apple Intelligence isn't available — callers fall
    /// back to running Auto-Fill unconstrained rather than blocking the
    /// fill entirely.
    func parse(prompt: String) async throws -> AutoFillNLParseResult {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        guard isAvailable else { throw AutoFillNLParseError.unsupported }

        // Normally already built by prewarm(). This is the safety net for a
        // Fill tapped before .onAppear's prewarm could run.
        if session == nil {
            session = LanguageModelSession(instructions: instructions)
        }
        guard let session else { throw AutoFillNLParseError.unsupported }

        // Preferred path: constrained decoding against a runtime schema
        // built from the real roster and the real position list.
        let result: AutoFillNLParseResult
        if let schema = try? dynamicSchema() {
            let response = try await session.respond(
                to: trimmed,
                schema: schema
            )
            result = resolveDynamic(response.content)
        } else {
            // Fallback path: prose roster + post-hoc string matching. Only
            // reached if schema construction throws, which shouldn't happen
            // in practice but shouldn't take the whole feature down if it does.
            let response = try await session.respond(
                to: trimmed,
                generating: NLAutoFillConstraintsFallback.self
            )
            result = resolveFallback(response.content)
        }

        return withClauseCountCheck(result, prompt: trimmed)
    }

    // MARK: - Dropped-clause heuristic
    //
    // The failure mode this exists for: "I want Jake to start on the bench the
    // first inning and then play the OF for the next 2" parsed into ONE
    // constraint (the outfield half) instead of two. The bench half evaporated,
    // Jake got auto-filled to 2B in inning 1, and nothing anywhere told the
    // coach their instruction had been dropped. The lineup just looked wrong.
    //
    // The instructions now explicitly teach clause-splitting, which should stop
    // this at the source. But "should" is doing a lot of work in that sentence,
    // and a silent miss is the single most trust-destroying outcome this feature
    // has. So: count the clause separators in the prompt, compare to how many
    // constraints came back, and say something if the numbers look off.
    //
    // Deliberately conservative. This only fires when the gap is real (fewer
    // constraints than clauses), and the copy hedges ("looked like", "about")
    // because the estimate is a word-count heuristic, not a parse. A false
    // positive costs the coach one glance at an alert. A false negative costs
    // them a wrong lineup they don't find out about until the third inning.

    private func withClauseCountCheck(
        _ result: AutoFillNLParseResult,
        prompt: String
    ) -> AutoFillNLParseResult {
        let expected = estimatedClauseCount(in: prompt)

        // Ignore the implicit avoid-Pitcher constraints this service adds
        // itself — they aren't things the coach typed, so counting them would
        // mask a genuine drop. Filtering out every avoid-Pitcher constraint
        // would also swallow ones the coach DID type ("don't let Sam pitch"),
        // so instead recompute exactly how many withImplicitPitcherAvoids
        // appended: one per complement range of each pitcher assign.
        let all = result.constraints.playerConstraints
        let implicitCount = all
            .filter { $0.intent == .assign && $0.target == .position(.pitcher) }
            .reduce(0) { $0 + complementRanges(of: $1.inningRange, totalInnings: inningCount).count }
        let parsed = all.count - implicitCount

        guard parsed > 0, expected > parsed else { return result }

        var diagnostics = result.diagnostics
        diagnostics.append(AutoFillNLDiagnostic(
            kind: .possibleDroppedClause(parsed: parsed, expected: expected)
        ))
        return AutoFillNLParseResult(
            constraints: result.constraints,
            diagnostics: diagnostics
        )
    }

    /// Rough count of how many separate PLACEMENTS the coach's text appears to
    /// describe.
    ///
    /// The first version of this counted clause separators (commas, "and",
    /// "then"). That broke immediately on a shared-instruction name list —
    /// "Marcus, Drew, and Eli all play infield" has three separators but one
    /// placement, and it produced a false "you lost a clause" alert every time.
    ///
    /// Counting distinct position/zone/bench mentions instead sidesteps that
    /// entirely. A name list mentions ONE placement ("infield") no matter how
    /// many names it strings together. A genuine two-clause prompt mentions TWO
    /// ("bench", "OF"). That's the actual signal, and it's the one that
    /// distinguishes the false positive from the real bug.
    private func estimatedClauseCount(in prompt: String) -> Int {
        // A coach who put each instruction on its own line meant each line as
        // its own instruction. Strongest signal available, take it directly.
        let lines = prompt
            .split(whereSeparator: \.isNewline)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if lines.count > 1 { return lines.count }

        // Count placement mentions. Longer phrases first so "first base" isn't
        // double-counted by a later, shorter "1b" pass, and so "center field"
        // is consumed before "field". These are matched case-insensitively.
        let placementPhrases: [String] = [
            "left center field", "right center field",
            "first base", "second base", "third base", "shortstop",
            "left field", "center field", "right field",
            "outfield", "infield", "bench",
            "pitcher", "pitches", "pitch", "catcher", "catches", "catch",
            "1b", "2b", "3b", "ss", "lf", "cf", "rf", "lcf", "rcf"
        ]

        // These abbreviations collide with ordinary English words ("most of
        // the game", "if you can") or single letters, so they only count when
        // written in uppercase — "play the OF" is a placement, "of" is not.
        let ambiguousAbbreviations: [String] = ["OF", "IF", "P", "C"]

        var count = 0
        var scratch = prompt

        func consume(pattern: String) {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
            let range = NSRange(scratch.startIndex..., in: scratch)
            let matches = regex.numberOfMatches(in: scratch, range: range)
            guard matches > 0 else { return }
            count += matches
            // Consume the matches so a shorter phrase can't re-count them.
            scratch = regex.stringByReplacingMatches(
                in: scratch, range: range, withTemplate: " "
            )
        }

        for phrase in placementPhrases {
            consume(pattern: "(?i)\\b\(NSRegularExpression.escapedPattern(for: phrase))\\b")
        }
        for abbreviation in ambiguousAbbreviations {
            // Case-sensitive on purpose — see above.
            consume(pattern: "\\b\(abbreviation)\\b")
        }

        return max(1, count)
    }

    // MARK: - Instructions
    //
    // Game-level context and task framing ONLY. Deliberately does NOT
    // repeat: the roster list (now enforced by the dynamic schema), the
    // position list (same), or the inning-range semantics (now stated once,
    // on the schema's inning fields). Every sentence here is prefilled on
    // every call, so anything stated twice is paid for twice.

    private var instructions: String {
        """
        You turn a youth baseball coach's plain-English lineup notes into \
        structured constraints for an auto-fill algorithm.

        The game has \(inningCount) innings, numbered 1 through \(inningCount).

        ONE ENTRY PER CLAUSE. A single sentence often contains more than one \
        instruction, including more than one for the same player. Split on \
        "and", "then", "and then", "after that", and commas. Each clause that \
        states a placement gets its own entry, even when it names a player \
        already covered by an earlier clause.

        Example — "I want Jake to start on the bench the first inning and then \
        play the outfield for the next 2" is TWO entries, both for Jake:
          1. Jake, Bench, innings 1 to 1, assign
          2. Jake, Outfield, innings 2 to 3, assign

        Example — "Caleb pitches the first two innings and Owen catches" is TWO \
        entries, one per player.

        "Start", "starts", and "begins" mark inning 1. A clause like "start on \
        the bench" or "start at shortstop" means inning 1 and inning 1 only. It \
        does not extend across the game, and it does not prevent a later clause \
        in the same sentence from covering later innings.

        Relative ranges are counted from where the previous clause left off. \
        "The next 2" after an inning-1 clause means innings 2 and 3.

        Ignore general strategy notes that name no specific player, with ONE \
        exception: the bench-pairing pattern below.

        BENCH PAIRING. Set benchInConsecutivePairs to true when the coach wants \
        players to sit consecutively — "have players sit two innings in a row", \
        "if a player sits one inning, have them sit the next too", "double up \
        the bench so nobody sits just once". This names no specific player and \
        produces NO per-player entry; it only sets that one flag. Leave it false \
        for everything else, including ordinary bench placements for a named \
        player ("Jake starts on the bench"), which are per-player entries, not \
        this pattern.

        Intent: use "assign" to place a player somewhere, "avoid" to keep them \
        out of it, "prioritize" to prefer it without forcing it.
        """
    }

    // MARK: - Dynamic schema
    //
    // Constrains playerName to the actual active roster and target to the
    // actual position/zone tokens. The model cannot emit a name or position
    // that doesn't exist, which removes an entire class of failure (the
    // near-miss name that used to get silently dropped in resolve()) without
    // spending a single prefill token on telling it not to.

    private func dynamicSchema() throws -> GenerationSchema {
        let playerSchema = DynamicGenerationSchema(
            name: "playerName",
            description: "Which player this instruction is about.",
            anyOf: activePlayers.map { $0.displayName }
        )

        let targetSchema = DynamicGenerationSchema(
            name: "target",
            description: "The position, zone, or bench this instruction refers to. Use Infield or Outfield when the coach means a zone rather than one specific position.",
            anyOf: targetTokens
        )

        let constraintSchema = DynamicGenerationSchema(
            name: "NLPlayerConstraint",
            properties: [
                DynamicGenerationSchema.Property(
                    name: "playerName",
                    schema: playerSchema
                ),
                DynamicGenerationSchema.Property(
                    name: "target",
                    schema: targetSchema
                ),
                DynamicGenerationSchema.Property(
                    name: "startInning",
                    description: "First inning this applies to, one-based. A bare \"start\" or \"begin\" with no stated duration means inning 1 and inning 1 only — do not widen it into a range. Default to 1 when no inning is mentioned.",
                    schema: DynamicGenerationSchema(type: Int.self)
                ),
                DynamicGenerationSchema.Property(
                    name: "endInning",
                    description: "Last inning, inclusive, one-based. Equal to startInning unless the coach explicitly stated a range, e.g. \"innings 3-5\", \"the first 2 innings\", \"all game\".",
                    schema: DynamicGenerationSchema(type: Int.self)
                ),
                DynamicGenerationSchema.Property(
                    name: "intent",
                    schema: DynamicGenerationSchema(
                        name: "intent",
                        anyOf: ["assign", "avoid", "prioritize"]
                    )
                )
            ]
        )

        let root = DynamicGenerationSchema(
            name: "NLAutoFillConstraints",
            properties: [
                DynamicGenerationSchema.Property(
                    name: "constraints",
                    description: "One entry per player-specific instruction. Empty if the prompt names no players.",
                    schema: DynamicGenerationSchema(arrayOf: constraintSchema)
                ),
                DynamicGenerationSchema.Property(
                    name: "benchInConsecutivePairs",
                    description: "True only if the coach asks that bench time come in consecutive pairs — e.g. \"players sit two innings in a row\", \"if someone sits an inning they sit the next too\", \"double up the bench\". This is a game-wide pattern that names no specific player. False otherwise.",
                    schema: DynamicGenerationSchema(type: Bool.self)
                )
            ]
        )

        // respond(to:schema:) takes a GenerationSchema; the dynamic pieces
        // above must be resolved into one. Nested schemas are embedded
        // directly, so there are no named dependencies to pass.
        return try GenerationSchema(root: root, dependencies: [])
    }

    /// The exact string tokens the target enum is constrained to. Built from
    /// FieldPosition so it can never drift out of sync with the app's real
    /// position list the way a hardcoded prose list would.
    private var targetTokens: [String] {
        FieldPosition.allCases.map { $0.rawValue } + ["Infield", "Outfield", "Bench"]
    }

    // MARK: - Resolution (dynamic path)
    //
    // The schema guarantees playerName and target are valid tokens, so this
    // is mostly a straight mapping. The diagnostics path is still wired up
    // because a guarantee you rely on silently is a guarantee you find out
    // about the hard way.

    private func resolveDynamic(_ content: GeneratedContent) -> AutoFillNLParseResult {
        guard inningCount > 0 else { return .empty }

        // Game-wide pattern rules are read independently of the per-player
        // entries — a prompt can be nothing but a pattern rule ("have players
        // sit two in a row"), which yields an empty constraints array but a
        // live rule the engine still needs to act on.
        let patternRules = AutoFillPatternRules(
            benchInConsecutivePairs: (try? content.value(Bool.self, forProperty: "benchInConsecutivePairs")) ?? false
        )

        guard let entries = try? content.value(
            [GeneratedContent].self,
            forProperty: "constraints"
        ) else {
            return AutoFillNLParseResult(
                constraints: AutoFillConstraintSet(playerConstraints: [], patternRules: patternRules),
                diagnostics: patternConfirmations(for: patternRules)
            )
        }

        var resolved: [AutoFillPlayerConstraint] = []
        var diagnostics: [AutoFillNLDiagnostic] = []

        for entry in entries {
            guard
                let rawName = try? entry.value(String.self, forProperty: "playerName"),
                let rawTarget = try? entry.value(String.self, forProperty: "target"),
                let rawIntent = try? entry.value(String.self, forProperty: "intent"),
                let rawStart = try? entry.value(Int.self, forProperty: "startInning"),
                let rawEnd = try? entry.value(Int.self, forProperty: "endInning")
            else { continue }

            guard let player = matchPlayer(named: rawName, in: activePlayers) else {
                diagnostics.append(AutoFillNLDiagnostic(kind: .unmatchedPlayer(rawName)))
                continue
            }
            guard let target = matchTarget(rawTarget) else {
                diagnostics.append(AutoFillNLDiagnostic(kind: .unmatchedTarget(rawTarget)))
                continue
            }

            let start = max(0, min(rawStart - 1, inningCount - 1))
            let end = max(start, min(rawEnd - 1, inningCount - 1))

            resolved.append(AutoFillPlayerConstraint(
                playerID: player.id,
                target: target,
                inningRange: start...end,
                intent: intent(from: rawIntent)
            ))
        }

        return AutoFillNLParseResult(
            constraints: AutoFillConstraintSet(
                playerConstraints: withImplicitPitcherAvoids(resolved),
                patternRules: patternRules
            ),
            diagnostics: diagnostics + patternConfirmations(for: patternRules)
        )
    }

    // MARK: - Resolution (fallback path)

    private func resolveFallback(_ raw: NLAutoFillConstraintsFallback) -> AutoFillNLParseResult {
        guard inningCount > 0 else { return .empty }

        var resolved: [AutoFillPlayerConstraint] = []
        var diagnostics: [AutoFillNLDiagnostic] = []

        for c in raw.constraints {
            guard let player = matchPlayer(named: c.playerName, in: activePlayers) else {
                diagnostics.append(AutoFillNLDiagnostic(kind: .unmatchedPlayer(c.playerName)))
                continue
            }
            guard let target = matchTarget(c.target) else {
                diagnostics.append(AutoFillNLDiagnostic(kind: .unmatchedTarget(c.target)))
                continue
            }

            let start = max(0, min(c.startInning - 1, inningCount - 1))
            let end = max(start, min(c.endInning - 1, inningCount - 1))

            resolved.append(AutoFillPlayerConstraint(
                playerID: player.id,
                target: target,
                inningRange: start...end,
                intent: intent(from: c.intent.rawValue)
            ))
        }

        let patternRules = AutoFillPatternRules(
            benchInConsecutivePairs: raw.benchInConsecutivePairs
        )
        return AutoFillNLParseResult(
            constraints: AutoFillConstraintSet(
                playerConstraints: withImplicitPitcherAvoids(resolved),
                patternRules: patternRules
            ),
            diagnostics: diagnostics + patternConfirmations(for: patternRules)
        )
    }

    // MARK: - Implicit pitcher range boundary
    //
    // Unchanged behavior from the previous version, just factored out so
    // both resolution paths share it.
    //
    // Most coaches read "Connor pitches innings 1-2" as an exact boundary,
    // not "at least innings 1-2." Without this, AutoFillEngine's pre-existing
    // pitcher force-fill fallback (which exists to avoid leaving Pitcher
    // empty) could still reuse Connor outside his stated range if he ends up
    // the only remaining pitcher-eligible player later in the game.
    //
    // Scoped to Pitcher only. It's the one position where an exact range has
    // real stakes (re-entry, pitch counts). Zone and bench assigns stay
    // purely additive, since implicitly avoiding e.g. infield outside a
    // stated inning could itself manufacture a genuine fair-play gap for that
    // same player. (This is the open question from the handoff docs — still
    // Pitcher-only until device testing says otherwise.)

    private func withImplicitPitcherAvoids(
        _ resolved: [AutoFillPlayerConstraint]
    ) -> [AutoFillPlayerConstraint] {
        var result = resolved

        let pitcherAssigns = resolved.filter {
            $0.intent == .assign && $0.target == .position(.pitcher)
        }
        for assign in pitcherAssigns {
            for range in complementRanges(of: assign.inningRange, totalInnings: inningCount) {
                result.append(AutoFillPlayerConstraint(
                    playerID: assign.playerID,
                    target: .position(.pitcher),
                    inningRange: range,
                    intent: .avoid
                ))
            }
        }

        return result
    }

    /// Zero-based inning ranges NOT covered by `range`, clamped to
    /// `0..<totalInnings`. Empty if `range` already spans the whole game.
    private func complementRanges(
        of range: ClosedRange<Int>,
        totalInnings: Int
    ) -> [ClosedRange<Int>] {
        guard totalInnings > 0 else { return [] }
        var result: [ClosedRange<Int>] = []
        if range.lowerBound > 0 {
            result.append(0...(range.lowerBound - 1))
        }
        if range.upperBound < totalInnings - 1 {
            result.append((range.upperBound + 1)...(totalInnings - 1))
        }
        return result
    }

    // MARK: - Pattern-rule confirmations

    /// Positive, coach-readable confirmations for any active game-wide pattern
    /// rule, so an applied rule that produces no visible per-player assignment
    /// still tells the coach it was understood.
    private func patternConfirmations(for rules: AutoFillPatternRules) -> [AutoFillNLDiagnostic] {
        var result: [AutoFillNLDiagnostic] = []
        if rules.benchInConsecutivePairs {
            result.append(AutoFillNLDiagnostic(
                kind: .patternRuleApplied("Bench pairing is on: once a player sits, they'll sit the next inning too, as long as enough others are available to field every spot.")
            ))
        }
        return result
    }

    // MARK: - Matching

    private func intent(from raw: String) -> AutoFillConstraintIntent {
        switch raw.lowercased() {
        case "avoid": return .avoid
        case "prioritize": return .prioritize
        default: return .assign
        }
    }

    /// Exact display-name match, then unambiguous first-name, then
    /// unambiguous prefix, then unambiguous contains, then a last-resort
    /// unambiguous close-edit-distance match to catch nicknames and typos
    /// ("Jonny" for "Jonathan", "Conner" for "Connor").
    ///
    /// With the dynamic schema in place the model can only emit exact roster
    /// names, so in practice the first tier handles everything. The rest is
    /// here for the fallback path and for defense in depth. Any ambiguity
    /// (0 or 2+ matches) returns nil rather than guessing — a wrong player is
    /// worse than a skipped instruction, and a skipped instruction is now at
    /// least reported.
    private func matchPlayer(named name: String, in players: [Player]) -> Player? {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }

        if let exact = players.first(where: { $0.displayName.lowercased() == normalized }) {
            return exact
        }

        let firstNameMatches = players.filter { $0.firstName.lowercased() == normalized }
        if firstNameMatches.count == 1 { return firstNameMatches.first }

        let prefixMatches = players.filter {
            $0.firstName.lowercased().hasPrefix(normalized)
                || normalized.hasPrefix($0.firstName.lowercased())
        }
        if prefixMatches.count == 1 { return prefixMatches.first }

        let containsMatches = players.filter { $0.displayName.lowercased().contains(normalized) }
        if containsMatches.count == 1 { return containsMatches.first }

        // Last resort: nickname/typo tolerance. Threshold scales with name
        // length so short names stay strict (2-char names shouldn't match
        // each other) while longer ones tolerate a slip or two.
        let threshold = normalized.count >= 6 ? 2 : 1
        let fuzzyMatches = players.filter {
            editDistance(normalized, $0.firstName.lowercased()) <= threshold
        }
        return fuzzyMatches.count == 1 ? fuzzyMatches.first : nil
    }

    /// Standard Levenshtein distance. Rosters are ~15 players and names are
    /// short, so the O(n*m) table is free at this scale.
    private func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }

        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)

        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(
                    previous[j] + 1,      // deletion
                    current[j - 1] + 1,   // insertion
                    previous[j - 1] + cost // substitution
                )
            }
            previous = current
        }

        return previous[b.count]
    }

    private func matchTarget(_ raw: String) -> AutoFillConstraintTarget? {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        switch normalized {
        case "infield": return .infield
        case "outfield": return .outfield
        case "bench": return .bench
        default: break
        }

        if let pos = FieldPosition.allCases.first(where: { $0.rawValue.lowercased() == normalized }) {
            return .position(pos)
        }

        let aliases: [String: FieldPosition] = [
            "pitcher": .pitcher, "catcher": .catcher,
            "first base": .firstBase, "second base": .secondBase,
            "third base": .thirdBase, "shortstop": .shortstop,
            "left field": .leftField, "center field": .centerField,
            "right field": .rightField,
            "left center field": .leftCenterField, "right center field": .rightCenterField
        ]
        return aliases[normalized].map { .position($0) }
    }
}
