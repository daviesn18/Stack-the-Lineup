import SwiftUI

// MARK: - TeamImportView
// Presented as a sheet when a .stlteam file is opened — either via the iOS share
// sheet / Files app (onOpenURL in ContentView) or via the file picker in TeamFormView.
// Shows a preview of the imported team and lets the coach choose how to apply it.

struct TeamImportView: View {
    @EnvironmentObject var store: LineupStore
    @Environment(\.dismiss) var dismiss

    let imported: TeamImporter.ImportedTeam
    /// Called after a successful import with a short confirmation string for a toast.
    let onComplete: (String) -> Void

    @State private var showingReplaceConfirmation = false

    private var currentTeamName: String {
        store.teamName.isEmpty ? "Current Team" : store.teamName
    }

    private var importedTeamName: String {
        imported.team.name.isEmpty ? "Unnamed Team" : imported.team.name
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 24) {

                        // MARK: Header
                        VStack(spacing: 10) {
                            Image(systemName: "square.and.arrow.down.fill")
                                .font(.system(size: 48))
                                .foregroundColor(.blue)
                                .padding(.top, 16)

                            Text("Import Team File")
                                .font(.title2.bold())

                            Text("Exported \(imported.exportedAtFormatted)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        // MARK: Preview Card
                        VStack(spacing: 0) {
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(imported.team.color)
                                    .frame(width: 14, height: 14)
                                Text(importedTeamName)
                                    .font(.headline)
                                Spacer()
                            }
                            .padding(.bottom, 14)

                            Divider()

                            HStack(spacing: 0) {
                                statCell(
                                    value: "\(imported.playerCount)",
                                    label: imported.playerCount == 1 ? "Player" : "Players"
                                )
                                Divider().frame(height: 40)
                                statCell(
                                    value: "\(imported.gameCount)",
                                    label: imported.gameCount == 1 ? "Game" : "Games"
                                )
                                Divider().frame(height: 40)
                                statCell(
                                    value: "\(imported.team.gameInningCount)",
                                    label: "Innings"
                                )
                            }
                            .padding(.top, 14)
                        }
                        .padding(16)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 24)
                    }
                    .padding(.horizontal, 4)
                    .padding(.bottom, 16)
                }

                // MARK: Action Buttons
                VStack(spacing: 12) {
                    Button {
                        showingReplaceConfirmation = true
                    } label: {
                        Label("Replace \"\(currentTeamName)\"", systemImage: "arrow.triangle.2.circlepath")
                            .font(.body.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Button {
                        commitAsNewTeam()
                    } label: {
                        Label("Start New Team", systemImage: "plus.circle")
                            .font(.body.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(.secondarySystemBackground))
                            .foregroundColor(.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Button {
                        dismiss()
                    } label: {
                        Text("Cancel")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
                .padding(.top, 12)
                .background(.bar)
            }
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog(
                "Replace \"\(currentTeamName)\"?",
                isPresented: $showingReplaceConfirmation,
                titleVisibility: .visible
            ) {
                Button("Replace Team", role: .destructive) {
                    commitAsReplacement()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This replaces all players, history, and settings for \"\(currentTeamName)\" with the imported data. Your current lineup will be cleared. This cannot be undone.")
            }
        }
    }

    // MARK: - Actions

    private func commitAsReplacement() {
        store.replaceActiveTeam(with: imported.team)
        Analytics.signal("team.import.completed", parameters: [
            "mode": "replace",
            "player_count": "\(imported.playerCount)",
            "game_count": "\(imported.gameCount)"
        ])
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            onComplete("Team replaced successfully.")
        }
    }

    private func commitAsNewTeam() {
        store.addImportedTeam(imported.team)
        Analytics.signal("team.import.completed", parameters: [
            "mode": "new_team",
            "player_count": "\(imported.playerCount)",
            "game_count": "\(imported.gameCount)"
        ])
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            onComplete("\(importedTeamName) added.")
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.bold())
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
