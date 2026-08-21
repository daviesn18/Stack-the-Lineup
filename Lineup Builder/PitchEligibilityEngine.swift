import Foundation

// MARK: - Pitch Eligibility Engine
//
// Computes each pitcher's current eligibility status from stored pitch counts
// and the team's PitchingConfig. Stateless — call compute() as needed.
//
// Inputs:
//   - gameLogs:      All GameLog records for the team (pitch counts stored per log)
//   - players:       Current roster (used to resolve league age and preferences)
//   - config:        Team's PitchingConfig (rules, thresholds, window type)
//   - referenceDate: The date to compute eligibility relative to (default: today)
//
// Output:
//   - [UUID: PitchEligibilityStatus] keyed by player ID

// MARK: - Eligibility Status

enum PitchEligibilityStatus: Equatable {
    /// No restrictions. Player is fully eligible to pitch.
    case eligible

    /// Player can pitch but has fewer pitches remaining than the daily max.
    /// `remaining` is how many pitches they have left in the current window.
    case limited(remaining: Int)

    /// Player must rest until the given date (inclusive — they may pitch on that date).
    case mustRest(until: Date)

    /// Player's league age is not set — eligibility cannot be computed.
    case unknownAge

    // MARK: Display helpers

    var displayLabel: String {
        switch self {
        case .eligible:
            return "Eligible"
        case .limited:
            return "Limited"
        case .mustRest(let date):
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE M/d"
            return "Available \(formatter.string(from: date))"
        case .unknownAge:
            return "Age not set"
        }
    }

    /// True when the player may pitch (either fully eligible or limited).
    var isEligible: Bool {
        switch self {
        case .eligible, .limited: return true
        case .mustRest, .unknownAge: return false
        }
    }

    var isRestricted: Bool { !isEligible }

    /// True only when the player cannot pitch at all — must rest or age unknown.
    /// .limited players can pitch (just fewer pitches) so this returns false for them.
    var blocksAssignment: Bool {
        switch self {
        case .mustRest, .unknownAge: return true
        case .eligible, .limited: return false
        }
    }
}

// MARK: - Pitch Window Entry

/// A single pitch count event: one game's worth of pitches for one player.
private struct PitchEntry {
    let playerID: UUID
    let gameDate: Date
    let pitches: Int
}

// MARK: - Engine

struct PitchEligibilityEngine {

    // MARK: - Public API

    /// Computes eligibility for all players whose Pitcher preference is not .never.
    /// Players without any pitch data in the relevant window are returned as .eligible.
    /// Returns an empty dictionary if pitching rules are disabled in config.
    static func compute(
        gameLogs: [GameLog],
        players: [Player],
        config: PitchingConfig,
        referenceDate: Date = Date()
    ) -> [UUID: PitchEligibilityStatus] {
        guard config.rulesEnabled else { return [:] }

        let pitchablePlayers = players.filter {
            $0.positionPreferences[.pitcher] != .never
        }

        var results: [UUID: PitchEligibilityStatus] = [:]
        for player in pitchablePlayers {
            results[player.id] = status(
                for: player,
                gameLogs: gameLogs,
                config: config,
                referenceDate: referenceDate
            )
        }
        return results
    }

    /// Computes eligibility for a single player. Useful for inline pitcher slot
    /// checks without recomputing the full roster.
    static func status(
        for player: Player,
        gameLogs: [GameLog],
        config: PitchingConfig,
        referenceDate: Date = Date()
    ) -> PitchEligibilityStatus {
        guard config.rulesEnabled else { return .eligible }

        // Can't apply rules without a league age
        guard let age = player.leagueAge else { return .unknownAge }

        // Age is set but outside any configured bracket (e.g. age 17+)
        guard let bracket = PitchingAgeBracket.bracket(for: age),
              let limits = config.ageLimits[bracket] else {
            return .eligible
        }

        let entries = pitchEntries(for: player.id, from: gameLogs)

        // 1. Rest day check: did the player throw pitches recently enough
        //    that mandatory rest days haven't elapsed yet?
        if let restStatus = restDayStatus(
            entries: entries,
            limits: limits,
            referenceDate: referenceDate
        ) {
            return restStatus
        }

        // 2. Weekly window cap: if enabled, check whether the player has
        //    used up their window allowance and whether that limits today.
        if config.weeklyLimitEnabled && config.weeklyLimit > 0 {
            let windowPitches = pitchesInWindow(
                entries: entries,
                config: config,
                referenceDate: referenceDate
            )
            let remaining = config.weeklyLimit - windowPitches

            if remaining <= 0 {
                // Cap exhausted — must wait for the window to roll forward
                let clearDate = windowClearDate(
                    entries: entries,
                    config: config,
                    referenceDate: referenceDate
                ) ?? referenceDate
                return .mustRest(until: clearDate)
            }

            // Can pitch, but effective max is capped by what's left in the window
            let effectiveMax = min(limits.dailyMax, remaining)
            if effectiveMax < limits.dailyMax {
                return .limited(remaining: effectiveMax)
            }
        }

        return .eligible
    }

