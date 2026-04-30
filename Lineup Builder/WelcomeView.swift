import SwiftUI

// MARK: - Welcome / Tutorial View

struct WelcomeView: View {
    @Environment(\.dismiss) var dismiss
    @State private var currentPage = 0

    let pages: [TutorialPage] = [
        TutorialPage(
            icon: "person.3.fill",
            iconColor: .blue,
            title: "Build Your Roster",
            description: "Add players with their names and jersey numbers on the Players tab. Tap \"Add Player\" to get started. You can edit or remove players at any time.",
            systemImage: "plus.circle.fill"
        ),
        TutorialPage(
            icon: "list.number",
            iconColor: .green,
            title: "Set Your Batting Order",
            description: "On the Lineup tab, tap + next to each player to add them to the batting order, then drag to reorder. Toggle the switch next to any player to mark them fully absent for the game.",
            systemImage: "arrow.up.arrow.down"
        ),
        TutorialPage(
            icon: "baseball.diamond.bases",
            iconColor: .orange,
            title: "Assign Positions",
            description: "On the Positions tab, select an inning and tap any player to assign their defensive position. Tap the bolt icon to auto-fill open slots — Auto-Fill respects each player's position preferences when filling. Switch to Summary view to see and edit all innings in one grid.",
            systemImage: "bolt.fill"
        ),
        TutorialPage(
            icon: "star.circle.fill",
            iconColor: .yellow,
            title: "Set Position Preferences",
            description: "In each player's edit screen, tag positions as Strength, Capable, Emergency, or Never. Auto-Fill uses these to place players in the right spots automatically — the more accurately you tag each player, the smarter your lineups get.",
            systemImage: "wand.and.stars"
        ),
        TutorialPage(
            icon: "exclamationmark.triangle.fill",
            iconColor: .red,
            title: "Fair Play Warnings",
            description: "The app enforces four rules: every player gets at least 1 infield inning, 1 outfield inning, no back-to-back bench innings, and a minimum of 4 innings fielded per game. Assign ABS on the Positions tab for individual innings a player misses — they're still exempt from the 4-inning minimum but need 1 infield and 1 outfield.",
            systemImage: "shield.checkered"
        ),
        TutorialPage(
            icon: "checkmark.circle.fill",
            iconColor: .green,
            title: "Finalize Your Lineup",
            description: "When your defensive assignments are set, tap \"Finalize lineup\" on the Positions tab. The Lineup tab shows your status as Finalized — any edit automatically reverts it to Draft so you always know where things stand.",
            systemImage: "checkmark.seal.fill"
        ),
        TutorialPage(
            icon: "clock.arrow.circlepath",
            iconColor: .teal,
            title: "Game History",
            description: "After each game, tap the Archive button to save the lineup to your history. Set how many innings were actually played so stats stay accurate. View past games and AI Coaching Insights anytime in the History tab.",
            systemImage: "archivebox.fill"
        ),
        TutorialPage(
            icon: "doc.text.fill",
            iconColor: .purple,
            title: "Export & Manage Teams",
            description: "Export a Batting Order or Coaches Guide PDF from the Lineup tab. Tap the Team Name row on the Players tab to set your team name and color — both appear on exported PDFs. Managing multiple teams? Tap Add Team to create a new team with its own roster and history.",
            systemImage: "square.and.arrow.up"
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Page indicator dots
            HStack(spacing: 8) {
                ForEach(0..<pages.count, id: \.self) { index in
                    Circle()
                        .fill(index == currentPage ? Color.blue : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                        .animation(.easeInOut, value: currentPage)
                }
            }
            .padding(.top, 20)
            .padding(.bottom, 10)

            // Page content
            TabView(selection: $currentPage) {
                ForEach(0..<pages.count, id: \.self) { index in
                    TutorialPageView(page: pages[index])
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            // Navigation buttons
            HStack(spacing: 20) {
                if currentPage > 0 {
                    Button {
                        withAnimation { currentPage -= 1 }
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                            .font(.body.bold())
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button("") {}
                        .buttonStyle(.bordered)
                        .opacity(0)
                }

                Spacer()

                if currentPage < pages.count - 1 {
                    Button {
                        withAnimation { currentPage += 1 }
                    } label: {
                        Label("Next", systemImage: "chevron.right")
                            .font(.body.bold())
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button {
                        UserDefaults.standard.set(true, forKey: "hasCompletedTutorial")
                        dismiss()
                    } label: {
                        Label("Get Started", systemImage: "checkmark")
                            .font(.body.bold())
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
            }
            .padding()
        }
        .interactiveDismissDisabled()
    }
}

// MARK: - Tutorial Page Model

struct TutorialPage {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    let systemImage: String
}

// MARK: - Tutorial Page View

struct TutorialPageView: View {
    let page: TutorialPage

    var body: some View {
        VStack(spacing: 30) {
            Spacer()

            ZStack {
                Circle()
                    .fill(page.iconColor.opacity(0.15))
                    .frame(width: 140, height: 140)
                Image(systemName: page.icon)
                    .font(.system(size: 60))
                    .foregroundColor(page.iconColor)
            }
            .padding(.top, 40)

            Text(page.title)
                .font(.system(size: 28, weight: .bold))
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Text(page.description)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
                .fixedSize(horizontal: false, vertical: true)

            Image(systemName: page.systemImage)
                .font(.system(size: 40))
                .foregroundColor(page.iconColor.opacity(0.5))
                .padding(.top, 10)

            Spacer()
            Spacer()
        }
    }
}

// MARK: - First Game Checklist
// A dismissible getting-started card shown on the Lineup tab until the coach
// completes their first game. Progress is tracked via UserDefaults flags that
// are already set as part of normal app flow — no extra instrumentation needed.

struct FirstGameChecklist: View {
    @EnvironmentObject var store: LineupStore
    @AppStorage("hasCompletedChecklist") private var hasCompletedChecklist = false
    @State private var isDismissed = false

    // Step completion derived from real app state
    private var hasPlayers: Bool { !store.players.isEmpty }
    private var hasBattingOrder: Bool { !store.lineup.battingOrder.isEmpty }
    private var hasPositions: Bool {
        store.lineup.innings.contains { !$0.assignments.isEmpty }
    }
    private var hasArchivedGame: Bool { !store.gameLogs.isEmpty }

    private var completedCount: Int {
        [hasPlayers, hasBattingOrder, hasPositions, hasArchivedGame].filter { $0 }.count
    }

    private var allDone: Bool { completedCount == 4 }

    var body: some View {
        // Auto-dismiss permanently once all steps are done
        let shouldShow = !hasCompletedChecklist && !isDismissed

        if shouldShow {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Getting Started")
                            .font(.subheadline.bold())
                        Text("\(completedCount) of 4 steps complete")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            if allDone {
                                hasCompletedChecklist = true
                            } else {
                                isDismissed = true
                            }
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(Color(.tertiaryLabel))
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                }

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(.systemGray5))
                            .frame(height: 5)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(allDone ? Color.green : Color.blue)
                            .frame(width: geo.size.width * CGFloat(completedCount) / 4.0, height: 5)
                            .animation(.easeInOut(duration: 0.4), value: completedCount)
                    }
                }
                .frame(height: 5)

                VStack(alignment: .leading, spacing: 8) {
                    ChecklistRow(label: "Add players to your roster", isDone: hasPlayers)
                    ChecklistRow(label: "Build your batting order", isDone: hasBattingOrder)
                    ChecklistRow(label: "Assign defensive positions", isDone: hasPositions)
                    ChecklistRow(label: "Archive your first game", isDone: hasArchivedGame)
                }

                if allDone {
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            hasCompletedChecklist = true
                        }
                    } label: {
                        Text("You're all set! Dismiss")
                            .font(.caption.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color(.systemGray4), lineWidth: 0.5)
            )
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}

// MARK: - Checklist Row

private struct ChecklistRow: View {
    let label: String
    let isDone: Bool

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(isDone ? Color.green : Color(.systemGray5))
                    .frame(width: 22, height: 22)
                Image(systemName: isDone ? "checkmark" : "circle")
                    .font(.system(size: isDone ? 11 : 14, weight: .bold))
                    .foregroundColor(isDone ? .white : Color(.systemGray3))
            }
            .animation(.easeInOut(duration: 0.3), value: isDone)

            Text(label)
                .font(.callout)
                .foregroundColor(isDone ? .secondary : .primary)
                .strikethrough(isDone, color: .secondary)
        }
    }
}

// MARK: - Auto-Fill Context Tip
// One-time popover shown the first time a Pro user opens the Positions tab
// with players assigned. Highlights that Auto-Fill is smarter when position
// preferences are set. Shown once, never again.

struct AutoFillContextTip: View {
    @Binding var isPresented: Bool
    let onGoToPlayers: () -> Void

