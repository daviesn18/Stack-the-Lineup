import SwiftUI
import MessageUI

// MARK: - MailComposeView
//
// A thin SwiftUI wrapper over MFMailComposeViewController, used by the
// diagnostics export so the report reaches support pre-addressed. Callers must
// gate on `MFMailComposeViewController.canSendMail()` first — a device with no
// Mail account configured returns false, and presenting anyway shows nothing.
// SettingsView falls back to a share sheet in that case.
//
// The report goes in the body AND as a .txt attachment: the body is what most
// support replies quote back, the attachment survives any client that mangles a
// long plain-text body.

struct MailComposeView: UIViewControllerRepresentable {

    let recipient: String
    let subject: String
    let body: String
    let attachmentText: String
    let attachmentFilename: String
    var onFinish: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setToRecipients([recipient])
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: false)
        if let data = attachmentText.data(using: .utf8) {
            vc.addAttachmentData(data, mimeType: "text/plain", fileName: attachmentFilename)
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            onFinish()
        }
    }
}

// The no-Mail-account fallback reuses the existing `ShareSheet` in
// PDFPreviewView.swift — passing the report as .txt Data shares it as a clean
// file the coach can AirDrop, Message, or attach however they like.
