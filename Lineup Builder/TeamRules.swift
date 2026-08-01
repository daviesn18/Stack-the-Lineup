import Foundation

// MARK: - TeamRules
//
// "How many innings do I need to play someone in the infield?"
// "If Bobby throws 33 pitches, how many days rest does he need?"
//
// Everything that answers a rules question, read off one Team's own
// FairPlayConfig and PitchingConfig, with no UI and no store.
//
// Every number here is READ, never generated. These are pitch counts and rest
// days that exist to protect kids' arms, and a wrong one spoken in Siri's voice
// is materially worse than "I don't have that rule" — so when a rule is off, or
// a league age is missing, the answer says exactly that instead of filling the
// gap with a plausible default.
//
// Deliberately not keyed to a governing body. `LeagueRuleset` exists on
// FairPlayConfig but is documented as informational: it stores the coach's
// selection and applies no presets. The only rule table in the app is the
// Little League pitch-count preset, and that is seeded *into* a team's own
// PitchingConfig, where the coach can then edit every value. So "what does Cal
// Ripken say" has nothing to read, while "what did I set for my team" always
// does — and the second is the question a coach actually has at the fence,
// because those are the rules this app will hold their lineup to tonight.

// MARK: - Topic

/// What the coach asked about. One case per question the stored config can
/// answer without guessing.
nonisolated enum RuleTopic: String, CaseIterable, Sendable {
    /// Every rule that's switched on, at a glance.
    case overview
    case fieldingMinimum
    case infieldMinimum
    case outfieldMinimum
    case benchRules
    case positionRules
    case batteryRules
    /// How many pitches someone can throw in a game.
    case pitchLimit
    /// How much rest a given pitch count buys.
    case restDays

    var title: String {
        switch self {
        case .overview:        return "Team Rules"
        case .fieldingMinimum: return "Fielding Minimum"
        case .infieldMinimum:  return "Infield Minimum"
        case .outfieldMinimum: return "Outfield Minimum"
        case .benchRules:      return "Bench Rules"
        case .positionRules:   return "Position Rules"
        case .batteryRules:    return "Catching and Pitching"
        case .pitchLimit:      return "Pitch Limits"
        case .restDays:        return "Rest Days"
        }
    }

    /// Names what's on screen without restating it. Pairs with the snippet's
    /// table, which is carrying the actual values.
    var shortLead: String {
        switch self {
        case .overview:        return "Your rules"
        case .fieldingMinimum: return "Your fielding minimum"
        case .infieldMinimum:  return "Your infield minimum"
        case .outfieldMinimum: return "Your outfield minimum"
        case .benchRules:      return "Your bench rules"
        case .positionRules:   return "Your position rules"
        case .batteryRules:    return "Your catching and pitching rules"
        case .pitchLimit:      return "Your pitch limits"
        case .restDays:        return "Your rest day thresholds"
        }
    }

    /// True for the two topics that read PitchingConfig rather than FairPlayConfig.
    var isPitching: Bool {
        switch self {
        case .pitchLimit, .restDays: return true
        default:                     return false
        }
    }
}

// MARK: - Rule Line

/// One rule in the two shapes an answer needs.
///
/// Split for the same reason `RecapIssue` is: the snippet renders a scannable
/// label/value pair, while the dialog has to be a sentence a coach can hear
/// once and act on. "Infield minimum / 1 inning" is unreadable spoken, and
/// "Everyone active needs at least 1 inning in the infield." is a wasteful row
/// in a box that clips.
nonisolated struct RuleLine: Equatable {
    let label: String
    /// Short enough for a right-aligned column — "1 inning", "85 pitches", "Off".
    let value: String
    /// A complete sentence, safe to read aloud on its own.
    let spoken: String
}

// MARK: - Answer

