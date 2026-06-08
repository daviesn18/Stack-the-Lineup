import CloudKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Players List

struct PlayersView: View {
    @EnvironmentObject var store: LineupStore
    @EnvironmentObject var purchaseManager: PurchaseManager
    @Environment(\.verticalSizeClass) var verticalSizeClass
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @State private var showingAddPlayer = false
    @State private var playerToEdit: Player?
    @State private var showingClearConfirmation = false
    @State private var showingSettings = false
    @State private var showingTips = false
    @State private var showingAddTeam = false
    @State private var showingEditTeam = false
    @State private var showingTeamSwitcher = false

    // Bulk add flow
    @State private var showingBulkAdd = false

    // Tip overlay driven by parent iPhoneTabView
    @Binding var showingTabTip: Bool

    // Roster import flow
    @State private var showingImportInstructions = false
    @State private var showingFileImporter = false
    @State private var parsedImport: ParsedImport?
    @State private var importError: ImportErrorWrapper?
    @State private var completionPrompt: CompletionPrompt?

    // Roster export flow
    @State private var exportShareItem: ExportShareItem?

    private var isReadOnly: Bool { store.activeTeam.isReadOnly }

    private struct ExportShareItem: Identifiable {
        let id = UUID()
        let data: Data
        let filename: String
    }

    private struct ParsedImport: Identifiable {
        let id = UUID()
        let filename: String
        let players: [RosterImporter.ImportedPlayer]
    }

    private struct ImportErrorWrapper: Identifiable {
        let id = UUID()
        let message: String
    }

    private struct CompletionPrompt: Identifiable {
        let id = UUID()
        let count: Int
        let firstImportedPlayerID: UUID?
    }

