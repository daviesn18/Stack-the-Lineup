import SwiftUI

// History teaser toolkit — the pieces a free coach sees on the History tab.
//
// The tab is no longer a hard wall. A free coach sees a real slice of their own
// season (the first player, the most recent game, the top of the coverage grid)
// rendered crisp, with the rest blurred behind an upgrade CTA. These are the
// shared pieces GameLogsView's three tab views compose; the per-tab slicing
// lives there.
//
// Nothing here invents data. When a coach has no archived games there is
// nothing to preview, so `HistoryEmptyState` is an honest nudge rather than a
// blurred sample.

// MARK: - Upgrade CTA

/// The blue unlock bar. Its label is the live purchase CTA — "Start 7-day free
/// trial" while the coach is intro-eligible, "Subscribe — $price" otherwise —
/// so trial copy is never hardcoded here. Tapping flips the caller's paywall.
struct HistoryUpgradeCTA: View {
    @EnvironmentObject var purchaseManager: PurchaseManager
    let subtitle: String
    let onUpgrade: () -> Void

    var body: some View {
        Button(action: onUpgrade) {
            HStack(spacing: 12) {
                Image(systemName: "lock.open.fill")
                    .font(.title3)
                VStack(alignment: .leading, spacing: 1) {
                    Text(purchaseManager.ctaLabel)
                        .font(.subheadline.weight(.semibold))
                    Text(subtitle)
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
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Teaser blur

/// Wraps real content that should read as "there's more, unlock it": blurred,
/// faded into the background, and non-interactive — a blurred `NavigationLink`
/// must not be followable. The whole area taps through to the paywall instead.
struct TeaserBlur<Content: View>: View {
    let onUpgrade: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        content
            .blur(radius: 6)
            .allowsHitTesting(false)
            .overlay(
                LinearGradient(
                    colors: [.clear, Color(.systemGroupedBackground).opacity(0.75)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                // Tap target sits above the blurred content so the gesture
                // reaches the paywall rather than the inert rows beneath.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onUpgrade)
            )
            .clipped()
            .accessibilityElement()
            .accessibilityLabel("Locked preview")
            .accessibilityHint("Upgrade to Pro to see the rest")
            .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Empty state

/// Shown to a free coach who has archived nothing yet: no data to tease, so an
/// honest prompt about what History becomes once games are archived, with the
/// same unlock CTA. Replaces the old fake-sample ghost.
struct HistoryEmptyState: View {
    let teamColor: Color
    let onUpgrade: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 40)

            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 46))
                .foregroundColor(teamColor.opacity(0.7))

            VStack(spacing: 8) {
                Text("Your season starts here")
                    .font(.title3.bold())
                Text("Archive a game and History fills in: per-player stats, roster coverage, and AI coaching insights.")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 32)

            Spacer(minLength: 20)

            HistoryUpgradeCTA(subtitle: "Stats, coverage, and AI insights", onUpgrade: onUpgrade)
                .padding(.horizontal, 16)

            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}
