import SwiftUI

// MARK: - Detail Tab

enum DetailTab: String, CaseIterable {
    case players   = "Players"
    case lineup    = "Lineup"
    case positions = "Positions"
    case history   = "History"
}

// MARK: - iPad Dashboard View

struct iPadDashboardView: View {
    @EnvironmentObject var store: LineupStore
    @EnvironmentObject var purchaseManager: PurchaseManager
    @Binding var showingArchive: Bool

    @State private var selectedTab: DetailTab = .players
    @State private var showingArchiveSheet = false
    @State private var showingAutoFillPopover = false
    @AppStorage("ipadBattingOrderExpanded") private var battingOrderExpanded: Bool = true

    // AutoFill state — passed through to PositionSummaryView
    @State private var showingPositionAutoFill = false

    var body: some View {
        VStack(spacing: 0) {
            iPadNavBar(
                selectedTab: $selectedTab,
                showingArchive: $showingArchive
            )

            Divider()

            HStack(spacing: 0) {
                SidebarRosterView(
                    battingOrderExpanded: $battingOrderExpanded
                )

                Divider()

                DetailPaneView(
                    selectedTab: $selectedTab,
                    showingAutoFillPopover: $showingPositionAutoFill,
                    showingArchive: $showingArchive
                )
            }
        }
        .background(Color(.systemBackground))
        .onAppear {
            Analytics.signal("ipad.dashboard.opened", parameters: [
                "playerCount": "\(store.players.count)"
            ])
        }
    }
}

// MARK: - Nav Bar

private struct iPadNavBar: View {
    @EnvironmentObject var store: LineupStore
    @EnvironmentObject var purchaseManager: PurchaseManager
    @Binding var selectedTab: DetailTab
    @Binding var showingArchive: Bool
    @State private var showingEditTeam = false
    @State private var showingAddTeam = false
    @State private var showingWarnings = false
    @State private var showingSettings = false

    private var violationCount: Int {
        let active = store.lineup.activePlayers(from: store.players)
        let backToBack = store.lineup.playersWithBackToBackBench(from: store.players)
        return store.lineup.playersWithoutInfield(players: active).count
             + store.lineup.playersWithoutOutfield(players: active).count
             + store.lineup.playersUnderFieldingMinimum(players: active).count
             + backToBack.count
    }

