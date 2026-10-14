import SwiftUI
import TipKit

// MARK: - Batting Order Column (left half)
//
// The batting order, once, with availability. A player turned off drops out of
// the numbering and every inning's assignments; turned back on, they return to
// the bench. Reordering is the existing Edit-mode drag.

struct DuoBattingOrderColumn: View {
    @EnvironmentObject var store: LineupStore

    @State private var editMode: EditMode = .inactive

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
        VStack(spacing: 0) {
            header

            List {
                Section {
                    ForEach(Array(orderedPlayers.enumerated()), id: \.element.id) { index, player in
                        RosterRow(player: player, index: index + 1, isReadOnly: isReadOnly)
                    }
                    .onMove(perform: isReadOnly ? nil : { store.moveBattingOrder(from: $0, to: $1) })

                    ForEach(unorderedPlayers) { player in
                        RosterRow(player: player, index: nil, isReadOnly: isReadOnly, onAdd: {
                            store.addToBattingOrder(player: player)
                        })
                    }

                    ForEach(absentPlayers) { player in
                        RosterRow(player: player, index: nil, isAbsent: true, isReadOnly: isReadOnly)
                    }

                    if store.players.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "person.badge.plus")
                                .font(.system(size: 36))
                                .foregroundColor(Color(.systemGray3))
                            Text("No players yet")
                                .font(.subheadline.bold())
                                .foregroundColor(.secondary)
                            Text("Go to the Players tab to build your roster.")
                                .font(.caption)
                                .foregroundColor(Color(.tertiaryLabel))
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    }
                } footer: {
                    Text(footer)
                        .font(.system(size: 13))
                }
            }
            .listStyle(.insetGrouped)
            .environment(\.editMode, $editMode)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var footer: String {
        if !unorderedPlayers.isEmpty {
            return "Tap + to add players to the batting order, then drag to reorder."
        }
        return "Turn a player off when they can't make it. Tap Edit, then drag the lines to reorder."
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Batting order")
                .font(.system(size: 17, weight: .semibold))
            Text("\(store.lineup.activePlayers(from: store.players).count) of \(store.players.count) playing")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 4)
            if !orderedPlayers.isEmpty && !isReadOnly {
                Button(editMode == .active ? "Done" : "Edit") {
                    withAnimation { editMode = editMode == .active ? .inactive : .active }
                }
                .font(.system(size: 16))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .tourTip(Tour.lineup.currentTip as? LineupBattingOrderTip, arrowEdge: .top)
        .tourTip(Tour.lineup.currentTip as? LineupAbsentTip, arrowEdge: .top)
    }
}

// MARK: - Schedule Column (right half)
//
// What used to be two buttons on the iPad — Schedule and Template — opened out
// into lists, so the coach can see the games and the saved rotations and pick
// one without a sheet. The PDF exports sit at the bottom, Pro gating intact.

struct DuoScheduleColumn: View {
    @Binding var showingScheduleImport: Bool
    @Binding var pdfRequest: LineupPDFRequest?

    @EnvironmentObject var store: LineupStore
    @EnvironmentObject var purchaseManager: PurchaseManager

    @State private var showingGameInfoEditor = false
    @State private var showingTemplateSaver = false
    @State private var pendingTemplate: LineupTemplate?

    private var isReadOnly: Bool { store.activeTeam.isReadOnly }

    private var canExportCoachesGuide: Bool {
        LineupPDFExport.canExportCoachesGuide(team: store.activeTeam, isPro: purchaseManager.isPro)
    }

    // MARK: Games

    private struct GameRow: Identifiable {
        enum Status { case draft, finalized, notStarted, archived }
        let id: String
        let date: Date
        let opponent: String?
        let meta: String
        let status: Status
        let isCurrent: Bool
        /// Nil for the working lineup and for archived games.
        let game: ScheduledGame?
    }

