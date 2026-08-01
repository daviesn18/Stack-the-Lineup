import AppIntents
import Foundation
import SwiftUI

// MARK: - Can They Pitch
//
// "Can Bobby pitch on Saturday?"
//
// Free and `openAppWhenRun = false`, matching FairPlayRuleIntent — Pitching
// Rules isn't Pro-gated in the app, so its answers aren't either.
//
// This is the one intent where a wrong answer has a consequence off the phone,
// so read the note at the top of PitchEligibility.swift before changing
// anything: the engine returns `.eligible` both for "rested" and for "nothing
// was configured to check", and only the first of those is a yes.

struct PitchEligibilityIntent: AppIntent {

    static let title: LocalizedStringResource = "Can They Pitch"

    static let description = IntentDescription(
        "Checks whether a player is rested and eligible to pitch, using your team's pitch counts and rest day rules.",
        categoryName: "Rules",
        searchKeywords: ["pitch", "pitcher", "eligible", "rest", "rested",
                         "available", "pitch count", "can they pitch"]
    )

    /// Answers in place. Nothing here mutates anything.
    static let openAppWhenRun = false

    @Parameter(
        title: "Player",
        description: "The player you want to check."
    )
    var player: PlayerEntity

    @Parameter(
        title: "Date",
        description: "The day you're asking about. Leave empty for today."
    )
    var date: Date?

    init() {}

    init(player: PlayerEntity, date: Date? = nil) {
        self.player = player
        self.date = date
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Can \(\.$player) pitch on \(\.$date)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let (teams, _) = TeamStorage.loadTeamsForReading()

        // The player identifies their own roster, so no team parameter — same
        // precedence a named player gets in FairPlayRuleIntent.
        guard let team = teams.first(where: { $0.id == player.teamID }),
              let resolved = team.players.first(where: { $0.id == player.id })
        else { throw STLIntentError.noSuchPlayer }

        let answer = PitchEligibilityAnswerBuilder.answer(
            player: resolved,
            team: team,
            on: date ?? Date()
        )

        Analytics.signal("intent.pitch_eligibility", parameters: [
            "verdict": Self.analyticsVerdict(answer.verdict),
            "askedFutureDate": date != nil ? "true" : "false"
        ])

        return .result(
            dialog: IntentDialog(
                full: LocalizedStringResource(stringLiteral: answer.spokenSummary),
                supporting: LocalizedStringResource(stringLiteral: answer.shortSummary)
            ),
            view: PitchEligibilitySnippetView(answer: answer)
        )
    }

    /// Coarse enough to be worth counting without recording who was benched.
    private static func analyticsVerdict(_ verdict: EligibilityVerdict) -> String {
        switch verdict {
        case .clear:            return "clear"
        case .limited:          return "limited"
        case .blocked:          return "blocked"
        case .notTracked:       return "not_tracked"
        }
    }
}

// MARK: - Snippet

struct PitchEligibilitySnippetView: View {

    let answer: PitchEligibilityAnswer

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            switch answer.verdict {
            case .notTracked:
                Label(answer.spokenSummary, systemImage: "info.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)

            default:
                VStack(alignment: .leading, spacing: 6) {
                    verdictRow
                    if let outing = answer.lastOuting {
                        row("Last outing",
                            value: "\(outing.pitches) P · \(PitchEligibilityAnswer.dayPhrase(outing.date))")
                    }
                }
            }
        }
        .padding(16)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(answer.playerDisplayName)
                .font(.headline)
            Text(answer.teamName.isEmpty ? answer.headline : answer.teamName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var verdictRow: some View {
        switch answer.verdict {
        case .clear(let maxPitches):
            Label("Clear to pitch — up to \(maxPitches) pitches",
                  systemImage: "checkmark.circle.fill")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.green)

        case .limited(let remaining):
            Label("Only \(remaining) pitches left under your cap",
                  systemImage: "exclamationmark.circle.fill")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.orange)

        case .blocked(let until):
            Label("Resting until \(PitchEligibilityAnswer.dayPhrase(until))",
                  systemImage: "moon.zzz.fill")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.red)

        case .notTracked:
            EmptyView()
        }
    }

    private func row(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.footnote)
            Spacer(minLength: 12)
            Text(value)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}
