import SwiftUI

// MARK: - What's New Data

struct WhatsNewFeature {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
}

struct WhatsNewContent {
    let version: String
    let features: [WhatsNewFeature]
}

// MARK: - Version Registry
// Add a new entry here each time you ship a version with notable changes.
// The trigger logic compares this version against the last seen version in UserDefaults.
// Rule: cap entries at 3 features max to keep the sheet dismissible on small screens.

extension WhatsNewContent {
    static let all: [WhatsNewContent] = [
        WhatsNewContent(
            version: "3.3",
            features: [
                WhatsNewFeature(
                    icon: "mic.fill",
                    iconColor: .purple,
                    title: "Ask Siri",
                    description: "Stack the Lineup answers to your voice now — handy when your hands are full of gear. Say \"Open Stack the Lineup\", or just ask it a question.\n\nEvery phrase it knows is listed under Settings › Siri Shortcuts. Players and teams turn up in Search now too."
                ),
                WhatsNewFeature(
                    icon: "checklist",
                    iconColor: .blue,
                    title: "Your Rules, Out Loud",
                    description: "Ask \"What's my pitch limit?\", \"How many days rest?\" or \"Can Jake pitch?\" and get the answer without opening the app.\n\nThe answers come from your team's own settings, not a generic rulebook — so they're the limits you actually coach to. Free, like the rest of Fair Play Rules."
                ),
                WhatsNewFeature(
                    icon: "sportscourt.fill",
                    iconColor: .green,
                    title: "Game Recap",
                    description: "Ask \"How did we do?\" and hear how the last game went — who sat, who pitched, and whether your fair play rules held up.\n\nGame Recap is a Pro feature."
                )
            ]
        ),
        WhatsNewContent(
            version: "3.2",
            features: [
                WhatsNewFeature(
                    icon: "doc.on.doc.fill",
                    iconColor: .blue,
                    title: "Lineup Templates",
                    description: "Save a lineup as a Template -- batting order, position locks, and all -- then apply it to a new game in one tap instead of rebuilding from scratch.\n\nOne template is free; multiple templates is a Pro feature."
                ),
                WhatsNewFeature(
                    icon: "text.bubble.fill",
                    iconColor: .purple,
                    title: "Natural Language Auto-Fill",
                    description: "Tell Auto-Fill what you want in plain English -- \"pitch Caleb the first two innings, bench the top of the order first\" -- and it builds the lineup around it.\n\nNatural Language Auto-Fill is a Pro feature."
                ),
                WhatsNewFeature(
                    icon: "square.grid.3x3.fill",
                    iconColor: .green,
                    title: "Positions, Reimagined",
                    description: "The By Inning view is now built around positions instead of batting order -- tap a position to assign a player, and see your whole field at a glance."
                )
            ]
        ),
        WhatsNewContent(
            version: "3.1",
            features: [
                WhatsNewFeature(
                    icon: "square.stack",
                    iconColor: .blue,
                    title: "Home Screen Widget",
                    description: "Add the Stack the Lineup widget to your Home Screen to see today's game at a glance. Tap it to jump straight to the Lineup tab."
                ),
                WhatsNewFeature(
                    icon: "note.text",
                    iconColor: .teal,
                    title: "Game Notes",
                    description: "Add notes to any game log — final score, field conditions, what to fix next week. Write them when you archive, or open the game later and add them then.\n\nAssistant coaches on shared teams can see them too."
                ),
                WhatsNewFeature(
                    icon: "bolt.fill",
                    iconColor: .orange,
                    title: "Auto-Fill Reports Back",
                    description: "When Auto-Fill can't fill a slot, it now tells you which one and why.\n\nThere's also a No Repeat Positions option in Fair Play Rules — turn it on and Auto-Fill gives each player a different position every inning when it can."
                )
            ]
        ),
        WhatsNewContent(
            version: "3.0",
            features: [
                WhatsNewFeature(
                    icon: "person.2.circle.fill",
                    iconColor: .purple,
                    title: "Shared Teams",
                    description: "Share your team with assistant coaches straight from the Players tab. Tap Team Settings, scroll down to Share Team, and send an invite link.\n\nAssistants can view the roster and build out positions. When the lineup is ready, the head coach finalizes and locks it -- assistants get a notification when it's done.\n\nShared Teams is a Pro feature."
                )
            ]
        ),
        WhatsNewContent(
            version: "2.5",
            features: [
                WhatsNewFeature(
                    icon: "figure.baseball.circle.fill",
                    iconColor: .orange,
                    title: "Pitch Count Tracking",
                    description: "Set up pitching rules for your team under Edit Team; configure weekly pitch limits and rest days by age.\n\nPitch counts are captured when you archive a game and tracked against each player's eligibility window.\n\nSee pitching eligibility in the Positions tab when you create defensive assignments.\n\nYour Coach's Guide now includes a pitch count table so you have eligibility at a glance on game day."
                )
            ]
        ),
        WhatsNewContent(
            version: "2.4",
            features: [
                WhatsNewFeature(
                    icon: "shield.checkered",
                    iconColor: .blue,
                    title: "Configurable Fair Play Rules",
                    description: "Every team can now have its own fair play ruleset. Set fielding minimums, toggle no back-to-back bench, restrict pitcher and catcher, configure 4 outfielders, and more. Find it under Edit Team on the Players tab."
                ),
                WhatsNewFeature(
                    icon: "baseball.fill",
                    iconColor: .orange,
                    title: "Battery Restrictions",
                    description: "New rules for catcher-to-pitcher and pitcher-to-catcher transitions. Set an inning threshold and the app warns you if a player crosses it."
                ),
                WhatsNewFeature(
                    icon: "arrow.left.arrow.right",
                    iconColor: .green,
                    title: "4-Outfielder Support",
                    description: "Younger leagues can now enable LCF and RCF from Fair Play Rules and the position grid and Auto-Fill update automatically."
                )
            ]
        ),
        WhatsNewContent(
            version: "2.3",
            features: [
                WhatsNewFeature(
                    icon: "slider.horizontal.3",
                    iconColor: .blue,
                    title: "Set Your Game Length",
                    description: "Configure the number of innings per game under Team Settings."
                ),
                WhatsNewFeature(
                    icon: "square.and.arrow.down",
                    iconColor: .teal,
                    title: "Import Your Roster",
                    description: "Import your roster directly from GameChanger. Tap Import Roster on the Players tab and follow the steps."
                ),
                WhatsNewFeature(
                    icon: "calendar.badge.plus",
                    iconColor: .green,
                    title: "Sync Your Schedule",
                    description: "Import your season schedule from GameChanger and pick games directly from the Lineup tab. Resync when your schedule changes."
                ),
                WhatsNewFeature(
                    icon: "square.and.arrow.up",
                    iconColor: .orange,
                    title: "Export and Share Your Roster",
                    description: "Back up your roster or share it with other coaches. Exports everything -- names, jersey numbers, league ages, and position preferences."
                )
            ]
        ),
        WhatsNewContent(
            version: "2.2",
            features: [
                WhatsNewFeature(
                    icon: "checkmark.seal.fill",
                    iconColor: .green,
                    title: "Draft & Finalized Lineups",
                    description: "Lineups now have a status -- Draft while you're building, Finalized when you're ready to go. Finalized lineups are locked against accidental edits and clearly marked on your Coach's Guide."
                ),
                WhatsNewFeature(
                    icon: "graduationcap.fill",
                    iconColor: .blue,
                    title: "Refreshed Tutorial",
                    description: "The in-app tutorial has been updated to cover position preferences, the redesigned History tab, and everything else added over the past few updates. Worth a quick re-read from Settings > Tutorial."
                )
            ]
        ),
        WhatsNewContent(
            version: "2.1",
            features: [
                WhatsNewFeature(
                    icon: "star.fill",
                    iconColor: .green,
                    title: "Position Preferences",
                    description: "Tag each player's preferred positions as Primary, Secondary, Emergency, or Never. AutoFill respects these preferences -- and Never positions are never assigned, great for safety-sensitive spots like Catcher."
                ),
                WhatsNewFeature(
                    icon: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                    iconColor: .purple,
                    title: "Redesigned History Tab",
                    description: "The History tab is rebuilt around your players. See each player's position breakdown across the season, spot gaps at a glance, and review team-wide bench distribution -- all in one place."
                ),
                WhatsNewFeature(
                    icon: "tablecells",
                    iconColor: .blue,
                    title: "Smarter Position Summary",
                    description: "The Positions tab now lets you view your lineup by Position as well as by Player -- see who's pitching, catching, and playing each spot across every inning at a glance."
                )
            ]
        ),
        WhatsNewContent(
            version: "2.0.1",
            features: [
                WhatsNewFeature(
                    icon: "person.3.fill",
                    iconColor: .blue,
                    title: "Multiple Teams",
                    description: "Manage two teams from one app. Add a second team from the Players tab -- each team has its own roster, lineup, and game history."
                ),
                WhatsNewFeature(
                    icon: "bolt.fill",
                    iconColor: .blue,
                    title: "Auto-Fill Positions",
                    description: "Tap the bolt icon on the Positions tab to automatically fill open slots. Choose to fill a single inning or select how many innings to fill -- great for shorter games."
                ),
                WhatsNewFeature(
                    icon: "clock.badge.xmark",
                    iconColor: .orange,
                    title: "Late Arrivals & Early Departures",
                    description: "Assign ABS to any inning for players who can't make the full game. ABS innings are exempt from the 4-inning minimum so your fair play warnings stay accurate."
                )
            ]
        )
    ]

