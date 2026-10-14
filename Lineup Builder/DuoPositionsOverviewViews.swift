import SwiftUI

// MARK: - By Position: whole-game grid (right half)
//
// Every position against every inning. The focused position's deep dive is on
// the left; tapping a cell focuses that position and opens the picker over the
// left half, so the grid stays in view while it's edited.

struct DuoWholeGameGrid: View {
    @EnvironmentObject var store: LineupStore
    @EnvironmentObject var purchaseManager: PurchaseManager
    @Environment(DuoPositionsModel.self) private var model

    private var isReadOnly: Bool { store.activeTeam.isReadOnly }
    private var inningCount: Int { store.lineup.innings.count }
    private var positions: [FieldPosition] { store.duoFieldPositions }
    private var activePlayers: [Player] { store.lineup.activePlayers(from: store.players) }

    private let labelWidth: CGFloat = 36
    private let gap: CGFloat = 3

    private var focused: FieldPosition {
        positions.contains(model.focusedPosition) ? model.focusedPosition : (positions.first ?? .shortstop)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Whole game")
                    .font(.system(size: 22, weight: .bold))
                    .tracking(-0.4)
                Text("Tap a cell to place a player. Tap a position to focus it.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }

            VStack(spacing: gap) {
                headerRow

                ForEach(positions.filter { $0.isInfield }, id: \.self) { row($0) }
                Color.clear.frame(height: 6 - gap)
                ForEach(positions.filter { $0.isOutfield }, id: \.self) { row($0) }

                Color.clear.frame(height: 6 - gap)
                benchRow
            }
        }
    }

    // MARK: Header

    private var headerRow: some View {
        HStack(spacing: gap) {
            Color.clear.frame(width: labelWidth, height: 1)
            ForEach(0..<inningCount, id: \.self) { inning in
                Button {
                    // Jump to By Inning at this inning. Mode first: switching
                    // it would otherwise close the picker the inning change opened.
                    model.mode = .inning
                    model.inning = inning
                } label: {
                    VStack(spacing: 3) {
                        Text("Inn \(inning + 1)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Circle()
                            .fill(statusColor(inning))
                            .frame(width: 5, height: 5)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 3)
    }

    /// Green when every spot is filled, orange when partly filled, gray when empty.
    private func statusColor(_ inning: Int) -> Color {
        guard !store.lineup.innings[inning].assignments.isEmpty else { return Color(.systemGray3) }
        let open = store.lineup.openPositions(
            inning: inning, players: activePlayers, config: store.fairPlayConfig
        )
        return open.isEmpty ? .green : .orange
    }

    // MARK: Position rows

    private func row(_ position: FieldPosition) -> some View {
        let isFocused = position == focused
        return HStack(spacing: gap) {
            Button {
                model.focusedPosition = position
            } label: {
                DuoPositionBadge(position: position, minWidth: 30, fontSize: 11.5,
                                 horizontalPadding: 4, verticalPadding: 4)
                    .frame(width: labelWidth)
            }
            .buttonStyle(.plain)

            ForEach(0..<inningCount, id: \.self) { inning in
                cell(position, inning: inning)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isFocused ? Color.blue.opacity(0.08) : Color.clear)
        )
        .overlay {
            if isFocused {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.blue.opacity(0.5), lineWidth: 1.5)
            }
        }
    }

    private func cell(_ position: FieldPosition, inning: Int) -> some View {
        let player = store.lineup.innings[inning].player(at: position, in: store.players)
        let isNever = purchaseManager.isPro && player?.positionPreferences[position] == .never
        let isEditing = model.picker?.position == position && model.picker?.inning == inning
        let tint: Color = position.isOutfield ? Color.green.opacity(0.15) : Color.blue.opacity(0.12)

        return Button {
            guard !isReadOnly else { return }
            model.focusedPosition = position
            // The coach tapped the right half, so the picker covers the left.
            model.picker = DuoPickerTarget(position: position, inning: inning, side: .leading)
        } label: {
            Text(player?.firstName ?? "Open")
                .font(.system(size: 11.5, weight: .semibold))
                .tracking(-0.2)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundColor(player == nil ? .orange : (isNever ? .red : .primary))
                .padding(.horizontal, 2)
                .frame(maxWidth: .infinity, minHeight: 32)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(player == nil ? Color(.systemBackground) : tint)
                )
                .overlay {
                    if player == nil {
                        RoundedRectangle(cornerRadius: 7)
                            .strokeBorder(Color(.systemGray3), style: StrokeStyle(lineWidth: 1, dash: [3]))
                    }
                }
                .overlay {
                    if isEditing {
                        RoundedRectangle(cornerRadius: 7)
                            .strokeBorder(Color.blue, lineWidth: 2)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isReadOnly)
    }

    // MARK: Bench

    private var benchRow: some View {
        HStack(alignment: .top, spacing: gap) {
            Text("BN")
                .font(.system(size: 11.5, weight: .bold))
                .foregroundColor(.white)
                .padding(.vertical, 4)
                .frame(minWidth: 30)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(.systemGray)))
                .frame(width: labelWidth)

            ForEach(0..<inningCount, id: \.self) { inning in
                VStack(spacing: 3) {
                    ForEach(benched(inning)) { player in
                        let backToBack = isBackToBack(player, inning: inning)
                        Text(player.firstName)
                            .font(.system(size: 11))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .foregroundColor(backToBack ? .red : .primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 5).fill(Color(.systemBackground)))
                            .overlay {
                                if backToBack {
                                    RoundedRectangle(cornerRadius: 5)
                                        .strokeBorder(Color.red, lineWidth: 1.5)
                                }
                            }
                    }
                }
                .padding(3)
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .top)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.duoFill))
            }
        }
        .padding(3)
    }

    private func benched(_ inning: Int) -> [Player] {
        store.lineup.displayPlayers(from: store.players)
            .filter { store.lineup.innings[inning].position(for: $0) == .bench }
    }

    private func isBackToBack(_ player: Player, inning: Int) -> Bool {
        let innings = store.lineup.innings
        let before = inning > 0 && innings[inning - 1].position(for: player) == .bench
        let after = inning + 1 < innings.count && innings[inning + 1].position(for: player) == .bench
        return before || after
    }
}

