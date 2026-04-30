import SwiftUI

// MARK: - Players List

struct PlayersView: View {
    @EnvironmentObject var store: LineupStore
    @Environment(\.verticalSizeClass) var verticalSizeClass
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @State private var showingAddPlayer = false
    @State private var playerToEdit: Player?
    @State private var showingClearConfirmation = false
    @State private var showingSettings = false
    @State private var showingTips = false
    @State private var showingAddTeam = false
    @State private var showingEditTeam = false

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Team Section
                Section {
                    // Team name row — pencil icon signals editability
                    Button {
                        showingEditTeam = true
                    } label: {
                        HStack {
                            Text("Team Name")
                                .foregroundColor(.primary)
                            Spacer()
                            Text(store.teamName.isEmpty ? "Unnamed Team" : store.teamName)
                                .foregroundColor(.secondary)
                            Image(systemName: "pencil")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }

                    // Team color row — read only, reflects active team
                    HStack {
                        Text("Team Color")
                        Spacer()
                        Circle()
                            .fill(store.teamColor)
                            .frame(width: 24, height: 24)
                            .overlay(Circle().strokeBorder(Color(.systemGray4), lineWidth: 1))
                    }

                    // Switch team — only visible when multiple teams exist
                    if store.teams.count > 1 {
                        Menu {
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
                        } label: {
                            HStack {
                                Text("Switch Team")
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "arrow.left.arrow.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("Team")
                        Spacer()
                        Button {
                            showingAddTeam = true
                        } label: {
                            Text("Add Team")
                                .font(.caption.bold())
                        }
                    }
                }

                // MARK: - Roster Section
                Section {
                    Button {
                        showingAddPlayer = true
                    } label: {
                        Label("Add Player", systemImage: "plus.circle.fill")
                            .foregroundColor(.blue)
                    }
                }

                ForEach(store.players) { player in
                    PlayerRosterRow(player: player) {
                        playerToEdit = player
                    }
                }
                .onDelete(perform: store.deletePlayer)

                if store.players.isEmpty {
                    ContentUnavailableView(
                        "No Players",
                        systemImage: "person.badge.plus",
                        description: Text("Tap Add Player to build your roster.")
                    )
                    .listRowBackground(Color.clear)
                }

                if !store.players.isEmpty {
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
            .navigationTitle("Players")
            .navigationBarTitleDisplayMode(verticalSizeClass == .compact ? .inline : .large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
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
                ToolbarItem(placement: .navigationBarLeading) {
                    EditButton()
                }
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
            }
            .sheet(isPresented: $showingEditTeam) {
                TeamFormView(mode: .edit(store.activeTeamID ?? UUID()))
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
    @Environment(\.dismiss) var dismiss

    let mode: TeamFormMode

    @State private var teamName: String = ""
    @State private var teamColor: Color = .blue
    @State private var showingDeleteConfirmation = false

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
            .onAppear {
                if case .edit(let id) = mode,
                   let team = store.teams.first(where: { $0.id == id }) {
                    teamName = team.name
                    teamColor = team.color
                }
            }
        }
    }

    private func save() {
        let trimmed = teamName.trimmingCharacters(in: .whitespaces)
        switch mode {
        case .add:
            store.addTeam(name: trimmed, color: teamColor)
        case .edit(let id):
            if let idx = store.teams.firstIndex(where: { $0.id == id }) {
                store.teams[idx].name = trimmed
                store.teams[idx].color = teamColor
                store.save()
            }
        }
        dismiss()
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
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(avatarTextColor)
            }
            .frame(width: 38, height: 38)

            // Name + jersey + pills
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(player.displayName)
                        .font(.body)
                        .lineLimit(1)
                    if !player.number.isEmpty {
                        Text("#\(player.number)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color(.systemGray5))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                if pills.isEmpty {
                    Text("No preferences set")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .opacity(0.6)
                } else {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(pills, id: \.0) { label, bg, fg in
                            Text(label)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(fg)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(bg)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .lineLimit(1)
                        }
                    }
                }
            }

            Spacer(minLength: 4)

            // Edit button
            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .foregroundColor(.blue)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
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
