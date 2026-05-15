import SwiftUI

// MARK: - Settings View

struct SettingsView: View {
    @EnvironmentObject var store: LineupStore
    @EnvironmentObject var purchaseManager: PurchaseManager
    @Environment(\.dismiss) var dismiss
    @State private var showingTutorial = false
    @State private var showingQuickTips = false
    @State private var showingResetConfirmation = false
    @State private var showingPaywall = false
    @State private var showingSeedConfirmation = false
    @State private var showingSeedDoneAlert = false
    @State private var showingResetTipsConfirmation = false
    @State private var showingResetTipsDoneAlert = false

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

                // MARK: - About
                Section("About") {
                    HStack {
                        Text("App Name")
                        Spacer()
                        Text("Stack the Lineup")
                            .foregroundColor(.secondary)
                    }

                    // Long-press 1.5s to reveal debug data seeder
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                            .foregroundColor(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onLongPressGesture(minimumDuration: 1.5) {
                        showingSeedConfirmation = true
                    }

                    // Long-press 1.5s to reset welcome cards and contextual tips
                    HStack {
                        Text("Build")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—")
                            .foregroundColor(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onLongPressGesture(minimumDuration: 1.5) {
                        showingResetTipsConfirmation = true
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
                PaywallView(source: "settings")
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
            .confirmationDialog("Seed Sample History?", isPresented: $showingSeedConfirmation, titleVisibility: .visible) {
                Button("Create Test Team") {
                    DebugDataSeeder.seed(into: store)
                    showingSeedDoneAlert = true
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Creates a separate \"Test Team\" with 10 fake players and 5 archived games. Your real teams are not affected.")
            }
            .alert("Test Team Created", isPresented: $showingSeedDoneAlert) {
                Button("OK") {}
            } message: {
                Text("Switch to \"Test Team\" from the Players tab to review the History tab. Delete the team when you're done.")
            }
            .confirmationDialog("Reset Onboarding?", isPresented: $showingResetTipsConfirmation, titleVisibility: .visible) {
                Button("Reset Welcome and Tips", role: .destructive) {
                    resetOnboardingFlags()
                    showingResetTipsDoneAlert = true
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Resets the welcome cards and all contextual tips so they appear again on next launch. Your data is not affected.")
            }
            .alert("Onboarding Reset", isPresented: $showingResetTipsDoneAlert) {
                Button("OK") {}
            } message: {
                Text("Close and reopen the app to see the welcome cards. Visit each tab to trigger the contextual tips.")
            }
        }
    }

    private func resetAllData() {
        store.clearAllPlayers()
        store.updateTeamName("")
        store.updateTeamColor(.blue)
        UserDefaults.standard.set(false, forKey: "hasCompletedTutorial")
        UserDefaults.standard.removeObject(forKey: "lastSeenWhatsNewVersion")
    }

    private func resetOnboardingFlags() {
        let keys = [
            "hasCompletedTutorial",
            "hasCompletedChecklist",
            "hasRunTabTipGrandfathering",
            "hasSeenPlayersTabTip",
            "hasSeenLineupDragTip",
            "hasSeenArchiveTip",
            "hasSeenPositionsTabTip",
            "hasSeenHistoryTabTip",
            "hasSeenAutoFillTip",
            "hasSeenPDFExportTip",
            "hasSeenScheduleImportTip",
            "hasSeenRosterImportTip",
        ]
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .environmentObject(LineupStore())
        .environmentObject(PurchaseManager())
}
