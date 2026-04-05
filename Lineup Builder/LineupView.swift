import SwiftUI

struct LineupView: View {
    @EnvironmentObject var store: LineupStore
    @AppStorage("complianceChecksEnabled") private var complianceChecksEnabled = true
    @State private var showingClearOptions = false
    @State private var showingSaveConfirmation = false
    @State private var generatedPDF: PDFDocument? = nil
    @Binding var showingArchive: Bool
    @State private var showingTips = false

    // Ordered active players
    var orderedPlayers: [Player] {
        store.lineup.orderedPlayers(from: store.players)
    }

    // Active players not yet in batting order
    var unorderedPlayers: [Player] {
        store.lineup.activePlayers(from: store.players)
            .filter { !store.lineup.battingOrder.contains($0.id) }
    }

    // Absent players
    var absentPlayers: [Player] {
        store.players.filter { store.lineup.isAbsent($0) }
    }

    var body: some View {
        NavigationStack {
            Form {
                // Game Info
                Section("Game Info") {
                    DatePicker("Game Date", selection: $store.lineup.gameDate, displayedComponents: .date)
                    HStack {
                        Text("Opponent")
                        Spacer()
                        TextField("Opponent Name", text: $store.lineup.opponent)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                    }
                }

                // Unified Roster Section
                Section {
                    // 1. Ordered active players (numbered, draggable)
                    ForEach(Array(orderedPlayers.enumerated()), id: \.element.id) { index, player in
                        RosterRow(player: player, index: index + 1)
                    }
                    .onMove { from, to in
                        store.lineup.battingOrder.move(fromOffsets: from, toOffset: to)
                    }

                    // 2. Active players not yet in batting order
                    ForEach(unorderedPlayers) { player in
                        RosterRow(player: player, index: nil, onAdd: {
                            store.lineup.battingOrder.append(player.id)
                        })
                    }

                    // 3. Absent players — grayed out at the bottom
                    ForEach(absentPlayers) { player in
                        RosterRow(player: player, index: nil, isAbsent: true)
                    }

                } header: {
                    HStack {
                        Text("Batting Order & Availability")
                        Spacer()
                        if !orderedPlayers.isEmpty {
                            EditButton()
                                .font(.caption)
                        }
                    }
                } footer: {
                    if !unorderedPlayers.isEmpty {
                        Text("Tap + to add players to the batting order, then drag to reorder.")
                    } else if store.players.isEmpty {
                        Text("No players added yet. Go to the Players tab to add your roster.")
                    }
                }

                // Fair Play Rules
                complianceSection

                // Actions
                Section {
                    Button {
                        store.save()
                        showingSaveConfirmation = true
                    } label: {
                        Label("Save Lineup", systemImage: "icloud.and.arrow.up")
                    }

                    Button {
                        let doc = PDFGenerator.generate(type: .battingOrder, lineup: store.lineup, players: store.players, teamName: store.teamName, teamColor: store.teamColor, showFairPlayRules: complianceChecksEnabled)
                        generatedPDF = doc
                    } label: {
                        Label("Export Batting Order PDF", systemImage: "doc.text")
                    }

                    Button {
                        let doc = PDFGenerator.generate(type: .coachesGuide, lineup: store.lineup, players: store.players, teamName: store.teamName, teamColor: store.teamColor, showFairPlayRules: complianceChecksEnabled)
                        generatedPDF = doc
                    } label: {
                        Label("Export Coaches Guide PDF", systemImage: "doc.richtext")
                    }

                    Button(role: .destructive) {
                        showingClearOptions = true
                    } label: {
                        Label("Clear Lineup...", systemImage: "trash")
                    }
                    .confirmationDialog("Clear Options", isPresented: $showingClearOptions, titleVisibility: .visible) {
                        Button("Clear Positions Only", role: .destructive) { store.clearPositions() }
                        Button("Clear Batting Order Only", role: .destructive) { store.clearBattingOrder() }
                        Button("Clear Both", role: .destructive) { store.clearAll() }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("What would you like to clear?")
                    }
                }
            }
            .navigationTitle("Lineup Builder")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        Button {
                            showingTips = true
                        } label: {
                            Image(systemName: "info.circle")
                        }
                        Button {
                            showingArchive = true
                        } label: {
                            Label("Archive Game", systemImage: "archivebox")
                        }
                    }
                }
            }
            .alert("Saved!", isPresented: $showingSaveConfirmation) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Your lineup has been saved.")
            }
            .sheet(item: $generatedPDF) { pdf in
                PDFPreviewView(document: pdf)
            }
            .sheet(isPresented: $showingTips) {
                PageTipsView(page: .lineup)
            }
        }
    }

    // MARK: - Fair Play Rules Section

    @ViewBuilder
    var complianceSection: some View {
        if complianceChecksEnabled {
            let activePlayers = store.lineup.activePlayers(from: store.players)
            let noInfield = store.lineup.playersWithoutInfield(players: activePlayers)
            let noOutfield = store.lineup.playersWithoutOutfield(players: activePlayers)

            if !noInfield.isEmpty || !noOutfield.isEmpty {
                Section(header: ComplianceRulesHeader(title: "Fair Play Warnings")) {
                    if !noInfield.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Missing Infield Inning", systemImage: "exclamationmark.triangle.fill")
                                .font(.subheadline.bold())
                                .foregroundColor(.orange)
                            ForEach(noInfield) { player in
                                Text("• \(player.displayName)")
                                    .font(.callout)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    if !noOutfield.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Missing Outfield Inning", systemImage: "exclamationmark.triangle.fill")
                                .font(.subheadline.bold())
                                .foregroundColor(.orange)
                            ForEach(noOutfield) { player in
                                Text("• \(player.displayName)")
                                    .font(.callout)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            } else if !activePlayers.isEmpty && store.lineup.innings.contains(where: { !$0.assignments.isEmpty }) {
                Section(header: ComplianceRulesHeader(title: "Fair Play Rules")) {
                    Label("All active players meet infield & outfield requirements", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.subheadline)
                }
            }
        }
    }
}

// MARK: - Roster Row

struct RosterRow: View {
    @EnvironmentObject var store: LineupStore
    let player: Player
    let index: Int?           // nil = not yet in batting order
    var isAbsent: Bool = false
    var onAdd: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            // Batting number or placeholder
            Group {
                if let i = index {
                    Text("\(i).")
                        .font(.headline)
                        .foregroundColor(isAbsent ? .secondary : .primary)
                } else if !isAbsent {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.green)
                        .font(.title3)
                        .onTapGesture { onAdd?() }
                } else {
                    Image(systemName: "minus.circle")
                        .foregroundColor(.secondary)
                        .font(.title3)
                }
            }
            .frame(width: 32, alignment: .leading)

            // Name
            Text(player.displayName)
                .foregroundColor(isAbsent ? .secondary : .primary)
                .strikethrough(isAbsent)

            Spacer()

            // Jersey (only show if number exists)
            if !player.number.isEmpty {
                Text("#\(player.number)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Availability toggle
            Toggle("", isOn: Binding(
                get: { !store.lineup.isAbsent(player) },
                set: { _ in
                    store.lineup.toggleAbsent(player: player)
                    store.save()
                }
            ))
            .labelsHidden()
            .tint(.green)
        }
        .opacity(isAbsent ? 0.5 : 1.0)
    }
}

// MARK: - Shared Fair Play Rules Tooltip

struct ComplianceRulesHeader: View {
    let title: String
    @State private var showingInfo = false

    var body: some View {
        HStack {
            Text(title)
            Button {
                showingInfo = true
            } label: {
                Image(systemName: "info.circle")
                    .foregroundColor(.blue)
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .alert("Lineup Rules", isPresented: $showingInfo) {
            Button("Got it", role: .cancel) {}
        } message: {
            Text("""
Every player must play at least 1 inning in the infield (P, C, 1B, 2B, 3B, SS).

Every player must play at least 1 inning in the outfield (LF, CF, RF).

No player should sit the bench for 2 consecutive innings.
""")
        }
    }
}
