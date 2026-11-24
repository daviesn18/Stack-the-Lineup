//
//  AccountSharingView.swift
//  Lineup Builder
//
//  Merge 4: assistant coaches on an account team.
//
//  The head coach makes one invite link, picks what every coach can do (one
//  role for all, as with CloudKit sharing), sees who joined, removes a coach,
//  or stops sharing. A coach who joined sees who shared it and what they can
//  do, and can leave. CloudKit teams keep TeamSharingView.
//
//  The server decides all of this (20261124000000_shared_teams); after each
//  change the account sync runs so the coaches list is the server's.
//

import SwiftUI

struct AccountSharingView: View {
    let teamID: UUID

    @EnvironmentObject var store: LineupStore
    @EnvironmentObject var purchaseManager: PurchaseManager
    @Environment(\.dismiss) private var dismiss

    @State private var link: AccountSharing.LiveLink?
    @State private var loadedLink = false
    @State private var busy: String?
    @State private var error: String?
    @State private var showingPaywall = false
    @State private var removing: TeamCoach?
    @State private var confirmingStop = false
    @State private var confirmingLeave = false

    private var access: TeamAccess? { store.access(for: teamID) }
    private var teamName: String { store.teams.first(where: { $0.id == teamID })?.name ?? "this team" }

    var body: some View {
        List {
            if let access {
                if access.isOwner { ownerSections(access) } else { coachSections(access) }
            } else {
                Section {
                    Text("Sharing appears once this team has synced with your account.")
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle(access?.isOwner == false ? "Shared with You" : "Assistant Coaches")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if let busy { busyOverlay(busy) } }
        .task { await loadLink() }
        .refreshable { await refresh() }
        .alert("Couldn't Update Sharing", isPresented: .constant(error != nil)) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "")
        }
        .fullScreenCover(isPresented: $showingPaywall) {
            ProGate(source: "shared_teams", navTitle: "Shared Teams")
                .environmentObject(purchaseManager)
        }
    }

    // MARK: - Head coach

    @ViewBuilder
    private func ownerSections(_ access: TeamAccess) -> some View {
        Section {
            if let link {
                ShareLink(item: link.url,
                          subject: Text("Coach \(teamName) with me"),
                          message: Text("Join \(teamName) on Stack the Lineup: ")) {
                    Label("Send Invite Link", systemImage: "square.and.arrow.up")
                }
                Picker("What coaches can do", selection: Binding(
                    get: { link.role },
                    set: { newRole in run("Updating…") { try await AccountSharing.setRole(team: teamID, role: newRole) } }
                )) {
                    Text(TeamSharePermission.readWrite.title).tag(TeamRole.editor)
                    Text(TeamSharePermission.readOnly.title).tag(TeamRole.viewer)
                }
            } else if loadedLink {
                Button {
                    createLink()
                } label: {
                    Label("Create Invite Link", systemImage: "link.badge.plus")
                }
            } else {
                HStack { ProgressView(); Text("Checking…").foregroundColor(.secondary) }
            }
        } header: {
            Text("Invite Link")
        } footer: {
            if let link {
                Text("\(permission(link.role).explanation)\n\nEveryone who joins from this link gets the same access, and changing it changes it for every coach. They sign in to join.")
            } else {
                Text("Make a link and send it to your assistant coaches. They sign in to join, and the team shows up on their phone, iPad and the web.")
            }
        }

        Section {
            if access.coaches.isEmpty {
                Text("No one has joined yet")
                    .foregroundColor(.secondary)
            } else {
                ForEach(access.coaches) { coach in
                    coachRow(coach)
                        .swipeActions {
                            Button("Remove", role: .destructive) { removing = coach }
                        }
                        .contextMenu {
                            Button("Remove Coach", role: .destructive) { removing = coach }
                        }
                }
            }
        } header: {
            Text("Coaches")
        } footer: {
            if !access.coaches.isEmpty {
                Text("Swipe a coach to remove them. They lose access right away; you can invite them again later.")
            }
        }
        .confirmationDialog("Remove \(removing?.displayName ?? "Coach")?",
                            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible) {
            Button("Remove Coach", role: .destructive) {
                if let coach = removing {
                    run("Removing…") { try await AccountSharing.remove(coach: coach.userID, team: teamID) }
                }
                removing = nil
            }
            Button("Cancel", role: .cancel) { removing = nil }
        } message: {
            Text("They'll lose access to \(teamName).")
        }

        if link != nil || access.isShared {
            Section {
                Button("Stop Sharing", role: .destructive) { confirmingStop = true }
            } footer: {
                Text("Every coach loses access and the link stops working. Your team and its history stay with you.")
            }
            .confirmationDialog("Stop Sharing \(teamName)?", isPresented: $confirmingStop, titleVisibility: .visible) {
                Button("Stop Sharing", role: .destructive) {
                    run("Stopping…") {
                        try await AccountSharing.stopSharing(team: teamID)
                        link = nil
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    // MARK: - A coach who joined

    @ViewBuilder
    private func coachSections(_ access: TeamAccess) -> some View {
        Section {
            LabeledContent("Shared by", value: access.ownerDisplayName)
            LabeledContent("Your access", value: permission(access.role).title)
        } footer: {
            Text(permission(access.role).participantExplanation)
        }

        Section("Coaches") {
            LabeledContent(access.ownerDisplayName, value: "Head coach")
            ForEach(access.coaches) { coach in coachRow(coach) }
        }

        Section {
            Button("Leave Team", role: .destructive) { confirmingLeave = true }
        } footer: {
            Text("You'll lose access on every device. The head coach can invite you again.")
        }
        .confirmationDialog("Leave \(teamName)?", isPresented: $confirmingLeave, titleVisibility: .visible) {
            Button("Leave Team", role: .destructive) {
                // Queued like a delete: the sync calls leave_team, and the
                // head coach's team is untouched.
                store.deleteTeam(id: teamID)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Pieces

    private func coachRow(_ coach: TeamCoach) -> some View {
        HStack {
            Text(coach.displayName)
            Spacer()
            Text(permission(coach.role).title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func permission(_ role: TeamRole) -> TeamSharePermission {
        role == .viewer ? .readOnly : .readWrite
    }

    private func busyOverlay(_ message: String) -> some View {
        ZStack {
            Color.black.opacity(0.15).ignoresSafeArea()
            VStack(spacing: 10) {
                ProgressView()
                Text(message).font(.subheadline)
            }
            .padding(20)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    // MARK: - Actions

    private func loadLink() async {
        guard access?.isOwner == true else { return }
        link = try? await AccountSharing.liveLink(team: teamID)
        loadedLink = true
    }

    private func refresh() async {
        await store.syncAccountAndWait()
        await loadLink()
    }

    private func createLink() {
        guard purchaseManager.isPro else {
            showingPaywall = true
            return
        }
        run("Creating link…") {
            link = try await AccountSharing.createInvite(team: teamID, role: .editor)
            Analytics.signal("sharing.account.linkCreated")
        }
    }

    /// Runs a sharing change, then syncs so the coaches list is the server's.
    private func run(_ message: String, _ body: @escaping () async throws -> Void) {
        busy = message
        Task {
            do {
                try await body()
                await store.syncAccountAndWait()
                await loadLink()
            } catch let e as AccountSharing.Failure where e == .proRequired {
                showingPaywall = true
            } catch {
                self.error = error.localizedDescription
            }
            busy = nil
        }
    }
}