    var body: some View {
        if isPresented {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack(alignment: .top, spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.12))
                            .frame(width: 40, height: 40)
                        Image(systemName: "bolt.fill")
                            .foregroundColor(.blue)
                            .font(.system(size: 18))
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Make Auto-Fill Smarter")
                            .font(.subheadline.bold())
                        Text("Auto-Fill uses position preferences for each player to buid better rosters.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Button {
                        withAnimation { isPresented = false }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(Color(.tertiaryLabel))
                            .font(.body)
                    }
                    .buttonStyle(.plain)
                }
                .padding(14)

                Divider()

                // Tier breakdown
                VStack(alignment: .leading, spacing: 10) {
                    Text("How preferences work:")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)

                    TierExplanationRow(tier: .strength,  description: "Tried first when filling a position")
                    TierExplanationRow(tier: .capable,   description: "Used if no Strength player is available")
                    TierExplanationRow(tier: .emergency, description: "Last resort — used only if needed")
                    TierExplanationRow(tier: .never,     description: "Never assigned to this position")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

                Divider()

                // CTA
                Button {
                    withAnimation { isPresented = false }
                    onGoToPlayers()
                } label: {
                    HStack {
                        Image(systemName: "person.crop.circle.badge.plus")
                        Text("Set Preferences on the Players Tab")
                            .font(.subheadline.bold())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .foregroundColor(.white)
                }

                Button {
                    withAnimation { isPresented = false }
                } label: {
                    Text("Got it, maybe later")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
            }
            .background(Color(.systemBackground))
            .cornerRadius(14)
            .shadow(color: .black.opacity(0.12), radius: 16, x: 0, y: 4)
            .padding(.horizontal, 20)
            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
        }
    }
}

