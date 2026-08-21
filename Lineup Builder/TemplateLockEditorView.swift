import SwiftUI

// MARK: - TemplateLockEditorView
// Presented from LineupView's "Save as Template" action. Snapshots the
// active lineup's batting order and position assignments, then lets the
// coach tap individual filled cells to mark them "locked" — everything
// else stays open when the template is later applied to a new lineup.
// Batting order itself is not editable here; it is always fully specified
// on the template exactly as it stands in the active lineup.
//
// Also presented from GameLogDetailView with a `sourceLog`, which swaps the
// active lineup for an archived game as the grid being locked. In that mode
// every filled cell starts locked and the name is pre-filled from the
// opponent — a coach saving a past game as a template is usually reusing the
// whole rotation, and unlocking a few cells is less work than locking most.

struct TemplateLockEditorView: View {
    @EnvironmentObject var store: LineupStore
    @EnvironmentObject var purchaseManager: PurchaseManager
    @Environment(\.dismiss) var dismiss

    /// Archived game to build the template from. Nil means the active lineup.
    var sourceLog: GameLog? = nil
    /// Called after a successful save, so the presenting screen can confirm.
    var onSaved: (() -> Void)? = nil

    @State private var name: String = ""
    @State private var lockedCells: Set<PositionInningKey> = []
    @State private var snapshot: Lineup = Lineup()
    @State private var roster: [Player] = []
    @State private var showingPaywall = false
    @State private var makeDefault = false

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
                } header: {
                    Text("Template name")
                } footer: {
                    Text(nameFooter)
                }

                Section {
                    Toggle(isOn: $makeDefault) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Use for every new game")
                            Text("Only one template can be your default")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    // A template with nothing locked would auto-apply an empty
                    // grid, so there's nothing to make default yet.
                    .disabled(lockedCells.isEmpty)
                    .onChange(of: lockedCells.isEmpty) { _, isEmpty in
                        if isEmpty { makeDefault = false }
                    }
                } footer: {
                    Text(defaultFooter)
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
            .onAppear { loadSnapshot() }
            .fullScreenCover(isPresented: $showingPaywall) {
                ProGate(source: "lineup_template", navTitle: "Lineup Templates") {
                    TemplateLockPreviewView()
                }
                .environmentObject(purchaseManager)
            }
        }
    }

    // MARK: - Snapshot Loading

    /// Runs once on appear. For the archived-game path the grid comes from
    /// store.lineupFromGameLog, so it's already scoped to the current roster
    /// and game length — every cell showing a player is a cell that would
    /// actually be filled if the log were applied.
    private func loadSnapshot() {
        roster = store.players

        guard let log = sourceLog else {
            snapshot = store.lineup
            return
        }

        snapshot = store.lineupFromGameLog(log)
        if name.isEmpty {
            name = log.opponent.isEmpty
                ? "\(log.gameDate.formatted(date: .abbreviated, time: .omitted)) lineup"
                : "vs. \(log.opponent) lineup"
        }
        lockedCells = allFilledCells()
    }

    /// The archived-game path explains what a template is for — the coach
    /// arrived here from History and may never have used one. The lineup path
    /// keeps the shorter instruction, since they're already in the grid.
    private var nameFooter: String {
        sourceLog == nil
            ? "Tap a filled cell to lock it into the template, or tap All, a position, or an inning header to lock a whole group at once. Everything else stays open for you to fill in manually or with Auto-Fill next time."
            : "Templates appear when you start a new game, so you can drop in this batting order and defensive plan in one tap. Tap a filled cell below to unlock it if you'd rather leave that spot open — or tap None, a position, or an inning header to unlock a whole group at once."
    }

    /// Names the template being displaced, so turning the toggle on is never a
    /// silent swap of a default the coach set up earlier.
    private var defaultFooter: String {
        guard !lockedCells.isEmpty else {
            return "Lock at least one cell below to use this template for every new game."
        }
        guard makeDefault else {
            return "Turn this on to have these locked assignments filled in automatically whenever you start a new game. You can still change any of them game by game."
        }
        if let current = store.defaultTemplate, current.name != name.trimmingCharacters(in: .whitespaces) {
            return "These locked assignments will fill in automatically when you start a new game, replacing “\(current.name)” as your default template."
        }
        return "These locked assignments will fill in automatically when you start a new game. Your batting order carries over from the previous game as usual."
    }

    /// Every cell in the snapshot that has a player in it, across the
    /// positions active under the current ruleset.
    private func allFilledCells() -> Set<PositionInningKey> {
        var cells: Set<PositionInningKey> = []
        for position in activePositions {
            for inning in 0..<inningCount where snapshot.innings[inning].player(at: position, in: roster) != nil {
                cells.insert(PositionInningKey(position: position, inning: inning))
            }
        }
        return cells
    }

    // MARK: - Grid Rows

    private let labelWidth: CGFloat = 56
    private let cellWidth: CGFloat = 64

    /// The corner cell toggles every filled cell in the grid; each inning
    /// header toggles that inning's column. Both mirror the row toggles on the
    /// position labels, so a coach can lock a whole rotation, a single inning,
    /// or a single position without tapping cell by cell.
    private var inningHeaderRow: some View {
        let everyCell = allFilledCells()

        return HStack(spacing: 4) {
            Button {
                toggle(everyCell)
            } label: {
                headerLabel(
                    isFullyLocked(everyCell) ? "None" : "All",
                    font: .caption2.bold(),
                    width: labelWidth,
                    alignment: .leading,
                    isActionable: !everyCell.isEmpty
                )
            }
            .buttonStyle(.plain)
            .disabled(everyCell.isEmpty)
            .accessibilityLabel(isFullyLocked(everyCell) ? "Unlock all cells" : "Lock all cells")

            ForEach(0..<inningCount, id: \.self) { inning in
                let cells = filledCells(inInning: inning)
                Button {
                    toggle(cells)
                } label: {
                    headerLabel(
                        "Inn \(inning + 1)",
                        font: .caption2,
                        width: cellWidth,
                        alignment: .center,
                        isActionable: !cells.isEmpty
                    )
                }
                .buttonStyle(.plain)
                .disabled(cells.isEmpty)
                .accessibilityLabel(isFullyLocked(cells) ? "Unlock inning \(inning + 1)" : "Lock inning \(inning + 1)")
            }
        }
    }

    /// Headers that can actually toggle something get a tinted capsule so they
    /// read as controls rather than labels; the ones with nothing to toggle
    /// stay bare text, which also keeps the empty corner cell quiet.
    private func headerLabel(
        _ text: String,
        font: Font,
        width: CGFloat,
        alignment: Alignment,
        isActionable: Bool
    ) -> some View {
        Text(text)
            .font(font)
            .foregroundColor(isActionable ? .accentColor : .secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background {
                if isActionable {
                    Capsule().fill(Color.accentColor.opacity(0.12))
                }
            }
            .frame(width: width, alignment: alignment)
    }

    @ViewBuilder
    private func positionRow(_ position: FieldPosition) -> some View {
        let rowCells = filledCells(at: position)

        HStack(spacing: 4) {
            Button {
                toggle(rowCells)
            } label: {
                headerLabel(
                    position.rawValue,
                    font: .caption.bold(),
                    width: labelWidth,
                    alignment: .leading,
                    isActionable: !rowCells.isEmpty
                )
            }
            .buttonStyle(.plain)
            .disabled(rowCells.isEmpty)
            .accessibilityLabel(isFullyLocked(rowCells) ? "Unlock all \(position.rawValue)" : "Lock all \(position.rawValue)")

            ForEach(0..<inningCount, id: \.self) { inning in
                cell(position: position, inning: inning)
            }
        }
    }

    // MARK: - Bulk Selection

    /// A group counts as locked only when every filled cell in it is locked,
    /// so a partially locked row or inning fills in rather than clearing.
    private func isFullyLocked(_ cells: Set<PositionInningKey>) -> Bool {
        !cells.isEmpty && cells.isSubset(of: lockedCells)
    }

    private func toggle(_ cells: Set<PositionInningKey>) {
        guard !cells.isEmpty else { return }
        if isFullyLocked(cells) {
            lockedCells.subtract(cells)
        } else {
            lockedCells.formUnion(cells)
        }
    }

    private func filledCells(at position: FieldPosition) -> Set<PositionInningKey> {
        var cells: Set<PositionInningKey> = []
        for inning in 0..<inningCount where snapshot.innings[inning].player(at: position, in: roster) != nil {
            cells.insert(PositionInningKey(position: position, inning: inning))
        }
        return cells
    }

    private func filledCells(inInning inning: Int) -> Set<PositionInningKey> {
        var cells: Set<PositionInningKey> = []
        for position in activePositions where snapshot.innings[inning].player(at: position, in: roster) != nil {
            cells.insert(PositionInningKey(position: position, inning: inning))
        }
        return cells
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
            // Only paywall once StoreKit has confirmed "not Pro". While
            // undetermined this would gate the coach *and* silently discard
            // the template they just built.
            if purchaseManager.showsLockedUI { showingPaywall = true }
            return
        }

        let locks = buildPositionLocks()
        let template = LineupTemplate(
            name: name.trimmingCharacters(in: .whitespaces),
            battingOrder: snapshot.battingOrder,
            positionLocks: locks
        )
        store.saveTemplate(template)
        if makeDefault {
            store.setDefaultTemplate(id: template.id)
        }
        dismiss()
        onSaved?()
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
