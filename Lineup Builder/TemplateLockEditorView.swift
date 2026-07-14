import SwiftUI

// MARK: - TemplateLockEditorView
// Presented from LineupView's "Save as Template" action. Snapshots the
// active lineup's batting order and position assignments, then lets the
// coach tap individual filled cells to mark them "locked" — everything
// else stays open when the template is later applied to a new lineup.
// Batting order itself is not editable here; it is always fully specified
// on the template exactly as it stands in the active lineup.

struct TemplateLockEditorView: View {
    @EnvironmentObject var store: LineupStore
    @EnvironmentObject var purchaseManager: PurchaseManager
    @Environment(\.dismiss) var dismiss

    @State private var name: String = ""
    @State private var lockedCells: Set<PositionInningKey> = []
    @State private var snapshot: Lineup = Lineup()
    @State private var roster: [Player] = []
    @State private var showingPaywall = false

    private struct PositionInningKey: Hashable {
        let position: FieldPosition
        let inning: Int
    }

    private var activePositions: [FieldPosition] {
        snapshot.activeFieldPositions(config: store.fairPlayConfig)
    }

    private var inningCount: Int { snapshot.innings.count }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Template name", text: $name)
                } footer: {
                    Text("Tap a filled cell to lock it into the template. Everything else stays open for you to fill in manually or with Auto-Fill next time.")
                }

                Section("Position locks") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 6) {
                            inningHeaderRow
                            ForEach(activePositions, id: \.self) { position in
                                positionRow(position)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Save as Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { attemptSave() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                snapshot = store.lineup
                roster = store.players
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView(source: "lineup_template")
                    .environmentObject(purchaseManager)
            }
        }
    }

    // MARK: - Grid Rows

    private let labelWidth: CGFloat = 56
    private let cellWidth: CGFloat = 64

    private var inningHeaderRow: some View {
        HStack(spacing: 4) {
            Text("").frame(width: labelWidth)
            ForEach(0..<inningCount, id: \.self) { inning in
                Text("Inn \(inning + 1)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(width: cellWidth)
            }
        }
    }

    @ViewBuilder
    private func positionRow(_ position: FieldPosition) -> some View {
        HStack(spacing: 4) {
            Text(position.rawValue)
                .font(.caption.bold())
                .foregroundColor(.secondary)
                .frame(width: labelWidth, alignment: .leading)

            ForEach(0..<inningCount, id: \.self) { inning in
                cell(position: position, inning: inning)
            }
        }
    }

    @ViewBuilder
    private func cell(position: FieldPosition, inning: Int) -> some View {
        let player = snapshot.innings[inning].player(at: position, in: roster)
        let key = PositionInningKey(position: position, inning: inning)
        let isLocked = lockedCells.contains(key)

        Button {
            guard player != nil else { return }
            if isLocked {
                lockedCells.remove(key)
            } else {
                lockedCells.insert(key)
            }
        } label: {
            VStack(spacing: 2) {
                Text(player?.shortName ?? "—")
                    .font(.caption2.bold())
                    .lineLimit(1)
                Image(systemName: isLocked ? "lock.fill" : "lock.open")
                    .font(.system(size: 9))
            }
            .frame(width: cellWidth, height: 40)
            .foregroundColor(isLocked ? .white : (player == nil ? Color(.tertiaryLabel) : .secondary))
            .background(isLocked ? Color.blue : Color(.secondarySystemBackground))
            .overlay {
                if !isLocked && player != nil {
                    RoundedRectangle(cornerRadius: 6).strokeBorder(Color(.systemGray3), style: StrokeStyle(lineWidth: 1, dash: [3]))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .disabled(player == nil)
    }

    // MARK: - Save

    private func attemptSave() {
        let existingCount = store.lineupTemplates.count
        guard existingCount == 0 || purchaseManager.isPro else {
            showingPaywall = true
            return
        }

        let locks = buildPositionLocks()
        let template = LineupTemplate(
            name: name.trimmingCharacters(in: .whitespaces),
            battingOrder: snapshot.battingOrder,
            positionLocks: locks
        )
        store.saveTemplate(template)
        dismiss()
    }

    /// Groups locked cells by (position, player), then collapses each
    /// player's locked innings into contiguous ranges. A player locked at
    /// innings 1-2 and separately at inning 4 (not touching 3) produces two
    /// PositionLock entries for that position — that's expected, since a
    /// ClosedRange can't represent a gap.
    private func buildPositionLocks() -> [PositionLock] {
        struct GroupKey: Hashable { let position: FieldPosition; let playerID: UUID }

        var grouped: [GroupKey: [Int]] = [:]
        for key in lockedCells {
            guard let player = snapshot.innings[key.inning].player(at: key.position, in: roster) else { continue }
            grouped[GroupKey(position: key.position, playerID: player.id), default: []].append(key.inning)
        }

        var locks: [PositionLock] = []
        for (groupKey, innings) in grouped {
            for range in contiguousRanges(from: innings) {
                locks.append(PositionLock(playerID: groupKey.playerID, position: groupKey.position, innings: range))
            }
        }
        return locks
    }

    /// Sorts and merges a list of inning indices into the minimal set of
    /// contiguous ClosedRanges. [0, 1, 3, 4, 5] -> [0...1, 3...5].
    private func contiguousRanges(from indices: [Int]) -> [ClosedRange<Int>] {
        let sorted = indices.sorted()
        guard var start = sorted.first else { return [] }
        var prev = start
        var ranges: [ClosedRange<Int>] = []

        for value in sorted.dropFirst() {
            if value == prev + 1 {
                prev = value
            } else {
                ranges.append(start...prev)
                start = value
                prev = value
            }
        }
        ranges.append(start...prev)
        return ranges
    }
}
