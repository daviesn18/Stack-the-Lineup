import AppIntents
import Foundation
import SwiftUI

// MARK: - Team Rules
//
// "How many innings do I need to play someone in the infield?"
// "If Bobby throws 33 pitches, how many days rest does he need?"
//
// Free, unlike Fill Lineup and Game Recap. Rules Q&A is a discovery surface in
// the same way Spotlight is: the coach who asks this at a fence and gets a
// straight answer is the one who later finds out what Auto-Fill does.
//
// `openAppWhenRun = false`, which fixes how failure has to work — nothing comes
// forward to explain itself, so a thrown `localizedStringResource` IS the whole
// answer. Note the split that follows from it: this intent throws only when it
// can't tell *who* the coach is asking about (no such team, no such player),
// and answers normally when it knows who but the rule isn't there to quote
// (pitching switched off, no league age on file). The second group isn't a
// failure — "you haven't turned pitching rules on" is the correct answer to
// "what's my pitch limit", and it comes back as a dialog with a snippet rather
// than an error banner.
//
// Every number is read from the team's own FairPlayConfig and PitchingConfig.
// See the header of TeamRules.swift for why these aren't keyed to a governing
// body, and why nothing here is generated.

struct FairPlayRuleIntent: AppIntent {

    static let title: LocalizedStringResource = "Look Up a Rule"

    static let description = IntentDescription(
        "Answers what your team's fair play and pitching rules are, including pitch limits and rest days.",
        categoryName: "Rules",
        searchKeywords: ["rule", "rules", "fair play", "innings", "infield",
                         "outfield", "bench", "pitch count", "pitch limit", "rest"]
    )

    /// Answers in place. Nothing here mutates anything.
    static let openAppWhenRun = false

    @Parameter(
        title: "Rule",
        description: "Which rule to look up.",
        default: .overview
    )
    var topic: RuleTopicAppEnum

    @Parameter(
        title: "Team",
        description: "Leave empty to use the team you're currently coaching."
    )
    var team: TeamEntity?

    @Parameter(
        title: "Player",
        description: "For pitch limits and rest days — their league age decides which limits apply."
    )
    var player: PlayerEntity?

    @Parameter(
        title: "Pitch Count",
        description: "For rest days: how many pitches they threw. Leave empty for all the rest day thresholds.",
        inclusiveRange: (1, 250)
    )
    var pitchCount: Int?

    init() {}

    init(topic: RuleTopicAppEnum = .overview,
         team: TeamEntity? = nil,
         player: PlayerEntity? = nil,
         pitchCount: Int? = nil) {
        self.topic = topic
        self.team = team
        self.player = player
        self.pitchCount = pitchCount
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Look up \(\.$topic) for \(\.$team)") {
            \.$player
            \.$pitchCount
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let (teams, activeTeam) = TeamStorage.loadTeamsForReading()
        guard !teams.isEmpty else { throw STLIntentError.noTeam }

        // A named player identifies their own roster, so they pick the team —
        // same precedence GameRecapIntent gives a named game. A coach asking
        // about Bobby's rest days shouldn't get the active team's limits
        // because Bobby is on their other roster.
        var resolvedPlayer: Player?
        var target: Team?

        if let requested = self.player {
            guard let owning = teams.first(where: { $0.id == requested.teamID }),
                  let found = owning.players.first(where: { $0.id == requested.id })
            else { throw STLIntentError.noSuchPlayer }
            resolvedPlayer = found
            target = owning
        } else if let requested = self.team {
            target = teams.first { $0.id == requested.id }
        } else {
            target = activeTeam
        }

        guard let target else { throw STLIntentError.noTeam }

        let answer = TeamRulesBuilder.answer(
            topic: topic.topic,
            team: target,
            player: resolvedPlayer,
            pitchCount: pitchCount
        )

        Analytics.signal("intent.team_rules", parameters: [
            "topic": topic.rawValue,
            "namedPlayer": resolvedPlayer != nil ? "true" : "false",
            "gavePitchCount": pitchCount != nil ? "true" : "false",
            "deferred": answer.isDeferred ? "true" : "false"
        ])

        // `full` is what a voice-only surface says — the complete answer, since
        // there's no table to read there. `supporting` is what appears when the
        // snippet IS on screen, where restating every value above the table
        // prints each number twice and buries the table under a paragraph.
        return .result(
            dialog: IntentDialog(
                full: LocalizedStringResource(stringLiteral: answer.spokenSummary),
                supporting: LocalizedStringResource(stringLiteral: answer.shortSummary)
            ),
            view: TeamRulesSnippetView(answer: answer)
        )
    }
}

// MARK: - RuleTopicAppEnum
//
// The App Intents face of `RuleTopic`, kept a wrapper for the same reason
// FieldPositionAppEnum is one: TeamRules.swift stays framework-independent, and
// the exhaustive switch in both directions means adding a topic fails the build
// here until it's been given a spoken name.
//
// The synonyms are the load-bearing part. Siri matches a transcription against
// these titles, and no coach says "fielding minimum" out loud — they say "how
// many innings does everyone have to play".

