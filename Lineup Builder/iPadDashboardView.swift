import SwiftUI
import TipKit

// MARK: - Detail Tab

enum DetailTab: String, CaseIterable {
    case players   = "Players"
    case lineup    = "Lineup"
    case positions = "Positions"
    case history   = "History"

    /// Maps an idiom-independent route target onto this pane's selection.
    init(_ tab: STLRoute.Tab) {
        switch tab {
        case .players:   self = .players
        case .lineup:    self = .lineup
        case .positions: self = .positions
        case .history:   self = .history
        }
    }
}

// MARK: - iPad Dashboard View

struct iPadDashboardView: View {
    @EnvironmentObject var store: LineupStore
    @EnvironmentObject var purchaseManager: PurchaseManager
    @EnvironmentObject var router: AppRouter
    @Binding var showingArchive: Bool

    @State private var selectedTab: DetailTab = .players
    /// Nonce of the last route applied here, so a pending route is consumed once.
    @State private var lastHandledRouteNonce: UUID?
    @State private var showingArchiveSheet = false
    @State private var showingAutoFillPopover = false
    @AppStorage("ipadBattingOrderExpanded") private var battingOrderExpanded: Bool = true

    // AutoFill state — passed through to PositionSummaryView
    @State private var showingPositionAutoFill = false

    // Schedule import state — owned here so the toast can overlay the full screen
    @State private var showingScheduleImport = false
    @State private var scheduleImportToast: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            iPadNavBar(
                selectedTab: $selectedTab,
                showingArchive: $showingArchive,
                showingScheduleImport: $showingScheduleImport,
                scheduleImportToast: $scheduleImportToast
            )

            Divider()

            HStack(spacing: 0) {
                SidebarRosterView(
                    battingOrderExpanded: $battingOrderExpanded
                )

                Divider()

                DetailPaneView(
                    selectedTab: $selectedTab,
                    showingAutoFillPopover: $showingPositionAutoFill,
                    showingArchive: $showingArchive
                )

                Divider()

                FairPlayRailView()
            }
        }
        .background(Color(.systemBackground))
        // Schedule import sheet — presented from here so it covers the full screen
        .sheet(isPresented: $showingScheduleImport) {
            ScheduleImportView { games, urlString in
                let result = store.mergeScheduledGames(games)
                if let url = urlString {
                    store.setCalendarSubscriptionURL(url)
                }
                let total = result.added + result.updated
                if total == 0 {
                    scheduleImportToast = "Schedule is already up to date."
                    Analytics.signal("schedule.import.already_current")
                } else {
                    var parts: [String] = []
                    if result.added > 0 { parts.append("\(result.added) added") }
                    if result.updated > 0 { parts.append("\(result.updated) updated") }
                    scheduleImportToast = parts.joined(separator: ", ").capitalized + "."
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    scheduleImportToast = nil
                }
            }
            .environmentObject(store)
        }
        // Toast overlay — anchored to the bottom of the full dashboard
        .safeAreaInset(edge: .bottom) {
            if let toast = scheduleImportToast {
                Text(toast)
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color(.label)))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(duration: 0.35), value: scheduleImportToast)
                    .padding(.bottom, 8)
            }
        }
        .onAppear {
            Analytics.signal("ipad.dashboard.opened", parameters: [
                "playerCount": "\(store.players.count)"
            ])
            consumePendingRoute()
        }
        .onChange(of: router.request) { _, _ in
            consumePendingRoute()
        }
        .remoteDeletionPrompt(store: store)
    }

    // Deep links, Spotlight results and App Intents were previously dropped on
    // iPad entirely — ContentView only ever set the iPhone tab index. ContentView
    // still owns team switching and any sheet the route targets; this maps the
    // route onto the detail pane's own selection.
    //
    // Called from BOTH onAppear and onChange. A deep link that cold-launches the
    // app fires onOpenURL during scene connection, before this pane exists — so
    // onChange alone never sees the change and the route is silently dropped.
    // That is the common case for Siri and Spotlight, which launch the app cold.
    //
    // The nonce guard keeps it idempotent: without it, every re-appearance would
    // re-apply the last route and yank the coach back off whatever tab they just
    // chose by hand.
    private func consumePendingRoute() {
        guard let request = router.request,
              request.nonce != lastHandledRouteNonce else { return }
        // A first-ever drain in a brand new window must not replay a stale route.
        guard lastHandledRouteNonce != nil || request.isFresh else { return }
        lastHandledRouteNonce = request.nonce
        selectedTab = DetailTab(request.route.tab)
    }
}

// MARK: - Nav Bar

private struct iPadNavBar: View {
    @EnvironmentObject var store: LineupStore
    @EnvironmentObject var purchaseManager: PurchaseManager
    @Binding var selectedTab: DetailTab
    @Binding var showingArchive: Bool
    @Binding var showingScheduleImport: Bool
    @Binding var scheduleImportToast: String?

    @State private var showingEditTeam = false
    @State private var showingAddTeam = false
    @State private var showingSettings = false
    @State private var pdfRequest: LineupPDFRequest? = nil

    private var isReadOnly: Bool { store.activeTeam.isReadOnly }

    /// Drives the menu label only; the export path re-checks the same rule.
    private var canExportCoachesGuide: Bool {
        LineupPDFExport.canExportCoachesGuide(
            team: store.activeTeam,
            isPro: purchaseManager.isPro
        )
    }

    /// Distinct players implicated in a fair-play rule the team actually has
    /// switched on. Previously this called the rule helpers directly, which
    /// meant it counted infield/outfield/fielding-minimum misses even for teams
    /// that had set those minimums to 0, and measured against the hardcoded
    /// default of 4 rather than the configured value. It also summed per-rule
    /// counts, so one player missing both infield and outfield showed as 2.
    private var violationCount: Int {
        store.lineup
            .fairPlayFindings(players: store.players, config: store.fairPlayConfig)
            .implicatedPlayerIDs
            .count
    }

