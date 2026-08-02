import Foundation

// MARK: - GameRecap
//
// "How did the Tigers do today?" — everything that answers that question,
// computed from one archived `GameLog`, with no UI and no store.
//
// Deliberately not a Foundation Models summarization. `GameLogInsightsService`
// already does season-level prose across many games, and that's the right shape
// for "what patterns do you see". A single-game recap is a set of facts the
// coach is going to repeat to a parent — who pitched, how many pitches, who
// came up short on innings — and a model paraphrasing those is a way to get
// them subtly wrong. Everything here is counted, not generated.

/// One fair-play rule that was broken, and who broke it.
///
/// Kept as names-plus-predicate rather than a finished sentence because the two
/// places it's rendered want different lengths: the snippet names everyone,
/// while the spoken summary caps the list. Hearing "Jake Rivera, Tyler Nguyen,
/// Drew Santos, Eli Park, Nate Coleman, and Leo Huang never played the outfield"
/// is not something a coach can hold onto — verified on a real 5-inning game.
nonisolated struct RecapIssue: Equatable {
    let names: [String]
    /// Agrees with both a singular and a plural subject: "never played the
    /// infield", "played fewer than 4 fielding innings".
    let predicate: String

    /// `limit` nil names everyone. Otherwise names that many and counts the rest.
    func sentence(namingAtMost limit: Int? = nil) -> String {
        guard let limit, names.count > limit, limit > 0 else {
            return "\(GameRecap.list(of: names)) \(predicate)."
        }
        let shown = Array(names.prefix(limit))
        let remaining = names.count - limit
        let others = remaining == 1 ? "1 other" : "\(remaining) others"
        return "\(GameRecap.list(of: shown + [others])) \(predicate)."
    }
}

/// One pitcher's line in a recap.
nonisolated struct RecapPitchingLine: Equatable {
    let playerID: UUID
    let name: String
    let innings: Int
    /// Pitches thrown, or nil when none were recorded. `pitchCounts` is optional
    /// per log — anything archived before v2.5 has none, and a coach can archive
    /// without entering them today. nil means "not recorded", never zero.
    let pitches: Int?
}

