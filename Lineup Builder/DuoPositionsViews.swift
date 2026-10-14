import SwiftUI
import TipKit

// MARK: - Design Tokens

extension Color {
    /// The design's "fill" gray (#EFEFF4): bar tracks, chips, unset tiers.
    static let duoFill = Color(red: 239 / 255, green: 239 / 255, blue: 244 / 255)
    /// Fair-play status text, clear and with issues.
    static let duoStatusClear = Color(red: 36 / 255, green: 138 / 255, blue: 61 / 255)
    static let duoStatusIssues = Color(red: 201 / 255, green: 52 / 255, blue: 0)
}

// MARK: - Fair Play Summary
//
// Every fair-play rule evaluated once against the team's own config, shaped for
// the Duo roster: a count for the side bar and status capsule, and one row per
// rule that has something to say.

struct DuoWarning: Identifiable {
    enum Severity { case red, orange }
    let id: String
    let severity: Severity
    let title: String
    let detail: String
}

struct DuoFairPlaySummary {
    let findings: FairPlayFindings
    let hasAnyAssignments: Bool
    let warnings: [DuoWarning]
    private let unfilledCount: Int

    /// Players counted once each, plus open field slots — the same two units the
    /// iPad's pill has always counted together.
    var issueCount: Int { findings.implicatedPlayerIDs.count + unfilledCount }

    init(store: LineupStore) {
        let lineup = store.lineup
        let findings = lineup.fairPlayFindings(players: store.players, config: store.fairPlayConfig)
        let hasAny = lineup.innings.contains { !$0.assignments.isEmpty }

        // Unfilled field positions: innings that have at least one assignment
        // but are missing an expected position (the pitcher, say).
        var unfilled: [(inning: Int, position: FieldPosition)] = []
        if hasAny {
            let expected = lineup.activeFieldPositions(config: store.fairPlayConfig)
            for (i, inning) in lineup.innings.enumerated() where !inning.assignments.isEmpty {
                let filled = Set(inning.assignments.values)
                for position in expected where !filled.contains(position) {
                    unfilled.append((i, position))
                }
            }
        }

        func names(_ players: [Player]) -> String {
            players.map { $0.firstName }.joined(separator: ", ")
        }

        var warnings: [DuoWarning] = []
        if !unfilled.isEmpty {
            // First two spots, then "+N more".
            let spots = unfilled.map { "\($0.position.rawValue) (Inning \($0.inning + 1))" }
            let detail = spots.prefix(2).joined(separator: ", ")
                + (spots.count > 2 ? " +\(spots.count - 2) more" : "")
            warnings.append(DuoWarning(id: "unfilled", severity: .red, title: "Positions not filled", detail: detail))
        }
        if !findings.backToBackBench.isEmpty {
            warnings.append(DuoWarning(id: "backToBack", severity: .red, title: "Back-to-back bench",
                                       detail: names(findings.backToBackBench)))
        }
        if !findings.withoutInfield.isEmpty {
            warnings.append(DuoWarning(id: "noInfield", severity: .orange, title: "Missing infield inning",
                                       detail: names(findings.withoutInfield)))
        }
        if !findings.withoutOutfield.isEmpty {
            warnings.append(DuoWarning(id: "noOutfield", severity: .orange, title: "Missing outfield inning",
                                       detail: names(findings.withoutOutfield)))
        }
        if !findings.underFieldingMinimum.isEmpty {
            warnings.append(DuoWarning(id: "underMin", severity: .orange, title: "Under minimum innings fielded",
                                       detail: names(findings.underFieldingMinimum)))
        }
        // Red, like the other hard rules: these are league restrictions on a
        // kid's arm, not playing-time fairness.
        if !findings.catcherThenPitcher.isEmpty {
            warnings.append(DuoWarning(id: "catcherThenPitcher", severity: .red, title: "Caught, then pitched",
                                       detail: names(findings.catcherThenPitcher)))
        }
        if !findings.pitcherThenCatcher.isEmpty {
            warnings.append(DuoWarning(id: "pitcherThenCatcher", severity: .red, title: "Pitched, then caught",
                                       detail: names(findings.pitcherThenCatcher)))
        }

        self.findings = findings
        self.hasAnyAssignments = hasAny
        self.warnings = warnings
        self.unfilledCount = unfilled.count
    }
}

