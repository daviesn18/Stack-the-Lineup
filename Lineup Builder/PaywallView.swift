import SwiftUI
import StoreKit

// MARK: - PaywallView
// Shown as a sheet when a free coach taps a Pro-gated feature. It is an
// interruption mid-task, so it leads with the feature they just tried (the
// "hero"), lists the rest in three groups, names what stays free, and keeps
// the price + CTA pinned so they're reachable without scrolling.
//
// The hero is chosen from `source` — the string each call site passes. Sources
// with no matching feature (settings, preview, and the now-free team file
// flows) fall back to a generic hero.

struct PaywallView: View {
    @EnvironmentObject var purchaseManager: PurchaseManager
    @Environment(\.dismiss) var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let source: String

    // Must include www — the apex domain has no valid TLS certificate, so
    // links without it fail to load. See CNAME in the website repo.
    private let termsURL = URL(string: "https://www.stackthelineup.com/terms.html")!
    private let privacyURL = URL(string: "https://www.stackthelineup.com/privacy.html")!

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                scrollingContent
                footer
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not Now") {
                        Analytics.signal("paywall.dismissed", parameters: ["source": source])
                        dismiss()
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text("PRO")
                        .font(.caption.weight(.bold))
                        .tracking(0.6)
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 5))
                }
            }
            .onChange(of: purchaseManager.isPro) { _, newValue in
                if newValue { dismiss() }
            }
            .task {
                await purchaseManager.loadProduct()
            }
            .onAppear {
                Analytics.signal("paywall.shown", parameters: ["source": source])
                purchaseManager.lastPaywallSource = source
            }
        }
    }

    // MARK: - Scrolling Content

    private var scrollingContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                heroCard

                if hero != nil {
                    sectionHeader("Also included in Pro")
                }

                ForEach(visibleGroups) { group in
                    sectionHeader(group.title)
                    VStack(spacing: 0) {
                        ForEach(Array(group.features.enumerated()), id: \.element.id) { index, feature in
                            ProFeatureRow(feature: feature)
                            if index < group.features.count - 1 {
                                Divider().padding(.leading, 61)
                            }
                        }
                    }
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
                }

                freeTierCard
            }
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
    }

    // MARK: - Hero

    /// The feature to lead with, or nil for the generic hero.
    private var hero: PaywallFeature? {
        PaywallFeature.forSource(source)
    }

    @ViewBuilder
    private var heroCard: some View {
        let accent = hero?.color ?? Color.accentColor
        let icon = hero?.icon ?? "star.circle.fill"
        let title = hero?.title ?? "Stack the Lineup Pro"
        let desc = hero?.description ?? "Auto-Fill, templates, the Coaches Guide PDF, and a full season of history."
        let eyebrow = hero != nil ? "You just tried" : "What Pro adds"
        let eyebrowIcon = hero != nil ? "lock.fill" : "star.fill"

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: eyebrowIcon)
                    .font(.system(size: 13, weight: .semibold))
                Text(eyebrow.uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(0.8)
            }
            .foregroundStyle(accent)

            HStack(alignment: .top, spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 30))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(accent, in: RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.primary)
                    Text(desc)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    // MARK: - Groups

    /// Groups with the hero feature removed, dropping any group left empty.
    private var visibleGroups: [PaywallGroup] {
        let heroID = hero?.id
        return PaywallGroup.all.compactMap { group in
            let features = group.features.filter { $0.id != heroID }
            return features.isEmpty ? nil : PaywallGroup(title: group.title, features: features)
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.footnote.weight(.semibold))
            .tracking(0.5)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 32)
            .padding(.top, 14)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Free Tier

    private var freeTierCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 19))
                .foregroundStyle(Color.green)
            (Text("Always free. ").font(.footnote.weight(.semibold)).foregroundColor(.primary)
             + Text("Batting order, positions, fair play warnings, and roster import.")
                .font(.footnote).foregroundColor(.secondary))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    // MARK: - Footer (pinned)

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
            VStack(spacing: 0) {
                planSummary

                if let error = purchaseManager.purchaseError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(Color.red)
                        .multilineTextAlignment(.center)
                        // Same compressible-Text trap as the disclosure below.
                        .fixedSize(horizontal: false, vertical: !dynamicTypeSize.isAccessibilitySize)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                }

                buyButton
                    .padding(.top, 11)

                Button {
                    Task { await purchaseManager.restore() }
                } label: {
                    Text("Restore Purchase")
                        .font(.callout)
                }
                .disabled(purchaseManager.isLoading)
                .padding(.top, 12)

                legalBlock
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)
        }
        .background(Color(.systemBackground))
    }

    private var planSummary: some View {
        HStack(spacing: 13) {
            Image(systemName: "star.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(Color.accentColor)
                .frame(width: 38, height: 38)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 1) {
                Text(purchaseManager.planHeadline)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(purchaseManager.isEligibleForIntroOffer
                     ? "Cancel anytime before the trial ends."
                     : "Cancel anytime in Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color(.systemGray4), lineWidth: 1.5)
        )
    }

    private var buyButton: some View {
        Button {
            Task { await purchaseManager.purchase() }
        } label: {
            Group {
                if purchaseManager.isLoading {
                    ProgressView().tint(.white)
                } else {
                    Text(purchaseManager.ctaLabel)
                        .font(.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(.white)
        }
        // Disabled until the real product has loaded — tapping before then hit
        // purchase()'s "product isn't available" guard, surfacing an error the
        // moment a fast tapper (like an App Review tester) hit Subscribe.
        .disabled(purchaseManager.isLoading || purchaseManager.subscriptionProduct == nil)
    }

    private var legalBlock: some View {
        // One Text from a single markdown AttributedString so the Terms/Privacy
        // links stay tappable (App Review 3.1.2). Links concatenated across
        // separate Text values do not reliably register taps.
        Text(legalAttributed)
            .font(.caption2)
            .tint(Color.accentColor)
            // Incompressible, like every other wrapping Text in this view.
            //
            // This footer is pinned beside a ScrollView, which takes all the
            // height it is offered. A plain Text is vertically compressible —
            // it answers a too-small proposal by truncating — so the scroll
            // content won the space and this disclosure ellipsised to a single
            // line at the peek detent, the state iPhone opens at. That left
            // "…is charged to your Apple Accou…" directly above a fully visible
            // purchase button. fixedSize makes the wrapped height a minimum the
            // stack must grant, and the scroll content absorbs the difference —
            // it has somewhere to put the loss, and this does not. Backlog 3.9.
            //
            // Released again at the accessibility sizes, where the footer wants
            // more height than the whole sheet: held rigid there it pushes the
            // price and the purchase button off the bottom, which is worse than
            // the truncation it replaced. Those sizes truncate exactly as they
            // did before, and the paywall's Dynamic Type pass is 4.3.
            .fixedSize(horizontal: false, vertical: !dynamicTypeSize.isAccessibilitySize)
    }

    private var legalAttributed: AttributedString {
        let markdown = "\(purchaseManager.legalText) By continuing you agree to our "
            + "[Terms of Service](\(termsURL.absoluteString)) and "
            + "[Privacy Policy](\(privacyURL.absoluteString))."
        var attributed = (try? AttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(markdown)
        // Base color for the non-link text; links keep the tint applied above.
        attributed.foregroundColor = .secondary
        for run in attributed.runs where run.link != nil {
            attributed[run.range].foregroundColor = .accentColor
        }
        return attributed
    }
}

// MARK: - Paywall Feature Model

struct PaywallFeature: Identifiable {
    let id: String
    let icon: String
    let color: Color
    let title: String
    let description: String

    /// Every Pro feature, in group order. Single source of truth for the list,
    /// the hero, and the source→hero mapping.
    static let all: [PaywallFeature] = [
        // Group 1 — Build lineups faster
        PaywallFeature(id: "autofill", icon: "bolt.fill", color: .blue,
                       title: "Auto-Fill Positions",
                       description: "Fill an inning or the whole game in one tap, fair play rules included."),
        PaywallFeature(id: "player_preferences", icon: "star.fill", color: .green,
                       title: "Position Preferences",
                       description: "Tag what each player can handle. Auto-Fill places them accordingly."),
        PaywallFeature(id: "lineup_template", icon: "square.stack.3d.up.fill", color: .blue,
                       title: "Lineup Templates",
                       description: "Save a lineup and rebuild it next week in one tap."),
        // Group 2 — Share it with your coaches and parents
        PaywallFeature(id: "pdf_export", icon: "doc.richtext.fill", color: .blue,
                       title: "Coaches Guide PDF",
                       description: "The full inning-by-inning grid, printed for the dugout."),
        PaywallFeature(id: "shared_teams", icon: "person.2.wave.2.fill", color: .green,
                       title: "Shared Teams",
                       description: "Invite an assistant coach to build positions with you."),
        // Group 3 — Track the whole season
        PaywallFeature(id: "game_history", icon: "clock.arrow.circlepath", color: .purple,
                       title: "Game History",
                       description: "Archive every game and keep a season record."),
        PaywallFeature(id: "ai_insights", icon: "sparkles", color: .orange,
                       title: "AI Coaching Insights",
                       description: "Spot bench-time and playing-time patterns across the season."),
        PaywallFeature(id: "pitch_tracking", icon: "figure.baseball", color: .red,
                       title: "Pitch Count Tracking",
                       description: "Weekly limits and rest days by age, checked as you assign."),
    ]

    /// Maps a paywall `source` string to the feature to lead with. Sources not
    /// listed here (settings, preview) get the generic hero. Team file flows are
    /// intentionally absent — that feature is free, so it has no hero.
    private static let sourceToID: [String: String] = [
        "autofill": "autofill",
        "player_preferences": "player_preferences",
        "lineup_template": "lineup_template",
        "pdf_export": "pdf_export",
        "game_history": "game_history",
    ]

    static func forSource(_ source: String) -> PaywallFeature? {
        guard let id = sourceToID[source] else { return nil }
        return all.first { $0.id == id }
    }
}

struct PaywallGroup: Identifiable {
    var id: String { title }
    let title: String
    let features: [PaywallFeature]

    static let all: [PaywallGroup] = [
        PaywallGroup(title: "Build lineups faster",
                     features: PaywallFeature.all.filter { ["autofill", "player_preferences", "lineup_template"].contains($0.id) }),
        PaywallGroup(title: "Share it with your coaches and parents",
                     features: PaywallFeature.all.filter { ["pdf_export", "shared_teams"].contains($0.id) }),
        PaywallGroup(title: "Track the whole season",
                     features: PaywallFeature.all.filter { ["game_history", "ai_insights", "pitch_tracking"].contains($0.id) }),
    ]
}

// MARK: - Pro Feature Row

struct ProFeatureRow: View {
    let feature: PaywallFeature

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: feature.icon)
                .font(.system(size: 20))
                .foregroundStyle(feature.color)
                .frame(width: 34, height: 34)
                .background(feature.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 1) {
                Text(feature.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(feature.description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

// MARK: - Preview

#Preview("Contextual — Auto-Fill") {
    PaywallView(source: "autofill")
        .environmentObject(PurchaseManager())
}

#Preview("Generic — Settings") {
    PaywallView(source: "settings")
        .environmentObject(PurchaseManager())
}
