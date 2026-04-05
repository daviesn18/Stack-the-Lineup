import SwiftUI

// MARK: - Settings View

struct SettingsView: View {
    @EnvironmentObject var store: LineupStore
    @EnvironmentObject var purchaseManager: PurchaseManager
    @Environment(\.dismiss) var dismiss
    @AppStorage("complianceChecksEnabled") private var complianceChecksEnabled = true
    @State private var showingTutorial = false
    @State private var showingQuickTips = false
    @State private var showingResetConfirmation = false
    @State private var showingPaywall = false

    var body: some View {
        NavigationStack {
            List {

                // MARK: - Pro Status
                Section {
                    if purchaseManager.isPro {
                        HStack(spacing: 12) {
                            Image(systemName: "star.circle.fill")
                                .foregroundColor(.blue)
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Stack the Lineup Pro")
                                    .font(.subheadline.bold())
                                Text("All features unlocked")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                    } else {
                        Button {
                            showingPaywall = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "star.circle")
                                    .foregroundColor(.blue)
                                    .font(.title3)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Upgrade to Pro")
                                        .font(.subheadline.bold())
                                        .foregroundColor(.primary)
                                    Text("Coaches Guide PDF, Game History & AI Insights")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Button {
                            Task { await purchaseManager.restore() }
                        } label: {
                            HStack {
                                if purchaseManager.isLoading {
                                    ProgressView().scaleEffect(0.8)
                                } else {
                                    Text("Restore Purchase")
                                }
                            }
                        }
                        .disabled(purchaseManager.isLoading)

                        if let error = purchaseManager.purchaseError {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                } header: {
                    Text("Subscription")
                }

                // MARK: - Help
                Section("Help & Support") {
                    Button {
                        showingTutorial = true
                    } label: {
                        Label("View Tutorial", systemImage: "play.circle.fill")
                    }

                    Button {
                        showingQuickTips = true
                    } label: {
                        Label("Quick Tips", systemImage: "lightbulb.fill")
                    }
                }

                // MARK: - Fair Play Rules
                Section {
                    Toggle(isOn: $complianceChecksEnabled) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Fair Play Rules")
                                .font(.body)
                            Text("Enforce infield/outfield requirements and consecutive bench warnings")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .tint(.blue)
                } header: {
                    Text("Lineup Rules")
                } footer: {
                    if complianceChecksEnabled {
                        Text("The app will warn you when players are missing required positions or sitting bench for consecutive innings.")
                    } else {
                        Text("Fair play rules are disabled. You can assign positions freely without warnings.")
                    }
                }

                // MARK: - About
                Section("About") {
                    HStack {
                        Text("App Name")
                        Spacer()
                        Text("Stack the Lineup")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Version")
                        Spacer()
                        Text("2.0")
                            .foregroundColor(.secondary)
                    }

                    Button {
                        if let url = URL(string: "mailto:support@stackthelineup.com") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack {
                            Text("Support")
                            Spacer()
                            Text("support@stackthelineup.com")
                                .foregroundColor(.secondary)
                                .font(.callout)
                        }
                    }
                }

                // MARK: - Data
                Section {
                    Button(role: .destructive) {
                        showingResetConfirmation = true
                    } label: {
                        Label("Reset All Data", systemImage: "trash.fill")
                    }
                } header: {
                    Text("Data")
                } footer: {
                    Text("This will delete all players, lineups, and reset your team settings. This action cannot be undone.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingTutorial) {
                WelcomeView()
            }
            .sheet(isPresented: $showingQuickTips) {
                QuickTipsView()
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
                    .environmentObject(purchaseManager)
            }
            .confirmationDialog("Reset All Data?", isPresented: $showingResetConfirmation, titleVisibility: .visible) {
                Button("Reset Everything", role: .destructive) {
                    resetAllData()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete all players, lineups, team name, and settings. This cannot be undone.")
            }
        }
    }

    private func resetAllData() {
        store.clearAllPlayers()
        store.updateTeamName("")
        store.updateTeamColor(.blue)
        UserDefaults.standard.set(false, forKey: "hasCompletedTutorial")
        complianceChecksEnabled = true
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .environmentObject(LineupStore())
        .environmentObject(PurchaseManager())
}
