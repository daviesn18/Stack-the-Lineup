import SwiftUI

// MARK: - ShareRevocationNotice
//
// "Rockhounds is no longer shared with you."
//
// The other half of the deletion story. `RemoteDeletionPrompt` covers a team the
// coach owns being deleted on their own other device, and asks before removing
// it. This covers a team someone else owned being taken away — deleted, or
// unshared, or this coach removed from it — and only reports.
//
// It asks nothing because there is nothing to ask. A participant's copy has no
// independent existence: the record is gone from the owner's zone, so the team
// cannot sync, cannot be edited, and will never receive another lineup. Offering
// "Keep" would be offering a team that does nothing.
//
// But it does not remove it silently either. An assistant who opens the app
// before a game and finds the team simply gone has no way to tell that from the
// app losing it, which is the more alarming reading and the wrong one.
//
// The removal has already happened in `mergeCloudKitChanges` by the time this
// presents — this explains it, it doesn't perform it.

struct ShareRevocationNotice: ViewModifier {
    @ObservedObject var store: LineupStore

    /// One at a time, like the deletion prompt. Losing access to two teams at
    /// once means the head coach left the app entirely, which is rare enough
    /// that a short sequence beats a stack of alerts.
    private var pending: LineupStore.RevokedShare? {
        store.pendingShareRevocations.first
    }

    func body(content: Content) -> some View {
        content
            .alert(
                pending.map { "\($0.displayName) is no longer shared with you" } ?? "",
                isPresented: Binding(
                    get: { pending != nil },
                    set: { _ in }
                ),
                presenting: pending
            ) { item in
                Button("OK") { store.acknowledgeShareRevocation(item) }
            } message: { item in
                Text("The head coach deleted \(item.displayName) or stopped sharing it, so it has been removed from this device. Anything you kept on your own teams is untouched.")
            }
    }
}

extension View {
    /// Explains a shared team disappearing, after it already has.
    func shareRevocationNotice(store: LineupStore) -> some View {
        modifier(ShareRevocationNotice(store: store))
    }
}
