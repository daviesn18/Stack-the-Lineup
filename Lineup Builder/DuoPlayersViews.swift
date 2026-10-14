import SwiftUI
import TipKit
import UniformTypeIdentifiers

// MARK: - Tier Colors
//
// The design's preference-tier tints. Strength reads green, Capable blue,
// Emergency amber, Never red — the same meaning the rest of the app gives them,
// as pastel fills with a dark foreground.

extension PositionPreferenceTier {
    var duoBackground: Color {
        switch self {
        case .strength:  return Color(red: 235 / 255, green: 242 / 255, blue: 222 / 255)
        case .capable:   return Color(red: 230 / 255, green: 242 / 255, blue: 250 / 255)
        case .emergency: return Color(red: 250 / 255, green: 237 / 255, blue: 217 / 255)
        case .never:     return Color(red: 253 / 255, green: 235 / 255, blue: 235 / 255)
        }
    }

    var duoForeground: Color {
        switch self {
        case .strength:  return Color(red: 59 / 255, green: 110 / 255, blue: 18 / 255)
        case .capable:   return Color(red: 23 / 255, green: 94 / 255, blue: 166 / 255)
        case .emergency: return Color(red: 133 / 255, green: 79 / 255, blue: 10 / 255)
        case .never:     return Color(red: 163 / 255, green: 46 / 255, blue: 46 / 255)
        }
    }
}

// MARK: - Avatar

/// Initials in a tinted circle: red when the player has any Never, green for any
/// Strength, amber for Emergency, gray when there are no preferences. Same
/// rules as the Players list's avatar.
struct DuoAvatar: View {
    let player: Player
    var size: CGFloat = 34
    var fontSize: CGFloat = 13

    private var background: Color {
        let prefs = player.positionPreferences.values
        if prefs.contains(.never)     { return Color(red: 0.99, green: 0.92, blue: 0.92) }
        if prefs.contains(.strength)  { return Color(red: 0.92, green: 0.95, blue: 0.87) }
        if prefs.contains(.emergency) { return Color(red: 0.98, green: 0.93, blue: 0.85) }
        return Color(.systemGray5)
    }

    private var foreground: Color {
        let prefs = player.positionPreferences.values
        if prefs.contains(.never)     { return Color(red: 0.64, green: 0.18, blue: 0.18) }
        if prefs.contains(.strength)  { return Color(red: 0.23, green: 0.43, blue: 0.07) }
        if prefs.contains(.emergency) { return Color(red: 0.52, green: 0.31, blue: 0.04) }
        return .secondary
    }

    private var initials: String {
        let first = player.firstName.first.map(String.init) ?? ""
        let last = player.lastName.first.map(String.init) ?? ""
        return first + last
    }

