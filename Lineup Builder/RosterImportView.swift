import SwiftUI

// MARK: - RosterImportView
// Preview sheet shown after a coach picks a CSV/.stlroster file.
// Shows parsed players, flags duplicates by full name, lets the coach
// toggle "Skip duplicates", and confirms the import.

struct RosterImportView: View {
    @EnvironmentObject var store: LineupStore
    @Environment(\.dismiss) var dismiss

    let parsedPlayers: [RosterImporter.ImportedPlayer]
    let sourceFilename: String
    let onImport: ([RosterImporter.ImportedPlayer]) -> Void

    @State private var skipDuplicates = true

    // MARK: - Computed

    private var existingMatchKeys: Set<String> {
        Set(store.players.map { player in
            "\(player.firstName) \(player.lastName)"
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
        })
    }

    private var duplicates: [RosterImporter.ImportedPlayer] {
        parsedPlayers.filter { existingMatchKeys.contains($0.matchKey) }
    }

    private var newPlayers: [RosterImporter.ImportedPlayer] {
        parsedPlayers.filter { !existingMatchKeys.contains($0.matchKey) }
    }

    private var playersToImport: [RosterImporter.ImportedPlayer] {
        skipDuplicates ? newPlayers : parsedPlayers
    }

    private var existingCount: Int { store.players.count }
    private var resultingTotal: Int { existingCount + playersToImport.count }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                summarySection
                if !duplicates.isEmpty {
                    duplicatesToggleSection
                }
                playerListSection
            }
            .navigationTitle("Import Roster")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        Analytics.signal("roster.import.canceled")
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        onImport(playersToImport)
                        dismiss()
                    }
                    .disabled(playersToImport.isEmpty)
                    .bold()
                }
            }
        }
    }

    // MARK: - Sections

    private var summarySection: some View {
        Section {
            HStack {
                Text("From")
                Spacer()
                Text(sourceFilename)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            HStack {
                Text("Players found")
                Spacer()
                Text("\(parsedPlayers.count)")
                    .foregroundColor(.secondary)
            }
            if !duplicates.isEmpty {
                HStack {
                    Text("Duplicates")
                    Spacer()
                    Text("\(duplicates.count)")
                        .foregroundColor(.secondary)
                }
            }
            HStack {
                Text("Will be imported")
                Spacer()
                Text("\(playersToImport.count)")
                    .font(.body.bold())
                    .foregroundColor(.blue)
            }
        } header: {
            Text("Summary")
        } footer: {
            Text("Your team has \(existingCount) \(existingCount == 1 ? "player" : "players"). After import, your roster will have \(resultingTotal).")
        }
    }

    private var duplicatesToggleSection: some View {
        Section {
            Toggle(isOn: $skipDuplicates) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Skip duplicates")
                    Text("Players with the same name as someone already on your roster")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .tint(.blue)
        }
    }

    private var playerListSection: some View {
        Section {
            ForEach(parsedPlayers) { player in
                playerRow(player)
            }
        } header: {
            Text("Players")
        }
    }

    @ViewBuilder
    private func playerRow(_ player: RosterImporter.ImportedPlayer) -> some View {
        let isDup = existingMatchKeys.contains(player.matchKey)
        let willSkip = isDup && skipDuplicates

        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(player.displayName)
                    .foregroundColor(willSkip ? .secondary : .primary)
                if isDup {
                    Text("Already on roster")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            Spacer()
            if !player.jerseyNumber.isEmpty {
                Text("#\(player.jerseyNumber)")
                    .font(.caption.bold())
                    .foregroundColor(willSkip ? Color.secondary.opacity(0.5) : .secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color(.systemGray6)))
            }
        }
        .opacity(willSkip ? 0.5 : 1.0)
    }
}