    private var gameRows: [GameRow] {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let innings = store.lineup.innings.count
        let current = store.currentGame
        var rows: [GameRow] = []

        // A working lineup that isn't tied to a scheduled game still needs a row.
        if current == nil {
            let date = store.lineup.gameDate
            let when = calendar.isDateInToday(date)
                ? "Today"
                : date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
            rows.append(GameRow(
                id: "working",
                date: date,
                opponent: store.lineup.opponent.isEmpty ? nil : "vs \(store.lineup.opponent)",
                meta: "\(when) · \(innings) \(innings == 1 ? "inning" : "innings")",
                status: store.lineup.status == .finalized ? .finalized : .draft,
                isCurrent: true,
                game: nil
            ))
        }

        let upcoming = store.scheduledGames
            .filter { !$0.isCancelled && $0.date >= startOfToday && !ICalParser.isPractice($0.rawSummary) }
            .sorted { $0.date < $1.date }
            .prefix(8)

        for game in upcoming {
            let isCurrent = game.id == current?.id
            var meta = game.date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
            if let location = game.location, !location.isEmpty { meta += " · \(location)" }

            let status: GameRow.Status
            if isCurrent {
                // The open game's saved copy lags the live one; read the live one.
                status = store.lineup.status == .finalized ? .finalized : .draft
                meta = calendar.isDateInToday(game.date)
                    ? "Today · \(innings) \(innings == 1 ? "inning" : "innings")"
                    : meta
            } else if let saved = store.savedLineup(for: game),
                      !saved.battingOrder.isEmpty || saved.innings.contains(where: { !$0.assignments.isEmpty }) {
                status = saved.status == .finalized ? .finalized : .draft
            } else {
                status = .notStarted
            }

            rows.append(GameRow(
                id: game.id.uuidString,
                date: game.date,
                opponent: game.opponent.map { "vs \($0)" } ?? game.rawSummary,
                meta: meta,
                status: status,
                isCurrent: isCurrent,
                game: game
            ))
        }

        let archived = store.gameLogs
            .sorted { $0.gameDate > $1.gameDate }
            .prefix(2)
        for log in archived {
            rows.append(GameRow(
                id: log.id.uuidString,
                date: log.gameDate,
                opponent: log.opponent.isEmpty ? nil : "vs \(log.opponent)",
                meta: "Archived · \(log.inningsPlayed) \(log.inningsPlayed == 1 ? "inning" : "innings")",
                status: .archived,
                isCurrent: false,
                game: nil
            ))
        }
        return rows
    }

    // MARK: Body