    var body: some View {
        ZStack {
            Circle().fill(background)
            Text(initials)
                .font(.system(size: fontSize, weight: .semibold))
                .foregroundColor(foreground)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Players Column (left half)
//
// The team and the roster. Tapping a player selects them; their detail is in the
// right half, so nothing pushes and the halves never move.

struct DuoPlayersColumn: View {
    @Binding var selectedPlayerID: UUID?

    @EnvironmentObject var store: LineupStore
    @EnvironmentObject var purchaseManager: PurchaseManager

    @State private var addOpen = false
    @State private var showingAddPlayer = false
    @State private var showingBulkAdd = false
    @State private var showingImportInstructions = false
    @State private var showingEditTeam = false
    @State private var showingAddTeam = false
    @State private var showingClearConfirmation = false
    @State private var playerToEdit: Player?
    @State private var exportItem: ExportItem?

    private struct ExportItem: Identifiable {
        let id = UUID()
        let data: Data
        let filename: String
    }

    private var isReadOnly: Bool { store.activeTeam.isReadOnly }

    var body: some View {
        List {
            Section {
                teamRow
                if !isReadOnly {
                    addPlayersRow
                    if addOpen { addPlayerActions }
                }
            }

            if isReadOnly {
                Section {
                    ReadOnlyBanner()
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }

            if store.players.isEmpty {
                ContentUnavailableView(
                    "No Players Yet",
                    systemImage: "person.badge.plus",
                    description: Text("Add players one at a time, paste your whole roster at once, or import from GameChanger.")
                )
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(store.players) { player in
                        rosterRow(player)
                    }
                    .onDelete(perform: isReadOnly ? nil : { offsets in
                        store.deletePlayer(at: offsets)
                    })
                } header: {
                    HStack {
                        Text("Roster · \(store.players.count) \(store.players.count == 1 ? "player" : "players")")
                            .font(.system(size: 15, weight: .semibold))
                        Spacer()
                        Text("Tags show preferences")
                            .font(.system(size: 12))
                            .foregroundColor(Color(.secondaryLabel).opacity(0.75))
                    }
                    .foregroundColor(.secondary)
                    .textCase(nil)
                }

                Section {
                    Button {
                        exportRoster()
                    } label: {
                        Label("Export Roster", systemImage: "square.and.arrow.up")
                    }
                    if !isReadOnly {
                        Button(role: .destructive) {
                            showingClearConfirmation = true
                        } label: {
                            Label("Clear All Players", systemImage: "person.slash")
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .confirmationDialog("Clear All Players", isPresented: $showingClearConfirmation, titleVisibility: .visible) {
            Button("Clear All Players", role: .destructive) {
                store.clearAllPlayers()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove all players and clear the entire lineup. This cannot be undone.")
        }
        .sheet(isPresented: $showingAddPlayer) {
            PlayerFormView(mode: .add)
                .environmentObject(store)
                .environmentObject(purchaseManager)
        }
        .sheet(isPresented: $showingBulkAdd) {
            BulkAddPlayersView()
                .environmentObject(store)
        }
        .sheet(item: $playerToEdit) { player in
            PlayerFormView(mode: .edit(player))
                .environmentObject(store)
                .environmentObject(purchaseManager)
        }
        .sheet(isPresented: $showingEditTeam) {
            TeamFormView(mode: .edit(store.activeTeamID ?? UUID()))
                .environmentObject(store)
                .environmentObject(purchaseManager)
        }
        .sheet(isPresented: $showingAddTeam) {
            TeamFormView(mode: .add)
                .environmentObject(store)
                .environmentObject(purchaseManager)
        }
        .sheet(item: $exportItem) { item in
            ShareSheet(items: [item.data], filename: item.filename)
        }
        .modifier(DuoRosterImportFlow(
            isPresentingInstructions: $showingImportInstructions,
            onEditPlayer: { playerToEdit = $0 }
        ))
        .onAppear(perform: ensureSelection)
        .onChange(of: store.players) { _, _ in ensureSelection() }
    }

    /// The detail half always has someone to show while there's a roster.
    private func ensureSelection() {
        if let id = selectedPlayerID, store.players.contains(where: { $0.id == id }) { return }
        selectedPlayerID = store.players.first?.id
    }

    // MARK: Team

    private var teamRow: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(store.teamColor)
                .frame(width: 26, height: 26)
            Text(store.teamName.isEmpty ? "My Team" : store.teamName)
                .font(.system(size: 17, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 4)
            Button {
                showingEditTeam = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.blue)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Team Settings")

            Divider().frame(height: 20)

            Menu {
                if store.teams.count > 1 {
                    Section("Switch Team") {
                        ForEach(store.teams) { team in
                            Button {
                                store.switchTeam(to: team.id)
                            } label: {
                                HStack {
                                    Text(team.name.isEmpty ? "Unnamed Team" : team.name)
                                    if team.id == store.activeTeamID {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                }
                Button {
                    showingAddTeam = true
                } label: {
                    Label("Add Team", systemImage: "plus")
                }
            } label: {
                Text("Switch")
                    .font(.system(size: 16))
                    .foregroundColor(.blue)
            }
        }
        .frame(minHeight: 44)
    }

    private var addPlayersRow: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { addOpen.toggle() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 19))
                    .foregroundColor(.blue)
                Text("Add players")
                    .font(.system(size: 16))
                    .foregroundColor(.blue)
                Spacer(minLength: 4)
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(.tertiaryLabel))
                    .rotationEffect(.degrees(addOpen ? 180 : 0))
            }
            .frame(minHeight: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tourTip(Tour.players.currentTip as? PlayersAddTip, arrowEdge: .top)
        .tourTip(Tour.players.currentTip as? PlayersImportTip, arrowEdge: .top)
    }

    /// The existing add options: one player, paste a roster, GameChanger import.
    @ViewBuilder
    private var addPlayerActions: some View {
        Button { showingAddPlayer = true } label: {
            Label("New Player", systemImage: "person.badge.plus")
        }
        Button { showingBulkAdd = true } label: {
            Label("Bulk Add", systemImage: "list.bullet")
        }
        Button {
            Analytics.signal("roster.import.started")
            showingImportInstructions = true
        } label: {
            Label("GameChanger Import", systemImage: "square.and.arrow.down")
        }
    }

    // MARK: Roster

    private func rosterRow(_ player: Player) -> some View {
        let isSelected = player.id == selectedPlayerID
        let isAbsent = store.lineup.isAbsent(player)

        return Button {
            selectedPlayerID = player.id
        } label: {
            HStack(spacing: 10) {
                DuoAvatar(player: player)

                Text(player.displayName)
                    .font(.system(size: 16))
                    .foregroundColor(isAbsent ? .secondary : .primary)
                    .lineLimit(1)
                if !player.number.isEmpty {
                    Text("#\(player.number)")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.duoFill))
                }

                Spacer(minLength: 4)

                HStack(spacing: 3) {
                    ForEach(preferenceTags(for: player), id: \.position) { tag in
                        Text(tag.position.rawValue)
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundColor(tag.tier.duoForeground)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .frame(minWidth: 24)
                            .background(RoundedRectangle(cornerRadius: 4).fill(tag.tier.duoBackground))
                            .fixedSize()
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(.tertiaryLabel))
            }
            .frame(minHeight: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(isSelected ? Color.blue.opacity(0.1) : Color(.secondarySystemGroupedBackground))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Up to three tags: strengths first, then capable, then never, then emergency.
    private func preferenceTags(for player: Player) -> [(position: FieldPosition, tier: PositionPreferenceTier)] {
        func rank(_ tier: PositionPreferenceTier) -> Int {
            switch tier {
            case .strength:  return 0
            case .capable:   return 1
            case .never:     return 2
            case .emergency: return 3
            }
        }
        return player.positionPreferences
            .map { (position: $0.key, tier: $0.value) }
            .sorted {
                rank($0.tier) != rank($1.tier)
                    ? rank($0.tier) < rank($1.tier)
                    : $0.position.rawValue < $1.position.rawValue
            }
            .prefix(3)
            .map { $0 }
    }

    private func exportRoster() {
        guard let data = RosterExporter.export(players: store.players, teamName: store.teamName) else { return }
        exportItem = ExportItem(data: data, filename: RosterExporter.filename(teamName: store.teamName))
        Analytics.signal("roster.export.completed", parameters: [
            "playerCount": "\(store.players.count)"
        ])
    }
}

// MARK: - Roster Import Flow
//
// GameChanger import: instructions → file picker → preview → commit. The same
// steps the Players tab runs, factored out so the Duo's roster column can run
// them without hosting the whole Players view.

private struct DuoRosterImportFlow: ViewModifier {
    @Binding var isPresentingInstructions: Bool
    let onEditPlayer: (Player) -> Void

    @EnvironmentObject var store: LineupStore

    @State private var showingFileImporter = false
    @State private var parsedImport: ParsedImport?
    @State private var importError: ImportError?
    @State private var completionPrompt: CompletionPrompt?

    private struct ParsedImport: Identifiable {
        let id = UUID()
        let filename: String
        let players: [RosterImporter.ImportedPlayer]
    }

    private struct ImportError: Identifiable {
        let id = UUID()
        let message: String
    }

    private struct CompletionPrompt: Identifiable {
        let id = UUID()
        let count: Int
        let firstImportedPlayerID: UUID?
    }

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresentingInstructions) {
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
                        onEditPlayer(player)
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
    }

    private func handleFileImporterResult(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
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
                importError = ImportError(message: err.errorDescription ?? "Unknown error.")
            }
        } catch {
            Analytics.signal("roster.import.failed", parameters: ["reason": "read_error"])
            importError = ImportError(message: "Couldn't read the file. Try again.")
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
            // Apply rich data from .stlroster imports.
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

// MARK: - Player Detail (right half)

struct DuoPlayerDetail: View {
    let playerID: UUID?

    @EnvironmentObject var store: LineupStore
    @EnvironmentObject var purchaseManager: PurchaseManager

    @State private var playerToEdit: Player?

    private var isReadOnly: Bool { store.activeTeam.isReadOnly }

    private var player: Player? {
        store.players.first { $0.id == playerID } ?? store.players.first
    }

    private var positions: [FieldPosition] {
        store.lineup.activeFieldPositions(config: store.fairPlayConfig)
    }

    var body: some View {
        Group {
            if let player {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        header(player)
                        preferencesHeader
                        preferencesCard(player)
                        Text("AutoFill will prioritize Strength and Capable positions. Emergency is used as a last resort. Never positions are never assigned.")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 20)
                }
            } else {
                ContentUnavailableView(
                    "No Players",
                    systemImage: "person.badge.plus",
                    description: Text("Add players on the left to set their position preferences.")
                )
            }
        }
        .background(Color(.systemGroupedBackground))
        .sheet(item: $playerToEdit) { player in
            PlayerFormView(mode: .edit(player))
                .environmentObject(store)
                .environmentObject(purchaseManager)
        }
    }

    // MARK: Header

    private func header(_ player: Player) -> some View {
        HStack(spacing: 12) {
            DuoAvatar(player: player, size: 52, fontSize: 19)
            VStack(alignment: .leading, spacing: 2) {
                Text(player.displayName)
                    .font(.system(size: 22, weight: .bold))
                    .tracking(-0.4)
                    .lineLimit(1)
                let details = [
                    player.number.isEmpty ? nil : "#\(player.number)",
                    player.leagueAge.map { "League age \($0)" }
                ].compactMap { $0 }
                if !details.isEmpty {
                    Text(details.joined(separator: " · "))
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
            }
            Spacer(minLength: 4)
            if !isReadOnly {
                Button("Edit") { playerToEdit = player }
                    .font(.system(size: 16))
            }
        }
    }

    // MARK: Preferences

    private var preferencesHeader: some View {
        HStack {
            Text("POSITION PREFERENCES")
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.4)
            Spacer()
            if !isReadOnly {
                Text("Tap to change")
                    .font(.system(size: 12))
            }
        }
        .foregroundColor(.secondary)
    }

    private func preferencesCard(_ player: Player) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(positions.enumerated()), id: \.element) { index, position in
                Button {
                    cycle(position, for: player)
                } label: {
                    HStack(spacing: 12) {
                        Text(position.rawValue)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .frame(minWidth: 32)
                            .background(RoundedRectangle(cornerRadius: 6).fill(position.badgeColor))
                        Text(position.displayName)
                            .font(.system(size: 16))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        tierCapsule(player.positionPreferences[position])
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isReadOnly)

                if index < positions.count - 1 {
                    Divider().padding(.leading, 14)
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))
    }

    private func tierCapsule(_ tier: PositionPreferenceTier?) -> some View {
        Text(tier?.displayName ?? "None")
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(tier?.duoForeground ?? .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(Capsule().fill(tier?.duoBackground ?? Color.duoFill))
    }

    /// Strength → Capable → Emergency → Never → None. Position preferences are
    /// a Pro feature; for anyone else the tap opens the edit sheet, which is
    /// where the unlock lives.
    private func cycle(_ position: FieldPosition, for player: Player) {
        guard !isReadOnly else { return }
        guard purchaseManager.isPro else {
            playerToEdit = player
            return
        }
        let next: PositionPreferenceTier?
        switch player.positionPreferences[position] {
        case nil:             next = .strength
        case .strength?:      next = .capable
        case .capable?:       next = .emergency
        case .emergency?:     next = .never
        case .never?:         next = nil
        }
        var updated = player
        if let next {
            updated.positionPreferences[position] = next
        } else {
            updated.positionPreferences.removeValue(forKey: position)
        }
        store.updatePlayer(updated)
    }
}
