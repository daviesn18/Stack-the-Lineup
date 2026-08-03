import SwiftUI

// MARK: - RemoteDeletionPrompt
//
// "Rockhounds was deleted on another device. Delete it here too?"
//
// Deleting a team used to be purely local — the CKRecord survived, so the other
// device kept the team and re-uploaded it, and the two never agreed. Deleting
// the record fixed the first half. This is the second: the device that still
// holds the team has to hear about it.
//
// It asks rather than removing automatically, and that is the whole point. The
// merge code has always refused to auto-remove an owned team on a server-side
// deletion, because a spurious or misread deletion would silently destroy a
// roster. Asking keeps that safety and still lets the two devices agree.
//
// One modifier applied to both roots — the iPhone's ContentView and the iPad's
// dashboard — so the two platforms can't drift. Alerts don't need a
// NavigationStack, which matters on iPad where the detail pane has none.

struct RemoteDeletionPrompt: ViewModifier {
    @ObservedObject var store: LineupStore

    /// Only the first is shown; answering it reveals the next. Deleting several
    /// teams elsewhere is rare, and a queue of stacked alerts is worse than a
    /// short sequence of clear ones.
    private var pending: LineupStore.PendingRemoteDeletion? {
        store.pendingRemoteDeletions.first
    }

    func body(content: Content) -> some View {
        content
            .alert(
                pending.map { "\($0.displayName) was deleted" } ?? "",
                isPresented: Binding(
                    get: { pending != nil },
                    // Nothing to do on dismissal: both buttons resolve the
                    // pending item themselves, and the alert can't be swiped away.
                    set: { _ in }
                ),
                presenting: pending
            ) { item in
                Button("Delete Here Too", role: .destructive) {
                    store.confirmRemoteDeletion(item)
                }
                Button("Keep", role: .cancel) {
                    store.declineRemoteDeletion(item)
                }
            } message: { item in
                Text("\(item.displayName) was deleted on another device. This one still has it — including its roster and game history.")
            }
    }
}

extension View {
    /// Asks before removing a team that was deleted on the coach's other device.
    func remoteDeletionPrompt(store: LineupStore) -> some View {
        modifier(RemoteDeletionPrompt(store: store))
    }
}
