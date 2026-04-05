import SwiftUI
import PDFKit
import StoreKit

// MARK: - LockedPDFPreviewView
// Shows the real Coaches Guide PDF blurred behind a paywall card.
// On successful purchase the sheet auto-dismisses and LineupView
// re-presents the unblurred PDF via its normal generatedPDF sheet.

struct LockedPDFPreviewView: View {
    let document: PDFDocument
    @EnvironmentObject var purchaseManager: PurchaseManager
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                // MARK: Blurred PDF underneath
                PDFKitView(data: document.data)
                    .blur(radius: 1)
                    .overlay(
                        Color.black.opacity(0.15)
                    )
                    .allowsHitTesting(false)

                // MARK: Paywall card on top
                VStack(spacing: 0) {
                    Spacer()

                    VStack(spacing: 20) {
                        // Icon + heading
                        VStack(spacing: 10) {
                            Image(systemName: "lock.doc.fill")
                                .font(.system(size: 48))
                                .foregroundColor(.blue)

                            Text("Unlock the Coaches Guide")
                                .font(.title3.bold())
                                .multilineTextAlignment(.center)

                            Text("Your lineup is ready. Upgrade to Pro to export and share this full inning-by-inning position grid.")
                                .font(.callout)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 8)
                        }

                        // Buy button
                        Button {
                            Task { await purchaseManager.purchase() }
                        } label: {
                            Group {
                                if purchaseManager.isLoading {
                                    ProgressView().tint(.white)
                                } else {
                                    Text("Unlock Pro — \(purchaseManager.proProduct?.displayPrice ?? "$4.99")")
                                        .font(.headline)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(14)
                        }
                        .disabled(purchaseManager.isLoading)

                        // Restore
                        Button {
                            Task { await purchaseManager.restore() }
                        } label: {
                            Text("Restore Purchase")
                                .font(.callout)
                                .foregroundColor(.blue)
                        }
                        .disabled(purchaseManager.isLoading)

                        if let error = purchaseManager.purchaseError {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                        }

                        Text("One-time purchase · No subscription")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(28)
                    .background(.regularMaterial)
                    .cornerRadius(20)
                    .shadow(color: .black.opacity(0.15), radius: 20, y: -4)
                }
                .ignoresSafeArea(edges: .bottom)
            }
            .navigationTitle("Coaches Guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            // Auto-dismiss when purchase completes — LineupView will
            // re-trigger the real PDF sheet via isPro state change
            .onChange(of: purchaseManager.isPro) { _, isPro in
                if isPro { dismiss() }
            }
            .task {
                if purchaseManager.proProduct == nil {
                    await purchaseManager.loadProduct()
                }
            }
        }
    }
}
