import UIKit
import SwiftUI
import QuickLook

// MARK: - PreviewViewController
//
// Quick Look preview provider for `.stlteam` files. Registered as the extension's
// principal class in Info.plist (NSExtensionPrincipalClass). Quick Look hands us a
// file URL; we read it, summarize it, and host a SwiftUI card.
//
// UIViewController is already @MainActor, so `preparePreviewOfFile` runs on the
// main actor — no extra hopping needed. The file is tiny (a few tens of KB), so a
// synchronous read here is fine for a preview.

final class PreviewViewController: UIViewController, QLPreviewingController {

    func preparePreviewOfFile(at url: URL) async throws {
        let data = try Data(contentsOf: url)
        let summary = TeamPreviewSummary.parse(data)

        let host = UIHostingController(rootView: TeamPreviewCard(summary: summary))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }
}
