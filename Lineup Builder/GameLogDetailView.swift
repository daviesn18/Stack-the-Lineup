import SwiftUI

// MARK: - GameLogDetailView
// Read-only view for a single archived game log.
// Shows batting order and the full 7-inning defensive grid.
// Innings beyond inningsPlayed are visually dimmed.

struct GameLogDetailView: View {
    @EnvironmentObject var store: LineupStore
    let log: GameLog

    private var archivedAtString: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return "Archived \(f.string(from: log.archivedAt))"
    }

    private var orderedPlayers: [PlayerSnapshot] {
        log.battingOrder.compactMap { id in
            log.snapshot(for: id)
        }
    }

    // Players in the snapshot who are NOT in the batting order
    private var benchOnlyPlayers: [PlayerSnapshot] {
        let orderedIDs = Set(log.battingOrder)
        return log.playerSnapshot.filter { !orderedIDs.contains($0.id) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                // Game Info
                GroupBox {
                    VStack(spacing: 0) {
                        infoRow(label: "Date", value: log.gameDate.formatted(date: .long, time: .omitted))
                        Divider().padding(.vertical, 6)
                        infoRow(label: "Opponent", value: log.opponent.isEmpty ? "No Opponent" : log.opponent)
                        Divider().padding(.vertical, 6)
                        infoRow(label: "Innings Played", value: "\(log.inningsPlayed) of 7")
                        Divider().padding(.vertical, 6)
                        infoRow(label: "Archived", value: archivedAtString, valueFont: .caption)
                    }
                }
                .padding(.horizontal)
                .padding(.top)

                // Batting Order
                Text("Batting Order")
                    .font(.headline)
                    .padding(.horizontal)
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                GroupBox {
                    if orderedPlayers.isEmpty {
                        Text("No batting order recorded")
                            .foregroundColor(.secondary)
                            .font(.callout)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(orderedPlayers.enumerated()), id: \.element.id) { index, snap in
                                if index > 0 { Divider().padding(.vertical, 4) }
                                HStack {
                                    Text("\(index + 1).")
                                        .font(.headline)
                                        .foregroundColor(.secondary)
                                        .frame(width: 32, alignment: .leading)
                                    Text(snap.displayName)
                                    Spacer()
                                    if !snap.number.isEmpty {
                                        Text("#\(snap.number)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)

                // Defensive Grid — unconstrained, full height
                Text("Defensive Positions")
                    .font(.headline)
                    .padding(.horizontal)
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                ArchivedPositionGridView(log: log)
                    .padding(.bottom, 32)
            }
        }
        .navigationTitle(log.opponent.isEmpty ? "Game Log" : "vs. \(log.opponent)")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground))
    }

    @ViewBuilder
    private func infoRow(label: String, value: String, valueFont: Font = .body) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.primary)
            Spacer()
            Text(value)
                .font(valueFont)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - ArchivedPositionGridView
// Read-only grid showing all players × all innings.
// Innings beyond inningsPlayed are dimmed with "—".

struct ArchivedPositionGridView: View {
    let log: GameLog

    private var orderedSnapshots: [PlayerSnapshot] {
        // Show batting order first, then anyone else
        let ordered = log.battingOrder.compactMap { id in log.snapshot(for: id) }
        let orderedIDs = Set(log.battingOrder)
        let rest = log.playerSnapshot.filter { !orderedIDs.contains($0.id) }
            .sorted { $0.displayName < $1.displayName }
        return ordered + rest
    }

    private var playerColumnWidth: CGFloat {
        let font = UIFont.preferredFont(forTextStyle: .caption1)
        let maxWidth = orderedSnapshots.reduce(CGFloat(0)) { current, snap in
            let w1 = (snap.firstName as NSString).size(withAttributes: [.font: font]).width
            let w2 = (snap.lastName as NSString).size(withAttributes: [.font: font]).width
            return max(current, max(w1, w2))
        }
        return min(max(maxWidth + 20, 60), 160)
    }

    var body: some View {
        let inningWidth: CGFloat = 44

        ScrollView(.horizontal, showsIndicators: false) {
            VStack(spacing: 0) {
                // Header row
                HStack(spacing: 0) {
                    Text("Player")
                        .font(.caption.bold())
                        .frame(width: playerColumnWidth, alignment: .leading)
                        .padding(.leading, 12)
                        .padding(.vertical, 8)

                    ForEach(0..<7, id: \.self) { i in
                        let played = i < log.inningsPlayed
                        Text("\(i + 1)")
                            .font(.caption.bold())
                            .frame(width: inningWidth)
                            .padding(.vertical, 8)
                            .opacity(played ? 1.0 : 0.35)
                    }
                }
                .background(Color(.systemGray5))

                Divider()

                // Player rows
                ForEach(Array(orderedSnapshots.enumerated()), id: \.element.id) { rowIndex, snap in
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            // Name column
                            VStack(alignment: .leading, spacing: 2) {
                                Text(snap.firstName)
                                    .font(.caption.bold())
                                    .lineLimit(1)
                                Text(snap.lastName)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(width: playerColumnWidth, alignment: .leading)
                            .padding(.leading, 12)
                            .padding(.vertical, 6)

                            // Inning cells
                            ForEach(0..<7, id: \.self) { inningIndex in
                                let played = inningIndex < log.inningsPlayed
                                let position = log.innings[inningIndex].assignments[snap.id]

                                positionCell(
                                    position: position,
                                    played: played,
                                    width: inningWidth,
                                    playerName: snap.displayName,
                                    inning: inningIndex
                                )
                            }
                        }
                        .background(rowIndex.isMultiple(of: 2)
                            ? Color(.systemBackground)
                            : Color(.systemGray6).opacity(0.5))

                        Divider()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func positionCell(
        position: FieldPosition?,
        played: Bool,
        width: CGFloat,
        playerName: String,
        inning: Int
    ) -> some View {
        let label: String = {
            guard played else { return "—" }
            return position?.rawValue ?? "—"
        }()

        let accessibilityLabel: String = {
            guard played else { return "Inning \(inning + 1) not played" }
            return position.map { "\(playerName), Inning \(inning + 1): \($0.displayName)" }
                ?? "\(playerName), Inning \(inning + 1): unassigned"
        }()

        Text(label)
            .font(.caption2.bold())
            .foregroundColor(played ? positionColor(position) : .secondary)
            .frame(width: width, height: 32)
            .opacity(played ? 1.0 : 0.3)
            .accessibilityLabel(accessibilityLabel)
    }

    private func positionColor(_ pos: FieldPosition?) -> Color {
        guard let pos else { return .secondary }
        if pos.isBench { return .secondary }
        if pos.isInfield { return .blue }
        return .green
    }
}