// MARK: - Tier Explanation Row

private struct TierExplanationRow: View {
    let tier: PositionPreferenceTier
    let description: String

    var body: some View {
        HStack(spacing: 8) {
            Text(tier.displayName)
                .font(.caption.bold())
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(tier.color, in: Capsule())
                .frame(width: 82, alignment: .center)
            Text(description)
                .font(.caption)
                .foregroundColor(.primary)
        }
    }
}

// MARK: - Page Tips Model
// Each tab has its own set of contextual tips shown via the info button.

struct PageTip: Identifiable {
    let id = UUID()
    let icon: String
    let iconColor: Color
    let text: String
}

enum AppPage {
    case players, lineup, positions, history

    var title: String {
        switch self {
        case .players:   return "Players Tips"
        case .lineup:    return "Lineup Tips"
        case .positions: return "Positions Tips"
        case .history:   return "History Tips"
        }
    }

    var tips: [PageTip] {
        switch self {

        case .players:
            return [
                PageTip(icon: "plus.circle.fill", iconColor: .blue,
                        text: "Tap \"Add Player\" to add a player to your roster with their name and jersey number."),
                PageTip(icon: "pencil.circle", iconColor: .blue,
                        text: "Tap the pencil icon next to any player to edit their details, including position preferences."),
                PageTip(icon: "star.circle.fill", iconColor: .green,
                        text: "Set position preferences for each player: Strength positions are tried first by Auto-Fill, Capable next, Emergency as a last resort, and Never positions are never assigned."),
                PageTip(icon: "bolt.fill", iconColor: .blue,
                        text: "Position preferences feed directly into Auto-Fill — the more accurately you tag each player, the smarter the automatic lineups."),
                PageTip(icon: "paintpalette.fill", iconColor: .pink,
                        text: "Tap the Team Name row to open Edit Team, where you can update your team name and color. Your color appears on all exported PDFs."),
                PageTip(icon: "arrow.left.arrow.right", iconColor: .orange,
                        text: "Managing multiple teams? Tap Add Team in the Team section header to create a new team. Once you have more than one, a Switch Team option appears to move between them."),
                PageTip(icon: "gearshape.fill", iconColor: .gray,
                        text: "Tap the gear icon to access Settings, the full tutorial, and data management options.")
            ]

        case .lineup:
            return [
                PageTip(icon: "plus.circle.fill", iconColor: .green,
                        text: "Tap + next to a player to add them to the batting order. Players without + are already in the order."),
                PageTip(icon: "arrow.up.arrow.down", iconColor: .blue,
                        text: "Tap Edit, then drag the handle on the right to reorder players in the batting lineup."),
                PageTip(icon: "person.slash", iconColor: .orange,
                        text: "Toggle the switch next to any player to mark them fully absent. Absent players are removed from the order and all position assignments."),
                PageTip(icon: "clock", iconColor: .purple,
                        text: "For late arrivals or early departures, keep the player in the lineup and assign ABS to their missed innings in the Positions tab. They still need 1 infield and 1 outfield inning among the innings they play."),
                PageTip(icon: "checkmark.circle.fill", iconColor: .green,
                        text: "When your lineup is ready, tap \"Finalize lineup\" on the Positions tab. The status shows here as Finalized — any edit automatically reverts it to Draft so you always know where things stand."),
                PageTip(icon: "archivebox", iconColor: .teal,
                        text: "Tap the Archive button after each game to save it to your History. Defensive positions are cleared but your batting order is kept."),
                PageTip(icon: "doc.richtext", iconColor: .purple,
                        text: "Export a Batting Order or Coaches Guide PDF to share with parents or print for the dugout.")
            ]

        case .positions:
            return [
                PageTip(icon: "list.bullet", iconColor: .blue,
                        text: "Use the inning selector at the top to switch between innings. Dots show completion status — green is complete, orange is incomplete, red means a duplicate position."),
                PageTip(icon: "tablecells", iconColor: .blue,
                        text: "Tap Summary in the toolbar to see all players and innings in one grid. Tap any cell to assign a position from a dropdown menu."),
                PageTip(icon: "bolt.fill", iconColor: .blue,
                        text: "Tap the bolt icon next to the title to auto-fill open positions. Choose to fill just the current inning, or select how many innings to fill — useful for shorter games. Auto-Fill respects each player's position preferences."),
                PageTip(icon: "star.circle.fill", iconColor: .green,
                        text: "Auto-Fill is smarter when players have position preferences set. Open any player on the Players tab and tag positions as Strength, Capable, Emergency, or Never."),
                PageTip(icon: "clock", iconColor: .purple,
                        text: "Assign ABS to any inning for a player who arrives late or leaves early. ABS innings count as filled and won't trigger open-position warnings, but the player still needs 1 infield and 1 outfield inning among the innings they do play."),
                PageTip(icon: "checkmark.circle.fill", iconColor: .green,
                        text: "Tap \"Finalize lineup\" in the status strip when your defensive assignments are locked in. Any subsequent edit automatically reverts the lineup to Draft."),
                PageTip(icon: "exclamationmark.triangle.fill", iconColor: .orange,
                        text: "Tap the warnings icon to see a full list of issues — open positions, duplicates, back-to-back bench, and under-4-innings fielded warnings."),
                PageTip(icon: "archivebox", iconColor: .teal,
                        text: "Tap the Archive button when the game is over to save the defensive grid to History.")
            ]

        case .history:
            return [
                PageTip(icon: "person.3.fill", iconColor: .blue,
                        text: "The Players tab shows a season card for each player — total innings, bench time, infield/outfield split, and a bar chart of every position they've played."),
                PageTip(icon: "exclamationmark.circle", iconColor: .orange,
                        text: "After 3 or more games, position gaps appear on each player card — positions they haven't played yet that aren't marked Never in their preferences. A useful planning prompt for upcoming games."),
                PageTip(icon: "square.grid.3x3.fill", iconColor: .teal,
                        text: "The Team tab shows a full position coverage grid — blue dots are positions played, amber rings are gaps, and striped dots are Never positions. Use it to spot patterns across the whole roster at once."),
                PageTip(icon: "chart.bar.fill", iconColor: .red,
                        text: "The Team tab also shows a bench innings chart sorted by most to least."),
                PageTip(icon: "sparkles", iconColor: .purple,
                        text: "AI Coaching Insights appear at the top of the Players tab after 2 or more games are archived. They analyze bench time, infield/outfield balance, and playing time across your season."),
                PageTip(icon: "clock.arrow.circlepath", iconColor: .teal,
                        text: "The Games tab lists every archived game. Tap any game to see the full batting order and defensive grid for that game."),
                PageTip(icon: "archivebox.fill", iconColor: .teal,
                        text: "Archive games from the Lineup or Positions tab. Set the innings played accurately — only played innings count toward season stats and AI insights."),
                PageTip(icon: "trash", iconColor: .red,
                        text: "Swipe left on any game in the Games tab to delete it. The app keeps your last 20 games automatically.")
            ]
        }
    }
}

