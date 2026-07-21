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

    // Collapsible card disclosures (default closed, one-time setup)
    @State private var teamOpen = false
    @State private var addOpen = false

    // Tip overlay driven by parent iPhoneTabView

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
                isOpen: $teamOpen,
                onSettings: { showingEditTeam = true },
                onSwitch: { showingTeamSwitcher = true },
                onAddTeam: { showingAddTeam = true }
            )
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            if isReadOnly {
                ReadOnlyBanner()
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                addPlayersCard
            }
        }
    }

    @ViewBuilder
    private var playerRowsSection: some View {
        if !store.players.isEmpty {
            let deleteAction: ((IndexSet) -> Void)? = isReadOnly ? nil : { offsets in
                store.deletePlayer(at: offsets)
            }
            Section {
                ForEach(store.players) { player in
                    PlayerRosterRow(player: player, isReadOnly: isReadOnly) {
                        playerToEdit = player
                    }
                    .alignmentGuide(.listRowSeparatorLeading) { _ in 68 }
                }
                .onDelete(perform: deleteAction)
            } header: {
                Text("Roster · \(store.players.count) \(store.players.count == 1 ? "player" : "players")")
            }
        }
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

    private var addPlayersCard: some View {
        VStack(spacing: 0) {
            // Header row — toggles the disclosure
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { addOpen.toggle() }
            } label: {
                HStack(spacing: 13) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.blue.opacity(0.12))
                            .frame(width: 30, height: 30)
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.blue)
                    }

                    Text("Add players")
                        .font(.body)
                        .foregroundColor(.primary)

                    Spacer(minLength: 4)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(.tertiaryLabel))
                        .rotationEffect(.degrees(addOpen ? 180 : 0))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded actions
            if addOpen {
                VStack(spacing: 8) {
                    AddPlayerActionButton(
                        icon: "person.badge.plus",
                        title: "New Player",
                        trailing: "Add one",
                        style: .primary
                    ) { showingAddPlayer = true }

                    AddPlayerActionButton(
                        icon: "list.bullet",
                        title: "Bulk Add",
                        trailing: "Paste a roster",
                        style: .secondary
                    ) { showingBulkAdd = true }

                    AddPlayerActionButton(
                        icon: "square.and.arrow.down",
                        title: "GameChanger",
                        trailing: "Import CSV",
                        style: .secondary
                    ) {
                        Analytics.signal("roster.import.started")
                        showingImportInstructions = true
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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

    @Binding var isOpen: Bool
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
        VStack(spacing: 0) {
            // Header row — swatch + name + gear + divider + switch, all on one line
            HStack(spacing: 12) {
                Circle()
                    .fill(store.teamColor)
                    .frame(width: 30, height: 30)
                    .overlay(
                        Circle().strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
                    )

                Text(store.teamName.isEmpty ? "Unnamed Team" : store.teamName)
                    .font(.title3.weight(.bold))
                    .lineLimit(1)

                Spacer(minLength: 4)

                // Settings gear — opens Edit Team sheet
                Button(action: onSettings) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)

                Divider()
                    .frame(width: 0.5, height: 22)

                // Add Team when solo, Switch when multiple teams exist
                Button(action: store.teams.count > 1 ? onSwitch : onAddTeam) {
                    Text(store.teams.count > 1 ? "Switch" : "Add Team")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            // Team setup disclosure
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isOpen.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text("Team setup")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.secondary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(.tertiaryLabel))
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded pills
            if isOpen {
                FlowPills(spacing: 6) {
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// Small pill used inside TeamCardView
private struct TeamInfoPill: View {
    let label: String
    let color: Color

    // Orange pills use a darker text tone so they stay legible on a light fill.
    private var textColor: Color {
        if color == .secondary { return .secondary }
        if color == .orange { return Color(red: 0.78, green: 0.42, blue: 0.0) }
        return color
    }

    var body: some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .foregroundColor(textColor)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                color == .secondary
                    ? Color(.systemGray5)
                    : color.opacity(color == .green ? 0.15 : 0.12)
            )
            .clipShape(Capsule())
            .lineLimit(1)
            .fixedSize()
    }
}

// MARK: - Add Player Action Button

private struct AddPlayerActionButton: View {
    enum Style { case primary, secondary }

    let icon: String
    let title: String
    let trailing: String
    let style: Style
    let action: () -> Void

    private var background: Color {
        style == .primary ? .blue : Color(.systemGray5)
    }
    private var iconColor: Color {
        style == .primary ? .white : .blue
    }
    private var titleColor: Color {
        style == .primary ? .white : .primary
    }
    private var trailingColor: Color {
        style == .primary ? Color.white.opacity(0.75) : .secondary
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(iconColor)
                    .frame(width: 22)

                Text(title)
                    .font(.callout.weight(.semibold))
                    .foregroundColor(titleColor)

                Spacer(minLength: 8)

                Text(trailing)
                    .font(.footnote)
                    .foregroundColor(trailingColor)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Flow Layout (wrapping pills)

/// Wraps its subviews left-to-right, moving to a new line when the row is full.
private struct FlowPills: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                totalHeight += rowHeight + spacing
                totalWidth = max(totalWidth, rowWidth)
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += (rowWidth > 0 ? spacing : 0) + size.width
                rowHeight = max(rowHeight, size.height)
            }
        }
        totalHeight += rowHeight
        totalWidth = max(totalWidth, rowWidth)
        return CGSize(width: min(totalWidth, maxWidth), height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width - bounds.minX > maxWidth {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
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
    @State private var showingSharedTeamsPaywall = false
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
                            exportTeamFile(id: id)
                        } label: {
                            HStack {
                                Label("Export Team File", systemImage: "square.and.arrow.up")
                                    .foregroundColor(.primary)
                                Spacer()
                            }
                        }

                        Button {
                            showingTeamFilePicker = true
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
                                showingSharedTeamsPaywall = true
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
                                    showingSharedTeamsPaywall = true
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
            .fullScreenCover(isPresented: $showingSharedTeamsPaywall) {
                ProGate(source: "shared_teams", navTitle: "Shared Teams")
                    .environmentObject(purchaseManager)
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
            .fullScreenCover(isPresented: $showingPaywall) {
                ProGate(source: "player_preferences", navTitle: "Position Preferences") {
                    PreferencesPreviewView()
                }
                .environmentObject(purchaseManager)
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

    // Only positions currently enabled under this team's Fair Play rules.
    // Mirrors activeFieldPositions(config:) usage in DefensiveGridView and
    // PositionSummaryView so preferences never show a position that can't
    // actually be assigned (e.g. LCF/RCF when outfielderCount == 3, or
    // Pitcher/Catcher when disabled).
    private var availablePositions: [FieldPosition] {
        store.lineup.activeFieldPositions(config: store.fairPlayConfig)
            .filter { $0.isInfield || $0.isOutfield }
    }

    private var positionPreferencesSection: some View {
        Section {
            ForEach(availablePositions, id: \.self) { position in
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

    // Positions for a tier, sorted, joined with ", ". Empty string if none.
    private func positions(for tier: PositionPreferenceTier) -> String {
        player.positionPreferences
            .filter { $0.value == tier }
            .map { $0.key.rawValue }
            .sorted()
            .joined(separator: ", ")
    }

    private var strengthPositions: String { positions(for: .strength) }
    private var capablePositions:  String { positions(for: .capable) }
    private var neverPositions:    String { positions(for: .never) }
    private var emergencyPositions: String { positions(for: .emergency) }

    private var hasPlays: Bool { !strengthPositions.isEmpty || !capablePositions.isEmpty }
    private var hasAvoid: Bool { !neverPositions.isEmpty || !emergencyPositions.isEmpty }
    private var hasAnyPreference: Bool { hasPlays || hasAvoid }

    // Tier pill colors — green strength, blue capable, red never, orange emergency.
    private let greenText = Color(red: 0.13, green: 0.63, blue: 0.24)   // ~#22A03D
    private let blueText  = Color.blue
    private let redText   = Color(red: 0.81, green: 0.23, blue: 0.20)   // ~#CF3B34
    private let orangeText = Color(red: 0.78, green: 0.42, blue: 0.0)   // ~#C76B00

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Initials avatar
            ZStack {
                Circle()
                    .fill(avatarColor)
                Text(initials)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(avatarTextColor)
            }
            .frame(width: 40, height: 40)

            // Name + jersey + two-column preferences
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 7) {
                    Text(player.displayName)
                        .font(.body)
                        .lineLimit(1)
                    if !player.number.isEmpty {
                        Text("#\(player.number)")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color(.systemGray5))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }

                if hasAnyPreference {
                    HStack(alignment: .top, spacing: 18) {
                        preferenceColumn(
                            caption: "Plays",
                            pills: [
                                (strengthPositions, greenText, greenText.opacity(0.15)),
                                (capablePositions,  blueText,  blueText.opacity(0.12))
                            ]
                        )
                        preferenceColumn(
                            caption: "Avoid",
                            pills: [
                                (neverPositions, redText, redText.opacity(0.12)),
                                (emergencyPositions.isEmpty ? "" : "\(emergencyPositions)*",
                                 orangeText, orangeText.opacity(0.15))
                            ]
                        )
                    }
                } else {
                    Text("No preferences set")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .opacity(0.7)
                }
            }

            Spacer(minLength: 4)

            if !isReadOnly {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Color(.tertiaryLabel))
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isReadOnly { onEdit() }
        }
    }

    // One PLAYS/AVOID column: uppercase caption over its stacked pills.
    // Skips the whole column if it has no pills. Skips empty pills within it.
    @ViewBuilder
    private func preferenceColumn(
        caption: String,
        pills: [(String, Color, Color)]
    ) -> some View {
        let visible = pills.filter { !$0.0.isEmpty }
        if !visible.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Text(caption.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(Color(.tertiaryLabel))
                    .kerning(0.4)
                ForEach(visible, id: \.0) { label, fg, bg in
                    pillView(label: label, fg: fg, bg: bg)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func pillView(label: String, fg: Color, bg: Color) -> some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .foregroundColor(fg)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
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
