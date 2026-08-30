import Combine
import Foundation

// MARK: - AutoFillCoordinator
//
// One place that knows how to run an Auto-Fill end to end: parse the coach's
// natural-language prompt (racing a timeout), call AutoFillEngine, compose the
// coach-facing messages, and emit analytics.
//
// Three callers need that sequence — the iPhone grid, the iPad summary pane,
// and FillLineupIntent. Before this existed the first two each had their own
// copy, and they had already drifted: the iPhone version rebuilt the
// "couldn't fill" text in a private helper that duplicated
// AutoFillResult.incompleteMessage(multiInning:) almost line for line, the two
// alert-sequencing delays differed, and only one of them captured an undo
// snapshot. Adding a third copy for the intent is how that becomes permanent.
//
// What stays with the callers: alerts, toasts, popover state, undo. This type
// deliberately owns no UI state and never touches LineupStore — it takes a
// Team in and hands an outcome back, which is also what lets an App Intent use
// it without a view hierarchy.

/// What a fill should cover. Inning indices are zero-based, matching
/// `Lineup.innings`, and only become 1-based in coach-facing text.
nonisolated enum AutoFillScope: Equatable {
    /// Just the inning currently on screen.
    case inning(Int)
    /// Innings 1 through this index, inclusive.
    case through(Int)

    var isMultiInning: Bool {
        if case .through = self { return true }
        return false
    }

    /// How this scope reads in a sentence: "inning 3", "innings 1–6".
    var label: String {
        switch self {
        case .inning(let index):  return "inning \(index + 1)"
        case .through(let last):  return "innings 1–\(last + 1)"
        }
    }

    /// Analytics dimension. Matches the values the shipped `autofill.used`
    /// signal already reports, so the existing funnel stays continuous.
    var analyticsMode: String {
        switch self {
        case .inning:  return "inning"
        case .through: return "range"
        }
    }
}

/// Everything one Auto-Fill produced, with no UI attached.
nonisolated struct AutoFillOutcome {
    let scope: AutoFillScope
    /// The filled lineup. Only worth writing back when `didFill` is true.
    let lineup: Lineup
    let filledCount: Int
    let unfilledSlots: [AutoFillUnfilledSlot]
    /// Why some slots stayed empty, or nil when everything filled.
    let incompleteMessage: String?
    /// Parse misses and engine overrides, already combined into one block of
    /// text, or nil when there's nothing to report.
    let noticeMessage: String?

    var didFill: Bool { filledCount > 0 }
    var hasUnfilledSlots: Bool { !unfilledSlots.isEmpty }

    /// Undo toast copy: "Auto-filled 9 positions (inning 3)".
    var undoMessage: String {
        let noun = filledCount == 1 ? "position" : "positions"
        return "Auto-filled \(filledCount) \(noun) (\(scope.label))"
    }

    /// What Siri says back. The alert copy is written for a screen the coach is
    /// already looking at, so the lead sentence here has to carry the result on
    /// its own before any caveats follow.
    var spokenSummary: String {
        var lead: String
        if didFill {
            let noun = filledCount == 1 ? "position" : "positions"
            lead = "Filled \(filledCount) \(noun) in \(scope.label)."
        } else if hasUnfilledSlots {
            lead = "I couldn't fill anything in \(scope.label)."
        } else {
            lead = "Every position in \(scope.label) was already assigned."
        }

        for detail in [incompleteMessage, noticeMessage].compactMap({ $0 }) {
            lead += " " + detail.replacingOccurrences(of: "\n\n", with: " ")
                                .replacingOccurrences(of: "\n", with: " ")
        }
        return lead
    }
}

@MainActor
final class AutoFillCoordinator: ObservableObject {

    /// True while the on-device parse is in flight. Drives the popover's
    /// "Reading your instructions…" spinner.
    @Published private(set) var isParsingPrompt = false

    /// Owns the on-device LanguageModelSession. Rebuilt on every prewarm so the
    /// roster and inning count baked into the session are always current.
    private var nlService: AutoFillNLConstraintService?

    init() {}

    // MARK: - NL Session Lifecycle

