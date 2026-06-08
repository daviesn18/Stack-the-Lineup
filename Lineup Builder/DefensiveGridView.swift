import SwiftUI
import StoreKit

struct DefensiveGridView: View {
    @EnvironmentObject var store: LineupStore
    @EnvironmentObject var purchaseManager: PurchaseManager
    @Environment(\.verticalSizeClass) var verticalSizeClass
    @State private var selectedInning: Int = 0
    @State private var selectedPlayer: Player? = nil
    @State private var showingWarnings = false
    @State private var showingSummary = false
    @Binding var showingArchive: Bool
    @Binding var selectedTab: Int          // passed in from ContentView to navigate to Players tab
    @State private var showingTips = false
    @State private var showingPaywall = false

    // Auto-Fill state
    @State private var showingAutoFillPopover = false
    @State private var undoSnapshot: [InningAssignment]? = nil
    @State private var undoMessage: String = ""
    @State private var showingUndo = false
    @State private var showingAutoFillIncomplete = false
    @State private var autoFillIncompleteMessage: String = ""

    // Clear positions state
    @State private var showingClearPopover = false     // inning view: anchored popover
    @State private var showingClearAllConfirm = false  // confirm alert for clearing all innings

    // One-time Auto-Fill context tip — shown the first time a Pro user opens
    // the Positions tab with at least one player in the roster.
    @AppStorage("hasSeenAutoFillTip") private var hasSeenAutoFillTip = false
    @State private var showingAutoFillTip = false

    // Tip overlay driven by parent iPhoneTabView
    @Binding var showingTabTip: Bool

    private var isReadOnly: Bool { store.activeTeam.isReadOnly }

    enum FillScope {
        case thisInning
        case through(Int)
    }