    /// Returns the WhatsNewContent for the current app version, if one exists.
    static var current: WhatsNewContent? {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        return all.first { $0.version == version }
    }
}

// MARK: - Trigger Logic

struct WhatsNewManager {
    private static let lastSeenKey = "lastSeenWhatsNewVersion"

    /// Returns true if the current version has What's New content the user hasn't seen yet.
    static func shouldShow() -> Bool {
        guard let content = WhatsNewContent.current else { return false }
        let lastSeen = UserDefaults.standard.string(forKey: lastSeenKey) ?? ""
        return lastSeen != content.version
    }

    /// Call this after the sheet is shown to mark this version as seen.
    static func markAsSeen() {
        guard let content = WhatsNewContent.current else { return }
        UserDefaults.standard.set(content.version, forKey: lastSeenKey)
    }

    /// Forgets the last seen version so the sheet shows again on next launch.
    /// Called from `SettingsView.resetOnboardingFlags()` — "Reset Welcome and
    /// Tips" restored the welcome flow and the tour but left What's New
    /// suppressed at its last-seen version, with no way to bring it back.
    static func reset() {
        UserDefaults.standard.removeObject(forKey: lastSeenKey)
    }
}

// MARK: - What's New View

struct WhatsNewView: View {
    @Environment(\.dismiss) var dismiss

