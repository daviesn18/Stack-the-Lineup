import SwiftUI
import TipKit

struct DefensiveGridView: View {
    @EnvironmentObject var store: LineupStore
    @EnvironmentObject var purchaseManager: PurchaseManager
    @Environment(\.verticalSizeClass) var verticalSizeClass
    @State private var selectedInning: Int = 0

    // Position-led By Inning selection. Tapping a position row (or a bench row)
    // opens the player picker for that slot. Replaces the old player-led flow
    // where tapping a player opened the position picker.
    @State private var selectedSlot: SlotTarget? = nil

    // Player-led picker for bench/absent chips on the diamond: tapping a chip
    // opens PositionPickerView so the coach can move that player to a
    // position, bench, or absent.
    @State private var selectedPlayer: Player? = nil
    @State private var showingWarnings = false
    @State private var showingSummary = false
    @Binding var showingArchive: Bool
    @Binding var selectedTab: Int          // passed in from ContentView to navigate to Players tab

    /// False while the welcome/what's-new cover is up. Passed from the parent
    /// so a Positions tip can't present over that chrome.
    var tourEnabled: Bool = true

    /// True when the Positions tab (tag 2) is the one on screen and no cover is
    /// up. Stands the tour anchors down while a sibling tab is showing, so an
    /// eligible Positions tip can't present mispositioned over another tab.
    /// This view is iPhone-only, so there's no iPad embed to account for.
    private var isTourTabActive: Bool { selectedTab == 2 && tourEnabled }
    @State private var showingTips = false
    @State private var showingPaywall = false
    @State private var showingSaveTemplate = false
    @State private var showingTemplatePaywall = false

    // Auto-Fill state
    @State private var showingAutoFillPopover = false
    @State private var undoSnapshot: [InningAssignment]? = nil
    @State private var undoMessage: String = ""
    @State private var showingUndo = false
    @State private var showingAutoFillIncomplete = false
    @State private var autoFillIncompleteMessage: String = ""

    // NL Auto-Fill constraint prompt — resets after every fill (one-shot,
    // not persisted between games). Parsing runs on-device via
    // AutoFillNLConstraintService before AutoFillEngine is called.
    @State private var autoFillPrompt: String = ""
    @State private var showingAutoFillConstraintNotice = false
    @State private var autoFillConstraintNoticeMessage: String = ""

    // Parse, engine call and message composition all live here — the iPad pane
    // and FillLineupIntent share the same instance type. What stays in this
    // view is the UI the outcome drives: the undo toast and the two alerts.
    @StateObject private var autoFill = AutoFillCoordinator()

    // Clear positions state
    @State private var showingClearPopover = false     // inning view: anchored popover
    @State private var showingClearAllConfirm = false  // confirm alert for clearing all innings

    // Bench-the-leftovers prompt. Offered the moment the last open field slot in
    // the current inning gets filled and players are still sitting with no slot
    // at all. By Inning only — the Summary grid edits many innings at once, so
    // an alert per completed inning would be noise.
    @State private var showingBenchLeftoverPrompt = false

    // One-time Auto-Fill context tip — shown the first time a Pro user opens
    // the Positions tab with at least one player in the roster.

    // Tip overlay driven by parent iPhoneTabView

