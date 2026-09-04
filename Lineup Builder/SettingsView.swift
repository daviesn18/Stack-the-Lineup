import SwiftUI
import TipKit
import MessageUI

// MARK: - Settings View

struct SettingsView: View {
    @EnvironmentObject var store: LineupStore
    @EnvironmentObject var purchaseManager: PurchaseManager
    @Environment(\.dismiss) var dismiss
    @State private var showingQuickTips = false
    @State private var showingSiriShortcuts = false
    @State private var showingResetConfirmation = false
    @State private var showingPaywall = false
    @State private var showingSeedConfirmation = false
    @State private var showingSeedDoneAlert = false
    @State private var seedSucceeded = false
    @State private var seedTeamName = "Test Team"
    /// The name actually used, so the result alert names the right team.
    @State private var seededTeamName = "Test Team"
    @State private var showingResetTipsConfirmation = false
    @State private var showingResetTipsDoneAlert = false
    @State private var showingTourRestartedAlert = false

    // Version-row tap counter for the debug data seeder. See the Version row below.
    @State private var versionTapCount = 0
    @State private var lastVersionTapAt: Date?

    // Diagnostics export — see the Email Diagnostics row and generateDiagnostics().
    @State private var diagnosticsText: String?
    @State private var isGeneratingDiagnostics = false
    @State private var showingMailComposer = false
    @State private var showingDiagnosticsFallback = false

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
                    } else if purchaseManager.showsLockedUI {
                        // Not `else`: while the entitlement is undetermined a
                        // paying coach would be shown an upgrade pitch.
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
                    // Re-entry for anyone who skipped or dismissed the tour.
                    // TourInSettingsTip is armed by skipping the welcome cards and
                    // tells the coach the tour lives here in Settings. On iPhone it
                    // anchors on the Players team card (the Settings gear is a nav-bar
                    // ToolbarItem, which popoverTip can't attach to); on iPad it points
                    // at the header's content gear directly. Either way it names this
                    // screen rather than this row — a coach who skipped needs to be
                    // told where Settings is, not shown a row they already found.
                    Button {
                        TipsConfigurator.restartTour()
                        showingTourRestartedAlert = true
                    } label: {
                        Label("Take the Tour", systemImage: "figure.walk.motion")
                    }

                    Button {
                        showingQuickTips = true
                    } label: {
                        Label("Quick Tips", systemImage: "lightbulb.fill")
                    }

                    // The permanent home for the phrase list. AskSiriTip fires
                    // once and points here; without this row the voice features
                    // are only findable by guessing the right words.
                    Button {
                        showingSiriShortcuts = true
                    } label: {
                        Label("Siri Shortcuts", systemImage: "mic.fill")
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

                    // Tap 7 times to reveal the debug data seeder.
                    //
                    // Deliberately not a long-press: press-and-hold on a version
                    // string is how iOS users select and copy text, so a real
                    // coach can reach it by accident. Seeding is additive (it
                    // adds "Test Team" and leaves every other team alone), but
                    // the new team syncs to their other devices, which is a
                    // confusing thing to happen unprompted.
                    //
                    // Taps must be within 2s of each other, so a stray tap while
                    // scrolling never accumulates toward the threshold.
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                            .foregroundColor(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        let now = Date()
                        if let last = lastVersionTapAt, now.timeIntervalSince(last) > 2 {
                            versionTapCount = 1
                        } else {
                            versionTapCount += 1
                        }
                        lastVersionTapAt = now

                        if versionTapCount >= 7 {
                            versionTapCount = 0
                            lastVersionTapAt = nil
                            seedTeamName = suggestedSeedName()
                            showingSeedConfirmation = true
                        }
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

                    // Emails a PII-safe state snapshot to support. No player,
                    // coach, or team names — see DiagnosticsReport. Given to
                    // coaches to send when a sharing or sync issue is otherwise
                    // invisible from our side.
                    Button {
                        generateDiagnostics()
                    } label: {
                        HStack {
                            Label("Email Diagnostics", systemImage: "stethoscope")
                            Spacer()
                            if isGeneratingDiagnostics {
                                ProgressView().scaleEffect(0.8)
                            }
                        }
                    }
                    .disabled(isGeneratingDiagnostics)
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
            .sheet(isPresented: $showingQuickTips) {
                QuickTipsView()
            }
            .sheet(isPresented: $showingSiriShortcuts) {
                SiriShortcutsView()
            }
            .fullScreenCover(isPresented: $showingPaywall) {
                ProGate(source: "settings", navTitle: "Stack the Lineup Pro")
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
            .alert("Create Test Team", isPresented: $showingSeedConfirmation) {
                TextField("Team name", text: $seedTeamName)
                Button("Create") { runSeed() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Creates a team with 10 fake players, 5 archived games, templates and a schedule. Your real teams are not affected.")
            }
            .alert(seedSucceeded ? "Test Team Created" : "Couldn't Create Test Team",
                   isPresented: $showingSeedDoneAlert) {
                Button("OK") { if seedSucceeded { dismiss() } }
            } message: {
                Text(seedSucceeded
                     ? "\"\(seededTeamName)\" is now your active team, with 10 players and 5 archived games. Delete it when you're done."
                     : "The team wasn't added. Check the console for the cause.")
            }
            .confirmationDialog("Reset Onboarding?", isPresented: $showingResetTipsConfirmation, titleVisibility: .visible) {
                Button("Reset Welcome and Tips", role: .destructive) {
                    resetOnboardingFlags()
                    showingResetTipsDoneAlert = true
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Resets the welcome cards, every tour tip, and the What's New sheet so they appear again. Your data is not affected.")
            }
            .alert("Onboarding Reset", isPresented: $showingResetTipsDoneAlert) {
                Button("OK") {}
            } message: {
                Text("Close and reopen the app to see the welcome cards again.")
            }
            .alert("Tour Reset", isPresented: $showingTourRestartedAlert) {
                Button("OK") { dismiss() }
            } message: {
                Text("Close and reopen the app, then tips will appear again as you move through the tabs.")
            }
            .sheet(isPresented: $showingMailComposer) {
                if let diagnosticsText {
                    MailComposeView(
                        recipient: "support@stackthelineup.com",
                        subject: "Stack the Lineup diagnostics",
                        body: "Tell us what happened here — the diagnostics are attached and repeated below.\n\n\(diagnosticsText)",
                        attachmentText: diagnosticsText,
                        attachmentFilename: "stl-diagnostics.txt",
                        onFinish: { showingMailComposer = false }
                    )
                    .ignoresSafeArea()
                }
            }
            .sheet(isPresented: $showingDiagnosticsFallback) {
                if let diagnosticsText, let data = diagnosticsText.data(using: .utf8) {
                    ShareSheet(items: [data], filename: "stl-diagnostics.txt")
                }
            }
        }
    }

    /// Builds the diagnostics snapshot, then presents Mail pre-addressed to
    /// support — or the share sheet when the device has no Mail account, so the
    /// coach can still send it however they like. Async only for the iCloud
    /// account-status round-trip inside the report.
    private func generateDiagnostics() {
        guard !isGeneratingDiagnostics else { return }
        isGeneratingDiagnostics = true
        Task {
            let text = await DiagnosticsReport.generate(store: store, purchaseManager: purchaseManager)
            diagnosticsText = text
            isGeneratingDiagnostics = false
            if MFMailComposeViewController.canSendMail() {
                showingMailComposer = true
            } else {
                showingDiagnosticsFallback = true
            }
        }
    }

    /// Seeds under the entered name and reports honestly.
    ///
    /// Lives outside `body` on purpose: SettingsView's body is already close to
    /// the type-checker's budget, and inlining this tipped it over.
    private func runSeed() {
        let trimmed = seedTeamName.trimmingCharacters(in: .whitespaces)
        seededTeamName = trimmed.isEmpty ? "Test Team" : trimmed
        // Only claim success when a team actually appeared. This used to be
        // unconditional, which made a failed seed look exactly like a good one.
        seedSucceeded = DebugDataSeeder.seed(into: store, name: seededTeamName) != nil
        showingSeedDoneAlert = true
    }

    /// A name that isn't already taken, so seeding a second and third team
    /// doesn't produce three identical rows in the switcher. Prefilled rather
    /// than forced — the field is editable and this is only the suggestion.
    private func suggestedSeedName() -> String {
        let base     = "Test Team"
        let existing = Set(store.teams.map(\.name))
        guard existing.contains(base) else { return base }
        var n = 2
        while existing.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }

    private func resetAllData() {
        store.clearAllPlayers()
        store.updateTeamName("")
        store.updateTeamColor(.blue)
        UserDefaults.standard.set(false, forKey: "hasCompletedTutorial")
        WhatsNewManager.reset()
    }

    /// Clears the welcome cards, then wipes the TipKit datastore so every tour
    /// tip is eligible again.
    /// Restores the whole first-run experience, not just part of it: the welcome
    /// cover, the TipKit tour, and the What's New sheet. What's New was missing
    /// here, so resetting left the release notes suppressed at their last-seen
    /// version and there was no way to see them again.
    private func resetOnboardingFlags() {
        UserDefaults.standard.removeObject(forKey: "hasCompletedTutorial")
        WhatsNewManager.reset()
        TipsConfigurator.restartTour()
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .environmentObject(LineupStore())
        .environmentObject(PurchaseManager())
}
