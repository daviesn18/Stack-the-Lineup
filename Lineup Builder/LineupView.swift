import SwiftUI
import TipKit

struct LineupView: View {
    @EnvironmentObject var store: LineupStore
    @EnvironmentObject var purchaseManager: PurchaseManager
    @Environment(\.verticalSizeClass) var verticalSizeClass
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Binding var showingArchive: Bool

    /// True when the Lineup tab is the one on screen. The iPad dashboard
    /// embeds this view and leaves it at the default; its tour anchors are
    /// stood down separately by the `horizontalSizeClass != .regular` guard.
    var isTourTabActive: Bool = true

    @State private var generatedPDF: PDFDocument? = nil
    @State private var showingTips = false
    @State private var lockedPDF: PDFDocument? = nil
    @State private var showingScheduleImport = false
    @State private var showingSchedulePicker = false
    @State private var scheduleImportToast: String? = nil
    @State private var showingTemplatePicker = false
    @State private var showingGameInfoEditor = false

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

    private var isReadOnly: Bool { store.activeTeam.isReadOnly }

    // MARK: - Fair Play Summary (drives the inline header chip)
    //
    // Read-only summary of the defensive assignments that live on the
    // Positions tab. If a coach wants the per-rule detail, they go to the
    // Positions tab, which is where the assignments are actually changed.

    /// True when a fair-play summary is meaningful — i.e. there are active
    /// players and at least one inning has assignments to evaluate.
    private var fairPlayEvaluable: Bool {
        let activePlayers = store.lineup.activePlayers(from: store.players)
        return !activePlayers.isEmpty
            && store.lineup.innings.contains(where: { !$0.assignments.isEmpty })
    }

    /// Count of active players implicated in any fair-play warning.
    private var fairPlayWarningCount: Int {
        store.lineup
            .fairPlayFindings(players: store.players, config: store.fairPlayConfig)
            .implicatedPlayerIDs
            .count
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
            // MARK: - Read-Only Banner
            if isReadOnly {
                Section {
                    ReadOnlyBanner()
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }

            // MARK: - Copied-From-History Banner
            // Set when the coach copies an archived game from History. Stays
            // up until they finalize (or archive), since "review and finalize"
            // is the thing it's asking for.
            if let source = store.copiedFromGameOpponent {
                Section {
                    CopiedFromGameBanner(source: source)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }

            // MARK: - Compact Game Card
            // Summary row (tap to edit date / opponent / status) plus a
            // Schedule / Template split-button row beneath a hairline.
            Section {
                GameSummaryCard(
                    gameDate: store.lineup.gameDate,
                    opponent: store.lineup.opponent,
                    isFinalized: store.lineup.status == .finalized,
                    showSchedule: !isReadOnly,
                    showTemplate: !isReadOnly,
                    onTapSummary: { showingGameInfoEditor = true },
                    onTapSchedule: { showingSchedulePicker = true },
                    onTapTemplate: { showingTemplatePicker = true }
                )
                .tourTip(Tour.lineup.currentTip as? LineupGameInfoTip, arrowEdge: .top,
                         enabled: isTourTabActive)
                .tourTip(Tour.secondGame.currentTip as? ReuseApplyTemplateTip, arrowEdge: .top,
                         enabled: isTourTabActive)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            // MARK: - Batting Order & Availability
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
                HStack(spacing: 8) {
                    Text("Batting Order")
                    FairPlayChip(
                        evaluable: fairPlayEvaluable,
                        warningCount: fairPlayWarningCount
                    )
                    Spacer()
                    if !orderedPlayers.isEmpty && !isReadOnly {
                        EditButton()
                            .font(.caption)
                    }
                }
                .tourTip(Tour.lineup.currentTip as? LineupBattingOrderTip, arrowEdge: .bottom,
                         enabled: horizontalSizeClass != .regular && isTourTabActive)
                .tourTip(Tour.lineup.currentTip as? LineupAbsentTip, arrowEdge: .bottom,
                         enabled: horizontalSizeClass != .regular && isTourTabActive)
            } footer: {
                if !unorderedPlayers.isEmpty {
                    Text("Tap + to add players to the batting order, then drag to reorder.")
                } else if !store.players.isEmpty && orderedPlayers.isEmpty {
                    Text("Tap + next to each player above to add them to the batting order.")
                }
            }
        }
        .sheet(item: $generatedPDF) { pdf in
            PDFPreviewView(document: pdf)
        }
        .fullScreenCover(item: $lockedPDF) { pdf in
            ProGate(source: "pdf_export", navTitle: "Coaches Guide") {
                PDFKitView(data: pdf.data)
            }
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
        .sheet(isPresented: $showingGameInfoEditor) {
            GameInfoEditorView()
                .environmentObject(store)
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
        .sheet(isPresented: $showingTemplatePicker) {
            TemplatePickerView()
                .environmentObject(store)
        }
        // Pinned export bar — always one tap from the batting order.
        // Content scrolls underneath it; the schedule-import toast floats above.
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if let toast = scheduleImportToast {
                    Text(toast)
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color(.label)))
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                ExportBar(
                    isPro: purchaseManager.isPro,
                    onExportBattingOrder: exportBattingOrder,
                    onExportCoachesGuide: exportCoachesGuide
                )
                .tourTip(Tour.lineup.currentTip as? LineupExportTip, arrowEdge: .bottom,
                         enabled: isTourTabActive)
            }
            .animation(.spring(duration: 0.35), value: scheduleImportToast)
        }
        .navigationTitle("Stack the Lineup")
        .navigationBarTitleDisplayMode(verticalSizeClass == .compact ? .inline : .large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    Button { showingTips = true } label: {
                        Image(systemName: "info.circle")
                    }
                    if !isReadOnly {
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
        }
    }

    // MARK: - Export Actions

    private func exportBattingOrder() {
        let doc = PDFGenerator.generate(
            type: .battingOrder,
            lineup: store.lineup,
            players: store.players,
            teamName: store.teamName,
            teamColor: store.teamColor
        )
        generatedPDF = doc
        Analytics.signal("pdf.exported", parameters: ["type": "battingOrder"])
    }

    private func exportCoachesGuide() {
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
    }
}

// MARK: - Copied From Game Banner

/// Shown at the top of the Lineup tab after the coach copies an archived game
/// from History. Green rather than the orange used for read-only: this is a
/// successful action landing, not a restriction.
struct CopiedFromGameBanner: View {
    /// Already formatted for the sentence, e.g. "vs Eagles".
    let source: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            Text("Copied from \(source). Review and finalize for game day.")
                .font(.subheadline)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.green.opacity(0.12))
        )
    }
}

