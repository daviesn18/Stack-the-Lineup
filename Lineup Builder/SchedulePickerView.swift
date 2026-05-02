import SwiftUI

// MARK: - SchedulePickerView
// Full-screen sheet presenting the team's imported schedule as a scannable
// list. Selecting a game pre-fills the active lineup's date and opponent
// and dismisses back to LineupView.

struct SchedulePickerView: View {
    @EnvironmentObject var store: LineupStore
    @Environment(\.dismiss) var dismiss

    let onPick: (ScheduledGame) -> Void

    private var upcomingGames: [ScheduledGame] {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        return store.scheduledGames
            .filter { !$0.isCancelled && $0.date >= startOfToday && !isPractice($0.rawSummary) }
            .sorted { $0.date < $1.date }
    }

    /// Returns true if the summary looks like a practice rather than a game.
    private func isPractice(_ summary: String) -> Bool {
        let lower = summary.lowercased()
        let keywords = ["practice", "batting practice", "bp", "team practice",
                        "infield", "skills", "clinic", "workout", "scrimmage",
                        "tryout", "try-out", "warm-up", "warmup"]
        return keywords.contains(where: { lower.contains($0) })
    }

    /// Returns the active lineup status if the lineup's game date matches
    /// this scheduled game's date (day-level comparison).
    private func lineupStatus(for game: ScheduledGame) -> LineupStatus? {
        let cal = Calendar.current
        guard cal.isDate(store.lineup.gameDate, inSameDayAs: game.date) else { return nil }
        // Only show status if there's actually something in the lineup
        let hasContent = !store.lineup.battingOrder.isEmpty
            || store.lineup.innings.contains(where: { !$0.assignments.isEmpty })
        guard hasContent else { return nil }
        return store.lineup.status
    }

    // Group games by month for section headers
    private var groupedGames: [(title: String, games: [ScheduledGame])] {
        var groups: [(title: String, games: [ScheduledGame])] = []
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"

        var seen: [String: Int] = [:]
        for game in upcomingGames {
            let key = formatter.string(from: game.date)
            if let idx = seen[key] {
                groups[idx].games.append(game)
            } else {
                seen[key] = groups.count
                groups.append((title: key, games: [game]))
            }
        }
        return groups
    }

    var body: some View {
        NavigationStack {
            Group {
                if upcomingGames.isEmpty {
                    emptyState
                } else {
                    gameList
                }
            }
            .navigationTitle("Pick a Game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: - Game List

    private var gameList: some View {
        List {
            ForEach(groupedGames, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.games) { game in
                        Button {
                            onPick(game)
                            dismiss()
                        } label: {
                            gameRow(game)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private func gameRow(_ game: ScheduledGame) -> some View {
        HStack(spacing: 12) {
            // Date badge
            VStack(spacing: 2) {
                Text(game.date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.blue)
                Text(game.date.formatted(.dateTime.day()))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.primary)
            }
            .frame(width: 44)
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(Color.blue.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                if let opponent = game.opponent {
                    Text("vs. \(opponent)")
                        .font(.headline)
                        .foregroundColor(.primary)
                } else {
                    Text(game.rawSummary)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    Text(game.date.formatted(.dateTime.hour().minute()))
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    if let location = game.location {
                        Text("·")
                            .foregroundColor(.secondary)
                        Text(location)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                // Lineup status badge — only shown when this game's date
                // matches the active lineup and the lineup has content
                if let status = lineupStatus(for: game) {
                    HStack(spacing: 4) {
                        Image(systemName: status == .finalized ? "checkmark.circle.fill" : "pencil.circle.fill")
                            .font(.caption)
                        Text(status == .finalized ? "Finalized" : "Draft")
                            .font(.caption.bold())
                    }
                    .foregroundColor(status == .finalized ? .green : .orange)
                    .padding(.top, 2)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundColor(Color(.tertiaryLabel))
        }
        .padding(.vertical, 4)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 48))
                .foregroundColor(Color(.systemGray3))
            Text("No Upcoming Games")
                .font(.headline)
            Text("All imported games may have already passed, or your schedule may be empty.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}
