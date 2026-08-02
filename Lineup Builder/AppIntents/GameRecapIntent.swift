import AppIntents
import Foundation
import SwiftUI

// MARK: - Game Recap
//
// "How did the Tigers do today?"
//
// The first `openAppWhenRun = false` intent: it answers by voice without ever
// foregrounding the app. That's the whole point — a coach asking this is usually
// walking to the car with a bag of bats, and opening the app to read a screen
// they can't hold is a worse answer than a sentence.
//
// It also changes how failure works. FillLineupIntent could not throw on a
// failed Pro check, because `openAppWhenRun = true` brings the app forward
// regardless and the coach would be left staring at an unchanged screen with no
// explanation (see the Phase 2 notes). Here there is no app coming forward, so
// a thrown error IS the answer, and `STLIntentError` is the right channel for
// every failure including the Pro gate.

struct GameRecapIntent: AppIntent {

    static let title: LocalizedStringResource = "Game Recap"

    static let description = IntentDescription(
        "Summarizes an archived game: innings, who pitched, and whether everyone met your fair play rules.",
        categoryName: "History",
        searchKeywords: ["recap", "game", "summary", "history", "pitch count", "fair play"]
    )

    /// Answers in place. Nothing here mutates anything.
    static let openAppWhenRun = false

    @Parameter(
        title: "Team",
        description: "Leave empty to use the team you're currently coaching."
    )
    var team: TeamEntity?

    @Parameter(
        title: "Game",
        description: "Leave empty for the most recent game."
    )
    var game: GameLogEntity?

    init() {}

    init(team: TeamEntity? = nil, game: GameLogEntity? = nil) {
        self.team = team
        self.game = game
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Recap \(\.$game) for \(\.$team)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        guard await PurchaseManager.isProNow() else {
            Analytics.signal("intent.game_recap.blocked_not_pro")
            throw STLIntentError.needsPro(feature: "Game recaps")
        }

        let (teams, activeTeam) = TeamStorage.loadTeamsForReading()

        // An explicitly named game wins outright — it already identifies its own
        // team, so a mismatched `team` parameter shouldn't override the coach.
        let resolved: (log: GameLog, team: Team)
        if let game {
            guard let owning = teams.first(where: { $0.id == game.teamID }),
                  let log = owning.gameLogs.first(where: { $0.id == game.id })
            else { throw STLIntentError.noSuchGame }
            resolved = (log, owning)
        } else {
            let target: Team?
            if let team {
                target = teams.first { $0.id == team.id }
            } else {
                target = activeTeam
            }
            guard let target else { throw STLIntentError.noTeam }
            resolved = (try await mostRecentGame(in: target), target)
        }

        let recap = GameRecapBuilder.build(log: resolved.log, team: resolved.team)

        Analytics.signal("intent.game_recap", parameters: [
            "inningsPlayed": "\(recap.inningsPlayed)",
            "pitcherCount": "\(recap.pitching.count)",
            "fairPlayClean": recap.isFairPlayClean ? "true" : "false"
        ])

        // `full` is what a voice-only surface says — the whole recap, since
        // there's no snippet to read there. `supporting` is what appears when
        // the snippet IS on screen, where restating every pitcher and issue
        // above the table prints each one twice and squeezes the table into
        // whatever height is left. See GameRecap.shortSummary.
        return .result(
            dialog: IntentDialog(
                full: LocalizedStringResource(stringLiteral: recap.spokenSummary),
                supporting: LocalizedStringResource(stringLiteral: recap.shortSummary)
            ),
            view: GameRecapSnippetView(recap: recap)
        )
    }

    /// The newest game, prompting when the newest *day* holds more than one.
    ///
    /// Doubleheaders are the case this exists for: two logs dated the same day
    /// against different opponents, where picking "the newest" by archive order
    /// is a coin flip the coach can't see. Anything less ambiguous answers
    /// straight away rather than making them tap.
    private func mostRecentGame(in team: Team) async throws -> GameLog {
        let sorted = team.gameLogs.sorted { $0.gameDate > $1.gameDate }
        guard let newest = sorted.first else {
            throw STLIntentError.noGames(teamName: TeamEntity(team).displayName)
        }

        let sameDay = sorted.filter {
            Calendar.current.isDate($0.gameDate, inSameDayAs: newest.gameDate)
        }
        guard sameDay.count > 1 else { return newest }

        let chosen = try await $game.requestDisambiguation(
            among: sameDay.map { GameLogEntity($0, team: team) },
            dialog: IntentDialog("You played \(sameDay.count) games that day. Which one?")
        )
        guard let log = team.gameLogs.first(where: { $0.id == chosen.id }) else {
            throw STLIntentError.noSuchGame
        }
        return log
    }
}

// MARK: - Snippet
//
// The spoken summary has to survive being heard once; this is the same
// information for a coach who is looking at the phone. It carries the full
// batting order, which the dialog deliberately omits — ten names read aloud is
// not an answer to anything.

struct GameRecapSnippetView: View {

    let recap: GameRecap

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if !recap.pitching.isEmpty {
                section("Pitching") {
                    ForEach(recap.pitching, id: \.playerID) { line in
                        row(line.name, detail: pitchingDetail(line))
                    }
                }
            }

            // Above the batting order on purpose, and the reverse of the spoken
            // order. A snippet has a fixed height and clips rather than scrolls,
            // so whatever sits last is what a long recap loses — and this is the
            // part the coach has to act on. Spoken, the same reasoning puts it
            // last: nothing gets cut off, and last is what people remember.
            fairPlay

            if !recap.battingOrder.isEmpty {
                section("Batting Order") {
                    // One flowing line, not a row per player: ten stacked rows
                    // pushed everything below them out of the snippet entirely.
                    Text(recap.numberedBattingOrder)
                        .font(.footnote)
                        .lineLimit(2)
                }
            }
        }
        .padding(16)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(recap.teamName.isEmpty ? "My Team" : recap.teamName)
                .font(.headline)
            Text(recap.headline)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var fairPlay: some View {
        if recap.isFairPlayClean {
            Label(
                recap.fieldingMinimumSkipped
                    ? "Nothing flagged — too short for the fielding minimum"
                    : "Everyone met your fair play rules",
                systemImage: "checkmark.circle.fill"
            )
            .font(.footnote.weight(.medium))
            .foregroundStyle(.green)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Label("Fair play", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.orange)
                // Every name within an issue, unlike the spoken summary — a
                // list you read at your own pace doesn't need capping. The
                // number of *issues* is capped, because the snippet's height is
                // whatever Spotlight has left after the dialog, and an
                // unbounded list silently pushes itself off the bottom.
                ForEach(Array(recap.fairPlayIssues.prefix(Self.issueLimit).enumerated()), id: \.offset) { _, issue in
                    Text(issue.sentence())
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if recap.fairPlayIssues.count > Self.issueLimit {
                    Text("+\(recap.fairPlayIssues.count - Self.issueLimit) more in the app")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    /// Fair-play issues rendered before deferring to the app.
    private static let issueLimit = 2

    @ViewBuilder
    private func section<Content: View>(_ title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func row(_ label: String, detail: String?) -> some View {
        HStack {
            Text(label)
                .font(.footnote)
            Spacer(minLength: 12)
            if let detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func pitchingDetail(_ line: RecapPitchingLine) -> String {
        guard let pitches = line.pitches else { return Plural.innings(line.innings) }
        return "\(Plural.innings(line.innings)) · \(pitches) P"
    }
}
