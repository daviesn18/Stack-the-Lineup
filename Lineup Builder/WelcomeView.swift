import SwiftUI
import TipKit

// MARK: - Welcome Cards (New-User First-Launch Flow)
// Two short cards shown on first launch, ending in "Start the tour". The tour
// itself is the anchored TipKit walkthrough in ContextualTips.swift — these
// cards only set the frame. Skipping arms TourInSettingsTip so the coach still
// learns where to find it. Ongoing reference help lives in the per-tab info
// button (see AppPage.tips).
// Gated by "hasCompletedTutorial" — existing users already have this set to true.

struct WelcomeCardsView: View {
    @Environment(\.dismiss) var dismiss
    @State private var currentPage = 0

    private struct WelcomeCard {
        let icon: String
        let iconColor: Color
        let tint: Color
        let title: String
        let body: String
        let cta: String
    }

    private let cards: [WelcomeCard] = [
        WelcomeCard(
            icon: "baseball.diamond.bases",
            iconColor: .blue,
            tint: Color.blue.opacity(0.12),
            title: "Welcome to Stack the Lineup.",
            body: "Build a fair lineup, assign every inning, and hand out the PDF before first pitch.",
            cta: "Show me around"
        ),
        WelcomeCard(
            icon: "shield.checkered",
            iconColor: .green,
            tint: Color.green.opacity(0.12),
            title: "Fair play, tracked for you.",
            body: "Set your league's rules once — fielding minimums, bench limits, pitching caps. The app flags a problem the moment you create one.",
            cta: "Start the tour"
        ),
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 0) {
                    // Skip row
                    HStack {
                        Spacer()
                        Button("Skip") {
                            UserDefaults.standard.set(true, forKey: "hasCompletedTutorial")
                            // Arms the one tip that points at the Settings
                            // re-entry row. The tour itself still runs.
                            TourState.welcomeSkipped = true
                            Analytics.signal("tour.welcome.skipped")
                            dismiss()
                        }
                        .font(.subheadline)
                        .foregroundColor(Color(.tertiaryLabel))
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 4)
                    }

                    let card = cards[currentPage]

                    // Icon disc
                    ZStack {
                        Circle()
                            .fill(card.tint)
                            .frame(width: 88, height: 88)
                        Image(systemName: card.icon)
                            .font(.system(size: 40))
                            .foregroundColor(card.iconColor)
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 18)

                    // Title
                    Text(card.title)
                        .font(.system(size: 24, weight: .bold))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                        .padding(.bottom, 10)

                    // Body
                    Text(card.body)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 24)

                    // Dot progress
                    HStack(spacing: 6) {
                        ForEach(0..<cards.count, id: \.self) { i in
                            Capsule()
                                .fill(i == currentPage ? card.iconColor : Color(.systemGray4))
                                .frame(width: i == currentPage ? 20 : 6, height: 6)
                                .animation(.spring(duration: 0.3), value: currentPage)
                        }
                    }
                    .padding(.bottom, 20)

                    // CTA button
                    Button {
                        if currentPage < cards.count - 1 {
                            withAnimation(.spring(duration: 0.35)) {
                                currentPage += 1
                            }
                        } else {
                            UserDefaults.standard.set(true, forKey: "hasCompletedTutorial")
                            dismiss()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(card.cta)
                                .font(.headline)
                            if currentPage < cards.count - 1 {
                                Image(systemName: "chevron.right")
                                    .font(.subheadline.bold())
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(card.iconColor)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 20)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 28)
                }
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .shadow(color: .black.opacity(0.3), radius: 30, x: 0, y: 8)
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
                .animation(.spring(duration: 0.35), value: currentPage)
            }
        }
        .interactiveDismissDisabled()
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
// Each tab has its own set of tips, shown via the info button in its toolbar.
// This is the single source of truth for in-app help — QuickTipsView renders
// the same content from AppPage.allCases, so there is only one copy to maintain.
// Tips are ordered to follow game-day sequence, not toolbar layout.

struct PageTip: Identifiable {
    let id = UUID()
    let icon: String
    let iconColor: Color
    let text: String
}

enum AppPage: CaseIterable {
    case players, lineup, positions, history

