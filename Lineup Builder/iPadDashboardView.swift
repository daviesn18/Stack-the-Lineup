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

    // Schedule import state — owned here so the toast can overlay the full screen
    @State private var showingScheduleImport = false
    @State private var scheduleImportToast: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            iPadNavBar(
                selectedTab: $selectedTab,
                showingArchive: $showingArchive,
                showingScheduleImport: $showingScheduleImport,
                scheduleImportToast: $scheduleImportToast
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

                Divider()

                FairPlayRailView()
            }
        }
        .background(Color(.systemBackground))
        // Schedule import sheet — presented from here so it covers the full screen
        .sheet(isPresented: $showingScheduleImport) {
            ScheduleImportView { games, urlString in
                let result = store.mergeScheduledGames(games)
                if let url = urlString {
                    store.setCalendarSubscriptionURL(url)
                }
                let total = result.added + result.updated
                if total == 0 {
                    scheduleImportToast = "Schedule is already up to date."
                    Analytics.signal("schedule.import.already_current")
                } else {
                    var parts: [String] = []
                    if result.added > 0 { parts.append("\(result.added) added") }
                    if result.updated > 0 { parts.append("\(result.updated) updated") }
                    scheduleImportToast = parts.joined(separator: ", ").capitalized + "."
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    scheduleImportToast = nil
                }
            }
            .environmentObject(store)
        }
        // Toast overlay — anchored to the bottom of the full dashboard
        .safeAreaInset(edge: .bottom) {
            if let toast = scheduleImportToast {
                Text(toast)
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color(.label)))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(duration: 0.35), value: scheduleImportToast)
                    .padding(.bottom, 8)
            }
        }
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
    @Binding var showingScheduleImport: Bool
    @Binding var scheduleImportToast: String?

    @State private var showingEditTeam = false
    @State private var showingAddTeam = false
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
        HStack(spacing: 14) {
            // Team switcher
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

            Divider()
                .frame(height: 20)

            // Game context — opponent, date, inning count
            HStack(spacing: 4) {
                if !store.lineup.opponent.isEmpty {
                    Text("vs. \(store.lineup.opponent)")
                        .fontWeight(.medium)
                    Text("·")
                        .foregroundColor(.secondary)
                }
                Text(store.lineup.gameDate, style: .date)
                    .foregroundColor(.secondary)
                Text("·")
                    .foregroundColor(.secondary)
                Text("\(store.lineup.innings.count) innings")
                    .foregroundColor(.secondary)
            }
            .font(.subheadline)

            Spacer()

            // Violation indicator — visual only; details live in the always-on Fair Play rail
            if violationCount > 0 {
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

            // Import schedule — Cmd+Shift+S
            Button {
                showingScheduleImport = true
                Analytics.signal("schedule.import.tapped")
            } label: {
                Image(systemName: "calendar.badge.plus")
                    .font(.title3)
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .help("Import Schedule (Cmd+Shift+S)")

            // Archive game — Cmd+Shift+A
            Button {
                showingArchive = true
            } label: {
                Image(systemName: "archivebox")
                    .font(.title3)
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])
            .help("Archive Game (Cmd+Shift+A)")

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

// MARK: - Fair Play Rail

private struct FairPlayRailView: View {
    @EnvironmentObject var store: LineupStore

    private var activePlayers: [Player] {
        store.lineup.activePlayers(from: store.players)
    }
    private var noInfield: [Player] {
        store.lineup.playersWithoutInfield(players: activePlayers)
    }
    private var noOutfield: [Player] {
        store.lineup.playersWithoutOutfield(players: activePlayers)
    }
    private var underMin: [Player] {
        store.lineup.playersUnderFieldingMinimum(players: activePlayers)
    }
    private var backToBack: [Player] {
        store.lineup.playersWithBackToBackBench(from: store.players)
    }
    private var violationCount: Int {
        noInfield.count + noOutfield.count + underMin.count + backToBack.count + unfilledPositions.count
    }
    private var hasAnyAssignments: Bool {
        store.lineup.innings.contains { !$0.assignments.isEmpty }
    }

    // Unfilled field positions — innings that have at least one assignment but
    // are missing one or more expected positions (e.g. pitcher not filled).
    private var unfilledPositions: [(inning: Int, position: FieldPosition)] {
        guard hasAnyAssignments else { return [] }
        let expected = store.lineup.activeFieldPositions(config: store.fairPlayConfig)
        var result: [(Int, FieldPosition)] = []
        for (i, inning) in store.lineup.innings.enumerated() {
            guard !inning.assignments.isEmpty else { continue }
            let filled = Set(inning.assignments.values)
            for pos in expected where !filled.contains(pos) {
                result.append((i, pos))
            }
        }
        return result
    }

    // Grouped label for the warning card: "P (Innings 6, 7), CF (Inning 4)"
    private var unfilledPositionsSummary: String? {
        let slots = unfilledPositions
        guard !slots.isEmpty else { return nil }
        var byPos: [FieldPosition: [Int]] = [:]
        for (i, pos) in slots { byPos[pos, default: []].append(i + 1) }
        return byPos
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { pos, innings in
                let numbers = innings.sorted().map { "\($0)" }.joined(separator: ", ")
                return innings.count == 1
                    ? "\(pos.rawValue) (Inning \(numbers))"
                    : "\(pos.rawValue) (Innings \(numbers))"
            }
            .joined(separator: ", ")
    }

    // Active players in batting-order sequence, then any unordered active players appended
    private var orderedActivePlayers: [Player] {
        let ordered = store.lineup.orderedPlayers(from: store.players)
        let unordered = activePlayers.filter { p in
            !ordered.contains(where: { $0.id == p.id })
        }
        return ordered + unordered
    }

    private func infieldCount(for player: Player) -> Int {
        store.lineup.innings.filter { inning in
            guard let pos = inning.assignments[player.id] else { return false }
            return pos.isInfield
        }.count
    }

    private func outfieldCount(for player: Player) -> Int {
        store.lineup.innings.filter { inning in
            guard let pos = inning.assignments[player.id] else { return false }
            return pos.isOutfield
        }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Header
            VStack(alignment: .leading, spacing: 3) {
                Text("Fair play")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.primary)
                Text("Live as you build the lineup")
                    .font(.system(size: 12.5))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            // Status pill
            FairPlayStatusPill(
                violationCount: violationCount,
                hasAnyAssignments: hasAnyAssignments
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            // Inline warning cards
            if hasAnyAssignments {
                FairPlayInlineWarnings(
                    noInfield: noInfield,
                    noOutfield: noOutfield,
                    underMin: underMin,
                    backToBack: backToBack,
                    unfilledSummary: unfilledPositionsSummary
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }

            Divider()
                .padding(.horizontal, 16)

            // Playing time section header + legend
            HStack {
                Text("Playing Time".uppercased())
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                    .kerning(0.4)
                Spacer()
                HStack(spacing: 10) {
                    FairPlayLegendChip(color: .blue, label: "Infield")
                    FairPlayLegendChip(color: .green, label: "Outfield")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            // Per-player equity bars
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(orderedActivePlayers) { player in
                        FairPlayEquityRow(
                            player: player,
                            infieldCount: infieldCount(for: player),
                            outfieldCount: outfieldCount(for: player),
                            totalInnings: store.lineup.innings.count,
                            missingInfield: noInfield.contains(where: { $0.id == player.id }),
                            missingOutfield: noOutfield.contains(where: { $0.id == player.id })
                        )
                        Divider()
                            .padding(.leading, 16)
                    }
                }
            }
        }
        .frame(width: 280)
        .background(Color(.systemBackground))
    }
}

// MARK: - Fair Play Status Pill

private struct FairPlayStatusPill: View {
    let violationCount: Int
    let hasAnyAssignments: Bool

    var body: some View {
        let showIssues = violationCount > 0 && hasAnyAssignments
        let icon = showIssues ? "exclamationmark.triangle.fill" : "checkmark.shield.fill"
        let tint: Color = showIssues ? .orange : .green
        let label = showIssues
            ? "\(violationCount) fair-play \(violationCount == 1 ? "issue" : "issues")"
            : "Fair play: all clear"

        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(tint)
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(tint)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Fair Play Inline Warnings

private struct FairPlayInlineWarnings: View {
    let noInfield: [Player]
    let noOutfield: [Player]
    let underMin: [Player]
    let backToBack: [Player]
    let unfilledSummary: String?

    private var allClear: Bool {
        noInfield.isEmpty && noOutfield.isEmpty && underMin.isEmpty
            && backToBack.isEmpty && unfilledSummary == nil
    }

    var body: some View {
        VStack(spacing: 7) {
            if allClear {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.green)
                    Text("Every player has a fair shot. No issues to fix.")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 9))
            } else {
                if let summary = unfilledSummary {
                    FairPlayWarningCard(
                        color: .red,
                        title: "Positions not filled",
                        detail: summary
                    )
                }
                if !noOutfield.isEmpty {
                    FairPlayWarningCard(
                        color: .orange,
                        title: "Missing outfield inning",
                        detail: noOutfield.map { $0.firstName }.joined(separator: ", ")
                    )
                }
                if !noInfield.isEmpty {
                    FairPlayWarningCard(
                        color: .orange,
                        title: "Missing infield inning",
                        detail: noInfield.map { $0.firstName }.joined(separator: ", ")
                    )
                }
                if !backToBack.isEmpty {
                    FairPlayWarningCard(
                        color: .red,
                        title: "Back-to-back bench",
                        detail: backToBack.map { $0.firstName }.joined(separator: ", ")
                    )
                }
                if !underMin.isEmpty {
                    FairPlayWarningCard(
                        color: .orange,
                        title: "Under minimum innings fielded",
                        detail: underMin.map { $0.firstName }.joined(separator: ", ")
                    )
                }
            }
        }
    }
}

// MARK: - Fair Play Warning Card

private struct FairPlayWarningCard: View {
    let color: Color
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13))
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
            Text(detail)
                .font(.system(size: 12.5))
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color == .red ? Color.red.opacity(0.07) : Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }
}

