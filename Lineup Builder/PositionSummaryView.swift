import SwiftUI

// MARK: - View Mode

enum SummaryViewMode: String, CaseIterable {
    case byPlayer   = "By Player"
    case byPosition = "By Position"
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
                VStack(spacing: 0) {
                    titleBar
                    if viewMode == .byPlayer {
                        byPlayerTable(colWidth: colWidth)
                    } else {
                        byPositionTable(colWidth: colWidth)
                    }
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
                    .frame(maxWidth: 260)
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

    private func byPlayerTable(colWidth: CGFloat) -> some View {
        let totalInningWidth = CGFloat(inningCount) * colWidth
        let needsHScroll = totalInningWidth > UIScreen.main.bounds.width - playerColumnWidth

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

    private func byPositionTable(colWidth: CGFloat) -> some View {
        let totalInningWidth = CGFloat(inningCount) * colWidth
        let needsHScroll = totalInningWidth > UIScreen.main.bounds.width - positionLabelWidth

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
            .background(cellColor(for: position))
            .overlay {
                if let borderColor = preferenceBorderColor(player: player, position: position) {
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(borderColor, lineWidth: 2)
                }
            }
            .contentShape(Rectangle())
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
            store.assignPosition(player: player, inning: inning, position: position)
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

        if hasAnyWarning {
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
