import CoreSpotlight
import SwiftUI
import TipKit
import WidgetKit
import os

struct ContentView: View {
    @StateObject var store = LineupStore()
    /// Observed here and injected so both idioms' navigation can observe it.
    /// Not `@StateObject` — App Intents set routes on `AppRouter.shared` from
    /// outside the view tree, potentially before this view is ever constructed.
    @ObservedObject private var router = AppRouter.shared
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

    // A CloudKit share invitation that failed to accept. Surfaced so a coach who
    // tapped "Join" and got nothing isn't left guessing — SceneDelegate records
    // the failure and ContentView presents it here.
    @State private var shareAcceptError: ShareAcceptErrorWrapper? = nil

    private struct ShareAcceptErrorWrapper: Identifiable {
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

    /// Nonce of the last route applied here, so a pending route is consumed once.
    @State private var lastHandledRouteNonce: UUID?

    /// Same, for a lineup FillLineupIntent computed and left for the store to
    /// apply. Drained only here — iPadDashboardView also observes the router,
    /// but ContentView owns the store on both idioms, so a second consumer
    /// would just write the same lineup twice.
    @State private var lastHandledFillNonce: UUID?

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

    // Shared-team join feedback. A tapped invite can take several seconds to
    // deliver server-side; this drives the banner that tells the assistant the
    // team is on its way, and the recovery if it doesn't arrive in the window.
    @State private var shareJoinPhase: ShareJoinPhase = .idle

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
        // Shared-team join feedback, top-aligned so it clears the toast above and
        // reads as "something is happening" the moment an invite is accepted.
        .overlay(alignment: .top) {
            ShareJoinBanner(
                phase: shareJoinPhase,
                onRetry: { retryShareJoin() },
                onDismiss: { withAnimation { shareJoinPhase = .idle } }
            )
            .padding(.horizontal)
        }
        .animation(.spring(duration: 0.35), value: shareJoinPhase)
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

