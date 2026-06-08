import CloudKit
import LinkPresentation
import SwiftUI

// MARK: - CloudKitSharingView
//
// Presents the correct sharing UI depending on share state:
//
//   share.url != nil  ->  UIActivityViewController
//       The share already exists in CloudKit. Present the share URL via the
//       system share sheet (Messages, Mail, Copy Link, AirDrop, etc.).
//       ShareLinkItem wraps the URL as a UIActivityItemSource so we can inject
//       custom LPLinkMetadata — overriding the default "Shared using iCloud
//       Sharing" preview text with a coach-friendly title.
//
//   share.url == nil  ->  UICloudSharingController(share:container:)
//       Fallback for the rare case where the share URL is not yet available.
//       This init shows the management UI only (owner, stop sharing) and is
//       intentionally not used as the primary invite path.
//
// Usage in TeamFormView:
//   1. Tap "Share Team" -- runs Task { cloudKitShareItem = try await createShare() }
//   2. Setting cloudKitShareItem presents this sheet via .sheet(item:)
//   3. share.url should be non-nil immediately after the CKModifyRecordsOperation
//      completes, so UIActivityViewController is shown in the normal path.
//
// Public permission is .readWrite on the share (set in CloudKitManager.createShare),
// so any coach who receives the link can accept it without being pre-added.
//
// Pro gate: applied at the call site, not inside this view.

struct CloudKitSharingView: UIViewControllerRepresentable {

    let share: CKShare
    let container: CKContainer
    let teamName: String

    // MARK: - UIViewControllerRepresentable

    func makeUIViewController(context: Context) -> UIViewController {
        if let shareURL = share.url {
            // Normal path: share is saved, URL is available.
            // ShareLinkItem provides custom LPLinkMetadata so the Messages
            // bubble shows "Join [Team] on Stack the Lineup" instead of
            // "Shared using iCloud Sharing".
            let item = ShareLinkItem(url: shareURL, teamName: teamName)
            let activity = UIActivityViewController(
                activityItems: [item],
                applicationActivities: nil
            )
            return activity
        } else {
            // Fallback: URL not yet available, show management UI.
            let controller = UICloudSharingController(share: share, container: container)
            controller.delegate = context.coordinator
            controller.availablePermissions = [.allowReadOnly, .allowReadWrite]
            return controller
        }
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // No dynamic updates needed.
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(teamName: teamName)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, UICloudSharingControllerDelegate {

        let teamName: String

        init(teamName: String) {
            self.teamName = teamName
        }

        func itemTitle(for csc: UICloudSharingController) -> String? {
            teamName.isEmpty ? "My Team" : teamName
        }

        func itemThumbnailData(for csc: UICloudSharingController) -> Data? { nil }

        func cloudSharingController(
            _ csc: UICloudSharingController,
            failedToSaveShareWithError error: Error
        ) {
            Task { @MainActor in
                Analytics.signal("team.share.failed", parameters: ["error": error.localizedDescription])
            }
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            Task { @MainActor in
                Analytics.signal("team.share.saved")
            }
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            // Owner revoked sharing or participant left.
            // LineupStore picks up the change on the next fetchCloudKitChanges() call.
            Task { @MainActor in
                Analytics.signal("team.share.stopped")
            }
        }
    }
}

// MARK: - ShareLinkItem
//
// UIActivityItemSource wrapper that provides custom LPLinkMetadata for the
// CloudKit share URL. This overrides the default "Shared using iCloud Sharing"
// text that iOS generates for icloud.com/shares/... URLs.
//
// activityViewControllerLinkMetadata is called by UIActivityViewController to
// build the rich preview shown in Messages, Mail, and the share sheet header.

private final class ShareLinkItem: NSObject, UIActivityItemSource {

    private let url: URL
    private let teamName: String

    init(url: URL, teamName: String) {
        self.url      = url
        self.teamName = teamName
    }

    // Placeholder returned synchronously before metadata is ready.
    func activityViewControllerPlaceholderItem(
        _ activityViewController: UIActivityViewController
    ) -> Any {
        url
    }

    // Actual item passed to the selected activity (Messages, Mail, etc.).
    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        url
    }

    // Rich link preview shown in the share sheet header and Messages bubble.
    func activityViewControllerLinkMetadata(
        _ activityViewController: UIActivityViewController
    ) -> LPLinkMetadata? {
        let metadata    = LPLinkMetadata()
        metadata.url    = url
        metadata.title  = teamName.isEmpty
            ? "Join My Team on Stack the Lineup"
            : "Join \(teamName) on Stack the Lineup"
        // Subtitle shown below the title in the Messages link preview.
        metadata.originalURL = url
        return metadata
    }
}


// MARK: - CloudKitManageView
//
// Wraps UICloudSharingController(share:container:) for the owner's "Manage Access"
// flow. This init shows the management UI — participant list, per-participant
// permission picker (read-only vs read-write), and Stop Sharing.
//
// Separate from CloudKitSharingView so the invite path (UIActivityViewController)
// and management path (UICloudSharingController) never conflict.

struct CloudKitManageView: UIViewControllerRepresentable {

    let share: CKShare
    let container: CKContainer

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.delegate = context.coordinator
        controller.availablePermissions = [.allowReadOnly, .allowReadWrite]
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, UICloudSharingControllerDelegate {

        func itemTitle(for csc: UICloudSharingController) -> String? { nil }

        func cloudSharingController(
            _ csc: UICloudSharingController,
            failedToSaveShareWithError error: Error
        ) {
            Task { @MainActor in
                Analytics.signal("team.share.manage.failed", parameters: ["error": error.localizedDescription])
            }
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            Task { @MainActor in
                Analytics.signal("team.share.manage.saved")
            }
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            Task { @MainActor in
                Analytics.signal("team.share.stopped")
            }
        }
    }
}
