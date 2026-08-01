import Foundation

// MARK: - PitchEligibility
//
// "Can Bobby pitch on Saturday?" — the spoken face of `PitchEligibilityEngine`.
//
// Same discipline as TeamRules.swift: every number is read, and when the app
// can't actually answer, it says so instead of guessing. That matters more here
// than anywhere else in the app, because the wrong answer is a kid pitching on
// short rest.
//
// THE TRAP THIS TYPE EXISTS FOR: `PitchEligibilityEngine.status(for:...)`
// returns `.eligible` for three different situations —
//
//   1. genuinely clear (rest days elapsed, under any cap)
//   2. `config.rulesEnabled == false`      → nothing was checked
//   3. no `ageLimits` entry for their bracket → nothing was checked
//
// For a roster badge that conflation is harmless: no rules configured, no
// warning to show. Spoken aloud it is not, because all three come out as
// "Yes, Bobby can pitch" — a sentence that sounds like the app checked when in
// two of the three cases it didn't. `Verdict` splits them apart, and the
// builder decides which one applies *before* consulting the engine rather than
// trying to read it back out of an `.eligible`.

/// Why the app can't answer, phrased as something the coach can go fix.
nonisolated enum EligibilityNotTracked: Equatable {
    case rulesOff
    case noLeagueAge
    case ageOutOfRange(Int)
    case noLimitsForBracket(PitchingAgeBracket)
}

nonisolated enum EligibilityVerdict: Equatable {
    /// Clear to pitch. `maxPitches` is the daily maximum for their bracket.
    case clear(maxPitches: Int)
    /// Can pitch, but a cap leaves fewer than a full outing.
    case limited(remaining: Int)
    /// Must rest. `until` is the first date they may pitch again.
    case blocked(until: Date)
    /// The app has nothing to check against. Never phrased as a yes or a no.
    case notTracked(EligibilityNotTracked)

    /// True only for a verdict the app actually computed.
    var isAnswered: Bool {
        if case .notTracked = self { return false }
        return true
    }
}

/// One pitcher's last recorded outing, which is what a rest verdict is derived
/// from. Carried so a "no" can say why rather than just asserting itself.
nonisolated struct EligibilityOuting: Equatable {
    let date: Date
    let pitches: Int
}

nonisolated struct PitchEligibilityAnswer: Equatable {
    let playerFirstName: String
    let playerDisplayName: String
    let teamName: String
    /// The day being asked about. Today unless the coach named one.
    let askedAbout: Date
    let verdict: EligibilityVerdict
    /// Their most recent outing before `askedAbout`, if any pitches were recorded.
    let lastOuting: EligibilityOuting?

    var headline: String { "Can \(playerFirstName) pitch?" }

    /// The one-word answer, for the snippet's value column.
    var shortVerdict: String {
        switch verdict {
        case .clear:            return "Yes"
        case .limited:          return "Yes, limited"
        case .blocked:          return "Not yet"
        case .notTracked:       return "Not tracked"
        }
    }

    /// What Siri says. Leads with the yes or no — a coach asking this is
    /// standing somewhere deciding, and the qualifier is no use before the
    /// verdict it qualifies.
    var spokenSummary: String {
        switch verdict {
        case .notTracked(let reason):
            return notTrackedSentence(reason)

        case .clear(let maxPitches):
            var sentence = "Yes, \(playerFirstName) can pitch \(Self.dayPhrase(askedAbout))"
            sentence += ", up to \(maxPitches) pitches."
            if let lastOuting {
                sentence += " \(lastOutingSentence(lastOuting))"
            }
            return sentence

        case .limited(let remaining):
            let pitchNoun = remaining == 1 ? "pitch" : "pitches"
            var sentence = "Yes, but only \(remaining) more \(pitchNoun) — "
            sentence += "\(playerFirstName) is close to your cap."
            if let lastOuting {
                sentence += " \(lastOutingSentence(lastOuting))"
            }
            return sentence

        case .blocked(let until):
            var sentence = "No. \(playerFirstName) is resting until \(Self.dayPhrase(until))"
            if let lastOuting {
                let pitchNoun = lastOuting.pitches == 1 ? "pitch" : "pitches"
                sentence += ", after \(lastOuting.pitches) \(pitchNoun) \(Self.dayPhrase(lastOuting.date))."
            } else {
                sentence += "."
            }
            return sentence
        }
    }

    /// One short line for surfaces that render the snippet next to it, so the
    /// verdict isn't printed twice. See GameRecap.shortSummary.
    var shortSummary: String {
        switch verdict {
        case .notTracked:
            return spokenSummary
        case .clear:
            return "Yes — \(playerFirstName) is clear to pitch."
        case .limited:
            return "\(playerFirstName) can pitch, with a limit."
        case .blocked:
            return "Not yet — \(playerFirstName) is still resting."
        }
    }

    private func lastOutingSentence(_ outing: EligibilityOuting) -> String {
        let pitchNoun = outing.pitches == 1 ? "pitch" : "pitches"
        return "They last threw \(outing.pitches) \(pitchNoun) \(Self.dayPhrase(outing.date))."
    }

    private func notTrackedSentence(_ reason: EligibilityNotTracked) -> String {
        // Deliberately never "yes" or "no". The app checked nothing in these
        // states, and a coach who hears a verdict will act on it.
        switch reason {
        case .rulesOff:
            let team = teamName.isEmpty ? "your team" : teamName
            return "I'm not tracking pitch counts for \(team), so I can't tell you whether \(playerFirstName) is rested. You can switch on Pitching Rules to start."
        case .noLeagueAge:
            return "I don't have a league age for \(playerFirstName), so I can't tell which pitch limits apply. You can add it on their player page."
        case .ageOutOfRange(let age):
            return "\(playerFirstName)'s league age is \(age), which is outside the age groups the app carries pitch limits for."
        case .noLimitsForBracket(let bracket):
            return "You haven't set pitch limits for \(bracket.spokenRange) year olds yet, so I can't tell whether \(playerFirstName) is rested. You can add them in Pitching Rules."
        }
    }

    // MARK: Phrasing

    /// "today" / "tomorrow" / "yesterday" / "Saturday" / "Saturday, Aug 8".
    ///
    /// `GameRecap.datePhrase` only looks backwards — a recap is always of a game
    /// already played. This one has to face both ways, because the question is
    /// usually about an upcoming game and the answer cites a past outing.
    static func dayPhrase(_ date: Date, relativeTo now: Date = Date()) -> String {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: now)
        let offset = calendar.dateComponents([.day], from: today, to: day).day ?? 0

        switch offset {
        case 0:  return "today"
        case 1:  return "tomorrow"
        case -1: return "yesterday"
        default: break
        }

        let formatter = DateFormatter()
        // A bare weekday is only unambiguous within a week either way; past that
        // "Saturday" could mean four different Saturdays.
        formatter.dateFormat = (-6...6).contains(offset) ? "EEEE" : "EEEE, MMM d"
        return formatter.string(from: date)
    }
}