    var body: some View {
        NavigationStack {
            playerList
            .navigationTitle("Players")
            .navigationBarTitleDisplayMode(verticalSizeClass == .compact ? .inline : .large)
            .toolbar { toolbarContent }
            .sheet(isPresented: $showingBulkAdd) {
                BulkAddPlayersView()
                    .environmentObject(store)
            }
            .sheet(isPresented: $showingAddPlayer) {
                PlayerFormView(mode: .add)
            }
            .sheet(item: $playerToEdit) { player in
                PlayerFormView(mode: .edit(player))
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showingTips) {
                PageTipsView(page: .players)
            }
            .sheet(isPresented: $showingAddTeam) {
                TeamFormView(mode: .add)
                    .environmentObject(purchaseManager)
            }
            .sheet(isPresented: $showingEditTeam) {
                TeamFormView(mode: .edit(store.activeTeamID ?? UUID()))
                    .environmentObject(purchaseManager)
            }
            .sheet(isPresented: $showingTeamSwitcher) {
                TeamSwitcherSheet(
                    onAddTeam: {
                        showingTeamSwitcher = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            showingAddTeam = true
                        }
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showingImportInstructions) {
                RosterImportInstructionsView {
                    showingFileImporter = true
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [UTType.commaSeparatedText, UTType.data],
                allowsMultipleSelection: false,
                onCompletion: handleFileImporterResult
            )
            .sheet(item: $parsedImport) { parsed in
                RosterImportView(
                    parsedPlayers: parsed.players,
                    sourceFilename: parsed.filename
                ) { playersToImport in
                    commitImport(playersToImport)
                }
                .environmentObject(store)
            }
            .sheet(item: $completionPrompt) { prompt in
                RosterCompletionPromptView(importedCount: prompt.count) {
                    if let firstID = prompt.firstImportedPlayerID,
                       let player = store.players.first(where: { $0.id == firstID }) {
                        playerToEdit = player
                    }
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .alert(item: $importError) { wrapper in
                Alert(
                    title: Text("Couldn't Import Roster"),
                    message: Text(wrapper.message),
                    dismissButton: .default(Text("OK"))
                )
            }
            .sheet(item: $exportShareItem) { item in
                ShareSheet(items: [item.data], filename: item.filename)
            }
            .overlay {
                if showingTabTip {
                    TabFirstTipOverlay(
                        config: TabTipConfig(
                            tabName: "Players",
                            title: "Set position preferences",
                            body: "Tap the pencil icon next to any player and tag positions as Strength, Capable, Emergency, or Never. Auto-Fill uses these to build smarter lineups.",
                            accentColor: .blue,
                            targetRect: CGRect(x: 16, y: 238, width: 200, height: 44),
                            targetCornerRadius: 10,
                            arrowDirection: .up
                        ),
                        onDismiss: {
                            withAnimation(.easeOut(duration: 0.2)) {
                                showingTabTip = false
                                UserDefaults.standard.set(true, forKey: "hasSeenPlayersTabTip")
                            }
                        }
                    )
                    .ignoresSafeArea()
                    .zIndex(100)
                    .transition(.opacity)
                }
            }
        }
    }

    private var playerList: some View {
        List {
            teamCardSection
            playerRowsSection
            emptyStateSection
            clearAllSection
        }
    }

    @ViewBuilder
    private var teamCardSection: some View {
        Section {
            TeamCardView(
                onSettings: { showingEditTeam = true },
                onSwitch: { showingTeamSwitcher = true },
                onAddTeam: { showingAddTeam = true }
            )
            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            if isReadOnly {
                ReadOnlyBanner()
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                rosterActionsRow
            }
        }
    }

    private var playerRowsSection: some View {
        let deleteAction: ((IndexSet) -> Void)? = isReadOnly ? nil : { offsets in
            store.deletePlayer(at: offsets)
        }
        return ForEach(store.players) { player in
            PlayerRosterRow(player: player, isReadOnly: isReadOnly) {
                playerToEdit = player
            }
        }
        .onDelete(perform: deleteAction)
    }

    @ViewBuilder
    private var emptyStateSection: some View {
        if store.players.isEmpty {
            ContentUnavailableView(
                "No Players Yet",
                systemImage: "person.badge.plus",
                description: Text("Add players one at a time, paste your whole roster at once, or import from GameChanger.")
            )
            .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder
    private var clearAllSection: some View {
        if !store.players.isEmpty && !isReadOnly {
            Section {
                Button(role: .destructive) {
                    showingClearConfirmation = true
                } label: {
                    HStack {
                        Spacer()
                        Label("Clear All Players", systemImage: "person.slash")
                        Spacer()
                    }
                }
                .confirmationDialog("Clear All Players", isPresented: $showingClearConfirmation, titleVisibility: .visible) {
                    Button("Clear All Players", role: .destructive) {
                        store.clearAllPlayers()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This will remove all players and clear the entire lineup. This cannot be undone.")
                }
            }
        }
    }

    private var rosterActionsRow: some View {
        HStack(spacing: 0) {
            RosterActionButton(
                icon: "plus.circle.fill",
                iconColor: .blue,
                title: "New Player",
                subtitle: "Add Player"
            ) { showingAddPlayer = true }

            Divider().frame(height: 36)

            RosterActionButton(
                icon: "text.alignleft",
                iconColor: .gray,
                title: "Paste List",
                subtitle: "Bulk add"
            ) { showingBulkAdd = true }

            Divider().frame(height: 36)

            RosterActionButton(
                icon: "square.and.arrow.down",
                iconColor: .blue,
                title: "GameChanger",
                subtitle: "Import",
                iconBackground: .blue
            ) {
                Analytics.signal("roster.import.started")
                showingImportInstructions = true
            }
        }
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            EditButton()
                .opacity(isReadOnly ? 0 : 1)
                .disabled(isReadOnly)
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            HStack(spacing: 16) {
                if !store.players.isEmpty {
                    Button {
                        exportRoster()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                if horizontalSizeClass != .regular {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                }
                Button {
                    showingTips = true
                } label: {
                    Image(systemName: "info.circle")
                }
            }
        }
    }

    // MARK: - Roster Export

    private func exportRoster() {
        guard let data = RosterExporter.export(
            players: store.players,
            teamName: store.teamName
        ) else { return }
        let filename = RosterExporter.filename(teamName: store.teamName)
        exportShareItem = ExportShareItem(data: data, filename: filename)
        Analytics.signal("roster.export.completed", parameters: [
            "playerCount": "\(store.players.count)"
        ])
    }

    // MARK: - Roster Import

    private func handleFileImporterResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let needsScope = url.startAccessingSecurityScopedResource()
            defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                let filename = url.lastPathComponent
                switch RosterImporter.parse(data: data, filename: filename) {
                case .success(let players):
                    parsedImport = ParsedImport(filename: filename, players: players)
                case .failure(let err):
                    Analytics.signal("roster.import.failed", parameters: ["reason": "\(err)"])
                    importError = ImportErrorWrapper(message: err.errorDescription ?? "Unknown error.")
                }
            } catch {
                Analytics.signal("roster.import.failed", parameters: ["reason": "read_error"])
                importError = ImportErrorWrapper(message: "Couldn't read the file. Try again.")
            }
        case .failure:
            break
        }
    }

    private func commitImport(_ imported: [RosterImporter.ImportedPlayer]) {
        guard !imported.isEmpty else { return }
        let newPlayers = imported.map { entry -> Player in
            var player = Player(
                firstName: entry.firstName,
                lastName: entry.lastName,
                number: entry.jerseyNumber
            )
            // Apply rich data from .stlroster imports
            if let age = entry.leagueAge {
                player.leagueAge = age
            }
            if !entry.positionPreferences.isEmpty {
                var prefs: [FieldPosition: PositionPreferenceTier] = [:]
                for (posName, tierRaw) in entry.positionPreferences {
                    if let pos = FieldPosition.allCases.first(where: { $0.displayName == posName }),
                       let tier = PositionPreferenceTier(rawValue: tierRaw) {
                        prefs[pos] = tier
                    }
                }
                player.positionPreferences = prefs
            }
            return player
        }
        store.addPlayers(newPlayers)
        Analytics.signal("roster.import.completed", parameters: ["count": "\(newPlayers.count)"])

        let count = newPlayers.count
        let firstID = newPlayers.first?.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            completionPrompt = CompletionPrompt(count: count, firstImportedPlayerID: firstID)
        }
    }
}

// MARK: - Team Card

private struct TeamCardView: View {
    @EnvironmentObject var store: LineupStore

    let onSettings: () -> Void
    let onSwitch: () -> Void
    let onAddTeam: () -> Void

    private var team: Team? {
        store.teams.first(where: { $0.id == store.activeTeamID })
    }

    // Fair play pill: "Off" if all rules disabled, "Custom" if any rule differs
    // from the out-of-box defaults, "Default" otherwise.
    private var fairPlayLabel: String {
        guard let t = team else { return "Default" }
        let cfg = t.fairPlayConfig
        let allOff = !cfg.noConsecutiveBench
            && cfg.minimumFieldingInnings == 0
            && cfg.minimumInfieldInnings == 0
            && cfg.minimumOutfieldInnings == 0
        if allOff { return "Off" }
        let isDefault = cfg.noConsecutiveBench
            && cfg.minimumFieldingInnings == 4
            && cfg.minimumInfieldInnings == 1
            && cfg.minimumOutfieldInnings == 1
        return isDefault ? "Default" : "Custom"
    }

    // Pitching pill: Off when disabled. Default when enabled with unmodified LL preset.
    // Custom when enabled with any values changed, or a weekly cap added.
    private var pitchingLabel: String {
        guard let t = team else { return "Off" }
        let cfg = t.pitchingConfig
        guard cfg.rulesEnabled else { return "Off" }
        let preset: [PitchingAgeBracket: PitchingLimits] = [
            .u8:  PitchingLimits(dailyMax: 50, restDay1Min: 21, restDay2Min: 36),
            .u10: PitchingLimits(dailyMax: 75, restDay1Min: 21, restDay2Min: 36, restDay3Min: 51, restDay4Min: 66),
            .u12: PitchingLimits(dailyMax: 85, restDay1Min: 21, restDay2Min: 36, restDay3Min: 51, restDay4Min: 66),
            .u14: PitchingLimits(dailyMax: 95, restDay1Min: 21, restDay2Min: 36, restDay3Min: 51, restDay4Min: 66),
            .u16: PitchingLimits(dailyMax: 95, restDay1Min: 31, restDay2Min: 46, restDay3Min: 61, restDay4Min: 76)
        ]
        guard cfg.ageLimits.count == preset.count else { return "Custom" }
        for (bracket, limits) in preset {
            guard let stored = cfg.ageLimits[bracket],
                  stored.dailyMax == limits.dailyMax,
                  stored.restDay1Min == limits.restDay1Min,
                  stored.restDay2Min == limits.restDay2Min,
                  stored.restDay3Min == limits.restDay3Min,
                  stored.restDay4Min == limits.restDay4Min else { return "Custom" }
        }
        if cfg.weeklyLimitEnabled { return "Custom" }
        return "Default"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Top row: circle + name + gear + switch
            HStack(spacing: 10) {
                Circle()
                    .fill(store.teamColor)
                    .frame(width: 26, height: 26)

                Text(store.teamName.isEmpty ? "Unnamed Team" : store.teamName)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)

                Spacer(minLength: 4)

                // Settings gear — opens Edit Team sheet
                Button(action: onSettings) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .frame(width: 30, height: 30)
                        .background(Color(.systemGray5))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                // Add Team when solo, Switch when multiple teams exist
                Button(action: store.teams.count > 1 ? onSwitch : onAddTeam) {
                    Text(store.teams.count > 1 ? "Switch" : "Add Team")
                        .font(.caption.bold())
                        .foregroundColor(.blue)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            // Pills row — gets the full card width so nothing truncates
            HStack(spacing: 6) {
                TeamInfoPill(
                    label: "\(store.activeTeam.gameInningCount) innings",
                    color: .blue
                )
                TeamInfoPill(
                    label: "Fair play: \(fairPlayLabel)",
                    color: fairPlayLabel == "Custom" ? .green : .secondary
                )
                TeamInfoPill(
                    label: "Pitching: \(pitchingLabel)",
                    color: pitchingLabel == "Off" ? .secondary : (pitchingLabel == "Custom" ? .orange : .secondary)
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// Small pill used inside TeamCardView
private struct TeamInfoPill: View {
    let label: String
    let color: Color

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(color == .secondary ? .secondary : color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                color == .secondary
                    ? Color(.systemGray5)
                    : color.opacity(0.12)
            )
            .clipShape(Capsule())
            .lineLimit(1)
    }
}

// MARK: - Roster Action Button

private struct RosterActionButton: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    var iconBackground: Color? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(iconBackground != nil ? iconBackground!.opacity(1) : Color(.systemGray5))
                        .frame(width: 38, height: 38)
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(iconBackground != nil ? .white : iconColor)
                }
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Team Switcher Sheet

private struct TeamSwitcherSheet: View {
    @EnvironmentObject var store: LineupStore
    @Environment(\.dismiss) var dismiss

    let onAddTeam: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.teams) { team in
                        Button {
                            store.switchTeam(to: team.id)
                            dismiss()
                        } label: {
                            HStack(spacing: 14) {
                                Circle()
                                    .fill(team.color)
                                    .frame(width: 32, height: 32)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(team.name.isEmpty ? "Unnamed Team" : team.name)
                                        .font(.body)
                                        .foregroundColor(.primary)
                                    Text("\(team.players.count) \(team.players.count == 1 ? "player" : "players")")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                if team.id == store.activeTeamID {
                                    Image(systemName: "checkmark")
                                        .font(.body.bold())
                                        .foregroundColor(.blue)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section {
                    Button {
                        onAddTeam()
                    } label: {
                        Label("Add Team", systemImage: "plus.circle.fill")
                            .foregroundColor(.blue)
                    }
                }
            }
            .navigationTitle("My Teams")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Team Form

enum TeamFormMode {
    case add
    case edit(UUID)
}

struct TeamFormView: View {
    @EnvironmentObject var store: LineupStore
    @EnvironmentObject var purchaseManager: PurchaseManager
    @Environment(\.dismiss) var dismiss

    let mode: TeamFormMode

    @State private var teamName: String = ""
    @State private var teamColor: Color = .blue
    @State private var gameInningCount: Int = 7
    @State private var coachName: String = ""
    @State private var showingDeleteConfirmation = false
    @State private var showingShortenConfirmation = false
    @State private var showingFairPlayRules = false
    @State private var showingPitchingRules = false
    @State private var pendingInningCount: Int = 7
    @State private var teamExportShareItem: TeamExportShareItem?
    @State private var showingTeamFilePicker = false
    @State private var pendingTeamImport: TeamImporter.ImportedTeam? = nil
    @State private var teamImportError: String? = nil
    @State private var showingPaywallForTransfer = false
    @State private var cloudKitShareItem: CloudKitShareItem? = nil
    @State private var isPreparingShare = false
    @State private var sharePreparationError: String? = nil
    @State private var cloudKitManageItem: CloudKitShareItem? = nil
    @State private var isPreparingManage = false

    private struct TeamExportShareItem: Identifiable {
        let id = UUID()
        let data: Data
        let filename: String
    }

    /// Identifiable wrapper so the CKShare sheet can use .sheet(item:).
    private struct CloudKitShareItem: Identifiable {
        let id = UUID()
        let share: CKShare
        let container: CKContainer
        let teamName: String
    }

    private var assignedInningsInLineup: Int {
        guard isEditing, case .edit(let id) = mode,
              let team = store.teams.first(where: { $0.id == id }) else { return 0 }
        return team.lineup.innings.enumerated().reversed().first { _, inning in
            !inning.assignments.isEmpty
        }.map { $0.offset + 1 } ?? 0
    }

    var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    var title: String {
        isEditing ? "Edit Team" : "New Team"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Team Info") {
                    HStack {
                        Text("Team Name")
                        Spacer()
                        TextField("e.g. Yankees", text: $teamName)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                    }

                    ColorPicker("Team Color", selection: $teamColor, supportsOpacity: false)

                    // Coach Name — used to attribute lineup finalization in shared teams.
                    // Pre-filled from the device name on first launch; editable here.
                    if isEditing {
                        HStack {
                            Text("Your Name")
                            Spacer()
                            TextField("Coach name", text: $coachName)
                                .multilineTextAlignment(.trailing)
                                .autocorrectionDisabled()
                        }
                    }
                }

                Section {
                    Picker("Game Length", selection: $gameInningCount) {
                        ForEach(3...9, id: \.self) { count in
                            Text("\(count) innings").tag(count)
                        }
                    }

                    // Fair Play Rules — only available when editing an existing team
                    if isEditing, case .edit(let id) = mode {
                        Button {
                            showingFairPlayRules = true
                        } label: {
                            HStack {
                                Text("Fair Play Rules")
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .sheet(isPresented: $showingFairPlayRules) {
                            FairPlayRulesView(teamID: id)
                        }

                        Button {
                            showingPitchingRules = true
                        } label: {
                            HStack {
                                Text("Pitching Rules")
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .sheet(isPresented: $showingPitchingRules) {
                            PitchingRulesView(teamID: id)
                        }
                    }
                } header: {
                    Text("Game Settings")
                } footer: {
                    Text("Past archived games keep their original inning count.")
                }

                // Backup & Transfer — only in edit mode
                if isEditing, case .edit(let id) = mode {
                    Section {
                        Button {
                            if purchaseManager.isPro {
                                exportTeamFile(id: id)
                            } else {
                                showingPaywallForTransfer = true
                            }
                        } label: {
                            HStack {
                                Label("Export Team File", systemImage: "square.and.arrow.up")
                                    .foregroundColor(.primary)
                                Spacer()
                            }
                        }

                        Button {
                            if purchaseManager.isPro {
                                showingTeamFilePicker = true
                            } else {
                                showingPaywallForTransfer = true
                            }
                        } label: {
                            HStack {
                                Label("Import Team File", systemImage: "square.and.arrow.down")
                                    .foregroundColor(.primary)
                                Spacer()
                            }
                        }

                        // Share Team — creates or retrieves the CKShare and
                        // presents UIActivityViewController so the owner can send
                        // the invite link via Messages, Mail, AirDrop, etc.
                        Button {
                            if purchaseManager.isPro {
                                guard let team = store.teams.first(where: { $0.id == id }) else { return }
                                isPreparingShare = true
                                Task {
                                    do {
                                        var teamToShare = team
                                        if teamToShare.ckRecordName == nil {
                                            try await CloudKitManager.shared.ensureZoneExists()
                                            let recordName = try await CloudKitManager.shared.saveTeam(teamToShare)
                                            teamToShare.ckRecordName = recordName
                                            if let idx = store.teams.firstIndex(where: { $0.id == id }) {
                                                store.teams[idx].ckRecordName = recordName
                                            }
                                        }
                                        let (share, container) = try await CloudKitManager.shared.createShare(for: teamToShare)
                                        cloudKitShareItem = CloudKitShareItem(
                                            share: share,
                                            container: container,
                                            teamName: teamToShare.name
                                        )
                                    } catch {
                                        sharePreparationError = error.localizedDescription
                                    }
                                    isPreparingShare = false
                                }
                            } else {
                                showingPaywallForTransfer = true
                            }
                        } label: {
                            HStack {
                                Label("Share Team", systemImage: "person.2.wave.2")
                                    .foregroundColor(.primary)
                                Spacer()
                                if isPreparingShare {
                                    ProgressView().scaleEffect(0.8)
                                } else if store.teams.first(where: { $0.id == id })?.ckRecordName != nil {
                                    Text("Shared")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .disabled(isPreparingShare)

                        // Manage Access — only shown when the team is already shared.
                        // Opens UICloudSharingController so the owner can change
                        // per-participant permissions (read-only vs read-write) or
                        // stop sharing entirely.
                        if store.teams.first(where: { $0.id == id })?.ckRecordName != nil {
                            Button {
                                if purchaseManager.isPro {
                                    guard let team = store.teams.first(where: { $0.id == id }) else { return }
                                    isPreparingManage = true
                                    Task {
                                        do {
                                            let (share, container) = try await CloudKitManager.shared.createShare(for: team)
                                            cloudKitManageItem = CloudKitShareItem(
                                                share: share,
                                                container: container,
                                                teamName: team.name
                                            )
                                        } catch {
                                            sharePreparationError = error.localizedDescription
                                        }
                                        isPreparingManage = false
                                    }
                                } else {
                                    showingPaywallForTransfer = true
                                }
                            } label: {
                                HStack {
                                    Label("Manage Access", systemImage: "person.badge.key")
                                        .foregroundColor(.primary)
                                    Spacer()
                                    if isPreparingManage {
                                        ProgressView().scaleEffect(0.8)
                                    }
                                }
                            }
                            .disabled(isPreparingManage)
                        }
                    } header: {
                        Text("Backup & Transfer")
                    } footer: {
                        Text("Share your team with an assistant coach so you can both manage the lineup in real time. Or export a .stlteam file to back up your team manually.")
                    }
                }

                // Delete option — only in edit mode, only if more than 1 team exists
                if isEditing && store.teams.count > 1 {
                    Section {
                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            HStack {
                                Spacer()
                                Label("Delete Team", systemImage: "trash")
                                Spacer()
                            }
                        }
                    } footer: {
                        Text("Deleting a team removes all its players, lineup, and game history. This cannot be undone.")
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(teamName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Delete Team?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete Team", role: .destructive) {
                    if case .edit(let id) = mode {
                        store.deleteTeam(id: id)
                    }
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete \"\(teamName)\" and all its data.")
            }
            .confirmationDialog("Shorten game?", isPresented: $showingShortenConfirmation, titleVisibility: .visible) {
                Button("Shorten to \(pendingInningCount) Innings", role: .destructive) {
                    gameInningCount = pendingInningCount
                    commitSave()
                }
                Button("Cancel", role: .cancel) {
                    pendingInningCount = gameInningCount
                }
            } message: {
                Text("Your current lineup has positions assigned through inning \(assignedInningsInLineup). Shortening to \(pendingInningCount) innings will remove those assignments. Past archived games are not affected.")
            }
            .fileImporter(
                isPresented: $showingTeamFilePicker,
                allowedContentTypes: [.init(filenameExtension: "stlteam") ?? .data],
                allowsMultipleSelection: false
            ) { result in
                handleTeamFileImport(result)
            }
            .sheet(item: $teamExportShareItem) { item in
                ShareSheet(items: [item.data], filename: item.filename)
            }
            .sheet(item: $cloudKitShareItem) { item in
                CloudKitSharingView(share: item.share, container: item.container, teamName: item.teamName)
                    .ignoresSafeArea()
            }
            .sheet(item: $cloudKitManageItem) { item in
                CloudKitManageView(share: item.share, container: item.container)
                    .ignoresSafeArea()
            }
            .sheet(item: $pendingTeamImport) { imported in
                TeamImportView(imported: imported) { _ in
                    dismiss()
                }
                .environmentObject(store)
                .environmentObject(purchaseManager)
            }
            .alert("Couldn't Import Team", isPresented: .constant(teamImportError != nil)) {
                Button("OK") { teamImportError = nil }
            } message: {
                Text(teamImportError ?? "")
            }
            .sheet(isPresented: $showingPaywallForTransfer) {
                PaywallView(source: "team_export")
            }
            .alert("Couldn't Prepare Share", isPresented: .constant(sharePreparationError != nil)) {
                Button("OK") { sharePreparationError = nil }
            } message: {
                Text(sharePreparationError ?? "")
            }
            .onAppear {
                if case .edit(let id) = mode,
                   let team = store.teams.first(where: { $0.id == id }) {
                    teamName = team.name
                    teamColor = team.color
                    gameInningCount = team.gameInningCount
                    coachName = team.coachName
                }
            }
        }
    }

    private func save() {
        if isEditing,
           case .edit(let id) = mode,
           let team = store.teams.first(where: { $0.id == id }),
           gameInningCount < team.gameInningCount,
           assignedInningsInLineup > gameInningCount {
            pendingInningCount = gameInningCount
            gameInningCount = team.gameInningCount
            showingShortenConfirmation = true
            return
        }
        commitSave()
    }

    private func commitSave() {
        let trimmed = teamName.trimmingCharacters(in: .whitespaces)
        switch mode {
        case .add:
            store.addTeam(name: trimmed, color: teamColor)
            store.updateGameInningCount(gameInningCount)
        case .edit(let id):
            if let idx = store.teams.firstIndex(where: { $0.id == id }) {
                store.teams[idx].name = trimmed
                store.teams[idx].color = teamColor
                store.teams[idx].coachName = coachName.trimmingCharacters(in: .whitespaces)
            }
            store.updateGameInningCount(gameInningCount, for: id)
            store.save()
        }
        dismiss()
    }

    // MARK: - Backup & Transfer

    private func exportTeamFile(id: UUID) {
        guard let team = store.teams.first(where: { $0.id == id }),
              let data = TeamExporter.export(team: team) else { return }
        let filename = TeamExporter.filename(teamName: team.name)
        teamExportShareItem = TeamExportShareItem(data: data, filename: filename)
        Analytics.signal("team.exported", parameters: [
            "player_count": "\(team.players.count)",
            "game_count": "\(team.gameLogs.count)"
        ])
    }

    private func handleTeamFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let needsScope = url.startAccessingSecurityScopedResource()
            defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                switch TeamImporter.parse(data: data) {
                case .success(let imported):
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        pendingTeamImport = imported
                    }
                case .failure(let err):
                    Analytics.signal("team.import.failed", parameters: ["reason": "\(err)"])
                    teamImportError = err.errorDescription ?? "Unknown error."
                }
            } catch {
                Analytics.signal("team.import.failed", parameters: ["reason": "read_error"])
                teamImportError = "Couldn't read the file. Try again."
            }
        case .failure:
            break
        }
    }
}

// MARK: - Player Form

enum PlayerFormMode {
    case add
    case edit(Player)
}

struct PlayerFormView: View {
    @EnvironmentObject var store: LineupStore
    @EnvironmentObject var purchaseManager: PurchaseManager
    @Environment(\.dismiss) var dismiss

    let mode: PlayerFormMode

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var number = ""
    @State private var leagueAge: Int? = nil
    @State private var positionPreferences: [FieldPosition: PositionPreferenceTier] = [:]
    @State private var showingValidationError = false
    @State private var validationMessage = ""
    @State private var showingPaywall = false

    var title: String {
        switch mode {
        case .add: return "Add Player"
        case .edit: return "Edit Player"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Player Info
                Section("Player Info") {
                    TextField("First Name", text: $firstName)
                        .textContentType(.givenName)
                        .autocorrectionDisabled()

                    TextField("Last Name", text: $lastName)
                        .textContentType(.familyName)
                        .autocorrectionDisabled()

                    TextField("Jersey Number", text: $number)
                        .keyboardType(.numberPad)

                    LeagueAgeField(leagueAge: $leagueAge)
                }

                // MARK: Position Preferences
                if purchaseManager.isPro {
                    positionPreferencesSection
                } else {
                    lockedPreferencesSection
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(firstName.trimmingCharacters(in: .whitespaces).isEmpty ||
                                  lastName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .alert("Invalid Entry", isPresented: $showingValidationError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(validationMessage)
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView(source: "player_preferences")
            }
            .onAppear {
                if case .edit(let player) = mode {
                    firstName = player.firstName
                    lastName = player.lastName
                    number = player.number
                    leagueAge = player.leagueAge
                    positionPreferences = player.positionPreferences
                }
            }
        }
    }

    // MARK: - Position Preferences Section (Pro)

    private var positionPreferencesSection: some View {
        Section {
            ForEach(FieldPosition.infieldPositions + FieldPosition.outfieldPositions, id: \.self) { position in
                preferenceRow(for: position)
            }
        } header: {
            Text("Position Preferences")
        } footer: {
            Text("AutoFill will prioritize Strength and Capable positions. Emergency is used as a last resort. Never positions are never assigned.")
        }
    }

    private func preferenceRow(for position: FieldPosition) -> some View {
        HStack {
            Text(position.displayName)
            Spacer()
            Menu {
                Button {
                    positionPreferences.removeValue(forKey: position)
                } label: {
                    HStack {
                        Text("—  No Preference")
                        if positionPreferences[position] == nil {
                            Image(systemName: "checkmark")
                        }
                    }
                }

                Divider()

                ForEach(PositionPreferenceTier.allCases, id: \.self) { tier in
                    Button {
                        positionPreferences[position] = tier
                    } label: {
                        HStack {
                            Text(tier.displayName)
                            if positionPreferences[position] == tier {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                tierBadge(for: positionPreferences[position])
                    .transaction { $0.animation = nil }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func tierBadge(for tier: PositionPreferenceTier?) -> some View {
        // Fixed-width container sized to the widest label ("Secondary") so SwiftUI
        // never recalculates the badge width after menu selection.
        HStack(spacing: 4) {
            ZStack {
                // Invisible sizing ghost — always present, always full width
                Text("Emergency")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .hidden()

                if let tier {
                    Text(tier.displayName)
                        .font(.caption.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(tier.color, in: Capsule())
                } else {
                    Text("—")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(.systemGray5), in: Capsule())
                }
            }
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Locked Section (non-Pro)

    private var lockedPreferencesSection: some View {
        Section {
            Button {
                showingPaywall = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "lock.fill")
                        .foregroundColor(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Position Preferences")
                            .font(.body)
                            .foregroundColor(.primary)
                        Text("Tag Strength, Capable, Emergency, and Never positions per player. Requires Pro.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Save

    private func save() {
        let trimmedFirst = firstName.trimmingCharacters(in: .whitespaces)
        let trimmedLast = lastName.trimmingCharacters(in: .whitespaces)
        let trimmedNumber = number.trimmingCharacters(in: .whitespaces)

        if !trimmedNumber.isEmpty {
            let existingNumberId: UUID? = {
                if case .edit(let player) = mode { return player.id }
                return nil
            }()
            if store.players.contains(where: { $0.number == trimmedNumber && $0.id != existingNumberId }) {
                validationMessage = "Jersey #\(trimmedNumber) is already taken by another player."
                showingValidationError = true
                return
            }
        }

        // Analytics: fire if any preference was explicitly set
        if purchaseManager.isPro && !positionPreferences.isEmpty {
            let strengthCount = positionPreferences.values.filter { $0 == .strength }.count
            let neverCount = positionPreferences.values.filter { $0 == .never }.count
            Analytics.signal("player.preferences.set", parameters: [
                "strengthCount": "\(strengthCount)",
                "neverCount": "\(neverCount)"
            ])
        }

        switch mode {
        case .add:
            var player = Player(firstName: trimmedFirst, lastName: trimmedLast, number: trimmedNumber)
            player.leagueAge = leagueAge
            player.positionPreferences = purchaseManager.isPro ? positionPreferences : [:]
            store.addPlayer(player)
        case .edit(let existing):
            var updated = existing
            updated.firstName = trimmedFirst
            updated.lastName = trimmedLast
            updated.number = trimmedNumber
            updated.leagueAge = leagueAge
            updated.positionPreferences = purchaseManager.isPro ? positionPreferences : existing.positionPreferences
            store.updatePlayer(updated)
        }
        dismiss()
    }
}

// MARK: - Player Roster Row

struct PlayerRosterRow: View {
    let player: Player
    var isReadOnly: Bool = false
    let onEdit: () -> Void

    // Avatar background color — red if any Never, green if any Strength,
    // amber if Emergency/Capable only, blue if no preferences.
    private var avatarColor: Color {
        let prefs = player.positionPreferences.values
        if prefs.contains(.never)     { return Color(red: 0.99, green: 0.92, blue: 0.92) }
        if prefs.contains(.strength)  { return Color(red: 0.92, green: 0.95, blue: 0.87) }
        if prefs.contains(.emergency) { return Color(red: 0.98, green: 0.93, blue: 0.85) }
        return Color(.systemGray5)
    }

    private var avatarTextColor: Color {
        let prefs = player.positionPreferences.values
        if prefs.contains(.never)     { return Color(red: 0.64, green: 0.18, blue: 0.18) }
        if prefs.contains(.strength)  { return Color(red: 0.23, green: 0.43, blue: 0.07) }
        if prefs.contains(.emergency) { return Color(red: 0.52, green: 0.31, blue: 0.04) }
        return Color.secondary
    }

    private var initials: String {
        let first = player.firstName.first.map(String.init) ?? ""
        let last  = player.lastName.first.map(String.init) ?? ""
        return first + last
    }

    // Preference pills — one pill per tier, listing all positions for that tier.
    // e.g. "Never: C, RF" instead of separate "C Never" + "RF Never" pills.
    // Ordered: Never, Strength, Capable, Emergency.
    private var pills: [(String, Color, Color)] {
        let order: [PositionPreferenceTier] = [.never, .strength, .capable, .emergency]
        var result: [(String, Color, Color)] = []
        for tier in order {
            let positions = player.positionPreferences
                .filter { $0.value == tier }
                .map { $0.key.rawValue }
                .sorted()
            guard !positions.isEmpty else { continue }
            let (bg, fg) = tierColors(tier)
            let label = "\(tier.displayName): \(positions.joined(separator: ", "))"
            result.append((label, bg, fg))
        }
        return result
    }

    private func tierColors(_ tier: PositionPreferenceTier) -> (Color, Color) {
        switch tier {
        case .never:     return (Color(red:0.99,green:0.92,blue:0.92), Color(red:0.64,green:0.18,blue:0.18))
        case .strength:  return (Color(red:0.92,green:0.95,blue:0.87), Color(red:0.23,green:0.43,blue:0.07))
        case .capable:   return (Color(red:0.90,green:0.95,blue:0.98), Color(red:0.09,green:0.37,blue:0.65))
        case .emergency: return (Color(red:0.98,green:0.93,blue:0.85), Color(red:0.52,green:0.31,blue:0.04))
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            // Initials avatar
            ZStack {
                Circle()
                    .fill(avatarColor)
                Text(initials)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(avatarTextColor)
            }
            .frame(width: 32, height: 32)

            // Name + jersey + pills
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(player.displayName)
                        .font(.body)
                        .lineLimit(1)
                    if !player.number.isEmpty {
                        Text("#\(player.number)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color(.systemGray5))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
                if pills.isEmpty {
                    Text("No preferences set")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .opacity(0.6)
                } else {
                    // Two-column grid — equal width columns so column 2 always aligns
                    let left  = stride(from: 0, to: pills.count, by: 2).map { pills[$0] }
                    let right = stride(from: 1, to: pills.count, by: 2).map { pills[$0] }
                    HStack(alignment: .top, spacing: 6) {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(left, id: \.0) { label, bg, fg in
                                pillView(label: label, bg: bg, fg: fg)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if !right.isEmpty {
                            VStack(alignment: .leading, spacing: 3) {
                                ForEach(right, id: \.0) { label, bg, fg in
                                    pillView(label: label, bg: bg, fg: fg)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }

            Spacer(minLength: 4)

            // Edit button — hidden for read-only shared teams
            if !isReadOnly {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 3)
    }

    private func pillView(label: String, bg: Color, fg: Color) -> some View {
        Text(label)
            .font(.system(size: 9, weight: .medium))
            .foregroundColor(fg)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .lineLimit(1)
    }
}

// MARK: - League Age Field

/// Stepper-based integer input for league age.
/// Shows "—" when nil, increments/decrements between 4 and 19.
struct LeagueAgeField: View {
    @Binding var leagueAge: Int?

    private let minAge = 4
    private let maxAge = 19

    var body: some View {
        HStack {
            Text("League Age")
            Spacer()
            if let age = leagueAge {
                HStack(spacing: 12) {
                    Button {
                        if age > minAge {
                            leagueAge = age - 1
                        } else {
                            leagueAge = nil
                        }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundColor(age > minAge ? .blue : .secondary)
                            .font(.title3)
                    }
                    .buttonStyle(.plain)

                    Text("\(age)")
                        .font(.body.monospacedDigit())
                        .frame(minWidth: 24, alignment: .center)

                    Button {
                        if age < maxAge { leagueAge = age + 1 }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(age < maxAge ? .blue : .secondary)
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "minus.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.title3)

                    Text("—")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .frame(minWidth: 24, alignment: .center)

                    Button {
                        leagueAge = minAge
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.blue)
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