    var body: some View {
        HStack(spacing: 14) {
            // Team switcher
            Menu {
                if store.teams.count > 1 {
                    Section("Switch Team") {
                        ForEach(store.teams) { team in
                            Button {
                                store.switchTeam(to: team.id)
                            } label: {
                                HStack {
                                    Text(team.name.isEmpty ? "Unnamed Team" : team.name)
                                    if team.id == store.activeTeamID {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                }
                Button {
                    showingEditTeam = true
                } label: {
                    Label("Edit Team", systemImage: "pencil")
                }
                Button {
                    showingAddTeam = true
                } label: {
                    Label("Add Team", systemImage: "plus")
                }
            } label: {
                HStack(spacing: 4) {
                    Text(store.teamName.isEmpty ? "My Team" : store.teamName)
                        .font(.headline)
                    Image(systemName: "chevron.down")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                }
            }
            .tourTip(Tour.players.currentTip as? PlayersTeamSetupTip, arrowEdge: .top)

            Divider()
                .frame(height: 20)

            // Game context — opponent, date, inning count
            HStack(spacing: 4) {
                if !store.lineup.opponent.isEmpty {
                    Text("vs. \(store.lineup.opponent)")
                        .fontWeight(.medium)
                    Text("·")
                        .foregroundColor(.secondary)
                }
                Text(store.lineup.gameDate, style: .date)
                    .foregroundColor(.secondary)
                Text("·")
                    .foregroundColor(.secondary)
                Text("\(store.lineup.innings.count) innings")
                    .foregroundColor(.secondary)
            }
            .font(.subheadline)

            Spacer()

            // Violation indicator — visual only; details live in the always-on Fair Play rail
            if violationCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption.bold())
                    Text("\(violationCount)")
                        .font(.caption.bold())
                }
                .foregroundColor(.orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.12))
                .clipShape(Capsule())
            }

            // Export — Cmd+P. Deliberately NOT gated on read-only: a view-only
            // assistant printing the Coaches Guide for the dugout is the case
            // the free unlock exists for. See LineupPDFExport.
            //
            // A menu rather than two more icons; this bar already carries the
            // team switcher, game context, the violations pill, and settings.
            Menu {
                Button {
                    pdfRequest = .battingOrder
                } label: {
                    Label("Batting Order", systemImage: "doc.text")
                }
                Button {
                    pdfRequest = .coachesGuide
                } label: {
                    Label(
                        canExportCoachesGuide ? "Coaches Guide" : "Coaches Guide (Pro)",
                        systemImage: "doc.richtext.fill"
                    )
                }
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.title3)
            }
            .keyboardShortcut("p", modifiers: .command)
            .help("Export PDF (Cmd+P)")

            // Import schedule and Archive both write to the team, so both are
            // gated exactly as they are on iPhone. Before this, iPadNavBar held
            // no isReadOnly reference at all — the 6 Aug read-only fix covered
            // the sidebar and the panes and never reached the bar above them,
            // so a view-only coach could import a schedule over the head
            // coach's team and archive their game. Neither sheet guards itself.
            if !isReadOnly {
                // Import schedule — Cmd+Shift+S
                Button {
                    showingScheduleImport = true
                    Analytics.signal("schedule.import.tapped")
                } label: {
                    Image(systemName: "calendar.badge.plus")
                        .font(.title3)
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .help("Import Schedule (Cmd+Shift+S)")

                // Archive game — Cmd+Shift+A
                Button {
                    showingArchive = true
                } label: {
                    Image(systemName: "archivebox")
                        .font(.title3)
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .help("Archive Game (Cmd+Shift+A)")
            }

            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.title3)
            }
            // Re-entry hint for coaches who skipped the welcome. On iPad the gear
            // is a content button (not a nav-bar ToolbarItem), so it can anchor
            // here directly. Gated on the Players arc being exhausted
            // (`currentTip == nil`), same as the iPhone team-card anchor: without
            // it the tip is eligible the instant `welcomeSkipped` flips and
            // competes with the arc-1 tips, where its single MaxDisplayCount gets
            // consumed before it ever presents. The welcome cover itself is held
            // off by the environment `tourActive` gate in `tourTip`.
            .tourTip(TourInSettingsTip(), arrowEdge: .top,
                     enabled: Tour.players.currentTip == nil)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
        .sheet(isPresented: $showingEditTeam) {
            TeamFormView(mode: .edit(store.activeTeamID ?? UUID()))
                .environmentObject(store)
                .environmentObject(purchaseManager)
        }
        .sheet(isPresented: $showingAddTeam) {
            TeamFormView(mode: .add)
                .environmentObject(store)
                .environmentObject(purchaseManager)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(store)
                .environmentObject(purchaseManager)
        }
        .lineupPDFExports(request: $pdfRequest)
    }
}

// MARK: - Fair Play Rail

private struct FairPlayRailView: View {
    @EnvironmentObject var store: LineupStore

    private var activePlayers: [Player] {
        store.lineup.activePlayers(from: store.players)
    }

    /// Every rule evaluated once against the team's own config. These used to
    /// call the rule helpers directly, which flagged players against minimums
    /// the team had switched off and measured the fielding minimum at the
    /// hardcoded default of 4 instead of the configured number.
    private var findings: FairPlayFindings {
        store.lineup.fairPlayFindings(players: store.players, config: store.fairPlayConfig)
    }

    private var noInfield: [Player]   { findings.withoutInfield }
    private var noOutfield: [Player]  { findings.withoutOutfield }
    private var underMin: [Player]    { findings.underFieldingMinimum }
    private var backToBack: [Player]  { findings.backToBackBench }

    /// Players counted once each, plus open field slots. The two units in one
    /// number predate this change and the pill's copy ("N fair-play issues")
    /// covers both; what changed is that a player breaking two rules no longer
    /// counts twice.
    private var violationCount: Int {
        findings.implicatedPlayerIDs.count + unfilledPositions.count
    }
    private var hasAnyAssignments: Bool {
        store.lineup.innings.contains { !$0.assignments.isEmpty }
    }

    // Unfilled field positions — innings that have at least one assignment but
    // are missing one or more expected positions (e.g. pitcher not filled).
    private var unfilledPositions: [(inning: Int, position: FieldPosition)] {
        guard hasAnyAssignments else { return [] }
        let expected = store.lineup.activeFieldPositions(config: store.fairPlayConfig)
        var result: [(Int, FieldPosition)] = []
        for (i, inning) in store.lineup.innings.enumerated() {
            guard !inning.assignments.isEmpty else { continue }
            let filled = Set(inning.assignments.values)
            for pos in expected where !filled.contains(pos) {
                result.append((i, pos))
            }
        }
        return result
    }

    // Grouped label for the warning card: "P (Innings 6, 7), CF (Inning 4)"
    private var unfilledPositionsSummary: String? {
        let slots = unfilledPositions
        guard !slots.isEmpty else { return nil }
        var byPos: [FieldPosition: [Int]] = [:]
        for (i, pos) in slots { byPos[pos, default: []].append(i + 1) }
        return byPos
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { pos, innings in
                let numbers = innings.sorted().map { "\($0)" }.joined(separator: ", ")
                return innings.count == 1
                    ? "\(pos.rawValue) (Inning \(numbers))"
                    : "\(pos.rawValue) (Innings \(numbers))"
            }
            .joined(separator: ", ")
    }

    // Active players in batting-order sequence, then any unordered active players appended
    private var orderedActivePlayers: [Player] {
        let ordered = store.lineup.orderedPlayers(from: store.players)
        let unordered = activePlayers.filter { p in
            !ordered.contains(where: { $0.id == p.id })
        }
        return ordered + unordered
    }

    private func infieldCount(for player: Player) -> Int {
        store.lineup.innings.filter { inning in
            guard let pos = inning.assignments[player.id] else { return false }
            return pos.isInfield
        }.count
    }