// MARK: - Roster Column (Positions, History)
//
// The merged roster: the batting order and its fair-play detail in one list.
// Fair play on shows the summary, the warnings, and each player's playing time;
// off, it's names only with the reorder grips.

struct DuoRosterColumn: View {
    @EnvironmentObject var store: LineupStore
    @EnvironmentObject var purchaseManager: PurchaseManager
    let showFairPlay: Bool

    @State private var showingAddPlayer = false
    @State private var showingBulkAdd = false

    private var isReadOnly: Bool { store.activeTeam.isReadOnly }

    private var orderedPlayers: [Player] {
        store.lineup.orderedPlayers(from: store.players)
    }
    private var unorderedPlayers: [Player] {
        store.lineup.activePlayers(from: store.players)
            .filter { !store.lineup.battingOrder.contains($0.id) }
    }
    private var absentPlayers: [Player] {
        store.players.filter { store.lineup.isAbsent($0) }
    }

    var body: some View {
        let summary = DuoFairPlaySummary(store: store)
        let totalInnings = store.lineup.innings.count

        VStack(spacing: 0) {
            header(summary: summary)

            if showFairPlay && summary.hasAnyAssignments && !summary.warnings.isEmpty {
                warningRows(summary.warnings)
            }

            List {
                Section {
                    ForEach(Array(orderedPlayers.enumerated()), id: \.element.id) { index, player in
                        row(player, order: index + 1, summary: summary, totalInnings: totalInnings)
                    }
                    // A nil handler is what removes the drag affordance —
                    // `.disabled` on a List row wouldn't stop the reorder. The
                    // grips are the fair-play-off state; with it on, reordering
                    // lives on the Lineup tab.
                    .onMove(perform: (isReadOnly || showFairPlay) ? nil : { from, to in
                        store.moveBattingOrder(from: from, to: to)
                    })

                    ForEach(unorderedPlayers) { player in
                        row(player, order: nil, summary: summary, totalInnings: totalInnings)
                    }
                } header: {
                    columnHeader
                }

                if !absentPlayers.isEmpty {
                    Section {
                        ForEach(absentPlayers) { player in
                            HStack(spacing: 8) {
                                Image(systemName: "minus.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundColor(.red)
                                Text(player.displayName)
                                    .font(.system(size: 15))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(minHeight: 40)
                        }
                    } header: {
                        Text("Absent")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.secondary)
                            .textCase(nil)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .environment(\.editMode, .constant((isReadOnly || showFairPlay) ? .inactive : .active))
        }
        .background(Color(.systemGroupedBackground))
        .sheet(isPresented: $showingAddPlayer) {
            PlayerFormView(mode: .add)
                .environmentObject(store)
                .environmentObject(purchaseManager)
        }
        .sheet(isPresented: $showingBulkAdd) {
            BulkAddPlayersView()
                .environmentObject(store)
        }
    }

    // MARK: Header

    private func header(summary: DuoFairPlaySummary) -> some View {
        HStack(spacing: 8) {
            Text("Roster")
                .font(.system(size: 17, weight: .semibold))
                .tracking(-0.4)
            Text("\(store.lineup.activePlayers(from: store.players).count) active")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            Spacer(minLength: 4)

            if showFairPlay {
                statusCapsule(summary: summary)
            }

            // Menu exposes both add options; hidden for view-only participants,
            // as on the Players tab.
            if !isReadOnly {
                Menu {
                    Button {
                        showingAddPlayer = true
                    } label: {
                        Label("Add Player", systemImage: "person.badge.plus")
                    }
                    .keyboardShortcut("n", modifiers: .command)

                    Button {
                        showingBulkAdd = true
                    } label: {
                        Label("Bulk Add from List", systemImage: "text.alignleft")
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.blue)
                }
                .accessibilityLabel("Add Players")
                .tourTip(Tour.players.currentTip as? PlayersAddTip, arrowEdge: .top)
                .tourTip(Tour.players.currentTip as? PlayersImportTip, arrowEdge: .top)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private func statusCapsule(summary: DuoFairPlaySummary) -> some View {
        let showIssues = summary.issueCount > 0 && summary.hasAnyAssignments
        let label = showIssues
            ? "\(summary.issueCount) fair-play \(summary.issueCount == 1 ? "issue" : "issues")"
            : "Fair play: all clear"
        return HStack(spacing: 5) {
            Image(systemName: showIssues ? "exclamationmark.triangle.fill" : "checkmark.shield.fill")
                .font(.system(size: 14))
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundColor(showIssues ? .duoStatusIssues : .duoStatusClear)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule().fill(showIssues ? Color.orange.opacity(0.12) : Color.green.opacity(0.12))
        )
        .tourTip(Tour.positions.currentTip as? PositionsWarningsTip, arrowEdge: .top)
    }

    // MARK: Warnings

    private func warningRows(_ warnings: [DuoWarning]) -> some View {
        VStack(spacing: 5) {
            ForEach(warnings) { warning in
                HStack(spacing: 7) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(warning.severity == .red ? .red : .orange)
                    Text(warning.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                        // The title never wraps; the detail gives way first.
                        .layoutPriority(1)
                    Text(warning.detail)
                        .font(.system(size: 12.5))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(warning.severity == .red ? Color.red.opacity(0.08) : Color.orange.opacity(0.1))
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    // MARK: Rows

    private var columnHeader: some View {
        HStack {
            Text("BATTING ORDER")
            Spacer()
            if showFairPlay {
                HStack(spacing: 5) {
                    Text("PLAYING TIME")
                    RoundedRectangle(cornerRadius: 2).fill(Color.blue).frame(width: 7, height: 7)
                    RoundedRectangle(cornerRadius: 2).fill(Color.green).frame(width: 7, height: 7)
                }
                .frame(width: 150, alignment: .trailing)
            }
        }
        .font(.system(size: 12, weight: .semibold))
        .tracking(0.4)
        .foregroundColor(.secondary)
        .textCase(nil)
        .tourTip(Tour.lineup.currentTip as? LineupBattingOrderTip, arrowEdge: .top)
        .tourTip(Tour.lineup.currentTip as? LineupAbsentTip, arrowEdge: .top)
    }

    private func row(
        _ player: Player,
        order: Int?,
        summary: DuoFairPlaySummary,
        totalInnings: Int
    ) -> some View {
        HStack(spacing: 8) {
            Text(order.map(String.init) ?? "")
                .font(.system(size: 14).monospacedDigit())
                .foregroundColor(.secondary)
                .frame(width: 18, alignment: .trailing)

            // Full name, and nothing else: no position tags on this tab.
            Text(player.displayName)
                .font(.system(size: 15))
                .lineLimit(1)

            Spacer(minLength: 4)

            if showFairPlay {
                DuoPlayingTime(
                    infield: count(player) { $0.isInfield },
                    outfield: count(player) { $0.isOutfield },
                    total: totalInnings,
                    minimum: summary.findings.minimumFieldingInnings
                )
            }
        }
        .frame(minHeight: 44)
    }

    private func count(_ player: Player, where matches: (FieldPosition) -> Bool) -> Int {
        store.lineup.innings.filter { inning in
            guard let position = inning.assignments[player.id] else { return false }
            return matches(position)
        }.count
    }
}

// MARK: - Playing Time

/// A stacked bar (infield blue, then outfield green, on a gray track) and the
/// fielded count. Orange when the player is under the team's fielding minimum.
struct DuoPlayingTime: View {
    let infield: Int
    let outfield: Int
    let total: Int
    let minimum: Int

    private var fielded: Int { infield + outfield }
    private var isUnderMinimum: Bool { minimum > 0 && fielded < minimum }

    var body: some View {
        HStack(spacing: 8) {
            GeometryReader { geo in
                let width = geo.size.width
                let inFraction = total > 0 ? CGFloat(infield) / CGFloat(total) : 0
                let outFraction = total > 0 ? CGFloat(outfield) / CGFloat(total) : 0
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.duoFill)
                    if infield > 0 {
                        Rectangle().fill(Color.blue).frame(width: width * inFraction)
                    }
                    if outfield > 0 {
                        Rectangle().fill(Color.green)
                            .frame(width: width * outFraction)
                            .offset(x: width * inFraction)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .frame(height: 10)

            HStack(spacing: 0) {
                Text("\(fielded)")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundColor(isUnderMinimum ? .orange : Color(.secondaryLabel))
                Text("/\(total)")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundColor(Color(.tertiaryLabel))
            }
            .frame(width: 30, alignment: .trailing)
        }
        .frame(width: 150)
    }
}