    private var isReadOnly: Bool { store.activeTeam.isReadOnly }

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
                        // Landscape folds the status/finalize row into the
                        // summary's collapsed top bar -- a standalone strip
                        // would cost a full row of scarce vertical space.
                        if verticalSizeClass != .compact {
                            LineupStatusStrip(
                                status: store.lineup.status,
                                isReadOnly: isReadOnly,
                                lastFinalizedBy: store.lineup.lastFinalizedBy,
                                lastFinalizedAt: store.lineup.lastFinalizedAt,
                                onFinalize: { store.finalizeLineup() },
                                onReopen: { store.reopenLineup() }
                            )
                        }

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
                                runAutoFill(scope: .through(lastInning))
                            },
                            smartDefaultLastInning: smartDefaultLastInning,
                            autoFillPrompt: $autoFillPrompt,
                            isParsingAutoFillPrompt: autoFill.isParsingPrompt
                        )
                        .onChange(of: showingAutoFillPopover) { _, isShowing in
                            if isShowing { autoFill.prewarm(for: store.activeTeam) } else { autoFill.teardown() }
                        }

                        // Summary view — clear all only, straight to confirm
                        // alert. In landscape this moves into the shared
                        // one-row footer alongside Save as Template.
                        if !isReadOnly && verticalSizeClass != .compact {
                            clearPositionsButton(isSummary: true)
                        }

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
                                        diamondBodyLandscape

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
                            .tourTip(Tour.positions.currentTip as? PositionsWarningsTip, arrowEdge: .top,
                                     enabled: isTourTabActive)

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
                            .tourTip(Tour.positions.currentTip as? PositionsViewModeTip, arrowEdge: .top,
                                     enabled: isTourTabActive)

                            Divider()

                            if store.players.isEmpty {
                                ContentUnavailableView(
                                    "No Players",
                                    systemImage: "person.badge.plus",
                                    description: Text("Add players on the Players tab first.")
                                )
                            } else {
                                diamondBodyPortrait

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
            .safeAreaInset(edge: .bottom) {
                if !isReadOnly {
                    if showingSummary && verticalSizeClass == .compact {
                        summaryLandscapeFooter
                    } else {
                        saveAsTemplateBanner
                    }
                }
            }
            .sheet(item: $selectedSlot) { slot in
                PlayerPickerView(position: slot.position, benchSlotOccupant: slot.benchOccupant, inning: selectedInning)
                    .environmentObject(store)
                    .environmentObject(purchaseManager)
            }
            .sheet(item: $selectedPlayer) { player in
                PositionPickerView(player: player, inning: selectedInning)
                    .environmentObject(store)
            }
            .sheet(isPresented: $showingWarnings) {
                WarningsView(inning: selectedInning)
            }
            .sheet(isPresented: $showingTips) {
                PageTipsView(page: .positions)
            }
            .fullScreenCover(isPresented: $showingPaywall) {
                ProGate(source: "autofill", navTitle: "Auto-Fill")
                    .environmentObject(purchaseManager)
            }
            .sheet(isPresented: $showingSaveTemplate) {
                TemplateLockEditorView()
                    .environmentObject(store)
                    .environmentObject(purchaseManager)
            }
            .fullScreenCover(isPresented: $showingTemplatePaywall) {
                ProGate(source: "lineup_template", navTitle: "Lineup Templates") {
                    TemplateLockPreviewView()
                }
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
            // Offers to bench whoever is left over once the inning's field is full.
            .onChange(of: benchPromptSignal) { old, new in
                evaluateBenchLeftoverPrompt(from: old, to: new)
            }
            .alert("Bench remaining players?", isPresented: $showingBenchLeftoverPrompt) {
                Button("Bench All") { benchLeftoverPlayers() }
                Button("Not Now", role: .cancel) {}
            } message: {
                Text(benchLeftoverPromptMessage)
            }
            // Shown when the NL prompt was honored but bypassed a Fair Play
            // soft constraint, or couldn't be honored at all.
            .alert("About Your Instructions", isPresented: $showingAutoFillConstraintNotice) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(autoFillConstraintNoticeMessage)
            }
        }
    }

    // MARK: - Clear Positions Button

    @ViewBuilder
    func clearPositionsButton(isSummary: Bool) -> some View {
        let hasAnyAssignments = store.lineup.innings.contains { !$0.assignments.isEmpty }
        if hasAnyAssignments, isSummary {
            // Summary footer -- full-width soft-red pill per the Position
            // Summary redesign, straight to the confirm alert.
            Button {
                showingClearAllConfirm = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Clear positions")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(Color(red: 0.89, green: 0.29, blue: 0.29))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(Color(red: 0.99, green: 0.92, blue: 0.92))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color(red: 0.94, green: 0.58, blue: 0.58), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(.systemGroupedBackground))
        } else if hasAnyAssignments {
            HStack {
                Spacer()
                Button {
                    showingClearPopover = true
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

    // MARK: - Save as Template Banner
    // Persistent bottom banner, visible in both Summary and by-inning modes
    // since it lives in a safeAreaInset outside the showingSummary branch.

    @ViewBuilder
    var saveAsTemplateBanner: some View {
        Button {
            if store.lineupTemplates.isEmpty || purchaseManager.isPro {
                showingSaveTemplate = true
            } else {
                showingTemplatePaywall = true
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "square.and.arrow.down")
                    .font(.subheadline.weight(.semibold))
                Text("Save as Template")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if !store.lineupTemplates.isEmpty && !purchaseManager.isPro {
                    ProBadge()
                }
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundColor(Color(.tertiaryLabel))
            }
            .foregroundColor(.blue)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .background(Color(.systemBackground))
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color(.separator)),
            alignment: .top
        )
    }

    // MARK: - Summary Landscape Footer
    // Landscape puts Clear positions and Save as Template on one shared row
    // instead of the portrait stack -- height is the scarce axis there.

    @ViewBuilder
    var summaryLandscapeFooter: some View {
        let hasAnyAssignments = store.lineup.innings.contains { !$0.assignments.isEmpty }
        HStack(spacing: 16) {
            if hasAnyAssignments {
                Button {
                    showingClearAllConfirm = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle")
                        Text("Clear positions")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(red: 0.89, green: 0.29, blue: 0.29))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color(red: 0.99, green: 0.92, blue: 0.92))
                    .cornerRadius(9)
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .strokeBorder(Color(red: 0.94, green: 0.58, blue: 0.58), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Button {
                if store.lineupTemplates.isEmpty || purchaseManager.isPro {
                    showingSaveTemplate = true
                } else {
                    showingTemplatePaywall = true
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.down")
                    Text("Save as Template")
                    if !store.lineupTemplates.isEmpty && !purchaseManager.isPro {
                        ProBadge()
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundColor(Color(.tertiaryLabel))
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.blue)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color(.separator)),
            alignment: .top
        )
    }

    // MARK: - Auto-Fill Logic

    func runAutoFill(scope: AutoFillScope) {
        Task { await performAutoFill(scope: scope) }
    }

    /// Runs the shared coordinator, then drives everything the outcome implies
    /// on screen: writing the lineup back, the undo toast, and the two alerts.
    ///
    /// The popover is intentionally kept open (not dismissed) until parsing
    /// finishes, so the "Reading your instructions..." spinner is actually
    /// visible while it runs — dismissing the popover immediately on tap (the
    /// original behavior) closed it before the spinner ever got a chance to
    /// render.
    @MainActor
    private func performAutoFill(scope: AutoFillScope) async {
        let snapshot = store.activeTeam.lineup.innings

        let outcome = await autoFill.run(
            scope: scope,
            prompt: autoFillPrompt,
            team: store.activeTeam
        )

        // Parsing has settled (success, fallback, or timeout) — everything from
        // here is fast, synchronous work, so the popover can go.
        showingAutoFillPopover = false

        if outcome.didFill {
            store.activeTeam.lineup = outcome.lineup
            store.save()

            undoSnapshot = snapshot
            undoMessage = outcome.undoMessage
            withAnimation { showingUndo = true }

            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                withAnimation { showingUndo = false }
            }
        }

        // Prompt is one-shot — clear it now that this fill has run, whether
        // or not it produced any usable constraints.
        autoFillPrompt = ""

        if let message = outcome.incompleteMessage {
            autoFillIncompleteMessage = message
            // Small delay so the undo toast settles before the alert fires.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                showingAutoFillIncomplete = true
            }
        }

        if let notice = outcome.noticeMessage {
            autoFillConstraintNoticeMessage = notice
            // Stack after the incomplete-fill alert if both fire.
            let delay = outcome.hasUnfilledSlots ? 0.7 : 0.35
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                showingAutoFillConstraintNotice = true
            }
        }
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

    /// What's wrong with the inning currently on screen. Deliberately overlaps
    /// nothing in `gameWideIssueCount` — the toolbar label adds the two together.
    var currentInningIssueCount: Int {
        let activePlayers = store.lineup.activePlayers(from: store.players)
        let openPos = store.lineup.openPositions(inning: selectedInning, players: activePlayers, config: store.fairPlayConfig)
        let dupPos = store.lineup.duplicatePositionErrors(inning: selectedInning)
        return openPos.count + dupPos.count
    }

    /// What's wrong with the game as a whole, counted the way a coach thinks
    /// about it: one number per player to go fix, not one per rule broken.
    ///
    /// Reads `Lineup.fairPlayFindings` — the same call the iPad dashboard, the
    /// iPad nav bar, the Lineup tab and the game recap make — so every surface
    /// reports the same number for the same lineup. This used to sum the
    /// per-rule counts, which showed a player missing both infield and outfield
    /// as 2 on iPhone and 1 everywhere else.
    ///
    /// The selected inning's open slots are excluded because
    /// `currentInningIssueCount` already counts them and `warningsToolbarLabel`
    /// adds both terms — one unfilled shortstop in the inning you're looking at
    /// used to read as 2 issues.
    var gameWideIssueCount: Int {
        fairPlayFindings.implicatedPlayerIDs.count
            + openPositionCount(excludingInning: selectedInning)
            + blockedPitcherCount
    }

    /// Every fair-play rule the team has switched on, evaluated once.
    /// Rules that are off come back empty, so nothing here re-checks the config.
    var fairPlayFindings: FairPlayFindings {
        store.lineup.fairPlayFindings(players: store.players, config: store.fairPlayConfig)
    }

    /// Open field slots across the game. Innings with no assignments at all are
    /// skipped — an inning nobody has started isn't missing anything yet.
    func openPositionCount(excludingInning excluded: Int) -> Int {
        let activePlayers = store.lineup.activePlayers(from: store.players)
        let config = store.fairPlayConfig
        return store.lineup.innings.indices.reduce(into: 0) { count, index in
            guard index != excluded, !store.lineup.innings[index].assignments.isEmpty else { return }
            count += store.lineup.openPositions(inning: index, players: activePlayers, config: config).count
        }
    }

    /// Assigned pitchers the pitching rules say can't take the mound — counted
    /// per player, not per inning, so a blocked pitcher listed three times is
    /// still one thing to fix.
    var blockedPitcherCount: Int {
        guard store.pitchingConfig.rulesEnabled else { return 0 }
        let assignedPitcherIDs = Set(
            store.lineup.innings.flatMap { inning in
                inning.assignments.compactMap { (pid, pos) -> UUID? in pos == .pitcher ? pid : nil }
            }
        )
        return assignedPitcherIDs.filter { playerID in
            guard let player = store.players.first(where: { $0.id == playerID }) else { return false }
            return PitchEligibilityEngine.status(
                for: player,
                gameLogs: store.gameLogs,
                config: store.pitchingConfig,
                referenceDate: store.lineup.gameDate
            ).blocksAssignment
        }.count
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
                inningCount: store.lineup.innings.count,
                prompt: $autoFillPrompt,
                isParsingPrompt: autoFill.isParsingPrompt,
                currentInning: selectedInning
            ) { scope in
                runAutoFill(scope: scope)
            }
            .presentationCompactAdaptation(.popover)
            .onAppear { autoFill.prewarm(for: store.activeTeam) }
            .onDisappear { autoFill.teardown() }
        }
        // Three tips point at the bolt, in the order a coach meets the idea:
        // arc 1 introduces the button, arc 2 introduces the natural-language
        // instructions inside its popover, then how to skip the button and just
        // ask Siri.
        .tourTip(Tour.positions.currentTip as? PositionsAutoFillTip, arrowEdge: .top,
                 enabled: isTourTabActive)
        .tourTip(Tour.secondGame.currentTip as? AutoFillConstraintsTip, arrowEdge: .top,
                 enabled: isTourTabActive)
        .tourTip(Tour.secondGame.currentTip as? AskSiriTip, arrowEdge: .top,
                 enabled: isTourTabActive)
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

    // MARK: - Position-Led Inning List

    /// Identifies the slot a coach tapped in the By Inning list. A field position
    /// carries a nil occupant. A bench row carries the player currently in that
    /// bench slot (nil for the "add to bench" row) so the picker knows whether it
    /// is reassigning that player or benching a new one.
    struct SlotTarget: Identifiable {
        let id = UUID()
        let position: FieldPosition
        let benchOccupant: Player?
    }

    /// Players sitting on the bench this inning, in batting-order display order.
    private var benchedPlayers: [Player] {
        displayPlayers.filter { store.lineup.innings[selectedInning].position(for: $0) == .bench }
    }

    /// Players marked absent (late arrival / early departure) for this inning.
    /// Distinct from lineup-level absentPlayerIDs, which removes a player from
    /// displayPlayers entirely — this is the per-inning FieldPosition.absent slot.
    private var absentPlayersThisInning: [Player] {
        displayPlayers.filter { store.lineup.innings[selectedInning].position(for: $0) == .absent }
    }

    // MARK: - Bench Leftovers Prompt

    /// Carries the inning index alongside its assignments so the observer can
    /// tell an edit apart from a plain inning switch (which also changes the
    /// assignments being watched, but must never prompt).
    private struct BenchPromptSignal: Equatable {
        let inning: Int
        let assignments: [UUID: FieldPosition]
    }

    private var benchPromptSignal: BenchPromptSignal {
        BenchPromptSignal(
            inning: selectedInning,
            assignments: store.lineup.innings.indices.contains(selectedInning)
                ? store.lineup.innings[selectedInning].assignments
                : [:]
        )
    }

    /// Players with no slot at all in the given inning — not on the field, not
    /// benched, not marked absent. These are the ones the prompt offers to bench.
    private func unslottedPlayers(in assignment: InningAssignment) -> [Player] {
        displayPlayers.filter { assignment.position(for: $0) == nil }
    }

    /// True when every field position active under the current ruleset has an
    /// occupant. ABS doesn't fill a slot, matching Lineup.openPositions.
    private func allFieldPositionsFilled(in assignment: InningAssignment) -> Bool {
        let filled = Set(assignment.assignments.values.filter { !$0.isAbsent })
        return store.lineup.activeFieldPositions(config: store.fairPlayConfig)
            .allSatisfy { filled.contains($0) }
    }

    /// Fires on the edit that completes the inning's field — not on every edit
    /// made while it happens to be complete, so reassigning players afterwards
    /// doesn't re-prompt.
    private func evaluateBenchLeftoverPrompt(from old: BenchPromptSignal, to new: BenchPromptSignal) {
        guard !isReadOnly, !showingSummary else { return }
        guard old.inning == new.inning else { return }
        let before = InningAssignment(assignments: old.assignments)
        let after = InningAssignment(assignments: new.assignments)
        guard !allFieldPositionsFilled(in: before) else { return }
        guard allFieldPositionsFilled(in: after), !unslottedPlayers(in: after).isEmpty else { return }

        // The picker sheet assigns and dismisses in one gesture, so the change
        // lands mid-dismissal. Presenting the alert now gets it swallowed —
        // wait for the sheet to finish leaving, then re-check that the state
        // that earned the prompt still holds.
        let inning = new.inning
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            guard selectedInning == inning,
                  !isReadOnly, !showingSummary,
                  store.lineup.innings.indices.contains(inning) else { return }
            let current = store.lineup.innings[inning]
            guard allFieldPositionsFilled(in: current), !unslottedPlayers(in: current).isEmpty else { return }
            showingBenchLeftoverPrompt = true
        }
    }

    /// Names the leftovers so the coach can spot anyone who should be marked
    /// absent instead of benched.
    private var benchLeftoverPromptMessage: String {
        guard store.lineup.innings.indices.contains(selectedInning) else { return "" }
        let leftovers = unslottedPlayers(in: store.lineup.innings[selectedInning])
        let names = leftovers.map(\.displayName).formatted(.list(type: .and))
        let subject = leftovers.count == 1 ? "isn't" : "aren't"
        return "\(names) \(subject) in inning \(selectedInning + 1) yet. Put them on the bench?"
    }

    private func benchLeftoverPlayers() {
        for player in unslottedPlayers(in: store.lineup.innings[selectedInning]) {
            store.assignPosition(player: player, inning: selectedInning, position: .bench)
        }
    }

    // MARK: - Diamond Body

    /// First names that appear more than once in the lineup. Computed across the
    /// full lineup (not per inning) so a player's field label never changes
    /// between innings.
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

    /// Slot placement as percentages of the field box, from the design spec.
    /// LCF/RCF aren't in the design (it assumes 3 outfielders) — under
    /// 4-outfielder configs they sit on the outfield arc where CF was.
    private func diamondCoordinates(for pos: FieldPosition) -> CGPoint? {
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

    /// Portrait: field over Bench and Absent chip groups, vertically scrollable.
    private var diamondBodyPortrait: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                diamondField
                    .aspectRatio(1 / 0.82, contentMode: .fit)
                    .padding(.horizontal, 8)
                    .padding(.top, 2)
                    .tourTip(Tour.positions.currentTip as? PositionsAssignTip, arrowEdge: .top,
                             enabled: isTourTabActive)

                chipGroupHeader("Bench")
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .padding(.bottom, 6)
                benchChipRail
                    .padding(.horizontal, 16)

                chipGroupHeader("Late arrival / early departure")
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .padding(.bottom, 6)
                absentChipRail
                    .padding(.horizontal, 16)
            }
            .padding(.bottom, 20)
        }
    }

    /// Landscape: field on the left (~56% width), Bench + Absent chip panel on
    /// the right. The field keeps its aspect ratio from its width rather than
    /// squashing into the short landscape viewport, so the whole body scrolls
    /// vertically when it runs past the fold.
    private var diamondBodyLandscape: some View {
        GeometryReader { geo in
            ScrollView(showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    diamondField
                        .aspectRatio(1 / 0.82, contentMode: .fit)
                        .frame(width: geo.size.width * 0.56)

                    VStack(alignment: .leading, spacing: 0) {
                        chipGroupHeader("Bench")
                            .padding(.top, 10)
                            .padding(.bottom, 6)
                        benchChipRail

                        chipGroupHeader("Late arrival / early departure")
                            .padding(.top, 14)
                            .padding(.bottom, 6)
                        absentChipRail
                    }
                    .padding(.trailing, 12)
                }
                .padding(.leading, 8)
                .padding(.top, 2)
                .padding(.bottom, 12)
            }
        }
    }

    /// The schematic field: outfield fan + infield diamond drawn in the design's
    /// 0–100 coordinate space, with position slots placed on top.
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

                // Computed once for the whole diamond rather than inside
                // fieldSlot, which would re-scan the inning's assignments for
                // each of the nine to eleven slots to answer the same question.
                let duplicates = Set(store.lineup.duplicatePositionErrors(inning: selectedInning))

                ForEach(store.lineup.activeFieldPositions(config: store.fairPlayConfig), id: \.self) { pos in
                    if let coord = diamondCoordinates(for: pos) {
                        fieldSlot(pos, duplicates: duplicates)
                            .position(
                                x: geo.size.width * coord.x / 100,
                                y: geo.size.height * coord.y / 100
                            )
                    }
                }
            }
        }
    }

    /// One field slot: position badge over the occupant's name chip ("Open" when
    /// empty). Carries the same duplicate and pitch-eligibility flags as the old
    /// list rows. Tapping opens the player picker for the slot.
    @ViewBuilder
    private func fieldSlot(_ pos: FieldPosition, duplicates: Set<FieldPosition>) -> some View {
        let occupant = store.lineup.innings[selectedInning].player(at: pos, in: store.players)
        let isDuplicate = duplicates.contains(pos)
        let pitchWarning: Bool = {
            guard pos == .pitcher, let occupant, store.pitchingConfig.rulesEnabled else { return false }
            return PitchEligibilityEngine.status(
                for: occupant, gameLogs: store.gameLogs, config: store.pitchingConfig,
                referenceDate: store.lineup.gameDate
            ).blocksAssignment
        }()

        Button {
            guard !isReadOnly else { return }
            selectedSlot = SlotTarget(position: pos, benchOccupant: nil)
            showingUndo = false
        } label: {
            VStack(spacing: 3) {
                diamondBadge(pos, occupant: occupant)

                HStack(spacing: 3) {
                    Text(occupant.map { diamondDisplayName($0) } ?? "Open")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(occupant == nil ? Color(.systemGray) : .primary)
                        .lineLimit(1)
                    if pitchWarning {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.red)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(isDuplicate ? Color.red.opacity(0.08) : Color.clear)
                .background(Color(.systemBackground))
                .cornerRadius(7)
                .shadow(color: .black.opacity(0.12), radius: 3, x: 0, y: 1)
            }
            .fixedSize()
        }
        .buttonStyle(.plain)
        .disabled(isReadOnly)
    }

    /// Solid position badge for a field slot, with the Emergency/Never preference
    /// border when the current occupant has a preference set (Pro).
    @ViewBuilder
    private func diamondBadge(_ pos: FieldPosition, occupant: Player?) -> some View {
        let prefTier: PositionPreferenceTier? = (purchaseManager.isPro && !pos.isAbsent)
            ? occupant?.positionPreferences[pos]
            : nil
        let showBorder = prefTier == .emergency || prefTier == .never

        Text(pos.rawValue)
            .font(.caption.bold())
            .foregroundColor(.white)
            .padding(.horizontal, 7)
            .frame(minWidth: 34, minHeight: 24)
            .background(pos.badgeColor)
            .cornerRadius(6)
            .overlay {
                if showBorder, let tier = prefTier {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(tier.color, lineWidth: 2)
                }
            }
    }

    // MARK: - Bench / Absent Chip Rails

    @ViewBuilder
    private func chipGroupHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .textCase(.uppercase)
            .foregroundColor(.secondary)
    }

    private var benchChipRail: some View {
        ChipFlowLayout(spacing: 8) {
            ForEach(benchedPlayers) { player in
                chip(player, kind: .bench)
            }
            if !isReadOnly {
                addChip("+ Bench", target: .bench)
            }
        }
    }

    private var absentChipRail: some View {
        ChipFlowLayout(spacing: 8) {
            ForEach(absentPlayersThisInning) { player in
                chip(player, kind: .absent)
            }
            if !isReadOnly {
                addChip("+ Absent", target: .absent)
            }
        }
    }

    /// Tapping a chip opens the player-led position picker; the undo bar goes
    /// away with it, since the action it would undo is no longer on screen.
    private func chip(_ player: Player, kind: PlayerChip.Kind) -> some View {
        PlayerChip(player: player, kind: kind, inning: selectedInning, isReadOnly: isReadOnly) {
            selectedPlayer = player
            showingUndo = false
        }
    }

    /// Dashed "+ Bench" / "+ Absent" chip — opens the picker targeting that slot.
    private func addChip(_ label: String, target: FieldPosition) -> some View {
        Button {
            selectedSlot = SlotTarget(position: target, benchOccupant: nil)
            showingUndo = false
        } label: {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.blue)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .overlay(
                    Capsule()
                        .strokeBorder(Color(.systemGray3), style: StrokeStyle(lineWidth: 1.5, dash: [4]))
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Field Shapes
// Drawn in the design's 0–100 viewBox and scaled to the container, so the
// field keeps its proportions at any size (portrait width-fit, landscape
// height-fill).

/// Outfield fan: home plate bottom-center, both foul lines out to the arc.
/// Stroking this shape draws the foul lines and the outfield arc; filling it
/// gives the grass wash. Shared with the iPad dashboard's By Inning diamond.
struct OutfieldFanShape: Shape {
    func path(in rect: CGRect) -> Path {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x / 100, y: rect.minY + rect.height * y / 100)
        }
        var path = Path()
        path.move(to: pt(50, 90))
        path.addLine(to: pt(6, 30))
        path.addQuadCurve(to: pt(94, 30), control: pt(50, -6))
        path.closeSubpath()
        return path
    }
}

