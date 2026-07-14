import SwiftUI
import StoreKit

// MARK: - ArchiveGameSheet
// Presented from the global toolbar button in ContentView.
// Coach confirms innings played, enters pitch counts, then archives in one step.
// Pitch counts are always shown (Pro) so data is captured even before pitching
// rules are configured — the coach can enable rules later and history is intact.

struct ArchiveGameSheet: View {
    @EnvironmentObject var store: LineupStore
    @EnvironmentObject var purchaseManager: PurchaseManager
    @Environment(\.dismiss) var dismiss
    @Environment(\.requestReview) var requestReview

    var onArchived: (() -> Void)?

    @State private var inningsPlayed: Int = 7
    @State private var showingConfirmation = false
    @State private var archivedOpponent: String = ""
    @State private var didInitializeInnings = false

    // Pitch count state — inline in the form
    // pitcherIDs: ordered list of players in the pitch count section
    // pitchCounts: keyed by player UUID, string so TextField works directly
    @State private var pitcherIDs: [UUID] = []
    @State private var pitchCounts: [UUID: String] = [:]
    @State private var showingAddPitcher = false
    @State private var gameNotes: String = ""

    // MARK: - Computed

    private var hasAnyAssignments: Bool {
        store.lineup.innings.contains { !$0.assignments.isEmpty }
    }

    private var hasGameDetails: Bool {
        !store.lineup.opponent.isEmpty || hasAnyAssignments
    }

    private var opponentDisplay: String {
        store.lineup.opponent.isEmpty ? "No Opponent" : store.lineup.opponent
    }

    private var activePlayers: [Player] {
        store.lineup.activePlayers(from: store.players)
    }

    /// Players currently assigned as Pitcher in any inning of the active lineup.
    private var detectedPitcherIDs: [UUID] {
        let ids = store.lineup.innings.flatMap { inning in
            inning.assignments.compactMap { (playerID, pos) -> UUID? in
                pos == .pitcher ? playerID : nil
            }
        }
        // Stable ordered unique list
        var seen = Set<UUID>()
        return ids.filter { seen.insert($0).inserted }
    }

