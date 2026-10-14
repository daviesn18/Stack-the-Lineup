import SwiftUI
import TipKit

// MARK: - Undo Toast
//
// Shown after an Auto-Fill on the Duo dashboard: what happened, and the lineup
// to restore if the coach didn't want it.

struct DuoUndoToast: Identifiable {
    let id = UUID()
    let text: String
    let snapshot: Lineup
}

struct DuoUndoToastView: View {
    let toast: DuoUndoToast
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Text(toast.text)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
            Button("Undo", action: onUndo)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color(red: 1, green: 0.8, blue: 0))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Capsule().fill(Color.black))
        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
    }
}

// MARK: - Regular-Width Dashboard Chooser
//
// Any regular-width window gets a dashboard. A window with a fold running
// through it (iPhone Duo's inner display) gets the two-halves layout; every
// other one, the iPad's. The choice follows the scene's reserved regions rather
// than a device check, so it also holds in a resized or multitasking window.

struct RegularDashboardView: View {
    @Binding var showingArchive: Bool

    var body: some View {
        GeometryReader { proxy in
            if let fold = DuoFold.read(from: proxy) {
                DuoDashboardView(fold: fold, showingArchive: $showingArchive)
            } else {
                iPadDashboardView(showingArchive: $showingArchive)
            }
        }
    }
}

// MARK: - Duo Dashboard
//
// The iPad dashboard rearranged for the iPhone Duo's inner display: two halves
// split exactly at the fold. Left of the fold is the roster, shown differently
// per tab; right of it is the tab's work surface. Icon actions go in the
// navigation container's toolbar, which the system lays out as a vertical bar
// on this display. Text controls (team switcher, tab strip) stay horizontal.

struct DuoDashboardView: View {
    let fold: DuoFold
    @Binding var showingArchive: Bool

    @EnvironmentObject var store: LineupStore
    @EnvironmentObject var purchaseManager: PurchaseManager
    @EnvironmentObject var router: AppRouter

    @State private var selectedTab: DetailTab = .players
    /// Nonce of the last route applied here, so a pending route is consumed once.
    @State private var lastHandledRouteNonce: UUID?
    @State private var selectedPlayerID: UUID?
    @State private var showingPositionAutoFill = false
    /// View mode, inning, focused position and open picker, shared by both halves.
    @State private var positions = DuoPositionsModel()

    @State private var showingScheduleImport = false
    @State private var scheduleImportToast: String?
    @State private var showingSettings = false
    @State private var showingEditTeam = false
    @State private var showingAddTeam = false
    @State private var showingTips = false
    @State private var pdfRequest: LineupPDFRequest?

    /// Whether the roster shows its fair-play summary, warnings and playing
    /// time. Per device, like the iPad's always-on rail was per install.
    @AppStorage("duoFairPlayVisible") private var fairPlayVisible = true

    private var isReadOnly: Bool { store.activeTeam.isReadOnly }

    private var canExportCoachesGuide: Bool {
        LineupPDFExport.canExportCoachesGuide(team: store.activeTeam, isPro: purchaseManager.isPro)
    }

    private var tipsPage: AppPage {
        switch selectedTab {
        case .players:   return .players
        case .lineup:    return .lineup
        case .positions: return .positions
        case .history:   return .history
        }
    }