    // MARK: - Private Helpers

    /// Extracts all pitch entries for a given player from game logs,
    /// sorted by game date ascending. Only includes entries with pitch count > 0.
    private static func pitchEntries(for playerID: UUID, from gameLogs: [GameLog]) -> [PitchEntry] {
        let key = playerID.uuidString
        return gameLogs
            .compactMap { log -> PitchEntry? in
                guard let count = log.pitchCounts[key], count > 0 else { return nil }
                return PitchEntry(playerID: playerID, gameDate: log.gameDate, pitches: count)
            }
            .sorted { $0.gameDate < $1.gameDate }
    }

    /// Checks whether the player is currently in a mandatory rest period.
    /// Finds the most recent past game where they threw pitches, then checks
    /// whether the required rest days have elapsed relative to referenceDate.
    private static func restDayStatus(
        entries: [PitchEntry],
        limits: PitchingLimits,
        referenceDate: Date
    ) -> PitchEligibilityStatus? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: referenceDate)

        // Only look at games that have already been played (before today)
        guard let lastEntry = entries.last(where: {
            cal.startOfDay(for: $0.gameDate) < today
        }) else {
            return nil
        }

        let restDaysNeeded = limits.restDaysRequired(for: lastEntry.pitches)
        guard restDaysNeeded > 0 else { return nil }

        let gameDay = cal.startOfDay(for: lastEntry.gameDate)
        // restDaysNeeded is the number of calendar days the player must sit out.
        // A player who throws 25 pitches on Monday needs 1 rest day (Tuesday),
        // and is available to pitch again on Wednesday — gameDay + restDays + 1.
        guard let availableDate = cal.date(byAdding: .day, value: restDaysNeeded + 1, to: gameDay) else {
            return nil
        }

        // Player must rest if today is still before the available date
        if today < availableDate {
            return .mustRest(until: availableDate)
        }

        return nil
    }

    /// Counts total pitches thrown within the active rolling window,
    /// not including today (games played today haven't been archived yet).
    private static func pitchesInWindow(
        entries: [PitchEntry],
        config: PitchingConfig,
        referenceDate: Date
    ) -> Int {
        let windowStart = windowStartDate(config: config, referenceDate: referenceDate)
        let cal = Calendar.current
        let today = cal.startOfDay(for: referenceDate)

        return entries
            .filter { entry in
                let day = cal.startOfDay(for: entry.gameDate)
                return day >= windowStart && day < today
            }
            .reduce(0) { $0 + $1.pitches }
    }

    /// Monday 00:00 of the week containing `date`.
    ///
    /// Derived by counting back from the weekday rather than by rebuilding the
    /// date from `weekOfYear` with `weekday = 2`. That route asks the *locale's*
    /// calendar where the week starts: on the US default it starts Sunday, so
    /// the week containing a Sunday runs Sun–Sat and `weekday = 2` resolves to
    /// the **following** Monday. The window then began in the future and matched
    /// no games at all, so on Sundays the weekly cap silently stopped applying.
    ///
    /// Weekday arithmetic gives the same answer in every locale.
    static func startOfPitchingWeek(for date: Date, calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: date)
        // .weekday is 1 = Sunday ... 7 = Saturday, so Monday (2) maps to 0 days
        // back and Sunday (1) to 6 — the Monday that *opened* the current week.
        let daysSinceMonday = (calendar.component(.weekday, from: today) + 5) % 7
        return calendar.date(byAdding: .day, value: -daysSinceMonday, to: today) ?? today
    }

    /// Returns the start date of the current rolling window.
    /// Calendar week: Monday 00:00 of the current week.
    /// Rolling: today minus (rollingWindowDays - 1).
    private static func windowStartDate(config: PitchingConfig, referenceDate: Date) -> Date {
        let cal = Calendar.current
        let today = cal.startOfDay(for: referenceDate)

        switch config.rollingWindowType {
        case .calendarWeek:
            return startOfPitchingWeek(for: today, calendar: cal)

        case .rolling:
            return cal.date(byAdding: .day, value: -(config.rollingWindowDays - 1), to: today) ?? today
        }
    }

    /// Returns the earliest date the weekly cap clears, based on when the oldest
    /// game in the current window rolls off.
    private static func windowClearDate(
        entries: [PitchEntry],
        config: PitchingConfig,
        referenceDate: Date
    ) -> Date? {
        let windowStart = windowStartDate(config: config, referenceDate: referenceDate)
        let cal = Calendar.current
        let today = cal.startOfDay(for: referenceDate)

        let windowEntries = entries.filter { entry in
            let day = cal.startOfDay(for: entry.gameDate)
            return day >= windowStart && day < today
        }

        guard let oldest = windowEntries.min(by: { $0.gameDate < $1.gameDate }) else {
            return nil
        }

        switch config.rollingWindowType {
        case .rolling:
            // Window clears when the oldest game ages out
            let oldestDay = cal.startOfDay(for: oldest.gameDate)
            return cal.date(byAdding: .day, value: config.rollingWindowDays, to: oldestDay)

        case .calendarWeek:
            // Window clears at the start of next Monday
            let thisMonday = startOfPitchingWeek(for: today, calendar: cal)
            return cal.date(byAdding: .weekOfYear, value: 1, to: thisMonday)
        }
    }
}

