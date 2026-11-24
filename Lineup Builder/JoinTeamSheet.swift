//
//  JoinTeamSheet.swift
//  Lineup Builder
//
//  Merge 4: opening an invite link (app.stackthelineup.com/join/<token>).
//
//  Joining needs an account, so a signed-out coach signs in first. Then the
//  sheet shows who invited them to which team and what they'll be able to do,
//  joins, waits for the sync to bring the team down, and opens it.
//

import Auth
import SwiftUI

struct JoinTeamSheet: View {
    let token: String

    @EnvironmentObject var store: LineupStore
    @EnvironmentObject var account: AccountManager
    @Environment(\.dismiss) private var dismiss

    private enum Phase: Equatable {
        case signedOut
        case loading
        case ready(AccountSharing.InvitePreview)
        case joining(AccountSharing.InvitePreview)
        case invalid
        case failed(String)
        /// Joined, but the team hasn't arrived on this device yet (offline).
        case joinedPending(String)
    }
    @State private var phase: Phase = .loading

    var body: some View {
        NavigationStack {
            content
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle("Join a Team")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
        }
        .task(id: account.user?.id) { await load() }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .signedOut:
            VStack(spacing: 16) {
                header(systemImage: "person.2.badge.key", title: "Sign in to join",
                       detail: "A head coach invited you to their team. Sign in, or create a free account, and the team shows up on your phone, iPad and the web.")
                NavigationLink {
                    SignInView()
                } label: {
                    Text("Sign In").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        case .loading:
            ProgressView("Checking the invite…")
        case .ready(let p), .joining(let p):
            VStack(spacing: 16) {
                header(systemImage: "person.2.fill",
                       title: p.isMember ? "You're already on \(p.teamName)" : "\(p.ownerName.isEmpty ? "A head coach" : p.ownerName) invited you to coach \(p.teamName)",
                       detail: p.isMember ? "Open it to pick up where you left off."
                                          : (p.role == .viewer ? TeamSharePermission.readOnly : .readWrite).participantExplanation)
                Button {
                    join(p)
                } label: {
                    Group {
                        if case .joining = phase { ProgressView() } else { Text(p.isMember ? "Open Team" : "Join Team") }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(phase == .joining(p))
            }
        case .invalid:
            header(systemImage: "link.badge.plus", title: "This invite link doesn't work",
                   detail: "It may have been replaced or the team stopped sharing. Ask the head coach to send a new link.")
        case .failed(let message):
            VStack(spacing: 16) {
                header(systemImage: "exclamationmark.triangle", title: "Couldn't open the invite", detail: message)
                Button("Try Again") { Task { await load() } }
            }
        case .joinedPending(let name):
            header(systemImage: "checkmark.circle", title: "You joined \(name)",
                   detail: "It'll appear on this device the next time you're online.")
        }
    }

    private func header(systemImage: String, title: String, detail: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 40))
                .foregroundColor(.accentColor)
            Text(title)
                .font(.title3.bold())
                .multilineTextAlignment(.center)
            Text(detail)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The name this coach goes by on their own teams (set by the coach-name
    /// prompt). Joined teams carry the head coach's name, so they're skipped.
    /// Empty is fine: the server falls back to the account's name.
    private var myCoachName: String {
        store.teams
            .filter { store.access(for: $0.id)?.isOwner ?? true }
            .map { $0.coachName.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
    }

    private func load() async {
        guard account.isSignedIn else {
            phase = .signedOut
            return
        }
        phase = .loading
        do {
            if let p = try await AccountSharing.preview(token: token) {
                phase = .ready(p)
            } else {
                phase = .invalid
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func join(_ p: AccountSharing.InvitePreview) {
        phase = .joining(p)
        Task {
            do {
                guard let teamID = try await AccountSharing.accept(token: token, name: myCoachName) else {
                    phase = .invalid
                    return
                }
                if !p.isMember { Analytics.signal("sharing.account.joined", parameters: ["role": p.role.rawValue]) }
                if await store.openJoinedTeam(teamID) {
                    dismiss()
                } else {
                    phase = .joinedPending(p.teamName)
                }
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }
}