// MARK: - Page Tips Sheet
// Presented from the info button on each tab's toolbar.

struct PageTipsView: View {
    @Environment(\.dismiss) var dismiss
    let page: AppPage

    var body: some View {
        NavigationStack {
            List {
                ForEach(page.tips) { tip in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: tip.icon)
                            .foregroundColor(tip.iconColor)
                            .font(.system(size: 20))
                            .frame(width: 28, alignment: .center)
                            .padding(.top, 2)
                        Text(tip.text)
                            .font(.callout)
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(page.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Info Button View Modifier
// Adds a consistent info button to any view's toolbar.

struct InfoToolbarButton: ViewModifier {
    let page: AppPage
    @State private var showingTips = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showingTips = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                }
            }
            .sheet(isPresented: $showingTips) {
                PageTipsView(page: page)
            }
    }
}

extension View {
    func infoButton(for page: AppPage) -> some View {
        modifier(InfoToolbarButton(page: page))
    }
}

// MARK: - Full Quick Tips (accessible from Settings)

struct QuickTipsView: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Players Tab") {
                    Label("Tap \"Add Player\" to add a player to your roster", systemImage: "plus.circle.fill")
                    Label("Tap the pencil icon to edit a player's name, number, or position preferences", systemImage: "pencil.circle")
                    Label("Swipe left on a player to delete them", systemImage: "trash")
                    Label("Tap the Team Name row to edit your team name and color — both appear on exported PDFs", systemImage: "paintpalette.fill")
                    Label("Tap Add Team to manage multiple teams — each has its own roster and history", systemImage: "person.3.fill")
                }

