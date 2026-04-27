import SwiftUI
import StoreKit

// MARK: - PaywallView
// Presented as a sheet when a free user taps a Pro-gated feature.
// Shows what Pro unlocks, the live price fetched from StoreKit, a Buy button,
// and the required Restore Purchases link.

struct PaywallView: View {
    @EnvironmentObject var purchaseManager: PurchaseManager
    @Environment(\.dismiss) var dismiss
    let source: String

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {

                    // MARK: Hero
                    VStack(spacing: 10) {
                        Image(systemName: "star.circle.fill")
                            .font(.system(size: 64))
                            .foregroundColor(.blue)

                        Text("Stack the Lineup Pro")
                            .font(.title2.bold())

                        Text("Unlock the full coaching toolkit.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 8)

                    // MARK: Feature list
                    VStack(spacing: 16) {
                        ProFeatureRow(
                            icon: "bolt.fill",
                            iconColor: .blue,
                            title: "Auto-Fill Positions",
                            description: "Fill open positions for an inning or the whole game automatically — fair play rules always respected."
                        )
                        ProFeatureRow(
                            icon: "person.3.fill",
                            iconColor: .green,
                            title: "Multiple Teams",
                            description: "Manage two teams from one app, each with their own roster, lineup, and game history."
                        )
                        ProFeatureRow(
                            icon: "doc.richtext.fill",
                            iconColor: .blue,
                            title: "Coaches Guide PDF",
                            description: "Export a full inning-by-inning position grid — ready to print or share with assistants."
                        )
                        ProFeatureRow(
                            icon: "clock.arrow.circlepath",
                            iconColor: .purple,
                            title: "Game History",
                            description: "Archive every game and build a full season record with up to 20 saved lineups."
                        )
                        ProFeatureRow(
                            icon: "star.fill",
                            iconColor: .green,
                            title: "Position Preferences",
                            description: "Tag each player's positions as Strength, Capable, Emergency, or Never. AutoFill respects preferences — and Never positions are never assigned."
                        )
                        ProFeatureRow(
                            icon: "sparkles",
                            iconColor: .orange,
                            title: "AI Coaching Insights",
                            description: "On-device analysis highlights position trends and playing-time patterns across your season."
                        )
                    }
                    .padding(.horizontal)

                    // MARK: Error message (if any)
                    if let error = purchaseManager.purchaseError {
                        Text(error)
                            .font(.callout)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    // MARK: Buy button
                    Button {
                        Task { await purchaseManager.purchase() }
                    } label: {
                        Group {
                            if purchaseManager.isLoading {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text(buyButtonLabel)
                                    .font(.headline)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(14)
                    }
                    .disabled(purchaseManager.isLoading)
                    .padding(.horizontal)

                    // MARK: Restore (required by Apple)
                    Button {
                        Task { await purchaseManager.restore() }
                    } label: {
                        Text("Restore Purchase")
                            .font(.callout)
                            .foregroundColor(.blue)
                    }
                    .disabled(purchaseManager.isLoading)

                    Text("One-time purchase. No subscription.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 4)
            }
            .navigationTitle("Upgrade to Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not Now") { dismiss() }
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

    private var buyButtonLabel: String {
        if let product = purchaseManager.proProduct {
            return "Unlock Pro — \(product.displayPrice)"
        }
        return "Unlock Pro — $4.99"
    }
}

// MARK: - Pro Feature Row

struct ProFeatureRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(iconColor)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.bold())
                Text(description)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    PaywallView(source: "preview")
            .environmentObject(PurchaseManager())
    }