// MARK: - Game Summary Card

/// Compact game card: a tappable summary row (date · opponent · status) over a
/// hairline, with a Schedule / Template split-button row beneath.
struct GameSummaryCard: View {
    let gameDate: Date
    let opponent: String
    let isFinalized: Bool
    let showSchedule: Bool
    let showTemplate: Bool
    let onTapSummary: () -> Void
    let onTapSchedule: () -> Void
    let onTapTemplate: () -> Void

    private var dateText: String {
        gameDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    var body: some View {
        VStack(spacing: 0) {
            // Summary row
            Button(action: onTapSummary) {
                HStack(spacing: 12) {
                    Image(systemName: "calendar")
                        .font(.system(size: 20))
                        .foregroundColor(.blue)

                    VStack(alignment: .leading, spacing: 4) {
                        // Line 1 — date + opponent. Trailing spacer pins the
                        // text to the leading edge so it starts on the same
                        // left margin as the pill below.
                        HStack(spacing: 6) {
                            Text(dateText)
                                .font(.headline)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                                .fixedSize()

                            // Placeholder when no opponent is set, so the row
                            // reads as editable rather than looking empty.
                            Text(opponent.isEmpty ? "· Add opponent" : "· \(opponent)")
                                .font(.body)
                                .foregroundColor(opponent.isEmpty ? Color(.tertiaryLabel) : .secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)

                            Spacer(minLength: 0)
                        }

                        // Line 2 — status pill, hugging its content at the
                        // same leading edge.
                        StatusPill(isFinalized: isFinalized)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(Color(.tertiaryLabel))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .frame(maxWidth: .infinity, alignment: .leading)
                // Make the whole row hit-testable, not just the text/glyphs.
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Split-button row (only when at least one half is shown)
            if showSchedule || showTemplate {
                Divider()
                    .padding(.leading, 16)

                HStack(spacing: 0) {
                    if showSchedule {
                        SplitButton(
                            systemImage: "calendar",
                            title: "Schedule",
                            action: onTapSchedule
                        )
                    }

                    if showSchedule && showTemplate {
                        Divider()
                            .frame(height: 24)
                    }

                    if showTemplate {
                        SplitButton(
                            systemImage: "square.grid.2x2",
                            title: "Template",
                            action: onTapTemplate
                        )
                    }
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }
}

/// Draft / Finalized capsule pill for the summary row.
struct StatusPill: View {
    let isFinalized: Bool

    var body: some View {
        if isFinalized {
            HStack(spacing: 3) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                Text("Done")
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundColor(.green)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.green.opacity(0.12)))
        } else {
            Text("Draft")
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .foregroundColor(.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color(.systemGray5)))
        }
    }
}

/// One half of the Schedule / Template split row.
struct SplitButton: View {
    let systemImage: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.subheadline)
                Text(title)
                    .font(.subheadline.weight(.medium))
            }
            .foregroundColor(.blue)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Fair Play Chip

/// Inline, non-tappable summary of fair-play status shown in the Batting Order
/// header. Reflects the defensive assignments on the Positions tab; coaches
/// make changes there.
struct FairPlayChip: View {
    let evaluable: Bool
    let warningCount: Int

    var body: some View {
        if evaluable {
            if warningCount == 0 {
                HStack(spacing: 3) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Fair play OK")
                }
                .font(.footnote.weight(.semibold))
                .foregroundColor(.green)
                .textCase(nil)
                .animation(.easeInOut(duration: 0.2), value: warningCount)
            } else {
                HStack(spacing: 3) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text("^[\(warningCount) warning](inflect: true)")
                }
                .font(.footnote.weight(.semibold))
                .foregroundColor(.orange)
                .textCase(nil)
                .animation(.easeInOut(duration: 0.2), value: warningCount)
            }
        }
    }
}

// MARK: - Export Bar

/// Pinned bottom bar with the two PDF export buttons. Sits above the tab bar,
/// with content scrolling underneath.
struct ExportBar: View {
    let isPro: Bool
    let onExportBattingOrder: () -> Void
    let onExportCoachesGuide: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // Primary — Batting Order
            Button(action: onExportBattingOrder) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                    Text("Batting Order")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Color.blue)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(.plain)