// MARK: - Coaches Guide Summary

/// A single row in the Coaches Guide pitching summary table.
struct PitchingGuideSummaryRow {
    let player: Player
    let pitchesInWindow: Int
    let dailyMax: Int
    /// The lower of the daily max and what's left in the weekly window — what
    /// the player can actually throw today, which is the number a coach plans
    /// against. Equals `dailyMax` when no weekly limit is enabled.
    let available: Int
    /// Rest days owed from their most recent outing. 0 once the rest has
    /// elapsed, so it's only meaningful alongside a restricted `status`.
    let restDaysRequired: Int
    let status: PitchEligibilityStatus
}

extension PitchEligibilityEngine {

    /// Builds rows for the Coaches Guide pitching summary table.
    /// Excludes players with Pitcher preference set to Never.
    /// Returns nil if pitching rules are disabled or no eligible pitchers exist.
    ///
    /// Sorted the way a coach reads the table: who can throw, most available
    /// first, with restricted players last. `PDFGenerator` used to hold its own
    /// hand-rolled copy of this ("exact port of PositionSummaryView") which
    /// sorted that way; this is now the single implementation, so the ordering
    /// came with it. Ties break on last name for a stable page.
    /// The per-player pitching math — window pitches, daily max, what's
    /// available today, rest owed, and status — for exactly the players given,
    /// in the order given. No filtering, no sorting, no rules-enabled guard:
    /// callers apply their own policy on top.
    ///
    /// This is the single copy of arithmetic that was previously triplicated
    /// across `coachesGuideSummary`, `PositionSummaryView.pitchingRows()` and
    /// (before it folded in here) `PDFGenerator`. The two remaining callers
    /// diverge deliberately — the Coaches Guide filters `.never`, drops the
    /// table when rules are off, and sorts stably; the Pitching tab keeps every
    /// pitcher, renders with rules off, and decorates each row with the innings
    /// it's assigned in today's lineup — so those policies stay at the call
    /// sites and only the maths lives here. See `PitchingSummaryTests` for the
    /// behaviour each side is pinned to.
    static func pitchingSummaryRows(
        gameLogs: [GameLog],
        players: [Player],
        config: PitchingConfig,
        referenceDate: Date = Date()
    ) -> [PitchingGuideSummaryRow] {
        let statuses = compute(
            gameLogs: gameLogs,
            players: players,
            config: config,
            referenceDate: referenceDate
        )

        return players.map { player in
            // Resolve limits for this player's age bracket
            let limits: PitchingLimits? = player.leagueAge
                .flatMap { PitchingAgeBracket.bracket(for: $0) }
                .flatMap { config.ageLimits[$0] }

            let entries = pitchEntries(for: player.id, from: gameLogs)

            let windowPitches = pitchesInWindow(
                entries: entries,
                config: config,
                referenceDate: referenceDate
            )

            // Rest days from the most recent past game
            let cal = Calendar.current
            let today = cal.startOfDay(for: referenceDate)
            let lastEntry = entries.last(where: {
                cal.startOfDay(for: $0.gameDate) < today
            })
            let restDays = lastEntry.flatMap { entry in
                limits.map { $0.restDaysRequired(for: entry.pitches) }
            } ?? 0

            let dailyMax = limits?.dailyMax ?? 0

            // What they can actually throw today. The weekly window only
            // constrains when the coach has enabled a limit.
            var available = dailyMax
            if config.weeklyLimitEnabled && config.weeklyLimit > 0 {
                available = min(dailyMax, max(0, config.weeklyLimit - windowPitches))
            }

            return PitchingGuideSummaryRow(
                player: player,
                pitchesInWindow: windowPitches,
                dailyMax: dailyMax,
                available: available,
                restDaysRequired: restDays,
                status: statuses[player.id] ?? .eligible
            )
        }
    }

    static func coachesGuideSummary(
        gameLogs: [GameLog],
        players: [Player],
        config: PitchingConfig,
        referenceDate: Date = Date()
    ) -> [PitchingGuideSummaryRow]? {
        guard config.rulesEnabled else { return nil }

        let pitchablePlayers = players.filter {
            $0.positionPreferences[.pitcher] != .never
        }
        guard !pitchablePlayers.isEmpty else { return nil }

        let rows = pitchingSummaryRows(
            gameLogs: gameLogs,
            players: pitchablePlayers,
            config: config,
            referenceDate: referenceDate
        )

        return rows.sorted { a, b in
            if a.status.isRestricted != b.status.isRestricted { return !a.status.isRestricted }
            if a.available != b.available { return a.available > b.available }
            return a.player.lastName < b.player.lastName
        }
    }
}