                Section("Position Preferences") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Set preferences per player in their edit screen. Auto-Fill uses these to place players intelligently:")
                            .font(.callout)
                            .foregroundColor(.secondary)
                        HStack(alignment: .top, spacing: 8) {
                            Text("Strength").font(.caption.bold()).foregroundColor(.white)
                                .padding(.horizontal, 7).padding(.vertical, 3).background(Color.green, in: Capsule())
                                .frame(width: 74, alignment: .leading)
                            Text("Tried first when filling this position").font(.callout)
                        }
                        HStack(alignment: .top, spacing: 8) {
                            Text("Capable").font(.caption.bold()).foregroundColor(.white)
                                .padding(.horizontal, 7).padding(.vertical, 3).background(Color.blue, in: Capsule())
                                .frame(width: 74, alignment: .leading)
                            Text("Used if no Strength player is available").font(.callout)
                        }
                        HStack(alignment: .top, spacing: 8) {
                            Text("Emergency").font(.caption.bold()).foregroundColor(.white)
                                .padding(.horizontal, 7).padding(.vertical, 3).background(Color.orange, in: Capsule())
                                .frame(width: 74, alignment: .leading)
                            Text("Last resort — only when nothing else works").font(.callout)
                        }
                        HStack(alignment: .top, spacing: 8) {
                            Text("Never").font(.caption.bold()).foregroundColor(.white)
                                .padding(.horizontal, 7).padding(.vertical, 3).background(Color.red, in: Capsule())
                                .frame(width: 74, alignment: .leading)
                            Text("Never assigned by Auto-Fill").font(.callout)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Lineup Tab") {
                    Label("Tap + next to a player to add them to the batting order", systemImage: "plus.circle")
                    Label("Tap Edit, then drag to reorder the batting lineup", systemImage: "arrow.up.arrow.down")
                    Label("Toggle the switch to mark a player fully absent for the game", systemImage: "person.slash")
                    Label("For late arrivals or early departures, keep them in the lineup and assign ABS to their missed innings on the Positions tab", systemImage: "clock")
                    Label("Tap Archive to save the game and start fresh", systemImage: "archivebox")
                    Label("Export Batting Order or Coaches Guide as a PDF", systemImage: "doc.richtext")
                }

