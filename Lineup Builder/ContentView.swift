import SwiftUI
import TipKit
import WidgetKit

struct ContentView: View {
    @StateObject var store = LineupStore()
    /// Owned here and injected so both idioms' navigation can observe it.
    @StateObject private var router = AppRouter()
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

    /// Player targeted by a deep link / Spotlight result / App Intent. Kept
    /// separate from playerToEditFromShareSheet so the two flows can't collide.
    @State private var routedPlayer: Player?

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
                iPhoneTabView(
                    showingArchive: $showingArchive,
                    selectedTab: $selectedTab,
                    // Hold the tour until the welcome/what's-new covers are gone.
                    // Fix A selects the Players tab during onAppear, which makes
                    // PlayersView "visible" underneath the welcome cover — and a
                    // popover would otherwise render on top of it.
                    tourEnabled: !showingWelcome && !showingWhatsNew
                )
            }
        }
        // Cross-platform welcome/what's-new gate for every tour tip. The iPhone
        // path also folds this into `tourEnabled` above; the iPad dashboard's
        // anchors have no per-anchor gate of their own, so this is what holds
        // their arc-1 tips off the welcome cards. See `tourActive` / `tourTip`.
        .environment(\.tourActive, !showingWelcome && !showingWhatsNew)
        .environmentObject(store)
        .environmentObject(router)
        .tint(.blue)
        // Reuse confirmations ("Copied to current game" / "Template saved").
        // Owned here because copying switches tabs out from under the screen
        // that triggered it.
        .overlay(alignment: .bottom) {
            if let toast = store.reuseToast {
                GameLogToast(text: toast)
                    // Clears the tab bar *and* the Lineup tab's export bar,
                    // which is where the copy flow lands.
                    .padding(.bottom, 104)
            }
        }
        .animation(.spring(duration: 0.35), value: store.reuseToast)
        .onChange(of: store.copiedFromGameOpponent) { _, opponent in
            // Copying from History lands the coach on the Lineup tab, where
            // the copied order is waiting under the "Copied from…" banner.
            if opponent != nil { selectedTab = 1 }
        }
        .onAppear {
            Analytics.signal("app.opened", parameters: [
                "playerCount": "\(store.players.count)"
            ])

            syncTourState()

            // First-run coaches land on the Players tab, where the tour's
            // ordered group begins. The default tab is Lineup (1), but every
            // Lineup/Positions tip is gated behind having a roster — so a fresh
            // coach who opens onto Lineup sees no tip at all until they wander
            // to Players on their own. Arc-suppressed (existing) coaches keep
            // the Lineup default.
            if !TipsConfigurator.arcOneSuppressed, store.players.isEmpty {
                selectedTab = 0
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
            // App/widget/Spotlight/Siri deep links route; everything else is a
            // shared file that still goes down the import paths.
            if router.handle(url) {
                return
            } else if url.pathExtension.lowercased() == "stlteam" {
                handleIncomingTeamURL(url)
            } else {
                handleIncomingRosterURL(url)
            }
        }
        .onChange(of: router.request) { _, request in
            guard let request else { return }
            applyRoute(request.route)
        }
        .sheet(item: $routedPlayer) { player in
            // Spotlight/Siri asked for this player specifically — open on their
            // Position Preferences rather than the top of the form.
            PlayerFormView(mode: .edit(player), focusPositionPreferences: true)
                .environmentObject(store)
        }
        .onChange(of: store.pendingRosterImport.isActive) { _, isActive in
            if isActive { selectedTab = 0 }
        }
        // Tour tips gate on real app state, so re-sync whenever it moves.
        // Collapsed into one observer — four separate onChange modifiers here
        // push this body past the type-checker's limit.
        .onChange(of: tourSignature) { _, _ in syncTourState() }
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

    // MARK: - Tour State

    /// Every piece of state a tour tip gates on, in one comparable value.
    private var tourSignature: String {
        let assignments = store.lineup.innings.reduce(0) { $0 + $1.assignments.count }
        return "\(store.players.count)-\(store.lineup.battingOrder.count)-\(assignments)-\(store.gameLogs.count)-\(purchaseManager.isPro)"
    }

    /// Mirrors store/entitlement state into the TipKit parameters that gate
    /// every tour tip. See ContextualTips.swift.
    private func syncTourState() {
        TourState.sync(
            players: store.players.count,
            battingOrder: store.lineup.battingOrder.count,
            hasAnyAssignments: store.lineup.innings.contains { !$0.assignments.isEmpty },
            archivedGames: store.gameLogs.count,
            isPro: purchaseManager.isPro
        )
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

    // MARK: - Deep Link / Intent Routing

    /// Applies a route to the state ContentView owns: which team is active, the
    /// iPhone tab selection, and any sheet the route targets.
    ///
    /// The iPad's tab selection is NOT set here — iPadDashboardView owns its own
    /// `DetailTab` and observes the router directly. Both consumers run for every
    /// request; only the one currently on screen has any effect.
    private func applyRoute(_ route: STLRoute) {
        // Bring the owning team forward first. A Spotlight hit for a player on a
        // different roster is otherwise a no-op: the tab changes and the player
        // isn't there.
        switch route {
        case .player(let playerID):
            if let owning = store.teams.first(where: { team in
                team.players.contains { $0.id == playerID }
            }), owning.id != store.activeTeamID {
                store.switchTeam(to: owning.id)
            }
        case .gameLog(let logID):
            if let owning = store.teams.first(where: { team in
                team.gameLogs.contains { $0.id == logID }
            }), owning.id != store.activeTeamID {
                store.switchTeam(to: owning.id)
            }
        case .team(let teamID):
            if store.teams.contains(where: { $0.id == teamID }), teamID != store.activeTeamID {
                store.switchTeam(to: teamID)
            }
        case .players, .lineup, .positions, .history:
            break
        }

        selectedTab = route.tab.iPhoneTag

        if case .player(let playerID) = route {
            routedPlayer = store.players.first { $0.id == playerID }
        }
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

private struct iPhoneTabView: View {
    @EnvironmentObject var store: LineupStore
    @EnvironmentObject var purchaseManager: PurchaseManager
    @Binding var showingArchive: Bool
    @Binding var selectedTab: Int
    /// False while the welcome or what's-new cover is up — holds every tour
    /// tip so none can present over that chrome.
    let tourEnabled: Bool

    var body: some View {
        TabView(selection: $selectedTab) {
            // isTourTabActive stands each tab's tour anchors down while the tab
            // is off-screen. TipKit presents an eligible tip the instant its
            // rules pass — even when the anchor lives in a sibling tab that's
            // instantiated but not visible — which puts a mispositioned popover
            // on whatever tab the coach is actually looking at. Gating on the
            // selection keeps every tip on its own tab.
            PlayersView(isTourTabActive: selectedTab == 0 && tourEnabled)
                .tabItem { Label("Players", systemImage: "person.3.fill") }
                .tag(0)
            LineupView(showingArchive: $showingArchive, isTourTabActive: selectedTab == 1 && tourEnabled)
                .tabItem { Label("Lineup", systemImage: "list.number") }
                .tag(1)
            DefensiveGridView(
                showingArchive: $showingArchive,
                selectedTab: $selectedTab,
                tourEnabled: tourEnabled
            )
                .tabItem { Label("Positions", systemImage: "baseball.diamond.bases") }
                .tag(2)
            GameLogsView(isTourTabActive: selectedTab == 3 && tourEnabled)
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(3)
        }
    }
}
