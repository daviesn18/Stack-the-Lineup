import SwiftUI

struct PositionSummaryView: View {
    @EnvironmentObject var store: LineupStore

    var displayPlayers: [Player] {
        let active = store.lineup.activePlayers(from: store.players)
        let ordered = store.lineup.orderedPlayers(from: active)
        return ordered.isEmpty ? active : ordered
    }

    var inningCount: Int {
        store.lineup.innings.count
    }

    /// Compute the width needed for the player name column based on the longest name
    var playerColumnWidth: CGFloat {
        let font = UIFont.preferredFont(forTextStyle: .caption1)
        let maxWidth = displayPlayers.reduce(CGFloat(0)) { current, player in
            let firstWidth = (player.firstName as NSString).size(withAttributes: [.font: font]).width
            let lastWidth = (player.lastName as NSString).size(withAttributes: [.font: font]).width
            return max(current, max(firstWidth, lastWidth))
        }
        // Add padding (12 leading + 8 trailing) and clamp to a reasonable range
        return min(max(maxWidth + 20, 60), 160)
    }

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
            GeometryReader { geo in
                let nameWidth = playerColumnWidth + 12 // include leading padding
                let minInningWidth: CGFloat = 52
                let availableForInnings = geo.size.width - nameWidth
                let inningWidth = max(minInningWidth, availableForInnings / CGFloat(inningCount))

                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        ScrollView(.horizontal) {
                            VStack(spacing: 0) {
                                // Header row
                                headerRow(inningWidth: inningWidth)

                                Divider()

                                // Player rows
                                LazyVStack(spacing: 0) {
                                    ForEach(Array(displayPlayers.enumerated()), id: \.element.id) { index, player in
                                        playerRow(player: player, isEven: index.isMultiple(of: 2), inningWidth: inningWidth)
                                        Divider()
                                    }
                                }
                            }
                            .frame(minWidth: geo.size.width)
                        }

                        // Fair Play Warnings
                        fairPlaySection
                    }
                }
            }
        }
    }

    // MARK: - Header Row

    private func headerRow(inningWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            Text("Player")
                .font(.caption.bold())
                .frame(width: playerColumnWidth, alignment: .leading)
                .padding(.leading, 12)
                .padding(.vertical, 10)

            ForEach(0..<inningCount, id: \.self) { inning in
                Text("\(inning + 1)")
                    .font(.caption.bold())
                    .frame(width: inningWidth)
                    .padding(.vertical, 10)
            }
        }
        .background(Color(.systemGray5))
    }

    // MARK: - Player Row

    private func playerRow(player: Player, isEven: Bool, inningWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            // Player name column
            VStack(alignment: .leading, spacing: 2) {
                Text(player.firstName)
                    .font(.caption.bold())
                    .lineLimit(1)
                Text(player.lastName)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(width: playerColumnWidth, alignment: .leading)
            .padding(.leading, 12)
            .padding(.vertical, 6)

            // Inning cells
            ForEach(0..<inningCount, id: \.self) { inning in
                positionCell(player: player, inning: inning, inningWidth: inningWidth)
            }
        }
        .background(isEven ? Color(.systemBackground) : Color(.systemGray6).opacity(0.5))
    }

    // MARK: - Fair Play Warnings

    @ViewBuilder
    private var fairPlaySection: some View {
        let activePlayers = store.lineup.activePlayers(from: store.players)
        let noInfield = store.lineup.playersWithoutInfield(players: activePlayers)
        let noOutfield = store.lineup.playersWithoutOutfield(players: activePlayers)
        let hasAssignments = store.lineup.innings.contains(where: { !$0.assignments.isEmpty })

        // Consecutive bench warnings
        let consecutiveBenchPlayers: [Player] = activePlayers.filter { player in
            (0..<6).contains(where: { i in
                store.lineup.innings[i].position(for: player) == .bench &&
                store.lineup.innings[i + 1].position(for: player) == .bench
            })
        }

        if !noInfield.isEmpty || !noOutfield.isEmpty || !consecutiveBenchPlayers.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("Fair Play Warnings", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.bold())
                    .foregroundColor(.orange)

                if !noInfield.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Missing Infield Inning")
                            .font(.caption.bold())
                            .foregroundColor(.orange)
                        Text(noInfield.map(\.displayName).joined(separator: ", "))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if !noOutfield.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Missing Outfield Inning")
                            .font(.caption.bold())
                            .foregroundColor(.orange)
                        Text(noOutfield.map(\.displayName).joined(separator: ", "))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if !consecutiveBenchPlayers.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Back-to-Back Bench")
                            .font(.caption.bold())
                            .foregroundColor(.red)
                        Text(consecutiveBenchPlayers.map(\.displayName).joined(separator: ", "))
                            .font(.caption)
                            .foregroundColor(.secondary)
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

    // MARK: - Position Cell

    private func positionCell(player: Player, inning: Int, inningWidth: CGFloat) -> some View {
        let position = store.lineup.innings[inning].position(for: player)

        return Menu {
            // Infield section
            Section("Infield") {
                ForEach(FieldPosition.infieldPositions, id: \.self) { pos in
                    positionMenuButton(player: player, inning: inning, position: pos, current: position)
                }
            }

            // Outfield section
            Section("Outfield") {
                ForEach(FieldPosition.outfieldPositions, id: \.self) { pos in
                    positionMenuButton(player: player, inning: inning, position: pos, current: position)
                }
            }

            // Bench
            Section {
                positionMenuButton(player: player, inning: inning, position: .bench, current: position)
            }

            // Clear option
            if position != nil {
                Section {
                    Button(role: .destructive) {
                        store.lineup.innings[inning].removeAssignment(for: player)
                        store.save()
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
            .frame(width: inningWidth, height: 32)
            .contentShape(Rectangle())
        }
    }

    @ViewBuilder
    private func positionMenuButton(player: Player, inning: Int, position: FieldPosition, current: FieldPosition?) -> some View {
        let occupant = store.lineup.innings[inning].player(at: position, in: store.players)
        let occupiedByOther = occupant != nil && occupant?.id != player.id && !position.isBench
        let isCurrentPlayerPosition = current == position

        Button {
            if !position.isBench, let existing = occupant, existing.id != player.id {
                store.lineup.innings[inning].removeAssignment(for: existing)
            }
            store.lineup.innings[inning].assign(player: player, position: position)
            store.save()
        } label: {
            HStack {
                if occupiedByOther, let other = occupant {
                    Text("\(position.displayName) — \(other.firstName)")
                        .strikethrough()
                } else if isCurrentPlayerPosition {
                    Text(styledCurrentPosition(position.displayName))
                } else {
                    Text(position.displayName)
                }
            }
            if isCurrentPlayerPosition {
                Image(systemName: "checkmark")
            }
        }
    }

    private func styledCurrentPosition(_ name: String) -> AttributedString {
        var str = AttributedString(name)
        str.strikethroughStyle = .single
        str.font = .callout.italic()
        str.foregroundColor = .secondary
        return str
    }
}
