import SwiftUI

// MARK: - Settings View

struct SettingsView: View {
    @EnvironmentObject var store: LineupStore
    @Environment(\.dismiss) var dismiss
    @AppStorage("complianceChecksEnabled") private var complianceChecksEnabled = true
    @State private var showingTutorial = false
    @State private var showingQuickTips = false
    @State private var showingResetConfirmation = false
    
    var body: some View {
        NavigationStack {
            List {
                // Help Section
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
                
                // Fair Play Rules Settings
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
                
                // App Information
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
                        Text("1.0")
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
                
                // Data Management
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
        // Clear all app data
        store.clearAllPlayers()
        store.teamName = ""
        store.teamColor = .blue
        
        // Reset tutorial flag
        UserDefaults.standard.set(false, forKey: "hasCompletedTutorial")
        
        // Reset fair play rules
        complianceChecksEnabled = true
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .environmentObject(LineupStore())
}