    private func outfieldCount(for player: Player) -> Int {
        store.lineup.innings.filter { inning in
            guard let pos = inning.assignments[player.id] else { return false }
            return pos.isOutfield
        }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Header
            VStack(alignment: .leading, spacing: 3) {
                Text("Fair play")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.primary)
                Text("Live as you build the lineup")
                    .font(.system(size: 12.5))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            // Status pill
            FairPlayStatusPill(
                violationCount: violationCount,
                hasAnyAssignments: hasAnyAssignments
            )
            .tourTip(Tour.positions.currentTip as? PositionsWarningsTip, arrowEdge: .top)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            // Inline warning cards
            if hasAnyAssignments {
                FairPlayInlineWarnings(
                    findings: findings,
                    unfilledSummary: unfilledPositionsSummary
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }

            Divider()
                .padding(.horizontal, 16)

            // Playing time section header + legend
            HStack {
                Text("Playing Time".uppercased())
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                    .kerning(0.4)
                Spacer()
                HStack(spacing: 10) {
                    FairPlayLegendChip(color: .blue, label: "Infield")
                    FairPlayLegendChip(color: .green, label: "Outfield")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            // Per-player equity bars
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(orderedActivePlayers) { player in
                        FairPlayEquityRow(
                            player: player,
                            infieldCount: infieldCount(for: player),
                            outfieldCount: outfieldCount(for: player),
                            totalInnings: store.lineup.innings.count,
                            missingInfield: noInfield.contains(where: { $0.id == player.id }),
                            missingOutfield: noOutfield.contains(where: { $0.id == player.id })
                        )
                        Divider()
                            .padding(.leading, 16)
                    }
                }
            }
        }
        .frame(width: 280)
        .background(Color(.systemBackground))
    }
}

// MARK: - Fair Play Status Pill

private struct FairPlayStatusPill: View {
    let violationCount: Int
    let hasAnyAssignments: Bool

    var body: some View {
        let showIssues = violationCount > 0 && hasAnyAssignments
        let icon = showIssues ? "exclamationmark.triangle.fill" : "checkmark.shield.fill"
        let tint: Color = showIssues ? .orange : .green
        let label = showIssues
            ? "\(violationCount) fair-play \(violationCount == 1 ? "issue" : "issues")"
            : "Fair play: all clear"

        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(tint)
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(tint)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Fair Play Inline Warnings

private struct FairPlayInlineWarnings: View {
    /// Every rule, so the cards can account for everything the status pill
    /// counts. The battery rules were previously missing here, which was
    /// survivable only because the pill wasn't counting them either.
    let findings: FairPlayFindings
    let unfilledSummary: String?

    private var noInfield: [Player]   { findings.withoutInfield }
    private var noOutfield: [Player]  { findings.withoutOutfield }
    private var underMin: [Player]    { findings.underFieldingMinimum }
    private var backToBack: [Player]  { findings.backToBackBench }

    private var allClear: Bool {
        findings.isEmpty && unfilledSummary == nil
    }

    var body: some View {
        VStack(spacing: 7) {
            if allClear {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.green)
                    Text("Every player meets your fair play rules.")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 9))
            } else {
                if let summary = unfilledSummary {
                    FairPlayWarningCard(
                        color: .red,
                        title: "Positions not filled",
                        detail: summary
                    )
                }
                if !noOutfield.isEmpty {
                    FairPlayWarningCard(
                        color: .orange,
                        title: "Missing outfield inning",
                        detail: noOutfield.map { $0.firstName }.joined(separator: ", ")
                    )
                }
                if !noInfield.isEmpty {
                    FairPlayWarningCard(
                        color: .orange,
                        title: "Missing infield inning",
                        detail: noInfield.map { $0.firstName }.joined(separator: ", ")
                    )
                }
                if !backToBack.isEmpty {
                    FairPlayWarningCard(
                        color: .red,
                        title: "Back-to-back bench",
                        detail: backToBack.map { $0.firstName }.joined(separator: ", ")
                    )
                }
                if !underMin.isEmpty {
                    FairPlayWarningCard(
                        color: .orange,
                        title: "Under minimum innings fielded",
                        detail: underMin.map { $0.firstName }.joined(separator: ", ")
                    )
                }
                // Red, like the other hard rules: these are league restrictions
                // on a kid's arm, not playing-time fairness.
                if !findings.catcherThenPitcher.isEmpty {
                    FairPlayWarningCard(
                        color: .red,
                        title: "Caught, then pitched",
                        detail: findings.catcherThenPitcher.map { $0.firstName }.joined(separator: ", ")
                    )
                }
                if !findings.pitcherThenCatcher.isEmpty {
                    FairPlayWarningCard(
                        color: .red,
                        title: "Pitched, then caught",
                        detail: findings.pitcherThenCatcher.map { $0.firstName }.joined(separator: ", ")
                    )
                }
            }
        }
    }
}

// MARK: - Fair Play Warning Card

private struct FairPlayWarningCard: View {
    let color: Color
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13))
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
            Text(detail)
                .font(.system(size: 12.5))
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color == .red ? Color.red.opacity(0.07) : Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }
}

// MARK: - Fair Play Equity Row

private struct FairPlayEquityRow: View {
    let player: Player
    let infieldCount: Int
    let outfieldCount: Int
    let totalInnings: Int
    let missingInfield: Bool
    let missingOutfield: Bool

    private var fieldedCount: Int { infieldCount + outfieldCount }
    private var hasViolation: Bool { missingInfield || missingOutfield }