    /// Builds a fresh NL service for this team and warms the on-device model.
    /// Call when the Auto-Fill popover opens, **not** when Fill is tapped.
    ///
    /// This is the single biggest speed lever in the feature. Creating the
    /// session inside `parse()` made every Fill tap pay full model load plus
    /// instruction prefill before a single token could be generated; doing it
    /// here spends that cost during the seconds the coach is already typing.
    func prewarm(for team: Team) {
        let service = makeService(for: team)
        service.prewarm()
        nlService = service
    }

    /// Popover closed without a fill. Drop the session so a warm model isn't
    /// held open indefinitely.
    func teardown() {
        nlService = nil
    }

    private func makeService(for team: Team) -> AutoFillNLConstraintService {
        AutoFillNLConstraintService(
            activePlayers: team.lineup.activePlayers(from: team.players),
            inningCount: team.lineup.innings.count
        )
    }

    // MARK: - Running a Fill

    /// Parses `prompt` (if any), runs AutoFillEngine over `team`, and composes
    /// the coach-facing messages.
    ///
    /// A blank prompt, or an on-device parse failure, falls back to
    /// unconstrained behavior rather than blocking the fill — a coach who just
    /// wants the normal Auto-Fill shouldn't be interrupted by an Apple
    /// Intelligence availability check they never asked to trigger.
    ///
    /// Callers are responsible for writing `outcome.lineup` back and for every
    /// piece of UI that follows.
    func run(scope: AutoFillScope, prompt: String, team: Team) async -> AutoFillOutcome {
        var constraints = AutoFillConstraintSet.empty
        var parseDiagnosticMessage: String? = nil

        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPrompt.isEmpty {
            isParsingPrompt = true
            let parseResult = await parseWithTimeout(prompt: prompt, team: team)
            constraints = parseResult.constraints
            parseDiagnosticMessage = parseResult.diagnosticMessage
            Analytics.signal("autofill.nl_prompt_used", parameters: [
                "constraintCount": "\(constraints.playerConstraints.count)",
                "diagnosticCount": "\(parseResult.diagnostics.count)"
            ])
            isParsingPrompt = false

            // Safety net for game-wide pattern rules. The on-device model parse
            // can time out (8s cap) or throw — on hardware far more than in the
            // model-less simulator — and both cases return `.empty`, silently
            // dropping a rule the coach plainly typed. Pattern detection is pure,
            // instant text matching that never needed the model, so re-apply it
            // here over whatever the parse produced. Idempotent: a no-op when the
            // parse already set the flag.
            let before = constraints.patternRules
            (constraints, parseDiagnosticMessage) = Self.applyingPatternRuleSafetyNet(
                to: constraints, prompt: trimmedPrompt, diagnostic: parseDiagnosticMessage
            )
            if constraints.patternRules != before {
                Analytics.signal("autofill.pattern_rule_safety_net", parameters: [
                    "rule": "benchInConsecutivePairs"
                ])
            }
        }

        let preferences = Dictionary(
            uniqueKeysWithValues: team.players.map { ($0.id, $0.positionPreferences) }
        )

        let result: AutoFillResult
        switch scope {
        case .inning(let index):
            result = AutoFillEngine.fillInning(
                index,
                in: team.lineup,
                players: team.players,
                preferences: preferences,
                config: team.fairPlayConfig,
                pitchingConfig: team.pitchingConfig,
                gameLogs: team.gameLogs,
                constraints: constraints
            )
        case .through(let lastInning):
            result = AutoFillEngine.fillInnings(
                through: lastInning,
                in: team.lineup,
                players: team.players,
                preferences: preferences,
                config: team.fairPlayConfig,
                pitchingConfig: team.pitchingConfig,
                gameLogs: team.gameLogs,
                constraints: constraints
            )
        }

        Analytics.signal("autofill.used", parameters: [
            "mode": scope.analyticsMode,
            "filledCount": "\(result.filledCount)",
            "unfilledCount": "\(result.unfilledSlots.count)"
        ])

        return Self.outcome(
            from: result,
            scope: scope,
            players: team.players,
            parseDiagnosticMessage: parseDiagnosticMessage
        )
    }

