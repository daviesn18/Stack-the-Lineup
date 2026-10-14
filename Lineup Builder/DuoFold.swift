import SwiftUI

// MARK: - Duo Fold
//
// Where the iPhone Duo's fold sits inside the current window, read from the
// scene's reserved regions rather than from a device check. The dashboard
// splits its two halves exactly here so nothing tappable ever lands on the
// fold, and so the halves don't move when the coach folds or unfolds.

struct DuoFold: Equatable {
    /// Horizontal position of the fold's center, in the reading view's own
    /// coordinate space.
    var splitX: CGFloat
    /// Width of the fold's gutter. Zero while the device is flat: the region is
    /// reported inactive, but the split stays at the same x.
    var gutter: CGFloat
    /// True when the region is currently active (book pose).
    var isActive: Bool

    /// Nil on a device with no fold, which is how the dashboard decides to use
    /// the iPad layout instead. Reserved regions arrived in iOS 27.1; earlier
    /// systems have no foldable hardware to report.
    static func read(from proxy: GeometryProxy) -> DuoFold? {
        guard #available(iOS 27.1, *) else { return nil }
        return readReservedRegions(from: proxy)
    }

    @available(iOS 27.1, *)
    private static func readReservedRegions(from proxy: GeometryProxy) -> DuoFold? {
        let regions = proxy.reservedRegions(kind: .division, options: .includeInactive)
        let origin = proxy.frame(in: .global).minX
        // A fold is a tall, narrow division that runs the height of the window.
        // Guard on the shape anyway, so a division that isn't a fold (a future
        // window split, say) doesn't move the dashboard's seam.
        guard let fold = regions.first(where: {
            $0.frame.height >= proxy.size.height * 0.9 && $0.frame.width < proxy.size.width * 0.15
        }) else { return nil }
        return DuoFold(
            splitX: fold.frame.midX - origin,
            gutter: fold.isActive ? fold.frame.width : 0,
            isActive: fold.isActive
        )
    }
}
