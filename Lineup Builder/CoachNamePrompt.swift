import SwiftUI

// MARK: - CoachNamePrompt
//
// "What should we call you?" — asked of an assistant coach the moment they join
// a team, because that is the moment their name starts meaning something to
// someone else.
//
// A received team's `coachName` is seeded from `UIDevice.current.name` in
// `mergeCloudKitChanges`, and since iOS 16 that returns the model rather than
// the name the coach gave their phone. So without this every assistant is
// "iPhone" to the head coach: in the push body the Worker sends, and in
// "Finalized by" on the head coach's own screen.
//
// The owning side of this already exists — `TeamSharingView` asks before it
// hands out an invite. This is the receiving side of the same question, and
// both go through `LineupStore.isPlaceholderCoachName` so they can't disagree
// about what counts as a real name. See backlog 1.11.
//
// Applied once, to the root in `ContentView`, which is above both the iPhone
// tab bar and the iPad dashboard. Unlike `RemoteDeletionPrompt` it isn't
// repeated on the iPad detail pane: that modifier is applied to both roots and
// on iPad ends up mounted twice against one piece of store state.
//
// Skipping is allowed, and the team is joined either way. Joining is what the
// coach came to do; a name is worth asking for, not worth blocking on. The
// consequence of skipping is being asked again on the next invite — Edit Team
// is the durable place to set it.

struct CoachNamePrompt: ViewModifier {
    @ObservedObject var store: LineupStore

    @State private var enteredName = ""

    func body(content: Content) -> some View {
        content
            .alert(
                "What should we call you?",
                isPresented: Binding(
                    get: { store.pendingCoachNameRequest != nil },
                    // Both buttons clear the request themselves. This only covers
                    // a dismissal that arrives from somewhere else, and clearing
                    // it is the right answer there too — a prompt that can't be
                    // put down is worse than one that doesn't get answered.
                    set: { if !$0 { store.pendingCoachNameRequest = nil } }
                ),
                // Carries the team through, so the copy doesn't fall back to
                // placeholder wording for the length of the dismiss animation.
                presenting: store.pendingCoachNameRequest
            ) { request in
                TextField("Your name", text: $enteredName)
                    .textInputAutocapitalization(.words)
                Button("Save") { save(request) }
                Button("Not Now", role: .cancel) { dismiss() }
            } message: { request in
                Text("The head coach of \(request.displayName) sees this when you finalize a lineup or archive a game. Without it, it just says \"iPhone\".")
            }
    }

    private func save(_ request: LineupStore.CoachNameRequest) {
        let trimmed = enteredName.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            store.setCoachName(trimmed, teamID: request.teamID)
            Analytics.signal("team.share.coach_name_set", parameters: ["source": "join"])
        }
        dismiss()
    }

    private func dismiss() {
        store.pendingCoachNameRequest = nil
        enteredName = ""
    }
}

extension View {
    /// Asks a coach for their name when they join a team that doesn't know it.
    func coachNamePrompt(store: LineupStore) -> some View {
        modifier(CoachNamePrompt(store: store))
    }
}
