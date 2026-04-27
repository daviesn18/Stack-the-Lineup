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

extension WhatsNewContent {
    static let all: [WhatsNewContent] = [
        WhatsNewContent(
            version: "2.1",
            features: [
                WhatsNewFeature(
                    icon: "star.fill",
                    iconColor: .green,
                    title: "Position Preferences",
                    description: "Tag each player's preferred positions as Primary, Secondary, Emergency, or Never. AutoFill respects these preferences — and Never positions are never assigned, great for safety-sensitive spots like Catcher."
                ),
                WhatsNewFeature(
                    icon: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                    iconColor: .purple,
                    title: "Redesigned History Tab",
                    description: "The History tab is rebuilt around your players. See each player's position breakdown across the season, spot gaps at a glance, and review team-wide bench distribution — all in one place."
                ),
                WhatsNewFeature(
                    icon: "tablecells",
                    iconColor: .blue,
                    title: "Smarter Position Summary",
                    description: "The Positions tab now lets you view your lineup by Position as well as by Player — see who's pitching, catching, and playing each spot across every inning at a glance."
                ),
                WhatsNewFeature(
                    icon: "ipad.and.iphone",
                    iconColor: .teal,
                    title: "Built for iPad",
                    description: "Stack the Lineup now has a dedicated iPad layout with a side-by-side dashboard view. If you coach with a tablet on the bench, it's worth a look."
                ),
                WhatsNewFeature(
                    icon: "person.text.rectangle",
                    iconColor: .orange,
                    title: "League Age",
                    description: "Record each player's league age on their profile — ready for pitching logs and tracking coming in a future update."
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
                    description: "Manage two teams from one app. Add a second team from the Players tab — each team has its own roster, lineup, and game history."
                ),
                WhatsNewFeature(
                    icon: "bolt.fill",
                    iconColor: .blue,
                    title: "Auto-Fill Positions",
                    description: "Tap the bolt icon on the Positions tab to automatically fill open slots. Choose to fill a single inning or select how many innings to fill — great for shorter games."
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
}

// MARK: - What's New View

struct WhatsNewView: View {
    @Environment(\.dismiss) var dismiss

    let content: WhatsNewContent

    var body: some View {
        VStack(spacing: 0) {
            // Header
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
            .padding(.bottom, 36)

            // Feature rows
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

            Spacer()

            // Continue button
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
            .padding(.bottom, 36)
        }
        .interactiveDismissDisabled()
    }
}