    var body: some View {
        HStack(spacing: 10) {
            // Player first name — fixed width, truncates
            Text(player.firstName)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)
                .frame(width: 64, alignment: .leading)

            // Stacked infield (blue) + outfield (green) bar on a gray track
            GeometryReader { geo in
                let w = geo.size.width
                let ifFrac = totalInnings > 0 ? CGFloat(infieldCount) / CGFloat(totalInnings) : 0
                let ofFrac = totalInnings > 0 ? CGFloat(outfieldCount) / CGFloat(totalInnings) : 0

                ZStack(alignment: .leading) {
                    // Gray track
                    Rectangle()
                        .fill(Color(.systemGray5))

                    // Infield segment (blue)
                    if infieldCount > 0 {
                        Rectangle()
                            .fill(Color.blue)
                            .frame(width: w * ifFrac)
                    }

                    // Outfield segment (green) — stacked after infield
                    if outfieldCount > 0 {
                        Rectangle()
                            .fill(Color.green)
                            .frame(width: w * ofFrac)
                            .offset(x: w * ifFrac)
                    }
                }
                .frame(height: 14)
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .frame(height: 14)

            // Count + optional violation dot
            HStack(spacing: 5) {
                HStack(spacing: 1) {
                    Text("\(fieldedCount)")
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundColor(.secondary)
                    Text("/\(totalInnings)")
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundColor(Color(.tertiaryLabel))
                }
                // Dot color indicates which coverage is missing;
                // red ring signals it is a violation
                if hasViolation {
                    Circle()
                        .fill(missingInfield ? Color.blue : Color.green)
                        .frame(width: 7, height: 7)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.red, lineWidth: 1.5)
                                .frame(width: 10, height: 10)
                        )
                }
            }
            .frame(width: 50, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Fair Play Legend Chip

private struct FairPlayLegendChip: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Sidebar Roster View

struct SidebarRosterView: View {
    @EnvironmentObject var store: LineupStore
    @EnvironmentObject var purchaseManager: PurchaseManager
    @Binding var battingOrderExpanded: Bool
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
        VStack(spacing: 0) {
            HStack {
                Text("Roster")
                    .font(.subheadline.bold())
                Spacer()
                Text("\(store.lineup.activePlayers(from: store.players).count) active")
                    .font(.caption)
                    .foregroundColor(.secondary)

                // Menu exposes both add options; Cmd+N shortcut on Add Player.
                // Hidden for view-only participants, as on the Players tab.
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
                            .font(.title3)
                            .foregroundColor(.blue)
                    }
                    .accessibilityLabel("Add Players")
                    .tourTip(Tour.players.currentTip as? PlayersAddTip, arrowEdge: .top)
                    .tourTip(Tour.players.currentTip as? PlayersImportTip, arrowEdge: .top)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(.systemBackground))

            Divider()

            List {
                Section {
                    if battingOrderExpanded {
                        ForEach(Array(orderedPlayers.enumerated()), id: \.element.id) { index, player in
                            SidebarPlayerRow(player: player, battingIndex: index + 1)
                        }
                        // A nil handler is what removes the drag affordance —
                        // `.disabled` on a List row wouldn't stop the reorder.
                        .onMove(perform: isReadOnly ? nil : { from, to in
                            store.moveBattingOrder(from: from, to: to)
                        })

                        ForEach(unorderedPlayers) { player in
                            SidebarPlayerRow(player: player, battingIndex: nil)
                        }
                    }
                } header: {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            battingOrderExpanded.toggle()
                        }
                        Analytics.signal("ipad.batting.order.toggled", parameters: [
                            "expanded": battingOrderExpanded ? "true" : "false"
                        ])
                    } label: {
                        HStack {
                            Text("Batting Order")
                            Spacer()
                            if !battingOrderExpanded {
                                Text("\(orderedPlayers.count + unorderedPlayers.count) players")
                            }
                            Image(systemName: battingOrderExpanded ? "chevron.down" : "chevron.right")
                        }
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                    }
                    .buttonStyle(.plain)
                    .tourTip(Tour.lineup.currentTip as? LineupBattingOrderTip, arrowEdge: .top)
                    .tourTip(Tour.lineup.currentTip as? LineupAbsentTip, arrowEdge: .top)
                }

                Section {
                    Text("Use the Lineup tab to mark players absent or available.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    ForEach(absentPlayers) { player in
                        SidebarPlayerRow(player: player, battingIndex: nil, isAbsent: true)
                    }
                } header: {
                    Text("Absent")
                }

                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 12) {
                            legendItem("S", "Strength", .green)
                            legendItem("C", "Capable", .blue)
                        }
                        HStack(spacing: 12) {
                            legendItem("E", "Emergency", .orange)
                            legendItem("N", "Never", .red)
                        }
                    }
                    .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.lineup.opponent.isEmpty ? "No opponent set" : "vs. \(store.lineup.opponent)")
                            .font(.caption.bold())
                            .foregroundColor(store.lineup.opponent.isEmpty ? .secondary : .primary)
                        HStack(spacing: 4) {
                            Text(store.lineup.gameDate, style: .date)
                            Text("·")
                            Text("\(store.lineup.innings.count) innings")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 2)
                } header: {
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 10))
                        Text("Colored tags show position preferences")
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .textCase(nil)
                }
            }
            .listStyle(.insetGrouped)
            .environment(\.editMode, .constant(.active))
        }
        .frame(width: 260)
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

    private func legendItem(_ letter: String, _ name: String, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Text(letter)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(color)
            Text(name)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .fixedSize()
        }
    }
}

// MARK: - Sidebar Player Row

private struct SidebarPlayerRow: View {
    @EnvironmentObject var store: LineupStore
    let player: Player
    var battingIndex: Int?
    var isAbsent: Bool = false

    private var preferencePills: [(String, Color)] {
        let prefs = player.positionPreferences
        guard !prefs.isEmpty else { return [] }
        var pills: [(String, Color, Int)] = []
        for (pos, tier) in prefs {
            let order: Int
            switch tier {
            case .strength:  order = 0
            case .capable:   order = 1
            case .never:     order = 2
            case .emergency: order = 3
            }
            pills.append((pos.rawValue, tier.color, order))
        }
        return pills.sorted { $0.2 < $1.2 }.prefix(3).map { ($0.0, $0.1) }
    }

    var body: some View {
        HStack(spacing: 8) {
            if let idx = battingIndex {
                Text("\(idx)")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                    .frame(width: 18, alignment: .trailing)
            } else if isAbsent {
                Image(systemName: "minus.circle")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 18)
            } else {
                Image(systemName: "circle")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 18)
            }

            Text(player.displayName)
                .font(.subheadline)
                .foregroundColor(isAbsent ? .secondary : .primary)
                .strikethrough(isAbsent)
                .lineLimit(1)

            Spacer(minLength: 4)

            if !preferencePills.isEmpty && !isAbsent {
                HStack(spacing: 3) {
                    ForEach(preferencePills.prefix(3), id: \.0) { posName, color in
                        Text(posName)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(color)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(color.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                            .fixedSize()
                    }
                }
                .lineLimit(1)
            }
        }
        .opacity(isAbsent ? 0.6 : 1.0)
    }
}

// MARK: - Detail Pane View

struct DetailPaneView: View {
    @EnvironmentObject var store: LineupStore
    @EnvironmentObject var purchaseManager: PurchaseManager
    @Binding var selectedTab: DetailTab
    @Binding var showingAutoFillPopover: Bool
    @Binding var showingArchive: Bool

    @State private var fillThroughInning: Int = 6
    @State private var showingClearAllConfirm = false
    @State private var showingAutoFillIncomplete = false
    @State private var autoFillIncompleteMessage: String = ""

    // NL Auto-Fill constraint prompt — resets after every fill. Parse, engine
    // call and message composition are shared with the iPhone grid and with
    // FillLineupIntent; see AutoFillCoordinator.
    @State private var autoFillPrompt: String = ""
    @State private var showingAutoFillConstraintNotice = false
    @State private var autoFillConstraintNoticeMessage: String = ""
    @StateObject private var autoFill = AutoFillCoordinator()

    private var isReadOnly: Bool { store.activeTeam.isReadOnly }

    private var smartDefaultLastInning: Int {
        for i in stride(from: store.lineup.innings.count - 1, through: 0, by: -1) {
            if !store.lineup.innings[i].assignments.isEmpty { return i }
        }
        return store.lineup.innings.count - 1
    }

    private var hasAnyAssignments: Bool {
        store.lineup.innings.contains { !$0.assignments.isEmpty }
    }

