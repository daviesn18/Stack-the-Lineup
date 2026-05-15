import SwiftUI

// MARK: - View Mode

enum SummaryViewMode: String, CaseIterable {
    case byPlayer   = "By Player"
    case byPosition = "By Position"
    case pitching   = "Pitching"
}

// MARK: - PositionSummaryView

struct PositionSummaryView: View {
    @EnvironmentObject var store: LineupStore
    @EnvironmentObject var purchaseManager: PurchaseManager
    @Environment(\.verticalSizeClass) var verticalSizeClass

    var onAutoFill: () -> Void
    @Binding var showingAutoFillPopover: Bool
    var onFillThrough: (Int) -> Void
    var smartDefaultLastInning: Int

    @State private var viewMode: SummaryViewMode = .byPlayer

    // Pitch eligibility alert — fired when coach assigns an ineligible pitcher
    // from the grid menu. Same pattern as PositionPickerView in DefensiveGridView.
    @State private var pendingPitchAssignment: PendingAssignment? = nil

    struct PendingAssignment {
        let player: Player
        let inning: Int
        let status: PitchEligibilityStatus
    }

    // MARK: - Layout Constants

    var playerColumnWidth: CGFloat {
        let font = UIFont.preferredFont(forTextStyle: .caption1)
        let maxWidth = displayPlayers.reduce(CGFloat(0)) { current, player in
            let firstWidth = (player.firstName as NSString).size(withAttributes: [.font: font]).width
            let lastWidth  = (player.lastName  as NSString).size(withAttributes: [.font: font]).width
            return max(current, max(firstWidth, lastWidth))
        }
        return min(max(maxWidth + 20, 60), 160)
    }

    let positionLabelWidth: CGFloat = 88
    let minInningColumnWidth: CGFloat = 80

    func inningColumnWidth(availableWidth: CGFloat) -> CGFloat {
        let frozenWidth = viewMode == .byPlayer ? playerColumnWidth : positionLabelWidth
        let remaining = availableWidth - frozenWidth
        let ideal = remaining / CGFloat(inningCount)
        return max(minInningColumnWidth, ideal)
    }

    // MARK: - Derived Data

    var displayPlayers: [Player] {
        store.lineup.displayPlayers(from: store.players)
    }

    var inningCount: Int { store.lineup.innings.count }

    /// Infield positions visible under the active fair play config.
    var activeInfieldPositions: [FieldPosition] {
        store.lineup.activeFieldPositions(config: store.fairPlayConfig).filter { $0.isInfield }
    }

    /// Outfield positions visible under the active fair play config.
    var activeOutfieldPositions: [FieldPosition] {
        store.lineup.activeFieldPositions(config: store.fairPlayConfig).filter { $0.isOutfield }
    }

    var benchRowCount: Int {
        // Active field slot count depends on outfielder config:
        // 3 OF = 9 slots (6 IF + 3 OF), 4 OF = 10 slots (6 IF + 4 OF).
        let ofCount = store.fairPlayConfig.outfielderCount
        let fieldSlots = FieldPosition.infieldPositions.count + ofCount
        return max(1, displayPlayers.count - fieldSlots)
    }

    // MARK: - Body

    var body: some View {
        if store.players.isEmpty {
            ContentUnavailableView(
                "No Players",
                systemImage: "person.badge.plus",
                description: Text("Add players on the Players tab first.")
            )
        } else if displayPlayers.isEmpty {
            ContentUnavailableView(
                "All Players Absent",
                systemImage: "person.slash",
                description: Text("Mark players as available on the Lineup tab.")
            )
        } else {
            // GeometryReader lives here at the top level so all private methods
            // remain in struct scope — no local-scope compiler errors.
            GeometryReader { geo in
                let colWidth = inningColumnWidth(availableWidth: geo.size.width)
                let containerWidth = geo.size.width
                VStack(spacing: 0) {
                    titleBar
                    if viewMode == .byPlayer {
                        byPlayerTable(colWidth: colWidth, containerWidth: containerWidth)
                    } else if viewMode == .byPosition {
                        byPositionTable(colWidth: colWidth, containerWidth: containerWidth)
                    } else {
                        pitchingTable
                    }
                }
            }
            .alert("Pitch Eligibility Warning", isPresented: Binding(
                get: { pendingPitchAssignment != nil },
                set: { if !$0 { pendingPitchAssignment = nil } }
            )) {
                Button("Assign Pitcher Anyway", role: .destructive) {
                    if let pending = pendingPitchAssignment {
                        store.assignPosition(player: pending.player, inning: pending.inning, position: .pitcher)
                    }
                    pendingPitchAssignment = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingPitchAssignment = nil
                }
            } message: {
                if let pending = pendingPitchAssignment {
                    Text("\(pending.player.firstName) may not be eligible to pitch. \(pending.status.displayLabel). You can still assign this position if needed.")
                }
            }
        }
    }

