import SwiftUI

struct LineupView: View {
    @EnvironmentObject var store: LineupStore
    @EnvironmentObject var purchaseManager: PurchaseManager
    @Environment(\.verticalSizeClass) var verticalSizeClass
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @AppStorage("hasCompletedChecklist") private var hasCompletedChecklist = false
    @AppStorage("hasSeenPDFExportTip") private var hasSeenPDFExportTip = false
    @Binding var showingArchive: Bool
    // Tip overlays driven by parent iPhoneTabView
    @Binding var showingDragTip: Bool
    @Binding var showingArchiveTip: Bool
    @State private var generatedPDF: PDFDocument? = nil
    @State private var showingPDFExportTip = false
    @State private var showingTips = false
    @State private var showingPaywall = false
    @State private var lockedPDF: PDFDocument? = nil
    @State private var showingScheduleImport = false
    @State private var showingSchedulePicker = false
    @State private var scheduleImportToast: String? = nil

    var orderedPlayers: [Player] {
        store.lineup.orderedPlayers(from: store.players)
    }

    var unorderedPlayers: [Player] {
        store.lineup.activePlayers(from: store.players)
            .filter { !store.lineup.battingOrder.contains($0.id) }
    }

    var absentPlayers: [Player] {
        store.players.filter { store.lineup.isAbsent($0) }
    }

    var body: some View {
        if horizontalSizeClass == .regular {
            formContent
        } else {
            NavigationStack { formContent }
        }
    }

