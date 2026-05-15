import SwiftUI

// MARK: - Welcome Cards (New-User First-Launch Flow)
// Three short cards shown on first launch. Replaces the 9-slide tutorial as
// the entry-point experience. The full tutorial remains accessible from Settings.
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
            body: "Build fair lineups, track positions, and share PDFs — all from your phone.",
            cta: "Show me around"
        ),
        WelcomeCard(
            icon: "shield.checkered",
            iconColor: .green,
            tint: Color.green.opacity(0.12),
            title: "Fair play is automatic.",
            body: "Everyone gets 1 infield inning, 1 outfield inning, and 4 fielding innings. The app flags issues as you go.",
            cta: "Got it"
        ),
        WelcomeCard(
            icon: "hand.tap.fill",
            iconColor: .purple,
            tint: Color.purple.opacity(0.12),
            title: "Tips pop up as you go.",
            body: "The first time you visit each tab, we will highlight the one thing to try first.",
            cta: "Let's start"
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

// MARK: - Tab First Tip Overlay
// Full-screen dim overlay with a glowing ring around a target element,
// an arrow pointing to it, and a tooltip card.
// Used for the five contextual tips fired on first visit to each tab.

struct TabFirstTipOverlay: View {
    let config: TabTipConfig
    let onDismiss: () -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Dim layer
                Color.black.opacity(0.30)
                    .ignoresSafeArea()
                    .onTapGesture { onDismiss() }

                // Glowing highlight ring around the target element.
                // The ring is a white-filled rounded rect with a colored stroke
                // and a shadow glow — matches the design exactly.
                RoundedRectangle(cornerRadius: config.targetCornerRadius)
                    .fill(Color(.systemBackground))
                    .frame(width: config.targetRect.width + 12, height: config.targetRect.height + 12)
                    .overlay(
                        RoundedRectangle(cornerRadius: config.targetCornerRadius)
                            .strokeBorder(config.accentColor, lineWidth: 2)
                    )
                    .shadow(color: config.accentColor.opacity(0.5), radius: 10, x: 0, y: 0)
                    .position(
                        x: config.targetRect.midX,
                        y: config.targetRect.midY
                    )

                // Arrow
                TabTipArrow(
                    arrowDirection: config.arrowDirection,
                    accentColor: config.accentColor,
                    targetRect: config.targetRect
                )

                // Tooltip card
                TabTipCard(config: config, onDismiss: onDismiss)
            }
        }
        .transition(.opacity)
    }
}

// MARK: - Tab Tip Arrow

private struct TabTipArrow: View {
    let arrowDirection: TabTipConfig.ArrowDirection
    let accentColor: Color
    let targetRect: CGRect

    var body: some View {
        GeometryReader { geo in
            let midX = targetRect.midX
            let arrowX = max(20, min(geo.size.width - 20, midX))

            Group {
                if arrowDirection == .up {
                    // Arrow points up: sits below the target, points upward
                    Image(systemName: "arrowtriangle.up.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 1)
                        .position(x: arrowX, y: targetRect.maxY + 14)
                } else {
                    // Arrow points down: sits above the target, points downward
                    Image(systemName: "arrowtriangle.down.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 1)
                        .position(x: arrowX, y: targetRect.minY - 14)
                }
            }
        }
    }
}

// MARK: - Tab Tip Card

private struct TabTipCard: View {
    let config: TabTipConfig
    let onDismiss: () -> Void

    var body: some View {
        GeometryReader { geo in
            let cardWidth = geo.size.width - 32
            let cardX = geo.size.width / 2
            // Place card below target for up-arrows, above for down-arrows.
            // Clamp so the card never clips off screen.
            let cardY: CGFloat = {
                if config.arrowDirection == .up {
                    let idealTop = config.targetRect.maxY + 28
                    return idealTop + 80 // 80 = approx half card height
                } else {
                    let idealBottom = config.targetRect.minY - 28
                    return idealBottom - 80
                }
            }()

            VStack(alignment: .leading, spacing: 0) {
                // Kicker row
                HStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(config.accentColor)
                            .frame(width: 20, height: 20)
                        Image(systemName: "hand.tap.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.white)
                    }
                    Text("First time on \(config.tabName)")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.8)
                        .textCase(.uppercase)
                        .foregroundColor(config.accentColor)
                }
                .padding(.bottom, 6)

                // Title
                Text(config.title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.primary)
                    .padding(.bottom, 4)

                // Body
                Text(config.body)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                // Footer buttons
                HStack {
                    Button("Don't show again") {
                        onDismiss()
                    }
                    .font(.caption)
                    .foregroundColor(Color(.tertiaryLabel))

                    Spacer()

                    Button("Got it") {
                        onDismiss()
                    }
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(config.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .padding(.top, 12)
            }
            .padding(16)
            .frame(width: cardWidth)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.22), radius: 20, x: 0, y: 6)
            .position(x: cardX, y: cardY)
        }
    }
}

