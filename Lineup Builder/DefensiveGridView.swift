import SwiftUI

struct DefensiveGridView: View {
    @EnvironmentObject var store: LineupStore
    @State private var selectedInning: Int = 0
    @State private var selectedPlayer: Player? = nil
    @State private var showingWarnings = false
    @State private var showingSummary = false
    @Binding var showingArchive: Bool
    @State private var showingTips = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if showingSummary {
                    PositionSummaryView()
                } else {
                    // Inning Selector
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(0..<7, id: \.self) { inning in
                                Button {
                                    selectedInning = inning
                                } label: {
                                    VStack(spacing: 2) {
                                        Text("Inn \(inning + 1)")
                                            .font(.callout.bold())
                                        inningStatusDot(inning: inning)
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(selectedInning == inning ? Color.blue : Color(.systemGray5))
                                    .foregroundColor(selectedInning == inning ? .white : .primary)
                                    .cornerRadius(10)
                                }
                            }
                        }
                        .padding()
                    }

                    Divider()

                    if store.players.isEmpty {
                        ContentUnavailableView(
                            "No Players",
                            systemImage: "person.badge.plus",
                            description: Text("Add players on the Players tab first.")
                        )
                    } else {
                        List {
                            ForEach(displayPlayers) { player in
                                PlayerInningRow(
                                    player: player,
                                    inning: selectedInning,
                                    onTap: {
                                        selectedPlayer = player
                                    }
                                )
                            }
                        }
                        .listStyle(.plain)
                    }
                }
            }
            .navigationTitle(showingSummary ? "Position Summary" : "Inning \(selectedInning + 1) Positions")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        withAnimation {
                            showingSummary.toggle()
                        }
                    } label: {
                        Label(
                            showingSummary ? "By Inning" : "Summary",
                            systemImage: showingSummary ? "list.bullet" : "tablecells"
                        )
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 4) {
                        Button {
                            showingWarnings = true
                        } label: {
                            warningsToolbarLabel
                        }
                        Button {
                            showingArchive = true
                        } label: {
                            Label("Archive Game", systemImage: "archivebox")
                        }
                        Button {
                            showingTips = true
                        } label: {
                            Image(systemName: "info.circle")
                        }
                    }
                }
            }
            .sheet(item: $selectedPlayer) { player in
                PositionPickerView(player: player, inning: selectedInning)
            }
            .sheet(isPresented: $showingWarnings) {
                WarningsView(inning: selectedInning)
            }
            .sheet(isPresented: $showingTips) {
                PageTipsView(page: .positions)
            }
        }
    }

    // MARK: - Warnings Button

    @ViewBuilder
    var warningsToolbarLabel: some View {
        let inningIssues = currentInningIssueCount
        let gameIssues = gameWideIssueCount

        if inningIssues > 0 && gameIssues > 0 {
            Label("Issues (\(inningIssues + gameIssues))", systemImage: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
        } else if inningIssues > 0 {
            Label("Inning Issues (\(inningIssues))", systemImage: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
        } else if gameIssues > 0 {
            Label("Game Issues (\(gameIssues))", systemImage: "exclamationmark.circle.fill")
                .foregroundColor(.orange)
        } else {
            Label("All Good", systemImage: "checkmark.shield.fill")
                .foregroundColor(.green)
        }
    }

    var currentInningIssueCount: Int {
        let activePlayers = store.lineup.activePlayers(from: store.players)
        let openPos = store.lineup.openPositions(inning: selectedInning, players: activePlayers)
        let dupPos = store.lineup.duplicatePositionErrors(inning: selectedInning)
        return openPos.count + dupPos.count
    }

    var gameWideIssueCount: Int {
        let activePlayers = store.lineup.activePlayers(from: store.players)
        let noInfield = store.lineup.playersWithoutInfield(players: activePlayers)
        let noOutfield = store.lineup.playersWithoutOutfield(players: activePlayers)
        let underMinimum = store.lineup.playersUnderFieldingMinimum(players: activePlayers)
        var consecutiveBenchCount = 0
        for player in activePlayers {
            for i in 0..<6 {
                if store.lineup.innings[i].position(for: player) == .bench &&
                   store.lineup.innings[i + 1].position(for: player) == .bench {
                    consecutiveBenchCount += 1
                    break
                }
            }
        }
        return noInfield.count + noOutfield.count + consecutiveBenchCount + underMinimum.count
    }

    var allWarningCount: Int {
        return currentInningIssueCount + gameWideIssueCount
    }

    var displayPlayers: [Player] {
        let active = store.lineup.activePlayers(from: store.players)
        let ordered = store.lineup.orderedPlayers(from: active)
        return ordered.isEmpty ? active : ordered
    }

    @ViewBuilder
    func inningStatusDot(inning: Int) -> some View {
        let activePlayers = store.lineup.activePlayers(from: store.players)
        let openPos = store.lineup.openPositions(inning: inning, players: activePlayers)
        let dupPos = store.lineup.duplicatePositionErrors(inning: inning)
        let hasAny = !store.lineup.innings[inning].assignments.isEmpty

        if !dupPos.isEmpty {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.red)
        } else if !openPos.isEmpty && hasAny {
            Image(systemName: "minus")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.orange)
        } else if openPos.isEmpty && hasAny {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.green)
        } else {
            Circle().fill(Color.gray.opacity(0.3)).frame(width: 6, height: 6)
        }
    }
}