    private var formContent: some View {
        Form {
            // MARK: - First Game Checklist
            // Shown until the coach completes all 4 steps or manually dismisses.
            // Rendered as a card inside a clear-background section so it sits
            // flush at the top without cell chrome.
            if !hasCompletedChecklist {
                Section {
                    FirstGameChecklist()
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }

            // MARK: - Game Info
            Section {
                // Pick from schedule — shown only when a schedule has been imported
                if !store.scheduledGames.isEmpty {
                    Button {
                        showingSchedulePicker = true
                    } label: {
                        HStack {
                            Label("Pick from Schedule", systemImage: "calendar")
                                .foregroundColor(.blue)
                            Spacer()
                            let startOfToday = Calendar.current.startOfDay(for: Date())
                            let upcoming = store.scheduledGames.filter { game in
                                !game.isCancelled
                                && game.date >= startOfToday
                                && !ICalParser.isPractice(game.rawSummary)
                            }.count
                            Text("\(upcoming) game\(upcoming == 1 ? "" : "s")")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                                .foregroundColor(Color(.tertiaryLabel))
                        }
                    }
                }
                DatePicker("Game Date", selection: Binding(
                    get: { store.lineup.gameDate },
                    set: { store.updateGameDate($0) }
                ), displayedComponents: .date)
                HStack {
                    Text("Opponent")
                    Spacer()
                    TextField("Opponent Name", text: Binding(
                        get: { store.lineup.opponent },
                        set: { store.updateOpponent($0) }
                    ))
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
                }

                // Read-only status indicator — changes are made on the Positions tab
                HStack {
                    Text("Status")
                        .foregroundColor(.primary)
                    Spacer()
                    if store.lineup.status == .finalized {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.subheadline)
                                .foregroundColor(.green)
                            Text("Finalized")
                                .font(.subheadline)
                                .foregroundColor(.green)
                        }
                    } else {
                        Text("Draft")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("Game Info")
            } footer: {
                if store.lineup.status == .draft {
                    Text("Finalize your lineup from the Positions tab when it's ready.")
                        .foregroundColor(.secondary)
                }
            }

            // MARK: - PDF Export Context Tip
            // Shown once to free users who have 3+ players in the batting order.
            // Surfaces PDF export as the key Pro value prop at the moment the
            // coach has real lineup data worth exporting.
            if showingPDFExportTip {
                Section {
                    PDFExportContextTip(isPresented: Binding(
                        get: { showingPDFExportTip },
                        set: { newValue in
                            showingPDFExportTip = newValue
                            if !newValue { hasSeenPDFExportTip = true }
                        }
                    ))
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }

            // MARK: - Batting Order & Availability
            Section {
                ForEach(Array(orderedPlayers.enumerated()), id: \.element.id) { index, player in
                    RosterRow(player: player, index: index + 1)
                }
                .onMove { from, to in
                    store.moveBattingOrder(from: from, to: to)
                }

                ForEach(unorderedPlayers) { player in
                    RosterRow(player: player, index: nil, onAdd: {
                        store.addToBattingOrder(player: player)
                    })
                }

                ForEach(absentPlayers) { player in
                    RosterRow(player: player, index: nil, isAbsent: true)
                }

                // Empty state — no players at all
                if store.players.isEmpty {
                    HStack {
                        Spacer()
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
                        .padding(.vertical, 20)
                        Spacer()
                    }
                }
            } header: {
                HStack {
                    Text("Batting Order & Availability")
                    Spacer()
                    if !orderedPlayers.isEmpty {
                        EditButton()
                            .font(.caption)
                    }
                }
            } footer: {
                if !unorderedPlayers.isEmpty {
                    Text("Tap + to add players to the batting order, then drag to reorder.")
                } else if !store.players.isEmpty && orderedPlayers.isEmpty {
                    Text("Tap + next to each player above to add them to the batting order.")
                }
            }

            // MARK: - Fair Play Rules
            complianceSection

            // MARK: - Exports
            Section {
                Button {
                    let doc = PDFGenerator.generate(
                        type: .battingOrder,
                        lineup: store.lineup,
                        players: store.players,
                        teamName: store.teamName,
                        teamColor: store.teamColor
                    )
                    generatedPDF = doc
                    Analytics.signal("pdf.exported", parameters: ["type": "battingOrder"])
                } label: {
                    Label("Export Batting Order PDF", systemImage: "doc.text")
                }

                Button {
                    let doc = PDFGenerator.generate(
                        type: .coachesGuide,
                        lineup: store.lineup,
                        players: store.players,
                        teamName: store.teamName,
                        teamColor: store.teamColor,
                        gameLogs: store.gameLogs,
                        pitchingConfig: store.pitchingConfig
                    )
                    if purchaseManager.isPro {
                        generatedPDF = doc
                        Analytics.signal("pdf.exported", parameters: ["type": "coachesGuide"])
                    } else {
                        lockedPDF = doc
                    }
                } label: {
                    HStack {
                        Label("Export Coaches Guide PDF", systemImage: "doc.richtext")
                        Spacer()
                        if !purchaseManager.isPro {
                            ProBadge()
                        }
                    }
                }
            }
        }
        .sheet(item: $generatedPDF) { pdf in
            PDFPreviewView(document: pdf)
        }
        .sheet(item: $lockedPDF) { pdf in
            LockedPDFPreviewView(document: pdf)
                .environmentObject(purchaseManager)
        }
        .onChange(of: purchaseManager.isPro) { _, isPro in
            if isPro, let pdf = lockedPDF {
                lockedPDF = nil
                generatedPDF = pdf
            }
        }
        .sheet(isPresented: $showingTips) {
            PageTipsView(page: .lineup)
        }
        .onAppear {
            // Show PDF export tip once to free users who have 3+ players
            // in the batting order — they have real data worth exporting.
            if !hasSeenPDFExportTip && !purchaseManager.isPro {
                if orderedPlayers.count >= 3 {
                    withAnimation(.easeIn(duration: 0.3)) {
                        showingPDFExportTip = true
                    }
                }
            }
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView(source: "pdf_export")
                .environmentObject(purchaseManager)
        }
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
                // Clear toast after 3 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    scheduleImportToast = nil
                }
            }
            .environmentObject(store)
        }
        .sheet(isPresented: $showingSchedulePicker) {
            SchedulePickerView { game in
                store.applyScheduledGame(game)
            }
            .environmentObject(store)
        }
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
        .navigationTitle("Lineup Builder")
        .navigationBarTitleDisplayMode(verticalSizeClass == .compact ? .inline : .large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    Button { showingTips = true } label: {
                        Image(systemName: "info.circle")
                    }
                    Button {
                        showingScheduleImport = true
                        Analytics.signal("schedule.import.tapped")
                    } label: {
                        Image(systemName: "calendar.badge.plus")
                    }
                    Button { showingArchive = true } label: {
                        Label("Archive Game", systemImage: "archivebox")
                    }
                }
            }
        }
        // Drag-to-reorder tip — fires on first Lineup tab visit
        .overlay {
            if showingDragTip {
                TabFirstTipOverlay(
                    config: TabTipConfig(
                        tabName: "Lineup",
                        title: "Drag to set your batting order",
                        body: "Tap Edit in the section header, then press and hold the lines on the right side of any row and drag up or down.",
                        accentColor: .green,
                        targetRect: CGRect(x: 340, y: 390, width: 36, height: 36),
                        targetCornerRadius: 8,
                        arrowDirection: .up
                    ),
                    onDismiss: {
                        withAnimation(.easeOut(duration: 0.2)) {
                            showingDragTip = false
                            UserDefaults.standard.set(true, forKey: "hasSeenLineupDragTip")
                        }
                    }
                )
                .ignoresSafeArea()
                .zIndex(100)
                .transition(.opacity)
            }
        }
        // Archive tip — fires on the visit after the drag tip is dismissed
        .overlay {
            if showingArchiveTip {
                TabFirstTipOverlay(
                    config: TabTipConfig(
                        tabName: "Lineup",
                        title: "Archive the game when it ends",
                        body: "Tap the archive icon to save the game to History. Positions clear for next week, your batting order is kept, and season stats only count archived games.",
                        accentColor: .teal,
                        targetRect: CGRect(x: 340, y: 56, width: 36, height: 36),
                        targetCornerRadius: 8,
                        arrowDirection: .down
                    ),
                    onDismiss: {
                        withAnimation(.easeOut(duration: 0.2)) {
                            showingArchiveTip = false
                            UserDefaults.standard.set(true, forKey: "hasSeenArchiveTip")
                        }
                    }
                )
                .ignoresSafeArea()
                .zIndex(100)
                .transition(.opacity)
            }
        }
    }

    // MARK: - Fair Play Rules Section

    @ViewBuilder
    var complianceSection: some View {
        let config = store.fairPlayConfig
        let activePlayers = store.lineup.activePlayers(from: store.players)
        let noInfield = config.minimumInfieldInnings > 0
            ? store.lineup.playersWithoutInfield(players: activePlayers) : []
        let noOutfield = config.minimumOutfieldInnings > 0
            ? store.lineup.playersWithoutOutfield(players: activePlayers) : []
        let underMinimum = config.minimumFieldingInnings > 0
            ? store.lineup.playersUnderFieldingMinimum(players: activePlayers, minimumInnings: config.minimumFieldingInnings) : []
        let backToBack = config.noConsecutiveBench
            ? store.lineup.playersWithBackToBackBench(from: store.players) : []
        let catcherToPitcher = store.lineup.playersViolatingCatcherToPitcher(
            players: activePlayers, threshold: config.catcherToPitcherThreshold)
        let pitcherToCatcher = store.lineup.playersViolatingPitcherToCatcher(
            players: activePlayers, threshold: config.pitcherToCatcherThreshold)

        let hasWarnings = !noInfield.isEmpty || !noOutfield.isEmpty || !underMinimum.isEmpty
            || !backToBack.isEmpty || !catcherToPitcher.isEmpty || !pitcherToCatcher.isEmpty

        if hasWarnings {
            Section(header: ComplianceRulesHeader(title: "Fair Play Warnings")) {
                if !noInfield.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Missing Infield Inning", systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline.bold())
                            .foregroundColor(.orange)
                        ForEach(noInfield) { player in
                            Text("• \(player.displayName)")
                                .font(.callout)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                if !noOutfield.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Missing Outfield Inning", systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline.bold())
                            .foregroundColor(.orange)
                        ForEach(noOutfield) { player in
                            Text("• \(player.displayName)")
                                .font(.callout)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                if !underMinimum.isEmpty {
                    let min = config.minimumFieldingInnings
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Under \(min) Inning\(min == 1 ? "" : "s") Fielded", systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline.bold())
                            .foregroundColor(.orange)
                        ForEach(underMinimum) { player in
                            Text("• \(player.displayName)")
                                .font(.callout)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                if !backToBack.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Back-to-Back Bench", systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline.bold())
                            .foregroundColor(.red)
                        ForEach(backToBack) { player in
                            Text("• \(player.displayName)")
                                .font(.callout)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                if !catcherToPitcher.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Catcher to Pitcher Violation", systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline.bold())
                            .foregroundColor(.red)
                        ForEach(catcherToPitcher) { player in
                            Text("• \(player.displayName)")
                                .font(.callout)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                if !pitcherToCatcher.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Pitcher to Catcher Violation", systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline.bold())
                            .foregroundColor(.red)
                        ForEach(pitcherToCatcher) { player in
                            Text("• \(player.displayName)")
                                .font(.callout)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        } else if !activePlayers.isEmpty && store.lineup.innings.contains(where: { !$0.assignments.isEmpty }) {
            Section(header: ComplianceRulesHeader(title: "Fair Play Rules")) {
                Label("All active players meet fair play requirements", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.subheadline)
            }
        }
    }
}

// MARK: - Roster Row

struct RosterRow: View {
    @EnvironmentObject var store: LineupStore
    let player: Player
    let index: Int?
    var isAbsent: Bool = false
    var onAdd: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let i = index {
                    Text("\(i).")
                        .font(.headline)
                        .foregroundColor(isAbsent ? .secondary : .primary)
                } else if !isAbsent {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.green)
                        .font(.title3)
                        .onTapGesture { onAdd?() }
                } else {
                    Image(systemName: "minus.circle")
                        .foregroundColor(.secondary)
                        .font(.title3)
                }
            }
            .frame(width: 32, alignment: .leading)

            Text(player.displayName)
                .foregroundColor(isAbsent ? .secondary : .primary)
                .strikethrough(isAbsent)

            Spacer()

            if !player.number.isEmpty {
                Text("#\(player.number)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Toggle("", isOn: Binding(
                get: { !store.lineup.isAbsent(player) },
                set: { _ in store.toggleAbsent(player: player) }
            ))
            .labelsHidden()
            .tint(.green)
        }
        .opacity(isAbsent ? 0.5 : 1.0)
    }
}

// MARK: - Shared Fair Play Rules Tooltip

struct ComplianceRulesHeader: View {
    let title: String
    @State private var showingInfo = false

    var body: some View {
        HStack {
            Text(title)
            Button {
                showingInfo = true
            } label: {
                Image(systemName: "info.circle")
                    .foregroundColor(.blue)
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .alert("Lineup Rules", isPresented: $showingInfo) {
            Button("Got it", role: .cancel) {}
        } message: {
            Text("""
Every player must play at least 1 inning in the infield (P, C, 1B, 2B, 3B, SS).

Every player must play at least 1 inning in the outfield (LF, CF, RF).

No player should sit the bench for 2 consecutive innings.

Every player must field for at least 4 innings across the game. Players with any ABS innings are exempt from this rule.

Assign ABS to innings when a player arrives late or leaves early — they still need 1 infield and 1 outfield inning among the innings they do play.
""")
        }
    }
}

// MARK: - Pro Badge

struct ProBadge: View {
    var body: some View {
        Text("PRO")
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.blue)
            .cornerRadius(5)
    }
}