    var body: some View {
        HStack(spacing: 16) {
            Menu {
                if store.teams.count > 1 {
                    Section("Switch Team") {
                        ForEach(store.teams) { team in
                            Button {
                                store.switchTeam(to: team.id)
                            } label: {
                                HStack {
                                    Text(team.name.isEmpty ? "Unnamed Team" : team.name)
                                    if team.id == store.activeTeamID {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                }
                Button {
                    showingEditTeam = true
                } label: {
                    Label("Edit Team", systemImage: "pencil")
                }
                Button {
                    showingAddTeam = true
                } label: {
                    Label("Add Team", systemImage: "plus")
                }
            } label: {
                HStack(spacing: 4) {
                    Text(store.teamName.isEmpty ? "My Team" : store.teamName)
                        .font(.headline)
                    Image(systemName: "chevron.down")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if violationCount > 0 {
                Button {
                    showingWarnings = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption.bold())
                        Text("\(violationCount)")
                            .font(.caption.bold())
                    }
                    .foregroundColor(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(Capsule())
                }
                .popover(isPresented: $showingWarnings, arrowEdge: .top) {
                    FairPlayWarningsSheet()
                        .environmentObject(store)
                        .frame(minWidth: 320, minHeight: 300)
                        .presentationCompactAdaptation(.popover)
                }
            }

            Button {
                showingArchive = true
            } label: {
                Image(systemName: "archivebox")
                    .font(.title3)
            }

            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.title3)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
        .sheet(isPresented: $showingEditTeam) {
            TeamFormView(mode: .edit(store.activeTeamID ?? UUID()))
                .environmentObject(store)
                .environmentObject(purchaseManager)
        }
        .sheet(isPresented: $showingAddTeam) {
            TeamFormView(mode: .add)
                .environmentObject(store)
                .environmentObject(purchaseManager)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(store)
                .environmentObject(purchaseManager)
        }
    }
}

// MARK: - Fair Play Warnings Sheet

private struct FairPlayWarningsSheet: View {
    @EnvironmentObject var store: LineupStore
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            let active     = store.lineup.activePlayers(from: store.players)
            let noInfield  = store.lineup.playersWithoutInfield(players: active)
            let noOutfield = store.lineup.playersWithoutOutfield(players: active)
            let underMin   = store.lineup.playersUnderFieldingMinimum(players: active)
            let backToBack = store.lineup.playersWithBackToBackBench(from: store.players)

            List {
                if !noInfield.isEmpty {
                    Section {
                        ForEach(noInfield) { p in Text(p.displayName) }
                    } header: {
                        Label("Missing Infield Inning", systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                    }
                }
                if !noOutfield.isEmpty {
                    Section {
                        ForEach(noOutfield) { p in Text(p.displayName) }
                    } header: {
                        Label("Missing Outfield Inning", systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                    }
                }
                if !backToBack.isEmpty {
                    Section {
                        ForEach(backToBack) { p in Text(p.displayName) }
                    } header: {
                        Label("Back-to-Back Bench", systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                    }
                }
                if !underMin.isEmpty {
                    Section {
                        ForEach(underMin) { p in Text(p.displayName) }
                    } header: {
                        Label("Under 4 Innings Fielded", systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                    }
                }
            }
            .navigationTitle("Fair Play Warnings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Sidebar Roster View

struct SidebarRosterView: View {
    @EnvironmentObject var store: LineupStore
    @EnvironmentObject var purchaseManager: PurchaseManager
    @Binding var battingOrderExpanded: Bool
    @State private var showingAddPlayer = false

    private var orderedPlayers: [Player] {
        store.lineup.orderedPlayers(from: store.players)
    }
    private var unorderedPlayers: [Player] {
        store.lineup.activePlayers(from: store.players)
            .filter { !store.lineup.battingOrder.contains($0.id) }
    }
    private var absentPlayers: [Player] {
        store.players.filter { store.lineup.isAbsent($0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Roster")
                    .font(.subheadline.bold())
                Spacer()
                Text("\(store.lineup.activePlayers(from: store.players).count) active")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button { showingAddPlayer = true } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundColor(.blue)
                }
                .accessibilityLabel("Add Player")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(.systemBackground))

            Divider()

            List {
                Section {
                    if battingOrderExpanded {
                        ForEach(Array(orderedPlayers.enumerated()), id: \.element.id) { index, player in
                            SidebarPlayerRow(player: player, battingIndex: index + 1)
                        }
                        .onMove { from, to in
                            store.moveBattingOrder(from: from, to: to)
                        }

                        ForEach(unorderedPlayers) { player in
                            SidebarPlayerRow(player: player, battingIndex: nil)
                        }
                    }
                } header: {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            battingOrderExpanded.toggle()
                        }
                        Analytics.signal("ipad.batting.order.toggled", parameters: [
                            "expanded": battingOrderExpanded ? "true" : "false"
                        ])
                    } label: {
                        HStack {
                            Text("Batting Order")
                            Spacer()
                            if !battingOrderExpanded {
                                Text("\(orderedPlayers.count + unorderedPlayers.count) players")
                            }
                            Image(systemName: battingOrderExpanded ? "chevron.down" : "chevron.right")
                        }
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                    }
                    .buttonStyle(.plain)
                }

                Section {
                    Text("Use the Lineup tab to mark players absent or available.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    ForEach(absentPlayers) { player in
                        SidebarPlayerRow(player: player, battingIndex: nil, isAbsent: true)
                    }
                } header: {
                    Text("Absent")
                }

                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 12) {
                            legendItem("S", "Strength", .green)
                            legendItem("C", "Capable", .blue)
                        }
                        HStack(spacing: 12) {
                            legendItem("E", "Emergency", .orange)
                            legendItem("N", "Never", .red)
                        }
                    }
                    .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.lineup.opponent.isEmpty ? "No opponent set" : "vs. \(store.lineup.opponent)")
                            .font(.caption.bold())
                            .foregroundColor(store.lineup.opponent.isEmpty ? .secondary : .primary)
                        HStack(spacing: 4) {
                            Text(store.lineup.gameDate, style: .date)
                            Text("·")
                            Text("\(store.lineup.innings.count) innings")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 2)
                } header: {
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 10))
                        Text("Colored tags show position preferences")
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .textCase(nil)
                }
            }
            .listStyle(.insetGrouped)
            .environment(\.editMode, .constant(.active))
        }
        .frame(width: 260)
        .sheet(isPresented: $showingAddPlayer) {
            PlayerFormView(mode: .add)
                .environmentObject(store)
                .environmentObject(purchaseManager)
        }
    }

    private func legendItem(_ letter: String, _ name: String, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Text(letter)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(color)
            Text(name)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .fixedSize()
        }
    }
}

// MARK: - Sidebar Player Row

private struct SidebarPlayerRow: View {
    @EnvironmentObject var store: LineupStore
    let player: Player
    var battingIndex: Int?
    var isAbsent: Bool = false

    private var preferencePills: [(String, Color)] {
        let prefs = player.positionPreferences
        guard !prefs.isEmpty else { return [] }
        var pills: [(String, Color, Int)] = []
        for (pos, tier) in prefs {
            let order: Int
            switch tier {
            case .strength:  order = 0
            case .capable:   order = 1
            case .never:     order = 2
            case .emergency: order = 3
            }
            pills.append((pos.rawValue, tier.color, order))
        }
        return pills.sorted { $0.2 < $1.2 }.prefix(3).map { ($0.0, $0.1) }
    }

    var body: some View {
        HStack(spacing: 8) {
            if let idx = battingIndex {
                Text("\(idx)")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                    .frame(width: 18, alignment: .trailing)
            } else if isAbsent {
                Image(systemName: "minus.circle")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 18)
            } else {
                Image(systemName: "circle")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 18)
            }

            Text(player.displayName)
                .font(.subheadline)
                .foregroundColor(isAbsent ? .secondary : .primary)
                .strikethrough(isAbsent)
                .lineLimit(1)

            Spacer(minLength: 4)

            if !preferencePills.isEmpty && !isAbsent {
                HStack(spacing: 3) {
                    ForEach(preferencePills.prefix(3), id: \.0) { posName, color in
                        Text(posName)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(color)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(color.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                            .fixedSize()
                    }
                }
                .lineLimit(1)
            }
        }
        .opacity(isAbsent ? 0.6 : 1.0)
    }
}

// MARK: - Detail Pane View

struct DetailPaneView: View {
    @EnvironmentObject var store: LineupStore
    @EnvironmentObject var purchaseManager: PurchaseManager
    @Binding var selectedTab: DetailTab
    @Binding var showingAutoFillPopover: Bool
    @Binding var showingArchive: Bool

