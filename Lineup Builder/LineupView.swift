import SwiftUI

struct LineupView: View {
    @EnvironmentObject var store: LineupStore
    @EnvironmentObject var purchaseManager: PurchaseManager
    @AppStorage("complianceChecksEnabled") private var complianceChecksEnabled = true
    @State private var showingClearOptions = false
    @State private var showingSaveConfirmation = false
    @State private var generatedPDF: PDFDocument? = nil
    @Binding var showingArchive: Bool
    @State private var showingTips = false
    @State private var showingPaywall = false
    @State private var lockedPDF: PDFDocument? = nil

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
                    DatePicker("Game Date", selection: Binding(
                        get: { store.lineup.gameDate },
                        set: { store.updateGameDate($0) }
                    ), displayedComponents: .date)
                    HStack {
                        Text("Opponent")
                        Spacer()
                        TextField("Opponent Name", text: Binding(
                            get: { store.lineup.opponent },
                            set: { store.updateOpponent($0) }
                        ))
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
                        store.moveBattingOrder(from: from, to: to)
                    }

                    // 2. Active players not yet in batting order
                    ForEach(unorderedPlayers) { player in
                        RosterRow(player: player, index: nil, onAdd: {
                            store.addToBattingOrder(player: player)
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

                    // Free — Batting Order PDF
                    Button {
                        let doc = PDFGenerator.generate(
                            type: .battingOrder,
                            lineup: store.lineup,
                            players: store.players,
                            teamName: store.teamName,
                            teamColor: store.teamColor,
                            showFairPlayRules: complianceChecksEnabled
                        )
                        generatedPDF = doc
                        Analytics.signal("pdf.exported", parameters: ["type": "battingOrder"])
                    } label: {
                        Label("Export Batting Order PDF", systemImage: "doc.text")
                    }

                    // Pro — Coaches Guide PDF
                    // Always generates the real PDF; free users see it blurred
                    // in LockedPDFPreviewView as a preview to entice purchase.
                    Button {
                        let doc = PDFGenerator.generate(
                            type: .coachesGuide,
                            lineup: store.lineup,
                            players: store.players,
                            teamName: store.teamName,
                            teamColor: store.teamColor,
                            showFairPlayRules: complianceChecksEnabled
                        )
                        if purchaseManager.isPro {
                            generatedPDF = doc
                            Analytics.signal("pdf.exported", parameters: ["type": "coachesGuide"])
                        } else {
                            lockedPDF = doc
                        }
                    } label: {
                        HStack {
                            Label("Export Coaches Guide PDF", systemImage: "doc.richtext")
                            Spacer()
                            if !purchaseManager.isPro {
                                ProBadge()
                            }
                        }
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
            .sheet(item: $lockedPDF) { pdf in
                LockedPDFPreviewView(document: pdf)
                    .environmentObject(purchaseManager)
            }
            // When purchase completes inside LockedPDFPreviewView it dismisses
            // itself and flips isPro — we re-present the real PDF immediately.
            .onChange(of: purchaseManager.isPro) { _, isPro in
                if isPro, let pdf = lockedPDF {
                    lockedPDF = nil
                    generatedPDF = pdf
                }
            }
            .sheet(isPresented: $showingTips) {
                PageTipsView(page: .lineup)
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
                    .environmentObject(purchaseManager)
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
            let underMinimum = store.lineup.playersUnderFieldingMinimum(players: activePlayers)

            if !noInfield.isEmpty || !noOutfield.isEmpty || !underMinimum.isEmpty {
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
                    if !underMinimum.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Under 4 Innings Fielded", systemImage: "exclamationmark.triangle.fill")
                                .font(.subheadline.bold())
                                .foregroundColor(.orange)
                            ForEach(underMinimum) { player in
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
                set: { _ in store.toggleAbsent(player: player) }
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

Every player must field for at least 4 innings across the game. Players with any ABS innings are exempt from this rule.

Assign ABS to innings when a player arrives late or leaves early — they still need 1 infield and 1 outfield inning among the innings they do play.
""")
        }
    }
}

// MARK: - Pro Badge
// Small reusable label shown next to Pro-gated features.

struct ProBadge: View {
    var body: some View {
        Text("PRO")
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.blue)
            .cornerRadius(5)
    }
}
