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
            description: "On the Lineup tab, tap + next to each player to add them to the batting order, then drag to reorder. Toggle the switch next to any player to mark them absent for the game.",
            systemImage: "arrow.up.arrow.down"
        ),
        TutorialPage(
            icon: "baseball.diamond.bases",
            iconColor: .orange,
            title: "Assign Positions",
            description: "On the Positions tab, select an inning and tap any player to assign their defensive position. Switch to Summary view to see and edit all players across all innings in one grid.",
            systemImage: "checkmark.shield.fill"
        ),
        TutorialPage(
            icon: "exclamationmark.triangle.fill",
            iconColor: .red,
            title: "Fair Play Warnings",
            description: "The app enforces four rules: every player gets at least 1 infield inning, 1 outfield inning, no back-to-back bench innings, and a minimum of 4 innings fielded per game. Players marked ABS (late arrival/early departure) are exempt from the 4-inning minimum but still need 1 infield and 1 outfield.",
            systemImage: "shield.checkered"
        ),
        TutorialPage(
            icon: "clock.arrow.circlepath",
            iconColor: .teal,
            title: "Game History",
            description: "After each game, tap the Archive button to save the lineup to your history. Set how many innings were actually played so stats stay accurate. View past games anytime in the History tab.",
            systemImage: "archivebox.fill"
        ),
        TutorialPage(
            icon: "doc.text.fill",
            iconColor: .purple,
            title: "Export & Customize",
            description: "Export a Batting Order or Coaches Guide PDF from the Lineup tab. Set your team name and color on the Players tab — your color appears on all exported PDFs.",
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
                        text: "Tap \"Add Player\" to add a new player to your roster with their name and jersey number."),
                PageTip(icon: "pencil.circle", iconColor: .blue,
                        text: "Tap the pencil icon next to any player to edit their name or jersey number."),
                PageTip(icon: "line.3.horizontal", iconColor: Color(.secondaryLabel),
                        text: "Tap Edit in the top left to reorder or delete players by swiping left on a row."),
                PageTip(icon: "paintpalette.fill", iconColor: .pink,
                        text: "Set your team name and team color here — your color appears on all exported PDFs."),
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
                PageTip(icon: "strikethrough", iconColor: Color(.secondaryLabel),
                        text: "In the Summary dropdown, your already-assigned position appears with a strikethrough so you can see it at a glance."),
                PageTip(icon: "clock", iconColor: .purple,
                        text: "Assign ABS to any inning for a player who arrives late or leaves early. ABS innings count as filled and won't trigger open-position warnings, but the player still needs 1 infield and 1 outfield inning among the innings they do play."),
                PageTip(icon: "exclamationmark.triangle.fill", iconColor: .orange,
                        text: "Tap the warnings icon to see a full list of issues — open positions, duplicates, back-to-back bench, and under-4-innings fielded warnings."),
                PageTip(icon: "archivebox", iconColor: .teal,
                        text: "Tap the Archive button when the game is over to save the defensive grid to History.")
            ]

        case .history:
            return [
                PageTip(icon: "archivebox.fill", iconColor: .teal,
                        text: "Games are archived from the Lineup or Positions tab. After archiving, your defensive positions are cleared and your batting order is preserved for the next game."),
                PageTip(icon: "slider.horizontal.3", iconColor: .blue,
                        text: "When archiving, set the innings played accurately — only innings that were actually played count toward season stats and AI insights."),
                PageTip(icon: "sparkles", iconColor: .purple,
                        text: "The AI Coaching Insights card appears after 2 or more games are archived. It analyzes bench time, infield/outfield balance, and playing time distribution across your season."),
                PageTip(icon: "clock.arrow.circlepath", iconColor: .teal,
                        text: "Tap any game in the list to see the full batting order and defensive grid for that game."),
                PageTip(icon: "trash", iconColor: .red,
                        text: "Swipe left on any game log to delete it. The app keeps your last 20 games automatically.")
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
                    Label("Tap the pencil icon to edit a player's name or number", systemImage: "pencil.circle")
                    Label("Swipe left on a player to delete them", systemImage: "trash")
                    Label("Set your team name and color — they appear on exported PDFs", systemImage: "paintpalette.fill")
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
                    Label("In the Summary grid, your current position shows with a strikethrough", systemImage: "strikethrough")
                    Label("Assign ABS to innings a player misses due to late arrival or early departure", systemImage: "clock")
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