    /// Runs the shared coordinator for the summary view's "Fill Innings 1–N"
    /// action, then drives the alerts it implies.
    @MainActor
    private func performAutoFill(through lastInning: Int) async {
        let outcome = await autoFill.run(
            scope: .through(lastInning),
            prompt: autoFillPrompt,
            team: store.activeTeam
        )

        // Parsing has settled — dismiss the popover now rather than the
        // instant Fill was tapped, so the spinner was actually visible
        // while the on-device parse was in flight.
        showingAutoFillPopover = false

        if outcome.didFill {
            store.activeTeam.lineup = outcome.lineup
            store.save()
        }

        autoFillPrompt = ""

        if let message = outcome.incompleteMessage {
            autoFillIncompleteMessage = message
            showingAutoFillIncomplete = true
        }

        if let notice = outcome.noticeMessage {
            autoFillConstraintNoticeMessage = notice
            let delay = outcome.hasUnfilledSlots ? 0.35 : 0
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                showingAutoFillConstraintNotice = true
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab selector
            HStack(spacing: 0) {
                ForEach(DetailTab.allCases, id: \.self) { tab in
                    Button {
                        selectedTab = tab
                        Analytics.signal("ipad.detail.tab.changed", parameters: ["tab": tab.rawValue])
                    } label: {
                        Text(tab.rawValue)
                            .font(.subheadline)
                            .fontWeight(selectedTab == tab ? .semibold : .regular)
                            .foregroundColor(selectedTab == tab ? .primary : .secondary)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(
                                selectedTab == tab
                                    ? Color(.systemBackground)
                                    : Color(.systemGray6)
                            )
                    }
                    .buttonStyle(.plain)

                    if tab != DetailTab.allCases.last {
                        Divider()
                            .frame(height: 36)
                    }
                }
                Spacer()

                // Hidden keyboard shortcut buttons for Cmd+1 through Cmd+4
                // These sit at the end of the tab bar and are invisible to the user.
                Group {
                    Button("") { selectedTab = .players }
                        .keyboardShortcut("1", modifiers: .command)
                        .help("Players (Cmd+1)")
                    Button("") { selectedTab = .lineup }
                        .keyboardShortcut("2", modifiers: .command)
                        .help("Lineup (Cmd+2)")
                    Button("") { selectedTab = .positions }
                        .keyboardShortcut("3", modifiers: .command)
                        .help("Positions (Cmd+3)")
                    Button("") { selectedTab = .history }
                        .keyboardShortcut("4", modifiers: .command)
                        .help("History (Cmd+4)")
                }
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
            }
            .background(Color(.systemGray6))
            .overlay(alignment: .bottom) { Divider() }

            // Content
            Group {
                switch selectedTab {
                case .positions:
                    VStack(spacing: 0) {
                        if isReadOnly { ReadOnlyBanner() }

                        // Status strip — same as iPhone. isReadOnly swaps
                        // Finalize/Reopen for a "View only" badge; the iPad
                        // never passed it, so a view-only coach could finalize
                        // a lineup and push a notification to the whole team.
                        LineupStatusStrip(
                            status: store.lineup.status,
                            isReadOnly: isReadOnly,
                            onFinalize: { store.finalizeLineup() },
                            onReopen: { store.reopenLineup() }
                        )

                        iPadPositionsPane(
                            onAutoFill: {
                                showingAutoFillPopover = true
                            },
                            showingAutoFillPopover: $showingAutoFillPopover,
                            onFillThrough: { lastInning in
                                Task { await performAutoFill(through: lastInning) }
                            },
                            smartDefaultLastInning: smartDefaultLastInning,
                            autoFillPrompt: $autoFillPrompt,
                            isParsingAutoFillPrompt: autoFill.isParsingPrompt
                        )
                        .onChange(of: showingAutoFillPopover) { _, isShowing in
                            if isShowing { autoFill.prewarm(for: store.activeTeam) } else { autoFill.teardown() }
                        }

                        // Clear positions button — summary-only context, clears all innings
                        if hasAnyAssignments && !isReadOnly {
                            HStack {
                                Spacer()
                                Button {
                                    showingClearAllConfirm = true
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "xmark.circle")
                                            .font(.caption.bold())
                                        Text("Clear positions")
                                            .font(.caption.bold())
                                    }
                                    .foregroundColor(Color(red: 0.89, green: 0.29, blue: 0.29))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 7)
                                    .background(Color(red: 0.99, green: 0.92, blue: 0.92))
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .strokeBorder(Color(red: 0.94, green: 0.58, blue: 0.58), lineWidth: 0.5)
                                    )
                                }
                                .buttonStyle(.plain)
                                Spacer()
                            }
                            .padding(.vertical, 10)
                            .background(Color(.systemBackground))
                            .overlay(
                                Rectangle()
                                    .frame(height: 0.5)
                                    .foregroundColor(Color(.separator)),
                                alignment: .top
                            )
                        }
                    }

                case .lineup:
                    LineupView(showingArchive: $showingArchive)

                case .players:
                    PlayersView()

                case .history:
                    GameLogsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .alert("Clear all positions?", isPresented: $showingClearAllConfirm) {
            Button("Clear", role: .destructive) {
                store.clearPositions()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All inning assignments will be removed. This can't be undone.")
        }
        .alert("Some Positions Not Filled", isPresented: $showingAutoFillIncomplete) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(autoFillIncompleteMessage)
        }
        .alert("About Your Instructions", isPresented: $showingAutoFillConstraintNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(autoFillConstraintNoticeMessage)
        }
    }
}

// MARK: - Positions Pane Mode

/// Segmented-control selection for the Positions tab detail pane.
private enum PositionsPaneMode: String, CaseIterable {
    case position = "By Position"
    case inning   = "By Inning"
    case pitching = "Pitching"

    var title: String {
        switch self {
        case .position: return "Position Summary"
        case .inning:   return "Inning by inning"
        case .pitching: return "Pitching"
        }
    }
}

// MARK: - Positions Pane

/// The Positions tab detail body: a segmented By Position matrix, the
/// By Inning diamond (default), and a lightweight Pitching table. The diamond
/// follows the DefensiveGridView field spec applied at iPad dashboard scale.
private struct iPadPositionsPane: View {
    @EnvironmentObject var store: LineupStore
    @EnvironmentObject var purchaseManager: PurchaseManager

    var onAutoFill: () -> Void
    @Binding var showingAutoFillPopover: Bool
    var onFillThrough: (Int) -> Void
    var smartDefaultLastInning: Int
    @Binding var autoFillPrompt: String
    var isParsingAutoFillPrompt: Bool

    @State private var mode: PositionsPaneMode = .inning
    @State private var selectedInning: Int = 0

    /// View-only participants in a shared team. The iPhone grid has gated every
    /// mutating control on this since shared teams shipped; this pane never did,
    /// and neither do the picker sheets it presents — `PositionPickerView` and
    /// `PlayerPickerView` rely on their call sites for it — so a read-only coach
    /// on iPad could reassign positions for real.
    private var isReadOnly: Bool { store.activeTeam.isReadOnly }

