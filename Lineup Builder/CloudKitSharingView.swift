import CloudKit
import LinkPresentation
import SwiftUI

// MARK: - ShareInviteSheet
//
// The system share sheet, used for one job: sending a CloudKit share URL to an
// assistant coach via Messages, Mail, AirDrop, or Copy Link.
//
// This is the only piece of the old sharing UI that survived the 3.3 rework.
// Management — who has joined, what each of them can do, revoking access — is
// now TeamSharingView, built natively. UICloudSharingController used to own that
// path and could not be made presentable: it showed a generic document icon, an
// unnamed "(Owner)" row, and a permission picker whose result the app then
// overwrote on the next read.
//
// ShareLinkItem supplies custom LPLinkMetadata so the Messages bubble reads
// "Join [Team] on Stack the Lineup" rather than "Shared using iCloud Sharing".
//
// Pro gate: applied at the call site, not here.

struct ShareInviteSheet: UIViewControllerRepresentable {

    let url: URL
    let teamName: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: [ShareLinkItem(url: url, teamName: teamName)],
            applicationActivities: nil
        )
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No dynamic updates needed.
    }
}

// MARK: - ShareLinkItem
//
// UIActivityItemSource wrapper providing custom LPLinkMetadata for the CloudKit
// share URL, overriding the default preview iOS generates for
// icloud.com/shares/... links.

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
        let metadata = LPLinkMetadata()
        metadata.url = url
        metadata.title = teamName.isEmpty
            ? "Join My Team on Stack the Lineup"
            : "Join \(teamName) on Stack the Lineup"
        metadata.originalURL = url
        return metadata
    }
}
