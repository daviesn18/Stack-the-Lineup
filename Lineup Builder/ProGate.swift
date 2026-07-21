import SwiftUI

// MARK: - ProGate
// The single presentation for every Pro-gated feature. A lightly blurred,
// non-interactive backdrop fills the screen, and the contextual PaywallView
// rises over it as a sheet. The chrome is identical everywhere (that's the
// consistency); the backdrop is the real feature where one is cheap to show
// (Coaches Guide PDF, Game History), or a neutral branded surface otherwise.
//
// Present with .fullScreenCover so the backdrop fills the screen edge to edge.
// The blur is deliberately light — enough to read as "locked" while still
// showing the coach the value they'd unlock.

struct ProGate: View {
    @EnvironmentObject var purchaseManager: PurchaseManager
    @Environment(\.dismiss) private var dismiss

    let source: String
    let navTitle: String
    private let backdrop: AnyView

    /// Detent that leaves the top of the backdrop visible.
    private static let peekDetent: PresentationDetent = .fraction(0.6)

    @State private var showingPaywall = true
    @State private var detent: PresentationDetent

    /// A feature with a real preview to show (e.g. the generated PDF). Opens at
    /// the peek so the preview is visible above the paywall.
    init(source: String, navTitle: String, @ViewBuilder preview: () -> some View) {
        self.source = source
        self.navTitle = navTitle
        self.backdrop = AnyView(preview())
        self._detent = State(initialValue: Self.peekDetent)
    }

    /// A feature with no cheap live preview — a neutral branded backdrop keeps
    /// the chrome consistent, and the paywall opens full so no empty gradient
    /// shows. Dragging down still reveals the backdrop.
    init(source: String, navTitle: String) {
        self.source = source
        self.navTitle = navTitle
        self.backdrop = AnyView(ProGateNeutralBackdrop(source: source))
        self._detent = State(initialValue: .large)
    }

    var body: some View {
        NavigationStack {
            backdrop
                .blur(radius: 0.5)
                .allowsHitTesting(false)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
                .navigationTitle(navTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                }
                .sheet(isPresented: $showingPaywall) {
                    PaywallView(source: source)
                        .environmentObject(purchaseManager)
                        .presentationDetents([Self.peekDetent, .large], selection: $detent)
                        .presentationDragIndicator(.visible)
                        // No dimming scrim below the peek detent, so the backdrop
                        // stays at full brightness and the "Close" button behind
                        // the sheet stays tappable.
                        .presentationBackgroundInteraction(.enabled(upThrough: Self.peekDetent))
                        // Can't be swiped away — that would strip the paywall and
                        // leave a bare backdrop. "Not Now" is the exit.
                        .interactiveDismissDisabled()
                }
                .onChange(of: showingPaywall) { _, isShowing in
                    // "Not Now" dismisses the paywall sheet → tear down the gate too.
                    if !isShowing { dismiss() }
                }
                .onChange(of: purchaseManager.isPro) { _, isPro in
                    // Purchased — close the gate. The caller re-presents the
                    // unlocked feature on its own isPro observer.
                    if isPro { dismiss() }
                }
        }
    }
}

// MARK: - Neutral Backdrop
// Used when a feature has no cheap live preview. A soft gradient in the hero
// feature's accent color — ambient branding, deliberately not a fake feature
// screen. Falls back to blue for generic sources (settings, preview).

struct ProGateNeutralBackdrop: View {
    let source: String

    private var accent: Color {
        PaywallFeature.forSource(source)?.color ?? .blue
    }

    var body: some View {
        LinearGradient(
            colors: [accent.opacity(0.18), accent.opacity(0.04)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}
