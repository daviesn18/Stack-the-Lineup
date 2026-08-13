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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let source: String
    let navTitle: String
    private let backdrop: AnyView

    /// Detent that leaves the top of the backdrop visible.
    private static let peekDetent: PresentationDetent = .fraction(0.6)

    @State private var showingPaywall = true
    @State private var detent: PresentationDetent

    // MARK: - Detents
    //
    // The peek is an iPhone idea and only works there. A sheet at compact width
    // is anchored to the bottom edge and spans it, so 60% height leaves the top
    // of the backdrop showing above it — which is the whole point, and why the
    // preview initializer opens at the peek rather than full.
    //
    // At regular width a sheet is a centered floating card instead. There is no
    // "top of the backdrop" to reveal, because the backdrop is already visible
    // all the way around the card; the fraction just makes the card too short
    // for its own content. Checked on an iPad Pro 13-inch: the "YOU JUST TRIED"
    // block was cut in half by the pricing panel and the legal footer truncated
    // mid-word. See backlog 3.8.
    //
    // So the peek is offered only where it means something. Offering it and
    // hoping nobody drags to it would leave the broken state one gesture away.

    private var usesPeekDetent: Bool { horizontalSizeClass == .compact }

    private var availableDetents: Set<PresentationDetent> {
        usesPeekDetent ? [Self.peekDetent, .large] : [.large]
    }

    /// Forces `.large` at regular width from the very first frame.
    ///
    /// Read through rather than corrected in `onAppear`: the initializers set
    /// the stored value before any environment exists, so a size class this
    /// view cannot see yet would otherwise render one frame at a detent that is
    /// not in `availableDetents`.
    private var detentSelection: Binding<PresentationDetent> {
        Binding(
            get: { usesPeekDetent ? detent : .large },
            set: { detent = $0 }
        )
    }

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
                        .presentationDetents(availableDetents, selection: detentSelection)
                        .presentationDragIndicator(.visible)
                        // No dimming scrim below this detent, so the backdrop
                        // stays at full brightness and the "Close" button behind
                        // the sheet stays tappable.
                        //
                        // Capped at the peek on iPhone, where anything above it
                        // covers the screen and there is nothing left to reach.
                        // At regular width it has to go up through `.large`,
                        // because that is the only detent there and Close sits
                        // in the nav bar *outside* the centered card — scrimmed
                        // at `.large`, the one non-committal exit from the gate
                        // would be unreachable.
                        .presentationBackgroundInteraction(
                            .enabled(upThrough: usesPeekDetent ? Self.peekDetent : .large)
                        )
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