// MARK: - Tab Tip Config
// Defines the content and geometry for each contextual tip overlay.
// targetRect is in the coordinate space of the tab's root view.

struct TabTipConfig {
    enum ArrowDirection { case up, down }

    let tabName: String
    let title: String
    let body: String
    let accentColor: Color
    // CGRect describing the element to highlight, in screen-relative coords.
    // Pass values appropriate for the device's safe area / layout.
    let targetRect: CGRect
    let targetCornerRadius: CGFloat
    let arrowDirection: ArrowDirection
}

// MARK: - Welcome / Tutorial View (Full — accessible from Settings)

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
            icon: "square.and.arrow.down",
            iconColor: .teal,
            title: "Get Set Up Fast",
            description: "Import your roster from GameChanger and sync your season schedule. Game length can be configured under Team Settings.",
            systemImage: "calendar.badge.plus"
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
            description: "On the Positions tab, select an inning and tap any player to assign their defensive position. Tap the bolt icon to auto-fill open slots. Auto-Fill respects each player's position preferences when filling. Switch to Summary view to see and edit all innings in one grid.",
            systemImage: "bolt.fill"
        ),
        TutorialPage(
            icon: "star.circle.fill",
            iconColor: .yellow,
            title: "Set Position Preferences",
            description: "In each player's edit screen, tag positions as Strength, Capable, Emergency, or Never. Auto-Fill uses these to place players in the right spots automatically. The more accurately you tag each player, the smarter your lineups get.",
            systemImage: "wand.and.stars"
        ),
        TutorialPage(
            icon: "exclamationmark.triangle.fill",
            iconColor: .red,
            title: "Fair Play Warnings",
            description: "Fair play rules are configurable per team. By default, the app warns you when a player is missing an infield or outfield inning, sitting back-to-back bench, or under the fielding minimum. To adjust the rules for your league, tap the Team Name on the Players tab, then tap Fair Play Rules.",
            systemImage: "shield.checkered"
        ),
        TutorialPage(
            icon: "checkmark.circle.fill",
            iconColor: .green,
            title: "Finalize Your Lineup",
            description: "When your defensive assignments are set, tap \"Finalize lineup\" on the Positions tab. The Lineup tab shows your status as Finalized. Any edit automatically reverts it to Draft so you always know where things stand.",
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
            title: "Export and Manage Teams",
            description: "Export a Batting Order or Coaches Guide PDF from the Lineup tab. Tap the Team Name row on the Players tab to set your team name and color. Both appear on exported PDFs. Managing multiple teams? Tap Add Team to create a new team with its own roster and history.",
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
                        dismiss()
                    } label: {
                        Label("Done", systemImage: "checkmark")
                            .font(.body.bold())
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
            }
            .padding()
        }
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
                        Text("Auto-Fill uses position preferences for each player to build better lineups.")
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

// MARK: - PDF Export Context Tip
// One-time tip shown on the Lineup tab when a free user has 3+ players in their
// batting order. Surfaces the Coaches Guide PDF as the key Pro value prop at the
// moment the coach has real lineup data to export.
// Gated with hasSeenPDFExportTip — never shown again after dismissal or tap-through.

struct PDFExportContextTip: View {
    @Binding var isPresented: Bool