nonisolated struct TeamRulesAnswer: Equatable {
    let teamName: String
    let topic: RuleTopic
    let lines: [RuleLine]
    /// Set when the config can't produce the number the coach asked for —
    /// pitching rules switched off, no league age on file, limits never entered.
    /// Always phrased as something the coach can go fix, because that *is* the
    /// answer in those cases. Never a substitute number.
    let caveat: String?

    var headline: String { topic.title }

    /// True when nothing could be quoted and the caveat is carrying the answer.
    var isDeferred: Bool { lines.isEmpty && caveat != nil }

    /// What Siri says. The caveat lands last on purpose: when there is one it's
    /// the part the coach has to act on, and last is what people remember from
    /// something they heard rather than read.
    var spokenSummary: String {
        var sentences = lines.map(\.spoken)
        if let caveat { sentences.append(caveat) }
        guard !sentences.isEmpty else {
            return "I don't have any rules set for \(teamNameForSpeech)."
        }
        return sentences.joined(separator: " ")
    }

    /// What to say when the snippet is on screen next to it.
    ///
    /// Spotlight renders the dialog as a block of text *above* the table, so
    /// speaking every value there prints each one twice and buries the table
    /// under a paragraph. This names what's being shown and lets the table
    /// carry the numbers; `spokenSummary` stays the complete answer for the
    /// voice-only case, where there is no table to read.
    var shortSummary: String {
        if lines.isEmpty, let caveat { return caveat }
        return "\(topic.shortLead) for \(teamNameForSpeech)."
    }

    private var teamNameForSpeech: String {
        teamName.isEmpty ? "your team" : teamName
    }
}

// MARK: - Builder