// MARK: - Warnings Sheet

struct WarningsView: View {
    @EnvironmentObject var store: LineupStore
    @Environment(\.dismiss) var dismiss
    let inning: Int

    var body: some View {
        NavigationStack {
            List {
                let inningWarnings = computeInningWarnings()
                let overallWarnings = computeOverallWarnings()

                Section(header: ComplianceRulesHeader(title: "Inning \(inning + 1) Issues")) {
                    if inningWarnings.isEmpty {
                        Label("No issues for this inning.", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.callout)
                    } else {
                        ForEach(inningWarnings, id: \.self) { msg in
                            Label(msg, systemImage: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.callout)
                        }
                    }
                }

                Section(header: ComplianceRulesHeader(title: "Overall Lineup")) {
                    if overallWarnings.isEmpty {
                        Label("All players meet infield & outfield requirements.", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.callout)
                    } else {
                        ForEach(overallWarnings, id: \.self) { msg in
                            Label(msg, systemImage: "exclamationmark.circle.fill")
                                .foregroundColor(.red)
                                .font(.callout)
                        }
                    }
                }
            }
            .navigationTitle("Warnings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    func computeInningWarnings() -> [String] {
        var warnings: [String] = []
        let activePlayers = store.lineup.activePlayers(from: store.players)
        let openPos = store.lineup.openPositions(inning: inning, players: activePlayers)
        let dupPos = store.lineup.duplicatePositionErrors(inning: inning)
        for pos in dupPos { warnings.append("Duplicate position: \(pos.displayName)") }
        for pos in openPos { warnings.append("Open position: \(pos.displayName)") }
        for player in activePlayers {
            if store.lineup.innings[inning].position(for: player) == .bench {
                let prevBench = inning > 0 && store.lineup.innings[inning - 1].position(for: player) == .bench
                let nextBench = inning < 6 && store.lineup.innings[inning + 1].position(for: player) == .bench
                if prevBench {
                    warnings.append("\(player.displayName): back-to-back bench (inn \(inning) & \(inning + 1))")
                } else if nextBench {
                    warnings.append("\(player.displayName): back-to-back bench (inn \(inning + 1) & \(inning + 2))")
                }
            }
        }
        return warnings
    }

    func computeOverallWarnings() -> [String] {
        var warnings: [String] = []
        let active = store.lineup.activePlayers(from: store.players)
        for player in store.lineup.playersWithoutInfield(players: active) {
            warnings.append("\(player.displayName): no infield inning assigned")
        }
        for player in store.lineup.playersWithoutOutfield(players: active) {
            warnings.append("\(player.displayName): no outfield inning assigned")
        }
        for player in store.lineup.playersUnderFieldingMinimum(players: active) {
            warnings.append("\(player.displayName): under 4 innings fielded")
        }
        return warnings
    }
}

// MARK: - Player Row in Inning

struct PlayerInningRow: View {
    @EnvironmentObject var store: LineupStore
    let player: Player
    let inning: Int
    let onTap: () -> Void

    var currentPosition: FieldPosition? {
        store.lineup.innings[inning].position(for: player)
    }

    var isDuplicate: Bool {
        guard let pos = currentPosition, !pos.isBench, !pos.isAbsent else { return false }
        return store.lineup.innings[inning].assignments.values.filter { $0 == pos }.count > 1
    }

    var previousPositionsSummary: String? {
        guard inning > 0 else { return nil }
        let history = (0..<inning).compactMap { i -> String? in
            guard let pos = store.lineup.innings[i].position(for: player) else { return nil }
            return "Inn\(i + 1):\(pos.rawValue)"
        }
        return history.isEmpty ? nil : history.joined(separator: "  ·  ")
    }

    var hasConsecutiveBenchWarning: Bool {
        guard currentPosition == .bench else { return false }
        let prevBench = inning > 0 && store.lineup.innings[inning - 1].position(for: player) == .bench
        let nextBench = inning < 6 && store.lineup.innings[inning + 1].position(for: player) == .bench
        return prevBench || nextBench
    }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center) {
                if !player.number.isEmpty {
                    Text("#\(player.number)")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                        .frame(width: 36, alignment: .leading)
                } else {
                    Text("—")
                        .font(.caption.bold())
                        .foregroundStyle(.tertiary)
                        .frame(width: 36, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(player.displayName)
                            .foregroundColor(.primary)
                        if hasConsecutiveBenchWarning {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                    if let history = previousPositionsSummary {
                        Text(history)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if let pos = currentPosition {
                    positionBadge(pos)
                } else {
                    Text("—")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 5)
        }
        .listRowBackground(isDuplicate ? Color.red.opacity(0.08) : nil)
    }

    @ViewBuilder
    func positionBadge(_ pos: FieldPosition) -> some View {
        Text(pos.rawValue)
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(positionColor(pos))
            .foregroundColor(.white)
            .cornerRadius(6)
    }

    func positionColor(_ pos: FieldPosition) -> Color {
        if pos.isAbsent { return Color(.systemGray2) }
        if pos.isBench { return .gray }
        if pos.isInfield { return .blue }
        return .green
    }
}

// MARK: - Position Picker Sheet

struct PositionPickerView: View {
    @EnvironmentObject var store: LineupStore
    @Environment(\.dismiss) var dismiss

    let player: Player
    let inning: Int

    @State private var showingConsecutiveBenchWarning = false
    @State private var pendingPosition: FieldPosition? = nil

    var body: some View {
        NavigationStack {
            List {
                if inning > 0 {
                    Section("Previous Innings") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(0..<inning, id: \.self) { i in
                                    VStack(spacing: 3) {
                                        Text("Inn \(i + 1)")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        if let pos = store.lineup.innings[i].position(for: player) {
                                            Text(pos.rawValue)
                                                .font(.caption.bold())
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(badgeColor(pos))
                                                .foregroundColor(.white)
                                                .cornerRadius(6)
                                        } else {
                                            Text("—")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                Section("Infield") {
                    ForEach(FieldPosition.infieldPositions, id: \.self) { pos in
                        positionRow(pos)
                    }
                }
                Section("Outfield") {
                    ForEach(FieldPosition.outfieldPositions, id: \.self) { pos in
                        positionRow(pos)
                    }
                }
                Section {
                    positionRow(.bench)
                }
                Section("Late Arrival / Early Departure") {
                    positionRow(.absent)
                }

                if store.lineup.innings[inning].position(for: player) != nil {
                    Section {
                        Button(role: .destructive) {
                            store.removeAssignment(player: player, inning: inning)
                            dismiss()
                        } label: {
                            Label("Remove Assignment", systemImage: "xmark.circle")
                        }
                    }
                }
            }
            .navigationTitle("\(player.firstName) – Inning \(inning + 1)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Back-to-Back Bench Warning", isPresented: $showingConsecutiveBenchWarning) {
                Button("Assign Bench Anyway", role: .destructive) {
                    if let pos = pendingPosition { commitAssignment(pos) }
                }
                Button("Cancel", role: .cancel) { pendingPosition = nil }
            } message: {
                Text("\(player.firstName) would be on the bench for two consecutive innings. You can still assign bench if needed.")
            }
        }
    }

    @ViewBuilder
    func positionRow(_ pos: FieldPosition) -> some View {
        let isSelected = store.lineup.innings[inning].position(for: player) == pos
        let occupant = store.lineup.innings[inning].player(at: pos, in: store.players)
        let occupiedByOther = occupant != nil && occupant?.id != player.id && !pos.isBench
        let wouldBeConsecutiveBench = pos == .bench && store.lineup.hasConsecutiveBench(player: player, assigningBenchToInning: inning)
        Button {
            assignPosition(pos)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(pos.displayName)
                            .foregroundColor(occupiedByOther ? .red : .primary)
                        if wouldBeConsecutiveBench {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                    if occupiedByOther, let other = occupant {
                        Text("Already assigned: \(other.displayName)")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    if wouldBeConsecutiveBench {
                        Text("Back-to-back bench warning")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark").foregroundColor(.blue)
                }
            }
        }
        .listRowBackground(occupiedByOther ? Color.red.opacity(0.06) : nil)
    }

    private func assignPosition(_ pos: FieldPosition) {
        if pos == .bench && store.lineup.hasConsecutiveBench(player: player, assigningBenchToInning: inning) {
            pendingPosition = pos
            showingConsecutiveBenchWarning = true
            return
        }
        commitAssignment(pos)
    }

    private func commitAssignment(_ pos: FieldPosition) {
        store.assignPosition(player: player, inning: inning, position: pos)
        dismiss()
    }

    func badgeColor(_ pos: FieldPosition) -> Color {
        if pos.isAbsent { return Color(.systemGray2) }
        if pos.isBench { return .gray }
        if pos.isInfield { return .blue }
        return .green
    }
}
