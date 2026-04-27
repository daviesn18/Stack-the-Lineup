import SwiftUI
import PDFKit
import StoreKit

struct PDFPreviewView: View {
    let document: PDFDocument
    @Environment(\.dismiss) var dismiss
    @Environment(\.requestReview) var requestReview
    @State private var showingShareSheet = false

    var body: some View {
        NavigationStack {
            PDFKitView(data: document.data)
                .navigationTitle(document.filename)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            showingShareSheet = true
                            maybeRequestReview()
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
                .sheet(isPresented: $showingShareSheet) {
                    ShareSheet(items: [document.data], filename: document.filename)
                }
        }
    }

    // MARK: - Review Request

    private func maybeRequestReview() {
        guard !UserDefaults.standard.bool(forKey: "hasRequestedReview") else { return }
        let count = UserDefaults.standard.integer(forKey: "pdfExportCount") + 1
        UserDefaults.standard.set(count, forKey: "pdfExportCount")
        if count >= 3 {
            requestReview()
            UserDefaults.standard.set(true, forKey: "hasRequestedReview")
        }
    }
}

// MARK: - PDFKit UIViewRepresentable

struct PDFKitView: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFKit.PDFView {
        let pdfView = PDFKit.PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        if let doc = PDFKit.PDFDocument(data: data) {
            pdfView.document = doc
        }
        return pdfView
    }

    func updateUIView(_ uiView: PDFKit.PDFView, context: Context) {}
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    let filename: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        // Write to temp file for cleaner sharing
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        if let data = items.first as? Data {
            try? data.write(to: tempURL)
            return UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
        }
        return UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