// MARK: - Builder

nonisolated enum PitchEligibilityAnswerBuilder {

    /// Answers whether `player` may pitch on `date`.
    ///
    /// The three `notTracked` checks run here, ahead of the engine, because the
    /// engine folds all of them into `.eligible` — see the note at the top of
    /// this file.
    static func answer(
        player: Player,
        team: Team,
        on date: Date = Date()
    ) -> PitchEligibilityAnswer {
        let config = team.pitchingConfig

        let verdict = self.verdict(player: player, team: team, config: config, on: date)

        return PitchEligibilityAnswer(
            playerFirstName: player.firstName,
            playerDisplayName: player.displayNameWithNumber,
            teamName: team.name,
            askedAbout: date,
            verdict: verdict,
            // Only attached to a verdict the app actually computed. Reciting a
            // pitch count under "I'm not tracking pitch counts" contradicts it.
            lastOuting: verdict.isAnswered ? lastOuting(for: player, in: team, before: date) : nil
        )
    }

    private static func verdict(
        player: Player,
        team: Team,
        config: PitchingConfig,
        on date: Date
    ) -> EligibilityVerdict {
        guard config.rulesEnabled else { return .notTracked(.rulesOff) }
        guard let age = player.leagueAge else { return .notTracked(.noLeagueAge) }
        guard let bracket = PitchingAgeBracket.bracket(for: age) else {
            return .notTracked(.ageOutOfRange(age))
        }
        guard let limits = config.ageLimits[bracket] else {
            return .notTracked(.noLimitsForBracket(bracket))
        }

        let status = PitchEligibilityEngine.status(
            for: player,
            gameLogs: team.gameLogs,
            config: config,
            referenceDate: date
        )

        switch status {
        case .eligible:
            return .clear(maxPitches: limits.dailyMax)
        case .limited(let remaining):
            return .limited(remaining: remaining)
        case .mustRest(let until):
            return .blocked(until: until)
        case .unknownAge:
            // Unreachable — the league age was checked above. Mapped rather
            // than defaulted to `.clear`, so a future engine change can't turn
            // a missing age into a spoken yes.
            return .notTracked(.noLeagueAge)
        }
    }

    /// Their most recent recorded outing strictly before `date`.
    ///
    /// Mirrors the engine's own window: `pitchEntries` ignores logs with no
    /// recorded count, and `restDayStatus` only looks at games already played.
    private static func lastOuting(for player: Player,
                                   in team: Team,
                                   before date: Date) -> EligibilityOuting? {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        let key = player.id.uuidString

        return team.gameLogs
            .compactMap { log -> EligibilityOuting? in
                guard let count = log.pitchCounts[key], count > 0 else { return nil }
                guard calendar.startOfDay(for: log.gameDate) < day else { return nil }
                return EligibilityOuting(date: log.gameDate, pitches: count)
            }
            .max { $0.date < $1.date }
    }
}