    /// Title for the per-tab info sheet.
    var title: String {
        switch self {
        case .players:   return "Players Tips"
        case .lineup:    return "Lineup Tips"
        case .positions: return "Positions Tips"
        case .history:   return "History Tips"
        }
    }

    /// Section header used when all pages are listed together in Quick Tips.
    var sectionTitle: String {
        switch self {
        case .players:   return "Players Tab"
        case .lineup:    return "Lineup Tab"
        case .positions: return "Positions Tab"
        case .history:   return "History Tab"
        }
    }

    var tips: [PageTip] {
        switch self {

        case .players:
            return [
                PageTip(icon: "person.badge.plus", iconColor: .blue,
                        text: "Add players one at a time, or use Bulk Add to type a full roster in one pass."),
                PageTip(icon: "square.and.arrow.down", iconColor: .teal,
                        text: "Import Roster pulls names, numbers, and position preferences from a GameChanger CSV export."),
                PageTip(icon: "star.circle.fill", iconColor: .green,
                        text: "Tag each player's positions Strength, Capable, Emergency, or Never. Auto-Fill works down that list — Never is never assigned."),
                PageTip(icon: "paintpalette.fill", iconColor: .pink,
                        text: "Tap your team name to set name, color, and game length. Name and color print on every PDF."),
                PageTip(icon: "shield.checkered", iconColor: .blue,
                        text: "Fair Play Rules live inside Edit Team, and each team gets its own set. Your rec team and travel team can run different rules."),
                PageTip(icon: "figure.baseball", iconColor: .orange,
                        text: "Pitching Rules track weekly pitch limits and required rest by age. Enter counts when you archive, and eligibility shows up on the Positions tab."),
                PageTip(icon: "person.2.wave.2", iconColor: .purple,
                        text: "Assistant Coaches, inside Edit Team, sends a coach an invite link. They can build positions; you finalize.")
            ]

        case .lineup:
            return [
                PageTip(icon: "calendar.badge.plus", iconColor: .teal,
                        text: "Import your season schedule once from GameChanger, then Pick from Schedule to fill in date and opponent."),
                PageTip(icon: "arrow.up.arrow.down", iconColor: .blue,
                        text: "Tap + to add a player to the batting order. Tap Edit, then drag the handle to reorder."),
                PageTip(icon: "person.slash", iconColor: .orange,
                        text: "The toggle marks a player out for the whole game and pulls them from every inning."),
                PageTip(icon: "clock", iconColor: .purple,
                        text: "Late arrival or early exit? Leave them in the order and assign ABS to the innings they miss on the Positions tab."),
                PageTip(icon: "square.stack.3d.up", iconColor: .blue,
                        text: "Templates rebuild a batting order and any locked positions in one tap. Good for a standing weekday lineup."),
                PageTip(icon: "doc.richtext", iconColor: .purple,
                        text: "Export a Batting Order for parents or a Coaches Guide for the dugout — the guide includes the full position grid and pitch counts."),
                PageTip(icon: "archivebox", iconColor: .teal,
                        text: "Archive after the game. Positions clear, batting order stays.")
            ]

        case .positions:
            return [
                PageTip(icon: "tablecells", iconColor: .blue,
                        text: "Switch between By Inning and Summary in the top left. Summary shows every inning in one grid."),
                PageTip(icon: "hand.tap.fill", iconColor: .blue,
                        text: "Tap any player or open slot to assign a position."),
                PageTip(icon: "bolt.fill", iconColor: .orange,
                        text: "The bolt fills open slots — one inning, or innings 1 through whatever you pick."),
                PageTip(icon: "text.bubble", iconColor: .indigo,
                        text: "Type instructions before you fill: \"Jack pitches innings 3 and 4, keep Maya out of catcher.\" Auto-Fill works around them and tells you if it can't."),
                PageTip(icon: "figure.baseball", iconColor: .orange,
                        text: "When pitching rules are on, each player's remaining pitches and rest status show as you assign the pitcher."),
                PageTip(icon: "clock", iconColor: .purple,
                        text: "ABS covers innings a player misses. Those innings won't flag as open, but they still need an infield and an outfield inning among the ones they play."),
                PageTip(icon: "exclamationmark.triangle.fill", iconColor: .red,
                        text: "The warnings icon lists everything open, duplicated, or against your fair play rules."),
                PageTip(icon: "square.stack.3d.up", iconColor: .blue,
                        text: "Save as Template keeps this lineup for next week. Lock the assignments you want repeated and leave the rest open."),
                PageTip(icon: "checkmark.circle.fill", iconColor: .green,
                        text: "Finalize lineup when assignments are locked in. Any edit after that puts it back to Draft.")
            ]

        case .history:
            return [
                PageTip(icon: "rectangle.3.group", iconColor: .blue,
                        text: "Three views: Players for season stats, Team for coverage across the roster, Games for the archive."),
                PageTip(icon: "person.3.fill", iconColor: .blue,
                        text: "Each player card shows total innings, bench time, the infield/outfield split, and every position they've played."),
                PageTip(icon: "exclamationmark.circle", iconColor: .orange,
                        text: "After 3 games, position gaps appear — spots a player hasn't seen that aren't marked Never."),
                PageTip(icon: "square.grid.3x3.fill", iconColor: .teal,
                        text: "The Team grid shows coverage at a glance, plus bench innings ranked most to least."),
                PageTip(icon: "sparkles", iconColor: .purple,
                        text: "AI Coaching Insights show up after 2 archived games and read bench time, field balance, and playing time across the season."),
                PageTip(icon: "arrow.uturn.down", iconColor: .green,
                        text: "Open any past game and copy its lineup to today's. It lands on the Lineup tab ready to adjust."),
                PageTip(icon: "note.text", iconColor: .teal,
                        text: "Notes save with each game — final score, field conditions, whatever you want next week. Assistant coaches on shared teams can see them.")
            ]
        }
    }
}