    /// Message composition, split out so it can be tested without an on-device
    /// model or a live team.
    ///
    /// Parse-side diagnostics (an instruction we couldn't resolve at all) and
    /// engine-side notices (an instruction we honored by bending a fair-play
    /// guideline) are deliberately one message: from the coach's point of view
    /// they're all "here's what happened to what you asked for". Parse misses
    /// lead, since a skipped instruction is the more surprising outcome.
    nonisolated static func outcome(
        from result: AutoFillResult,
        scope: AutoFillScope,
        players: [Player],
        parseDiagnosticMessage: String?
    ) -> AutoFillOutcome {
        let combinedNotice = [parseDiagnosticMessage, result.constraintNoticeMessage(players: players)]
            .compactMap { $0 }
            .joined(separator: "\n")

        return AutoFillOutcome(
            scope: scope,
            lineup: result.lineup,
            filledCount: result.filledCount,
            unfilledSlots: result.unfilledSlots,
            incompleteMessage: result.incompleteMessage(multiInning: scope.isMultiInning),
            noticeMessage: combinedNotice.isEmpty ? nil : combinedNotice
        )
    }

    // MARK: - Pattern-Rule Safety Net
    //
    // Re-applies deterministic, model-free pattern detection over whatever the
    // parse produced. Pure and standalone so it can be unit-tested without an
    // on-device model — which is exactly the situation it exists to cover (the
    // model timed out or threw, so the parse came back empty). Idempotent: when
    // the parse already carried the rule, nothing changes.
    nonisolated static func applyingPatternRuleSafetyNet(
        to constraints: AutoFillConstraintSet,
        prompt: String,
        diagnostic: String?
    ) -> (AutoFillConstraintSet, String?) {
        let detected = AutoFillNLConstraintService.detectedPatternRules(in: prompt)
        guard detected.benchInConsecutivePairs,
              !constraints.patternRules.benchInConsecutivePairs else {
            return (constraints, diagnostic)
        }
        let merged = AutoFillConstraintSet(
            playerConstraints: constraints.playerConstraints,
            patternRules: AutoFillPatternRules(benchInConsecutivePairs: true)
        )
        let message = [diagnostic, AutoFillNLConstraintService.benchPairingConfirmationMessage]
            .compactMap { $0 }
            .joined(separator: "\n")
        return (merged, message)
    }

    // MARK: - Parse Timeout

    /// Races the NL parse against a timeout so a slow or stuck on-device model
    /// call can never leave the coach staring at a spinner indefinitely. Falls
    /// back to unconstrained after `timeout` elapses.
    ///
    /// With prewarming in place the session is already warm and the
    /// instructions already prefilled by the time this runs, so a normal parse
    /// should land well inside the timeout. The old 12s ceiling was sized for a
    /// cold start on every call; 8s is a more honest bound now, and if the model
    /// hasn't answered in 8 seconds with a warm session, waiting longer is
    /// unlikely to help.
    ///
    /// Note: if the underlying model call ignores cancellation it may keep
    /// running in the background after the timeout wins. That's harmless (the
    /// result is discarded), just not free.
    private func parseWithTimeout(
        prompt: String,
        team: Team,
        timeout: Duration = .seconds(8)
    ) async -> AutoFillNLParseResult {
        // prewarm() should have built this. If it somehow didn't — an intent
        // invocation never opens a popover — build one now rather than
        // silently skipping the parse and ignoring what the coach asked for.
        let service = nlService ?? {
            let fresh = makeService(for: team)
            nlService = fresh
            return fresh
        }()

        // Run the parse as its own main-actor task, then race its *handle*
        // against a timeout. Racing the Task (which is Sendable) rather than
        // capturing the non-Sendable `service` directly inside the task-group
        // closures is what keeps this legible to Swift 6's region-isolation
        // checker — a plain `group.addTask { @MainActor in service.parse(...) }`
        // trips a checker limitation on the captured main-actor service.
        let parseTask = Task { @MainActor in
            do {
                return try await service.parse(prompt: prompt)
            } catch {
                // Apple Intelligence unavailable, or the model call failed.
                // Proceed unconstrained rather than blocking the fill.
                return AutoFillNLParseResult.empty
            }
        }

        // `nil` is the timeout marker; a real parse result is always non-nil.
        return await withTaskGroup(of: AutoFillNLParseResult?.self) { group in
            group.addTask { await parseTask.value }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            // If the timeout won, stop the parse. Harmless if the model call
            // ignores cancellation — its result is simply discarded.
            parseTask.cancel()
            return first ?? .empty
        }
    }
}
