import SwiftUI

// MARK: - HistoryGhostView
// The teaser content for the History tab when the coach isn't Pro: a faded
// Coaching Insights card plus either sample game rows (no data yet) or a real
// count badge (games waiting). Rendered on its own here — callers add their own
// blur/scrim. Reused as the ProGate backdrop so the tab teaser and the upsell
// gate show the same thing.

struct HistoryGhostView: View {
    let teamColor: Color
    let archivedCount: Int

    // Sample game data — only shown when archivedCount == 0
    private let fakeGames: [(date: String, opponent: String, innings: Int)] = [
        ("Mon, Apr 7",  "Tigers",     6),
        ("Sat, Apr 12", "Blue Jays",  6),
        ("Wed, Apr 16", "Cardinals",  5),
        ("Sat, Apr 19", "Marlins",    6),
    ]

    var body: some View {
        List {
            Section {
                fakeInsightsCard
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            if archivedCount > 0 {
                Section(header: Text("\(archivedCount) \(archivedCount == 1 ? "Game" : "Games") Archived")) {
                    HStack(spacing: 14) {
                        Image(systemName: "archivebox.fill")
                            .font(.title2)
                            .foregroundColor(.teal)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(archivedCount) archived \(archivedCount == 1 ? "game" : "games") waiting")
                                .font(.subheadline.bold())
                                .foregroundColor(.primary.opacity(0.4))
                            Text("Upgrade to Pro to view your season history.")
                                .font(.caption)
                                .foregroundColor(.secondary.opacity(0.6))
                        }
                    }
                    .padding(.vertical, 4)
                }
            } else {
                Section(header: Text("4 Games")) {
                    ForEach(fakeGames, id: \.date) { game in
                        FakeGameLogRow(date: game.date, opponent: game.opponent, innings: game.innings)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var fakeInsightsCard: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 14)
                .fill(teamColor.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(teamColor.opacity(0.18), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.subheadline.bold())
                        .foregroundColor(teamColor)
                    Text("Coaching Insights")
                        .font(.subheadline.bold())
                        .foregroundColor(teamColor)
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 8) {
                    FakeTextLine(width: 260)
                    FakeTextLine(width: 220)
                    FakeTextLine(width: 240)
                }
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - LockedHistoryView
// The inline teaser shown in GameLogsView when the coach isn't Pro: the ghost
// content blurred, with a compact unlock prompt at the bottom. Tapping the
// prompt flips `showingPaywall`, which GameLogsView uses to present the full
// ProGate upsell (same ghost, unblurred, behind the contextual paywall).

struct LockedHistoryView: View {
    let teamColor: Color
    @Binding var showingPaywall: Bool
    let archivedCount: Int

    var body: some View {
        HistoryGhostView(teamColor: teamColor, archivedCount: archivedCount)
            .blur(radius: 1)
            .allowsHitTesting(false)
            .overlay(alignment: .bottom) {
                // Fade so the ghost content dissolves into the prompt card
                LinearGradient(
                    colors: [.clear, Color(.systemGroupedBackground).opacity(0.6), Color(.systemGroupedBackground)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 340)
                .allowsHitTesting(false)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                promptCard
            }
    }

    // MARK: - Prompt Bar
    // Compact re-entry to the Pro gate. The full pitch lives in the gate itself
    // (ProGate + PaywallView), so this stays a single tappable bar — no second
    // paywall card competing with it.

    private var promptCard: some View {
        Button {
            showingPaywall = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.title3)
                VStack(alignment: .leading, spacing: 1) {
                    Text("See your season with Pro")
                        .font(.subheadline.weight(.semibold))
                    Text(archivedCount > 0
                         ? "\(archivedCount) archived \(archivedCount == 1 ? "game" : "games") waiting"
                         : "Stats, coverage, and AI insights")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.85))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote.bold())
            }
            .foregroundColor(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(Color.blue, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Fake Game Log Row

struct FakeGameLogRow: View {
    let date: String
    let opponent: String
    let innings: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(date)
                    .font(.subheadline.bold())
                    .foregroundColor(.primary.opacity(0.35))
                Spacer()
                Text("\(innings) inn.")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(.systemGray5).opacity(0.5))
                    .foregroundColor(.secondary.opacity(0.5))
                    .cornerRadius(8)
            }
            Text("vs. \(opponent)")
                .font(.callout)
                .foregroundColor(.primary.opacity(0.35))
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Fake Text Line (for insights card placeholder)

struct FakeTextLine: View {
    let width: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color(.systemGray4).opacity(0.6))
            .frame(width: width, height: 12)
    }
}
