import CloudKit
import SwiftUI

// MARK: - TeamSharingView
//
// The whole sharing surface for a team the coach owns: invite, see who has
// joined, change what each of them can do, and stop sharing.
//
// This replaces UICloudSharingController on the management path. That controller
// was showing a generic document icon, an "(Owner)" row for the coach themselves
// with no name attached, and a "Share Options" screen whose permission choice
// looked like it silently failed. None of that is configurable from outside, so
// the screen is built here against the same CloudKit state instead.
//
// The system share sheet is still used for *sending* an invite — that part was
// never the problem, and coaches expect Messages/Mail/AirDrop there.
//
// Reads and writes both go through CloudKitManager, which hands back a
// TeamShareInfo value snapshot. No CKShare ever reaches this file.

struct TeamSharingView: View {

    let teamID: UUID

    /// Trailing text for the Edit Team row that pushed this screen. Written on
    /// every state change so popping back never shows a stale count.
    @Binding var summary: String?

    @EnvironmentObject private var store: LineupStore

    @State private var info: TeamShareInfo?
    @State private var isLoading    = true
    @State private var busyMessage: String?
    @State private var errorMessage: String?
    @State private var inviteLink: InviteLink?
    @State private var showingStopConfirmation = false

    // MARK: - Coach name
    //
    // Asked for here, at the one moment it starts mattering to someone else.
    // `coachName` is what the assistant's notification reads back ("<name>
    // finalized the lineup"), and its default is UIDevice.current.name — which
    // iOS 16 reduced to the model, so it is "iPhone" on every device. Coaches
    // could always set it in Edit Team; nothing ever asked them to, so nobody
    // did. See backlog 1.11.
    //
    // Deliberately not blocking: skipping still sends the invite. Sharing is
    // the goal the coach came here for, and a name is worth asking for, not
    // worth refusing over.

    @State private var showingCoachNamePrompt = false
    @State private var enteredCoachName = ""
    /// The invite the prompt is standing in front of, run either way once it
    /// is answered.
    @State private var inviteAwaitingName: (() -> Void)?

    /// The access level a *new* share is created with. Only meaningful before
    /// the team is shared; afterwards the link's own permission is authoritative.
    @State private var pendingPermission: TeamSharePermission = .readWrite

    private struct InviteLink: Identifiable {
        let id = UUID()
        let url: URL
        let teamName: String
    }

    private var team: Team? {
        store.teams.first { $0.id == teamID }
    }

    private var teamName: String {
        let name = team?.name ?? ""
        return name.isEmpty ? "this team" : name
    }

    /// Read off the model rather than the fetched state, so the title is right
    /// on the first frame instead of changing once CloudKit answers.
    private var isReceivedTeam: Bool {
        team?.isSharedParticipant ?? false
    }

    // MARK: - Body