nonisolated struct GameRecap {
    let teamName: String
    let opponent: String
    let gameDate: Date
    let inningsPlayed: Int
    /// Batting order, resolved against the archived snapshot. Short names
    /// ("Jake R.") rather than full ones with jersey numbers: the only surface
    /// that renders this is height-constrained, and "1 #4 Jake Rivera" puts two
    /// unrelated numbers side by side.
    let battingOrder: [String]
    /// Pitchers in the order they first took the mound.
    let pitching: [RecapPitchingLine]
    /// One entry per rule that was broken. Empty when clean.
    let fairPlayIssues: [RecapIssue]
    /// True when the game was too short to judge against the fielding minimum,
    /// so the recap says the rule was skipped rather than flagging the roster.
    let fieldingMinimumSkipped: Bool

    var isFairPlayClean: Bool { fairPlayIssues.isEmpty }

    /// How many names a spoken issue lists before it starts counting. Three is
    /// about the length of a phrase someone can repeat back from memory.
    static let spokenNameLimit = 3

    /// "vs Rangers · 6 innings · Tuesday, Jul 28"
    var headline: String {
        let opponentPart = opponent.isEmpty ? "Game" : "vs \(opponent)"
        return "\(opponentPart) · \(Plural.innings(inningsPlayed)) · \(Self.datePhrase(gameDate))"
    }

    /// What Siri says. The coach may be driving, so this leads with the
    /// identifying facts and puts the fair-play verdict last — that's the part
    /// they'll act on, and last is what people remember from a spoken list.
    var spokenSummary: String {
        var parts: [String] = []

        let opponentPhrase = opponent.isEmpty ? "Your game" : "Your game against \(opponent)"
        parts.append("\(opponentPhrase) \(Self.dateVerbPhrase(gameDate)) went \(Plural.innings(inningsPlayed)).")

        if let pitchingSentence = pitchingSentence {
            parts.append(pitchingSentence)
        }

        if fieldingMinimumSkipped {
            parts.append("It was too short to judge against your \(fieldingMinimumSkippedNote).")
        }

        if fairPlayIssues.isEmpty {
            parts.append(fieldingMinimumSkipped
                ? "Nothing else was flagged."
                : "Everyone met your fair play rules.")
        } else {
            parts.append(
                fairPlayIssues
                    .map { $0.sentence(namingAtMost: Self.spokenNameLimit) }
                    .joined(separator: " ")
            )
        }

        return parts.joined(separator: " ")
    }

    /// What to say when the snippet is on screen next to it.
    ///
    /// Spotlight renders the dialog as a paragraph *above* the snippet, so
    /// speaking the full recap there prints every pitcher, pitch count and
    /// fair-play issue twice and pushes the table down under it. This names the
    /// game and lets the snippet carry the facts; `spokenSummary` stays the
    /// complete answer for the voice-only case, where there is nothing to read.
    ///
    /// It also buys back height: the snippet gets whatever is left after the
    /// dialog, which is what made a multi-issue recap clip partway through the
    /// fair-play block.
    var shortSummary: String {
        opponent.isEmpty
            ? "Your recap of the game \(Self.dateVerbPhrase(gameDate))."
            : "Your recap of the \(opponent) game."
    }

    private var fieldingMinimumSkippedNote: String {
        "fielding-innings minimum"
    }

    /// "1 Jake R. · 2 Connor W. · 3 Tyler N. …" — the whole order on one
    /// wrapping line, for surfaces with a height budget.
    var numberedBattingOrder: String {
        battingOrder
            .enumerated()
            .map { "\($0.offset + 1) \($0.element)" }
            .joined(separator: " · ")
    }

    /// "Jake Rivera pitched 2 innings on 34 pitches, and Nate Coleman pitched 2."
    var pitchingSentence: String? {
        guard !pitching.isEmpty else { return nil }

        let clauses = pitching.map { line -> String in
            if let pitches = line.pitches {
                return "\(line.name) pitched \(Plural.innings(line.innings)) on \(Plural.pitches(pitches))"
            }
            return "\(line.name) pitched \(Plural.innings(line.innings))"
        }

        return Self.sentence(joining: clauses)
    }

    // MARK: - Phrasing helpers

    /// Joins independent clauses and closes the sentence. Two clauses keep the
    /// comma before "and" because they're full statements — "Jake pitched 2
    /// innings, and Nate pitched 2."
    static func sentence(joining clauses: [String]) -> String {
        switch clauses.count {
        case 0: return ""
        case 1: return clauses[0] + "."
        case 2: return "\(clauses[0]), and \(clauses[1])."
        default:
            let head = clauses.dropLast().joined(separator: ", ")
            return "\(head), and \(clauses.last!)."
        }
    }

    /// Joins a list of names, mid-sentence and unpunctuated. Distinct from
    /// `sentence(joining:)`: two names take a bare "and" ("Leo and Cam never
    /// played the infield"), where two clauses take a comma. Spoken aloud the
    /// difference is a pause in the wrong place.
    static func list(of names: [String]) -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default:
            let head = names.dropLast().joined(separator: ", ")
            return "\(head), and \(names.last!)"
        }
    }

    /// "today" / "yesterday" / "Tuesday, Jul 28".
    static func datePhrase(_ date: Date, relativeTo now: Date = Date()) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return "today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) { return "yesterday" }

        let formatter = DateFormatter()
        // Within the last week a weekday name is how coaches actually refer to
        // a game ("Saturday's game"); older than that it stops being unambiguous.
        let daysAgo = calendar.dateComponents([.day],
                                              from: calendar.startOfDay(for: date),
                                              to: calendar.startOfDay(for: now)).day ?? 0
        formatter.dateFormat = (0...6).contains(daysAgo) ? "EEEE" : "EEEE, MMM d"
        return formatter.string(from: date)
    }

    /// Same, phrased to follow a subject: "…against the Rangers today went…".
    static func dateVerbPhrase(_ date: Date, relativeTo now: Date = Date()) -> String {
        let phrase = datePhrase(date, relativeTo: now)
        switch phrase {
        case "today", "yesterday": return phrase
        default: return "on \(phrase)"
        }
    }
}

// MARK: - Builder

