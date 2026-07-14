import SwiftUI
import WidgetKit

struct ContentView: View {
    @StateObject var store = LineupStore()
    @EnvironmentObject var purchaseManager: PurchaseManager
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.scenePhase) var scenePhase

    @State private var showingWelcome = !UserDefaults.standard.bool(forKey: "hasCompletedTutorial")
    @State private var showingArchive = false
    @State private var showingWhatsNew = false
    @State private var whatsNewContent: WhatsNewContent? = nil

    // Share-sheet team file import flow (.stlteam)
    @State private var pendingTeamImport: TeamImporter.ImportedTeam? = nil
    @State private var teamImportError: TeamImportErrorWrapper? = nil
    @State private var teamImportToast: String? = nil

    private struct TeamImportErrorWrapper: Identifiable {
        let id = UUID()
        let message: String
    }

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

    // Grandfathering gate — runs once per install so a debug reset of this
    // flag allows contextual tips to re-appear without re-grandfathering.
    @AppStorage("hasRunTabTipGrandfathering") private var hasRunTabTipGrandfathering = false

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

            // v2.3 schedule import tip: skip for existing users who already
            // have game history — they're mid-season and don't need the prompt.
            if !UserDefaults.standard.bool(forKey: "hasSeenScheduleImportTip") {
                if !store.gameLogs.isEmpty || !store.players.isEmpty {
                    UserDefaults.standard.set(true, forKey: "hasSeenScheduleImportTip")
                }
            }

            // v2.3 roster import tip: skip for existing users who already
            // have players on their roster.
            if !UserDefaults.standard.bool(forKey: "hasSeenRosterImportTip") {
                if !store.players.isEmpty {
                    UserDefaults.standard.set(true, forKey: "hasSeenRosterImportTip")
                }
            }

            // PDF export tip: skip for existing users who have already archived
            // at least one game — they've been through the full workflow and
            // know the PDF export exists.
            if !UserDefaults.standard.bool(forKey: "hasSeenPDFExportTip") {
                if !store.gameLogs.isEmpty {
                    UserDefaults.standard.set(true, forKey: "hasSeenPDFExportTip")
                }
            }

            // MARK: Tab-First Tip Grandfathering
            // Any existing user (has players or archived games) should skip all
            // tab-first tips — they already know the app.
            // Gated so a debug reset of this flag re-enables the tips without
            // onAppear immediately re-grandfathering them.
            if !hasRunTabTipGrandfathering {
                hasRunTabTipGrandfathering = true
                let isExistingUser = !store.players.isEmpty || !store.gameLogs.isEmpty

                if !UserDefaults.standard.bool(forKey: "hasSeenPlayersTabTip") {
                    if isExistingUser { UserDefaults.standard.set(true, forKey: "hasSeenPlayersTabTip") }
                }
                if !UserDefaults.standard.bool(forKey: "hasSeenLineupDragTip") {
                    if !store.lineup.battingOrder.isEmpty || isExistingUser {
                        UserDefaults.standard.set(true, forKey: "hasSeenLineupDragTip")
                    }
                }
                if !UserDefaults.standard.bool(forKey: "hasSeenArchiveTip") {
                    if !store.gameLogs.isEmpty || isExistingUser {
                        UserDefaults.standard.set(true, forKey: "hasSeenArchiveTip")
                    }
                }
                if !UserDefaults.standard.bool(forKey: "hasSeenPositionsTabTip") {
                    let hasAssignments = store.lineup.innings.contains { !$0.assignments.isEmpty }
                    if hasAssignments || isExistingUser {
                        UserDefaults.standard.set(true, forKey: "hasSeenPositionsTabTip")
                    }
                }
                if !UserDefaults.standard.bool(forKey: "hasSeenHistoryTabTip") {
                    if !store.gameLogs.isEmpty || isExistingUser {
                        UserDefaults.standard.set(true, forKey: "hasSeenHistoryTabTip")
                    }
                }
            }

            // v3.0: Request push notification permission once and set up
            // CloudKit subscriptions for lineup-finalized alerts.
            NotificationManager.shared.requestPermissionIfNeeded()

            if !showingWelcome, WhatsNewManager.shouldShow(), let content = WhatsNewContent.current {
                whatsNewContent = content
                showingWhatsNew = true
            }
        }
        // New-user welcome cards — full screen cover so the dim overlay fills
        // edge-to-edge without the sheet's card handle chrome.
        .fullScreenCover(isPresented: $showingWelcome) {
            WelcomeCardsView()
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
                .environmentObject(purchaseManager)
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
        .sheet(item: $pendingTeamImport) { imported in
            TeamImportView(imported: imported) { toastMessage in
                teamImportToast = toastMessage
            }
            .environmentObject(store)
            .environmentObject(purchaseManager)
        }
        .alert(item: $teamImportError) { wrapper in
            Alert(
                title: Text("Couldn't Import Team"),
                message: Text(wrapper.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .onOpenURL { url in
            if url.scheme == "stackthelineup" {
                // Deep link from the home screen widget — jump straight to Lineup tab.
                selectedTab = 1
            } else if url.pathExtension.lowercased() == "stlteam" {
                handleIncomingTeamURL(url)
            } else {
                handleIncomingRosterURL(url)
            }
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
                // Re-apply iCloud KV data immediately so changes from another device
                // appear before the CloudKit incremental fetch completes.
                store.load()
                // Pull CloudKit changes (owned + shared teams) concurrently.
                Task { await store.fetchCloudKitChanges() }
                // Refresh the home screen widget so it reflects any changes made
                // on another device or since the last app session.
                WidgetCenter.shared.reloadAllTimelines()
                // Check whether to show the archive nudge, after a short delay
                // so the store has settled from load().
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    checkArchiveNudge()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .apnsTokenReceived)) { notification in
            guard let tokenData = notification.object as? Data else { return }
            DeviceTokenManager.shared.didRegister(deviceToken: tokenData, store: store)
        }
        .onReceive(NotificationCenter.default.publisher(for: .cloudKitShareAccepted)) { _ in
            // Capture current team IDs so we can detect the newly added shared
            // team after the fetch completes and switch to it automatically.
            let teamIDsBefore = Set(store.teams.map { $0.id })
            Task {
                // Give CloudKit a moment to finish processing the acceptance
                // server-side before fetching.
                try? await Task.sleep(for: .seconds(2))
                await store.fetchCloudKitChanges()
                // Switch to the newly added shared team so the coach sees it
                // immediately rather than having to notice the team switcher changed.
                if let newTeam = store.teams.first(where: { !teamIDsBefore.contains($0.id) }) {
                    store.switchTeam(to: newTeam.id)
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

    // MARK: - Share-Sheet Team File Import

    private func handleIncomingTeamURL(_ url: URL) {
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
        Analytics.signal("team.import.shared")
        do {
            let data = try Data(contentsOf: url)
            switch TeamImporter.parse(data: data) {
            case .success(let imported):
                pendingTeamImport = imported
            case .failure(let err):
                Analytics.signal("team.import.failed", parameters: ["reason": "\(err)"])
                teamImportError = TeamImportErrorWrapper(message: err.errorDescription ?? "Unknown error.")
            }
        } catch {
            Analytics.signal("team.import.failed", parameters: ["reason": "read_error"])
            teamImportError = TeamImportErrorWrapper(message: "Couldn't read the file. Try again.")
        }
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
// Owns all tab-first tip state and fires tips via onChange(of: selectedTab).
// This is more reliable than onAppear inside tab views, which SwiftUI may
// pre-fire at launch for all tabs before the user navigates to them.

private struct iPhoneTabView: View {
    @EnvironmentObject var store: LineupStore
    @EnvironmentObject var purchaseManager: PurchaseManager
    @Binding var showingArchive: Bool
    @Binding var selectedTab: Int

    // Tab-first tip flags — read/written via UserDefaults directly so that
    // a debug reset (which clears UserDefaults) is reflected immediately
    // without stale @AppStorage cache invalidation issues.
    @AppStorage("hasSeenPlayersTabTip")  private var hasSeenPlayersTabTip  = false
    @AppStorage("hasSeenLineupDragTip")  private var hasSeenLineupDragTip  = false
    @AppStorage("hasSeenArchiveTip")     private var hasSeenArchiveTip     = false
    @AppStorage("hasSeenPositionsTabTip") private var hasSeenPositionsTabTip = false
    @AppStorage("hasSeenHistoryTabTip")  private var hasSeenHistoryTabTip  = false

    // Local show-state passed as bindings into each tab view
    @State private var showingPlayersTabTip   = false
    @State private var showingLineupDragTip   = false
    @State private var showingArchiveTabTip   = false
    @State private var showingPositionsTabTip = false
    @State private var showingHistoryTabTip   = false

    var body: some View {
        TabView(selection: $selectedTab) {
            PlayersView(showingTabTip: $showingPlayersTabTip)
                .tabItem { Label("Players", systemImage: "person.3.fill") }
                .tag(0)
            LineupView(
                showingArchive: $showingArchive,
                showingDragTip: $showingLineupDragTip,
                showingArchiveTip: $showingArchiveTabTip
            )
                .tabItem { Label("Lineup", systemImage: "list.number") }
                .tag(1)
            DefensiveGridView(
                showingArchive: $showingArchive,
                selectedTab: $selectedTab,
                showingTabTip: $showingPositionsTabTip
            )
                .tabItem { Label("Positions", systemImage: "baseball.diamond.bases") }
                .tag(2)
            GameLogsView(showingTabTip: $showingHistoryTabTip)
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(3)
        }
        .onChange(of: selectedTab) { _, newTab in
            fireTipIfNeeded(for: newTab)
        }
        .onAppear {
            // Fire tip for the initial tab (selectedTab = 1, Lineup) on first launch
            fireTipIfNeeded(for: selectedTab)
        }
    }

    private func fireTipIfNeeded(for tab: Int) {
        print("🟡 fireTipIfNeeded called for tab \(tab)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            print("🟡 After delay, tab \(tab), players flag: \(UserDefaults.standard.bool(forKey: "hasSeenPlayersTabTip"))")
            switch tab {
            case 0:
                if !UserDefaults.standard.bool(forKey: "hasSeenPlayersTabTip") {
                    print("🟢 Setting showingPlayersTabTip = true")
                    withAnimation(.easeOut(duration: 0.25)) { showingPlayersTabTip = true }
                }
            default:
                break
            }
        }
    }
}