    // MARK: - Title Bar

    private var titleBar: some View {
        Group {
            if verticalSizeClass == .compact {
                HStack(spacing: 12) {
                    Text("Position Summary")
                        .font(.title2.bold())
                        .layoutPriority(1)
                    boltMenuButton
                    Picker("View", selection: $viewMode) {
                        ForEach(SummaryViewMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 360)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            } else {
                VStack(spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("Position Summary")
                            .font(.largeTitle.bold())
                        boltMenuButton
                        Spacer()
                    }
                    Picker("View", selection: $viewMode) {
                        ForEach(SummaryViewMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 8)
            }
        }
    }

    private var boltMenuButton: some View {
        Button { onAutoFill() } label: {
            Image(systemName: "bolt.fill")
                .font(.title3)
                .foregroundColor(purchaseManager.isPro ? .blue : Color(.systemGray3))
        }
        .accessibilityLabel("Auto-Fill All Positions")
        .popover(isPresented: $showingAutoFillPopover, arrowEdge: .top) {
            AutoFillPopover(
                isSummary: true,
                smartDefaultLastInning: smartDefaultLastInning,
                inningCount: store.lineup.innings.count
            ) { scope in
                if case .through(let last) = scope { onFillThrough(last) }
            }
            .presentationCompactAdaptation(.popover)
        }
    }

    // MARK: - Cell Color

    private func cellColor(for position: FieldPosition?) -> Color {
        guard let position else { return .clear }
        if position.isAbsent   { return Color(.systemGray4).opacity(0.4) }
        if position.isBench    { return Color.red.opacity(0.15) }
        if position.isInfield  { return Color.blue.opacity(0.12) }
        if position.isOutfield { return Color.green.opacity(0.12) }
        return .clear
    }

    private func preferenceBorderColor(player: Player?, position: FieldPosition?) -> Color? {
        guard purchaseManager.isPro,
              let player = player,
              let position = position,
              !position.isAbsent,
              let tier = player.positionPreferences[position]
        else { return nil }
        switch tier {
        case .emergency, .never: return tier.color
        case .strength, .capable: return nil
        }
    }

    // MARK: - By Player Table

    private func byPlayerTable(colWidth: CGFloat, containerWidth: CGFloat) -> some View {
        let totalInningWidth = CGFloat(inningCount) * colWidth
        let needsHScroll = totalInningWidth > containerWidth - playerColumnWidth

        return ScrollView(.vertical) {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 0) {

                    // Frozen player name column
                    VStack(spacing: 0) {
                        Text("Player")
                            .font(.caption.bold())
                            .frame(width: playerColumnWidth, height: 37, alignment: .leading)
                            .padding(.leading, 12)
                            .background(Color(.systemGray5))
                        Divider()
                        ForEach(Array(displayPlayers.enumerated()), id: \.element.id) { index, player in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(player.firstName)
                                    .font(.caption.bold())
                                    .lineLimit(1)
                                Text(player.lastName)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(width: playerColumnWidth, height: 40, alignment: .leading)
                            .padding(.leading, 12)
                            .background(index.isMultiple(of: 2) ? Color(.systemBackground) : Color(.systemGray6).opacity(0.5))
                            Divider()
                        }
                    }
                    .frame(width: playerColumnWidth)
                    .overlay(alignment: .trailing) {
                        Rectangle().fill(Color(.separator)).frame(width: 0.5)
                    }

                    // Scrollable inning columns
                    ScrollView(.horizontal, showsIndicators: needsHScroll) {
                        VStack(spacing: 0) {
                            HStack(spacing: 0) {
                                ForEach(0..<inningCount, id: \.self) { i in
                                    Text("\(i + 1)")
                                        .font(.caption.bold())
                                        .frame(width: colWidth, height: 37)
                                }
                            }
                            .background(Color(.systemGray5))
                            Divider()
                            ForEach(Array(displayPlayers.enumerated()), id: \.element.id) { index, player in
                                HStack(spacing: 0) {
                                    ForEach(0..<inningCount, id: \.self) { inning in
                                        playerPositionCell(player: player, inning: inning, colWidth: colWidth)
                                    }
                                }
                                .background(index.isMultiple(of: 2) ? Color(.systemBackground) : Color(.systemGray6).opacity(0.5))
                                Divider()
                            }
                        }
                        .frame(width: totalInningWidth)
                    }
                }
                fairPlaySection
            }
        }
    }

    // MARK: - By Position Table

    private func byPositionTable(colWidth: CGFloat, containerWidth: CGFloat) -> some View {
        let totalInningWidth = CGFloat(inningCount) * colWidth
        let needsHScroll = totalInningWidth > containerWidth - positionLabelWidth

        return ScrollView(.vertical) {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 0) {

                    // Frozen position label column
                    VStack(spacing: 0) {
                        Text("Position")
                            .font(.caption.bold())
                            .frame(width: positionLabelWidth, height: 37, alignment: .leading)
                            .padding(.leading, 12)
                            .background(Color(.systemGray5))
                        Divider()
                        ForEach(Array(activeInfieldPositions.enumerated()), id: \.element) { idx, pos in
                            positionLabelCell(pos.displayName, isEven: idx.isMultiple(of: 2))
                            Divider()
                        }
                        ForEach(Array(activeOutfieldPositions.enumerated()), id: \.element) { idx, pos in
                            positionLabelCell(pos.displayName, isEven: idx.isMultiple(of: 2))
                            Divider()
                        }
                        positionSectionHeader("BENCH")
                        ForEach(0..<benchRowCount, id: \.self) { i in
                            positionLabelCell(benchRowCount == 1 ? "Bench" : "Bench \(i + 1)", isEven: i.isMultiple(of: 2))
                            Divider()
                        }
                    }
                    .frame(width: positionLabelWidth)
                    .overlay(alignment: .trailing) {
                        Rectangle().fill(Color(.separator)).frame(width: 0.5)
                    }

                    // Scrollable inning columns
                    ScrollView(.horizontal, showsIndicators: needsHScroll) {
                        VStack(spacing: 0) {
                            HStack(spacing: 0) {
                                ForEach(0..<inningCount, id: \.self) { i in
                                    Text("\(i + 1)")
                                        .font(.caption.bold())
                                        .frame(width: colWidth, height: 37)
                                }
                            }
                            .background(Color(.systemGray5))
                            Divider()
                            ForEach(Array(activeInfieldPositions.enumerated()), id: \.element) { idx, pos in
                                inningCellRow(position: pos, benchIndex: nil, isEven: idx.isMultiple(of: 2), colWidth: colWidth)
                                Divider()
                            }
                            ForEach(Array(activeOutfieldPositions.enumerated()), id: \.element) { idx, pos in
                                inningCellRow(position: pos, benchIndex: nil, isEven: idx.isMultiple(of: 2), colWidth: colWidth)
                                Divider()
                            }
                            // Bench separator
                            Color.clear
                                .frame(width: totalInningWidth, height: 22)
                                .background(Color(.systemGray5).opacity(0.8))
                            ForEach(0..<benchRowCount, id: \.self) { i in
                                inningCellRow(position: .bench, benchIndex: i, isEven: i.isMultiple(of: 2), colWidth: colWidth)
                                Divider()
                            }
                        }
                        .frame(width: totalInningWidth)
                    }
                }
                fairPlaySection
            }
        }
    }

    // MARK: - Row Helpers

    private func inningCellRow(position: FieldPosition, benchIndex: Int?, isEven: Bool, colWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<inningCount, id: \.self) { inning in
                positionSlotCell(position: position, benchIndex: benchIndex, inning: inning, colWidth: colWidth)
            }
        }
        .background(isEven ? Color(.systemBackground) : Color(.systemGray6).opacity(0.5))
    }

    private func positionSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.secondary)
            .frame(width: positionLabelWidth, height: 22, alignment: .leading)
            .padding(.leading, 12)
            .background(Color(.systemGray5).opacity(0.8))
    }

    private func positionLabelCell(_ name: String, isEven: Bool) -> some View {
        Text(name)
            .font(.caption.bold())
            .lineLimit(1)
            .frame(width: positionLabelWidth, height: 40, alignment: .leading)
            .padding(.leading, 12)
            .background(isEven ? Color(.systemBackground) : Color(.systemGray6).opacity(0.5))
    }

    // MARK: - By Player Position Cell

    private func playerPositionCell(player: Player, inning: Int, colWidth: CGFloat) -> some View {
        let position = store.lineup.innings[inning].position(for: player)

        // Pitch eligibility warning — only relevant when this cell is Pitcher
        let pitchWarning: PitchEligibilityStatus? = {
            guard position == .pitcher, store.pitchingConfig.rulesEnabled else { return nil }
            let status = PitchEligibilityEngine.status(
                for: player,
                gameLogs: store.gameLogs,
                config: store.pitchingConfig,
                referenceDate: store.lineup.gameDate
            )
            return status.blocksAssignment ? status : nil
        }()

        return Menu {
            Section("Infield") {
                ForEach(activeInfieldPositions, id: \.self) { pos in
                    positionMenuButton(player: player, inning: inning, position: pos, current: position)
                }
            }
            Section("Outfield") {
                ForEach(activeOutfieldPositions, id: \.self) { pos in
                    positionMenuButton(player: player, inning: inning, position: pos, current: position)
                }
            }
            Section {
                positionMenuButton(player: player, inning: inning, position: .bench, current: position)
                positionMenuButton(player: player, inning: inning, position: .absent, current: position)
            }
            if position != nil {
                Section {
                    Button(role: .destructive) {
                        store.removeAssignment(player: player, inning: inning)
                    } label: {
                        Label("Remove", systemImage: "xmark.circle")
                    }
                }
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 1) {
                    if let pos = position {
                        Text(pos.rawValue)
                            .font(.caption2.bold())
                            .foregroundColor(pos.isAbsent ? Color(.systemGray) : .primary)
                    } else {
                        Text("—")
                            .font(.caption2)
                            .foregroundStyle(.quaternary)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundColor(.secondary)
                }
                .frame(width: colWidth, height: 40)
                .background(pitchWarning != nil ? Color.red.opacity(0.12) : cellColor(for: position))
                .overlay {
                    if let borderColor = preferenceBorderColor(player: player, position: position) {
                        RoundedRectangle(cornerRadius: 2)
                            .strokeBorder(borderColor, lineWidth: 2)
                    }
                }
                .contentShape(Rectangle())

                // Red dot in top-right corner when pitcher is ineligible
                if pitchWarning != nil {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 6, height: 6)
                        .padding(.top, 4)
                        .padding(.trailing, 4)
                }
            }
        }
    }

    // MARK: - By Position Slot Cell

    private func positionSlotCell(position: FieldPosition, benchIndex: Int?, inning: Int, colWidth: CGFloat) -> some View {
        let inningAssignment = store.lineup.innings[inning]

        let assignedPlayer: Player?
        if let idx = benchIndex {
            let benchPlayers = displayPlayers.filter { inningAssignment.position(for: $0) == .bench }
            assignedPlayer = idx < benchPlayers.count ? benchPlayers[idx] : nil
        } else {
            assignedPlayer = inningAssignment.player(at: position, in: store.players)
        }

        return Menu {
            Section("Assign Player") {
                ForEach(displayPlayers) { player in
                    let currentPos = inningAssignment.position(for: player)
                    let isHere = (benchIndex == nil && currentPos == position)
                               || (benchIndex != nil && currentPos == .bench
                                   && assignedPlayer?.id == player.id)
                    Button {
                        store.assignPosition(player: player, inning: inning, position: position)
                    } label: {
                        HStack {
                            if isHere {
                                Text(styledStrikethrough(player.displayName))
                            } else if let cp = currentPos {
                                Text("\(player.shortName)  (\(cp.rawValue))")
                            } else {
                                Text(player.shortName)
                            }
                            Spacer()
                            if isHere { Image(systemName: "checkmark") }
                        }
                    }
                }
            }
            if let player = assignedPlayer {
                Section {
                    Button(role: .destructive) {
                        store.removeAssignment(player: player, inning: inning)
                    } label: {
                        Label("Remove \(player.shortName)", systemImage: "xmark.circle")
                    }
                }
            }
        } label: {
            VStack(spacing: 1) {
                if let player = assignedPlayer {
                    Text(player.shortName)
                        .font(.caption2.bold())
                        .lineLimit(1)
                        .foregroundColor(.primary)
                } else {
                    Text("—")
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 6, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .frame(width: colWidth, height: 40)
            .background(assignedPlayer != nil ? cellColor(for: position) : Color.clear)
            .overlay {
                if let borderColor = preferenceBorderColor(player: assignedPlayer, position: position) {
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(borderColor, lineWidth: 2)
                }
            }
            .contentShape(Rectangle())
        }
    }

    // MARK: - Menu Button Helpers

    @ViewBuilder
    private func positionMenuButton(player: Player, inning: Int, position: FieldPosition, current: FieldPosition?) -> some View {
        let occupant = store.lineup.innings[inning].player(at: position, in: store.players)
        let occupiedByOther = occupant != nil && occupant?.id != player.id && !position.isBench
        let isCurrentPlayerPosition = current == position

        Button {
            // Check pitch eligibility before assigning the pitcher slot
            if position == .pitcher, store.pitchingConfig.rulesEnabled {
                let status = PitchEligibilityEngine.status(
                    for: player,
                    gameLogs: store.gameLogs,
                    config: store.pitchingConfig,
                    referenceDate: store.lineup.gameDate
                )
                if status.blocksAssignment {
                    pendingPitchAssignment = PendingAssignment(
                        player: player, inning: inning, status: status
                    )
                } else {
                    store.assignPosition(player: player, inning: inning, position: position)
                }
            } else {
                store.assignPosition(player: player, inning: inning, position: position)
            }
        } label: {
            HStack {
                if occupiedByOther, let other = occupant {
                    Text("\(position.displayName) — \(other.firstName)")
                        .strikethrough()
                } else if isCurrentPlayerPosition {
                    Text(styledStrikethrough(position.displayName))
                } else {
                    Text(position.displayName)
                }
                Spacer()
                if isCurrentPlayerPosition {
                    Image(systemName: "checkmark")
                }
            }
        }
    }

    /// Strikethrough/italic/secondary attributed string used to indicate a stale
    /// current value during a position swap (the player or position currently
    /// occupying the slot before the new selection commits).
    private func styledStrikethrough(_ name: String) -> AttributedString {
        var str = AttributedString(name)
        str.strikethroughStyle = .single
        str.font = .callout.italic()
        str.foregroundColor = .secondary
        return str
    }

    // MARK: - Pitching Table

    @State private var pitchingAssignmentPlayer: Player? = nil

    private var pitchingTable: some View {
        let pitchers = displayPlayers.filter { $0.positionPreferences[.pitcher] != .never }

        return ScrollView(.vertical) {
            VStack(spacing: 0) {
                if !store.pitchingConfig.rulesEnabled {
                    HStack(spacing: 10) {
                        Image(systemName: "info.circle")
                            .foregroundColor(.secondary)
                        Text("Enable Pitching Rules in team settings to track eligibility and pitch counts.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemGray6))
                }

                // Header
                HStack(spacing: 0) {
                    Text("Player")
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 16)
                    Text("Thrown")
                        .font(.caption.bold())
                        .frame(width: 60, alignment: .center)
                    Text("Available")
                        .font(.caption.bold())
                        .frame(width: 80, alignment: .center)
                    Text("Status")
                        .font(.caption.bold())
                        .frame(width: 82, alignment: .center)
                        .padding(.trailing, 8)
                }
                .frame(height: 34)
                .background(Color(.systemGray5))

                Divider()

                if pitchers.isEmpty {
                    Text("No players have Pitcher as an available position preference.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(Array(pitchingRows(for: pitchers).enumerated()), id: \.element.player.id) { index, row in
                        Button {
                            pitchingAssignmentPlayer = row.player
                        } label: {
                            HStack(spacing: 0) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(row.player.displayName)
                                        .font(.subheadline)
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                    if !row.assignedInnings.isEmpty {
                                        Text("Pitching: \(row.assignedInnings.map { "Inn \($0 + 1)" }.joined(separator: ", "))")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    } else {
                                        Text("Tap to assign innings")
                                            .font(.caption2)
                                            .foregroundColor(.blue.opacity(0.7))
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.leading, 16)

                                // Thrown — pitches in the rolling window
                                Text("\(row.windowPitches)")
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundColor(.secondary)
                                    .frame(width: 60, alignment: .center)

                                // Available — min(dailyMax, weeklyRemaining) minus window pitches
                                Text(row.dailyMax > 0 ? "\(row.available)" : "—")
                                    .font(.subheadline.monospacedDigit().bold())
                                    .foregroundColor(remainingColor(row.available, max: row.dailyMax))
                                    .frame(width: 80, alignment: .center)

                                Text(row.status.displayLabel)
                                    .font(.caption)
                                    .foregroundColor(row.status.isRestricted ? .red : .secondary)
                                    .multilineTextAlignment(.center)
                                    .frame(width: 74, alignment: .center)

                                Image(systemName: "chevron.right")
                                    .font(.caption.bold())
                                    .foregroundColor(.secondary)
                                    .frame(width: 16)
                                    .padding(.trailing, 8)
                            }
                            .frame(minHeight: 48)
                            .background(index.isMultiple(of: 2) ? Color(.systemBackground) : Color(.systemGray6).opacity(0.5))
                        }
                        Divider()
                    }
                }

                if store.pitchingConfig.rulesEnabled && !pitchers.isEmpty {
                    Text("Available is the lower of the daily max and the pitches remaining in the current weekly window.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                fairPlaySection
            }
        }
        .sheet(item: $pitchingAssignmentPlayer) { player in
            PitchingAssignmentSheet(player: player)
                .environmentObject(store)
        }
    }

    // MARK: - Pitching Table Helpers

    struct PitchingRow {
        let player: Player
        let windowPitches: Int
        let dailyMax: Int
        let available: Int   // min(dailyMax, weeklyRemaining) — pitches available for today's game
        let status: PitchEligibilityStatus
        let assignedInnings: [Int]
    }

    private func pitchingRows(for players: [Player]) -> [PitchingRow] {
        let cal = Calendar.current
        let gameDate = cal.startOfDay(for: store.lineup.gameDate)

        let windowStart: Date = {
            switch store.pitchingConfig.rollingWindowType {
            case .calendarWeek:
                var comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: gameDate)
                comps.weekday = 2
                return cal.date(from: comps) ?? gameDate
            case .rolling:
                return cal.date(byAdding: .day,
                    value: -(store.pitchingConfig.rollingWindowDays - 1), to: gameDate) ?? gameDate
            }
        }()

        let rows: [PitchingRow] = players.map { player in
            let key = player.id.uuidString
            // Window pitches = all logs before the game date (not including game day itself)
            let windowPitches = store.gameLogs
                .filter { cal.startOfDay(for: $0.gameDate) >= windowStart && cal.startOfDay(for: $0.gameDate) < gameDate }
                .reduce(0) { $0 + ($1.pitchCounts[key] ?? 0) }

            let dailyMax: Int = {
                guard let age = player.leagueAge,
                      let bracket = PitchingAgeBracket.bracket(for: age),
                      let limits = store.pitchingConfig.ageLimits[bracket] else { return 0 }
                return limits.dailyMax
            }()

            // Available = min(daily max, weekly cap remaining if enabled)
            // This matches the engine's .limited calculation — the constraint
            // is whichever ceiling is lower for today's game, not daily max
            // minus historical pitches (those were thrown on past days, not today).
            var available = dailyMax
            if store.pitchingConfig.weeklyLimitEnabled && store.pitchingConfig.weeklyLimit > 0 {
                let weeklyRemaining = max(0, store.pitchingConfig.weeklyLimit - windowPitches)
                available = min(dailyMax, weeklyRemaining)
            }

            let status = PitchEligibilityEngine.status(
                for: player, gameLogs: store.gameLogs, config: store.pitchingConfig,
                referenceDate: store.lineup.gameDate
            )

            let assignedInnings = store.lineup.innings.indices.filter { i in
                store.lineup.innings[i].assignments[player.id] == .pitcher
            }

            return PitchingRow(
                player: player,
                windowPitches: windowPitches,
                dailyMax: dailyMax,
                available: available,
                status: status,
                assignedInnings: assignedInnings
            )
        }

        return rows.sorted { a, b in
            if a.status.isRestricted != b.status.isRestricted {
                return !a.status.isRestricted
            }
            return a.available > b.available
        }
    }

    private func remainingColor(_ remaining: Int, max: Int) -> Color {
        guard max > 0 else { return .secondary }
        let fraction = Double(remaining) / Double(max)
        if fraction >= 0.6 { return Color(red: 0.1, green: 0.5, blue: 0.2) }
        if fraction >= 0.25 { return Color(red: 0.6, green: 0.35, blue: 0.0) }
        return .red
    }

    // MARK: - Fair Play Warnings

    @ViewBuilder
    private var fairPlaySection: some View {
        let config = store.fairPlayConfig
        let activePlayers = store.lineup.activePlayers(from: store.players)
        let noInfield = config.minimumInfieldInnings > 0
            ? store.lineup.playersWithoutInfield(players: activePlayers)
            : []
        let noOutfield = config.minimumOutfieldInnings > 0
            ? store.lineup.playersWithoutOutfield(players: activePlayers)
            : []
        let underMinimum = config.minimumFieldingInnings > 0
            ? store.lineup.playersUnderFieldingMinimum(players: activePlayers, minimumInnings: config.minimumFieldingInnings)
            : []
        let consecutiveBenchPlayers = config.noConsecutiveBench
            ? store.lineup.playersWithBackToBackBench(from: store.players)
            : []
        let catcherToPitcherViolators = store.lineup.playersViolatingCatcherToPitcher(
            players: activePlayers, threshold: config.catcherToPitcherThreshold)
        let pitcherToCatcherViolators = store.lineup.playersViolatingPitcherToCatcher(
            players: activePlayers, threshold: config.pitcherToCatcherThreshold)
        let hasAssignments = store.lineup.innings.contains(where: { !$0.assignments.isEmpty })
        let hasAnyWarning = !noInfield.isEmpty || !noOutfield.isEmpty || !consecutiveBenchPlayers.isEmpty
            || !underMinimum.isEmpty || !catcherToPitcherViolators.isEmpty || !pitcherToCatcherViolators.isEmpty

        // Pitch eligibility — only computed when rules are enabled
        let pitchViolators: [(player: Player, status: PitchEligibilityStatus)] = {
            guard store.pitchingConfig.rulesEnabled else { return [] }
            let assignedPitcherIDs = Set(
                store.lineup.innings.flatMap { inning in
                    inning.assignments.compactMap { (pid, pos) -> UUID? in pos == .pitcher ? pid : nil }
                }
            )
            return assignedPitcherIDs.compactMap { pid -> (Player, PitchEligibilityStatus)? in
                guard let player = store.players.first(where: { $0.id == pid }) else { return nil }
                let status = PitchEligibilityEngine.status(
                    for: player, gameLogs: store.gameLogs, config: store.pitchingConfig,
                    referenceDate: store.lineup.gameDate
                )
                switch status {
                case .eligible: return nil
                default: return (player, status)
                }
            }
        }()

        if hasAnyWarning || !pitchViolators.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("Fair Play Warnings", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.bold())
                    .foregroundColor(.orange)
                if !noInfield.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Missing Infield Inning").font(.caption.bold()).foregroundColor(.orange)
                        Text(noInfield.map(\.displayName).joined(separator: ", ")).font(.caption).foregroundColor(.secondary)
                    }
                }
                if !noOutfield.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Missing Outfield Inning").font(.caption.bold()).foregroundColor(.orange)
                        Text(noOutfield.map(\.displayName).joined(separator: ", ")).font(.caption).foregroundColor(.secondary)
                    }
                }
                if !consecutiveBenchPlayers.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Back-to-Back Bench").font(.caption.bold()).foregroundColor(.red)
                        Text(consecutiveBenchPlayers.map(\.displayName).joined(separator: ", ")).font(.caption).foregroundColor(.secondary)
                    }
                }
                if !underMinimum.isEmpty {
                    let min = config.minimumFieldingInnings
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Under \(min) Inning\(min == 1 ? "" : "s") Fielded").font(.caption.bold()).foregroundColor(.orange)
                        Text(underMinimum.map(\.displayName).joined(separator: ", ")).font(.caption).foregroundColor(.secondary)
                    }
                }
                if !catcherToPitcherViolators.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Catcher to Pitcher Violation").font(.caption.bold()).foregroundColor(.red)
                        Text(catcherToPitcherViolators.map(\.displayName).joined(separator: ", ")).font(.caption).foregroundColor(.secondary)
                    }
                }
                if !pitcherToCatcherViolators.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Pitcher to Catcher Violation").font(.caption.bold()).foregroundColor(.red)
                        Text(pitcherToCatcherViolators.map(\.displayName).joined(separator: ", ")).font(.caption).foregroundColor(.secondary)
                    }
                }
                if !pitchViolators.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Pitch Eligibility").font(.caption.bold()).foregroundColor(.red)
                        ForEach(pitchViolators, id: \.player.id) { item in
                            Text("\(item.player.displayName): \(item.status.displayLabel)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemGray6))
        } else if hasAssignments {
            HStack {
                Label("All players meet fair play requirements", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.green)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemGray6))
        }
    }
}

