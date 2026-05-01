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

    // Clear positions state
    @State private var showingClearPopover = false     // inning view: anchored popover
    @State private var showingClearAllConfirm = false  // confirm alert for clearing all innings

    // One-time Auto-Fill context tip — shown the first time a Pro user opens
    // the Positions tab with at least one player in the roster.
    @AppStorage("hasSeenAutoFillTip") private var hasSeenAutoFillTip = false
    @State private var showingAutoFillTip = false

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
                    if showingSummary {
                        LineupStatusStrip(
                            status: store.lineup.status,
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
                        clearPositionsButton(isSummary: true)

                    } else {
                        if verticalSizeClass == .compact {
                            // ── Landscape layout ──────────────────────────────
                            LineupStatusStrip(
                                status: store.lineup.status,
                                onFinalize: { store.finalizeLineup() },
                                onReopen: { store.reopenLineup() }
                            )

                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("Inning \(selectedInning + 1)")
                                    .font(.title2.bold())
                                boltButton
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
                                                    onTap: {
                                                        selectedPlayer = player
                                                        showingUndo = false
                                                    }
                                                )
                                            }
                                        }
                                        .listStyle(.plain)

                                        // Inning view — popover with two scope options
                                        clearPositionsButton(isSummary: false)
                                    }
                                }
                            }

                        } else {
                            // ── Portrait layout ───────────────────────────────
                            LineupStatusStrip(
                                status: store.lineup.status,
                                onFinalize: { store.finalizeLineup() },
                                onReopen: { store.reopenLineup() }
                            )

                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("Inning \(selectedInning + 1) Positions")
                                    .font(.largeTitle.bold())
                                boltButton
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
                                            onTap: {
                                                selectedPlayer = player
                                                showingUndo = false
                                            }
                                        )
                                    }
                                }
                                .listStyle(.plain)

                                // Inning view — popover with two scope options
                                clearPositionsButton(isSummary: false)
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
                        Button {
                            showingArchive = true
                        } label: {
                            Label("Archive Game", systemImage: "archivebox")
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

        let result: (lineup: Lineup, filledCount: Int)
        switch scope {
        case .thisInning:
            result = AutoFillEngine.fillInning(selectedInning, in: store.activeTeam.lineup, players: store.players, preferences: preferences)
        case .through(let lastInning):
            result = AutoFillEngine.fillInnings(through: lastInning, in: store.activeTeam.lineup, players: store.players, preferences: preferences)
        }

        guard result.filledCount > 0 else { return }

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

        Analytics.signal("autofill.used", parameters: [
            "mode": {
                if case .thisInning = scope { return "inning" }
                return "range"
            }(),
            "filledCount": "\(result.filledCount)"
        ])
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
        let openPos = store.lineup.openPositions(inning: selectedInning, players: activePlayers)
        let dupPos = store.lineup.duplicatePositionErrors(inning: selectedInning)
        return openPos.count + dupPos.count
    }

    var gameWideIssueCount: Int {
        let activePlayers = store.lineup.activePlayers(from: store.players)
        let noInfield = store.lineup.playersWithoutInfield(players: activePlayers)
        let noOutfield = store.lineup.playersWithoutOutfield(players: activePlayers)
        let underMinimum = store.lineup.playersUnderFieldingMinimum(players: activePlayers)
        let backToBack = store.lineup.playersWithBackToBackBench(from: store.players)
        return noInfield.count + noOutfield.count + backToBack.count + underMinimum.count
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
        let openPos = store.lineup.openPositions(inning: inning, players: activePlayers)
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
    let onFinalize: () -> Void
    let onReopen: () -> Void

    var body: some View {
        HStack {
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

            Spacer()

            if status == .finalized {
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
        let activePlayers = store.lineup.activePlayers(from: store.players)
        let openPos = store.lineup.openPositions(inning: inning, players: activePlayers)
        let dupPos = store.lineup.duplicatePositionErrors(inning: inning)
        for pos in dupPos { warnings.append("Duplicate position: \(pos.displayName)") }
        for pos in openPos { warnings.append("Open position: \(pos.displayName)") }
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
        return warnings
    }

    func computeOverallWarnings() -> [String] {
        var warnings: [String] = []
        let active = store.lineup.activePlayers(from: store.players)
        for player in store.lineup.playersWithoutInfield(players: active) {
            warnings.append("\(player.displayName): no infield inning assigned")
        }
        for player in store.lineup.playersWithoutOutfield(players: active) {
            warnings.append("\(player.displayName): no outfield inning assigned")
        }
        for player in store.lineup.playersUnderFieldingMinimum(players: active) {
            warnings.append("\(player.displayName): under 4 innings fielded")
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
                    }
                    if let history = previousPositionsSummary {
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
        .listRowBackground(isDuplicate ? Color.red.opacity(0.08) : nil)
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

    var body: some View {
        NavigationStack {
            List {
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
                    ForEach(FieldPosition.infieldPositions, id: \.self) { pos in
                        positionRow(pos)
                    }
                }
                Section("Outfield") {
                    ForEach(FieldPosition.outfieldPositions, id: \.self) { pos in
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
        }
    }

    @ViewBuilder
    func positionRow(_ pos: FieldPosition) -> some View {
        let isSelected = store.lineup.innings[inning].position(for: player) == pos
        let occupant = store.lineup.innings[inning].player(at: pos, in: store.players)
        let occupiedByOther = occupant != nil && occupant?.id != player.id && !pos.isBench
        let wouldBeConsecutiveBench = pos == .bench && store.lineup.hasConsecutiveBench(player: player, assigningBenchToInning: inning)
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
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark").foregroundColor(.blue)
                }
            }
        }
        .listRowBackground(occupiedByOther ? Color.red.opacity(0.06) : nil)
    }

    private func assignPosition(_ pos: FieldPosition) {
        if pos == .bench && store.lineup.hasConsecutiveBench(player: player, assigningBenchToInning: inning) {
            pendingPosition = pos
            showingConsecutiveBenchWarning = true
            return
        }
        commitAssignment(pos)
    }

    private func commitAssignment(_ pos: FieldPosition) {
        store.assignPosition(player: player, inning: inning, position: pos)
        dismiss()
    }
}