    // Picker sheets — same targets as the iPhone diamond (DefensiveGridView).
    @State private var selectedSlot: DefensiveGridView.SlotTarget? = nil
    @State private var selectedPlayer: Player? = nil
    @State private var quickSetTarget: QuickSetTarget? = nil
    @State private var pitchingAssignmentPlayer: Player? = nil

    struct QuickSetTarget: Identifiable {
        let id = UUID()
        let origin: QuickSetSheet.Origin
        let inning: Int
    }

    // MARK: Derived Data

    private var displayPlayers: [Player] {
        store.lineup.displayPlayers(from: store.players)
    }
    private var activePlayers: [Player] {
        store.lineup.activePlayers(from: store.players)
    }
    private var inningCount: Int { store.lineup.innings.count }
    /// Guard against a stale selection when the inning count shrinks.
    private var clampedInning: Int { min(selectedInning, max(0, inningCount - 1)) }
    private var activePositions: [FieldPosition] {
        store.lineup.activeFieldPositions(config: store.fairPlayConfig)
    }

    private let paneHorizontalPadding: CGFloat = 26

    // MARK: Body

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
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(mode.title)
                            .font(.largeTitle.bold())
                            .padding(.bottom, 16)

                        Picker("View", selection: $mode) {
                            ForEach(PositionsPaneMode.allCases, id: \.self) { m in
                                Text(m.rawValue).tag(m)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.bottom, 20)
                        .tourTip(Tour.positions.currentTip as? PositionsViewModeTip, arrowEdge: .top)
                        .tourTip(Tour.positions.currentTip as? PositionsAssignTip, arrowEdge: .bottom)

                        switch mode {
                        case .position:
                            byPositionMatrix(availableWidth: geo.size.width)
                        case .inning:
                            byInningDiamond
                        case .pitching:
                            pitchingTable
                        }
                    }
                    .padding(.horizontal, paneHorizontalPadding)
                    .padding(.top, 22)
                    .padding(.bottom, 26)
                }
            }
            .background(Color(.systemBackground))
            .sheet(item: $selectedSlot) { slot in
                PlayerPickerView(position: slot.position, benchSlotOccupant: slot.benchOccupant, inning: clampedInning)
                    .environmentObject(store)
                    .environmentObject(purchaseManager)
            }
            .sheet(item: $selectedPlayer) { player in
                PositionPickerView(player: player, inning: clampedInning)
                    .environmentObject(store)
            }
            .sheet(item: $quickSetTarget) { target in
                QuickSetSheet(origin: target.origin, initialInning: target.inning)
                    .environmentObject(store)
            }
            .sheet(item: $pitchingAssignmentPlayer) { player in
                PitchingAssignmentSheet(player: player)
                    .environmentObject(store)
            }
            .onChange(of: mode) { _, newMode in
                Analytics.signal("ipad.positions.mode.changed", parameters: ["mode": newMode.rawValue])
            }
        }
    }

    // MARK: - By Position (position × inning matrix)

    private let matrixLabelWidth: CGFloat = 152
    private let matrixGap: CGFloat = 7

    private func matrixColumnWidth(availableWidth: CGFloat) -> CGFloat {
        let remaining = availableWidth - paneHorizontalPadding * 2 - matrixLabelWidth
            - matrixGap * CGFloat(inningCount)
        return max(56, remaining / CGFloat(inningCount))
    }

    @ViewBuilder
    private func byPositionMatrix(availableWidth: CGFloat) -> some View {
        let colWidth = matrixColumnWidth(availableWidth: availableWidth)

        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(spacing: matrixGap) {
                Text("Position")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(width: matrixLabelWidth, alignment: .leading)
                ForEach(0..<inningCount, id: \.self) { i in
                    Text("Inn \(i + 1)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: colWidth)
                }
            }
            .padding(.bottom, 4)

            matrixGroupHeader("Infield", color: .blue)
            ForEach(activePositions.filter { $0.isInfield }, id: \.self) { pos in
                matrixRow(pos, colWidth: colWidth)
            }

            matrixGroupHeader("Outfield", color: .green)
            ForEach(activePositions.filter { $0.isOutfield }, id: \.self) { pos in
                matrixRow(pos, colWidth: colWidth)
            }

            matrixGroupHeader("Bench", color: Color(.systemGray2))
            benchMatrixRow(colWidth: colWidth)

            matrixFairPlayFooter
                .padding(.top, 18)
        }
    }

    private func matrixGroupHeader(_ label: String, color: Color) -> some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .kerning(0.5)
        }
        .padding(.top, 15)
        .padding(.bottom, 8)
        .padding(.leading, 2)
    }

    private func matrixRow(_ pos: FieldPosition, colWidth: CGFloat) -> some View {
        HStack(spacing: matrixGap) {
            HStack(spacing: 8) {
                Text(pos.rawValue)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 7)
                    .frame(minWidth: 32, minHeight: 22)
                    .background(pos.badgeColor)
                    .cornerRadius(6)
                Text(pos.displayName)
                    .font(.system(size: 12.5))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(width: matrixLabelWidth, alignment: .leading)

            ForEach(0..<inningCount, id: \.self) { inning in
                matrixCell(pos, inning: inning, colWidth: colWidth)
            }
        }
        .padding(.bottom, matrixGap)
    }

    private func matrixCell(_ pos: FieldPosition, inning: Int, colWidth: CGFloat) -> some View {
        let player = store.lineup.innings[inning].player(at: pos, in: store.players)
        let tint: Color = pos.isOutfield ? Color.green.opacity(0.13) : Color.blue.opacity(0.12)

        return Button {
            guard !isReadOnly else { return }
            quickSetTarget = QuickSetTarget(origin: .position(pos, benchIndex: nil), inning: inning)
        } label: {
            Group {
                if let player {
                    Text(player.firstName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                } else {
                    Text("+")
                        .font(.system(size: 20, weight: .light))
                        .foregroundColor(Color(.systemGray3))
                }
            }
            .padding(.horizontal, 6)
            .frame(width: colWidth, height: 40)
            .background(player != nil ? tint : Color(.systemBackground))
            .cornerRadius(9)
            .overlay {
                if player == nil {
                    RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(Color(.separator).opacity(0.4), lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isReadOnly)
    }

    /// One gray well per inning holding a chip for each benched player.
    private func benchMatrixRow(colWidth: CGFloat) -> some View {
        HStack(alignment: .top, spacing: matrixGap) {
            Color.clear
                .frame(width: matrixLabelWidth, height: 1)

            ForEach(0..<inningCount, id: \.self) { inning in
                let benched = displayPlayers.filter {
                    store.lineup.innings[inning].position(for: $0) == .bench
                }
                VStack(spacing: 4) {
                    ForEach(benched) { player in
                        Button {
                            guard !isReadOnly else { return }
                            quickSetTarget = QuickSetTarget(origin: .player(player), inning: inning)
                        } label: {
                            Text(player.firstName)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                                .padding(.horizontal, 6)
                                .background(Color(.systemBackground))
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .disabled(isReadOnly)
                    }
                }
                .padding(5)
                .frame(width: colWidth, alignment: .top)
                .frame(minHeight: 44, alignment: .top)
                .background(Color(.systemGray6))
                .cornerRadius(9)
            }
        }
    }

    /// Green all-clear line under the matrix. Violations themselves live in
    /// the always-on Fair Play rail, so no warning list is duplicated here.
    @ViewBuilder
    private var matrixFairPlayFooter: some View {
        let hasAssignments = store.lineup.innings.contains { !$0.assignments.isEmpty }
        // This version checked four rules by hand and silently omitted both
        // battery rules, so it could promise "all players meet fair play
        // requirements" over a live catcher-then-pitcher violation. An all-clear
        // that isn't true is worse than no all-clear at all.
        let allClear = store.lineup
            .fairPlayFindings(players: store.players, config: store.fairPlayConfig)
            .isEmpty

        if hasAssignments && allClear {
            HStack(spacing: 7) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.green)
                Text("All players meet fair play requirements")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.green)
            }
        }
    }

    // MARK: - By Inning (diamond)

    private var byInningDiamond: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: inning title + fill status + Auto-Fill
            HStack(spacing: 12) {
                Text("Inning \(clampedInning + 1)")
                    .font(.title2.bold())
                fillStatusLabel
                Spacer()
                // Hidden rather than disabled when read-only, matching the
                // iPhone grid's bolt button.
                if !isReadOnly { autoFillButton }
            }
            .padding(.bottom, 16)

            HStack(alignment: .top, spacing: 22) {
                inningRail

                // Field — the primary element; dominates the remaining width.
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    diamondField
                        .aspectRatio(1 / 0.82, contentMode: .fit)
                        .frame(maxWidth: 720)
                        .padding(.top, 20)
                    Spacer(minLength: 0)
                }
            }

            // Bench + Absent side by side, aligned past the inning rail.
            HStack(alignment: .top, spacing: 40) {
                chipGroup("Bench") { benchChips }
                chipGroup("Late arrival / early departure") { absentChips }
            }
            .padding(.leading, 78)
            .padding(.top, 24)
        }
    }

    private var fillStatusLabel: some View {
        let openCount = store.lineup.openPositions(
            inning: clampedInning, players: activePlayers, config: store.fairPlayConfig
        ).count
        return Text(openCount == 0 ? "Field set" : "\(openCount) \(openCount == 1 ? "spot" : "spots") open")
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(openCount == 0 ? .green : .orange)
    }

    private var autoFillButton: some View {
        Button { onAutoFill() } label: {
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                Text("Auto-Fill Open Positions")
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 11)
            .background(purchaseManager.isPro ? Color.blue : Color(.systemGray3))
            .cornerRadius(10)
            .shadow(color: purchaseManager.isPro ? Color.blue.opacity(0.35) : .clear, radius: 3, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Auto-Fill Open Positions")
        .tourTip(Tour.positions.currentTip as? PositionsAutoFillTip, arrowEdge: .top)
        .tourTip(Tour.secondGame.currentTip as? AutoFillConstraintsTip, arrowEdge: .top)
        .popover(isPresented: $showingAutoFillPopover, arrowEdge: .top) {
            AutoFillPopover(
                isSummary: true,
                smartDefaultLastInning: smartDefaultLastInning,
                inningCount: inningCount,
                prompt: $autoFillPrompt,
                isParsingPrompt: isParsingAutoFillPrompt
            ) { scope in
                if case .through(let last) = scope { onFillThrough(last) }
            }
            .presentationCompactAdaptation(.popover)
        }
    }

    private var inningRail: some View {
        VStack(spacing: 8) {
            ForEach(0..<inningCount, id: \.self) { inning in
                let isSelected = clampedInning == inning
                Button {
                    selectedInning = inning
                } label: {
                    VStack(spacing: 3) {
                        Text("\(inning + 1)")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(isSelected ? .white : .primary)
                        railStatusGlyph(inning: inning, isSelected: isSelected)
                    }
                    .frame(width: 56)
                    .padding(.vertical, 9)
                    .background(isSelected ? Color.blue : Color(.systemGray5))
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 56)
    }

    @ViewBuilder
    private func railStatusGlyph(inning: Int, isSelected: Bool) -> some View {
        let openPos = store.lineup.openPositions(inning: inning, players: activePlayers, config: store.fairPlayConfig)
        let dupPos = store.lineup.duplicatePositionErrors(inning: inning)
        let hasAny = !store.lineup.innings[inning].assignments.isEmpty

        if !dupPos.isEmpty {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(isSelected ? .white : .red)
        } else if !openPos.isEmpty && hasAny {
            Image(systemName: "minus")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(isSelected ? .white : .orange)
        } else if openPos.isEmpty && hasAny {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(isSelected ? .white : .green)
        } else {
            Circle()
                .fill(isSelected ? Color.white.opacity(0.7) : Color.gray.opacity(0.35))
                .frame(width: 6, height: 6)
                .frame(height: 12)
        }
    }

    /// The schematic field: outfield fan + infield diamond drawn in the design's
    /// 0–100 coordinate space (shared shapes), with position slots on top.
    private var diamondField: some View {
        GeometryReader { geo in
            ZStack {
                OutfieldFanShape()
                    .fill(Color.green.opacity(0.07))
                OutfieldFanShape()
                    .stroke(Color(.separator), lineWidth: 0.5)
                InfieldDiamondShape()
                    .fill(Color.blue.opacity(0.09))
                InfieldDiamondShape()
                    .stroke(Color(.separator), lineWidth: 0.5)

                ForEach(activePositions, id: \.self) { pos in
                    if let coord = diamondCoordinate(for: pos) {
                        fieldSlot(pos)
                            .position(
                                x: geo.size.width * coord.x / 100,
                                y: geo.size.height * coord.y / 100
                            )
                    }
                }
            }
        }
    }

    /// Slot placement as percentages of the field box, from the design spec.
    /// LCF/RCF aren't in the design (it assumes 3 outfielders) — under
    /// 4-outfielder configs they sit on the outfield arc where CF was.
    private func diamondCoordinate(for pos: FieldPosition) -> CGPoint? {
        switch pos {
        case .centerField:      return CGPoint(x: 50, y: 13)
        case .leftField:        return CGPoint(x: 19, y: 24)
        case .rightField:       return CGPoint(x: 81, y: 24)
        case .leftCenterField:  return CGPoint(x: 36, y: 15)
        case .rightCenterField: return CGPoint(x: 64, y: 15)
        case .shortstop:        return CGPoint(x: 36, y: 45)
        case .secondBase:       return CGPoint(x: 64, y: 45)
        case .thirdBase:        return CGPoint(x: 23, y: 60)
        case .firstBase:        return CGPoint(x: 77, y: 60)
        case .pitcher:          return CGPoint(x: 50, y: 61)
        case .catcher:          return CGPoint(x: 50, y: 87)
        case .bench, .absent:   return nil
        }
    }

    /// One field slot: position badge over the occupant's name chip ("Open"
    /// when empty). Tapping opens the player picker for the slot.
    @ViewBuilder
    private func fieldSlot(_ pos: FieldPosition) -> some View {
        let occupant = store.lineup.innings[clampedInning].player(at: pos, in: store.players)
        let isDuplicate = store.lineup.duplicatePositionErrors(inning: clampedInning).contains(pos)
        let pitchWarning: Bool = {
            guard pos == .pitcher, let occupant, store.pitchingConfig.rulesEnabled else { return false }
            return PitchEligibilityEngine.status(
                for: occupant, gameLogs: store.gameLogs, config: store.pitchingConfig,
                referenceDate: store.lineup.gameDate
            ).blocksAssignment
        }()

        Button {
            guard !isReadOnly else { return }
            selectedSlot = DefensiveGridView.SlotTarget(position: pos, benchOccupant: nil)
        } label: {
            VStack(spacing: 4) {
                slotBadge(pos, occupant: occupant)

                HStack(spacing: 3) {
                    Text(occupant.map { diamondDisplayName($0) } ?? "Open")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundColor(occupant == nil ? Color(.systemGray) : .primary)
                        .lineLimit(1)
                    if pitchWarning {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.red)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(isDuplicate ? Color.red.opacity(0.08) : Color.clear)
                .background(Color(.systemBackground))
                .cornerRadius(8)
                .shadow(color: .black.opacity(0.12), radius: 3, x: 0, y: 1)
            }
            .fixedSize()
        }
        .buttonStyle(.plain)
        .disabled(isReadOnly)
    }

    /// Solid position badge for a field slot, with the Emergency/Never
    /// preference border when the occupant has a preference set (Pro).
    @ViewBuilder
    private func slotBadge(_ pos: FieldPosition, occupant: Player?) -> some View {
        let prefTier: PositionPreferenceTier? = purchaseManager.isPro
            ? occupant?.positionPreferences[pos]
            : nil
        let showBorder = prefTier == .emergency || prefTier == .never

        Text(pos.rawValue)
            .font(.system(size: 14, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 9)
            .frame(minWidth: 40, minHeight: 27)
            .background(pos.badgeColor)
            .cornerRadius(7)
            .shadow(color: .black.opacity(0.20), radius: 3, x: 0, y: 1)
            .overlay {
                if showBorder, let tier = prefTier {
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(tier.color, lineWidth: 2)
                }
            }
    }

    // MARK: Diamond display names

    /// First names that appear more than once in the lineup — computed across
    /// the full lineup so a player's field label never changes between innings.
    private var collidingFirstNames: Set<String> {
        var counts: [String: Int] = [:]
        for player in displayPlayers { counts[player.firstName, default: 0] += 1 }
        return Set(counts.filter { $0.value > 1 }.keys)
    }

    /// Field-slot display name: first name only, adding a last initial
    /// ("Cameron T.") when two lineup players share a first name.
    private func diamondDisplayName(_ player: Player) -> String {
        collidingFirstNames.contains(player.firstName) ? player.shortName : player.firstName
    }

    // MARK: Bench / Absent chip groups

    private var benchedPlayers: [Player] {
        displayPlayers.filter { store.lineup.innings[clampedInning].position(for: $0) == .bench }
    }

    private var absentPlayersThisInning: [Player] {
        displayPlayers.filter { store.lineup.innings[clampedInning].position(for: $0) == .absent }
    }

    private func chipGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .textCase(.uppercase)
                .foregroundColor(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var benchChips: some View {
        ChipFlowLayout(spacing: 9) {
            ForEach(benchedPlayers) { player in
                chip(player, kind: .bench)
            }
            if !isReadOnly {
                addChip("+ Bench", target: .bench)
            }
        }
    }

    private var absentChips: some View {
        ChipFlowLayout(spacing: 9) {
            ForEach(absentPlayersThisInning) { player in
                chip(player, kind: .absent)
            }
            if !isReadOnly {
                addChip("+ Absent", target: .absent)
            }
        }
    }

    private func chip(_ player: Player, kind: PlayerChip.Kind) -> some View {
        PlayerChip(player: player, kind: kind, inning: clampedInning, isReadOnly: isReadOnly) {
            selectedPlayer = player
        }
    }

    /// Dashed "+ Bench" / "+ Absent" chip — opens the picker targeting that slot.
    private func addChip(_ label: String, target: FieldPosition) -> some View {
        Button {
            selectedSlot = DefensiveGridView.SlotTarget(position: target, benchOccupant: nil)
        } label: {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.blue)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .overlay(
                    Capsule()
                        .strokeBorder(Color(.systemGray3), style: StrokeStyle(lineWidth: 1.5, dash: [4]))
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Pitching

    /// Lightweight PITCHER · INNINGS · REST table. Tapping a row opens the
    /// existing pitching assignment sheet.
    private var pitchingTable: some View {
        let rows: [(player: Player, innings: Int, rest: String)] = displayPlayers
            .filter { $0.positionPreferences[.pitcher] != .never }
            .map { player in
                let innings = store.lineup.innings.filter { $0.assignments[player.id] == .pitcher }.count
                let rest: String = {
                    guard store.pitchingConfig.rulesEnabled else { return "—" }
                    let status = PitchEligibilityEngine.status(
                        for: player, gameLogs: store.gameLogs, config: store.pitchingConfig,
                        referenceDate: store.lineup.gameDate
                    )
                    if case .eligible = status { return "—" }
                    return status.displayLabel
                }()
                return (player, innings, rest)
            }
            .sorted { a, b in
                if a.innings != b.innings { return a.innings > b.innings }
                return a.player.displayName < b.player.displayName
            }

        return VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 0) {
                HStack {
                    Text("PITCHER")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("INNINGS")
                        .frame(width: 90, alignment: .trailing)
                    Text("REST")
                        .frame(width: 110, alignment: .trailing)
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .kerning(0.4)
                .padding(.horizontal, 16)
                .padding(.vertical, 13)

                Divider()

                if rows.isEmpty {
                    Text("No players have Pitcher as an available position preference.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(rows, id: \.player.id) { row in
                        Button {
                            guard !isReadOnly else { return }
                            pitchingAssignmentPlayer = row.player
                        } label: {
                            HStack {
                                Text(row.player.displayName)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text("\(row.innings)")
                                    .font(.system(size: 15, weight: .semibold).monospacedDigit())
                                    .foregroundColor(.primary)
                                    .frame(width: 90, alignment: .trailing)
                                Text(row.rest)
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .frame(width: 110, alignment: .trailing)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(isReadOnly)

                        if row.player.id != rows.last?.player.id {
                            Divider()
                                .padding(.leading, 16)
                        }
                    }
                }
            }
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.5)
            )

            if !store.pitchingConfig.rulesEnabled {
                Text("Pitch tracking is off for this game. Turn it on in team settings to log pitch counts and enforce rest days.")
                    .font(.system(size: 12.5))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: 560, alignment: .leading)
    }
}