            // Secondary — Coaches Guide (Pro-gated).
            // Matches the primary button's solid fill for clarity; the PRO
            // badge is what distinguishes the gated export for non-Pro users.
            Button(action: onExportCoachesGuide) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.richtext.fill")
                    Text("Coaches Guide")
                    if !isPro {
                        ProBadge(inverted: true)
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Color.blue)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 14)
        // Opaque base so scrolling list rows do not show through the bar.
        .background(
            Color(.systemGroupedBackground)
                .ignoresSafeArea(edges: .bottom)
        )
        // Short fade strip above the bar so rows dissolve into it rather than
        // hard-cutting at the top edge.
        .overlay(alignment: .top) {
            LinearGradient(
                colors: [
                    Color(.systemGroupedBackground).opacity(0),
                    Color(.systemGroupedBackground)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 18)
            .offset(y: -18)
        }
    }
}

// MARK: - Roster Row

struct RosterRow: View {
    @EnvironmentObject var store: LineupStore
    let player: Player
    let index: Int?
    var isAbsent: Bool = false
    var isReadOnly: Bool = false
    var onAdd: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let i = index {
                    Text("\(i).")
                        .font(.headline)
                        .foregroundColor(isAbsent ? .secondary : .primary)
                } else if !isAbsent && !isReadOnly {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.green)
                        .font(.title3)
                        .onTapGesture { onAdd?() }
                } else if !isAbsent {
                    // Read-only placeholder — keeps row alignment consistent
                    Image(systemName: "minus.circle")
                        .foregroundColor(Color(.systemGray4))
                        .font(.title3)
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
            .disabled(isReadOnly)
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
    /// When true, renders white-on-blue for placement on a solid blue surface.
    /// Default is blue-on-white for placement on neutral backgrounds.
    var inverted: Bool = false

    var body: some View {
        Text("PRO")
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(inverted ? .blue : .white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(inverted ? Color.white : Color.blue)
            .cornerRadius(5)
    }
}
