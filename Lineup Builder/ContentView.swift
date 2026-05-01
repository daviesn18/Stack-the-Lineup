import SwiftUI

struct ContentView: View {
    @StateObject var store = LineupStore()
    @EnvironmentObject var purchaseManager: PurchaseManager
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.scenePhase) var scenePhase

    @State private var showingWelcome = !UserDefaults.standard.bool(forKey: "hasCompletedTutorial")
    @State private var showingArchive = false
    @State private var showingWhatsNew = false
    @State private var whatsNewContent: WhatsNewContent? = nil

    // Share-sheet roster import flow
    @State private var showingImportTeamPicker = false
    @State private var showingImportTeamForm = false
    @State private var showingImportPreview = false
    @State private var rosterImportError: RosterImportError?
    @State private var teamIDsBeforeNewTeamSheet: Set<UUID> = []
    @State private var shareSheetCompletionPrompt: ShareSheetCompletionPrompt?
    @State private var playerToEditFromShareSheet: Player?

    private struct RosterImportError: Identifiable {
        let id = UUID()
        let message: String
    }

    private struct ShareSheetCompletionPrompt: Identifiable {
        let id = UUID()
        let count: Int
        let firstImportedPlayerID: UUID?
    }

    // Tab selection — used to navigate to History when coach taps "Go to History"
    // in the multi-game nudge. 0=Players 1=Lineup 2=Positions 3=History
    @State private var selectedTab: Int = 1

    // Archive nudge state
    @State private var showingNudge = false
    @State private var nudgePastGameCount: Int = 0

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                // iPad — full planning dashboard
                iPadDashboardView(showingArchive: $showingArchive)
            } else {
                // iPhone — existing tab bar
                iPhoneTabView(showingArchive: $showingArchive, selectedTab: $selectedTab)
            }
        }
        .environmentObject(store)
        .tint(.blue)
        .onAppear {
            Analytics.signal("app.opened", parameters: [
                "playerCount": "\(store.players.count)"
            ])

            // MARK: - Existing User Grandfathering
            // Prevent first-launch onboarding UI from appearing for coaches
            // who are already mid-season after updating to this version.

            // Checklist: skip for any user who already has players or archived games.
            if !UserDefaults.standard.bool(forKey: "hasCompletedChecklist") {
                if !store.players.isEmpty || !store.gameLogs.isEmpty {
                    UserDefaults.standard.set(true, forKey: "hasCompletedChecklist")
                }
            }

            // Auto-Fill tip: skip for users who already have position preferences
            // set on at least one player — they know the feature exists.
            if !UserDefaults.standard.bool(forKey: "hasSeenAutoFillTip") {
                let hasAnyPreferences = store.players.contains { !$0.positionPreferences.isEmpty }
                if hasAnyPreferences {
                    UserDefaults.standard.set(true, forKey: "hasSeenAutoFillTip")
                }
            }

            if !showingWelcome, WhatsNewManager.shouldShow(), let content = WhatsNewContent.current {
                whatsNewContent = content
                showingWhatsNew = true
            }
        }
        .sheet(isPresented: $showingWelcome) {
            WelcomeView()
        }
        .sheet(isPresented: $showingWhatsNew) {
            if let content = whatsNewContent {
                WhatsNewView(content: content)
            }
        }
        .sheet(isPresented: $showingArchive) {
            ArchiveGameSheet()
                .environmentObject(store)
        }
        .sheet(isPresented: $showingImportTeamPicker) {
            RosterImportTeamPickerView(
                filename: importFilename ?? "",
                playerCount: importPlayerCount,
                onPickExistingTeam: { teamID in advanceToPreview(targetTeamID: teamID) },
                onCreateNewTeam: {
                    teamIDsBeforeNewTeamSheet = Set(store.teams.map { $0.id })
                    if case .awaitingTeamSelection(let f, let p) = store.pendingRosterImport {
                        store.pendingRosterImport = .awaitingNewTeamCreation(filename: f, players: p)
                    }
                    showingImportTeamForm = true
                },
                onCancel: { cancelPendingImport() }
            )
            .environmentObject(store)
        }
        .sheet(isPresented: $showingImportTeamForm, onDismiss: handleNewTeamSheetDismissed) {
            TeamFormView(mode: .add)
                .environmentObject(store)
        }
        .sheet(isPresented: $showingImportPreview) {
            if let filename = importFilename, let players = importPlayers {
                RosterImportView(parsedPlayers: players, sourceFilename: filename) { playersToImport in
                    commitShareSheetImport(playersToImport)
                }
                .environmentObject(store)
            }
        }
        .sheet(item: $shareSheetCompletionPrompt) { prompt in
            RosterCompletionPromptView(importedCount: prompt.count) {
                if let firstID = prompt.firstImportedPlayerID,
                   let player = store.players.first(where: { $0.id == firstID }) {
                    playerToEditFromShareSheet = player
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $playerToEditFromShareSheet) { player in
            PlayerFormView(mode: .edit(player))
                .environmentObject(store)
        }
        .alert(item: $rosterImportError) { wrapper in
            Alert(
                title: Text("Couldn't Import Roster"),
                message: Text(wrapper.message),
                dismissButton: .default(Text("OK")) { cancelPendingImport() }
            )
        }
        .onOpenURL { url in
            handleIncomingRosterURL(url)
        }
        .onChange(of: store.pendingRosterImport.isActive) { _, isActive in
            if isActive { selectedTab = 0 }
        }
        .alert(nudgeAlertTitle, isPresented: $showingNudge) {
            nudgeAlertButtons
        } message: {
            Text(nudgeAlertMessage)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                // Re-apply iCloud data when app returns to foreground so changes
                // made on another device are reflected immediately.
                store.load()
                // Check whether to show the archive nudge, after a short delay
                // so the store has settled from load().
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    checkArchiveNudge()
                }
            }
        }
    }

    // MARK: - Share-Sheet Roster Import

    private var importFilename: String? {
        switch store.pendingRosterImport {
        case .none: return nil
        case .awaitingTeamSelection(let f, _),
             .awaitingNewTeamCreation(let f, _),
             .readyForPreview(let f, _, _): return f
        }
    }

    private var importPlayers: [RosterImporter.ImportedPlayer]? {
        switch store.pendingRosterImport {
        case .none: return nil
        case .awaitingTeamSelection(_, let p),
             .awaitingNewTeamCreation(_, let p),
             .readyForPreview(_, let p, _): return p
        }
    }

    private var importPlayerCount: Int { importPlayers?.count ?? 0 }

    private func handleIncomingRosterURL(_ url: URL) {
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
        Analytics.signal("roster.import.shared", parameters: ["extension": url.pathExtension.lowercased()])
        let filename = url.lastPathComponent
        do {
            let data = try Data(contentsOf: url)
            switch RosterImporter.parse(data: data, filename: filename) {
            case .success(let players):
                if store.teams.isEmpty {
                    teamIDsBeforeNewTeamSheet = []
                    store.pendingRosterImport = .awaitingNewTeamCreation(filename: filename, players: players)
                    showingImportTeamForm = true
                } else {
                    store.pendingRosterImport = .awaitingTeamSelection(filename: filename, players: players)
                    showingImportTeamPicker = true
                }
            case .failure(let err):
                Analytics.signal("roster.import.failed", parameters: ["reason": "\(err)"])
                rosterImportError = RosterImportError(message: err.errorDescription ?? "Unknown error.")
            }
        } catch {
            Analytics.signal("roster.import.failed", parameters: ["reason": "read_error"])
            rosterImportError = RosterImportError(message: "Couldn't read the file. Try again.")
        }
    }

    private func advanceToPreview(targetTeamID: UUID) {
        guard let filename = importFilename, let players = importPlayers else { return }
        if store.activeTeamID != targetTeamID { store.switchTeam(to: targetTeamID) }
        store.pendingRosterImport = .readyForPreview(filename: filename, players: players, targetTeamID: targetTeamID)
        showingImportPreview = true
    }

    private func handleNewTeamSheetDismissed() {
        guard case .awaitingNewTeamCreation(let filename, let players) = store.pendingRosterImport else { return }
        let currentIDs = Set(store.teams.map { $0.id })
        let newTeamIDs = currentIDs.subtracting(teamIDsBeforeNewTeamSheet)
        if let newID = newTeamIDs.first {
            store.pendingRosterImport = .readyForPreview(filename: filename, players: players, targetTeamID: newID)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { showingImportPreview = true }
        } else {
            cancelPendingImport()
        }
    }

    private func commitShareSheetImport(_ imported: [RosterImporter.ImportedPlayer]) {
        guard !imported.isEmpty else { cancelPendingImport(); return }
        let newPlayers = imported.map { Player(firstName: $0.firstName, lastName: $0.lastName, number: $0.jerseyNumber) }
        store.addPlayers(newPlayers)
        Analytics.signal("roster.import.completed", parameters: ["count": "\(newPlayers.count)", "source": "share_sheet"])
        let count = newPlayers.count
        let firstID = newPlayers.first?.id
        cancelPendingImport()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            shareSheetCompletionPrompt = ShareSheetCompletionPrompt(count: count, firstImportedPlayerID: firstID)
        }
    }

    private func cancelPendingImport() {
        store.pendingRosterImport = .none
    }

    // MARK: - Archive Nudge

    /// UserDefaults key scoped to the active team so each team gets independent suppression.
    private var nudgeDismissedKey: String {
        "nudge_dismissed_date_\(store.activeTeamID?.uuidString ?? "default")"
    }

    /// True if the nudge was dismissed within the last 24 hours for this team.
    private var nudgeIsSuppressed: Bool {
        let last = UserDefaults.standard.double(forKey: nudgeDismissedKey)
        guard last > 0 else { return false }
        return Date().timeIntervalSince1970 - last < 86_400
    }

    private func checkArchiveNudge() {
        // Never stack nudge on top of welcome or whats-new sheets
        guard !showingWelcome, !showingWhatsNew else { return }
        guard store.lineup.isPastAndFinalized else { return }
        guard !nudgeIsSuppressed else { return }

        // Count is always 1 with the current single-lineup model.
        // Structured for easy expansion when multi-game ships.
        nudgePastGameCount = 1
        showingNudge = true

        Analytics.signal("archive.nudge.shown", parameters: [
            "gameCount": "\(nudgePastGameCount)",
            "isPro": purchaseManager.isPro ? "true" : "false"
        ])
    }

    private func dismissNudge() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: nudgeDismissedKey)
        Analytics.signal("archive.nudge.dismissed", parameters: [
            "isPro": purchaseManager.isPro ? "true" : "false"
        ])
    }

    // MARK: - Nudge Alert Content

    private var nudgeAlertTitle: String {
        nudgePastGameCount > 1 ? "Games to Archive" : "Game Played?"
    }

    private var nudgeAlertMessage: String {
        let opponent = store.lineup.opponent.isEmpty ? nil : store.lineup.opponent
        let dateStr = store.lineup.gameDate.formatted(date: .abbreviated, time: .omitted)

        if nudgePastGameCount > 1 {
            let teamName = store.teamName.isEmpty ? "your team" : store.teamName
            return "You have \(nudgePastGameCount) finalized games from \(teamName) that haven't been archived yet. Want to archive them now?"
        } else if let opp = opponent {
            return "Your game against \(opp) was on \(dateStr). Ready to archive it?"
        } else {
            return "Your game on \(dateStr) is ready to archive."
        }
    }

    @ViewBuilder
    private var nudgeAlertButtons: some View {
        if nudgePastGameCount > 1 {
            Button("Go to History") {
                selectedTab = 3
                Analytics.signal("archive.nudge.accepted", parameters: [
                    "isPro": purchaseManager.isPro ? "true" : "false"
                ])
            }
            Button("Not Yet", role: .cancel) {
                dismissNudge()
            }
        } else {
            Button("Archive Now") {
                showingArchive = true
                Analytics.signal("archive.nudge.accepted", parameters: [
                    "isPro": purchaseManager.isPro ? "true" : "false"
                ])
            }
            Button("Not Yet", role: .cancel) {
                dismissNudge()
            }
        }
    }
}

// MARK: - iPhone Tab View
// Extracted so ContentView stays clean.

private struct iPhoneTabView: View {
    @Binding var showingArchive: Bool
    @Binding var selectedTab: Int

    var body: some View {
        TabView(selection: $selectedTab) {
            PlayersView()
                .tabItem {
                    Label("Players", systemImage: "person.3.fill")
                }
                .tag(0)
            LineupView(showingArchive: $showingArchive)
                .tabItem {
                    Label("Lineup", systemImage: "list.number")
                }
                .tag(1)
            DefensiveGridView(showingArchive: $showingArchive, selectedTab: $selectedTab)
                .tabItem {
                    Label("Positions", systemImage: "baseball.diamond.bases")
                }
                .tag(2)
            GameLogsView()
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
                .tag(3)
        }
    }
}
