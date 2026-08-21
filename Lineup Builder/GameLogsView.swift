import SwiftUI
import TipKit

// MARK: - GameLogsView
// The History tab. A three-tab experience:
//   Players — per-player season stats cards with position breakdown and gaps
//   Games   — chronological list of archived game logs
//   Team    — position coverage grid and bench distribution across the roster
//
// Pro coaches see all of it. Free coaches see the same tabs in *teaser* mode
// (`isTeaser`): a real slice of their own season — the first player, the most
// recent game, the top of the coverage grid — with the rest blurred behind an
// upgrade CTA (see LockedHistoryView.swift for the shared teaser pieces). The
// paywall only appears when the coach taps for it; nothing auto-presents.
//
// Free coaches can archive games (the gate is on viewing, not archiving), so
// the Games tab still shows the "Ready to Archive" section. A coach with no
// history at all gets HistoryEmptyState rather than a blurred nothing.

struct GameLogsView: View {
    @EnvironmentObject var store: LineupStore
    @EnvironmentObject var purchaseManager: PurchaseManager
    @Environment(\.verticalSizeClass) var verticalSizeClass
    @StateObject private var insightsService = GameLogInsightsService()

    /// True when the History tab (tag 3) is the one on screen. The iPad
    /// dashboard embeds this view and leaves it at the default. Keeps the
    /// season-views tip from presenting over another tab when it first becomes
    /// eligible (on archive, while the coach may be on Lineup or Positions).
    var isTourTabActive: Bool = true

    @State private var selectedTab: HistoryTab = .players
    // Mirrors the ordered `Tour.history` group's current tip, driven by the
    // group's `currentTipUpdates` async sequence instead of read synchronously.
    // The lead tip (`HistorySeasonViewsTip`) gates on `isPro`, a StoreKit-derived
    // @Parameter that resolves asynchronously; TipKit re-evaluates the group a
    // beat after it flips, so a synchronous `currentTip` read at render time can
    // still be nil in the very pass that Pro unlocks — dropping the tip until an
    // unrelated re-render. Reacting to `currentTipUpdates` makes the anchor pick
    // up the resolved tip the instant it lands. See tipkit-currenttip-async.
    @State private var currentHistoryTip: (any Tip)?
    @State private var logToDelete: GameLog? = nil
    @State private var showingDeleteConfirmation = false
    @State private var showingTips = false
    @State private var showingPaywall = false
    @State private var showingArchive = false
    // Auto-opens the Pro gate the first time a free coach lands on History this
    // session. After they dismiss it, the blurred teaser stays with its own
    // unlock button, so it never re-throws the modal on every tab switch.
    /// Free coaches see the tabs in teaser mode; Pro coaches see them in full.
    private var isTeaser: Bool { !purchaseManager.isPro }

    // Tip overlay driven by parent iPhoneTabView

    enum HistoryTab { case players, games, team }

    // Pre-compute season stats once so all sub-views share the same result.
    // outfielderCount is forwarded so positionGaps and position bar rows only
    // reflect positions that are actually configured for this team.
    private var seasonStats: SeasonStats {
        SeasonStatsCalculator.compute(
            from: store.gameLogs,
            players: store.players,
            outfielderCount: store.fairPlayConfig.outfielderCount
        )
    }

    /// The current lineup is a past finalized game that hasn't been archived yet.
    private var readyToArchiveLineup: Bool {
        store.lineup.isPastAndFinalized
    }

