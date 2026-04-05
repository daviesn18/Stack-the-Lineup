import SwiftUI
import StoreKit

// MARK: - LockedHistoryView
// Shown in GameLogsView when the user hasn't purchased Pro.
// Renders realistic-looking fake game rows and a blurred insights card
// so the user can see exactly what they're missing, with a paywall
// card overlaid via ZStack.

struct LockedHistoryView: View {
    @EnvironmentObject var purchaseManager: PurchaseManager
    let teamColor: Color
    @Binding var showingPaywall: Bool

    // Fake game data — realistic enough to be enticing
    private let fakeGames: [(date: String, opponent: String, innings: Int)] = [
        ("Mon, Apr 7",  "Tigers",     6),
        ("Sat, Apr 12", "Blue Jays",  6),
        ("Wed, Apr 16", "Cardinals",  5),
        ("Sat, Apr 19", "Marlins",    6),
    ]

    var body: some View {
        ghostContent
            .blur(radius: 1)
            .allowsHitTesting(false)
            .overlay(alignment: .bottom) {
                // Fade gradient so ghost content dissolves into the card
                LinearGradient(
                    colors: [.clear, Color(.systemGroupedBackground).opacity(0.6), Color(.systemGroupedBackground)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 340)
                .allowsHitTesting(false)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                // Paywall card pinned above the tab bar via safeAreaInset
                paywallCard
            }
    }

    // MARK: - Ghost Content

    private var ghostContent: some View {
        List {
            // Fake insights card
            Section {
                fakeInsightsCard
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            // Fake game rows
            Section(header: Text("4 Games")) {
                ForEach(fakeGames, id: \.date) { game in
                    FakeGameLogRow(date: game.date, opponent: game.opponent, innings: game.innings)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Fake Insights Card

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

                // Fake insight lines as greyed-out bars
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

    // MARK: - Paywall Card

    private var paywallCard: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 36))
                    .foregroundColor(.blue)

                Text("Game History is a Pro Feature")
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)

                Text("Archive games, track your season, and get AI coaching insights.")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }

            Button {
                showingPaywall = true
            } label: {
                Label("Upgrade to Pro — \(purchaseManager.proProduct?.displayPrice ?? "$4.99")", systemImage: "star.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(14)
            }

            Button {
                Task { await purchaseManager.restore() }
            } label: {
                Text("Restore Purchase")
                    .font(.callout)
                    .foregroundColor(.blue)
            }

            Text("One-time purchase · No subscription")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(28)
        .background(.regularMaterial)
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.12), radius: 20, y: -4)
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