    var smartDefaultLastInning: Int {
        let lastFilled = (0..<store.lineup.innings.count).reversed().first {
            !store.lineup.innings[$0].assignments.isEmpty
        }
        // Fallback to second-to-last inning index (inning 6 in a 7-inning game) —
        // typical rec games go the full distance, so defaulting to "fill through inning 6"
        // is a safe starting point that the coach can adjust upward in the popover.
        return lastFilled ?? max(0, store.lineup.innings.count - 2)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    if isReadOnly { ReadOnlyBanner() }

                    if showingSummary {
                        LineupStatusStrip(
                            status: store.lineup.status,
                            isReadOnly: isReadOnly,
                            lastFinalizedBy: store.lineup.lastFinalizedBy,
                            lastFinalizedAt: store.lineup.lastFinalizedAt,
                            onFinalize: { store.finalizeLineup() },
                            onReopen: { store.reopenLineup() }
                        )

                        PositionSummaryView(
                            onAutoFill: {
                                if purchaseManager.isPro {
                                    showingAutoFillPopover = true
                                } else {
                                    showingPaywall = true
                                }
                            },
                            showingAutoFillPopover: $showingAutoFillPopover,
                            onFillThrough: { lastInning in
                                showingAutoFillPopover = false
                                runAutoFill(scope: .through(lastInning))
                            },
                            smartDefaultLastInning: smartDefaultLastInning
                        )

                        // Summary view — clear all only, straight to confirm alert
                        if !isReadOnly { clearPositionsButton(isSummary: true) }

                    } else {
                        if verticalSizeClass == .compact {
                            // ── Landscape layout ──────────────────────────────
                            LineupStatusStrip(
                                status: store.lineup.status,
                                isReadOnly: isReadOnly,
                                lastFinalizedBy: store.lineup.lastFinalizedBy,
                                lastFinalizedAt: store.lineup.lastFinalizedAt,
                                onFinalize: { store.finalizeLineup() },
                                onReopen: { store.reopenLineup() }
                            )

                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("Inning \(selectedInning + 1)")
                                    .font(.title2.bold())
                                if !isReadOnly { boltButton }
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 6)
                            .padding(.bottom, 4)

                            HStack(spacing: 0) {
                                ScrollView(.vertical, showsIndicators: false) {
                                    VStack(spacing: 6) {
                                        ForEach(0..<store.lineup.innings.count, id: \.self) { inning in
                                            Button {
                                                selectedInning = inning
                                                showingUndo = false
                                            } label: {
                                                VStack(spacing: 2) {
                                                    Text("\(inning + 1)")
                                                        .font(.caption.bold())
                                                    inningStatusDot(inning: inning)
                                                }
                                                .frame(width: 44)
                                                .padding(.vertical, 8)
                                                .background(selectedInning == inning ? Color.blue : Color(.systemGray5))
                                                .foregroundColor(selectedInning == inning ? .white : .primary)
                                                .cornerRadius(10)
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                }
                                .frame(width: 60)

                                Divider()

                                if store.players.isEmpty {
                                    ContentUnavailableView(
                                        "No Players",
                                        systemImage: "person.badge.plus",
                                        description: Text("Add players on the Players tab first.")
                                    )
                                } else {
                                    VStack(spacing: 0) {
                                        List {
                                            ForEach(displayPlayers) { player in
                                                PlayerInningRow(
                                                    player: player,
                                                    inning: selectedInning,
                                                    onTap: isReadOnly ? {} : {
                                                        selectedPlayer = player
                                                        showingUndo = false
                                                    }
                                                )
                                            }
                                        }
                                        .listStyle(.plain)

                                        // Inning view — popover with two scope options
                                        if !isReadOnly { clearPositionsButton(isSummary: false) }
                                    }
                                }
                            }

                        } else {
                            // ── Portrait layout ───────────────────────────────
                            LineupStatusStrip(
                                status: store.lineup.status,
                                isReadOnly: isReadOnly,
                                lastFinalizedBy: store.lineup.lastFinalizedBy,
                                lastFinalizedAt: store.lineup.lastFinalizedAt,
                                onFinalize: { store.finalizeLineup() },
                                onReopen: { store.reopenLineup() }
                            )

                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("Inning \(selectedInning + 1) Positions")
                                    .font(.largeTitle.bold())
                                if !isReadOnly { boltButton }
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            .padding(.bottom, 4)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(0..<store.lineup.innings.count, id: \.self) { inning in
                                        Button {
                                            selectedInning = inning
                                            showingUndo = false
                                        } label: {
                                            VStack(spacing: 2) {
                                                Text("Inn \(inning + 1)")
                                                    .font(.callout.bold())
                                                inningStatusDot(inning: inning)
                                            }
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 8)
                                            .background(selectedInning == inning ? Color.blue : Color(.systemGray5))
                                            .foregroundColor(selectedInning == inning ? .white : .primary)
                                            .cornerRadius(10)
                                        }
                                    }
                                }
                                .padding()
                            }

                            Divider()

                            if store.players.isEmpty {
                                ContentUnavailableView(
                                    "No Players",
                                    systemImage: "person.badge.plus",
                                    description: Text("Add players on the Players tab first.")
                                )
                            } else {
                                List {
                                    ForEach(displayPlayers) { player in
                                        PlayerInningRow(
                                            player: player,
                                            inning: selectedInning,
                                            onTap: isReadOnly ? {} : {
                                                selectedPlayer = player
                                                showingUndo = false
                                            }
                                        )
                                    }
                                }
                                .listStyle(.plain)

                                // Inning view — popover with two scope options
                                if !isReadOnly { clearPositionsButton(isSummary: false) }
                            }
                        }
                    }
                }

                // Undo banner
                if showingUndo {
                    HStack {
                        Text(undoMessage)
                            .font(.subheadline)
                            .foregroundColor(.white)
                        Spacer()
                        Button("Undo") {
                            if let snapshot = undoSnapshot {
                                store.activeTeam.lineup.innings = snapshot
                                store.save()
                            }
                            withAnimation { showingUndo = false }
                            undoSnapshot = nil
                        }
                        .font(.subheadline.bold())
                        .foregroundColor(.yellow)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(.systemGray2).opacity(0.95))
                    .cornerRadius(12)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        withAnimation {
                            showingSummary.toggle()
                            showingUndo = false
                            showingAutoFillPopover = false
                        }
                    } label: {
                        Label(
                            showingSummary ? "By Inning" : "Summary",
                            systemImage: showingSummary ? "list.bullet" : "tablecells"
                        )
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 4) {
                        Button {
                            showingWarnings = true
                        } label: {
                            warningsToolbarLabel
                        }
                        if !isReadOnly {
                            Button {
                                showingArchive = true
                            } label: {
                                Label("Archive Game", systemImage: "archivebox")
                            }
                        }
                        Button {
                            showingTips = true
                        } label: {
                            Image(systemName: "info.circle")
                        }
                    }
                }
            }
            .sheet(item: $selectedPlayer) { player in
                PositionPickerView(player: player, inning: selectedInning)
            }
            .sheet(isPresented: $showingWarnings) {
                WarningsView(inning: selectedInning)
            }
            .sheet(isPresented: $showingTips) {
                PageTipsView(page: .positions)
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView(source: "autofill")
                    .environmentObject(purchaseManager)
            }
            // Confirmation alert for clearing all innings — used by both
            // the summary view path and the "Clear all innings" branch in the popover
            .alert("Clear all positions?", isPresented: $showingClearAllConfirm) {
                Button("Clear", role: .destructive) {
                    store.clearPositions()
                    withAnimation { showingUndo = false }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("All inning assignments will be removed. This can't be undone.")
            }
            // Shown when auto-fill completes but could not fill one or more positions.
            .alert("Some Positions Not Filled", isPresented: $showingAutoFillIncomplete) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(autoFillIncompleteMessage)
            }
            .onAppear {
                // Show the Auto-Fill context tip once — only to Pro users who
                // have at least one player, and haven't seen it before.
                if purchaseManager.isPro && !hasSeenAutoFillTip && !store.players.isEmpty {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        withAnimation(.easeOut(duration: 0.25)) {
                            showingAutoFillTip = true
                            hasSeenAutoFillTip = true
                        }
                    }
                }
            }
            // Auto-Fill context tip — floats above content, dismisses itself
            .overlay(alignment: .top) {
                if showingAutoFillTip {
                    AutoFillContextTip(isPresented: $showingAutoFillTip) {
                        // Navigate to Players tab (tag 0)
                        selectedTab = 0
                    }
                    .padding(.top, 8)
                    .zIndex(10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .animation(.easeOut(duration: 0.25), value: showingAutoFillTip)
                }
            }
            // Positions tab first-visit tip — full-screen dim overlay
            .overlay {
                if showingTabTip {
                    TabFirstTipOverlay(
                        config: TabTipConfig(
                            tabName: "Positions",
                            title: "Tap the bolt to auto-fill",
                            body: "The app fills open spots while checking every fair play rule. Set position preferences on the Players tab first for the best results.",
                            accentColor: .orange,
                            targetRect: CGRect(x: 160, y: 56, width: 36, height: 36),
                            targetCornerRadius: 8,
                            arrowDirection: .down
                        ),
                        onDismiss: {
                            withAnimation(.easeOut(duration: 0.2)) {
                                showingTabTip = false
                                UserDefaults.standard.set(true, forKey: "hasSeenPositionsTabTip")
                            }
                        }
                    )
                    .ignoresSafeArea()
                    .zIndex(100)
                    .transition(.opacity)
                }
            }
        }
    }

    // MARK: - Clear Positions Button

    @ViewBuilder
    func clearPositionsButton(isSummary: Bool) -> some View {
        let hasAnyAssignments = store.lineup.innings.contains { !$0.assignments.isEmpty }
        if hasAnyAssignments {
            HStack {
                Spacer()
                Button {
                    if isSummary {
                        showingClearAllConfirm = true
                    } else {
                        showingClearPopover = true
                    }
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
                // Popover anchors to the button — only shown for inning view
                .popover(isPresented: $showingClearPopover, arrowEdge: .bottom) {
                    VStack(spacing: 0) {
                        Button(role: .destructive) {
                            showingClearPopover = false
                            store.activeTeam.lineup.innings[selectedInning] = InningAssignment()
                            store.save()
                            withAnimation { showingUndo = false }
                        } label: {
                            Text("Clear Inning \(selectedInning + 1) only")
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 14)
                        }
                        Divider()
                        Button(role: .destructive) {
                            showingClearPopover = false
                            showingClearAllConfirm = true
                        } label: {
                            Text("Clear all innings")
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 14)
                        }
                    }
                    .frame(minWidth: 220)
                    .presentationCompactAdaptation(.popover)
                }
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

    // MARK: - Auto-Fill Logic

    func runAutoFill(scope: FillScope) {
        let snapshot = store.activeTeam.lineup.innings

        let preferences = Dictionary(
            uniqueKeysWithValues: store.players.map { ($0.id, $0.positionPreferences) }
        )

        let result: AutoFillResult
        switch scope {
        case .thisInning:
            result = AutoFillEngine.fillInning(
                selectedInning,
                in: store.activeTeam.lineup,
                players: store.players,
                preferences: preferences,
                config: store.fairPlayConfig,
                pitchingConfig: store.pitchingConfig,
                gameLogs: store.gameLogs
            )
        case .through(let lastInning):
            result = AutoFillEngine.fillInnings(
                through: lastInning,
                in: store.activeTeam.lineup,
                players: store.players,
                preferences: preferences,
                config: store.fairPlayConfig,
                pitchingConfig: store.pitchingConfig,
                gameLogs: store.gameLogs
            )
        }

        if result.filledCount > 0 {
            store.activeTeam.lineup = result.lineup
            store.save()

            undoSnapshot = snapshot
            let scopeLabel: String
            switch scope {
            case .thisInning: scopeLabel = "inning \(selectedInning + 1)"
            case .through(let last): scopeLabel = "innings 1–\(last + 1)"
            }
            undoMessage = "Auto-filled \(result.filledCount) position\(result.filledCount == 1 ? "" : "s") (\(scopeLabel))"
            withAnimation { showingUndo = true }

            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                withAnimation { showingUndo = false }
            }
        }

        if result.hasUnfilledSlots {
            autoFillIncompleteMessage = buildAutoFillIncompleteMessage(from: result.unfilledSlots, scope: scope)
            // Small delay so the undo toast settles before the alert fires.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                showingAutoFillIncomplete = true
            }
        }

        Analytics.signal("autofill.used", parameters: [
            "mode": {
                if case .thisInning = scope { return "inning" }
                return "range"
            }(),
            "filledCount": "\(result.filledCount)",
            "unfilledCount": "\(result.unfilledSlots.count)"
        ])
    }

    /// Builds a coach-readable explanation of why specific positions could not
    /// be auto-filled. Groups slots by reason so related issues read together.
    private func buildAutoFillIncompleteMessage(
        from slots: [AutoFillUnfilledSlot],
        scope: FillScope
    ) -> String {
        let isMultiInning: Bool = {
            if case .through = scope { return true }
            return false
        }()

        // Format a list of positions (with inning numbers when multi-inning).
        func label(for group: [AutoFillUnfilledSlot]) -> String {
            if isMultiInning {
                // Group by position: "P (Innings 3, 4), CF (Inning 5)"
                var byPos: [FieldPosition: [Int]] = [:]
                for slot in group {
                    byPos[slot.position, default: []].append(slot.inningIndex + 1)
                }
                return byPos
                    .sorted { $0.key.rawValue < $1.key.rawValue }
                    .map { pos, innings in
                        let numbers = innings.map { "\($0)" }.joined(separator: ", ")
                        let qualifier = innings.count == 1 ? "Inning \(numbers)" : "Innings \(numbers)"
                        return "\(pos.rawValue) (\(qualifier))"
                    }
                    .joined(separator: ", ")
            } else {
                return group.map { $0.position.rawValue }.joined(separator: ", ")
            }
        }

        var parts: [String] = []

        let rosterSlots = slots.filter { $0.reason == .rosterTooSmall }
        if !rosterSlots.isEmpty {
            parts.append("""
\(label(for: rosterSlots)) could not be filled. Not enough active players to cover every field position. Mark additional players as active on the Lineup tab, or assign these slots manually.
""")
        }

        let reentrySlots = slots.filter { $0.reason == .pitcherReentry }
        if !reentrySlots.isEmpty {
            parts.append("""
\(label(for: reentrySlots)) could not be filled. All eligible pitchers have already left the mound this game and cannot re-enter. Assign pitcher manually.
""")
        }

        let capacitySlots = slots.filter { $0.reason == .pitchCapacityLimited }
        if !capacitySlots.isEmpty {
            parts.append("""
\(label(for: capacitySlots)) could not be filled. All eligible pitchers have reached their estimated pitch count limit for today. Assign pitcher manually or adjust pitch counts on the Players tab.
""")
        }

        let neverSlots = slots.filter { $0.reason == .neverPreferences }
        if !neverSlots.isEmpty {
            parts.append("""
\(label(for: neverSlots)) could not be filled. All remaining players have those positions set to Never in their preferences. Update preferences on the Players tab, or assign manually.
""")
        }

        return parts.joined(separator: "\n")
    }

    // MARK: - Warnings Button

    @ViewBuilder
    var warningsToolbarLabel: some View {
        let inningIssues = currentInningIssueCount
        let gameIssues = gameWideIssueCount

        if inningIssues > 0 && gameIssues > 0 {
            Label("Issues (\(inningIssues + gameIssues))", systemImage: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
        } else if inningIssues > 0 {
            Label("Inning Issues (\(inningIssues))", systemImage: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
        } else if gameIssues > 0 {
            Label("Game Issues (\(gameIssues))", systemImage: "exclamationmark.circle.fill")
                .foregroundColor(.orange)
        } else {
            Label("All Good", systemImage: "checkmark.shield.fill")
                .foregroundColor(.green)
        }
    }

    var currentInningIssueCount: Int {
        let activePlayers = store.lineup.activePlayers(from: store.players)
        let openPos = store.lineup.openPositions(inning: selectedInning, players: activePlayers, config: store.fairPlayConfig)
        let dupPos = store.lineup.duplicatePositionErrors(inning: selectedInning)
        return openPos.count + dupPos.count
    }

    var gameWideIssueCount: Int {
        let activePlayers = store.lineup.activePlayers(from: store.players)
        let config = store.fairPlayConfig
        var count = 0
        // Open positions across all innings (any inning that has at least one assignment
        // but is still missing one or more field positions)
        for inningIndex in 0..<store.lineup.innings.count {
            guard !store.lineup.innings[inningIndex].assignments.isEmpty else { continue }
            let open = store.lineup.openPositions(inning: inningIndex, players: activePlayers, config: config)
            count += open.count
        }
        if config.minimumInfieldInnings > 0 {
            count += store.lineup.playersWithoutInfield(players: activePlayers).count
        }
        if config.minimumOutfieldInnings > 0 {
            count += store.lineup.playersWithoutOutfield(players: activePlayers).count
        }
        if config.noConsecutiveBench {
            count += store.lineup.playersWithBackToBackBench(from: store.players).count
        }
        count += store.lineup.playersUnderFieldingMinimum(players: activePlayers, minimumInnings: config.minimumFieldingInnings).count
        count += store.lineup.playersViolatingCatcherToPitcher(players: activePlayers, threshold: config.catcherToPitcherThreshold).count
        count += store.lineup.playersViolatingPitcherToCatcher(players: activePlayers, threshold: config.pitcherToCatcherThreshold).count

        // Pitch eligibility violations: assigned pitchers who are on rest or unknown age
        if store.pitchingConfig.rulesEnabled {
            let assignedPitcherIDs = Set(
                store.lineup.innings.flatMap { inning in
                    inning.assignments.compactMap { (pid, pos) -> UUID? in pos == .pitcher ? pid : nil }
                }
            )
            for playerID in assignedPitcherIDs {
                guard let player = store.players.first(where: { $0.id == playerID }) else { continue }
                let status = PitchEligibilityEngine.status(
                    for: player,
                    gameLogs: store.gameLogs,
                    config: store.pitchingConfig,
                    referenceDate: store.lineup.gameDate
                )
                if status.blocksAssignment { count += 1 }
            }
        }

        return count
    }

    var allWarningCount: Int {
        return currentInningIssueCount + gameWideIssueCount
    }

    @ViewBuilder
    var boltButton: some View {
        Button {
            if purchaseManager.isPro {
                showingAutoFillPopover = true
            } else {
                showingPaywall = true
            }
        } label: {
            Image(systemName: "bolt.fill")
                .font(.title3)
                .foregroundColor(purchaseManager.isPro ? .blue : Color(.systemGray3))
        }
        .accessibilityLabel("Auto-Fill Positions")
        .popover(isPresented: $showingAutoFillPopover, arrowEdge: .top) {
            AutoFillPopover(
                isSummary: false,
                smartDefaultLastInning: smartDefaultLastInning,
                inningCount: store.lineup.innings.count
            ) { scope in
                showingAutoFillPopover = false
                runAutoFill(scope: scope)
            }
            .presentationCompactAdaptation(.popover)
        }
    }

    var displayPlayers: [Player] {
        store.lineup.displayPlayers(from: store.players)
    }

    @ViewBuilder
    func inningStatusDot(inning: Int) -> some View {
        let activePlayers = store.lineup.activePlayers(from: store.players)
        let openPos = store.lineup.openPositions(inning: inning, players: activePlayers, config: store.fairPlayConfig)
        let dupPos = store.lineup.duplicatePositionErrors(inning: inning)
        let hasAny = !store.lineup.innings[inning].assignments.isEmpty

        if !dupPos.isEmpty {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.red)
        } else if !openPos.isEmpty && hasAny {
            Image(systemName: "minus")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.orange)
        } else if openPos.isEmpty && hasAny {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.green)
        } else {
            Circle().fill(Color.gray.opacity(0.3)).frame(width: 6, height: 6)
        }
    }
}

