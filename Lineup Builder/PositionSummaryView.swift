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
    @Binding var autoFillPrompt: String
    var isParsingAutoFillPrompt: Bool

    @State private var viewMode: SummaryViewMode = .byPlayer

    // Drives the Quick-Set Sheet — replaces the old per-cell dropdown Menu on
    // both By Player and By Position. Pitch eligibility warnings are now
    // handled inside the sheet itself (see QuickSetSheet).
    @State private var quickSetTarget: QuickSetTarget? = nil

    struct QuickSetTarget: Identifiable {
        let id = UUID()
        let origin: QuickSetSheet.Origin
        let inning: Int
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

    let positionLabelWidth: CGFloat = 52
    let minInningColumnWidth: CGFloat = 80

    /// By Position scrolls horizontally when 7 innings won't fit, but expands to
    // fill available width when they do (72pt is the minimum that renders
    // "Drew S." style names without clipping).
    let minByPositionColumnWidth: CGFloat = 72

    func byPositionColumnWidth(availableWidth: CGFloat) -> CGFloat {
        let remaining = availableWidth - positionLabelWidth
        let ideal = remaining / CGFloat(inningCount)
        return max(minByPositionColumnWidth, ideal)
    }

    func inningColumnWidth(availableWidth: CGFloat) -> CGFloat {
        let remaining = availableWidth - playerColumnWidth
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
                        byPositionTable(colWidth: byPositionColumnWidth(availableWidth: containerWidth), containerWidth: containerWidth)
                    } else {
                        pitchingTable
                    }
                }
            }
            .sheet(item: $quickSetTarget) { target in
                QuickSetSheet(origin: target.origin, initialInning: target.inning)
                    .environmentObject(store)
            }
        }
    }

    // MARK: - Title Bar

    private var titleBar: some View {
        VStack(spacing: 10) {
            if verticalSizeClass == .compact {
                HStack(spacing: 12) {
                    Text("Position Summary")
                        .font(.title2.bold())
                        .layoutPriority(1)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Position Summary")
                        .font(.largeTitle.bold())
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }

            Picker("View", selection: $viewMode) {
                ForEach(SummaryViewMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)

            // Auto-Fill is now a primary, always-visible action on the two
            // assignment tabs -- replaces the old small bolt icon next to the
            // title. Not shown on Pitching, which has its own assignment flow.
            if viewMode != .pitching {
                autoFillButton
                    .padding(.horizontal, 16)
            }
        }
        .padding(.bottom, 8)
    }

    private var autoFillButton: some View {
        Button { onAutoFill() } label: {
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill")
                Text("Auto-Fill Open Positions")
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(purchaseManager.isPro ? Color.blue : Color(.systemGray3))
            .cornerRadius(10)
        }
        .accessibilityLabel("Auto-Fill All Positions")
        .popover(isPresented: $showingAutoFillPopover, arrowEdge: .top) {
            AutoFillPopover(
                isSummary: true,
                smartDefaultLastInning: smartDefaultLastInning,
                inningCount: store.lineup.innings.count,
                prompt: $autoFillPrompt,
                isParsingPrompt: isParsingAutoFillPrompt
            ) { scope in
                if case .through(let last) = scope { onFillThrough(last) }
            }
            .presentationCompactAdaptation(.popover)
        }
    }

    // MARK: - Cell Color

    /// Category tint used for a filled cell's background (15% opacity per design tokens).
    private func cellColor(for position: FieldPosition?) -> Color {
        guard let position else { return .clear }
        if position.isAbsent   { return Color(.systemGray4).opacity(0.4) }
        if position.isBench    { return Color(red: 0.557, green: 0.557, blue: 0.576).opacity(0.15) }
        if position.isInfield  { return Color(red: 0.0, green: 0.478, blue: 1.0).opacity(0.15) }
        if position.isOutfield { return Color(red: 0.204, green: 0.780, blue: 0.349).opacity(0.15) }
        return .clear
    }

    /// Solid category color used for a filled cell's text (design tokens).
    private func cellTextColor(for position: FieldPosition?) -> Color {
        guard let position else { return .primary }
        if position.isAbsent   { return Color(.systemGray) }
        if position.isBench    { return Color(red: 0.557, green: 0.557, blue: 0.576) }
        if position.isInfield  { return Color(red: 0.0, green: 0.478, blue: 1.0) }
        if position.isOutfield { return Color(red: 0.204, green: 0.780, blue: 0.349) }
        return .primary
    }

    /// True when this player's bench assignment in this inning is back-to-back
    /// with another bench inning (immediately before or after). Derived per-cell,
    /// not stored -- recomputed from the grid whenever it changes.
    private func isBackToBackBench(player: Player, inning: Int) -> Bool {
        guard store.lineup.innings[inning].position(for: player) == .bench else { return false }
        let innings = store.lineup.innings
        let prevIsBench = inning > 0 && innings[inning - 1].position(for: player) == .bench
        let nextIsBench = inning < innings.count - 1 && innings[inning + 1].position(for: player) == .bench
        return prevIsBench || nextIsBench
    }

    /// Small badge dot for Emergency/Never position-preference tiers (Pro only).
    /// Replaces the old colored border overlay.
    private func preferenceBadgeColor(player: Player?, position: FieldPosition?) -> Color? {
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
                            positionLabelCell(pos.rawValue, isEven: idx.isMultiple(of: 2))
                            Divider()
                        }
                        ForEach(Array(activeOutfieldPositions.enumerated()), id: \.element) { idx, pos in
                            positionLabelCell(pos.rawValue, isEven: idx.isMultiple(of: 2))
                            Divider()
                        }
                        positionSectionHeader("BENCH")
                        ForEach(0..<benchRowCount, id: \.self) { i in
                            positionLabelCell(benchRowCount == 1 ? "BN" : "BN \(i + 1)", isEven: i.isMultiple(of: 2))
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

        let backToBackBench = isBackToBackBench(player: player, inning: inning)

        return Button {
            quickSetTarget = QuickSetTarget(origin: .player(player), inning: inning)
        } label: {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let pos = position {
                        Text(pos.rawValue)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(cellTextColor(for: pos))
                    } else {
                        Text("+")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color(red: 0.780, green: 0.780, blue: 0.800))
                    }
                }
                .frame(width: colWidth, height: 40)
                .background(pitchWarning != nil ? Color.red.opacity(0.12) : (position != nil ? cellColor(for: position) : Color(.systemBackground)))
                .cornerRadius(8)
                .overlay {
                    if backToBackBench {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.red, lineWidth: 1.5)
                    }
                }
                .contentShape(Rectangle())

                // Preference badge (Emergency/Never tier, Pro only)
                if let badgeColor = preferenceBadgeColor(player: player, position: position) {
                    Circle()
                        .fill(badgeColor)
                        .frame(width: 6, height: 6)
                        .padding(.top, 4)
                        .padding(.trailing, 4)
                } else if pitchWarning != nil {
                    // Red dot in top-right corner when pitcher is ineligible
                    Circle()
                        .fill(Color.red)
                        .frame(width: 6, height: 6)
                        .padding(.top, 4)
                        .padding(.trailing, 4)
                }
            }
        }
        .buttonStyle(.plain)
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

        return Button {
            quickSetTarget = QuickSetTarget(origin: .position(position, benchIndex: benchIndex), inning: inning)
        } label: {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let player = assignedPlayer {
                        Text("\(player.firstName) \(player.lastName.prefix(1)).")
                            .font(.system(size: 13, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .foregroundColor(cellTextColor(for: position))
                    } else {
                        Text("+")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color(red: 0.780, green: 0.780, blue: 0.800))
                    }
                }
                .frame(width: colWidth, height: 40)
                .background(assignedPlayer != nil ? cellColor(for: position) : Color(.systemBackground))
                .cornerRadius(8)
                .overlay {
                    if let player = assignedPlayer, isBackToBackBench(player: player, inning: inning), position.isBench {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.red, lineWidth: 1.5)
                    }
                }
                .contentShape(Rectangle())

                if let badgeColor = preferenceBadgeColor(player: assignedPlayer, position: position) {
                    Circle()
                        .fill(badgeColor)
                        .frame(width: 6, height: 6)
                        .padding(.top, 4)
                        .padding(.trailing, 4)
                }
            }
        }
        .buttonStyle(.plain)
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