// MARK: - Pitching Assignment Sheet

/// Lets the coach assign or remove a player from the Pitcher slot for specific innings.
/// Only pitcher assignments are made here — other positions are not touched.
struct PitchingAssignmentSheet: View {
    @EnvironmentObject var store: LineupStore
    @Environment(\.dismiss) var dismiss

    let player: Player

    @State private var showingEligibilityWarning = false
    @State private var pendingInning: Int? = nil

    private var eligibilityStatus: PitchEligibilityStatus {
        PitchEligibilityEngine.status(
            for: player, gameLogs: store.gameLogs, config: store.pitchingConfig,
            referenceDate: store.lineup.gameDate
        )
    }

    private var remaining: Int? {
        pitchesRemaining(
            for: player, gameLogs: store.gameLogs, config: store.pitchingConfig,
            referenceDate: store.lineup.gameDate
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "figure.baseball.pitcher")
                            .font(.title3)
                            .foregroundColor(.secondary)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            switch eligibilityStatus {
                            case .eligible:
                                Text("Eligible to pitch")
                                    .font(.subheadline.bold())
                                if let r = remaining {
                                    Text("\(r) pitches available today")
                                        .font(.caption).foregroundColor(.secondary)
                                }
                            case .limited(let r):
                                Text("Eligible — limited")
                                    .font(.subheadline.bold())
                                    .foregroundColor(Color(red: 0.6, green: 0.35, blue: 0.0))
                                Text("\(r) pitches available today")
                                    .font(.caption).foregroundColor(.secondary)
                            case .mustRest:
                                Text("Must rest")
                                    .font(.subheadline.bold()).foregroundColor(.red)
                                Text(eligibilityStatus.displayLabel)
                                    .font(.caption).foregroundColor(.secondary)
                            case .unknownAge:
                                Text("League age not set")
                                    .font(.subheadline.bold()).foregroundColor(.orange)
                                Text("Set age on the player card to track pitching eligibility")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }

                        Spacer()

                        if let r = remaining, r > 0 {
                            VStack(spacing: 0) {
                                Text("\(r)")
                                    .font(.system(size: 22, weight: .bold).monospacedDigit())
                                    .foregroundColor(remainingColor(r))
                                Text("left")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    ForEach(0..<store.lineup.innings.count, id: \.self) { inning in
                        let isAssigned = store.lineup.innings[inning].assignments[player.id] == .pitcher
                        let occupant = store.lineup.innings[inning].player(at: .pitcher, in: store.players)
                        let occupiedByOther = !isAssigned && occupant != nil

                        Button {
                            if isAssigned {
                                store.removeAssignment(player: player, inning: inning)
                            } else if eligibilityStatus.blocksAssignment {
                                pendingInning = inning
                                showingEligibilityWarning = true
                            } else {
                                store.assignPosition(player: player, inning: inning, position: .pitcher)
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Inning \(inning + 1)")
                                        .foregroundColor(.primary)
                                    if occupiedByOther, let other = occupant {
                                        Text("Currently: \(other.displayName)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: isAssigned ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(isAssigned ? .blue : .secondary)
                                    .font(.title3)
                            }
                        }
                        .listRowBackground(isAssigned ? Color.blue.opacity(0.06) : nil)
                    }
                } header: {
                    Text("Assign Pitcher Innings")
                } footer: {
                    Text("Tap an inning to assign or remove this player as pitcher. Other position assignments in that inning are not affected.")
                }
            }
            .navigationTitle(player.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .alert("Pitch Eligibility Warning", isPresented: $showingEligibilityWarning) {
                Button("Assign Anyway", role: .destructive) {
                    if let inning = pendingInning {
                        store.assignPosition(player: player, inning: inning, position: .pitcher)
                    }
                    pendingInning = nil
                }
                Button("Cancel", role: .cancel) { pendingInning = nil }
            } message: {
                Text("\(player.firstName) may not be eligible to pitch. \(eligibilityStatus.displayLabel). You can still assign this inning if needed.")
            }
        }
    }

    private func remainingColor(_ remaining: Int) -> Color {
        guard let age = player.leagueAge,
              let bracket = PitchingAgeBracket.bracket(for: age),
              let limits = store.pitchingConfig.ageLimits[bracket] else { return .secondary }
        let fraction = limits.dailyMax > 0 ? Double(remaining) / Double(limits.dailyMax) : 0
        if fraction >= 0.6 { return Color(red: 0.1, green: 0.5, blue: 0.2) }
        if fraction >= 0.25 { return Color(red: 0.6, green: 0.35, blue: 0.0) }
        return .red
    }
}
