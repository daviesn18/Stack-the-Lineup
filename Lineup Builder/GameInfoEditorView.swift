import SwiftUI

/// Editor sheet for the game's date, opponent, and status.
///
/// Presented from the compact Game card on the Lineup tab. Editing happens
/// here rather than inline so the Lineup tab can lead with the batting order.
/// Status is read-only: finalizing happens on the Positions tab.
struct GameInfoEditorView: View {
    @EnvironmentObject var store: LineupStore
    @Environment(\.dismiss) private var dismiss

    private var isReadOnly: Bool { store.activeTeam.isReadOnly }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Game Date", selection: Binding(
                        get: { store.lineup.gameDate },
                        set: { store.updateGameDate($0) }
                    ), displayedComponents: .date)
                    .disabled(isReadOnly)

                    HStack {
                        Text("Opponent")
                        Spacer()
                        TextField("Opponent Name", text: Binding(
                            get: { store.lineup.opponent },
                            set: { store.updateOpponent($0) }
                        ))
                        .multilineTextAlignment(.trailing)
                        .autocorrectionDisabled()
                        .disabled(isReadOnly)
                    }

                    // Read-only status indicator — changes are made on the Positions tab
                    HStack {
                        Text("Status")
                            .foregroundColor(.primary)
                        Spacer()
                        if store.lineup.status == .finalized {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.subheadline)
                                    .foregroundColor(.green)
                                Text("Finalized")
                                    .font(.subheadline)
                                    .foregroundColor(.green)
                            }
                        } else {
                            Text("Draft")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Game Info")
                } footer: {
                    if store.lineup.status == .draft {
                        Text("Finalize your lineup from the Positions tab when it's ready.")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Game Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