    let content: WhatsNewContent

    var body: some View {
        VStack(spacing: 0) {
            // Header — fixed, never scrolls
            VStack(spacing: 12) {
                Image(systemName: "baseball.fill")
                    .font(.system(size: 52))
                    .foregroundColor(.blue)
                    .padding(.top, 48)

                Text("What's New")
                    .font(.system(size: 28, weight: .bold))

                Text("Version \(content.version)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 32)

            // Feature rows — scrollable so the button is never pushed off screen
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    ForEach(content.features, id: \.title) { feature in
                        HStack(alignment: .top, spacing: 16) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(feature.iconColor.opacity(0.15))
                                    .frame(width: 48, height: 48)
                                Image(systemName: feature.icon)
                                    .font(.system(size: 22))
                                    .foregroundColor(feature.iconColor)
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(feature.title)
                                    .font(.body.bold())
                                Text(feature.description)
                                    .font(.callout)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 8)
            }

            // Continue button — always pinned at the bottom, never scrolls away
            Button {
                WhatsNewManager.markAsSeen()
                dismiss()
            } label: {
                Text("Continue")
                    .font(.body.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(14)
            }
            .padding(.horizontal, 28)
            .padding(.top, 16)
            .padding(.bottom, 36)
        }
        .interactiveDismissDisabled()
    }
}

// MARK: - Previews

#Preview("What's New v3.2") {
    WhatsNewView(content: WhatsNewContent.all.first(where: { $0.version == "3.2" })!)
}

#Preview("What's New v3.0") {
    WhatsNewView(content: WhatsNewContent.all.first(where: { $0.version == "3.0" })!)
}

#Preview("What's New v2.4") {
    WhatsNewView(content: WhatsNewContent.all.first(where: { $0.version == "2.4" })!)
}
