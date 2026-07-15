import SwiftUI

// MARK: - Quick-Set Sheet
//
// Single bottom-sheet pattern replacing the old per-cell dropdown menus on the
// Position Summary screen's By Player and By Position tabs. Same sheet, two
// body modes depending on what was tapped:
//   - .player  -> coach picks a POSITION for this player (By Player tab)
//   - .position -> coach picks a PLAYER for this position (By Position tab)
//
// "Apply to innings" lets the coach batch the assignment across a run of
// innings in one tap instead of repeating the flow per inning.

struct QuickSetSheet: View {
    @EnvironmentObject var store: LineupStore
    @Environment(\.dismiss) var dismiss

    enum Origin {
        case player(Player)
        /// benchIndex identifies which bench slot was tapped, purely for display
        /// of "currently occupied by" -- the assignment itself is just `.bench`.
        case position(FieldPosition, benchIndex: Int?)
    }

    let origin: Origin
    let initialInning: Int

    @State private var selectedInnings: Set<Int>

    // Combined pitch-eligibility warning. Eligibility is computed from the
    // lineup's game date, not per-inning, so a single check covers every
    // selected inning -- one alert, not one per inning.
    @State private var pendingPitchStatus: PitchEligibilityStatus? = nil
    @State private var pendingCommit: (() -> Void)? = nil

    init(origin: Origin, initialInning: Int) {
        self.origin = origin
        self.initialInning = initialInning
        _selectedInnings = State(initialValue: [initialInning])
    }

    private var inningCount: Int { store.lineup.innings.count }

    private var activeInfield: [FieldPosition] {
        store.lineup.activeFieldPositions(config: store.fairPlayConfig).filter { $0.isInfield }
    }

    private var activeOutfield: [FieldPosition] {
        store.lineup.activeFieldPositions(config: store.fairPlayConfig).filter { $0.isOutfield }
    }

    private var sortedInnings: [Int] { selectedInnings.sorted() }

    /// Fill-status lookups (By Player sheet mode) are keyed off the first
    /// selected inning only, mirroring how the By Position mode's "currently
    /// holds" note already works off `sortedInnings.first`.
    private var firstSelectedInning: Int { sortedInnings.first ?? initialInning }

    private func occupant(at position: FieldPosition, inning: Int) -> Player? {
        let players = store.lineup.displayPlayers(from: store.players)
        return store.lineup.innings[inning].player(at: position, in: players)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                inningChipsRow
                Divider()
                ScrollView {
                    VStack(spacing: 0) {
                        switch origin {
                        case .player(let player):
                            positionGridBody(player: player)
                        case .position(let position, let benchIndex):
                            playerListBody(position: position, benchIndex: benchIndex)
                        }
                        clearRow
                    }
                    .padding(.bottom, 12)
                }
            }
            .navigationTitle(sheetTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(20)
        .alert("Pitch Eligibility Warning", isPresented: Binding(
            get: { pendingPitchStatus != nil },
            set: { if !$0 { pendingPitchStatus = nil; pendingCommit = nil } }
        )) {
            Button("Assign Anyway", role: .destructive) {
                pendingCommit?()
                pendingPitchStatus = nil
                pendingCommit = nil
            }
            Button("Cancel", role: .cancel) {
                pendingPitchStatus = nil
                pendingCommit = nil
            }
        } message: {
            if let status = pendingPitchStatus {
                Text(pitchWarningMessage(status))
            }
        }
    }

    private var sheetTitle: String {
        switch origin {
        case .player(let player): return player.displayName
        case .position(let position, _): return position.displayName
        }
    }

    private func pitchWarningMessage(_ status: PitchEligibilityStatus) -> String {
        let inningList = sortedInnings.map { "\($0 + 1)" }.joined(separator: ", ")
        let name: String
        switch origin {
        case .player(let player): name = player.firstName
        case .position(_, _): name = "This player"
        }
        return "\(name) may not be eligible to pitch. \(status.displayLabel). This applies across the selected innings (\(inningList)). You can still assign anyway if needed."
    }

    // MARK: - Apply to Innings