    var body: some View {
        List {
            if isReadOnly {
                Section {
                    ReadOnlyBanner()
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }

            if let source = store.copiedFromGameOpponent {
                Section {
                    CopiedFromGameBanner(source: source)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }

            Section {
                ForEach(gameRows) { row in
                    gameRow(row)
                }
            } header: {
                HStack {
                    Text("SCHEDULE")
                        .tracking(0.4)
                    Spacer()
                    if !isReadOnly {
                        Button {
                            showingScheduleImport = true
                            Analytics.signal("schedule.import.tapped")
                        } label: {
                            Label("Import", systemImage: "calendar.badge.plus")
                                .font(.system(size: 14))
                        }
                        .textCase(nil)
                    }
                }
                .font(.system(size: 12, weight: .semibold))
                .tourTip(Tour.lineup.currentTip as? LineupGameInfoTip, arrowEdge: .top)
            }

            Section {
                if store.lineupTemplates.isEmpty {
                    Text("Save your first rotation: build a lineup, then tap Save current.")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .frame(minHeight: 50)
                } else {
                    ForEach(store.lineupTemplates) { template in
                        templateRow(template)
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                defaultSwipeAction(template)
                            }
                    }
                    .onDelete(perform: isReadOnly ? nil : { offsets in
                        let templates = store.lineupTemplates
                        for index in offsets { store.deleteTemplate(id: templates[index].id) }
                    })
                }
            } header: {
                HStack {
                    Text("TEMPLATES")
                        .tracking(0.4)
                    Spacer()
                    if !isReadOnly {
                        Button("Save current") { showingTemplateSaver = true }
                            .font(.system(size: 14))
                            .textCase(nil)
                    }
                }
                .font(.system(size: 12, weight: .semibold))
                .tourTip(Tour.secondGame.currentTip as? ReuseApplyTemplateTip, arrowEdge: .top)
            } footer: {
                Text("Applying a template sets positions for every inning. Players who are out leave their spots open.")
                    .font(.system(size: 13))
            }
        }
        .listStyle(.insetGrouped)
        .safeAreaInset(edge: .bottom) {
            ExportBar(
                isCoachesGuideUnlocked: canExportCoachesGuide,
                onExportBattingOrder: { pdfRequest = .battingOrder },
                onExportCoachesGuide: { pdfRequest = .coachesGuide }
            )
            .tourTip(Tour.lineup.currentTip as? LineupExportTip, arrowEdge: .bottom)
        }
        .background(Color(.systemGroupedBackground))
        .sheet(isPresented: $showingGameInfoEditor) {
            GameInfoEditorView()
                .environmentObject(store)
        }
        .sheet(isPresented: $showingTemplateSaver) {
            TemplateLockEditorView()
                .environmentObject(store)
        }
        .alert(
            "Replace current game?",
            isPresented: Binding(
                get: { pendingTemplate != nil },
                set: { if !$0 { pendingTemplate = nil } }
            ),
            presenting: pendingTemplate
        ) { template in
            Button("Cancel", role: .cancel) { pendingTemplate = nil }
            Button("Apply Template", role: .destructive) { apply(template) }
        } message: { template in
            Text(overwriteMessage(for: template))
        }
    }

    // MARK: Game Row

    private func gameRow(_ row: GameRow) -> some View {
        let isArchived = row.status == .archived

        return Button {
            guard !isReadOnly, !isArchived else { return }
            if row.isCurrent {
                // The open game: tapping it edits its date, opponent and status.
                showingGameInfoEditor = true
            } else if let game = row.game {
                store.applyScheduledGame(game)
            }
        } label: {
            HStack(spacing: 12) {
                VStack(spacing: 0) {
                    Text(row.date.formatted(.dateTime.month(.abbreviated)).uppercased())
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(isArchived ? Color(.secondaryLabel).opacity(0.75) : .red)
                    Text(row.date.formatted(.dateTime.day()))
                        .font(.system(size: 18, weight: .bold).monospacedDigit())
                        .foregroundColor(isArchived ? .secondary : .primary)
                }
                .frame(width: 34)

                VStack(alignment: .leading, spacing: 1) {
                    Text(row.opponent ?? "Add opponent")
                        .font(.system(size: 16))
                        .foregroundColor(row.opponent == nil ? Color(.tertiaryLabel) : .primary)
                        .lineLimit(1)
                    Text(row.meta)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                statusCapsule(row.status)
            }
            .frame(minHeight: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(row.isCurrent ? Color.blue.opacity(0.08) : Color(.secondarySystemGroupedBackground))
    }

    private func statusCapsule(_ status: GameRow.Status) -> some View {
        let (text, background, foreground): (String, Color, Color) = {
            switch status {
            case .draft:
                return ("Draft", .duoFill, .secondary)
            case .finalized:
                return ("Finalized", Color.green.opacity(0.14), .duoStatusClear)
            case .notStarted:
                return ("Not started", Color(.systemGray6), Color(.secondaryLabel).opacity(0.75))
            case .archived:
                return ("Archived", Color.teal.opacity(0.14), Color(red: 20 / 255, green: 110 / 255, blue: 128 / 255))
            }
        }()
        return Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(foreground)
            .padding(.horizontal, 9)
            .padding(.vertical, 2)
            .background(Capsule().fill(background))
    }

    // MARK: Templates

    private func templateRow(_ template: LineupTemplate) -> some View {
        let isDefault = store.isDefaultTemplate(template.id)
        let locks = template.positionLocks.isEmpty ? "No position locks" : Plural.locks(template.positionLocks.count)
        let saved = template.createdAt.formatted(.dateTime.month(.abbreviated).day())

        return HStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 16))
                .foregroundColor(.blue)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue.opacity(0.12)))

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(template.name)
                        .font(.system(size: 16))
                        .lineLimit(1)
                    if isDefault {
                        Image(systemName: "star.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.orange)
                            .accessibilityLabel("Default template, applied to every new game")
                    }
                }
                Text("\(locks) · saved \(saved)")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if !isReadOnly {
                Button("Apply") { handleApply(template) }
                    .font(.system(size: 15))
                    .buttonStyle(.borderless)
            }
        }
        .frame(minHeight: 50)
    }

    /// Setting the default lives on a leading swipe, since tapping Apply
    /// already means "apply this template right now".
    @ViewBuilder
    private func defaultSwipeAction(_ template: LineupTemplate) -> some View {
        if store.isDefaultTemplate(template.id) {
            Button {
                store.setDefaultTemplate(id: nil)
            } label: {
                Label("Remove Default", systemImage: "star.slash")
            }
            .tint(.gray)
        } else {
            Button {
                store.setDefaultTemplate(id: template.id)
            } label: {
                Label("Make Default", systemImage: "star")
            }
            .tint(.orange)
        }
    }

    /// Applying rebuilds the lineup from scratch, so warn only when there is
    /// actually something to lose.
    private func handleApply(_ template: LineupTemplate) {
        if store.currentGameHasLineup {
            pendingTemplate = template
        } else {
            apply(template)
        }
    }

    private func apply(_ template: LineupTemplate) {
        pendingTemplate = nil
        store.applyTemplate(template)
    }

    private func overwriteMessage(for template: LineupTemplate) -> String {
        let hasPositions = store.lineup.innings.contains { !$0.assignments.isEmpty }
        let existing = hasPositions
            ? "Your current game already has a batting order and players assigned to positions."
            : "Your current game already has a batting order."
        let replaced = hasPositions
            ? "Applying “\(template.name)” clears every position you've assigned and replaces the batting order."
            : "Applying “\(template.name)” replaces it."
        return "\(existing) \(replaced) Only the template's locked assignments are filled in — the rest of the field is unassigned."
    }
}
