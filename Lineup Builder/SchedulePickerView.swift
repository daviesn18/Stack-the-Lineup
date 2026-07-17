import SwiftUI

// MARK: - SchedulePickerView
// Full-screen sheet presenting the team's imported schedule as a scannable
// list. Selecting a game pre-fills the active lineup's date and opponent
// and dismisses back to LineupView.
//
// A coach who realizes the schedule is stale can update it without leaving:
// the footer button opens the import sheet on top of the picker, and the
// list refreshes in place once new games merge in.

struct SchedulePickerView: View {
    @EnvironmentObject var store: LineupStore
    @Environment(\.dismiss) var dismiss

    let onPick: (ScheduledGame) -> Void

    @State private var showingScheduleImport = false

    private var upcomingGames: [ScheduledGame] {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        return store.scheduledGames
            .filter { !$0.isCancelled && $0.date >= startOfToday && !ICalParser.isPractice($0.rawSummary) }
            .sorted { $0.date < $1.date }
    }

    /// Whether a schedule has already been imported. Drives the footer button
    /// label (Add vs. Update).
    private var hasSchedule: Bool { !store.scheduledGames.isEmpty }

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
            // Footer action to add or refresh the schedule without leaving.
            .safeAreaInset(edge: .bottom) {
                updateScheduleBar
            }
        }
        .sheet(isPresented: $showingScheduleImport) {
            ScheduleImportView { games, urlString in
                // Merge in place. The list reads store.scheduledGames
                // reactively, so refreshed games appear once this returns.
                _ = store.mergeScheduledGames(games)
                if let url = urlString {
                    store.setCalendarSubscriptionURL(url)
                }
            }
            .environmentObject(store)
        }
    }

    // MARK: - Update Schedule Bar

    private var updateScheduleBar: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                showingScheduleImport = true
                Analytics.signal("schedule.import.tapped", parameters: ["source": "picker"])
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "calendar.badge.plus")
                    Text(hasSchedule ? "Update Schedule" : "Add Schedule")
                }
                .font(.subheadline.weight(.medium))
                .foregroundColor(.blue)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
        }
        .background(.bar)
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