    private var listedPlayers: [Player] {
        pitcherIDs.compactMap { id in store.players.first { $0.id == id } }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                gameSummarySection
                inningsSection
                if purchaseManager.isPro {
                    pitchCountSection
                }
                notesSection
                archiveSection
            }
            .navigationTitle("Archive Game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Game Archived", isPresented: $showingConfirmation) {
                Button("Done") { dismiss() }
            } message: {
                Text("vs. \(archivedOpponent) has been saved to your game history. Defensive positions have been cleared.")
            }
            .sheet(isPresented: $showingAddPitcher) {
                AddPitcherPickerSheet(excludedIDs: Set(pitcherIDs)) { player in
                    pitcherIDs.append(player.id)
                    pitchCounts[player.id] = ""
                }
                .environmentObject(store)
            }
            .onAppear {
                if !didInitializeInnings {
                    inningsPlayed = store.gameInningCount
                    didInitializeInnings = true
                }
                setupPitchers()
            }
        }
    }

    // MARK: - Sections

    private var gameSummarySection: some View {
        Section("Game Summary") {
            HStack {
                Text("Date")
                Spacer()
                Text(store.lineup.gameDate, style: .date)
                    .foregroundColor(.secondary)
            }
            HStack {
                Text("Opponent")
                Spacer()
                Text(opponentDisplay)
                    .foregroundColor(store.lineup.opponent.isEmpty ? .secondary : .primary)
            }
            HStack {
                Text("Active Players")
                Spacer()
                Text("\(activePlayers.count)")
                    .foregroundColor(.secondary)
            }
        }
    }

    private var inningsSection: some View {
        Section {
            Stepper(value: $inningsPlayed, in: 1...store.gameInningCount) {
                HStack {
                    Text("Innings Played")
                    Spacer()
                    Text("\(inningsPlayed)")
                        .font(.body.bold())
                        .foregroundColor(.blue)
                        .frame(minWidth: 24, alignment: .trailing)
                }
            }
        } footer: {
            Text("Only innings actually played will count toward season stats and AI insights.")
        }
    }

    private var pitchCountSection: some View {
        Section {
            if listedPlayers.isEmpty {
                Text("No pitchers assigned in the positions grid. Tap Add Pitcher to enter counts manually.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(listedPlayers) { player in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(player.displayName)
                            if player.leagueAge == nil {
                                Text("Set league age to track eligibility")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                        Spacer()
                        TextField("0", text: countBinding(for: player.id))
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 64)
                            .foregroundStyle(.blue)
                            .fontWeight(.semibold)
                    }
                }
                .onDelete { indexSet in
                    for i in indexSet {
                        let id = pitcherIDs[i]
                        pitchCounts.removeValue(forKey: id)
                    }
                    pitcherIDs.remove(atOffsets: indexSet)
                }
            }

            Button {
                showingAddPitcher = true
            } label: {
                Label("Add Pitcher", systemImage: "plus.circle")
            }
        } header: {
            Text("Pitch Counts")
        } footer: {
            Text("Enter pitches thrown today. Swipe to remove a pitcher. This data is used to track rest days and eligibility.")
        }
    }

    private var notesSection: some View {
        Section("Game Notes") {
            TextField("Score, standout moments, reminders... (optional)", text: $gameNotes, axis: .vertical)
                .lineLimit(3...6)
        }
    }

    private var archiveSection: some View {
        Section {
            Button {
                archiveGame()
            } label: {
                HStack {
                    Spacer()
                    Label("Archive Game", systemImage: "archivebox.fill")
                        .font(.body.bold())
                    Spacer()
                }
            }
            .disabled(!hasGameDetails)
            .listRowBackground(hasGameDetails ? Color.blue : Color(.systemGray5))
            .foregroundColor(hasGameDetails ? .white : .secondary)
        } footer: {
            if !hasGameDetails {
                Text("Add game details or defensive positions before archiving.")
                    .foregroundColor(.orange)
            } else {
                Text("Archiving will save this game to your history and clear all defensive positions. Your batting order will be kept.")
            }
        }
    }

    // MARK: - Setup

    private func setupPitchers() {
        let ids = detectedPitcherIDs
        pitcherIDs = ids
        for id in ids {
            pitchCounts[id] = ""
        }
    }

    private func countBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { pitchCounts[id] ?? "" },
            set: { pitchCounts[id] = $0 }
        )
    }

    // MARK: - Archive

    private func archiveGame() {
        archivedOpponent = opponentDisplay
        let newLogID = store.archiveCurrentLineup(inningsPlayed: inningsPlayed, notes: gameNotes)
        onArchived?()

        // Save any pitch counts that were entered
        if purchaseManager.isPro {
            var parsed: [String: Int] = [:]
            for (id, text) in pitchCounts {
                if let value = Int(text), value > 0 {
                    parsed[id.uuidString] = value
                }
            }
            if !parsed.isEmpty {
                store.savePitchCounts(parsed, for: newLogID)
            }
        }

        Analytics.signal("game.archived", parameters: [
            "inningsPlayed": "\(inningsPlayed)",
            "playerCount": "\(activePlayers.count)",
            "pitchCountsEntered": "\(pitchCounts.values.filter { Int($0) ?? 0 > 0 }.count)"
        ])
        maybeRequestReview()
        showingConfirmation = true
    }

    // MARK: - Review Request

    private func maybeRequestReview() {
        guard !UserDefaults.standard.bool(forKey: "hasRequestedReview") else { return }
        let count = UserDefaults.standard.integer(forKey: "gamesArchivedCount") + 1
        UserDefaults.standard.set(count, forKey: "gamesArchivedCount")
        if count >= 2 {
            requestReview()
            UserDefaults.standard.set(true, forKey: "hasRequestedReview")
        }
    }
}

// MARK: - Add Pitcher Picker Sheet

/// Lets the coach pick a player from the roster who isn't already in the pitch count list.
private struct AddPitcherPickerSheet: View {
    @EnvironmentObject var store: LineupStore
    @Environment(\.dismiss) var dismiss

    let excludedIDs: Set<UUID>
    let onSelect: (Player) -> Void

    private var availablePlayers: [Player] {
        store.players
            .filter { !excludedIDs.contains($0.id) }
            .sorted { $0.lastName < $1.lastName }
    }

    var body: some View {
        NavigationStack {
            Group {
                if availablePlayers.isEmpty {
                    ContentUnavailableView(
                        "All players added",
                        systemImage: "person.crop.circle.badge.checkmark",
                        description: Text("Every player on the roster has been added.")
                    )
                } else {
                    List(availablePlayers) { player in
                        Button {
                            onSelect(player)
                            dismiss()
                        } label: {
                            HStack {
                                Text(player.displayName)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if !player.number.isEmpty {
                                    Text("#\(player.number)")
                                        .foregroundStyle(.secondary)
                                        .font(.subheadline)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add Pitcher")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ArchiveGameSheet()
        .environmentObject(LineupStore())
        .environmentObject(PurchaseManager())
}