    private var historyContent: some View {
        Group {
            if !purchaseManager.isResolved {
                // StoreKit hasn't answered yet. Deliberately NOT the teaser
                // branch: `isPro` is false while undetermined, so falling
                // through would show a paying coach the locked teaser on a slow
                // or offline cold launch. Wait for the real answer first.
                entitlementResolvingState
            } else if store.gameLogs.isEmpty && !readyToArchiveLineup {
                // No history to show either way. A free coach gets an honest
                // nudge (nothing real to tease); a Pro coach gets the standard
                // empty state.
                if purchaseManager.isPro {
                    emptyState
                } else {
                    HistoryEmptyState(teamColor: store.teamColor) { showingPaywall = true }
                        .environmentObject(purchaseManager)
                }
            } else {
                // Free coaches see the real tabs in teaser mode — a genuine
                // slice of their season, the rest blurred behind the CTA. The
                // paywall only appears when they ask for it; no auto-open.
                tabbedContent
            }
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(verticalSizeClass == .compact ? .inline : .large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showingTips = true } label: {
                    Image(systemName: "info.circle")
                }
            }
        }
        .sheet(isPresented: $showingTips) {
            PageTipsView(page: .history)
        }
        .fullScreenCover(isPresented: $showingPaywall) {
            // Neutral branded backdrop — the real teaser is already what the
            // coach sees on the tab, so the gate no longer needs a preview.
            ProGate(source: "game_history", navTitle: "Game History")
                .environmentObject(purchaseManager)
        }
        .sheet(isPresented: $showingArchive) {
            ArchiveGameSheet()
                .environmentObject(store)
        }
    }

    var body: some View {
        // Always our own stack. The iPad dashboard embeds this pane bare — it
        // has no navigation container of its own — so dropping the stack on
        // regular width left the "History" title, the info-button toolbar, and
        // the NavigationLink into GameLogDetailView all inert on iPad. Matches
        // PlayersView, which wraps unconditionally in the same detail pane.
        NavigationStack { historyContent }
        .onAppear {
            if purchaseManager.isPro {
                insightsService.loadIfNeeded(logs: store.gameLogs)
            }
        }
        .onChange(of: store.gameLogs.count) {
            if purchaseManager.isPro {
                insightsService.loadIfNeeded(logs: store.gameLogs)
            }
        }
        .onChange(of: purchaseManager.isPro) { _, newValue in
            if newValue { insightsService.loadIfNeeded(logs: store.gameLogs) }
        }
    }

    // MARK: - Empty State

    /// Shown for the moment between launch and StoreKit answering. Says nothing
    /// about whether the coach has Pro, because at this point nothing knows.
    /// Usually invisible; on a cold offline launch it is what stands in for the
    /// paywall that used to appear here.
    private var entitlementResolvingState: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text("Checking your subscription…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer(minLength: 40)

                ZStack {
                    Circle()
                        .fill(Color.teal.opacity(0.12))
                        .frame(width: 110, height: 110)
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 48))
                        .foregroundColor(.teal)
                }

                VStack(spacing: 8) {
                    Text("No Games Archived Yet")
                        .font(.title3.bold())
                    Text("After each game, tap the Archive button on the Lineup or Positions tab. Set the innings played and your season stats start building here.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                // What they'll unlock
                VStack(alignment: .leading, spacing: 14) {
                    EmptyStateFeatureRow(
                        icon: "person.3.fill", color: .blue,
                        title: "Player Season Stats",
                        detail: "Innings played, bench time, infield/outfield split per player"
                    )
                    EmptyStateFeatureRow(
                        icon: "square.grid.3x3.fill", color: .teal,
                        title: "Team Position Coverage",
                        detail: "Which positions each player has and hasn't covered"
                    )
                    EmptyStateFeatureRow(
                        icon: "sparkles", color: .purple,
                        title: "AI Coaching Insights",
                        detail: "Bench time, field balance, and playing time across the season"
                    )
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 20)
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(14)
                .padding(.horizontal, 24)

                Spacer(minLength: 40)
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Tabbed Content

    private var tabbedContent: some View {
        VStack(spacing: 0) {
            // Segment control pinned below the nav bar
            Picker("", selection: $selectedTab) {
                Text("Players").tag(HistoryTab.players)
                Text("Games").tag(HistoryTab.games)
                Text("Team").tag(HistoryTab.team)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(.systemGroupedBackground))
            .tourTip(currentHistoryTip as? HistorySeasonViewsTip, arrowEdge: .top,
                     enabled: isTourTabActive)
            .task {
                // Seed with whatever's already resolved, then track every change.
                // currentTipUpdates only yields non-nil tips, so a later group
                // advance to a game-detail tip re-casts to nil here (clearing the
                // picker anchor), and a dismissed lead tip won't re-present
                // because popoverTip honors the tip's own invalidated status.
                currentHistoryTip = Tour.history.currentTip
                for await tip in Tour.history.currentTipUpdates {
                    currentHistoryTip = tip
                }
            }

            Divider()

            // Tab content
            switch selectedTab {
            case .players:
                PlayersTabView(
                    seasonStats: seasonStats,
                    insightsService: insightsService,
                    teamColor: store.teamColor,
                    logs: store.gameLogs,
                    outfielderCount: store.fairPlayConfig.outfielderCount,
                    isTeaser: isTeaser,
                    onUpgrade: { showingPaywall = true }
                )
            case .games:
                GamesTabView(
                    logs: store.gameLogs,
                    readyToArchive: readyToArchiveLineup,
                    logToDelete: $logToDelete,
                    showingDeleteConfirmation: $showingDeleteConfirmation,
                    showingArchive: $showingArchive,
                    isTeaser: isTeaser,
                    onUpgrade: { showingPaywall = true }
                )
                .confirmationDialog(
                    "Delete Game Log?",
                    isPresented: $showingDeleteConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Delete", role: .destructive) {
                        if let log = logToDelete {
                            store.deleteGameLog(id: log.id)
                            insightsService.invalidateCache()
                            insightsService.loadIfNeeded(logs: store.gameLogs)
                        }
                    }
                    Button("Cancel", role: .cancel) { logToDelete = nil }
                } message: {
                    if let log = logToDelete {
                        let opponent = log.opponent.isEmpty ? "this game" : "vs. \(log.opponent)"
                        Text("Delete the log for \(opponent)? This cannot be undone.")
                    }
                }
            case .team:
                TeamTabView(
                    seasonStats: seasonStats,
                    outfielderCount: store.fairPlayConfig.outfielderCount,
                    isTeaser: isTeaser,
                    onUpgrade: { showingPaywall = true }
                )
            }
        }
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - Players Tab

private struct PlayersTabView: View {
    let seasonStats: SeasonStats
    @ObservedObject var insightsService: GameLogInsightsService
    let teamColor: Color
    let logs: [GameLog]
    let outfielderCount: Int
    var isTeaser: Bool = false
    var onUpgrade: () -> Void = {}

    private let cardInsets = EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16)

    var body: some View {
        List {
            // AI Insights card at the top — Pro only. In teaser mode the
            // insights service isn't loaded (loadIfNeeded gates on Pro), so it
            // is omitted rather than shown empty; the CTA advertises it instead.
            if !isTeaser {
                Section {
                    InsightsCardView(
                        service: insightsService,
                        teamColor: teamColor,
                        logs: logs
                    )
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }

            // One card per player. Teaser: the first card crisp, the second
            // blurred as the hook, then the unlock CTA.
            Section {
                let players = seasonStats.players
                let visible = isTeaser ? Array(players.prefix(1)) : players

                ForEach(visible, id: \.playerID) { stats in
                    PlayerSeasonCard(stats: stats, outfielderCount: outfielderCount)
                        .listRowInsets(cardInsets)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                if isTeaser {
                    if players.count > 1 {
                        TeaserBlur(onUpgrade: onUpgrade) {
                            PlayerSeasonCard(stats: players[1], outfielderCount: outfielderCount)
                        }
                        .frame(height: 96)
                        .listRowInsets(cardInsets)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }

                    HistoryUpgradeCTA(
                        subtitle: players.count > 1
                            ? "See all \(players.count) players + AI insights"
                            : "Season stats, coverage, and AI insights",
                        onUpgrade: onUpgrade
                    )
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            } header: {
                Text("\(seasonStats.players.count) Players · \(seasonStats.gameCount) \(seasonStats.gameCount == 1 ? "Game" : "Games")")
            }
        }
        .listStyle(.insetGrouped)
    }
}

// MARK: - Player Season Card

private struct PlayerSeasonCard: View {
    let stats: PlayerSeasonStats
    let outfielderCount: Int

    // Only show positions configured for this team — mirrors activeFieldPositions(config:).
    // 3-OF: LF/CF/RF; 4-OF: LF/LCF/RCF/RF (CF hidden).
    private var infield: [FieldPosition] { FieldPosition.infieldPositions }
    private var outfield: [FieldPosition] {
        outfielderCount == 4
            ? [.leftField, .leftCenterField, .rightCenterField, .rightField]
            : [.leftField, .centerField, .rightField]
    }
    private var allField: [FieldPosition] { infield + outfield }

    // Max innings across all field positions for bar scaling
    private var maxCount: Int {
        let counts = allField.map { pos in stats.posCounts[pos.displayName] ?? 0 }
        return max(counts.max() ?? 0, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 10) {
                initialsAvatar
                VStack(alignment: .leading, spacing: 2) {
                    Text(stats.playerName)
                        .font(.subheadline.bold())
                    Text("\(stats.gamesPlayed) \(stats.gamesPlayed == 1 ? "game" : "games") played")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.bottom, 10)

            // Stat pills
            HStack(spacing: 6) {
                StatPill(value: "\(stats.totalInnings)", label: "innings", color: .primary)
                StatPill(value: "\(stats.benchInnings)", label: "bench", color: .red)
                StatPill(value: "\(stats.infieldInnings)", label: "infield", color: .blue)
                StatPill(value: "\(stats.outfieldInnings)", label: "outfield", color: .green)
            }
            .padding(.bottom, 10)

            // Position breakdown bars
            Text("Innings at position")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 5)

            ForEach(allField, id: \.self) { pos in
                positionBarRow(for: pos)
            }

            // Never-played gaps (only after 3+ games, only non-Never positions)
            if !stats.positionGaps.isEmpty {
                Divider()
                    .padding(.top, 8)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Never played")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    gapChips
                }
                .padding(.top, 8)
            }
        }
        .padding(14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color(.separator).opacity(0.4), lineWidth: 0.5)
        )
    }

    // MARK: - Sub-views

    private var initialsAvatar: some View {
        let initials = stats.playerName
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
            .map { String($0) }
            .joined()
        return Text(initials)
            .font(.caption.bold())
            .foregroundStyle(.blue)
            .frame(width: 36, height: 36)
            .background(Color.blue.opacity(0.12))
            .clipShape(Circle())
    }

    @ViewBuilder
    private func positionBarRow(for pos: FieldPosition) -> some View {
        let isNever = stats.neverPositionRawValues.contains(pos.rawValue)
        let count   = stats.posCounts[pos.displayName] ?? 0
        let fillPct = isNever ? 1.0 : Double(count) / Double(maxCount)
        let barColor: Color = pos.isInfield ? .blue : .green

        HStack(spacing: 6) {
            Text(pos.rawValue)
                .font(.caption2)
                .foregroundStyle(isNever ? Color(.tertiaryLabel) : Color(.secondaryLabel))
                .frame(width: 26, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    if isNever {
                        NeverStripeBar()
                            .frame(width: geo.size.width, height: 7)
                    } else {
                        RoundedRectangle(cornerRadius: 3.5)
                            .fill(Color(.systemFill))
                            .frame(height: 7)
                        RoundedRectangle(cornerRadius: 3.5)
                            .fill(barColor)
                            .frame(width: geo.size.width * fillPct, height: 7)
                    }
                }
            }
            .frame(height: 7)

            Text(isNever ? "—" : "\(count)")
                .font(.caption2)
                .foregroundStyle(isNever ? Color(.tertiaryLabel) : Color(.secondaryLabel))
                .frame(width: 16, alignment: .trailing)
        }
        .padding(.bottom, 4)
    }

    private var gapChips: some View {
        FlowLayout(spacing: 4) {
            ForEach(stats.positionGaps, id: \.self) { raw in
                Text(raw)
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.15))
                    .foregroundStyle(Color.orange)
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(Color.orange.opacity(0.4), lineWidth: 0.5))
            }
        }
    }
}