    /// Width of the left half. The fold sits at the physical center, so the
    /// half stops half a gutter short of it.
    private func leftWidth(in available: CGFloat) -> CGFloat {
        min(max(fold.splitX - fold.gutter / 2, 0), available * 0.7)
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let left = leftWidth(in: geo.size.width)
                VStack(spacing: 0) {
                    header(leftWidth: left)
                    Divider()
                    HStack(spacing: 0) {
                        leftContent
                            .frame(width: left)
                        gutter
                        rightContent
                            .frame(maxWidth: .infinity)
                    }
                    .overlay {
                        if selectedTab == .positions, let target = positions.picker {
                            DuoPickerOverlay(
                                target: target,
                                leftWidth: left,
                                gutterWidth: gutterWidth,
                                onDismiss: { positions.picker = nil }
                            )
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: positions.picker)
                }
            }
            .background(Color(.systemBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .background { shortcutButtons }
        }
        .environment(positions)
        .onChange(of: selectedTab) { _, _ in positions.picker = nil }
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
        .sheet(isPresented: $showingTips) {
            PageTipsView(page: tipsPage)
        }
        .lineupPDFExports(request: $pdfRequest)
        // Toast overlay — centered in the right half, where the coach is looking.
        .overlay(alignment: .bottom) {
            if let toast = scheduleImportToast {
                Text(toast)
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color(.label)))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 20)
            }
        }
        .animation(.spring(duration: 0.35), value: scheduleImportToast)
        .onAppear {
            Analytics.signal("duo.dashboard.opened", parameters: [
                "playerCount": "\(store.players.count)"
            ])
            consumePendingRoute()
        }
        .onChange(of: router.request) { _, _ in
            consumePendingRoute()
        }
        .remoteDeletionPrompt(store: store)
    }

    // MARK: Header

    private func header(leftWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 10) {
                teamSwitcher
                Divider().frame(height: 22)
                gameContext
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(width: leftWidth, alignment: .leading)

            Color.clear.frame(width: gutterWidth)

            tabStrip
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 48)
        .background(Color(.systemBackground))
    }

    private var teamSwitcher: some View {
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
                    .font(.system(size: 17, weight: .semibold))
                    .tracking(-0.4)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(.blue)
        }
        .fixedSize()
        .tourTip(Tour.players.currentTip as? PlayersTeamSetupTip, arrowEdge: .top)
    }

    /// Opponent, date and inning count — truncates before it can crowd the fold.
    private var gameContext: some View {
        let opponent = store.lineup.opponent.isEmpty ? "" : "vs. \(store.lineup.opponent) · "
        let date = store.lineup.gameDate.formatted(date: .abbreviated, time: .omitted)
        return Text("\(opponent)\(date) · \(store.lineup.innings.count) innings")
            .font(.system(size: 14))
            .foregroundColor(.secondary)
            .lineLimit(1)
    }

    /// Text tabs rather than a segmented control: a text control stays in the
    /// horizontal bar on this display, and sits in the right half by the fold.
    private var tabStrip: some View {
        HStack(spacing: 0) {
            ForEach(DetailTab.allCases, id: \.self) { tab in
                let isSelected = selectedTab == tab
                Button {
                    selectedTab = tab
                    Analytics.signal("duo.detail.tab.changed", parameters: ["tab": tab.rawValue])
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                        .foregroundColor(isSelected ? .primary : .secondary)
                        .padding(.horizontal, 12)
                        .frame(maxHeight: .infinity)
                        .overlay(alignment: .bottom) {
                            if isSelected {
                                Rectangle()
                                    .fill(Color.blue)
                                    .frame(height: 2)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 4)
    }

    /// Cmd+1…4, as on the iPad. Hidden; present only for the keyboard.
    private var shortcutButtons: some View {
        Group {
            Button("") { selectedTab = .players }.keyboardShortcut("1", modifiers: .command)
            Button("") { selectedTab = .lineup }.keyboardShortcut("2", modifiers: .command)
            Button("") { selectedTab = .positions }.keyboardShortcut("3", modifiers: .command)
            Button("") { selectedTab = .history }.keyboardShortcut("4", modifiers: .command)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    // MARK: Halves

    private var gutterWidth: CGFloat { fold.isActive ? fold.gutter : 1 }

    /// A soft gutter while the device is folded; a hairline when it's flat.
    /// Either way the halves stay where they are.
    @ViewBuilder
    private var gutter: some View {
        if fold.isActive {
            LinearGradient(
                colors: [
                    Color(red: 233 / 255, green: 233 / 255, blue: 238 / 255),
                    Color(red: 217 / 255, green: 217 / 255, blue: 223 / 255),
                    Color(red: 233 / 255, green: 233 / 255, blue: 238 / 255)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: fold.gutter)
        } else {
            Rectangle()
                .fill(Color(.separator))
                .frame(width: 1)
        }
    }

    @ViewBuilder
    private var leftContent: some View {
        switch selectedTab {
        case .players:
            DuoPlayersColumn(selectedPlayerID: $selectedPlayerID)
        case .lineup:
            DuoBattingOrderColumn()
        case .positions:
            switch positions.mode {
            case .inning:   DuoRosterColumn(showFairPlay: fairPlayVisible)
            case .position: DuoFocusedPositionColumn()
            case .pitching: DuoPitcherColumn()
            }
        case .history:
            // History has no design of its own yet. The roster stays on the
            // left, as it does on the iPad, without the fair-play summary.
            DuoRosterColumn(showFairPlay: false)
        }
    }

    @ViewBuilder
    private var rightContent: some View {
        switch selectedTab {
        case .players:
            DuoPlayerDetail(playerID: selectedPlayerID)
        case .lineup:
            DuoScheduleColumn(
                showingScheduleImport: $showingScheduleImport,
                pdfRequest: $pdfRequest
            )
        case .positions, .history:
            DetailPaneView(
                selectedTab: $selectedTab,
                showingAutoFillPopover: $showingPositionAutoFill,
                showingArchive: $showingArchive,
                duo: true
            )
        }
    }

    // MARK: Toolbar (icon actions → the system's vertical bar)

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            // Export — Cmd+P. Deliberately NOT gated on read-only: a view-only
            // assistant printing the Coaches Guide for the dugout is the case
            // the free unlock exists for. See LineupPDFExport.
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
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .keyboardShortcut("p", modifiers: .command)

            // Import schedule and Archive both write to the team, so both are
            // hidden for a view-only assistant, exactly as on the iPad.
            if !isReadOnly {
                Button {
                    showingScheduleImport = true
                    Analytics.signal("schedule.import.tapped")
                } label: {
                    Label("Import Schedule", systemImage: "calendar.badge.plus")
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])

                Button {
                    showingArchive = true
                } label: {
                    Label("Archive Game", systemImage: "archivebox")
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
            }

            Button {
                showingSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape.fill")
            }
            .tourTip(TourInSettingsTip(), arrowEdge: .top,
                     enabled: Tour.players.currentTip == nil)

            Button {
                showingTips = true
            } label: {
                Label("Tips", systemImage: "info.circle")
            }

            DuoFairPlayToggle(isOn: $fairPlayVisible)
        }
    }

    // MARK: Routes

    // Deep links, Spotlight results and App Intents land here the same way they
    // do on the iPad: called from onAppear *and* onChange, because a link that
    // cold-launches the app fires before this view exists. The nonce keeps it
    // idempotent so a re-appearance doesn't yank the coach off the tab they
    // chose by hand.
    private func consumePendingRoute() {
        guard let request = router.request,
              request.nonce != lastHandledRouteNonce else { return }
        guard lastHandledRouteNonce != nil || request.isFresh else { return }
        lastHandledRouteNonce = request.nonce
        selectedTab = DetailTab(request.route.tab)
    }
}

// MARK: - Fair Play Toggle

/// The side bar's Fair play control. Its icon is the roster's status at a
/// glance (green shield when clear, orange triangle with a count when not),
/// and tapping it shows or hides the fair-play detail on the Positions roster.
private struct DuoFairPlayToggle: View {
    @Binding var isOn: Bool
    @EnvironmentObject var store: LineupStore

    var body: some View {
        let summary = DuoFairPlaySummary(store: store)
        let hasIssues = summary.hasAnyAssignments && summary.issueCount > 0

        Button {
            withAnimation(.easeInOut(duration: 0.2)) { isOn.toggle() }
        } label: {
            Label {
                Text("Fair play")
            } icon: {
                Image(systemName: hasIssues ? "exclamationmark.triangle.fill" : "checkmark.shield.fill")
                    .font(.system(size: 22))
                    .foregroundColor(hasIssues ? .orange : .green)
                    .overlay(alignment: .topTrailing) {
                        if hasIssues {
                            Text("\(summary.issueCount)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 4)
                                .frame(minWidth: 16, minHeight: 16)
                                .background(Capsule().fill(Color.orange))
                                .offset(x: 8, y: -6)
                        }
                    }
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isOn ? Color.blue.opacity(0.1) : Color.clear)
            )
        }
        .accessibilityLabel("Fair play")
        .accessibilityValue(isOn ? "Shown" : "Hidden")
    }
}
