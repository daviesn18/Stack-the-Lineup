import SwiftUI

// MARK: - GameLogDetailView
// Read-only view for a single archived game log.
// Shows batting order and the full 7-inning defensive grid.
// Innings beyond inningsPlayed are visually dimmed.

struct GameLogDetailView: View {
    @EnvironmentObject var store: LineupStore
    @EnvironmentObject var purchaseManager: PurchaseManager
    let log: GameLog

    @State private var showingPitchCountEdit = false

    private var archivedAtString: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return "Archived \(f.string(from: log.archivedAt))"
    }

    private var orderedPlayers: [PlayerSnapshot] {
        log.battingOrder.compactMap { id in log.snapshot(for: id) }
    }

    private var benchOnlyPlayers: [PlayerSnapshot] {
        let orderedIDs = Set(log.battingOrder)
        return log.playerSnapshot.filter { !orderedIDs.contains($0.id) }
    }

    /// Pitch count entries resolved to display names, sorted by pitches descending.
    private var pitchCountEntries: [(name: String, pitches: Int)] {
        log.pitchCounts
            .compactMap { (uuidString, count) -> (String, Int)? in
                guard count > 0, let uuid = UUID(uuidString: uuidString) else { return nil }
                let name = log.snapshot(for: uuid)?.displayName
                    ?? store.players.first(where: { $0.id == uuid })?.displayName
                    ?? "Unknown"
                return (name, count)
            }
            .sorted { $0.1 > $1.1 }
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
                        infoRow(label: "Innings Played", value: "\(log.inningsPlayed) of \(log.innings.count)")
                        Divider().padding(.vertical, 6)
                        infoRow(label: "Archived", value: archivedAtString, valueFont: .caption)
                    }
                }
                .padding(.horizontal)
                .padding(.top)

                // Pitch Counts — shown to Pro users, always accessible for retroactive entry
                if purchaseManager.isPro {
                    HStack {
                        Text("Pitch Counts")
                            .font(.headline)
                        Spacer()
                        Button {
                            showingPitchCountEdit = true
                        } label: {
                            Label(
                                pitchCountEntries.isEmpty ? "Add" : "Edit",
                                systemImage: pitchCountEntries.isEmpty ? "plus.circle" : "pencil"
                            )
                            .font(.subheadline)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                    GroupBox {
                        if pitchCountEntries.isEmpty {
                            Button {
                                showingPitchCountEdit = true
                            } label: {
                                HStack {
                                    Image(systemName: "figure.baseball.pitcher")
                                        .foregroundStyle(.secondary)
                                    Text("No pitch counts recorded. Tap Add to enter them.")
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(pitchCountEntries.enumerated()), id: \.offset) { index, entry in
                                    if index > 0 { Divider().padding(.vertical, 4) }
                                    HStack {
                                        Text(entry.name)
                                        Spacer()
                                        Text("\(entry.pitches) pitches")
                                            .foregroundColor(.secondary)
                                            .font(.subheadline)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }

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

                // Defensive Grid
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
        .sheet(isPresented: $showingPitchCountEdit) {
            RetroactivePitchCountSheet(log: log)
                .environmentObject(store)
        }
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

// MARK: - Retroactive Pitch Count Sheet

/// Lets the coach add or edit pitch counts on an already-archived game.
/// Players are sourced from the game's snapshot so names always match
/// what was on the roster at game time. The coach can also add players
/// who weren't in the snapshot (e.g. a pitcher who subbed in late).
struct RetroactivePitchCountSheet: View {
    @EnvironmentObject var store: LineupStore
    @Environment(\.dismiss) var dismiss

    let log: GameLog

    @State private var counts: [UUID: String] = [:]
    @State private var includedIDs: [UUID] = []
    @State private var showingAddPitcher = false

    /// All players in the snapshot, keyed by ID for fast lookup.
    private var snapshotByID: [UUID: PlayerSnapshot] {
        Dictionary(uniqueKeysWithValues: log.playerSnapshot.map { ($0.id, $0) })
    }

    /// Display name for a UUID — snapshot first, live roster fallback.
    private func displayName(for id: UUID) -> String {
        snapshotByID[id]?.displayName
            ?? store.players.first(where: { $0.id == id })?.displayName
            ?? "Unknown"
    }

    /// Players in the snapshot who aren't already in the list.
    private var availableToAdd: [PlayerSnapshot] {
        log.playerSnapshot
            .filter { !includedIDs.contains($0.id) }
            .sorted { $0.displayName < $1.displayName }
    }

    private var canSave: Bool { !includedIDs.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Enter pitches thrown in this game. Changes update eligibility calculations going forward.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if includedIDs.isEmpty {
                    Section {
                        Text("No pitchers listed. Tap Add Pitcher to enter counts.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        ForEach(includedIDs, id: \.self) { id in
                            HStack {
                                Text(displayName(for: id))
                                Spacer()
                                TextField("0", text: countBinding(for: id))
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 64)
                                    .foregroundStyle(.blue)
                                    .fontWeight(.semibold)
                            }
                        }
                        .onDelete { offsets in
                            for i in offsets {
                                let id = includedIDs[i]
                                counts.removeValue(forKey: id)
                            }
                            includedIDs.remove(atOffsets: offsets)
                        }
                    }
                }

                Section {
                    Button {
                        showingAddPitcher = true
                    } label: {
                        Label("Add Pitcher", systemImage: "plus.circle")
                    }
                }
            }
            .navigationTitle("Pitch Counts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .sheet(isPresented: $showingAddPitcher) {
                RetroactivePitcherPickerSheet(available: availableToAdd) { snapshot in
                    if !includedIDs.contains(snapshot.id) {
                        includedIDs.append(snapshot.id)
                        counts[snapshot.id] = ""
                    }
                }
            }
            .onAppear { loadExisting() }
        }
    }

    private func loadExisting() {
        // Pre-populate from any existing pitch counts on the log
        var ids: [UUID] = []
        for (uuidString, count) in log.pitchCounts where count > 0 {
            if let id = UUID(uuidString: uuidString) {
                ids.append(id)
                counts[id] = "\(count)"
            }
        }
        // If no existing counts, pre-populate detected pitchers from the grid
        if ids.isEmpty {
            ids = log.innings.flatMap { inning in
                inning.assignments.compactMap { (playerID, pos) -> UUID? in
                    pos == .pitcher ? playerID : nil
                }
            }
            var seen = Set<UUID>()
            ids = ids.filter { seen.insert($0).inserted }
            for id in ids { counts[id] = "" }
        }
        includedIDs = ids
    }

    private func countBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { counts[id] ?? "" },
            set: { counts[id] = $0 }
        )
    }

    private func save() {
        var parsed: [String: Int] = [:]
        for (id, text) in counts {
            if let value = Int(text), value > 0 {
                parsed[id.uuidString] = value
            }
        }
        // replacePitchCounts replaces the entire dict so removed pitchers are cleared
        store.replacePitchCounts(parsed, for: log.id)
        Analytics.signal("pitchcounts.retroactive", parameters: [
            "pitcherCount": "\(parsed.count)"
        ])
        dismiss()
    }
}

// MARK: - Retroactive Pitcher Picker Sheet

private struct RetroactivePitcherPickerSheet: View {
    @Environment(\.dismiss) var dismiss
    let available: [PlayerSnapshot]
    let onSelect: (PlayerSnapshot) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if available.isEmpty {
                    ContentUnavailableView(
                        "All players added",
                        systemImage: "person.crop.circle.badge.checkmark",
                        description: Text("Every player in this game's roster has been added.")
                    )
                } else {
                    List(available) { snap in
                        Button {
                            onSelect(snap)
                            dismiss()
                        } label: {
                            HStack {
                                Text(snap.displayName)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if !snap.number.isEmpty {
                                    Text("#\(snap.number)")
                                        .foregroundStyle(.secondary)
                                        .font(.subheadline)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add Pitcher")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
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

                    ForEach(0..<log.innings.count, id: \.self) { i in
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
                            ForEach(0..<log.innings.count, id: \.self) { inningIndex in
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
