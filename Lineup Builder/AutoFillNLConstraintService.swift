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

    @Guide(description: "True if the coach wants any player who sits to sit two innings in a row — e.g. \"players sit two innings in a row\", \"any player who sits must sit 2 consecutive innings\", \"if someone sits an inning they sit the next too\", \"double up the bench\". \"2 consecutive innings\" or \"two in a row\" tied to sitting is this flag, not a per-player inning range. Names no specific player. False otherwise, including the opposite request (\"don't sit anyone twice in a row\").")
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

        // Deterministic pattern-rule detection runs FIRST and regardless of
        // model availability. Game-wide pattern rules like bench pairing are a
        // single boolean flipped from niche phrasing ("any player who sits must
        // sit two consecutive innings"), and asking an on-device model to set
        // one reliably from arbitrary wording is exactly the kind of thing it
        // quietly gets wrong. A keyword scan is dull but dependable, in the same
        // spirit as the name-matching fallbacks below.
        let promptPatternRules = Self.detectedPatternRules(in: trimmed)

        guard isAvailable else {
            // No model on this device. We can't parse per-player instructions,
            // but a recognized pattern-rule prompt shouldn't need the model at
            // all — honor it rather than throwing the whole prompt away.
            guard !promptPatternRules.isEmpty else {
                throw AutoFillNLParseError.unsupported
            }
            return AutoFillNLParseResult(
                constraints: AutoFillConstraintSet(playerConstraints: [], patternRules: promptPatternRules),
                diagnostics: patternConfirmations(for: promptPatternRules)
            )
        }

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

        // OR the deterministic detection over whatever the model produced, so a
        // pattern rule the model missed is still applied.
        let merged = mergingPatternRules(promptPatternRules, into: result)
        return withClauseCountCheck(merged, prompt: trimmed)
    }

    // MARK: - Deterministic pattern-rule detection
    //
    // A keyword safety net for the game-wide pattern rules the model is asked to
    // set as flags. These name no player and hinge on one boolean, so a missed
    // one is invisible until the coach notices the lineup is wrong — the exact
    // failure this whole service was built to avoid.

    /// Pattern rules recognizable from the prompt text alone. Internal (not
    /// private) so the deterministic detection can be unit-tested without an
    /// on-device model, which the simulator doesn't provide.
    /// Pure text detection — deliberately `nonisolated static` so it needs
    /// neither a model session nor a roster. This is what lets the coordinator
    /// apply pattern rules as a safety net even when the model parse times out
    /// or throws (both of which otherwise discard the whole result), and it's
    /// why bench pairing works on hardware where the on-device model is slower
    /// or flakier than the simulator's absent one.
    nonisolated static func detectedPatternRules(in prompt: String) -> AutoFillPatternRules {
        AutoFillPatternRules(
            benchInConsecutivePairs: promptRequestsBenchPairing(prompt)
        )
    }

    /// Coach-facing confirmation for the bench-pairing rule. A single source so
    /// the parse path and the coordinator's safety-net path show identical copy.
    nonisolated static let benchPairingConfirmationMessage =
        "Bench pairing is on: once a player sits, they'll sit the next inning too, as long as enough others are available to field every spot."

    /// True when the prompt asks for consecutive bench innings, in the natural
    /// ways a coach actually says it: "sit two in a row", "any player who sits
    /// must sit 2 consecutive innings", "double up the bench", "if a player
    /// sits, have them sit the next one too", "bench them again."
    ///
    /// In baseball "sit" IS "bench," so both vocabularies count. This leans
    /// toward RECALL on purpose: the flag surfaces a visible "Bench pairing is
    /// on" confirmation to the coach, so an over-trigger is cheap and instantly
    /// correctable, whereas a silent miss is the exact failure that made the
    /// feature look broken. A bench word is still required (so "two consecutive
    /// innings at shortstop" doesn't trip it), and negations bail out ("no
    /// back-to-back bench" is the opposite request, already the default).
    nonisolated static func promptRequestsBenchPairing(_ prompt: String) -> Bool {
        let p = prompt.lowercased()

        // Negation = the opposite request (avoid back-to-back / don't repeat a
        // sit), which is already the default fair-play behavior.
        let negations = [
            "no back", "not back", "no consecutive", "not consecutive",
            "no two in a row", "not two in a row", "no 2 in a row",
            "don't sit", "do not sit", "dont sit", "never sit", "avoid sitting",
            "don't have", "do not have", "dont have", "no double", "without sitting",
            "turn off", "turned off", "disable", "no pairing", "without pairing"
        ]
        if negations.contains(where: { p.contains($0) }) { return false }

        // The literal feature name, however the coach phrases turning it on
        // ("turn on bench pairing", "enable bench pairing", "use pairing").
        // Checked before the bench-word guard so "pair the bench" counts even
        // though the coach didn't say "sit."
        let featureNameTerms = [
            "bench pairing", "bench pair", "pair the bench", "pair up the bench",
            "pair benches", "pairing the bench"
        ]
        if featureNameTerms.contains(where: { p.contains($0) }) { return true }

        // "sit" and "bench" are the same concept in sports lingo.
        let benchTerms = ["sit", "sits", "sitting", "sat", "bench", "benched"]
        guard benchTerms.contains(where: { p.contains($0) }) else { return false }

        // Unambiguous pairing vocabulary. A bench word is guaranteed present by
        // the guard above, so "pairing"/"pair" here already means the bench.
        let pairingTerms = [
            "consecutive", "in a row", "back to back", "back-to-back",
            "two in a row", "2 in a row", "twice in a row", "double up",
            "pairing", "paired", "in pairs", "pair up"
        ]
        if pairingTerms.contains(where: { p.contains($0) }) { return true }

        // Conversational repetition forms: "sit them again", "sit the next one
        // too / as well." A bench word is already present per the guard above.
        if p.contains("again") { return true }
        if p.contains("next") && (p.contains("too") || p.contains("also") || p.contains("as well")) {
            return true
        }

        return false
    }

    /// Folds deterministically-detected pattern rules into a model parse result,
    /// setting any flag the model left off and adding its coach-facing
    /// confirmation exactly once.
    private func mergingPatternRules(
        _ detected: AutoFillPatternRules,
        into result: AutoFillNLParseResult
    ) -> AutoFillNLParseResult {
        // Only bench pairing exists today; the guard keeps this a no-op unless
        // the detector adds something the model result didn't already carry.
        guard detected.benchInConsecutivePairs,
              !result.constraints.patternRules.benchInConsecutivePairs else {
            return result
        }
        var rules = result.constraints.patternRules
        rules.benchInConsecutivePairs = true
        return AutoFillNLParseResult(
            constraints: AutoFillConstraintSet(
                playerConstraints: result.constraints.playerConstraints,
                patternRules: rules
            ),
            diagnostics: result.diagnostics + patternConfirmations(for: detected)
        )
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

        BENCH PAIRING. Set benchInConsecutivePairs to true whenever the coach \
        wants any player who sits to sit two innings in a row — "have players sit \
        two innings in a row", "any player who sits must sit 2 consecutive \
        innings", "if a player sits one inning, have them sit the next too", \
        "nobody sits just once", "double up the bench". A phrase like "2 \
        consecutive innings" or "two in a row" tied to sitting/benching is this \
        rule, NOT a per-player inning range. It names no specific player and \
        produces NO per-player entry; it only sets that one flag. Leave it false \
        for everything else, including ordinary bench placements for a named \
        player ("Jake starts on the bench"), which are per-player entries, not \
        this pattern, and the opposite request ("don't sit anyone twice in a \
        row"), which is not this rule.

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
                    description: "True if the coach wants any player who sits to sit two innings in a row — e.g. \"players sit two innings in a row\", \"any player who sits must sit 2 consecutive innings\", \"if someone sits an inning they sit the next too\", \"double up the bench\". \"2 consecutive innings\" or \"two in a row\" tied to sitting is this flag, not a per-player inning range. Names no specific player. False otherwise, including the opposite request (\"don't sit anyone twice in a row\").",
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

    // MARK: - Deterministic parsing
    //
    // A model-free parser for the common, templated ways coaches actually write
    // Auto-Fill instructions ("Caleb pitches the first 2 innings", "keep Sam off
    // pitcher", "Marcus, Drew and Eli play infield", "Jake starts on the bench").
    // It runs BEFORE the on-device model (see parse()), so the frequent cases are
    // instant, reliable, offline, and work on every device — the model is only
    // needed for freeform phrasing this can't map.
    //
    // Precision over recall on purpose: an ambiguous clause is reported
    // `hasUnresolvedInstruction`, and the caller falls back to the model (or
    // surfaces a diagnostic when there is none). A wrong constraint is worse than
    // a deferred one.

    struct DeterministicParse {
        var constraints: [AutoFillPlayerConstraint]
        /// True when the text clearly holds a player-specific instruction the
        /// parser could not confidently map — the signal to try the model.
        var hasUnresolvedInstruction: Bool
    }

    /// Position / zone / bench vocabulary, longest phrases first so "first base"
    /// wins over a later "base", and "left center field" is consumed before
    /// "center field". Case-insensitive, word-bounded.
    private static let targetPhrases: [(String, AutoFillConstraintTarget)] = [
        ("left center field", .position(.leftCenterField)),
        ("right center field", .position(.rightCenterField)),
        ("center field", .position(.centerField)),
        ("left field", .position(.leftField)),
        ("right field", .position(.rightField)),
        ("first base", .position(.firstBase)),
        ("second base", .position(.secondBase)),
        ("third base", .position(.thirdBase)),
        ("shortstop", .position(.shortstop)),
        ("short stop", .position(.shortstop)),
        ("catcher", .position(.catcher)),
        ("pitcher", .position(.pitcher)),
        ("infield", .infield),
        ("outfield", .outfield),
        ("bench", .bench),
        ("1b", .position(.firstBase)),
        ("2b", .position(.secondBase)),
        ("3b", .position(.thirdBase)),
        ("ss", .position(.shortstop)),
        ("lcf", .position(.leftCenterField)),
        ("rcf", .position(.rightCenterField)),
        ("lf", .position(.leftField)),
        ("cf", .position(.centerField)),
        ("rf", .position(.rightField)),
        ("short", .position(.shortstop)),
    ]

    /// Verb anchors that imply a position without naming it. Checked after the
    /// explicit phrases above.
    private static let verbTargets: [(String, AutoFillConstraintTarget)] = [
        ("pitches", .position(.pitcher)), ("pitching", .position(.pitcher)),
        ("pitch", .position(.pitcher)), ("on the mound", .position(.pitcher)),
        ("catches", .position(.catcher)), ("catching", .position(.catcher)),
        ("catch", .position(.catcher)), ("behind the plate", .position(.catcher)),
    ]

    func parseDeterministically(_ prompt: String) -> DeterministicParse {
        // Ambiguity guard: if two active players share a first name, a bare
        // first-name mention can't be resolved deterministically — defer the
        // whole thing to the model rather than assign to the wrong kid.
        let firstNames = activePlayers.map { $0.firstName.lowercased() }
        let hasDuplicateFirstNames = Set(firstNames).count != firstNames.count

        var constraints: [AutoFillPlayerConstraint] = []
        var unresolved = false

        for clause in splitClauses(prompt) {
            let lower = clause.lowercased()
            guard let target = firstTarget(in: lower) else {
                // No position/zone/bench here. If it named a player, it's an
                // instruction we didn't understand.
                if !playersMentioned(in: lower).isEmpty { unresolved = true }
                continue
            }
            if hasDuplicateFirstNames, !playersMentioned(in: lower).isEmpty {
                unresolved = true
                continue
            }
            let players = clausePlayers(in: lower)
            guard !players.isEmpty else {
                // A target with no player we can name — e.g. the "then plays
                // outfield" half of a same-subject compound, or a relative
                // range ("the next 2"). Guessing the subject/inning here would
                // place a wrong assignment; defer the whole prompt to the model.
                unresolved = true
                continue
            }
            let intent = clauseIntent(in: lower)
            // Default range when none is stated: a bare assign means inning 1
            // only (matching the model's documented rule), but a bare avoid or
            // prioritize means the whole game — "keep Sam off pitcher" is not an
            // inning-1-only request.
            let defaultRange = intent == .assign ? (0...0) : (0...(inningCount - 1))
            let range = parseRange(in: lower) ?? defaultRange
            for player in players {
                constraints.append(AutoFillPlayerConstraint(
                    playerID: player.id, target: target, inningRange: range, intent: intent))
            }
        }

        // Coverage: a named player who ended up with no constraint means we
        // missed their instruction.
        if !hasDuplicateFirstNames {
            let covered = Set(constraints.map { $0.playerID })
            if playersMentioned(in: prompt.lowercased()).contains(where: { !covered.contains($0.id) }) {
                unresolved = true
            }
        } else if !playersMentioned(in: prompt.lowercased()).isEmpty {
            unresolved = true
        }

        return DeterministicParse(
            constraints: withImplicitPitcherAvoids(constraints),
            hasUnresolvedInstruction: unresolved
        )
    }

    // MARK: Clause splitting

    /// Splits a prompt into instruction clauses. Strong separators (newlines,
    /// ";", "then", "after that") always split. Commas and "and" split ONLY when
    /// both sides carry a target anchor — so "Caleb pitches, Owen catches" splits
    /// into two, but the name list "Marcus, Drew and Eli play infield" stays one.
    private func splitClauses(_ prompt: String) -> [String] {
        let strong = prompt
            .replacingOccurrences(of: " and then ", with: "\n")
            .replacingOccurrences(of: " then ", with: "\n")
            .replacingOccurrences(of: " after that ", with: "\n")
            .replacingOccurrences(of: ";", with: "\n")
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return strong.flatMap { conditionallySplit($0) }
    }

    private func conditionallySplit(_ clause: String) -> [String] {
        for sep in [", ", " and "] {
            var from = clause.startIndex
            while let r = clause.range(of: sep, range: from..<clause.endIndex) {
                let left = String(clause[..<r.lowerBound])
                let right = String(clause[r.upperBound...])
                if firstTarget(in: left.lowercased()) != nil,
                   firstTarget(in: right.lowercased()) != nil {
                    return conditionallySplit(left) + conditionallySplit(right)
                }
                from = r.upperBound
            }
        }
        return [clause]
    }

    // MARK: Clause fields

    /// The position/zone/bench a clause refers to, or nil if none is present.
    private func firstTarget(in lower: String) -> AutoFillConstraintTarget? {
        var best: (index: String.Index, target: AutoFillConstraintTarget)?
        func consider(_ phrase: String, _ target: AutoFillConstraintTarget) {
            guard let idx = wordRange(of: phrase, in: lower)?.lowerBound else { return }
            if best == nil || idx < best!.index { best = (idx, target) }
        }
        for (phrase, target) in Self.targetPhrases { consider(phrase, target) }
        if best != nil { return best!.target }
        for (phrase, target) in Self.verbTargets { consider(phrase, target) }
        return best?.target
    }

    private func clausePlayers(in lower: String) -> [Player] {
        if lower.contains("everyone") || lower.contains("everybody")
            || lower.contains("all players") || lower.contains("whole team")
            || lower.contains("the team") {
            return activePlayers
        }
        return playersMentioned(in: lower)
    }

    private func playersMentioned(in lower: String) -> [Player] {
        var seen = Set<UUID>()
        var result: [Player] = []
        for p in activePlayers {
            let name = p.firstName.lowercased()
            guard !name.isEmpty, !seen.contains(p.id) else { continue }
            if wordRange(of: name, in: lower) != nil {
                seen.insert(p.id); result.append(p)
            }
        }
        return result
    }

    private func clauseIntent(in lower: String) -> AutoFillConstraintIntent {
        let prioritize = ["prefer", "if possible", "when possible", "ideally", "try to"]
        if prioritize.contains(where: { lower.contains($0) }) { return .prioritize }
        // "keep X off Y", "don't let X pitch", "no pitching for X", etc. Note
        // "keep" alone is NOT avoid — "keep X at short" is an assign; the avoid
        // signal is off/never/avoid/don't/not/can't.
        let avoid = [" off ", "off the", "don't", "do not", "dont", "never",
                     "avoid", "not at", "not in", "can't", "cannot", "stay off", "away from"]
        if avoid.contains(where: { lower.contains($0) }) { return .avoid }
        return .assign
    }

    // MARK: Inning ranges

    private static let numberWords: [String: Int] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9,
        "first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5,
        "sixth": 6, "seventh": 7, "eighth": 8, "ninth": 9
    ]

    /// Zero-based, inclusive, clamped inning range from a clause, or nil when no
    /// inning is stated (caller defaults to inning 1 only, matching the model).
    private func parseRange(in lower: String) -> ClosedRange<Int>? {
        guard inningCount > 0 else { return nil }
        let last = inningCount - 1
        func clamp(_ oneBased: Int) -> Int { max(0, min(oneBased - 1, last)) }

        if lower.contains("all game") || lower.contains("whole game")
            || lower.contains("entire game") || lower.contains("every inning") {
            return 0...last
        }
        // Explicit "innings X-Y" / "X to Y" / "X through Y".
        if let m = firstMatch(#"innings?\s+(\d+)\s*(?:-|to|through|thru|and)\s*(\d+)"#, in: lower),
           let a = Int(m[1]), let b = Int(m[2]) {
            let lo = clamp(min(a, b)), hi = clamp(max(a, b))
            return lo...hi
        }
        // "first N innings" / "first inning".
        if let n = countAfter(anyOf: ["first", "the first"], in: lower) {
            return 0...clamp(n)
        }
        // "last N innings" / "last inning".
        if let n = countAfter(anyOf: ["last", "the last"], in: lower) {
            let lo = max(0, inningCount - n)
            return lo...last
        }
        // "start" / "starts" / "to start" / "begins" — inning 1 only.
        if wordRange(of: "start", in: lower) != nil || wordRange(of: "starts", in: lower) != nil
            || wordRange(of: "starting", in: lower) != nil || wordRange(of: "begins", in: lower) != nil
            || wordRange(of: "begin", in: lower) != nil {
            return 0...0
        }
        // "inning X" / "the Xth inning" / "in the Xth".
        if let m = firstMatch(#"inning\s+(\d+)"#, in: lower), let a = Int(m[1]) {
            return clamp(a)...clamp(a)
        }
        if let m = firstMatch(#"(\d+)(?:st|nd|rd|th)\s+inning"#, in: lower), let a = Int(m[1]) {
            return clamp(a)...clamp(a)
        }
        for (word, n) in Self.numberWords {
            if wordRange(of: "\(word) inning", in: lower) != nil {
                return clamp(n)...clamp(n)
            }
        }
        return nil
    }

    /// For "first N innings": returns N (digit or number word), or 1 for a bare
    /// "first inning". nil when the anchor isn't present.
    private func countAfter(anyOf anchors: [String], in lower: String) -> Int? {
        for anchor in anchors {
            // "<anchor> <number> inning(s)"
            if let m = firstMatch(#"\#(anchor)\s+(\d+)\s+innings?"#, in: lower), let n = Int(m[1]) {
                return n
            }
            for (word, n) in Self.numberWords {
                if lower.contains("\(anchor) \(word) innings") { return n }
            }
            // Bare "<anchor> inning" → 1.
            if lower.contains("\(anchor) inning") && !lower.contains("\(anchor) innings") {
                return 1
            }
        }
        return nil
    }

    // MARK: Regex helpers

    private func wordRange(of phrase: String, in text: String) -> Range<String.Index>? {
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: phrase))\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: ns) else { return nil }
        return Range(match.range, in: text)
    }

    /// Returns capture groups [full, g1, g2, ...] of the first match, or nil.
    private func firstMatch(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = NSRange(text.startIndex..., in: text)
        guard let m = regex.firstMatch(in: text, range: ns) else { return nil }
        return (0..<m.numberOfRanges).map {
            Range(m.range(at: $0), in: text).map { String(text[$0]) } ?? ""
        }
    }

    // MARK: - Pattern-rule confirmations

    /// Positive, coach-readable confirmations for any active game-wide pattern
    /// rule, so an applied rule that produces no visible per-player assignment
    /// still tells the coach it was understood.
    private func patternConfirmations(for rules: AutoFillPatternRules) -> [AutoFillNLDiagnostic] {
        var result: [AutoFillNLDiagnostic] = []
        if rules.benchInConsecutivePairs {
            result.append(AutoFillNLDiagnostic(
                kind: .patternRuleApplied(Self.benchPairingConfirmationMessage)
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