// MARK: - Lineup Status Strip

struct LineupStatusStrip: View {
    let status: LineupStatus
    var isReadOnly: Bool = false
    var lastFinalizedBy: String? = nil
    var lastFinalizedAt: Date? = nil
    let onFinalize: () -> Void
    let onReopen: () -> Void

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    if status == .finalized {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption.bold())
                            .foregroundColor(.green)
                        Text("Finalized")
                            .font(.caption.bold())
                            .foregroundColor(.green)
                    } else {
                        Circle()
                            .fill(Color.secondary)
                            .frame(width: 7, height: 7)
                        Text("Draft")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                    }
                }

                // Attribution line — shown when finalized and a coach name is available
                if status == .finalized, let name = lastFinalizedBy, !name.isEmpty {
                    Text("by \(name)\(formattedDate)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if isReadOnly {
                HStack(spacing: 4) {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("View only")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                }
            } else if status == .finalized {
                Button("Reopen", action: onReopen)
                    .font(.caption.bold())
                    .foregroundColor(.blue)
            } else {
                Button(action: onFinalize) {
                    Text("Finalize lineup →")
                        .font(.caption.bold())
                        .foregroundColor(.blue)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(
            status == .finalized
                ? Color.green.opacity(0.10)
                : Color(.systemGray6)
        )
        .animation(.easeInOut(duration: 0.2), value: status)
    }

    private var formattedDate: String {
        guard let date = lastFinalizedAt else { return "" }
        let formatted = date.formatted(date: .abbreviated, time: .omitted)
        return " · \(formatted)"
    }
}

// MARK: - Auto-Fill Popover

struct AutoFillPopover: View {
    let isSummary: Bool
    let smartDefaultLastInning: Int
    let inningCount: Int
    let onSelect: (DefensiveGridView.FillScope) -> Void

    @State private var selectedLastInning: Int

    init(isSummary: Bool, smartDefaultLastInning: Int, inningCount: Int, onSelect: @escaping (DefensiveGridView.FillScope) -> Void) {
        self.isSummary = isSummary
        self.smartDefaultLastInning = smartDefaultLastInning
        self.inningCount = inningCount
        self.onSelect = onSelect
        self._selectedLastInning = State(initialValue: smartDefaultLastInning)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Auto-Fill Positions")
                    .font(.subheadline.bold())
                Text("Already-assigned positions won't be changed.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack(spacing: 4) {
                    Image(systemName: "star.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                    Text("Uses position preferences when set.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            if !isSummary {
                Button {
                    onSelect(.thisInning)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "1.circle.fill")
                            .foregroundColor(.blue)
                        Text("Fill This Inning")
                            .font(.body)
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                }

                Divider()
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: "7.circle.fill")
                        .foregroundColor(.blue)
                    Text("Fill Innings 1 – \(selectedLastInning + 1)")
                        .font(.body)
                    Spacer()
                }

                HStack(spacing: 6) {
                    ForEach(0..<inningCount, id: \.self) { i in
                        Button {
                            selectedLastInning = i
                        } label: {
                            Text("\(i + 1)")
                                .font(.caption.bold())
                                .frame(width: 28, height: 28)
                                .background(selectedLastInning == i ? Color.blue : Color(.systemGray5))
                                .foregroundColor(selectedLastInning == i ? .white : .primary)
                                .cornerRadius(6)
                        }
                    }
                }

                Button {
                    onSelect(.through(selectedLastInning))
                } label: {
                    Text("Fill")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
        }
        .frame(width: 280)
    }
}

// MARK: - Warnings Sheet

struct WarningsView: View {
    @EnvironmentObject var store: LineupStore
    @Environment(\.dismiss) var dismiss
    let inning: Int

    var body: some View {
        NavigationStack {
            List {
                let inningWarnings = computeInningWarnings()
                let overallWarnings = computeOverallWarnings()

                Section(header: ComplianceRulesHeader(title: "Inning \(inning + 1) Issues")) {
                    if inningWarnings.isEmpty {
                        Label("No issues for this inning.", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.callout)
                    } else {
                        ForEach(inningWarnings, id: \.self) { msg in
                            Label(msg, systemImage: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.callout)
                        }
                    }
                }

                let missingPositionWarnings = computeMissingPositionWarnings()
                Section(header: ComplianceRulesHeader(title: "Missing Positions")) {
                    if missingPositionWarnings.isEmpty {
                        Label("All innings have positions filled.", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.callout)
                    } else {
                        ForEach(missingPositionWarnings, id: \.self) { msg in
                            Label(msg, systemImage: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.callout)
                        }
                    }
                }

                Section(header: ComplianceRulesHeader(title: "Overall Lineup")) {
                    if overallWarnings.isEmpty {
                        Label("All players meet infield & outfield requirements.", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.callout)
                    } else {
                        ForEach(overallWarnings, id: \.self) { msg in
                            Label(msg, systemImage: "exclamationmark.circle.fill")
                                .foregroundColor(.red)
                                .font(.callout)
                        }
                    }
                }

                let pitchWarnings = computePitchEligibilityWarnings()
                if store.pitchingConfig.rulesEnabled {
                    Section(header: ComplianceRulesHeader(title: "Pitch Eligibility")) {
                        if pitchWarnings.isEmpty {
                            Label("All assigned pitchers are eligible.", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.callout)
                        } else {
                            ForEach(pitchWarnings, id: \.self) { msg in
                                Label(msg, systemImage: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                    .font(.callout)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Warnings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    func computeInningWarnings() -> [String] {
        var warnings: [String] = []
        let config = store.fairPlayConfig
        let activePlayers = store.lineup.activePlayers(from: store.players)
        let openPos = store.lineup.openPositions(inning: inning, players: activePlayers, config: config)
        let dupPos = store.lineup.duplicatePositionErrors(inning: inning)
        for pos in dupPos { warnings.append("Duplicate position: \(pos.displayName)") }
        for pos in openPos { warnings.append("Open position: \(pos.displayName)") }
        if config.noConsecutiveBench {
            for player in activePlayers {
                if store.lineup.innings[inning].position(for: player) == .bench {
                    let prevBench = inning > 0 && store.lineup.innings[inning - 1].position(for: player) == .bench
                    let nextBench = inning < store.lineup.innings.count - 1 && store.lineup.innings[inning + 1].position(for: player) == .bench
                    if prevBench {
                        warnings.append("\(player.displayName): back-to-back bench (inn \(inning) & \(inning + 1))")
                    } else if nextBench {
                        warnings.append("\(player.displayName): back-to-back bench (inn \(inning + 1) & \(inning + 2))")
                    }
                }
            }
        }
        return warnings
    }

    func computeMissingPositionWarnings() -> [String] {
        var warnings: [String] = []
        let activePlayers = store.lineup.activePlayers(from: store.players)
        let config = store.fairPlayConfig
        for i in 0..<store.lineup.innings.count {
            guard !store.lineup.innings[i].assignments.isEmpty else { continue }
            let open = store.lineup.openPositions(inning: i, players: activePlayers, config: config)
            guard !open.isEmpty else { continue }
            let posNames = open.map { $0.displayName }.joined(separator: ", ")
            warnings.append("Inning \(i + 1): \(posNames)")
        }
        return warnings
    }

    func computeOverallWarnings() -> [String] {
        var warnings: [String] = []
        let config = store.fairPlayConfig
        let active = store.lineup.activePlayers(from: store.players)
        if config.minimumInfieldInnings > 0 {
            for player in store.lineup.playersWithoutInfield(players: active) {
                warnings.append("\(player.displayName): no infield inning assigned")
            }
        }
        if config.minimumOutfieldInnings > 0 {
            for player in store.lineup.playersWithoutOutfield(players: active) {
                warnings.append("\(player.displayName): no outfield inning assigned")
            }
        }
        let minimum = config.minimumFieldingInnings
        if minimum > 0 {
            for player in store.lineup.playersUnderFieldingMinimum(players: active, minimumInnings: minimum) {
                warnings.append("\(player.displayName): under \(minimum) inning\(minimum == 1 ? "" : "s") fielded")
            }
        }
        let c2p = config.catcherToPitcherThreshold
        if c2p > 0 {
            for player in store.lineup.playersViolatingCatcherToPitcher(players: active, threshold: c2p) {
                warnings.append("\(player.displayName): caught \(c2p)+ innings and is pitching (C to P restriction)")
            }
        }
        let p2c = config.pitcherToCatcherThreshold
        if p2c > 0 {
            for player in store.lineup.playersViolatingPitcherToCatcher(players: active, threshold: p2c) {
                warnings.append("\(player.displayName): pitched \(p2c)+ innings and is catching (P to C restriction)")
            }
        }
        return warnings
    }

    func computePitchEligibilityWarnings() -> [String] {
        guard store.pitchingConfig.rulesEnabled else { return [] }

        // Find all players assigned as pitcher in any inning of this lineup
        let assignedPitcherIDs = Set(
            store.lineup.innings.flatMap { inning in
                inning.assignments.compactMap { (playerID, pos) -> UUID? in
                    pos == .pitcher ? playerID : nil
                }
            }
        )
        guard !assignedPitcherIDs.isEmpty else { return [] }

        var warnings: [String] = []
        for playerID in assignedPitcherIDs {
            guard let player = store.players.first(where: { $0.id == playerID }) else { continue }
            let status = PitchEligibilityEngine.status(
                for: player,
                gameLogs: store.gameLogs,
                config: store.pitchingConfig,
                referenceDate: store.lineup.gameDate
            )
            switch status {
            case .eligible:
                break
            case .limited(let remaining):
                warnings.append("\(player.displayName): limited to \(remaining) pitches today")
            case .mustRest(let date):
                let formatter = DateFormatter()
                formatter.dateFormat = "EEE M/d"
                warnings.append("\(player.displayName): available \(formatter.string(from: date))")
            case .unknownAge:
                warnings.append("\(player.displayName): league age not set, eligibility unknown")
            }
        }
        return warnings
    }
}

// MARK: - Player Row in Inning

struct PlayerInningRow: View {
    @EnvironmentObject var store: LineupStore
    @EnvironmentObject var purchaseManager: PurchaseManager
    let player: Player
    let inning: Int
    let onTap: () -> Void

    var currentPosition: FieldPosition? {
        store.lineup.innings[inning].position(for: player)
    }

    var isDuplicate: Bool {
        guard let pos = currentPosition, !pos.isBench, !pos.isAbsent else { return false }
        return store.lineup.innings[inning].assignments.values.filter { $0 == pos }.count > 1
    }

    var previousPositionsSummary: String? {
        guard inning > 0 else { return nil }
        let history = (0..<inning).compactMap { i -> String? in
            guard let pos = store.lineup.innings[i].position(for: player) else { return nil }
            return "Inn\(i + 1):\(pos.rawValue)"
        }
        return history.isEmpty ? nil : history.joined(separator: "  ·  ")
    }

    var hasConsecutiveBenchWarning: Bool {
        guard currentPosition == .bench else { return false }
        let prevBench = inning > 0 && store.lineup.innings[inning - 1].position(for: player) == .bench
        let nextBench = inning < store.lineup.innings.count - 1 && store.lineup.innings[inning + 1].position(for: player) == .bench
        return prevBench || nextBench
    }

    /// Non-nil when this player is assigned pitcher this inning, pitching rules
    /// are enabled, and the player is ineligible or their age is unknown.
    var pitchEligibilityWarning: PitchEligibilityStatus? {
        guard currentPosition == .pitcher,
              store.pitchingConfig.rulesEnabled else { return nil }
        let status = PitchEligibilityEngine.status(
            for: player,
            gameLogs: store.gameLogs,
            config: store.pitchingConfig,
            referenceDate: store.lineup.gameDate
        )
        return status.blocksAssignment ? status : nil
    }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center) {
                if !player.number.isEmpty {
                    Text("#\(player.number)")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                        .frame(width: 36, alignment: .leading)
                } else {
                    Text("—")
                        .font(.caption.bold())
                        .foregroundStyle(.tertiary)
                        .frame(width: 36, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(player.displayName)
                            .foregroundColor(.primary)
                        if hasConsecutiveBenchWarning {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                        if let pitchWarning = pitchEligibilityWarning {
                            Image(systemName: pitchWarning == .unknownAge ? "questionmark.circle.fill" : "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                    if let pitchWarning = pitchEligibilityWarning {
                        Text(pitchWarning.displayLabel)
                            .font(.caption2)
                            .foregroundColor(.red)
                    } else if let history = previousPositionsSummary {
                        Text(history)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if let pos = currentPosition {
                    positionBadge(pos)
                } else {
                    Text("—")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 5)
        }
        .listRowBackground(
            isDuplicate ? Color.red.opacity(0.08) :
            pitchEligibilityWarning != nil ? Color.red.opacity(0.06) : nil
        )
    }

    @ViewBuilder
    func positionBadge(_ pos: FieldPosition) -> some View {
        let prefTier: PositionPreferenceTier? = purchaseManager.isPro && !pos.isAbsent
            ? player.positionPreferences[pos]
            : nil
        let showBorder: Bool = prefTier == .emergency || prefTier == .never

        Text(pos.rawValue)
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(pos.badgeColor)
            .foregroundColor(.white)
            .cornerRadius(6)
            .overlay {
                if showBorder, let tier = prefTier {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(tier.color, lineWidth: 2)
                }
            }
    }
}

// MARK: - Position Picker Sheet

struct PositionPickerView: View {
    @EnvironmentObject var store: LineupStore
    @Environment(\.dismiss) var dismiss

    let player: Player
    let inning: Int

    @State private var showingConsecutiveBenchWarning = false
    @State private var pendingPosition: FieldPosition? = nil
    @State private var showingPitchEligibilityWarning = false

    /// Non-nil when pitching rules are on and this player is ineligible or
    /// their age is unknown. Computed once per picker open.
    private var pitchEligibilityStatus: PitchEligibilityStatus? {
        guard store.pitchingConfig.rulesEnabled else { return nil }
        let status = PitchEligibilityEngine.status(
            for: player,
            gameLogs: store.gameLogs,
            config: store.pitchingConfig,
            referenceDate: store.lineup.gameDate
        )
        return status.blocksAssignment ? status : nil
    }

    /// Single-row pitch status shown at the top of the picker for pitcher-eligible players.
    @ViewBuilder
    private var pitchStatusRow: some View {
        let status = PitchEligibilityEngine.status(
            for: player, gameLogs: store.gameLogs, config: store.pitchingConfig,
            referenceDate: store.lineup.gameDate
        )
        let remaining = pitchesRemaining(
            for: player, gameLogs: store.gameLogs, config: store.pitchingConfig,
            referenceDate: store.lineup.gameDate
        )

        HStack(spacing: 12) {
            Image(systemName: "figure.baseball.pitcher")
                .font(.title3)
                .foregroundColor(.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                switch status {
                case .eligible:
                    Text("Eligible to pitch")
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)
                    if remaining != nil {
                        Text("Pitches available today")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                case .limited:
                    Text("Eligible — limited")
                        .font(.subheadline.bold())
                        .foregroundColor(Color(red: 0.6, green: 0.35, blue: 0.0))
                    Text("Pitches available today")
                        .font(.caption)
                        .foregroundColor(.secondary)
                case .mustRest(let date):
                    Text("Must rest")
                        .font(.subheadline.bold())
                        .foregroundColor(.red)
                    Text(status.displayLabel)
                        .font(.caption)
                        .foregroundColor(.secondary)
                case .unknownAge:
                    Text("League age not set")
                        .font(.subheadline.bold())
                        .foregroundColor(.orange)
                    Text("Set age on the player card to track eligibility")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if let r = remaining {
                Text("\(r)")
                    .font(.system(size: 22, weight: .bold).monospacedDigit())
                    .foregroundColor({
                        guard let age = player.leagueAge,
                              let bracket = PitchingAgeBracket.bracket(for: age),
                              let limits = store.pitchingConfig.ageLimits[bracket] else { return .secondary }
                        let fraction = limits.dailyMax > 0 ? Double(r) / Double(limits.dailyMax) : 0
                        return fraction >= 0.6 ? Color(red: 0.1, green: 0.5, blue: 0.2)
                             : fraction >= 0.25 ? Color(red: 0.6, green: 0.35, blue: 0.0)
                             : .red
                    }())
                Text("left")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .offset(y: 4)
            }
        }
        .padding(.vertical, 4)
    }

    var body: some View {
        NavigationStack {
            List {
                // Pitch availability — shown for all pitcher-eligible players (Pro)
                // so the coach can see runway before choosing a position
                if player.positionPreferences[.pitcher] != .never,
                   store.pitchingConfig.rulesEnabled {
                    Section {
                        pitchStatusRow
                    } footer: {
                        Text("Available is the lower of the daily max and the pitches remaining in the current weekly window.")
                    }
                }

                if inning > 0 {
                    Section("Previous Innings") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(0..<inning, id: \.self) { i in
                                    VStack(spacing: 3) {
                                        Text("Inn \(i + 1)")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        if let pos = store.lineup.innings[i].position(for: player) {
                                            Text(pos.rawValue)
                                                .font(.caption.bold())
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(pos.badgeColor)
                                                .foregroundColor(.white)
                                                .cornerRadius(6)
                                        } else {
                                            Text("—")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                Section("Infield") {
                    ForEach(store.lineup.activeFieldPositions(config: store.fairPlayConfig).filter { $0.isInfield }, id: \.self) { pos in
                        positionRow(pos)
                    }
                }
                Section("Outfield") {
                    ForEach(store.lineup.activeFieldPositions(config: store.fairPlayConfig).filter { $0.isOutfield }, id: \.self) { pos in
                        positionRow(pos)
                    }
                }
                Section {
                    positionRow(.bench)
                }
                Section("Late Arrival / Early Departure") {
                    positionRow(.absent)
                }

                if store.lineup.innings[inning].position(for: player) != nil {
                    Section {
                        Button(role: .destructive) {
                            store.removeAssignment(player: player, inning: inning)
                            dismiss()
                        } label: {
                            Label("Remove Assignment", systemImage: "xmark.circle")
                        }
                    }
                }
            }
            .navigationTitle("\(player.firstName) – Inning \(inning + 1)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Back-to-Back Bench Warning", isPresented: $showingConsecutiveBenchWarning) {
                Button("Assign Bench Anyway", role: .destructive) {
                    if let pos = pendingPosition { commitAssignment(pos) }
                }
                Button("Cancel", role: .cancel) { pendingPosition = nil }
            } message: {
                Text("\(player.firstName) would be on the bench for two consecutive innings. You can still assign bench if needed.")
            }
            .alert("Pitch Eligibility Warning", isPresented: $showingPitchEligibilityWarning) {
                Button("Assign Pitcher Anyway", role: .destructive) {
                    if let pos = pendingPosition { commitAssignment(pos) }
                }
                Button("Cancel", role: .cancel) { pendingPosition = nil }
            } message: {
                if let status = pitchEligibilityStatus {
                    Text("\(player.firstName) may not be eligible to pitch. \(status.displayLabel). You can still assign this position if needed.")
                }
            }
        }
    }

    @ViewBuilder
    func positionRow(_ pos: FieldPosition) -> some View {
        let isSelected = store.lineup.innings[inning].position(for: player) == pos
        let occupant = store.lineup.innings[inning].player(at: pos, in: store.players)
        let occupiedByOther = occupant != nil && occupant?.id != player.id && !pos.isBench
        let wouldBeConsecutiveBench = pos == .bench
            && store.fairPlayConfig.noConsecutiveBench
            && store.lineup.hasConsecutiveBench(player: player, assigningBenchToInning: inning)
        let pitchWarning = pos == .pitcher ? pitchEligibilityStatus : nil
        Button {
            assignPosition(pos)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(pos.displayName)
                            .foregroundColor(occupiedByOther ? .red : .primary)
                        if wouldBeConsecutiveBench {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                        if pitchWarning != nil {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                    if occupiedByOther, let other = occupant {
                        Text("Already assigned: \(other.displayName)")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    if wouldBeConsecutiveBench {
                        Text("Back-to-back bench warning")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    if let pitchWarning {
                        Text(pitchWarning.displayLabel)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark").foregroundColor(.blue)
                }
            }
        }
        .listRowBackground(
            occupiedByOther ? Color.red.opacity(0.06) :
            pitchWarning != nil ? Color.red.opacity(0.06) : nil
        )
    }

    private func assignPosition(_ pos: FieldPosition) {
        if pos == .bench
            && store.fairPlayConfig.noConsecutiveBench
            && store.lineup.hasConsecutiveBench(player: player, assigningBenchToInning: inning) {
            pendingPosition = pos
            showingConsecutiveBenchWarning = true
            return
        }
        // Warn before assigning an ineligible pitcher — still allows the coach to proceed
        if pos == .pitcher, let _ = pitchEligibilityStatus {
            pendingPosition = pos
            showingPitchEligibilityWarning = true
            return
        }
        commitAssignment(pos)
    }

    private func commitAssignment(_ pos: FieldPosition) {
        store.assignPosition(player: player, inning: inning, position: pos)
        dismiss()
    }
}

// MARK: - Pitch Availability Helpers
//
// Shared across DefensiveGridView and PositionSummaryView.
// Computes how many pitches a player has remaining today given their
// daily max and window total, and provides badge + strip card views.

/// Returns pitches remaining for today given a player's config and game logs.
/// Returns nil if the player's pitcher preference is Never, rules are off,
/// or the player has no age bracket configured.
func pitchesRemaining(
    for player: Player,
    gameLogs: [GameLog],
    config: PitchingConfig,
    referenceDate: Date = Date()
) -> Int? {
    guard config.rulesEnabled else { return nil }
    guard player.positionPreferences[.pitcher] != .never else { return nil }
    guard let age = player.leagueAge,
          let bracket = PitchingAgeBracket.bracket(for: age),
          let limits = config.ageLimits[bracket] else { return nil }

    let cal = Calendar.current
    let today = cal.startOfDay(for: referenceDate)
    let windowStart: Date = {
        switch config.rollingWindowType {
        case .calendarWeek:
            var comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)
            comps.weekday = 2
            return cal.date(from: comps) ?? today
        case .rolling:
            return cal.date(byAdding: .day, value: -(config.rollingWindowDays - 1), to: today) ?? today
        }
    }()

    let key = player.id.uuidString
    let windowPitches = gameLogs
        .filter { log in
            let day = cal.startOfDay(for: log.gameDate)
            return day >= windowStart && day < today
        }
        .reduce(0) { total, log in total + (log.pitchCounts[key] ?? 0) }

    // Available = min(dailyMax, weeklyCapRemaining)
    // Daily max is the ceiling for today's game — it doesn't reduce based on
    // pitches thrown on past days, only on the weekly cap if enabled.
    var available = limits.dailyMax
    if config.weeklyLimitEnabled && config.weeklyLimit > 0 {
        let weeklyRemaining = max(0, config.weeklyLimit - windowPitches)
        available = min(available, weeklyRemaining)
    }
    return available
}

/// A small pill badge showing pitch availability for a single player.
/// Green >= 60% of daily max, yellow >= 25%, red = on rest or zero.
/// Hidden for Never-pitcher players.
struct PitchAvailabilityBadge: View {
    let player: Player
    let gameLogs: [GameLog]
    let config: PitchingConfig
    var referenceDate: Date = Date()

    private var content: BadgeContent? {
        guard player.positionPreferences[.pitcher] != .never else { return nil }
        guard config.rulesEnabled else { return nil }

        let status = PitchEligibilityEngine.status(
            for: player, gameLogs: gameLogs, config: config, referenceDate: referenceDate
        )
        switch status {
        case .mustRest(let date):
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE"
            return BadgeContent(label: "REST \(formatter.string(from: date))", style: .red)
        case .unknownAge:
            return BadgeContent(label: "Age?", style: .gray)
        case .eligible, .limited:
            guard let remaining = pitchesRemaining(
                for: player, gameLogs: gameLogs, config: config, referenceDate: referenceDate
            ) else { return nil }
            let dailyMax: Int = {
                guard let age = player.leagueAge,
                      let bracket = PitchingAgeBracket.bracket(for: age),
                      let limits = config.ageLimits[bracket] else { return 85 }
                return limits.dailyMax
            }()
            let fraction = dailyMax > 0 ? Double(remaining) / Double(dailyMax) : 0
            let style: BadgeContent.Style = fraction >= 0.6 ? .green : fraction >= 0.25 ? .yellow : .red
            return BadgeContent(label: "\(remaining)P", style: style)
        }
    }

    var body: some View {
        if let c = content {
            Text(c.label)
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(c.style.background)
                .foregroundColor(c.style.foreground)
                .clipShape(Capsule())
        }
    }

    struct BadgeContent {
        let label: String
        let style: Style
        enum Style {
            case green, yellow, red, gray
            var background: Color {
                switch self {
                case .green:  return Color.green.opacity(0.15)
                case .yellow: return Color.orange.opacity(0.15)
                case .red:    return Color.red.opacity(0.13)
                case .gray:   return Color(.systemGray5)
                }
            }
            var foreground: Color {
                switch self {
                case .green:  return Color(red: 0.1, green: 0.5, blue: 0.2)
                case .yellow: return Color(red: 0.6, green: 0.35, blue: 0.0)
                case .red:    return Color(red: 0.65, green: 0.1, blue: 0.1)
                case .gray:   return .secondary
                }
            }
        }
    }
}

/// A card used in the pitcher availability strip shown above position pickers.
struct PitcherStripCard: View {
    let player: Player
    let gameLogs: [GameLog]
    let config: PitchingConfig
    var referenceDate: Date = Date()

    private var info: (count: String, sub: String, color: Color) {
        let status = PitchEligibilityEngine.status(
            for: player, gameLogs: gameLogs, config: config, referenceDate: referenceDate
        )
        switch status {
        case .mustRest(let date):
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE M/d"
            return ("REST", formatter.string(from: date), .red)
        case .unknownAge:
            return ("?", "set age", .secondary)
        case .eligible, .limited:
            let remaining = pitchesRemaining(
                for: player, gameLogs: gameLogs, config: config, referenceDate: referenceDate
            ) ?? 0
            let dailyMax: Int = {
                guard let age = player.leagueAge,
                      let bracket = PitchingAgeBracket.bracket(for: age),
                      let limits = config.ageLimits[bracket] else { return 85 }
                return limits.dailyMax
            }()
            let fraction = dailyMax > 0 ? Double(remaining) / Double(dailyMax) : 0
            let color: Color = fraction >= 0.6 ? Color(red: 0.1, green: 0.5, blue: 0.2)
                             : fraction >= 0.25 ? Color(red: 0.6, green: 0.35, blue: 0.0)
                             : .red
            return ("\(remaining)", "pitches left", color)
        }
    }

    var body: some View {
        VStack(spacing: 2) {
            Text(player.firstName)
                .font(.caption2.bold())
                .foregroundColor(.primary)
                .lineLimit(1)
            Text(info.count)
                .font(.system(size: 15, weight: .bold).monospacedDigit())
                .foregroundColor(info.color)
            Text(info.sub)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(minWidth: 56)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(.systemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    info.color == .red ? Color.red.opacity(0.4) : Color(.separator),
                    lineWidth: 0.5
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// Horizontal scrolling strip of all pitcher-eligible players with their availability.
/// Shown above position pickers when the pitcher slot is being assigned.
struct PitcherAvailabilityStrip: View {
    let players: [Player]
    let gameLogs: [GameLog]
    let config: PitchingConfig
    var referenceDate: Date = Date()

    private var eligiblePlayers: [Player] {
        players
            .filter { $0.positionPreferences[.pitcher] != .never }
            .sorted {
                let aStatus = PitchEligibilityEngine.status(for: $0, gameLogs: gameLogs, config: config, referenceDate: referenceDate)
                let bStatus = PitchEligibilityEngine.status(for: $1, gameLogs: gameLogs, config: config, referenceDate: referenceDate)
                return !aStatus.isRestricted && bStatus.isRestricted
            }
    }

    var body: some View {
        if config.rulesEnabled && !eligiblePlayers.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Pitcher availability")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(eligiblePlayers) { player in
                            PitcherStripCard(
                                player: player,
                                gameLogs: gameLogs,
                                config: config,
                                referenceDate: referenceDate
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 4)
            .background(Color(.systemGroupedBackground))
        }
    }
}

// MARK: - Read-Only Banner
// Shown at the top of each tab when the active team is a shared read-only team.
// Explains the lock state so coaches aren't confused by disabled controls.

struct ReadOnlyBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.2.fill")
                .font(.caption.bold())
                .foregroundColor(.orange)
            Text("Shared team. You can view but not make changes.")
                .font(.caption)
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08))
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color.orange.opacity(0.25)),
            alignment: .bottom
        )
    }
}