/// Infield diamond centered under the pitcher's mound slot.
struct InfieldDiamondShape: Shape {
    func path(in rect: CGRect) -> Path {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x / 100, y: rect.minY + rect.height * y / 100)
        }
        var path = Path()
        path.move(to: pt(50, 88))
        path.addLine(to: pt(74, 60))
        path.addLine(to: pt(50, 40))
        path.addLine(to: pt(26, 60))
        path.closeSubpath()
        return path
    }
}

// MARK: - Chip Flow Layout
// Left-aligned wrapping layout for the bench/absent chip rails. Shared with
// the iPad dashboard's By Inning diamond.

struct ChipFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > width, currentX > 0 {
                currentY += lineHeight + spacing
                currentX = 0
                lineHeight = 0
            }
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: width, height: currentY + lineHeight)
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
    @Binding var prompt: String
    let isParsingPrompt: Bool
    /// Zero-based index behind "Fill This Inning". Ignored in summary mode,
    /// which has no single current inning and hides that button.
    let currentInning: Int
    let onSelect: (AutoFillScope) -> Void

    @State private var selectedLastInning: Int
    @FocusState private var promptFieldFocused: Bool

    init(
        isSummary: Bool,
        smartDefaultLastInning: Int,
        inningCount: Int,
        prompt: Binding<String>,
        isParsingPrompt: Bool,
        currentInning: Int = 0,
        onSelect: @escaping (AutoFillScope) -> Void
    ) {
        self.isSummary = isSummary
        self.smartDefaultLastInning = smartDefaultLastInning
        self.inningCount = inningCount
        self._prompt = prompt
        self.isParsingPrompt = isParsingPrompt
        self.currentInning = currentInning
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

            VStack(alignment: .leading, spacing: 6) {
                Text("Optional adjustments")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                TextField(
                    "e.g. \"Caleb pitches the first 2 innings\"",
                    text: $prompt,
                    axis: .vertical
                )
                .font(.caption)
                .lineLimit(1...6)
                .textFieldStyle(.roundedBorder)
                .focused($promptFieldFocused)
                .disabled(isParsingPrompt)

                if isParsingPrompt {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("Reading your instructions...")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            if !isSummary {
                Button {
                    onSelect(.inning(currentInning))
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
                .disabled(isParsingPrompt)

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
                    HStack(spacing: 6) {
                        if isParsingPrompt {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(.white)
                        }
                        Text(isParsingPrompt ? "Reading instructions..." : "Fill")
                            .font(.subheadline.bold())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .disabled(isParsingPrompt)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
        }
        .frame(width: 280)
        .fixedSize(horizontal: false, vertical: true)
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

                // Excludes the inning above so a single unfilled slot isn't listed
                // twice — the same split the toolbar badge makes between
                // currentInningIssueCount and gameWideIssueCount.
                let missingPositionWarnings = computeMissingPositionWarnings()
                Section(header: ComplianceRulesHeader(title: "Other Innings")) {
                    if missingPositionWarnings.isEmpty {
                        Label("No other inning is missing a position.", systemImage: "checkmark.circle.fill")
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
                        Label("No game-wide fair-play issues.", systemImage: "checkmark.circle.fill")
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
        // Back-to-back bench is a game-wide rule and now lives in
        // computeOverallWarnings(), which names the innings itself. Listing it
        // here as well would double-report the pair that touches this inning.
        return warnings
    }

    /// Open slots in every inning *except* the one the sheet is opened on —
    /// that inning has its own section above.
    func computeMissingPositionWarnings() -> [String] {
        var warnings: [String] = []
        let activePlayers = store.lineup.activePlayers(from: store.players)
        let config = store.fairPlayConfig
        for i in store.lineup.innings.indices where i != inning {
            guard !store.lineup.innings[i].assignments.isEmpty else { continue }
            let open = store.lineup.openPositions(inning: i, players: activePlayers, config: config)
            guard !open.isEmpty else { continue }
            let posNames = open.map { $0.displayName }.joined(separator: ", ")
            warnings.append("Inning \(i + 1): \(posNames)")
        }
        return warnings
    }

    /// One line per player per broken rule, built from the same
    /// `Lineup.fairPlayFindings` the toolbar badge counts — so the badge and
    /// this list can't disagree, and a rule the coach switched off produces
    /// nothing rather than being re-checked here.
    ///
    /// Back-to-back bench is included. It used to appear only in the selected
    /// inning's section, so a violation in innings 4-5 counted toward the badge
    /// and then showed up nowhere in the sheet the badge opens.
    func computeOverallWarnings() -> [String] {
        let config = store.fairPlayConfig
        let findings = store.lineup.fairPlayFindings(players: store.players, config: config)
        var warnings: [String] = []

        for player in findings.withoutInfield {
            warnings.append("\(player.displayName): no infield inning assigned")
        }
        for player in findings.withoutOutfield {
            warnings.append("\(player.displayName): no outfield inning assigned")
        }
        let minimum = findings.minimumFieldingInnings
        for player in findings.underFieldingMinimum {
            warnings.append("\(player.displayName): under \(Plural.innings(minimum)) fielded")
        }
        for player in findings.backToBackBench {
            let pairs = store.lineup.backToBackBenchInnings(player: player)
                .map { "\($0.first) & \($0.second)" }
                .joined(separator: ", ")
            warnings.append("\(player.displayName): back-to-back bench (inn \(pairs))")
        }
        for player in findings.catcherThenPitcher {
            warnings.append("\(player.displayName): caught \(config.catcherToPitcherThreshold)+ innings before pitching (C to P restriction)")
        }
        for player in findings.pitcherThenCatcher {
            warnings.append("\(player.displayName): pitched \(config.pitcherToCatcherThreshold)+ innings before catching (P to C restriction)")
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
                warnings.append("\(player.displayName): available \(Self.restDateFormatter.string(from: date))")
            case .unknownAge:
                warnings.append("\(player.displayName): league age not set, eligibility unknown")
            }
        }
        return warnings
    }

    /// Static so a roster full of resting pitchers doesn't build a formatter each.
    private static let restDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE M/d"
        return f
    }()
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
    @State private var showingDefaultTemplateWarning = false
    /// Set when the coach confirms the override, so the follow-on rule warnings
    /// (bench, pitch eligibility) still get their turn instead of being skipped.
    @State private var defaultOverrideConfirmed = false
    @State private var showingRemoveDefaultWarning = false

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
                case .mustRest:
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
                            // Clearing a template-assigned cell is an override too.
                            if store.isDefaultTemplateAssignment(player: player, inning: inning) {
                                showingRemoveDefaultWarning = true
                            } else {
                                store.removeAssignment(player: player, inning: inning)
                                dismiss()
                            }
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
            .alert("Override Default Template?", isPresented: $showingDefaultTemplateWarning) {
                Button("Change Anyway", role: .destructive) {
                    defaultOverrideConfirmed = true
                    let pos = pendingPosition
                    // Deferred so this alert finishes dismissing before any
                    // follow-on rule warning tries to present.
                    DispatchQueue.main.async {
                        if let pos { assignPosition(pos) }
                    }
                }
                Button("Cancel", role: .cancel) { pendingPosition = nil }
            } message: {
                Text(defaultOverrideMessage)
            }
            .alert("Override Default Template?", isPresented: $showingRemoveDefaultWarning) {
                Button("Remove Anyway", role: .destructive) {
                    store.removeAssignment(player: player, inning: inning)
                    dismiss()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("\(player.firstName) was assigned here by “\(store.defaultTemplateName ?? "your default template")”. Clearing this spot overrides your default template for this game. Continue?")
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
        // Checked first: departing from the coach's standing plan is a bigger
        // decision than the per-rule warnings, and confirming it still leaves
        // those warnings to be answered on the way through.
        if !defaultOverrideConfirmed, overridesDefaultTemplate(pos) {
            pendingPosition = pos
            showingDefaultTemplateWarning = true
            return
        }
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

    /// True when this move would undo something the default template set up —
    /// either by moving this player out of their template cell, or by bumping
    /// another player out of theirs. Bench and absent hold multiple players, so
    /// they can't displace anyone.
    private func overridesDefaultTemplate(_ pos: FieldPosition) -> Bool {
        guard store.lineup.innings[inning].position(for: player) != pos else { return false }

        if store.isDefaultTemplateAssignment(player: player, inning: inning) { return true }

        if !pos.isNonFielding,
           let occupant = store.lineup.innings[inning].player(at: pos, in: store.players),
           occupant.id != player.id,
           store.isDefaultTemplateAssignment(inning: inning, position: pos) {
            return true
        }
        return false
    }

    private var defaultOverrideMessage: String {
        let templateName = store.defaultTemplateName ?? "your default template"
        guard let pos = pendingPosition else { return "" }

        if store.isDefaultTemplateAssignment(player: player, inning: inning),
           let current = store.lineup.innings[inning].position(for: player) {
            return "“\(templateName)” has \(player.firstName) at \(current.displayName) for inning \(inning + 1). Moving them to \(pos.displayName) overrides your default template for this game. Continue?"
        }
        if let occupant = store.lineup.innings[inning].player(at: pos, in: store.players) {
            return "“\(templateName)” has \(occupant.firstName) at \(pos.displayName) for inning \(inning + 1). Putting \(player.firstName) there overrides your default template for this game. Continue?"
        }
        return "This overrides “\(templateName)” for this game. Continue?"
    }

    private func commitAssignment(_ pos: FieldPosition) {
        store.assignPosition(player: player, inning: inning, position: pos)
        dismiss()
    }
}

// MARK: - Player Picker Sheet (position-led)

/// Picks which player fills a given position for one inning. This is the inverse
/// of PositionPickerView: the position is fixed and the coach chooses the player.
/// Used by the position-led By Inning list. Warning and assignment semantics
/// mirror PositionPickerView so both flows behave identically.
struct PlayerPickerView: View {
    @EnvironmentObject var store: LineupStore
    @EnvironmentObject var purchaseManager: PurchaseManager
    @Environment(\.dismiss) var dismiss

    let position: FieldPosition
    /// For a bench row: the player currently in that bench slot (nil when adding
    /// a new player to the bench). Ignored for field positions.
    let benchSlotOccupant: Player?
    let inning: Int

    @State private var showingConsecutiveBenchWarning = false
    @State private var showingPitchEligibilityWarning = false
    @State private var showingNeverPositionWarning = false
    @State private var pendingPlayer: Player? = nil
    @State private var showingDefaultTemplateWarning = false
    /// Set when the coach confirms the override, so the follow-on rule warnings
    /// still get their turn instead of being skipped.
    @State private var defaultOverrideConfirmed = false
    @State private var showingRemoveDefaultWarning = false

    /// Player currently in this position this inning (field positions only).
    /// Bench and absent slots hold multiple players, so the occupant is whoever
    /// was tapped (nil when adding via "+ Bench" / "+ Absent").
    private var currentOccupant: Player? {
        position.isNonFielding
            ? benchSlotOccupant
            : store.lineup.innings[inning].player(at: position, in: store.players)
    }

    /// Candidates for this slot: all active (present) players in display order.
    /// The row annotates where each one currently is this inning so the coach can
    /// see the trade before making it.
    private var candidates: [Player] {
        let displayed = store.lineup.displayPlayers(from: store.players)
        return displayed.filter { !store.lineup.isAbsent($0) }
    }

    private func pitchWarning(for player: Player) -> PitchEligibilityStatus? {
        guard position == .pitcher, store.pitchingConfig.rulesEnabled else { return nil }
        let status = PitchEligibilityEngine.status(
            for: player, gameLogs: store.gameLogs, config: store.pitchingConfig,
            referenceDate: store.lineup.gameDate
        )
        return status.blocksAssignment ? status : nil
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(candidates) { player in
                        playerRow(player)
                    }
                } header: {
                    Text(position.isNonFielding ? "Choose a player" : "Choose a player for \(position.displayName)")
                }

                if let occupant = currentOccupant {
                    Section {
                        Button(role: .destructive) {
                            // Clearing a template-assigned cell is an override too.
                            if store.isDefaultTemplateAssignment(player: occupant, inning: inning) {
                                showingRemoveDefaultWarning = true
                            } else {
                                store.removeAssignment(player: occupant, inning: inning)
                                dismiss()
                            }
                        } label: {
                            Label(position.isBench ? "Remove from Bench" : "Clear Position", systemImage: "xmark.circle")
                        }
                    }
                }
            }
            .navigationTitle(position.isBench ? "Bench – Inning \(inning + 1)" : "\(position.displayName) – Inning \(inning + 1)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Back-to-Back Bench Warning", isPresented: $showingConsecutiveBenchWarning) {
                Button("Assign Bench Anyway", role: .destructive) {
                    if let player = pendingPlayer { commitAssignment(player) }
                }
                Button("Cancel", role: .cancel) { pendingPlayer = nil }
            } message: {
                if let player = pendingPlayer {
                    Text("\(player.firstName) would be on the bench for two consecutive innings. You can still assign bench if needed.")
                }
            }
            .alert("Pitch Eligibility Warning", isPresented: $showingPitchEligibilityWarning) {
                Button("Assign Pitcher Anyway", role: .destructive) {
                    if let player = pendingPlayer { commitAssignment(player) }
                }
                Button("Cancel", role: .cancel) { pendingPlayer = nil }
            } message: {
                if let player = pendingPlayer, let status = pitchWarning(for: player) {
                    Text("\(player.firstName) may not be eligible to pitch. \(status.displayLabel). You can still assign this position if needed.")
                }
            }
            .alert("Position Preference Warning", isPresented: $showingNeverPositionWarning) {
                Button("Assign Anyway", role: .destructive) {
                    if let player = pendingPlayer { commitAssignment(player) }
                }
                Button("Cancel", role: .cancel) { pendingPlayer = nil }
            } message: {
                if let player = pendingPlayer {
                    Text("\(player.firstName) is marked Never for \(position.displayName). You can still assign this position if needed.")
                }
            }
            .alert("Override Default Template?", isPresented: $showingDefaultTemplateWarning) {
                Button("Change Anyway", role: .destructive) {
                    defaultOverrideConfirmed = true
                    let player = pendingPlayer
                    // Deferred so this alert finishes dismissing before any
                    // follow-on rule warning tries to present.
                    DispatchQueue.main.async {
                        if let player { assign(player) }
                    }
                }
                Button("Cancel", role: .cancel) { pendingPlayer = nil }
            } message: {
                Text(defaultOverrideMessage)
            }
            .alert("Override Default Template?", isPresented: $showingRemoveDefaultWarning) {
                Button("Remove Anyway", role: .destructive) {
                    if let occupant = currentOccupant {
                        store.removeAssignment(player: occupant, inning: inning)
                    }
                    dismiss()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("\(currentOccupant?.firstName ?? "This player") was assigned here by “\(store.defaultTemplateName ?? "your default template")”. Clearing this spot overrides your default template for this game. Continue?")
            }
        }
    }

    @ViewBuilder
    private func playerRow(_ player: Player) -> some View {
        let currentPos = store.lineup.innings[inning].position(for: player)
        let isHere = position.isBench
            ? (currentPos == .bench && player.id == benchSlotOccupant?.id)
            : (currentPos == position)
        let prefTier = purchaseManager.isPro ? player.positionPreferences[position] : nil
        // Never-tier players are shown, not hidden, and flagged red like other
        // overridable warnings so the coach can still emergency-assign them.
        let isNeverHere = purchaseManager.isPro && !position.isBench && prefTier == .never
        let warning = pitchWarning(for: player)

        Button {
            assign(player)
        } label: {
            HStack(spacing: 10) {
                if !player.number.isEmpty {
                    Text("#\(player.number)")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                        .frame(width: 34, alignment: .leading)
                } else {
                    Text("—")
                        .font(.caption.bold())
                        .foregroundStyle(.tertiary)
                        .frame(width: 34, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(player.displayName)
                            .foregroundColor(.primary)
                        if let prefTier, prefTier == .emergency || prefTier == .never {
                            Circle()
                                .fill(prefTier.color)
                                .frame(width: 7, height: 7)
                        }
                        if isNeverHere || warning != nil {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                    if let currentPos, !isHere {
                        Text("Currently: \(currentPos.rawValue)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    if isNeverHere {
                        Text("Marked Never for \(position.displayName)")
                            .font(.caption2)
                            .foregroundColor(.red)
                    }
                    if let warning {
                        Text(warning.displayLabel)
                            .font(.caption2)
                            .foregroundColor(.red)
                    }
                }

                Spacer()

                if isHere {
                    Image(systemName: "checkmark").foregroundColor(.blue)
                }
            }
        }
        .listRowBackground(isNeverHere || warning != nil ? Color.red.opacity(0.06) : nil)
    }

    private func assign(_ player: Player) {
        // Checked first, for the same reason as in PositionPickerView: the
        // standing plan outranks the per-rule warnings, which still run after.
        if !defaultOverrideConfirmed, overridesDefaultTemplate(player) {
            pendingPlayer = player
            showingDefaultTemplateWarning = true
            return
        }
        // Bench with the no-consecutive-bench rule on: warn first.
        if position == .bench
            && store.fairPlayConfig.noConsecutiveBench
            && store.lineup.hasConsecutiveBench(player: player, assigningBenchToInning: inning) {
            pendingPlayer = player
            showingConsecutiveBenchWarning = true
            return
        }
        // Ineligible pitcher: warn but allow override.
        if position == .pitcher, pitchWarning(for: player) != nil {
            pendingPlayer = player
            showingPitchEligibilityWarning = true
            return
        }
        // Marked Never for this position: warn but allow override.
        if purchaseManager.isPro,
           !position.isBench,
           player.positionPreferences[position] == .never {
            pendingPlayer = player
            showingNeverPositionWarning = true
            return
        }
        commitAssignment(player)
    }

    /// True when filling this slot with `player` would undo the default
    /// template — either by displacing whoever it put in this slot, or by
    /// pulling `player` out of the slot it gave them elsewhere this inning.
    private func overridesDefaultTemplate(_ player: Player) -> Bool {
        guard store.lineup.innings[inning].position(for: player) != position else { return false }

        if !position.isNonFielding,
           let occupant = store.lineup.innings[inning].player(at: position, in: store.players),
           occupant.id != player.id,
           store.isDefaultTemplateAssignment(inning: inning, position: position) {
            return true
        }

        if store.isDefaultTemplateAssignment(player: player, inning: inning) { return true }

        return false
    }

    private var defaultOverrideMessage: String {
        let templateName = store.defaultTemplateName ?? "your default template"
        guard let player = pendingPlayer else { return "" }

        if let occupant = store.lineup.innings[inning].player(at: position, in: store.players),
           occupant.id != player.id,
           store.isDefaultTemplateAssignment(inning: inning, position: position) {
            return "“\(templateName)” has \(occupant.firstName) at \(position.displayName) for inning \(inning + 1). Putting \(player.firstName) there overrides your default template for this game. Continue?"
        }
        if let current = store.lineup.innings[inning].position(for: player) {
            return "“\(templateName)” has \(player.firstName) at \(current.displayName) for inning \(inning + 1). Moving them to \(position.displayName) overrides your default template for this game. Continue?"
        }
        return "This overrides “\(templateName)” for this game. Continue?"
    }

    private func commitAssignment(_ player: Player) {
        store.assignPosition(player: player, inning: inning, position: position)
        pendingPlayer = nil
        dismiss()
    }
}

// MARK: - Pitch Availability Helpers
//
// Shared across DefensiveGridView and PositionSummaryView.
// Computes how many pitches a player has remaining today given their
// daily max and window total.

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