    var body: some View {
        Form {
            if let info {
                switch info.state {
                case .notSynced:
                    notSyncedSection
                case .notShared:
                    inviteIntroSection
                    permissionChoiceSection
                    inviteButtonSection
                case .participant:
                    receivedTeamSection(info)
                case .shared:
                    coachesSection(info)
                    linkAccessSection(info)
                    stopSharingSection
                }
            } else if isLoading {
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Checking iCloud…")
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                notSyncedSection
            }
        }
        // Matches the row that pushed this screen. A coach who was invited isn't
        // managing assistants — they are one.
        .navigationTitle(isReceivedTeam ? "Shared With You" : "Assistant Coaches")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(busyMessage != nil)
        .overlay {
            if let busyMessage {
                busyOverlay(busyMessage)
            }
        }
        .alert("What should we call you?", isPresented: $showingCoachNamePrompt) {
            TextField("Your name", text: $enteredCoachName)
                .textInputAutocapitalization(.words)
            Button("Continue") {
                let trimmed = enteredCoachName.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    store.setCoachName(trimmed, teamID: teamID)
                }
                inviteAwaitingName?()
                inviteAwaitingName = nil
            }
            Button("Skip", role: .cancel) {
                inviteAwaitingName?()
                inviteAwaitingName = nil
            }
        } message: {
            Text("Assistant coaches see this when you finalize a lineup. Without it, their notification just says \"iPhone\".")
        }
        .sheet(item: $inviteLink) { link in
            ShareInviteSheet(url: link.url, teamName: link.teamName)
                .ignoresSafeArea()
        }
        .alert(
            "Couldn't Update Sharing",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog(
            "Stop sharing \(teamName)?",
            isPresented: $showingStopConfirmation,
            titleVisibility: .visible
        ) {
            Button("Stop Sharing", role: .destructive) { stopSharing() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every assistant coach loses access right away. Your team, roster, and game history stay on your device.")
        }
        .task { await load() }
    }

    // MARK: - Not Synced

    private var notSyncedSection: some View {
        Section {
            VStack(spacing: 10) {
                Image(systemName: "icloud.slash")
                    .font(.system(size: 34))
                    .foregroundStyle(.secondary)
                Text("This team isn't in iCloud yet")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text("Sharing needs the team synced to iCloud first. Check that you're signed in under Settings, then try again.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)

            Button {
                Task { await load() }
            } label: {
                HStack {
                    Spacer()
                    Text("Check Again")
                    Spacer()
                }
            }
        }
    }

    // MARK: - Received Team
    //
    // A team this coach was invited to. There is nothing to manage — the head
    // coach owns the share — so this answers the two questions a coach actually
    // has here: who sent me this, and what am I allowed to do with it?
    //
    // Leaving the team is deliberately not repeated here. Edit Team's Delete
    // Team already handles a participant's copy, and a second destructive path
    // for the same action is worse than one.

    private func receivedTeamSection(_ info: TeamShareInfo) -> some View {
        Section {
            VStack(spacing: 10) {
                Image(systemName: "person.2.badge.gearshape")
                    .font(.system(size: 34))
                    .foregroundStyle(.tint)
                Text("Shared with you")
                    .font(.headline)
                Text(sharedByLine(info))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)

            HStack {
                Text("Your access")
                Spacer()
                Text(info.myPermission.title)
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Text(info.myPermission.participantExplanation)
        }
    }

    private func sharedByLine(_ info: TeamShareInfo) -> String {
        guard let owner = info.ownerName else {
            return "The head coach shares \(teamName) with you."
        }
        return "\(owner) shares \(teamName) with you."
    }

    // MARK: - Not Shared

    private var inviteIntroSection: some View {
        Section {
            VStack(spacing: 10) {
                Image(systemName: "person.2.badge.plus")
                    .font(.system(size: 34))
                    .foregroundStyle(.tint)
                Text("No assistant coaches yet")
                    .font(.headline)
                Text("Invite a coach to help build positions before the game. You stay in control of the final lineup.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }

    private var permissionChoiceSection: some View {
        Section {
            Picker("Access", selection: $pendingPermission) {
                ForEach(TeamSharePermission.allCases) { permission in
                    Text(permission.title).tag(permission)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        } header: {
            Text("What they can do")
        } footer: {
            Text(pendingPermission.explanation)
        }
    }

    private var inviteButtonSection: some View {
        Section {
            Button {
                askForNameThenInvite { createShareAndInvite() }
            } label: {
                HStack {
                    Spacer()
                    Label("Invite an Assistant Coach", systemImage: "person.badge.plus")
                    Spacer()
                }
            }
        } footer: {
            Text("You'll pick how to send the invite — Messages, Mail, or anything else on your share sheet.")
        }
    }

    // MARK: - Shared

    private func coachesSection(_ info: TeamShareInfo) -> some View {
        Section {
            if info.participants.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No one has joined yet")
                        .font(.subheadline.weight(.medium))
                    Text("Send the invite link to an assistant coach.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            } else {
                // A direct destination rather than NavigationLink(value:) plus
                // navigationDestination(for:). The value-based pair does not
                // register from inside this screen — TeamFormView owns the
                // NavigationStack and is itself presented as a sheet — so the
                // rows rendered but tapping them did nothing.
                ForEach(info.participants) { participant in
                    NavigationLink {
                        participantDetail(participant)
                    } label: {
                        ParticipantRow(participant: participant)
                    }
                }
            }

            Button {
                askForNameThenInvite { shareExistingLink(info) }
            } label: {
                Label(
                    info.participants.isEmpty ? "Send Invite Link" : "Invite Another Coach",
                    systemImage: "person.badge.plus"
                )
            }
        } header: {
            Text("Coaches")
        }
    }

    private func participantDetail(_ participant: ShareParticipantInfo) -> some View {
        ParticipantDetailView(
            participant: participant,
            teamName: teamName,
            onRemove: {
                await mutate("Removing…") { recordName in
                    try await CloudKitManager.shared.removeParticipant(
                        participant.id,
                        teamRecordName: recordName
                    )
                }
            }
        )
    }

    private func linkAccessSection(_ info: TeamShareInfo) -> some View {
        Section {
            Picker(
                "Anyone with the link",
                selection: Binding(
                    get: { info.linkPermission },
                    set: { setLinkPermission($0) }
                )
            ) {
                ForEach(TeamSharePermission.allCases) { permission in
                    Text(permission.title).tag(permission)
                }
            }
        } header: {
            Text("Invite Link")
        } footer: {
            // This footer used to promise that changing the link left existing
            // coaches alone. Device testing on 9 Aug disproved it: a coach who
            // joins by tapping a link is a *public* participant, and CloudKit
            // governs public participants by the share's publicPermission —
            // there is no separate per-participant value for them to keep. See
            // backlog 1.10.
            Text("This is what every coach on the team can do. Coaches join by tapping your link, and iCloud gives them all the same access — so changing this changes it for everyone, including coaches who already joined.")
        }
    }

    private var stopSharingSection: some View {
        Section {
            Button(role: .destructive) {
                showingStopConfirmation = true
            } label: {
                HStack {
                    Spacer()
                    Label("Stop Sharing", systemImage: "person.2.slash")
                    Spacer()
                }
            }
        } footer: {
            Text("Everyone loses access. Your team and its history stay on your device.")
        }
    }

    // MARK: - Busy Overlay

    private func busyOverlay(_ message: String) -> some View {
        ZStack {
            Color.black.opacity(0.12).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    // MARK: - Actions

    /// The single place share state lands, so the parent row's subtitle can
    /// never drift from what this screen is showing.
    private func apply(_ newInfo: TeamShareInfo) {
        info    = newInfo
        summary = newInfo.summary
        if case .shared = newInfo.state {
            pendingPermission = newInfo.linkPermission
        }
    }

    /// Reads the current state from CloudKit. Never creates a share — the old
    /// code opened the manage screen by calling createShare(), so looking at a
    /// team could change it.
    private func load() async {
        guard let team else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let fetched = try await CloudKitManager.shared.shareInfo(for: team)

            // A record name pointing at a record the server doesn't have is the
            // exact state behind the old "Record not found" alert. Clear it so
            // the next save re-uploads the team instead of dead-ending here.
            //
            // Never for a received team: its record name points into the owner's
            // zone, is how the shared-database merge matches the local copy, and
            // is not this device's to invalidate.
            //
            // Judge "received" by the durable ledger, not `isSharedParticipant`:
            // that flag is false in the window before the first shared fetch of a
            // session, and trusting it here is what let a participant's record
            // name — its only link back to the owner's zone — get cleared.
            if case .notSynced(let stale) = fetched.state, stale,
               !team.isSharedParticipant, !store.isReceivedShare(team) {
                store.clearStaleRecordName(teamID: teamID)
            }
            apply(fetched)
        } catch {
            errorMessage = CloudKitManager.friendlyMessage(for: error)
            apply(TeamShareInfo(state: .notSynced(staleRecordName: false)))
        }
    }

    /// True when `coachName` carries no information about who the coach is.
    /// The rule itself lives on `LineupStore` — the join path asks the same
    /// question when an invite is accepted, and two copies of "is this a real
    /// name?" would drift.
    private var needsCoachName: Bool {
        LineupStore.isPlaceholderCoachName(
            team?.coachName ?? "",
            deviceName: UIDevice.current.name
        )
    }

    /// Runs `invite`, asking for the coach's name first when there isn't one.
    private func askForNameThenInvite(_ invite: @escaping () -> Void) {
        guard needsCoachName else {
            invite()
            return
        }
        enteredCoachName = ""
        inviteAwaitingName = invite
        showingCoachNamePrompt = true
    }

    /// First-time share: make sure the team is in iCloud, create the share at the
    /// chosen permission, then hand the link to the share sheet.
    private func createShareAndInvite() {
        guard var team else { return }
        let permission = pendingPermission

        Task {
            busyMessage = "Preparing invite…"
            defer { busyMessage = nil }

            do {
                if team.ckRecordName == nil {
                    try await CloudKitManager.shared.ensureZoneExists()
                    let recordName = try await CloudKitManager.shared.saveTeam(team)
                    team.ckRecordName = recordName
                    store.setRecordName(recordName, teamID: teamID)
                }

                let fetched = try await CloudKitManager.shared.createShare(for: team, permission: permission)
                apply(fetched)

                if let url = fetched.url {
                    inviteLink = InviteLink(url: url, teamName: team.name)
                } else {
                    errorMessage = "iCloud created the share but hasn't returned a link yet. Try again in a moment."
                }
            } catch {
                errorMessage = CloudKitManager.friendlyMessage(for: error)
            }
        }
    }

    /// Re-presents the existing link. Does not touch the share.
    private func shareExistingLink(_ info: TeamShareInfo) {
        guard let url = info.url else {
            errorMessage = "iCloud hasn't returned a link for this team yet. Try again in a moment."
            return
        }
        inviteLink = InviteLink(url: url, teamName: team?.name ?? "")
    }

    private func setLinkPermission(_ permission: TeamSharePermission) {
        Task {
            await mutate("Updating…") { recordName in
                try await CloudKitManager.shared.setLinkPermission(permission, teamRecordName: recordName)
            }
        }
    }

    private func stopSharing() {
        guard let recordName = team?.ckRecordName else { return }
        Task {
            busyMessage = "Stopping…"
            defer { busyMessage = nil }
            do {
                try await CloudKitManager.shared.stopSharing(teamRecordName: recordName)
                apply(TeamShareInfo(state: .notShared))
                pendingPermission = .readWrite
            } catch {
                errorMessage = CloudKitManager.friendlyMessage(for: error)
            }
        }
    }

    /// Runs a write that returns fresh state, with the busy overlay up and a
    /// coach-readable message on failure.
    private func mutate(
        _ message: String,
        _ operation: @escaping (String) async throws -> TeamShareInfo
    ) async {
        guard let recordName = team?.ckRecordName else {
            errorMessage = CloudKitManager.CloudKitError.notSynced.errorDescription
            return
        }
        busyMessage = message
        defer { busyMessage = nil }
        do {
            apply(try await operation(recordName))
        } catch {
            errorMessage = CloudKitManager.friendlyMessage(for: error)
            // The share moved under us — resync rather than leaving stale rows.
            await load()
        }
    }
}

// MARK: - ParticipantRow

private struct ParticipantRow: View {

    let participant: ShareParticipantInfo

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: participant.hasAccepted ? "person.crop.circle.fill" : "person.crop.circle.badge.clock")
                .font(.title2)
                .foregroundStyle(participant.hasAccepted ? Color.accentColor : Color.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(participant.displayName)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private var subtitle: String {
        guard participant.hasAccepted else { return "Invited — hasn't joined yet" }
        if let contact = participant.contact { return "\(participant.permission.title) · \(contact)" }
        return participant.permission.title
    }
}

// MARK: - ParticipantDetailView

private struct ParticipantDetailView: View {

    let participant: ShareParticipantInfo
    let teamName: String
    let onRemove: () async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var showingRemoveConfirmation = false

    init(
        participant: ShareParticipantInfo,
        teamName: String,
        onRemove: @escaping () async -> Void
    ) {
        self.participant = participant
        self.teamName    = teamName
        self.onRemove    = onRemove
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 8) {
                    Image(systemName: participant.hasAccepted ? "person.crop.circle.fill" : "person.crop.circle.badge.clock")
                        .font(.system(size: 44))
                        .foregroundStyle(participant.hasAccepted ? Color.accentColor : Color.secondary)
                    Text(participant.displayName)
                        .font(.headline)
                    if let contact = participant.contact {
                        Text(contact)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if !participant.hasAccepted {
                        Text("Hasn't accepted the invite yet")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            // Read-only, deliberately. This was an editable picker until 9 Aug,
            // when device testing showed CloudKit ignoring it: a coach who joins
            // from an invite link is a public participant, whose access is the
            // share's publicPermission and not a value of their own. Offering a
            // control here made the app claim a guarantee it could not keep —
            // and worse, changing the link silently re-permissioned coaches who
            // had deliberately been set to View only. Backlog 1.10; the way to
            // make this editable for real is per-coach invites by Apple ID.
            Section {
                LabeledContent("Access", value: participant.permission.title)
            } header: {
                Text("What they can do")
            } footer: {
                Text("\(participant.permission.explanation)\n\nEveryone who joins from your invite link gets the same access. To change it, use Invite Link on the previous screen.")
            }

            Section {
                Button(role: .destructive) {
                    showingRemoveConfirmation = true
                } label: {
                    HStack {
                        Spacer()
                        Text("Remove Coach")
                        Spacer()
                    }
                }
            } footer: {
                Text("They lose access to \(teamName) right away.")
            }
        }
        .navigationTitle(participant.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Remove \(participant.displayName)?",
            isPresented: $showingRemoveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove Coach", role: .destructive) {
                Task {
                    await onRemove()
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They'll lose access to \(teamName). You can invite them again later.")
        }
    }
}
