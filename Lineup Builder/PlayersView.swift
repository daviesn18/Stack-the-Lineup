import SwiftUI

// MARK: - Players List

struct PlayersView: View {
    @EnvironmentObject var store: LineupStore
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
                    HStack {
                        if !player.number.isEmpty {
                            Text("#\(player.number)")
                                .font(.headline)
                                .foregroundColor(.secondary)
                                .frame(width: 44, alignment: .leading)
                        } else {
                            Text("—")
                                .font(.headline)
                                .foregroundColor(.gray)
                                .frame(width: 44, alignment: .leading)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(player.displayName)
                                .font(.body)
                        }
                        Spacer()
                        Button {
                            playerToEdit = player
                        } label: {
                            Image(systemName: "pencil")
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
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
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        Button {
                            showingSettings = true
                        } label: {
                            Image(systemName: "gearshape.fill")
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
    @Environment(\.dismiss) var dismiss

    let mode: PlayerFormMode

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var number = ""
    @State private var showingValidationError = false
    @State private var validationMessage = ""

    var title: String {
        switch mode {
        case .add: return "Add Player"
        case .edit: return "Edit Player"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Player Info") {
                    TextField("First Name", text: $firstName)
                        .textContentType(.givenName)
                        .autocorrectionDisabled()

                    TextField("Last Name", text: $lastName)
                        .textContentType(.familyName)
                        .autocorrectionDisabled()

                    TextField("Jersey Number (Optional)", text: $number)
                        .keyboardType(.numberPad)
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
            .onAppear {
                if case .edit(let player) = mode {
                    firstName = player.firstName
                    lastName = player.lastName
                    number = player.number
                }
            }
        }
    }

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

        switch mode {
        case .add:
            let player = Player(firstName: trimmedFirst, lastName: trimmedLast, number: trimmedNumber)
            store.addPlayer(player)
        case .edit(let existing):
            var updated = existing
            updated.firstName = trimmedFirst
            updated.lastName = trimmedLast
            updated.number = trimmedNumber
            store.updatePlayer(updated)
        }
        dismiss()
    }
}
