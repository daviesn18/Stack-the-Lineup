import SwiftUI
import StoreKit

// MARK: - ArchiveGameSheet
// Presented from the global toolbar button in ContentView.
// Coach confirms innings played (pre-filled to 7), then archives.

struct ArchiveGameSheet: View {
    @EnvironmentObject var store: LineupStore
    @Environment(\.dismiss) var dismiss
    @Environment(\.requestReview) var requestReview

    // Callback fires after a successful archive so GameLogsView
    // can invalidate its insights cache.
    var onArchived: (() -> Void)?

    @State private var inningsPlayed: Int = 7
    @State private var showingConfirmation = false
    @State private var archivedOpponent: String = ""

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

    var body: some View {
        NavigationStack {
            Form {
                // Game Summary (read-only)
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

                // Innings Played
                Section {
                    Stepper(value: $inningsPlayed, in: 1...7) {
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

                // Archive Action
                Section {
                    Button {
                        archivedOpponent = opponentDisplay
                        store.archiveCurrentLineup(inningsPlayed: inningsPlayed)
                        onArchived?()
                        Analytics.signal("game.archived", parameters: [
                            "inningsPlayed": "\(inningsPlayed)",
                            "playerCount": "\(activePlayers.count)"
                        ])
                        maybeRequestReview()
                        showingConfirmation = true
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
        }
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

// MARK: - Preview

#Preview {
    ArchiveGameSheet()
        .environmentObject(LineupStore())
}
