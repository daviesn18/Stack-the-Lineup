import SwiftUI

// MARK: - Lineup PDF Exports
//
// One place for the three things a PDF export needs to agree on across idioms:
// who is entitled to the Coaches Guide, how each document is built, and what
// happens afterwards — preview, or paywall with a promotion once purchased.
//
// It lives here rather than inside either view because iPhone and iPad both
// need all three, and this codebase has already paid for the alternative:
// finding 2.4 of the August audit is `playerChip` copied into
// `iPadDashboardView` and drifting by hand until the two no longer matched.
// A drifting paywall rule is worse than a drifting point of spacing.

/// Which export the coach asked for. Set the binding and the modifier attached
/// by `lineupPDFExports(request:)` does the rest.
enum LineupPDFRequest: Identifiable, Hashable {
    case battingOrder
    case coachesGuide

    var id: Self { self }
}

enum LineupPDFExport {

    /// Whether the Coaches Guide is unlocked for this coach on this team.
    ///
    /// Pro buys it, and so does being a **view-only** assistant on a team
    /// somebody else shared. The case that matters: a head coach running late
    /// asks an assistant to print the guide for the dugout. Charging that
    /// assistant for a read-only copy of a lineup they cannot even edit would
    /// block a job the head coach has already paid for.
    ///
    /// Read-write assistants are deliberately not included. They are co-coaches
    /// and pay like a head coach — Pro is per-account, so they get the same free
    /// tier as any unpaid coach.
    ///
    /// Both flags are checked rather than `isReadOnly` alone. That flag is only
    /// ever set on a received team today, but requiring `isSharedParticipant`
    /// too means this can never become a way to unlock a Pro export on a team
    /// you own if the flag is repurposed later.
    static func canExportCoachesGuide(team: Team, isPro: Bool) -> Bool {
        isPro || (team.isSharedParticipant && team.isReadOnly)
    }

    /// Builds the document. The two types take different argument lists — the
    /// guide also needs game logs and the pitching config — so they are built
    /// here rather than at each call site, where a new field could be added to
    /// one and missed on the other.
    @MainActor
    static func document(for request: LineupPDFRequest, store: LineupStore) -> PDFDocument {
        switch request {
        case .battingOrder:
            return PDFGenerator.generate(
                type: .battingOrder,
                lineup: store.lineup,
                players: store.players,
                teamName: store.teamName,
                teamColor: store.teamColor
            )
        case .coachesGuide:
            return PDFGenerator.generate(
                type: .coachesGuide,
                lineup: store.lineup,
                players: store.players,
                teamName: store.teamName,
                teamColor: store.teamColor,
                gameLogs: store.gameLogs,
                pitchingConfig: store.pitchingConfig
            )
        }
    }
}

// MARK: - View Modifier

extension View {

    /// Attaches the whole export presentation: the preview sheet, the paywall
    /// cover for a locked Coaches Guide, and the promotion that swaps the
    /// locked document for the real one the moment Pro is purchased.
    ///
    /// Callers own only a `LineupPDFRequest?` and set it. Nothing else about
    /// exporting is duplicated between the iPhone and iPad layouts.
    func lineupPDFExports(request: Binding<LineupPDFRequest?>) -> some View {
        modifier(LineupPDFExportModifier(request: request))
    }
}

private struct LineupPDFExportModifier: ViewModifier {

    @Binding var request: LineupPDFRequest?

    @EnvironmentObject private var store: LineupStore
    @EnvironmentObject private var purchaseManager: PurchaseManager

    @State private var generatedPDF: PDFDocument?
    @State private var lockedPDF: PDFDocument?

    func body(content: Content) -> some View {
        content
            .onChange(of: request) { _, newValue in
                guard let newValue else { return }
                fulfil(newValue)
                // Cleared so asking for the same export twice in a row works.
                request = nil
            }
            .sheet(item: $generatedPDF) { pdf in
                PDFPreviewView(document: pdf)
            }
            .fullScreenCover(item: $lockedPDF) { pdf in
                ProGate(source: "pdf_export", navTitle: "Coaches Guide") {
                    PDFKitView(data: pdf.data)
                }
                .environmentObject(purchaseManager)
            }
            .onChange(of: purchaseManager.isPro) { _, isPro in
                if isPro, let pdf = lockedPDF {
                    lockedPDF = nil
                    generatedPDF = pdf
                }
            }
    }

    private func fulfil(_ request: LineupPDFRequest) {
        let doc = LineupPDFExport.document(for: request, store: store)

        switch request {
        case .battingOrder:
            // Always free.
            generatedPDF = doc
            Analytics.signal("pdf.exported", parameters: ["type": "battingOrder"])

        case .coachesGuide:
            let entitled = LineupPDFExport.canExportCoachesGuide(
                team: store.activeTeam,
                isPro: purchaseManager.isPro
            )
            if entitled {
                generatedPDF = doc
                Analytics.signal("pdf.exported", parameters: [
                    "type": "coachesGuide",
                    // Separates a Pro export from an assistant's free one, so the
                    // unlock's real usage is visible rather than inferred.
                    "entitlement": purchaseManager.isPro ? "pro" : "readonly_participant"
                ])
            } else if purchaseManager.showsLockedUI {
                lockedPDF = doc
            }
            // Still resolving: drop the request rather than show the gate to a
            // coach who may already have paid. Tapping Export again once the
            // entitlement lands produces the real document.
        }
    }
}