nonisolated enum GameRecapBuilder {

    /// Composes a recap from an archived game.
    ///
    /// Two deliberate choices about *which* roster is used:
    ///
    /// 1. Players come from `log.playerSnapshot`, not the live roster. A recap
    ///    is a historical record — a coach who has since deleted a player still
    ///    wants to hear that they pitched. `SeasonStatsCalculator` filters by
    ///    the live roster for the opposite and equally correct reason: season
    ///    totals for someone no longer on the team are noise.
    ///
    /// 2. `absentPlayerIDs` on the synthetic lineup is left empty, even though
    ///    some players may carry `.absent` innings for a late arrival or early
    ///    departure. That matches what the app's own Fair Play rail does with a
    ///    live lineup: only `playersUnderFieldingMinimum` exempts them. Making
    ///    the recap kinder than the rail would be the recap being wrong.
    static func build(log: GameLog, team: Team, now: Date = Date()) -> GameRecap {
        let players = log.playerSnapshot.map {
            Player(id: $0.id, firstName: $0.firstName, lastName: $0.lastName, number: $0.number)
        }
        let byID = Dictionary(uniqueKeysWithValues: players.map { ($0.id, $0) })

        let lineup = Lineup(
            gameDate: log.gameDate,
            opponent: log.opponent,
            battingOrder: log.battingOrder,
            innings: log.playedInnings
        )

        let battingOrder = log.battingOrder.compactMap { byID[$0]?.shortName }

        // A game called after 3 innings can't be judged against a 4-inning
        // fielding minimum — every player would be "under", which is true and
        // useless. Report the rule as skipped instead.
        let config = team.fairPlayConfig
        let fieldingMinimumSkipped = config.minimumFieldingInnings > 0
            && log.inningsPlayed < config.minimumFieldingInnings

        var effectiveConfig = config
        if fieldingMinimumSkipped { effectiveConfig.minimumFieldingInnings = 0 }

        let findings = lineup.fairPlayFindings(players: players, config: effectiveConfig)

        return GameRecap(
            teamName: team.name,
            opponent: log.opponent,
            gameDate: log.gameDate,
            inningsPlayed: log.inningsPlayed,
            battingOrder: battingOrder,
            pitching: pitchingLines(log: log, players: byID),
            fairPlayIssues: issueSentences(findings),
            fieldingMinimumSkipped: fieldingMinimumSkipped
        )
    }

    /// Pitchers in the order they first took the mound, with innings counted
    /// only from the innings actually played.
    static func pitchingLines(log: GameLog, players: [UUID: Player]) -> [RecapPitchingLine] {
        var inningsByPitcher: [UUID: Int] = [:]
        var firstAppearance: [UUID: Int] = [:]

        for (index, inning) in log.playedInnings.enumerated() {
            for (playerID, position) in inning.assignments where position == .pitcher {
                inningsByPitcher[playerID, default: 0] += 1
                if firstAppearance[playerID] == nil { firstAppearance[playerID] = index }
            }
        }

        return inningsByPitcher.keys
            .sorted { (firstAppearance[$0] ?? 0, $0.uuidString) < (firstAppearance[$1] ?? 0, $1.uuidString) }
            .map { playerID in
                RecapPitchingLine(
                    playerID: playerID,
                    name: players[playerID]?.displayName ?? "A player",
                    innings: inningsByPitcher[playerID] ?? 0,
                    pitches: log.pitchCounts[playerID.uuidString]
                )
            }
    }

    /// Turns findings into issues a coach can hear once and act on. One entry
    /// per rule, naming the players — a bare count ("3 fair play issues") is the
    /// thing they'd have to open the app to decode.
    ///
    /// Ordered by how much it costs a kid: innings on the field first, then
    /// where those innings were, then the seating and battery rules.
    static func issueSentences(_ findings: FairPlayFindings) -> [RecapIssue] {
        var issues: [RecapIssue] = []

        func add(_ players: [Player], _ predicate: String) {
            guard !players.isEmpty else { return }
            issues.append(RecapIssue(names: players.map(\.displayName), predicate: predicate))
        }

        add(findings.underFieldingMinimum,
            "played fewer than \(findings.minimumFieldingInnings) fielding \(Plural.inningNoun(findings.minimumFieldingInnings))")
        add(findings.withoutInfield, "never played the infield")
        add(findings.withoutOutfield, "never played the outfield")
        add(findings.backToBackBench, "sat two innings in a row")
        add(findings.catcherThenPitcher, "caught and then pitched")
        add(findings.pitcherThenCatcher, "pitched and then caught")

        return issues
    }
}