            // Asks for notification permission once per install, then registers
            // for remote notifications on every launch so APNs re-issues the
            // token. That registration is the whole delivery path: the token
            // goes to a DeviceToken record in public CloudKit, and the
            // Cloudflare Worker reads it when a lineup is finalized.
            //
            // This comment used to say it "set up CloudKit subscriptions for
            // lineup-finalized alerts". It never did — there is no CKSubscription
            // anywhere in the app, and there never has been. Whether there
            // *should* be is a real question, since it would remove the Worker,
            // the token records and their whole failure surface; see backlog 4.7.
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
        .alert(item: $shareAcceptError) { wrapper in
            Alert(
                title: Text("Couldn't Join Team"),
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
        // Tapping an indexed player or team in system Spotlight. This does NOT
        // arrive through onOpenURL — see STLRoute.fromSpotlightIdentifier.
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            handleSpotlightSelection(activity)
        }
        // Both onAppear and onChange — a deep link that cold-launches the app can
        // set the route before this view is installed, and onChange alone would
        // never see it. See consumePendingRoute() in iPadDashboardView.
        .onAppear {
            consumePendingRoute()
            consumePendingFill()
        }
        .onChange(of: router.request) { _, _ in
            consumePendingRoute()
        }
        .onChange(of: router.pendingFill) { _, _ in
            consumePendingFill()
        }
        // A Pro-gated intent asking for the upgrade sheet. Presented here rather
        // than by the screen that owns the feature, because an intent can run
        // with any tab (or none) on screen.
        .sheet(item: $router.paywallRequest) { request in
            PaywallView(source: request.source)
                .environmentObject(purchaseManager)
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
        .remoteDeletionPrompt(store: store)
        .shareRevocationNotice(store: store)
        .coachNamePrompt(store: store)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                // Re-apply iCloud KV data immediately so changes from another device
                // appear before the CloudKit incremental fetch completes.
                store.load()
                // Pull CloudKit changes (owned + shared teams) concurrently.
                // The incremental merge overwrites the active team wholesale
                // (mergeCloudKitChanges), so a server copy that predates a just-
                // staged Auto-Fill can stomp it — the fill's own push is
                // debounced and may not have uploaded yet. Re-assert the fill
                // after the merge to repair that.
                Task {
                    await store.fetchCloudKitChanges()
                    consumePendingFill(reassert: true)
                }
                // Write this device's APNs token for every team, if one arrived
                // before there was a view to receive it. On a cold launch that
                // is the normal case, not the edge case — see backlog 1.9.
                // Runs after load() so store.teams is populated. No-ops once
                // the token has been written.
                DeviceTokenManager.shared.flushPendingRegistration(store: store)
                // Refresh the home screen widget so it reflects any changes made
                // on another device or since the last app session.
                WidgetCenter.shared.reloadAllTimelines()
                // Check whether to show the archive nudge, after a short delay
                // so the store has settled from load().
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    checkArchiveNudge()
                }
            } else {
                // Leaving the foreground (.inactive / .background): flush any
                // debounced CloudKit push so an edit made just before backgrounding
                // isn't stranded behind the trailing timer. The local write already
                // happened in save(); this only forces the cloud round-trip early.
                store.flushCloudPushes()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .apnsTokenReceived)) { _ in
            // The token itself came from AppDelegate straight into the manager;
            // this only prompts the write for the already-running case. Both
            // entry points drain the same flag, so whichever wins does the work
            // and the other finds nothing — same contract as share acceptance.
            DeviceTokenManager.shared.flushPendingRegistration(store: store)
        }
        .onReceive(NotificationCenter.default.publisher(for: .cloudKitShareAccepted)) { _ in
            // Both entry points drain the same stored value, so whichever wins
            // the race handles it and the other finds nothing.
            handleShareAcceptanceIfPending()
        }
        .onReceive(NotificationCenter.default.publisher(for: .cloudKitShareAcceptFailed)) { _ in
            // Same drain contract as acceptance: the stored value is the source
            // of truth, so this and the cold-launch .task can't double-alert.
            handleShareAcceptFailureIfPending()
        }
        .task {
            // The cold-launch half. Tapping an invite when the app isn't running
            // delivers the accept callback before this view subscribes above, so
            // the notification is posted to nobody. Without this the team lands
            // silently in the background at the next ordinary sync — which is
            // exactly what it did.
            handleShareAcceptanceIfPending()
            // A failed accept races the first render the same way; drain it here
            // too so a cold-launch failure still reaches the coach.
            handleShareAcceptFailureIfPending()
        }
    }

    /// Brings a just-accepted team to the foreground.
    ///
    /// Switching is the point: joining a team and then having to notice the team
    /// switcher changed is not joining it. `switchTeam` also registers this
    /// device for the new team's notifications, so a share that never gets
    /// switched to never gets a device token either.
    private func handleShareAcceptanceIfPending() {
        guard let accepted = PendingShareAcceptance.take() else { return }

        // A coach re-invited to a team they previously left still has its
        // tombstone, which would make mergeCloudKitChanges refuse the share.
        // Accepting an invite is an explicit re-add, so clear it first.
        if let rootRecordName = accepted.rootRecordName {
            store.tombstones.forget(teamID: nil, recordName: rootRecordName)
        }

        let teamIDsBefore = Set(store.teams.map { $0.id })
        joinSharedTeam(rootRecordName: accepted.rootRecordName, teamIDsBefore: teamIDsBefore)
    }

    /// Tells the coach a share invitation failed to accept. Drains the same
    /// stored value the notification and the cold-launch `.task` both feed, so a
    /// single failure produces a single alert.
    private func handleShareAcceptFailureIfPending() {
        guard let message = PendingShareAcceptFailure.take() else { return }
        shareAcceptError = ShareAcceptErrorWrapper(message: message)
    }

    /// Polls CloudKit until the just-accepted team lands, then foregrounds it and
    /// drops the coach on the Players tab. Drives `shareJoinPhase` so the UI can
    /// show the wait and recover if the team never arrives. Also used by the
    /// failure banner's Try Again, which is why the baseline is passed in rather
    /// than captured — a retry's "before" is the current roster, not the original.
    private func joinSharedTeam(rootRecordName: String?, teamIDsBefore: Set<UUID>) {
        // Prefer the record name CloudKit gave us. Falling straight to "whichever
        // team is new" misidentifies the target when the same fetch also brings
        // down other teams — which is normal on a device that has been offline.
        func joinedTeam() -> Team? {
            if let name = rootRecordName,
               let match = store.teams.first(where: { $0.ckRecordName == name }) {
                return match
            }
            return store.teams.first { !teamIDsBefore.contains($0.id) }
        }

        withAnimation { shareJoinPhase = .joining }

        Task {
            // CloudKit makes the owner's shared zone available on its own schedule
            // after accept() returns — routinely longer than a couple of seconds
            // on a cold launch, which is exactly when an invite tap lands. A single
            // fetch-then-give-up left the team to arrive via ordinary sync minutes
            // later, never foregrounded — the whole failure the invite flow exists
            // to prevent. So poll a bounded number of times, stopping the instant
            // the team appears. Worst case ~16s of retries, all in the background;
            // the coach sees the team the moment it lands, not on the next launch.
            let backoff: [Duration] = [
                .seconds(1), .seconds(2), .seconds(3), .seconds(5), .seconds(5)
            ]

            var joined: Team?
            for delay in backoff {
                try? await Task.sleep(for: delay)
                await store.fetchCloudKitChanges()
                if let found = joinedTeam() {
                    joined = found
                    break
                }
            }

            if let joined {
                store.switchTeam(to: joined.id)
                // Land on the roster — the first thing an assistant is here to do
                // is help build it, and it is where the team reads as "loaded".
                selectedTab = 0
                // Ask who this coach is, now that the answer has somewhere to go.
                // Joining is the receiving-side counterpart of the question
                // TeamSharingView asks before sending an invite: until it is
                // answered, everything this coach does reaches the head coach
                // attributed to "iPhone". See backlog 1.11.
                store.requestCoachNameIfPlaceholder(teamID: joined.id)
                withAnimation { shareJoinPhase = .idle }
                Analytics.signal("team.share.opened_after_accept")
            } else {
                // The invite was accepted but the shared zone never delivered the
                // team within the retry window. Surface it (so the coach isn't left
                // on a blank screen) and signal it: this is the metric that tells a
                // propagation delay we should wait longer for from a share that is
                // genuinely not arriving.
                withAnimation { shareJoinPhase = .failed(rootRecordName: rootRecordName) }
                Log.sync.error("Share accepted but no matching team arrived after retries")
                Analytics.signal("team.share.accept_no_team_arrived")
            }
        }
    }

    /// Re-runs the join from the failure banner. The team may simply have been
    /// slow; a fresh poll against the current roster picks it up if it has since
    /// landed, and re-surfaces the wait if it hasn't.
    private func retryShareJoin() {
        guard case .failed(let rootRecordName) = shareJoinPhase else { return }
        joinSharedTeam(
            rootRecordName: rootRecordName,
            teamIDsBefore: Set(store.teams.map { $0.id })
        )
    }

    // MARK: - Tour State

    /// Every piece of state a tour tip gates on, in one comparable value.
    /// Includes the team count so creating a second team re-triggers the sync
    /// even when the new (empty) team's other counts happen to match the old
    /// active team's — that is what lets the multi-team suppression fire.
    private var tourSignature: String {
        let assignments = store.lineup.innings.reduce(0) { $0 + $1.assignments.count }
        return "\(store.teams.count)-\(store.players.count)-\(store.lineup.battingOrder.count)-\(assignments)-\(store.gameLogs.count)-\(purchaseManager.isPro)"
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
        // A coach with more than one team has already been through the app; retire
        // the whole tour so a new roster doesn't replay it. Idempotent — does the
        // work once, then no-ops. See TipsConfigurator.
        TipsConfigurator.suppressTourForMultiTeamCoach(teamCount: store.teams.count)
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

    /// Applies any pending route exactly once. The nonce guard stops a
    /// re-appearance from re-applying the last route.
    private func consumePendingRoute() {
        guard let request = router.request,
              request.nonce != lastHandledRouteNonce else { return }
        // A first-ever drain in a brand new window must not replay a stale route.
        guard lastHandledRouteNonce != nil || request.isFresh else { return }
        lastHandledRouteNonce = request.nonce
        applyRoute(request.route)
    }

    /// Writes a lineup FillLineupIntent already computed. The intent can't do
    /// this itself: whenever the app is running, the store holds the
    /// authoritative copy and its next save() would overwrite a write made
    /// straight to storage.
    ///
    /// Applied by team id, and the owning team is brought forward first — both
    /// because "fill the Tigers lineup" shouldn't land on another roster, and
    /// because save() only pushes the *active* team to CloudKit, so mutating an
    /// inactive one would persist locally and never sync.
    ///
    /// Two entry points: the normal drain (onAppear / a `pendingFill` change)
    /// and a re-assert from the scenePhase `.active` handler after a CloudKit
    /// merge. Gated on freshness rather than a permanent "already handled"
    /// latch: a foreground CloudKit fetch can overwrite the active team wholesale
    /// (mergeCloudKitChanges), and because the fill's own push is debounced a
    /// server copy that predates the fill can land first and stomp it. The
    /// re-assert re-applies the fill the normal path already latched; past the
    /// 60s freshness window we stop, so a fill can't resurrect over a later edit
    /// — the same bound `consumePendingRoute` uses.
    ///
    /// Residual edge: a coach edit made in the seconds between the fill and the
    /// merge completing can be reverted by the re-assert. It restores the exact
    /// lineup the coach asked Siri for, not arbitrary data.
    ///
    /// The proper source fix has since landed: `Team.updatedAt` + the recency
    /// guard in `mergeCloudKitChanges` (`shouldApplyServerTeam`) now stop a stale
    /// server copy from stomping a locally-newer team at all. This re-assert is
    /// kept as belt-and-suspenders for the staged-fill nonce path.
    private func consumePendingFill(reassert: Bool = false) {
        guard let pending = router.pendingFill, pending.isFresh,
              store.teams.contains(where: { $0.id == pending.teamID }) else { return }
        // The normal path applies each fill once; only the post-merge re-assert
        // re-applies one it has already handled.
        if pending.nonce == lastHandledFillNonce && !reassert { return }
        lastHandledFillNonce = pending.nonce

        if pending.teamID != store.activeTeamID {
            store.switchTeam(to: pending.teamID)
        }
        store.activeTeam.lineup = pending.outcome.lineup
        store.save()
    }

    /// Turns a Spotlight result tap into a route. Resolved against the rosters
    /// actually in the store, so an identifier for a player deleted since the
    /// index was last written is dropped rather than opening the wrong screen.
    private func handleSpotlightSelection(_ activity: NSUserActivity) {
        guard let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
              let route = STLRoute.fromSpotlightIdentifier(
                  identifier,
                  playerIDs: Set(store.teams.flatMap { $0.players.map(\.id) }),
                  teamIDs: Set(store.teams.map(\.id))
              )
        else {
            Analytics.signal("spotlight.selection_unresolved")
            return
        }
        router.route(to: route)
    }

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

// MARK: - Shared-Team Join Feedback

/// Where a just-accepted invite is in the load cycle. `failed` carries the
/// CloudKit root record name so Try Again can re-poll for the same team.
private enum ShareJoinPhase: Equatable {
    case idle
    case joining
    case failed(rootRecordName: String?)
}

/// The banner shown while a tapped invite is being fetched, and if it doesn't
/// arrive in the retry window. Nothing shows in `.idle`, so it is safe to keep
/// mounted as a permanent overlay.
private struct ShareJoinBanner: View {
    let phase: ShareJoinPhase
    let onRetry: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        switch phase {
        case .idle:
            EmptyView()

        case .joining:
            HStack(spacing: 10) {
                ProgressView()
                Text("Getting the shared team…")
                    .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
            .transition(.move(edge: .top).combined(with: .opacity))

        case .failed:
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "icloud.slash")
                        .foregroundStyle(.secondary)
                    Text("That team hasn't arrived yet")
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 8)
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                Text("It'll appear here on its own once iCloud delivers it. Check your connection, or try again.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: onRetry) {
                    Text("Try Again")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
            .transition(.move(edge: .top).combined(with: .opacity))
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