    private var inningChipsRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Apply to innings")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color(.tertiaryLabel))
                .textCase(.uppercase)
            HStack(spacing: 6) {
                ForEach(0..<inningCount, id: \.self) { inning in
                    let isSelected = selectedInnings.contains(inning)
                    Button {
                        toggleInning(inning)
                    } label: {
                        Text("\(inning + 1)")
                            .font(.system(size: 14, weight: .bold))
                            .frame(width: 32, height: 32)
                            .background(isSelected ? Color.blue : Color(.systemGray6))
                            .foregroundColor(isSelected ? .white : .primary)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private func toggleInning(_ inning: Int) {
        if selectedInnings.contains(inning) {
            // Never allow zero innings selected -- keep at least one.
            if selectedInnings.count > 1 { selectedInnings.remove(inning) }
        } else {
            selectedInnings.insert(inning)
        }
    }

    // MARK: - By Player Body (pick a position)

    private func positionGridBody(player: Player) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            positionSection(title: "Infield", positions: activeInfield, player: player)
            if !activeOutfield.isEmpty {
                positionSection(title: "Outfield", positions: activeOutfield, player: player)
            }
            positionSection(title: "Bench", positions: [.bench, .absent], player: player)
        }
        .padding(.top, 16)
    }

    private func positionSection(title: String, positions: [FieldPosition], player: Player) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color(.tertiaryLabel))
                .textCase(.uppercase)
                .padding(.horizontal, 20)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(positions, id: \.self) { position in
                    positionPill(position: position, player: player)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func positionPill(position: FieldPosition, player: Player) -> some View {
        let occupantPlayer = occupant(at: position, inning: firstSelectedInning)
        let isCurrent = occupantPlayer?.id == player.id

        return Button {
            assign(position: position, toPlayer: player)
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                HStack {
                    Text(position.displayName)
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    if isCurrent {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                    }
                }
                .foregroundColor(pillTextColor(position))
                Text(fillStatusLabel(occupant: occupantPlayer, isCurrent: isCurrent))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(fillStatusColor(occupant: occupantPlayer, isCurrent: isCurrent))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(pillTintColor(position))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .inset(by: 0.75)
                    .stroke(fillStatusBorderColor(occupant: occupantPlayer, isCurrent: isCurrent), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Fill Status (By Player sheet only)
    //
    // Shows which positions are already taken -- for the player's own
    // occupied position, taken by someone else, or open -- since the sheet is
    // a modal and the coach can't see the grid behind it. Keyed off
    // `firstSelectedInning`; purely informational, tap behavior is unchanged.

    private func fillStatusLabel(occupant: Player?, isCurrent: Bool) -> String {
        guard let occupant else { return "Open" }
        if isCurrent { return "Current" }
        return "\(occupant.firstName) \(occupant.lastName.prefix(1))."
    }

    private func fillStatusColor(occupant: Player?, isCurrent: Bool) -> Color {
        guard occupant != nil else { return Color(red: 0.235, green: 0.235, blue: 0.263).opacity(0.4) }
        if isCurrent { return Color(red: 0.0, green: 0.478, blue: 1.0) }
        return Color(red: 1.0, green: 0.584, blue: 0.0)
    }

    private func fillStatusBorderColor(occupant: Player?, isCurrent: Bool) -> Color {
        guard occupant != nil else { return .clear }
        if isCurrent { return Color(red: 0.0, green: 0.478, blue: 1.0) }
        return Color(red: 1.0, green: 0.584, blue: 0.0).opacity(0.5)
    }

    // MARK: - By Position Body (pick a player)

    private func playerListBody(position: FieldPosition, benchIndex: Int?) -> some View {
        let players = store.lineup.displayPlayers(from: store.players)
        let firstInning = sortedInnings.first ?? initialInning

        return VStack(alignment: .leading, spacing: 0) {
            Text("Players")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color(.tertiaryLabel))
                .textCase(.uppercase)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
                .padding(.top, 16)

            ForEach(players) { player in
                let currentPos = store.lineup.innings[firstInning].position(for: player)
                Button {
                    assign(position: position, toPlayer: player)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(player.displayName)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.primary)
                            if let cp = currentPos {
                                Text("Currently: \(cp.rawValue)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        if currentPos == position {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 20)
            }
        }
    }

    // MARK: - Clear Row

    private var clearRow: some View {
        Button(role: .destructive) {
            clearSelection()
        } label: {
            HStack {
                Spacer()
                Text(selectedInnings.count > 1 ? "Clear position(s)" : "Clear position")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
            }
            .foregroundColor(.red)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
        .padding(.top, 16)
    }

    // MARK: - Commit Logic

    private func assign(position: FieldPosition, toPlayer player: Player) {
        if position == .pitcher, store.pitchingConfig.rulesEnabled {
            let status = PitchEligibilityEngine.status(
                for: player,
                gameLogs: store.gameLogs,
                config: store.pitchingConfig,
                referenceDate: store.lineup.gameDate
            )
            if status.blocksAssignment {
                pendingCommit = { [sortedInnings] in
                    for inning in sortedInnings {
                        store.assignPosition(player: player, inning: inning, position: position)
                    }
                    dismiss()
                }
                pendingPitchStatus = status
                return
            }
        }
        for inning in sortedInnings {
            store.assignPosition(player: player, inning: inning, position: position)
        }
        dismiss()
    }

    private func clearSelection() {
        switch origin {
        case .player(let player):
            for inning in sortedInnings {
                store.removeAssignment(player: player, inning: inning)
            }
        case .position(let position, _):
            let players = store.lineup.displayPlayers(from: store.players)
            for inning in sortedInnings {
                if let occupant = store.lineup.innings[inning].player(at: position, in: players) {
                    store.removeAssignment(player: occupant, inning: inning)
                }
            }
        }
        dismiss()
    }

    // MARK: - Pill Colors (Design Tokens)
    //
    // Muted position palette (design direction 2a) -- same tints/text as the
    // grid cells so the sheet and grid read as one system. #007AFF stays the
    // interactive color (selection outlines, chips).

    private func pillTintColor(_ position: FieldPosition) -> Color {
        if position.isBench || position.isAbsent { return Color(red: 0.557, green: 0.557, blue: 0.576).opacity(0.10) }
        if position.isInfield { return Color(red: 0.0, green: 0.478, blue: 1.0).opacity(0.09) }
        return Color(red: 0.204, green: 0.780, blue: 0.349).opacity(0.10)
    }

    private func pillTextColor(_ position: FieldPosition) -> Color {
        if position.isBench || position.isAbsent { return Color(red: 0.541, green: 0.541, blue: 0.557) }
        if position.isInfield { return Color(red: 0.306, green: 0.431, blue: 0.588) }
        return Color(red: 0.357, green: 0.541, blue: 0.400)
    }
}