                Section("Positions Tab") {
                    Label("Tap an inning at the top, then tap a player to assign their position", systemImage: "hand.tap.fill")
                    Label("Tap Summary to edit all innings in a single grid", systemImage: "tablecells")
                    Label("Tap the bolt icon to auto-fill open positions — fill a single inning or choose how many innings to fill", systemImage: "bolt.fill")
                    Label("Auto-Fill respects position preferences — set them on the Players tab for smarter automatic lineups", systemImage: "star.circle.fill")
                    Label("In the Summary grid, your current position shows with a strikethrough", systemImage: "strikethrough")
                    Label("Assign ABS to innings a player misses due to late arrival or early departure", systemImage: "clock")
                    Label("Tap \"Finalize lineup\" in the status strip when assignments are locked in — any edit reverts it to Draft automatically", systemImage: "checkmark.circle.fill")
                    Label("Tap the warnings icon to review all issues for the current inning and game", systemImage: "exclamationmark.triangle.fill")
                    Label("Archive the game from this tab when finished", systemImage: "archivebox")
                }

                Section("History Tab") {
                    Label("Archive from Lineup or Positions tab to save games here", systemImage: "archivebox.fill")
                    Label("Set innings played accurately when archiving for correct stats", systemImage: "slider.horizontal.3")
                    Label("AI Coaching Insights appear after 2+ games are archived", systemImage: "sparkles")
                    Label("Tap any game to view its full batting order and defensive grid", systemImage: "clock.arrow.circlepath")
                    Label("Swipe left on a game to delete it", systemImage: "trash")
                }

                Section("Fair Play Rules") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "1.circle.fill").foregroundColor(.blue)
                            Text("Every player must play at least 1 inning in the infield (P, C, 1B, 2B, SS, 3B)")
                                .font(.callout)
                        }
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "2.circle.fill").foregroundColor(.green)
                            Text("Every player must play at least 1 inning in the outfield (LF, CF, RF)")
                                .font(.callout)
                        }
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "3.circle.fill").foregroundColor(.orange)
                            Text("No player should sit the bench for 2 consecutive innings")
                                .font(.callout)
                        }
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "4.circle.fill").foregroundColor(.purple)
                            Text("Every player must field for at least 4 innings (checked once all innings are planned)")
                                .font(.callout)
                        }
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "clock.fill").foregroundColor(Color(.systemGray))
                            Text("Players with ABS innings (late arrival/early departure) are exempt from the 4-inning minimum, but still need 1 infield and 1 outfield inning")
                                .font(.callout)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Warning Indicators") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "checkmark.shield.fill").foregroundColor(.green)
                            Text("All Good — no issues").font(.callout)
                        }
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                            Text("Inning or game-wide issues").font(.callout)
                        }
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
                            Text("Critical — both inning and game issues").font(.callout)
                        }
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "checkmark").foregroundColor(.green)
                            Text("Green dot — inning fully assigned").font(.callout)
                        }
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "minus").foregroundColor(.orange)
                            Text("Orange dash — inning partially assigned").font(.callout)
                        }
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "xmark").foregroundColor(.red)
                            Text("Red X — duplicate position in inning").font(.callout)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Quick Tips")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("Welcome") {
    WelcomeView()
}

#Preview("Quick Tips") {
    QuickTipsView()
}

#Preview("Page Tips - Players") {
    PageTipsView(page: .players)
}

#Preview("First Game Checklist") {
    let store = LineupStore()
    return ScrollView {
        FirstGameChecklist()
            .environmentObject(store)
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("AutoFill Context Tip") {
    AutoFillContextTip(isPresented: .constant(true), onGoToPlayers: {})
        .padding(.top, 40)
        .background(Color(.systemGroupedBackground))
}