    var body: some View {
        if isPresented {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack(alignment: .top, spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.12))
                            .frame(width: 40, height: 40)
                        Image(systemName: "doc.richtext.fill")
                            .foregroundColor(.blue)
                            .font(.system(size: 18))
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Export a Coaches Guide PDF")
                            .font(.subheadline.bold())
                        Text("When your lineup is ready, export a full inning-by-inning position grid to print or share with your assistant coach.")
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

                // What's in the PDF
                VStack(alignment: .leading, spacing: 8) {
                    Text("The Coaches Guide includes:")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.green).font(.caption)
                        Text("Every player's position for each inning").font(.caption)
                    }
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.green).font(.caption)
                        Text("Full batting order with jersey numbers").font(.caption)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

                Divider()

                // CTA
                Button {
                    withAnimation { isPresented = false }
                } label: {
                    Text("Got it")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .foregroundColor(.white)
                }

                Button {
                    withAnimation { isPresented = false }
                } label: {
                    Text("Maybe later")
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
                PageTip(icon: "square.and.arrow.down", iconColor: .teal,
                        text: "Tap Import Roster to bring in your full roster from a GameChanger CSV export. Names, jersey numbers, and position preferences are all imported."),
                PageTip(icon: "square.and.arrow.up", iconColor: .orange,
                        text: "Tap the share icon in the toolbar to export your roster as a .stlroster file. Use it to back up your roster or share it with an assistant coach."),
                PageTip(icon: "pencil.circle", iconColor: .blue,
                        text: "Tap the pencil icon next to any player to edit their details, including position preferences."),
                PageTip(icon: "star.circle.fill", iconColor: .green,
                        text: "Set position preferences for each player: Strength positions are tried first by Auto-Fill, Capable next, Emergency as a last resort, and Never positions are never assigned."),
                PageTip(icon: "bolt.fill", iconColor: .blue,
                        text: "Position preferences feed directly into Auto-Fill. The more accurately you tag each player, the smarter the automatic lineups."),
                PageTip(icon: "paintpalette.fill", iconColor: .pink,
                        text: "Tap the Team Name row to open Edit Team, where you can update your team name, color, and game length. Your name and color appear on all exported PDFs."),
                PageTip(icon: "shield.checkered", iconColor: .blue,
                        text: "Tap the Team Name row, then Fair Play Rules to configure your league's rules per team. Set fielding minimums, toggle no back-to-back bench, restrict pitcher and catcher positions, and more."),
                PageTip(icon: "arrow.left.arrow.right", iconColor: .orange,
                        text: "Managing multiple teams? Tap Add Team in the Team section header to create a new team. Once you have more than one, a Switch Team option appears to move between them."),
                PageTip(icon: "gearshape.fill", iconColor: .gray,
                        text: "Tap the gear icon to access Settings, the full tutorial, and data management options.")
            ]

        case .lineup:
            return [
                PageTip(icon: "calendar.badge.plus", iconColor: .teal,
                        text: "Tap the calendar icon in the toolbar to import your season schedule from GameChanger. Paste your calendar link and tap Import."),
                PageTip(icon: "calendar", iconColor: .blue,
                        text: "Once your schedule is imported, tap Pick from Schedule to pre-fill the game date and opponent. Tap Sync anytime to pull the latest changes from GameChanger."),
                PageTip(icon: "plus.circle.fill", iconColor: .green,
                        text: "Tap + next to a player to add them to the batting order. Players without + are already in the order."),
                PageTip(icon: "arrow.up.arrow.down", iconColor: .blue,
                        text: "Tap Edit, then drag the handle on the right to reorder players in the batting lineup."),
                PageTip(icon: "person.slash", iconColor: .orange,
                        text: "Toggle the switch next to any player to mark them fully absent. Absent players are removed from the order and all position assignments."),
                PageTip(icon: "clock", iconColor: .purple,
                        text: "For late arrivals or early departures, keep the player in the lineup and assign ABS to their missed innings in the Positions tab. They still need 1 infield and 1 outfield inning among the innings they play."),
                PageTip(icon: "checkmark.circle.fill", iconColor: .green,
                        text: "When your lineup is ready, tap \"Finalize lineup\" on the Positions tab. The status shows here as Finalized. Any edit automatically reverts it to Draft so you always know where things stand."),
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
                        text: "Tap the bolt icon next to the title to auto-fill open positions. Choose to fill just the current inning, or select how many innings to fill. Auto-Fill respects each player's position preferences."),
                PageTip(icon: "star.circle.fill", iconColor: .green,
                        text: "Auto-Fill is smarter when players have position preferences set. Open any player on the Players tab and tag positions as Strength, Capable, Emergency, or Never."),
                PageTip(icon: "clock", iconColor: .purple,
                        text: "Assign ABS to any inning for a player who arrives late or leaves early. ABS innings count as filled and won't trigger open-position warnings, but the player still needs 1 infield and 1 outfield inning among the innings they do play."),
                PageTip(icon: "checkmark.circle.fill", iconColor: .green,
                        text: "Tap \"Finalize lineup\" in the status strip when your defensive assignments are locked in. Any subsequent edit automatically reverts the lineup to Draft."),
                PageTip(icon: "exclamationmark.triangle.fill", iconColor: .orange,
                        text: "Tap the warnings icon to see a full list of issues — open positions, duplicates, back-to-back bench, and any fair play rule violations configured for your team."),
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
                    Label("Tap Import Roster to bring in your roster from a GameChanger CSV export", systemImage: "square.and.arrow.down")
                    Label("Tap the share icon in the toolbar to export your roster as a .stlroster file — useful for backups or sharing with an assistant", systemImage: "square.and.arrow.up")
                    Label("Tap the pencil icon to edit a player's name, number, or position preferences", systemImage: "pencil.circle")
                    Label("Swipe left on a player to delete them", systemImage: "trash")
                    Label("Tap the Team Name row to edit your team name, color, and game length", systemImage: "paintpalette.fill")
                    Label("Tap Fair Play Rules inside Edit Team to configure your league's rules per team — fielding minimums, bench rules, position restrictions, and battery restrictions", systemImage: "shield.checkered")
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
                    Label("Tap the calendar icon in the toolbar to import or sync your season schedule from GameChanger", systemImage: "calendar.badge.plus")
                    Label("Tap Pick from Schedule to pre-fill the game date and opponent from your imported schedule", systemImage: "calendar")
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
                            Image(systemName: "slider.horizontal.3").foregroundColor(.blue)
                            Text("Fair play rules are configurable per team. Open Edit Team from the Players tab, then tap Fair Play Rules.")
                                .font(.callout)
                        }
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "shield.checkered").foregroundColor(.blue)
                            Text("Default rules: 1 infield inning minimum, 1 outfield inning minimum, no back-to-back bench, and 4 innings fielded minimum.")
                                .font(.callout)
                        }
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "baseball.fill").foregroundColor(.orange)
                            Text("Additional rules include: No Pitcher, No Catcher, 4 outfielders (LCF/RCF), equal bench time, and battery restrictions (Catcher to Pitcher, Pitcher to Catcher).")
                                .font(.callout)
                        }
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "person.3.fill").foregroundColor(.purple)
                            Text("Rules are scoped per team. Your rec team and travel team can have completely different configurations.")
                                .font(.callout)
                        }
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "clock.fill").foregroundColor(Color(.systemGray))
                            Text("Players with ABS innings are exempt from the fielding minimum but still need 1 infield and 1 outfield inning among the innings they play.")
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

#Preview("Welcome Cards") {
    WelcomeCardsView()
}

#Preview("Full Tutorial") {
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

#Preview("Tab First Tip Overlay") {
    ZStack {
        Color(.systemGroupedBackground).ignoresSafeArea()
        TabFirstTipOverlay(
            config: TabTipConfig(
                tabName: "Players",
                title: "Set position preferences",
                body: "Tap the pencil icon next to any player and tag positions as Strength, Capable, Emergency, or Never. Auto-Fill uses these to build smarter lineups.",
                accentColor: .blue,
                targetRect: CGRect(x: 20, y: 120, width: 140, height: 36),
                targetCornerRadius: 10,
                arrowDirection: .up
            ),
            onDismiss: {}
        )
    }
}