nonisolated enum TeamRulesBuilder {

    /// Composes the answer to one rules question.
    ///
    /// `player` is what makes a pitching answer specific — the age bracket comes
    /// from their `leagueAge`, and there is no roster-wide default to fall back
    /// on. `pitchCount` turns the rest-day ladder into a single answer.
    static func answer(
        topic: RuleTopic,
        team: Team,
        player: Player? = nil,
        pitchCount: Int? = nil
    ) -> TeamRulesAnswer {
        let fair = team.fairPlayConfig
        let pitching = team.pitchingConfig

        switch topic {
        case .overview:
            return overview(team: team)

        case .fieldingMinimum:
            return answer(topic: topic, team: team, lines: [fieldingMinimumLine(fair)])

        case .infieldMinimum:
            return answer(topic: topic, team: team, lines: [infieldMinimumLine(fair)])

        case .outfieldMinimum:
            return answer(topic: topic, team: team, lines: [outfieldMinimumLine(fair)])

        case .benchRules:
            return answer(topic: topic, team: team, lines: benchLines(fair))

        case .positionRules:
            return answer(topic: topic, team: team, lines: positionLines(fair))

        case .batteryRules:
            return answer(topic: topic, team: team, lines: batteryLines(fair))

        case .pitchLimit:
            return pitchLimitAnswer(team: team, config: pitching, player: player)

        case .restDays:
            return restDaysAnswer(team: team, config: pitching,
                                  player: player, pitchCount: pitchCount)
        }
    }

    private static func answer(topic: RuleTopic, team: Team,
                               lines: [RuleLine], caveat: String? = nil) -> TeamRulesAnswer {
        TeamRulesAnswer(teamName: team.name, topic: topic, lines: lines, caveat: caveat)
    }

    // MARK: Fair play lines
    //
    // The "is this rule on" test in each of these matches `fairPlayFindings`
    // exactly — `> 0` for the minimums, the flag for bench, `> 0` for the two
    // battery thresholds. That agreement is the whole point: an answer that
    // says a rule is on while the Fair Play rail declines to enforce it is
    // worse than no answer.

    private static func fieldingMinimumLine(_ config: FairPlayConfig) -> RuleLine {
        let minimum = config.minimumFieldingInnings
        guard minimum > 0 else {
            return RuleLine(
                label: "Fielding minimum",
                value: "Off",
                spoken: "You don't have a fielding minimum turned on, so no one has to play a set number of innings."
            )
        }
        return RuleLine(
            label: "Fielding minimum",
            value: innings(minimum),
            spoken: "Everyone active has to field at least \(innings(minimum))."
        )
    }

    private static func infieldMinimumLine(_ config: FairPlayConfig) -> RuleLine {
        let minimum = config.minimumInfieldInnings
        guard minimum > 0 else {
            return RuleLine(
                label: "Infield minimum",
                value: "Off",
                spoken: "You don't have an infield minimum turned on, so no one is required to play the infield."
            )
        }
        return RuleLine(
            label: "Infield minimum",
            value: innings(minimum),
            spoken: "Everyone active needs at least \(innings(minimum)) in the infield."
        )
    }

    private static func outfieldMinimumLine(_ config: FairPlayConfig) -> RuleLine {
        let minimum = config.minimumOutfieldInnings
        guard minimum > 0 else {
            return RuleLine(
                label: "Outfield minimum",
                value: "Off",
                spoken: "You don't have an outfield minimum turned on, so no one is required to play the outfield."
            )
        }
        return RuleLine(
            label: "Outfield minimum",
            value: innings(minimum),
            spoken: "Everyone active needs at least \(innings(minimum)) in the outfield."
        )
    }

    private static func benchLines(_ config: FairPlayConfig) -> [RuleLine] {
        [
            RuleLine(
                label: "Back-to-back bench",
                value: config.noConsecutiveBench ? "Not allowed" : "Allowed",
                spoken: config.noConsecutiveBench
                    ? "No one can sit on the bench two innings in a row."
                    : "Sitting two innings in a row is allowed — that rule is off."
            ),
            RuleLine(
                label: "Equal bench time",
                value: config.equalBenchTime ? "On" : "Off",
                spoken: config.equalBenchTime
                    ? "No one sits a second time until everyone has sat once."
                    : "Equal bench time is off."
            )
        ]
    }

    private static func positionLines(_ config: FairPlayConfig) -> [RuleLine] {
        var lines: [RuleLine] = [
            RuleLine(
                label: "Outfielders",
                value: "\(config.outfielderCount)",
                spoken: config.outfielderCount == 4
                    ? "You play 4 outfielders, with left center and right center instead of center field."
                    : "You play \(config.outfielderCount) outfielders."
            )
        ]

        if config.noPitcher {
            lines.append(RuleLine(
                label: "Pitcher",
                value: "Not used",
                spoken: "You don't use a pitcher position, so it's off the grid entirely."
            ))
        }
        if config.noCatcher {
            lines.append(RuleLine(
                label: "Catcher",
                value: "Not used",
                spoken: "You don't use a catcher position, so it's off the grid entirely."
            ))
        }

        lines.append(RuleLine(
            label: "Same position twice in a row",
            value: config.noConsecutivePosition ? "Not allowed" : "Allowed",
            spoken: config.noConsecutivePosition
                ? "No one plays the same position two innings in a row."
                : "Playing the same position two innings in a row is allowed."
        ))

        if config.noRepeatPositions {
            lines.append(RuleLine(
                label: "Vary positions",
                value: "On",
                spoken: "Auto-Fill tries to give everyone a different position every inning."
            ))
        }

        return lines
    }

    private static func batteryLines(_ config: FairPlayConfig) -> [RuleLine] {
        [
            RuleLine(
                label: "Caught, then pitched",
                value: config.catcherToPitcherThreshold > 0
                    ? innings(config.catcherToPitcherThreshold) : "Off",
                spoken: config.catcherToPitcherThreshold > 0
                    ? "Once someone has caught \(innings(config.catcherToPitcherThreshold)), they can't pitch."
                    : "You don't have a rule against catching and then pitching."
            ),
            RuleLine(
                label: "Pitched, then caught",
                value: config.pitcherToCatcherThreshold > 0
                    ? innings(config.pitcherToCatcherThreshold) : "Off",
                spoken: config.pitcherToCatcherThreshold > 0
                    ? "Once someone has pitched \(innings(config.pitcherToCatcherThreshold)), they can't catch."
                    : "You don't have a rule against pitching and then catching."
            )
        ]
    }

    // MARK: Overview
    //
    // Only what's switched ON. A coach asking "what are my rules" wants the
    // list they have to coach to, not an inventory of everything they declined.
    // It also keeps the answer inside what a snippet can show and a person can
    // hold onto — the off-rules are all still one specific question away.

    private static func overview(team: Team) -> TeamRulesAnswer {
        let fair = team.fairPlayConfig
        var lines: [RuleLine] = []

        if fair.minimumFieldingInnings > 0 { lines.append(fieldingMinimumLine(fair)) }
        if fair.minimumInfieldInnings  > 0 { lines.append(infieldMinimumLine(fair)) }
        if fair.minimumOutfieldInnings > 0 { lines.append(outfieldMinimumLine(fair)) }
        if fair.noConsecutiveBench {
            lines.append(benchLines(fair)[0])
        }
        if fair.equalBenchTime {
            lines.append(benchLines(fair)[1])
        }
        if fair.noConsecutivePosition {
            lines.append(RuleLine(
                label: "Same position twice in a row",
                value: "Not allowed",
                spoken: "No one plays the same position two innings in a row."
            ))
        }
        if fair.catcherToPitcherThreshold > 0 { lines.append(batteryLines(fair)[0]) }
        if fair.pitcherToCatcherThreshold > 0 { lines.append(batteryLines(fair)[1]) }

        // One line, not the whole bracket table — the table is what asking about
        // pitch limits directly is for.
        if team.pitchingConfig.rulesEnabled {
            lines.append(RuleLine(
                label: "Pitching rules",
                value: "On",
                spoken: "Pitch counts and rest days are switched on. Ask about pitch limits for the numbers."
            ))
        }

        guard !lines.isEmpty else {
            return TeamRulesAnswer(
                teamName: team.name,
                topic: .overview,
                lines: [],
                caveat: "You haven't switched on any fair play rules for \(spokenTeamName(team)) yet. You can set them up in Fair Play Rules."
            )
        }

        return TeamRulesAnswer(teamName: team.name, topic: .overview, lines: lines, caveat: nil)
    }

    // MARK: Pitching

    private static func pitchLimitAnswer(team: Team,
                                         config: PitchingConfig,
                                         player: Player?) -> TeamRulesAnswer {
        guard config.rulesEnabled else {
            return disabledPitchingAnswer(topic: .pitchLimit, team: team)
        }

        let resolved = resolveBrackets(team: team, config: config, player: player)
        guard !resolved.brackets.isEmpty else {
            return TeamRulesAnswer(teamName: team.name, topic: .pitchLimit,
                                   lines: [], caveat: resolved.caveat)
        }

        var lines = grouped(resolved.brackets, by: { $0.limits.dailyMax }).map { group -> RuleLine in
            let maximum = group[0].limits.dailyMax
            let spoken: String
            if let player, resolved.brackets.count == 1 {
                spoken = "\(player.firstName) can throw up to \(pitches(maximum)) in a game, your limit for \(spokenRange(of: group)) year olds."
            } else {
                spoken = "\(spokenRange(of: group)) year olds can throw up to \(pitches(maximum)) in a game."
            }
            return RuleLine(label: "Ages \(rangeLabel(of: group))",
                            value: pitches(maximum),
                            spoken: spoken)
        }

        if config.weeklyLimitEnabled, config.weeklyLimit > 0 {
            let window = config.rollingWindowType == .calendarWeek
                ? "per calendar week"
                : "per rolling \(config.rollingWindowDays) days"
            lines.append(RuleLine(
                label: "Cap \(window)",
                value: pitches(config.weeklyLimit),
                spoken: "There's also a cap of \(pitches(config.weeklyLimit)) \(window)."
            ))
        }

        return TeamRulesAnswer(teamName: team.name, topic: .pitchLimit,
                               lines: lines, caveat: resolved.caveat)
    }

    private static func restDaysAnswer(team: Team,
                                       config: PitchingConfig,
                                       player: Player?,
                                       pitchCount: Int?) -> TeamRulesAnswer {
        guard config.rulesEnabled else {
            return disabledPitchingAnswer(topic: .restDays, team: team)
        }

        let resolved = resolveBrackets(team: team, config: config, player: player)
        guard !resolved.brackets.isEmpty else {
            return TeamRulesAnswer(teamName: team.name, topic: .restDays,
                                   lines: [], caveat: resolved.caveat)
        }

        // A count of zero or less isn't a question about rest — fall through to
        // the ladder, which is the honest answer to "what are the rest rules".
        guard let count = pitchCount, count > 0 else {
            let lines = grouped(resolved.brackets, by: { ladderSignature($0) })
                .map { ladderLine(for: $0) }
            return TeamRulesAnswer(teamName: team.name, topic: .restDays,
                                   lines: lines, caveat: resolved.caveat)
        }

        let lines = grouped(resolved.brackets,
                            by: { [$0.limits.restDaysRequired(for: count), $0.limits.dailyMax] })
            .map { group -> RuleLine in
                let entry = group[0]
                let days = entry.limits.restDaysRequired(for: count)
                let subject: String
                if let player, resolved.brackets.count == 1 {
                    subject = "\(player.firstName) needs \(restPhrase(days))"
                } else {
                    subject = "\(spokenRange(of: group)) year olds need \(restPhrase(days))"
                }

                var spoken = "At \(pitches(count)), \(subject)."
                // Worth saying unprompted: a coach planning 90 pitches for an
                // 11-year-old has a bigger problem than when the kid pitches next.
                if count > entry.limits.dailyMax {
                    spoken += " That's also over your \(entry.limits.dailyMax)-pitch game limit for \(spokenRange(of: group)) year olds."
                }

                return RuleLine(
                    label: resolved.brackets.count == 1 ? "\(count) pitches" : "Ages \(rangeLabel(of: group))",
                    value: days == 0 ? "No rest" : days == 1 ? "1 day" : "\(days) days",
                    spoken: spoken
                )
            }

        return TeamRulesAnswer(teamName: team.name, topic: .restDays,
                               lines: lines, caveat: resolved.caveat)
    }

    /// The tiers a bracket actually has set, skipping the ones left unset.
    /// nil or 0 means the tier doesn't apply — not that it triggers at zero.
    private static func ladderSignature(_ entry: BracketLimits) -> [Int] {
        let tiers = [entry.limits.restDay1Min, entry.limits.restDay2Min,
                     entry.limits.restDay3Min, entry.limits.restDay4Min]
        return tiers.enumerated().compactMap { index, minimum in
            guard let minimum, minimum > 0 else { return nil }
            return (index + 1) * 1000 + minimum
        }
    }

    /// The full rest ladder for one group of brackets that share it.
    private static func ladderLine(for group: [BracketLimits]) -> RuleLine {
        let entry = group[0]
        let tiers: [(days: Int, minimum: Int?)] = [
            (1, entry.limits.restDay1Min),
            (2, entry.limits.restDay2Min),
            (3, entry.limits.restDay3Min),
            (4, entry.limits.restDay4Min)
        ]

        let active = tiers.compactMap { tier -> (days: Int, minimum: Int)? in
            guard let minimum = tier.minimum, minimum > 0 else { return nil }
            return (tier.days, minimum)
        }

        guard !active.isEmpty else {
            return RuleLine(
                label: "Ages \(rangeLabel(of: group))",
                value: "No rest tiers",
                spoken: "You haven't set any rest day thresholds for \(spokenRange(of: group)) year olds."
            )
        }

        let clauses = active.map { tier in
            "\(tier.minimum) or more needs \(restPhrase(tier.days))"
        }

        return RuleLine(
            label: "Ages \(rangeLabel(of: group))",
            value: active.map { "\($0.minimum)+ → \($0.days)d" }.joined(separator: ", "),
            spoken: "For \(spokenRange(of: group)) year olds, \(GameRecap.list(of: clauses))."
        )
    }

    // MARK: Bracket grouping
    //
    // Found by listening to the result, not by reading the code. A roster
    // spanning 9-10, 11-12 and 13-14 shares one rest ladder under the Little
    // League preset, and spelling it out per bracket spoke the same four
    // thresholds three times — about ninety words of near-identical text, which
    // is nothing a coach can hold onto. Adjacent brackets whose answer would be
    // word-for-word identical collapse into a single "9 to 14 year olds" line.

    /// Runs of adjacent brackets whose answer is identical. Input must be in
    /// `allCases` order, which `resolveBrackets` guarantees — only *adjacent*
    /// brackets merge, so a collapsed label never spans a bracket in between
    /// that has a different rule.
    private static func grouped<Key: Equatable>(
        _ brackets: [BracketLimits],
        by key: (BracketLimits) -> Key
    ) -> [[BracketLimits]] {
        var groups: [[BracketLimits]] = []
        for entry in brackets {
            if let last = groups.last?.last, key(last) == key(entry) {
                groups[groups.count - 1].append(entry)
            } else {
                groups.append([entry])
            }
        }
        return groups
    }

    /// "9-10" for one bracket, "9-14" for a merged run.
    private static func rangeLabel(of group: [BracketLimits]) -> String {
        guard let first = group.first, let last = group.last, group.count > 1 else {
            return group.first?.bracket.displayName ?? ""
        }
        return "\(first.bracket.lowAge)-\(last.bracket.highAge)"
    }

    /// The same, said out loud.
    private static func spokenRange(of group: [BracketLimits]) -> String {
        guard let first = group.first, let last = group.last, group.count > 1 else {
            return group.first?.bracket.spokenRange ?? ""
        }
        return "\(first.bracket.lowAge) to \(last.bracket.highAge)"
    }

    private static func disabledPitchingAnswer(topic: RuleTopic, team: Team) -> TeamRulesAnswer {
        // No numbers, deliberately. The Little League preset is sitting right
        // there in PitchingConfig, and quoting it to a coach who never switched
        // pitching rules on would be inventing their rules for them.
        TeamRulesAnswer(
            teamName: team.name,
            topic: topic,
            lines: [],
            caveat: "Pitching rules are turned off for \(spokenTeamName(team)), so I don't have any pitch limits to quote. You can switch them on in Pitching Rules."
        )
    }

    // MARK: Bracket resolution

    /// Not Equatable — `PitchingLimits` isn't, and nothing needs to compare two.
    struct BracketLimits {
        let bracket: PitchingAgeBracket
        let limits: PitchingLimits
    }

    /// Which age brackets an answer should cover, and why it might cover none.
    ///
    /// A named player pins it to exactly one bracket. Without one, the answer
    /// covers every bracket actually represented on the roster — a coach with
    /// 9-to-12s gets both rows rather than one arbitrarily chosen row.
    static func resolveBrackets(team: Team,
                                config: PitchingConfig,
                                player: Player?) -> (brackets: [BracketLimits], caveat: String?) {
        if let player {
            guard let age = player.leagueAge else {
                return ([], "I don't have a league age for \(player.firstName), so I can't tell which pitch limits apply. You can add it on their player page.")
            }
            guard let bracket = PitchingAgeBracket.bracket(for: age) else {
                return ([], "\(player.firstName)'s league age is \(age), which is outside the age groups the app carries pitch limits for.")
            }
            guard let limits = config.ageLimits[bracket] else {
                return ([], "You haven't set pitch limits for \(bracket.spokenRange) year olds yet. You can add them in Pitching Rules.")
            }
            return ([BracketLimits(bracket: bracket, limits: limits)], nil)
        }

        let onRoster = Set(team.players.compactMap { $0.leagueAge }
            .compactMap { PitchingAgeBracket.bracket(for: $0) })

        guard !onRoster.isEmpty else {
            return ([], "No one on \(spokenTeamName(team)) has a league age set, so I can't tell which pitch limits apply. You can add ages on each player's page.")
        }

        // allCases order, so brackets read youngest first rather than in Set order.
        let resolved = PitchingAgeBracket.allCases
            .filter { onRoster.contains($0) }
            .compactMap { bracket -> BracketLimits? in
                guard let limits = config.ageLimits[bracket] else { return nil }
                return BracketLimits(bracket: bracket, limits: limits)
            }

        guard !resolved.isEmpty else {
            return ([], "You haven't set pitch limits for the age groups on \(spokenTeamName(team)) yet. You can add them in Pitching Rules.")
        }

        // Some brackets on the roster have no limits entered. Say so — silently
        // answering for only the configured ones would read as a complete answer.
        let missing = PitchingAgeBracket.allCases
            .filter { onRoster.contains($0) && config.ageLimits[$0] == nil }
        let caveat = missing.isEmpty ? nil
            : "You don't have pitch limits set for \(GameRecap.list(of: missing.map { "\($0.spokenRange) year olds" })) yet."

        return (resolved, caveat)
    }

    // MARK: Phrasing

    private static func innings(_ count: Int) -> String {
        count == 1 ? "1 inning" : "\(count) innings"
    }

    private static func pitches(_ count: Int) -> String {
        count == 1 ? "1 pitch" : "\(count) pitches"
    }

    private static func restPhrase(_ days: Int) -> String {
        switch days {
        case 0:  return "no rest days"
        case 1:  return "1 day of rest"
        default: return "\(days) days of rest"
        }
    }

    private static func spokenTeamName(_ team: Team) -> String {
        team.name.isEmpty ? "your team" : team.name
    }
}

// MARK: - Spoken age ranges

extension PitchingAgeBracket {
    /// "11 to 12". `displayName` is "11-12", which speech synthesis reads as a
    /// hyphen or a subtraction rather than a range.
    nonisolated var spokenRange: String {
        displayName.replacingOccurrences(of: "-", with: " to ")
    }

    /// "9" and "10" out of "9-10", so adjacent brackets can merge into one range.
    nonisolated var lowAge: String {
        displayName.split(separator: "-").first.map(String.init) ?? displayName
    }

    nonisolated var highAge: String {
        displayName.split(separator: "-").last.map(String.init) ?? displayName
    }
}