    @State private var fillThroughInning: Int = 6
    @State private var showingClearAllConfirm = false

    private var smartDefaultLastInning: Int {
        for i in stride(from: store.lineup.innings.count - 1, through: 0, by: -1) {
            if !store.lineup.innings[i].assignments.isEmpty { return i }
        }
        return store.lineup.innings.count - 1
    }

    private var hasAnyAssignments: Bool {
        store.lineup.innings.contains { !$0.assignments.isEmpty }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab selector
            HStack(spacing: 0) {
                ForEach(DetailTab.allCases, id: \.self) { tab in
                    Button {
                        selectedTab = tab
                        Analytics.signal("ipad.detail.tab.changed", parameters: ["tab": tab.rawValue])
                    } label: {
                        Text(tab.rawValue)
                            .font(.subheadline)
                            .fontWeight(selectedTab == tab ? .semibold : .regular)
                            .foregroundColor(selectedTab == tab ? .primary : .secondary)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(
                                selectedTab == tab
                                    ? Color(.systemBackground)
                                    : Color(.systemGray6)
                            )
                    }
                    .buttonStyle(.plain)

                    if tab != DetailTab.allCases.last {
                        Divider()
                            .frame(height: 36)
                    }
                }
                Spacer()
            }
            .background(Color(.systemGray6))
            .overlay(alignment: .bottom) { Divider() }

            // Content
            Group {
                switch selectedTab {
                case .positions:
                    VStack(spacing: 0) {
                        // Status strip — same as iPhone
                        LineupStatusStrip(
                            status: store.lineup.status,
                            onFinalize: { store.finalizeLineup() },
                            onReopen: { store.reopenLineup() }
                        )

                        PositionSummaryView(
                            onAutoFill: {
                                showingAutoFillPopover = true
                            },
                            showingAutoFillPopover: $showingAutoFillPopover,
                            onFillThrough: { lastInning in
                                let prefs = Dictionary(
                                    uniqueKeysWithValues: store.players.map { ($0.id, $0.positionPreferences) }
                                )
                                let result = AutoFillEngine.fillInnings(
                                    through: lastInning,
                                    in: store.lineup,
                                    players: store.players,
                                    preferences: prefs
                                )
                                store.activeTeam.lineup = result.lineup
                                store.save()
                            },
                            smartDefaultLastInning: smartDefaultLastInning
                        )

                        // Clear positions button — summary-only context, clears all innings
                        if hasAnyAssignments {
                            HStack {
                                Spacer()
                                Button {
                                    showingClearAllConfirm = true
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "xmark.circle")
                                            .font(.caption.bold())
                                        Text("Clear positions")
                                            .font(.caption.bold())
                                    }
                                    .foregroundColor(Color(red: 0.89, green: 0.29, blue: 0.29))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 7)
                                    .background(Color(red: 0.99, green: 0.92, blue: 0.92))
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .strokeBorder(Color(red: 0.94, green: 0.58, blue: 0.58), lineWidth: 0.5)
                                    )
                                }
                                .buttonStyle(.plain)
                                Spacer()
                            }
                            .padding(.vertical, 10)
                            .background(Color(.systemBackground))
                            .overlay(
                                Rectangle()
                                    .frame(height: 0.5)
                                    .foregroundColor(Color(.separator)),
                                alignment: .top
                            )
                        }
                    }

                case .lineup:
                    LineupView(
                        showingArchive: $showingArchive,
                        showingDragTip: .constant(false),
                        showingArchiveTip: .constant(false)
                    )

                case .players:
                    PlayersView(showingTabTip: .constant(false))

                case .history:
                    GameLogsView(showingTabTip: .constant(false))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .alert("Clear all positions?", isPresented: $showingClearAllConfirm) {
            Button("Clear", role: .destructive) {
                store.clearPositions()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All inning assignments will be removed. This can't be undone.")
        }
    }
}