// MARK: - Never Stripe Bar

private struct NeverStripeBar: View {
    var body: some View {
        Canvas { context, size in
            let stripeWidth: CGFloat = 3
            let gap: CGFloat = 3
            let step = stripeWidth + gap
            let color = Color(.systemFill)
            let stripe = Color(.tertiaryLabel).opacity(0.5)

            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(color)
            )

            var x: CGFloat = -size.height
            while x < size.width + size.height {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x + stripeWidth, y: 0))
                path.addLine(to: CGPoint(x: x + stripeWidth + size.height, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: size.height))
                path.closeSubpath()
                context.fill(path, with: .color(stripe))
                x += step
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 3.5))
    }
}

// MARK: - Stat Pill

private struct StatPill: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline.bold())
                .foregroundStyle(color == .primary ? Color.primary : color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Flow Layout

private struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > width, currentX > 0 {
                currentY += lineHeight + spacing
                currentX = 0
                lineHeight = 0
                totalHeight = currentY
            }
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        totalHeight += lineHeight
        return CGSize(width: width, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX, currentX > bounds.minX {
                currentY += lineHeight + spacing
                currentX = bounds.minX
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: ProposedViewSize(size))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

// MARK: - Games Tab

private struct GamesTabView: View {
    let logs: [GameLog]
    let readyToArchive: Bool
    @Binding var logToDelete: GameLog?
    @Binding var showingDeleteConfirmation: Bool
    @Binding var showingArchive: Bool
    var isTeaser: Bool = false
    var onUpgrade: () -> Void = {}

    var body: some View {
        List {
            // Ready to Archive section — shown when there's a past finalized
            // game. Kept for free coaches too: archiving is free.
            if readyToArchive {
                Section {
                    ReadyToArchiveRow(showingArchive: $showingArchive)
                        .listRowBackground(Color.teal.opacity(0.06))
                } header: {
                    Text("Ready to Archive")
                }
            }

            // Archived game logs
            if !logs.isEmpty {
                if isTeaser {
                    teaserSection
                } else {
                    fullSection
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // Pro: every game, navigable, swipe-to-delete.
    @ViewBuilder private var fullSection: some View {
        Section {
            ForEach(logs) { log in
                NavigationLink(destination: GameLogDetailView(log: log)) {
                    GameLogRow(log: log)
                }
            }
            .onDelete { offsets in
                if let first = offsets.first {
                    logToDelete = logs[first]
                    showingDeleteConfirmation = true
                }
            }

            if logs.count >= 20 {
                Text("Showing your last 20 games. Older games are automatically removed.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        } header: {
            Text("\(logs.count) \(logs.count == 1 ? "Game" : "Games")")
        }
    }

    // Free: the most recent game crisp but non-navigating (its detail is Pro),
    // the next blurred, then the CTA. No swipe-to-delete.
    @ViewBuilder private var teaserSection: some View {
        Section {
            // The most recent game is readable, but its detail is Pro — a tap
            // routes to the paywall rather than a dead end. `.contentShape` +
            // `.onTapGesture` is the reliable way to make a whole List row
            // tappable; a plain Button here does not fire.
            GameLogRow(log: logs[0])
                .contentShape(Rectangle())
                .onTapGesture(perform: onUpgrade)

            if logs.count > 1 {
                TeaserBlur(onUpgrade: onUpgrade) {
                    GameLogRow(log: logs[1])
                        .padding(.vertical, 4)
                }
                .frame(height: 64)
                .listRowSeparator(.hidden)
            }

            HistoryUpgradeCTA(
                subtitle: logs.count > 1
                    ? "See all \(logs.count) games and their lineups"
                    : "Open past games and copy their lineups",
                onUpgrade: onUpgrade
            )
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } header: {
            Text("\(logs.count) \(logs.count == 1 ? "Game" : "Games")")
        }
    }
}

// MARK: - Ready to Archive Row

private struct ReadyToArchiveRow: View {
    @EnvironmentObject var store: LineupStore
    @Binding var showingArchive: Bool

    private var dateStr: String {
        store.lineup.gameDate.formatted(date: .abbreviated, time: .omitted)
    }

    private var opponentStr: String {
        store.lineup.opponent.isEmpty ? "No Opponent" : "vs. \(store.lineup.opponent)"
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(opponentStr)
                    .font(.subheadline.bold())
                Text(dateStr)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button {
                showingArchive = true
            } label: {
                Text("Archive")
                    .font(.caption.bold())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.teal.opacity(0.15))
                    .foregroundColor(.teal)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Team Tab

private struct TeamTabView: View {
    let seasonStats: SeasonStats
    let outfielderCount: Int

    // Only show positions configured for this team — mirrors activeFieldPositions(config:).
    private var infieldPositions: [FieldPosition] { FieldPosition.infieldPositions }
    private var outfieldPositions: [FieldPosition] {
        outfielderCount == 4
            ? [.leftField, .leftCenterField, .rightCenterField, .rightField]
            : [.leftField, .centerField, .rightField]
    }
    private var allField: [FieldPosition] { infieldPositions + outfieldPositions }
    var isTeaser: Bool = false
    var onUpgrade: () -> Void = {}

    // How many coverage rows show crisp before the blur, in teaser mode.
    private let teaserVisibleRows = 2

    var body: some View {
        List {
            Section {
                if isTeaser {
                    teaserCoverage
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else {
                    coverageGrid
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            } header: {
                Text("Position coverage")
            }

            // Bench innings — omitted in teaser mode; the coverage CTA covers it.
            if !isTeaser {
                Section {
                    ForEach(seasonStats.players.sorted { $0.benchInnings > $1.benchInnings }, id: \.playerID) { stats in
                        benchRow(stats: stats)
                    }
                } header: {
                    Text("Bench innings this season")
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // Teaser: legend + column header + the first couple of players crisp, the
    // rest of the grid blurred, then the unlock CTA.
    @ViewBuilder private var teaserCoverage: some View {
        let players = seasonStats.players
        let visible = Array(players.prefix(teaserVisibleRows))
        let hidden = Array(players.dropFirst(teaserVisibleRows))

        VStack(alignment: .leading, spacing: 10) {
            coverageLegend
            coverageHeaderRow

            ForEach(visible, id: \.playerID) { stats in
                coverageRow(stats: stats)
            }

            if !hidden.isEmpty {
                TeaserBlur(onUpgrade: onUpgrade) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(hidden.prefix(3), id: \.playerID) { stats in
                            coverageRow(stats: stats)
                        }
                    }
                }
                .frame(maxHeight: 90)
            }

            HistoryUpgradeCTA(
                subtitle: "Full coverage for all \(players.count) players + bench innings",
                onUpgrade: onUpgrade
            )
            .padding(.top, 4)
        }
    }

    private func shortName(from fullName: String) -> String {
        let parts = fullName.components(separatedBy: " ")
        guard let first = parts.first, parts.count > 1,
              let lastInitial = parts.last?.first else {
            return fullName
        }
        return "\(first) \(lastInitial)."
    }

    private var coverageLegend: some View {
        HStack(spacing: 12) {
            legendItem(dotStyle: .played,   label: "Played")
            legendItem(dotStyle: .gap,      label: "Yet to play")
            legendItem(dotStyle: .never,    label: "N/A")
        }
    }

    private var coverageHeaderRow: some View {
        HStack(spacing: 0) {
            Text("")
                .frame(width: 72, alignment: .leading)
            ForEach(allField, id: \.self) { pos in
                Text(pos.rawValue)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var coverageGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            coverageLegend
            coverageHeaderRow

            ForEach(seasonStats.players, id: \.playerID) { stats in
                coverageRow(stats: stats)
            }
        }
    }

    private func coverageRow(stats: PlayerSeasonStats) -> some View {
        HStack(spacing: 0) {
            Text(shortName(from: stats.playerName))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 72, alignment: .leading)

            ForEach(allField, id: \.self) { pos in
                let isNever  = stats.neverPositionRawValues.contains(pos.rawValue)
                let played   = (stats.posCounts[pos.displayName] ?? 0) > 0
                let isGap    = stats.positionGaps.contains(pos.rawValue)

                CoverageDot(
                    style: isNever ? .never : played ? .played : isGap ? .gap : .unplayed
                )
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func benchRow(stats: PlayerSeasonStats) -> some View {
        let maxBench = seasonStats.players.map { $0.benchInnings }.max() ?? 1
        let fraction = Double(stats.benchInnings) / Double(max(maxBench, 1))

        return HStack(spacing: 8) {
            Text(shortName(from: stats.playerName))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3.5)
                        .fill(Color(.systemFill))
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 3.5)
                        .fill(Color.red.opacity(0.7))
                        .frame(width: geo.size.width * fraction, height: 8)
                }
            }
            .frame(height: 8)

            Text("\(stats.benchInnings)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .trailing)
        }
    }

    enum DotStyle { case played, gap, never, unplayed }

    private func legendItem(dotStyle: DotStyle, label: String) -> some View {
        HStack(spacing: 4) {
            CoverageDot(style: dotStyle)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Coverage Dot

private struct CoverageDot: View {
    let style: TeamTabView.DotStyle

    var body: some View {
        switch style {
        case .played:
            Circle()
                .fill(Color.blue)
                .frame(width: 10, height: 10)
        case .gap:
            Circle()
                .fill(Color.orange.opacity(0.2))
                .frame(width: 10, height: 10)
                .overlay(Circle().strokeBorder(Color.orange, lineWidth: 1.5))
        case .never:
            NeverStripeDot()
                .frame(width: 10, height: 10)
        case .unplayed:
            Circle()
                .fill(Color(.systemFill))
                .frame(width: 10, height: 10)
                .overlay(Circle().strokeBorder(Color(.separator).opacity(0.4), lineWidth: 0.5))
        }
    }
}

// MARK: - Never Stripe Dot

private struct NeverStripeDot: View {
    var body: some View {
        Canvas { context, size in
            let r = min(size.width, size.height) / 2
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let clip = Path(ellipseIn: CGRect(origin: .zero, size: size))

            context.clip(to: clip)
            context.fill(clip, with: .color(Color(.systemFill)))

            let stripeColor = Color(.tertiaryLabel).opacity(0.6)
            var x: CGFloat = -size.height
            while x < size.width + size.height {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x + 2, y: 0))
                path.addLine(to: CGPoint(x: x + 2 + size.height, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: size.height))
                path.closeSubpath()
                context.fill(path, with: .color(stripeColor))
                x += 4
            }

            context.stroke(clip, with: .color(Color(.separator).opacity(0.4)), lineWidth: 0.5)
            _ = (r, center)
        }
    }
}

// MARK: - Game Log Row

struct GameLogRow: View {
    let log: GameLog

    /// Static because this is a list row: building a DateFormatter is expensive
    /// relative to formatting with one, and an instance property would allocate
    /// a fresh one on every body evaluation of every row.
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f
    }()

    private var dateString: String {
        Self.dateFormatter.string(from: log.gameDate)
    }

    private var pitchCountPlayerCount: Int {
        log.pitchCounts.values.filter { $0 > 0 }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(dateString)
                    .font(.subheadline.bold())
                Spacer()
                if pitchCountPlayerCount > 0 {
                    Label("\(pitchCountPlayerCount) pitchers", systemImage: "figure.baseball.pitcher")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.trailing, 4)
                }
                Text("\(log.inningsPlayed) inn.")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(.systemGray5))
                    .foregroundColor(.secondary)
                    .cornerRadius(8)
            }
            Text(log.opponent.isEmpty ? "No Opponent" : "vs. \(log.opponent)")
                .font(.callout)
                .foregroundColor(log.opponent.isEmpty ? .secondary : .primary)
            if !log.notes.isEmpty {
                Text(log.notes)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            if !log.archivedBy.isEmpty {
                Text("Archived by \(log.archivedBy)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Insights Card

struct InsightsCardView: View {
    @ObservedObject var service: GameLogInsightsService
    let teamColor: Color
    let logs: [GameLog]

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 14)
                .fill(teamColor.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(teamColor.opacity(0.18), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.subheadline.bold())
                        .foregroundColor(teamColor)
                    Text("Coaching Insights")
                        .font(.subheadline.bold())
                        .foregroundColor(teamColor)
                    Spacer()
                }
                insightBody
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity)
    }

    private func bulletLines(from text: String) -> [String] {
        let rawLines = text.components(separatedBy: "\n")
        var result: [String] = []
        for line in rawLines {
            if line.contains("•") {
                let parts = line.components(separatedBy: "•")
                    .map { "• " + $0.trimmingCharacters(in: .whitespaces) }
                    .filter { $0.trimmingCharacters(in: .whitespaces) != "•" && $0 != "• " }
                result.append(contentsOf: parts)
            } else {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { result.append(trimmed) }
            }
        }
        return result
    }

    @ViewBuilder
    private var insightBody: some View {
        switch service.state {
        case .idle:
            EmptyView()
        case .placeholder:
            Text("Archive 2 or more games to unlock AI coaching insights.")
                .font(.callout)
                .foregroundColor(.secondary)
        case .unsupported:
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "apple.intelligence.badge.xmark")
                    .foregroundColor(.secondary)
                Text("AI insights require iOS 26 and an Apple Intelligence‑capable device.")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
        case .loading:
            HStack(spacing: 10) {
                ProgressView().scaleEffect(0.85)
                Text("Analyzing your season…")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
        case .loaded(let text):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(bulletLines(from: text), id: \.self) { line in
                    Text(line.trimmingCharacters(in: .whitespaces))
                        .font(.callout)
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        case .error:
            VStack(alignment: .leading, spacing: 8) {
                Text("Couldn't load insights right now.")
                    .font(.callout)
                    .foregroundColor(.secondary)
                Button {
                    service.retry(logs: logs)
                } label: {
                    Label("Tap to retry", systemImage: "arrow.clockwise")
                        .font(.caption.bold())
                }
                .buttonStyle(.borderless)
                .foregroundColor(teamColor)
            }
        }
    }
}

// MARK: - Empty State Feature Row
// Used in the History tab empty state to preview what coaches unlock after archiving.

struct EmptyStateFeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(color.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    GameLogsView()
        .environmentObject(LineupStore())
        .environmentObject(PurchaseManager())
}