// MARK: - Page Tip Row
// Shared by the per-tab info sheet and the full Quick Tips list.

struct PageTipRow: View {
    let tip: PageTip

    var body: some View {
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

// MARK: - Page Tips Sheet
// Presented from the info button on each tab's toolbar.

struct PageTipsView: View {
    @Environment(\.dismiss) var dismiss
    let page: AppPage

    var body: some View {
        NavigationStack {
            List {
                ForEach(page.tips) { tip in
                    PageTipRow(tip: tip)
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

// MARK: - Full Quick Tips (accessible from Settings)
// Renders every tab's tips in one scroll, generated from AppPage so this
// screen can never drift out of sync with the per-tab info sheets.
// The reference sections below (preference tiers, warning icons) are the only
// content unique to this screen — they explain vocabulary rather than actions.

struct QuickTipsView: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(AppPage.allCases, id: \.self) { page in
                    Section(page.sectionTitle) {
                        ForEach(page.tips) { tip in
                            PageTipRow(tip: tip)
                        }
                    }
                }

                Section("Position Preferences") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Set these per player on the Players tab. Auto-Fill works down the list in order:")
                            .font(.callout)
                            .foregroundColor(.secondary)
                        TierExplanationRow(tier: .strength,  description: "Tried first when filling a position")
                        TierExplanationRow(tier: .capable,   description: "Used if no Strength player is available")
                        TierExplanationRow(tier: .emergency, description: "Only used if nothing else is available")
                        TierExplanationRow(tier: .never,     description: "Never assigned to this position")
                    }
                    .padding(.vertical, 4)
                }

                Section("Reading the Grid") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "checkmark.shield.fill").foregroundColor(.green)
                            Text("Green shield: no issues").font(.callout)
                        }
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                            Text("Orange triangle: an issue in this inning, or across the game").font(.callout)
                        }
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
                            Text("Red triangle: issues in both").font(.callout)
                        }
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "circle.fill").foregroundColor(.green)
                            Text("Green dot: every position in the inning is assigned").font(.callout)
                        }
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "circle.fill").foregroundColor(.orange)
                            Text("Orange dot: the inning still has open positions").font(.callout)
                        }
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "circle.fill").foregroundColor(.red)
                            Text("Red dot: the same position is assigned twice").font(.callout)
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

#Preview("Welcome Cards") {
    WelcomeCardsView()
}

#Preview("Quick Tips") {
    QuickTipsView()
}

#Preview("Page Tips - Players") {
    PageTipsView(page: .players)
}

#Preview("Page Tips - Positions") {
    PageTipsView(page: .positions)
}

