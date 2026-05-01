import SwiftUI

// MARK: - RosterImportTeamPickerView
// First step of the share-sheet roster import flow. Shown when a coach shares
// a CSV/.stlroster file into the app and the parser successfully reads it.
// Asks which team the roster belongs to, or offers to create a new team.
// In-app imports (via PlayersView's "Import Roster" button) skip this entirely —
// they import into the active team without a picker since context is implicit.

struct RosterImportTeamPickerView: View {
    @EnvironmentObject var store: LineupStore
    @Environment(\.dismiss) var dismiss

    let filename: String
    let playerCount: Int
    let onPickExistingTeam: (UUID) -> Void
    let onCreateNewTeam: () -> Void
    let onCancel: () -> Void

    @State private var selectedTeamID: UUID?
    @State private var creatingNewTeam = false

    var body: some View {
        NavigationStack {
            List {
                // Source summary
                Section {
                    HStack {
                        Text("From")
                        Spacer()
                        Text(filename)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    HStack {
                        Text("Players found")
                        Spacer()
                        Text("\(playerCount)")
                            .foregroundColor(.secondary)
                    }
                } footer: {
                    Text("Choose where these players should go.")
                }

                // Existing teams
                if !store.teams.isEmpty {
                    Section("Existing Teams") {
                        ForEach(store.teams) { team in
                            Button {
                                selectedTeamID = team.id
                                creatingNewTeam = false
                            } label: {
                                HStack(spacing: 12) {
                                    Circle()
                                        .fill(team.color)
                                        .frame(width: 14, height: 14)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(team.name.isEmpty ? "Untitled Team" : team.name)
                                            .foregroundColor(.primary)
                                        if team.id == store.activeTeamID {
                                            Text("Current team")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        } else {
                                            Text("\(team.players.count) \(team.players.count == 1 ? "player" : "players")")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    Spacer()
                                    if selectedTeamID == team.id && !creatingNewTeam {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                            .font(.body.bold())
                                    }
                                }
                            }
                        }
                    }
                }

                // New team option
                Section {
                    Button {
                        selectedTeamID = nil
                        creatingNewTeam = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.blue)
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Create New Team")
                                    .foregroundColor(.primary)
                                Text("Set up a new team and add these players to it")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if creatingNewTeam {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                                    .font(.body.bold())
                            }
                        }
                    }
                }
            }
            .navigationTitle("Import Roster")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continue") {
                        if creatingNewTeam {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                onCreateNewTeam()
                            }
                        } else if let teamID = selectedTeamID {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                onPickExistingTeam(teamID)
                            }
                        }
                    }
                    .bold()
                    .disabled(selectedTeamID == nil && !creatingNewTeam)
                }
            }
        }
    }
}