// MARK: - Pitching: pitch eligibility (right half)

struct DuoPitchEligibilityPane: View {
    @EnvironmentObject var store: LineupStore
    @EnvironmentObject var purchaseManager: PurchaseManager

    @State private var showingRules = false

    private var config: PitchingConfig { store.pitchingConfig }

    /// Pitching-capable players. Preferences are a Pro feature, so on a free
    /// team everyone who isn't ruled out counts as able to pitch.
    private func canPitch(_ player: Player) -> Bool {
        let pref = player.positionPreferences[.pitcher]
        return purchaseManager.isPro ? (pref != nil && pref != .never) : pref != .never
    }

    private var activePlayers: [Player] { store.lineup.activePlayers(from: store.players) }
    private var pitchers: [Player] { activePlayers.filter(canPitch) }
    private var notSet: [Player] { activePlayers.filter { !canPitch($0) } }

    private var rows: [PitchingGuideSummaryRow] {
        PitchEligibilityEngine.pitchingSummaryRows(
            gameLogs: store.gameLogs, players: pitchers, config: config,
            referenceDate: store.lineup.gameDate
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Pitch eligibility")
                        .font(.system(size: 22, weight: .bold))
                        .tracking(-0.4)
                    Text("From pitch counts logged when games were archived.")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                Spacer(minLength: 8)
                Button("Rules") { showingRules = true }
                    .font(.system(size: 14))
            }

            if rows.isEmpty {
                Text("No players have Pitcher as an available position preference.")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemBackground)))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.player.id) { index, row in
                        eligibilityRow(row)
                        if index < rows.count - 1 {
                            Divider().padding(.leading, 44)
                        }
                    }
                }
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            if !notSet.isEmpty {
                Text("NOT SET TO PITCH")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.4)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
                Text(notSet.map(\.firstName).joined(separator: ", "))
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
        }
        .sheet(isPresented: $showingRules) {
            if let teamID = store.activeTeamID {
                NavigationStack {
                    PitchingRulesView(teamID: teamID)
                }
                .environmentObject(store)
            }
        }
    }

    // MARK: Row

    private struct StatusStyle {
        let label: String
        let background: Color
        let foreground: Color
        let icon: Color
    }

    private func style(for status: PitchEligibilityStatus) -> StatusStyle {
        let gray = StatusStyle(label: "", background: Color.duoFill, foreground: .secondary, icon: Color(.systemGray))
        guard config.rulesEnabled else {
            return StatusStyle(label: "Rules off", background: gray.background,
                               foreground: gray.foreground, icon: gray.icon)
        }
        switch status {
        case .eligible:
            return StatusStyle(label: "Eligible", background: Color.green.opacity(0.14),
                               foreground: .duoStatusClear, icon: .green)
        case .limited:
            return StatusStyle(label: "Limited", background: Color.orange.opacity(0.14),
                               foreground: Color(red: 178 / 255, green: 94 / 255, blue: 0), icon: .orange)
        case .mustRest:
            return StatusStyle(label: "Resting", background: Color.red.opacity(0.1),
                               foreground: Color(red: 215 / 255, green: 0, blue: 21 / 255), icon: .red)
        case .unknownAge:
            return StatusStyle(label: "Age not set", background: gray.background,
                               foreground: gray.foreground, icon: gray.icon)
        }
    }

    /// The most recent outing before the game's date, if any.
    private func lastOuting(_ player: Player) -> (date: Date, pitches: Int)? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: store.lineup.gameDate)
        return store.gameLogs
            .compactMap { log -> (Date, Int)? in
                guard calendar.startOfDay(for: log.gameDate) < today,
                      let pitches = log.pitchCounts[player.id.uuidString], pitches > 0 else { return nil }
                return (log.gameDate, pitches)
            }
            .max { $0.0 < $1.0 }
            .map { (date: $0.0, pitches: $0.1) }
    }

    private func detail(for row: PitchingGuideSummaryRow) -> String {
        if config.rulesEnabled, case .mustRest(let until) = row.status {
            return "Eligible \(until.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))"
        }
        var parts: [String] = []
        if let outing = lastOuting(row.player) {
            let day = outing.date.formatted(.dateTime.month(.abbreviated).day())
            parts.append("\(day): \(outing.pitches) \(outing.pitches == 1 ? "pitch" : "pitches")")
        }
        if config.rulesEnabled {
            var left = row.available
            if case .limited(let remaining) = row.status { left = min(left, remaining) }
            if row.dailyMax > 0 { parts.append("\(left) pitches left") }
        }
        return parts.isEmpty ? "No outings logged" : parts.joined(separator: " · ")
    }

    private func eligibilityRow(_ row: PitchingGuideSummaryRow) -> some View {
        let style = style(for: row.status)
        let tier = purchaseManager.isPro ? row.player.positionPreferences[.pitcher] : nil
        let innings = store.lineup.innings.filter { $0.assignments[row.player.id] == .pitcher }.count

        return HStack(spacing: 10) {
            Image(systemName: "figure.baseball.pitcher")
                .font(.system(size: 20))
                .foregroundColor(style.icon)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.player.displayName)
                        .font(.system(size: 16))
                        .lineLimit(1)
                    if let tier {
                        Text(tier.displayName)
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundColor(tier.duoForeground)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 4).fill(tier.duoBackground))
                    }
                }
                Text(detail(for: row))
                    .font(.system(size: 12.5))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 3) {
                Text(style.label)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(style.foreground)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(style.background))
                Text("\(innings) \(innings == 1 ? "inning" : "innings") today")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(minHeight: 54)
    }
}