nonisolated enum RuleTopicAppEnum: String, AppEnum, CaseIterable {
    case overview
    case fieldingMinimum
    case infieldMinimum
    case outfieldMinimum
    case benchRules
    case positionRules
    case batteryRules
    case pitchLimit
    case restDays

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Rule")

    static let caseDisplayRepresentations: [RuleTopicAppEnum: DisplayRepresentation] = [
        .overview: DisplayRepresentation(
            title: "All My Rules",
            subtitle: "Everything switched on",
            synonyms: ["my rules", "team rules", "fair play rules", "all rules", "rules"]
        ),
        .fieldingMinimum: DisplayRepresentation(
            title: "Fielding Minimum",
            subtitle: "Innings everyone has to field",
            synonyms: ["fielding innings", "minimum innings", "playing time",
                       "how many innings does everyone play", "sit"]
        ),
        .infieldMinimum: DisplayRepresentation(
            title: "Infield Minimum",
            subtitle: "Innings everyone needs in the infield",
            synonyms: ["infield innings", "infield", "how many innings in the infield"]
        ),
        .outfieldMinimum: DisplayRepresentation(
            title: "Outfield Minimum",
            subtitle: "Innings everyone needs in the outfield",
            synonyms: ["outfield innings", "outfield", "how many innings in the outfield"]
        ),
        .benchRules: DisplayRepresentation(
            title: "Bench Rules",
            subtitle: "Sitting out and equal bench time",
            synonyms: ["bench", "benching", "sitting out", "back to back bench"]
        ),
        .positionRules: DisplayRepresentation(
            title: "Position Rules",
            subtitle: "Outfielders and repeat positions",
            synonyms: ["positions", "how many outfielders", "same position"]
        ),
        .batteryRules: DisplayRepresentation(
            title: "Catching and Pitching",
            subtitle: "Moving between catcher and pitcher",
            synonyms: ["catcher to pitcher", "pitcher to catcher", "battery",
                       "can my catcher pitch"]
        ),
        .pitchLimit: DisplayRepresentation(
            title: "Pitch Limits",
            subtitle: "Pitches allowed in a game",
            synonyms: ["pitch count", "pitch limit", "how many pitches",
                       "daily max", "pitch max"]
        ),
        .restDays: DisplayRepresentation(
            title: "Rest Days",
            subtitle: "Rest a pitch count requires",
            synonyms: ["rest", "days rest", "days of rest", "how much rest",
                       "when can they pitch again"]
        )
    ]

    // MARK: - Bridge

    init(_ topic: RuleTopic) {
        switch topic {
        case .overview:        self = .overview
        case .fieldingMinimum: self = .fieldingMinimum
        case .infieldMinimum:  self = .infieldMinimum
        case .outfieldMinimum: self = .outfieldMinimum
        case .benchRules:      self = .benchRules
        case .positionRules:   self = .positionRules
        case .batteryRules:    self = .batteryRules
        case .pitchLimit:      self = .pitchLimit
        case .restDays:        self = .restDays
        }
    }

    var topic: RuleTopic {
        switch self {
        case .overview:        return .overview
        case .fieldingMinimum: return .fieldingMinimum
        case .infieldMinimum:  return .infieldMinimum
        case .outfieldMinimum: return .outfieldMinimum
        case .benchRules:      return .benchRules
        case .positionRules:   return .positionRules
        case .batteryRules:    return .batteryRules
        case .pitchLimit:      return .pitchLimit
        case .restDays:        return .restDays
        }
    }
}

// MARK: - Snippet
//
// The dialog carries the complete answer; this is the same rules for a coach
// who is looking at the phone rather than listening. It stays a scannable
// label/value table because that's what the spoken version can't be.
//
// Row count is capped for the reason recorded in the Phase 3 notes: a snippet
// clips at whatever height is left after the dialog and does not scroll, so an
// unbounded list silently pushes its own last rows off the bottom.

struct TeamRulesSnippetView: View {

    let answer: TeamRulesAnswer

    /// Rows rendered before deferring to the app.
    private static let rowLimit = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if !answer.lines.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(answer.lines.prefix(Self.rowLimit).enumerated()), id: \.offset) { _, line in
                        row(line)
                    }
                    if answer.lines.count > Self.rowLimit {
                        Text("+\(answer.lines.count - Self.rowLimit) more in the app")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            if let caveat = answer.caveat {
                Label(caveat, systemImage: "info.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        .padding(16)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(answer.teamName.isEmpty ? "My Team" : answer.teamName)
                .font(.headline)
            Text(answer.headline)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func row(_ line: RuleLine) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(line.label)
                .font(.footnote)
            Spacer(minLength: 12)
            Text(line.value)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}
