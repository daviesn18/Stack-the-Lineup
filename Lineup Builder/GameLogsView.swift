import SwiftUI

// MARK: - GameLogsView
// The History tab. Shows AI insights card at the top, then the list of archived games.

struct GameLogsView: View {
    @EnvironmentObject var store: LineupStore
    @StateObject private var insightsService = GameLogInsightsService()

    @State private var logToDelete: GameLog? = nil
    @State private var showingDeleteConfirmation = false
    @State private var showingTips = false

    var body: some View {
        NavigationStack {
            Group {
                if store.gameLogs.isEmpty {
                    emptyState
                } else {
                    logList
                }
            }
            .navigationTitle("Game History")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingTips = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                }
            }
            .sheet(isPresented: $showingTips) {
                PageTipsView(page: .history)
            }
        }
        .onAppear {
            insightsService.loadIfNeeded(logs: store.gameLogs)
        }
        .onChange(of: store.gameLogs.count) {
            insightsService.loadIfNeeded(logs: store.gameLogs)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView(
            "No Game Logs Yet",
            systemImage: "clock.arrow.circlepath",
            description: Text("Tap the archive button after each game to build your season history.")
        )
    }

    // MARK: - Log List

    private var logList: some View {
        List {
            // AI Insights Card — always at the top when logs exist
            Section {
                InsightsCardView(
                    service: insightsService,
                    teamColor: store.teamColor,
                    logs: store.gameLogs
                )
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            // Game log rows
            Section {
                ForEach(store.gameLogs) { log in
                    NavigationLink(destination: GameLogDetailView(log: log)) {
                        GameLogRow(log: log)
                    }
                }
                .onDelete { offsets in
                    // Map offsets to actual logs for confirmation
                    if let first = offsets.first {
                        logToDelete = store.gameLogs[first]
                        showingDeleteConfirmation = true
                    }
                }

                // Cap footer
                if store.gameLogs.count >= 20 {
                    Text("Showing your last 20 games. Older games are automatically removed.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            } header: {
                Text("\(store.gameLogs.count) \(store.gameLogs.count == 1 ? "Game" : "Games")")
            }
        }
        .listStyle(.insetGrouped)
        .confirmationDialog(
            "Delete Game Log?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let log = logToDelete {
                    store.deleteGameLog(id: log.id)
                    insightsService.invalidateCache()
                    insightsService.loadIfNeeded(logs: store.gameLogs)
                }
            }
            Button("Cancel", role: .cancel) { logToDelete = nil }
        } message: {
            if let log = logToDelete {
                let opponent = log.opponent.isEmpty ? "this game" : "vs. \(log.opponent)"
                Text("Delete the log for \(opponent)? This cannot be undone.")
            }
        }
    }
}

// MARK: - Game Log Row

struct GameLogRow: View {
    let log: GameLog

    private var dateString: String {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f.string(from: log.gameDate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(dateString)
                    .font(.subheadline.bold())

                Spacer()

                // Innings played badge
                Text("\(log.inningsPlayed) inn.")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(.systemGray5))
                    .foregroundColor(.secondary)
                    .cornerRadius(8)
            }

            Text(log.opponent.isEmpty ? "No Opponent" : "vs. \(log.opponent)")
                .font(.callout)
                .foregroundColor(log.opponent.isEmpty ? .secondary : .primary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Insights Card

struct InsightsCardView: View {
    @ObservedObject var service: GameLogInsightsService
    let teamColor: Color
    let logs: [GameLog]

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Card background — team color at 8% opacity
            RoundedRectangle(cornerRadius: 14)
                .fill(teamColor.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(teamColor.opacity(0.18), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 10) {
                // Header
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.subheadline.bold())
                        .foregroundColor(teamColor)
                    Text("Coaching Insights")
                        .font(.subheadline.bold())
                        .foregroundColor(teamColor)
                    Spacer()
                }

                // Body content driven by state
                insightBody
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity)
    }

    private func bulletLines(from text: String) -> [String] {
        let rawLines = text.components(separatedBy: "\n")
        var result: [String] = []
        for line in rawLines {
            if line.contains("•") {
                let parts = line.components(separatedBy: "•")
                    .map { "• " + $0.trimmingCharacters(in: .whitespaces) }
                    .filter { $0.trimmingCharacters(in: .whitespaces) != "•" && $0 != "• " }
                result.append(contentsOf: parts)
            } else {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { result.append(trimmed) }
            }
        }
        return result
    }

    @ViewBuilder
    private var insightBody: some View {
        switch service.state {

        case .idle:
            EmptyView()

        case .placeholder:
            Text("Archive 2 or more games to unlock AI coaching insights.")
                .font(.callout)
                .foregroundColor(.secondary)

        case .unsupported:
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "apple.intelligence.badge.xmark")
                    .foregroundColor(.secondary)
                Text("AI insights require iOS 26 and an Apple Intelligence‑capable device.")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }

        case .loading:
            HStack(spacing: 10) {
                ProgressView()
                    .scaleEffect(0.85)
                Text("Analyzing your season…")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }

        case .loaded(let text):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(bulletLines(from: text), id: \.self) { line in
                    Text(line.trimmingCharacters(in: .whitespaces))
                        .font(.callout)
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

        case .error:
            VStack(alignment: .leading, spacing: 8) {
                Text("Couldn't load insights right now.")
                    .font(.callout)
                    .foregroundColor(.secondary)
                Button {
                    service.retry(logs: logs)
                } label: {
                    Label("Tap to retry", systemImage: "arrow.clockwise")
                        .font(.caption.bold())
                }
                .buttonStyle(.borderless)
                .foregroundColor(teamColor)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    GameLogsView()
        .environmentObject(LineupStore())
}
