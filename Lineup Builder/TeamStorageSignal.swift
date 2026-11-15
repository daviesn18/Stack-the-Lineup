//
//  TeamStorageSignal.swift
//  Lineup Builder
//
//  A once-a-day TelemetryDeck signal saying where this device's teams live.
//
//  Why: existing teams stay on CloudKit after the spring cutover; only new
//  teams (for signed-in coaches) go to Supabase, and coaches can move a team
//  over by hand. A hard cutover waits until CloudKit activity has dwindled.
//  This signal is how we'll see that: coaches per week whose open team is on
//  CloudKit, against coaches whose open team is in their account.
//
//  Counts only, never names or team contents. Per device, so a coach with an
//  iPhone and an iPad counts twice, and a shared team counts once per coach
//  on it. That's fine for a trend.
//
//  "account" is always 0 until account teams exist (Merge 0b/1); the
//  parameter is sent from the start so the chart's shape never changes.
//

import Foundation

nonisolated enum TeamStorageSignal {

    static let name = "teams.storage.daily"

    /// A team counts as active if it was edited within this many days.
    static let activeWindowDays = 14

    /// UserDefaults key holding the last day (yyyy-MM-dd, local) a signal went.
    static let lastSentDayKey = "stl_storage_signal_day"

    enum Storage: String {
        /// Synced through iCloud (has a CloudKit record).
        case cloudkit
        /// In the coach's Supabase account.
        case account
        /// Never uploaded anywhere: no iCloud, or not yet synced.
        case device
    }

    static func storage(of team: Team, accountTeamIDs: Set<UUID>) -> Storage {
        if accountTeamIDs.contains(team.id) { return .account }
        return team.ckRecordName == nil ? .device : .cloudkit
    }

    /// The signal's parameters. Pure, for tests.
    static func parameters(teams: [Team], activeTeamID: UUID?, accountTeamIDs: Set<UUID> = [],
                           isReceivedShare: (Team) -> Bool, now: Date = Date()) -> [String: String] {
        let cutoff = now.addingTimeInterval(-Double(activeWindowDays) * 86_400)
        var total: [Storage: Int] = [:]
        var active: [Storage: Int] = [:]
        var received = 0

        for team in teams {
            let s = storage(of: team, accountTeamIDs: accountTeamIDs)
            total[s, default: 0] += 1
            if team.updatedAt >= cutoff { active[s, default: 0] += 1 }
            if s == .cloudkit && (isReceivedShare(team) || team.isSharedParticipant) { received += 1 }
        }

        let open = teams.first { $0.id == activeTeamID }.map { storage(of: $0, accountTeamIDs: accountTeamIDs).rawValue } ?? "none"
        return [
            "cloudKitTeams": "\(total[.cloudkit] ?? 0)",
            "accountTeams": "\(total[.account] ?? 0)",
            "deviceOnlyTeams": "\(total[.device] ?? 0)",
            "cloudKitActive": "\(active[.cloudkit] ?? 0)",
            "accountActive": "\(active[.account] ?? 0)",
            "deviceOnlyActive": "\(active[.device] ?? 0)",
            "cloudKitReceivedTeams": "\(received)",
            "openTeamStorage": open,
        ]
    }

    /// The local calendar day, as the once-a-day gate stores it.
    static func dayString(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// True (and records today) when no signal has gone yet today.
    static func claimToday(defaults: UserDefaults = .standard, now: Date = Date()) -> Bool {
        let today = dayString(now)
        guard defaults.string(forKey: lastSentDayKey) != today else { return false }
        defaults.set(today, forKey: lastSentDayKey)
        return true
    }
}

extension LineupStore {
    /// Sends `teams.storage.daily` at most once per local day. Call on
    /// foreground, after the teams have loaded.
    func sendDailyStorageSignalIfNeeded() {
        guard !teams.isEmpty, TeamStorageSignal.claimToday() else { return }
        Analytics.signal(TeamStorageSignal.name, parameters: TeamStorageSignal.parameters(
            teams: teams, activeTeamID: activeTeamID, isReceivedShare: { self.isReceivedShare($0) }))
    }
}
