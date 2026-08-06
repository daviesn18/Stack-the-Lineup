import SwiftUI

// MARK: - Player Chip
//
// One bench or absent chip, shared by the iPhone diamond (DefensiveGridView)
// and the iPad positions pane (iPadPositionsPane).
//
// These were the same ~48-line @ViewBuilder copied into both files, and they
// had already drifted by hand: HStack spacing 6 vs 7, badge minHeight 20 vs 18,
// and — the one that mattered — the iPad copy had lost both read-only guards,
// so a coach with view-only access to a shared team could tap a chip and
// reassign a player. Cosmetics here follow the iPhone copy; the read-only
// guards are unconditional.

/// A tappable chip naming one player who is benched or absent for an inning.
/// Tapping opens the player-led position picker so the coach can move them onto
/// the field — the caller supplies that action, since the two panes track their
/// own sheet state (and the iPhone also dismisses its undo bar).
struct PlayerChip: View {
    /// Which rail the chip belongs to. Was a bare `badge: String` compared
    /// against "BN" / "ABS" in two places per copy.
    enum Kind {
        case bench
        case absent

        var badge: String {
            switch self {
            case .bench:  return "BN"
            case .absent: return "ABS"
            }
        }

        var badgeColor: Color {
            switch self {
            case .bench:  return FieldPosition.bench.badgeColor
            case .absent: return FieldPosition.absent.badgeColor
            }
        }
    }

    @EnvironmentObject private var store: LineupStore

    let player: Player
    let kind: Kind
    /// The inning the rail is showing — `selectedInning` on iPhone,
    /// `clampedInning` on iPad.
    let inning: Int
    var isReadOnly: Bool = false
    let onTap: () -> Void

    /// Bench chips carry the back-to-back-bench warning. The chip is only in the
    /// bench rail because the player is benched this inning, so the neighbours
    /// are all that's left to check — which is exactly
    /// `Lineup.hasConsecutiveBench`, rather than a fourth hand-rolled copy of it.
    private var showsBackToBackWarning: Bool {
        kind == .bench
            && store.lineup.hasConsecutiveBench(player: player, assigningBenchToInning: inning)
    }

    var body: some View {
        Button {
            guard !isReadOnly else { return }
            onTap()
        } label: {
            HStack(spacing: 6) {
                Text(kind.badge)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .frame(minWidth: 28, minHeight: 20)
                    .background(kind.badgeColor)
                    .cornerRadius(5)
                Text(player.displayName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(kind == .absent ? .primary.opacity(0.9) : .primary)
                if showsBackToBackWarning {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
            .padding(.leading, 8)
            .padding(.trailing, 12)
            .padding(.vertical, 6)
            .background(Color(.systemBackground))
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.06), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .disabled(isReadOnly)
    }
}