// MARK: - Fair Play Equity Row

private struct FairPlayEquityRow: View {
    let player: Player
    let infieldCount: Int
    let outfieldCount: Int
    let totalInnings: Int
    let missingInfield: Bool
    let missingOutfield: Bool

    private var fieldedCount: Int { infieldCount + outfieldCount }
    private var hasViolation: Bool { missingInfield || missingOutfield }

    var body: some View {
        HStack(spacing: 10) {
            // Player first name — fixed width, truncates
            Text(player.firstName)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)
                .frame(width: 64, alignment: .leading)

            // Stacked infield (blue) + outfield (green) bar on a gray track
            GeometryReader { geo in
                let w = geo.size.width
                let ifFrac = totalInnings > 0 ? CGFloat(infieldCount) / CGFloat(totalInnings) : 0
                let ofFrac = totalInnings > 0 ? CGFloat(outfieldCount) / CGFloat(totalInnings) : 0

                ZStack(alignment: .leading) {
                    // Gray track
                    Rectangle()
                        .fill(Color(.systemGray5))

                    // Infield segment (blue)
                    if infieldCount > 0 {
                        Rectangle()
                            .fill(Color.blue)
                            .frame(width: w * ifFrac)
                    }

                    // Outfield segment (green) — stacked after infield
                    if outfieldCount > 0 {
                        Rectangle()
                            .fill(Color.green)
                            .frame(width: w * ofFrac)
                            .offset(x: w * ifFrac)
                    }
                }
                .frame(height: 14)
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .frame(height: 14)

            // Count + optional violation dot
            HStack(spacing: 5) {
                HStack(spacing: 1) {
                    Text("\(fieldedCount)")
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundColor(.secondary)
                    Text("/\(totalInnings)")
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundColor(Color(.tertiaryLabel))
                }
                // Dot color indicates which coverage is missing;
                // red ring signals it is a violation
                if hasViolation {
                    Circle()
                        .fill(missingInfield ? Color.blue : Color.green)
                        .frame(width: 7, height: 7)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.red, lineWidth: 1.5)
                                .frame(width: 10, height: 10)
                        )
                }
            }
            .frame(width: 50, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Fair Play Legend Chip

private struct FairPlayLegendChip: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Sidebar Roster View

struct SidebarRosterView: View {
    @EnvironmentObject var store: LineupStore
    @EnvironmentObject var purchaseManager: PurchaseManager
    @Binding var battingOrderExpanded: Bool
    @State private var showingAddPlayer = false
    @State private var showingBulkAdd = false

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

                // Menu exposes both add options; Cmd+N shortcut on Add Player
                Menu {
                    Button {
                        showingAddPlayer = true
                    } label: {
                        Label("Add Player", systemImage: "person.badge.plus")
                    }
                    .keyboardShortcut("n", modifiers: .command)

                    Button {
                        showingBulkAdd = true
                    } label: {
                        Label("Bulk Add from List", systemImage: "text.alignleft")
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundColor(.blue)
                }
                .accessibilityLabel("Add Players")
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
        .sheet(isPresented: $showingBulkAdd) {
            BulkAddPlayersView()
                .environmentObject(store)
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
    @State private var showingAutoFillIncomplete = false
    @State private var autoFillIncompleteMessage: String = ""

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

                // Hidden keyboard shortcut buttons for Cmd+1 through Cmd+4
                // These sit at the end of the tab bar and are invisible to the user.
                Group {
                    Button("") { selectedTab = .players }
                        .keyboardShortcut("1", modifiers: .command)
                        .help("Players (Cmd+1)")
                    Button("") { selectedTab = .lineup }
                        .keyboardShortcut("2", modifiers: .command)
                        .help("Lineup (Cmd+2)")
                    Button("") { selectedTab = .positions }
                        .keyboardShortcut("3", modifiers: .command)
                        .help("Positions (Cmd+3)")
                    Button("") { selectedTab = .history }
                        .keyboardShortcut("4", modifiers: .command)
                        .help("History (Cmd+4)")
                }
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
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
                                    preferences: prefs,
                                    config: store.fairPlayConfig,
                                    pitchingConfig: store.pitchingConfig,
                                    gameLogs: store.gameLogs
                                )
                                if result.filledCount > 0 {
                                    store.activeTeam.lineup = result.lineup
                                    store.save()
                                }
                                if result.hasUnfilledSlots,
                                   let message = result.incompleteMessage(multiInning: true) {
                                    autoFillIncompleteMessage = message
                                    showingAutoFillIncomplete = true
                                }
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
        .alert("Some Positions Not Filled", isPresented: $showingAutoFillIncomplete) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(autoFillIncompleteMessage)
        }
    }
}
