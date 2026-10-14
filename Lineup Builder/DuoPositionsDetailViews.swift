import SwiftUI
import Observation

// MARK: - Shared Positions State
//
// The Positions tab on the Duo is one screen split across the fold, so its two
// halves have to agree on the view mode, the inning, the focused position and
// the open picker. The dashboard owns this and hands it down through the
// environment; the iPad's pane keeps its own local state and never sees it.

enum DuoPickerSide {
    case leading, trailing
}

/// A position-and-inning being edited, and which half of the screen the picker
/// covers while it is.
struct DuoPickerTarget: Equatable {
    let position: FieldPosition
    let inning: Int
    let side: DuoPickerSide
}

@Observable
final class DuoPositionsModel {
    /// Switching views closes any open picker.
    var mode: PositionsPaneMode = .inning {
        didSet { if mode != oldValue { picker = nil } }
    }
    /// Zero-based. Chips switch it and close the picker.
    var inning: Int = 0 {
        didSet { if inning != oldValue { picker = nil } }
    }
    /// By Position's focused position. Persists across view switches.
    var focusedPosition: FieldPosition = .shortstop
    var picker: DuoPickerTarget?
}

extension FieldPosition {
    /// The order the Duo lists positions in: battery, infield, outfield.
    static let duoOrder: [FieldPosition] = [
        .pitcher, .catcher, .firstBase, .secondBase, .thirdBase, .shortstop,
        .leftField, .leftCenterField, .centerField, .rightCenterField, .rightField
    ]
}

extension LineupStore {
    /// The positions this lineup uses, in the Duo's order.
    var duoFieldPositions: [FieldPosition] {
        let active = lineup.activeFieldPositions(config: fairPlayConfig)
        return FieldPosition.duoOrder.filter { active.contains($0) }
    }
}

// MARK: - Small Pieces

struct DuoPositionBadge: View {
    let position: FieldPosition
    var minWidth: CGFloat = 30
    var fontSize: CGFloat = 12
    var radius: CGFloat = 6
    var horizontalPadding: CGFloat = 6
    var verticalPadding: CGFloat = 4

    var body: some View {
        Text(position.rawValue)
            .font(.system(size: fontSize, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(minWidth: minWidth)
            .background(position.badgeColor)
            .clipShape(RoundedRectangle(cornerRadius: radius))
    }
}

struct DuoTierCapsule: View {
    let tier: PositionPreferenceTier

    var body: some View {
        Text(tier.displayName)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(tier.duoForeground)
            .padding(.horizontal, 9)
            .padding(.vertical, 2)
            .background(Capsule().fill(tier.duoBackground))
    }
}

/// Wrapping count tiles: how many innings each player has at a position.
struct DuoCountTiles: View {
    let counts: [(player: Player, count: Int)]
    let useFirstName: Bool

    var body: some View {
        ChipFlowLayout(spacing: 8) {
            ForEach(counts, id: \.player.id) { entry in
                HStack(spacing: 6) {
                    Text("\(entry.count)")
                        .font(.system(size: 20, weight: .bold).monospacedDigit())
                    Text(useFirstName ? entry.player.firstName : entry.player.displayName)
                        .font(.system(size: 14))
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemGroupedBackground)))
            }
        }
    }
}

private func duoSectionLabel(_ text: String) -> some View {
    Text(text)
        .font(.system(size: 12, weight: .semibold))
        .tracking(0.4)
        .foregroundColor(.secondary)
}

/// The white inning-by-inning card both left-half views are built from.
private struct DuoInningCard<Row: View>: View {
    let count: Int
    @ViewBuilder let row: (Int) -> Row

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { index in
                row(index)
                if index < count - 1 {
                    Divider().padding(.leading, 14)
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.5)
        )
    }
}

// MARK: - By Position: focused position (left half)

struct DuoFocusedPositionColumn: View {
    @EnvironmentObject var store: LineupStore
    @EnvironmentObject var purchaseManager: PurchaseManager
    @Environment(DuoPositionsModel.self) private var model

    private var isReadOnly: Bool { store.activeTeam.isReadOnly }
    private var positions: [FieldPosition] { store.duoFieldPositions }
    private var inningCount: Int { store.lineup.innings.count }

    private var focused: FieldPosition {
        positions.contains(model.focusedPosition) ? model.focusedPosition : (positions.first ?? .shortstop)
    }

    /// Preferences are a Pro feature, so a free team never sees a tier here.
    private func tier(_ player: Player) -> PositionPreferenceTier? {
        purchaseManager.isPro ? player.positionPreferences[focused] : nil
    }

    private var counts: [(player: Player, count: Int)] {
        store.lineup.displayPlayers(from: store.players)
            .map { player in
                (player, store.lineup.innings.filter { $0.assignments[player.id] == focused }.count)
            }
            .filter { $0.count > 0 }
            .sorted { a, b in
                a.count != b.count ? a.count > b.count : a.player.displayName < b.player.displayName
            }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                positionChips
                DuoInningCard(count: inningCount) { inning in
                    inningRow(inning)
                }

                duoSectionLabel("INNINGS AT \(focused.rawValue) THIS GAME")
                    .padding(.top, 4)
                if counts.isEmpty {
                    Text("Nobody yet")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                } else {
                    DuoCountTiles(counts: counts, useFirstName: true)
                }

                if purchaseManager.isPro { strengthFooter }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 16)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var header: some View {
        HStack(spacing: 10) {
            DuoPositionBadge(position: focused, minWidth: 38, fontSize: 15, radius: 7,
                             horizontalPadding: 8, verticalPadding: 5)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(focused.displayName) by inning")
                    .font(.system(size: 22, weight: .bold))
                    .tracking(-0.4)
                    .lineLimit(1)
                Text("Tap an inning to change who plays it.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private var positionChips: some View {
        HStack(spacing: 4) {
            ForEach(positions, id: \.self) { position in
                let isSelected = position == focused
                Button {
                    model.focusedPosition = position
                } label: {
                    Text(position.rawValue)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(isSelected ? .white : .primary)
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(isSelected ? position.badgeColor : Color.duoFill)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func inningRow(_ inning: Int) -> some View {
        let player = store.lineup.innings[inning].player(at: focused, in: store.players)
        let playerTier = player.flatMap(tier)
        let isEditing = model.picker?.position == focused && model.picker?.inning == inning

        return Button {
            guard !isReadOnly else { return }
            // The coach tapped the left half, so the picker covers the right.
            model.picker = DuoPickerTarget(position: focused, inning: inning, side: .trailing)
        } label: {
            HStack(spacing: 10) {
                Text("Inn \(inning + 1)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 44, alignment: .leading)

                Text(player?.displayName ?? "Open")
                    .font(.system(size: 16))
                    .foregroundColor(
                        player == nil ? .orange : (playerTier == .never ? .red : .primary)
                    )
                    .lineLimit(1)

                Spacer(minLength: 4)

                if let playerTier { DuoTierCapsule(tier: playerTier) }

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(.systemGray3))
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 42)
            .background(isEditing ? Color.blue.opacity(0.1) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isReadOnly)
    }

    private var strengthFooter: some View {
        let names = store.lineup.displayPlayers(from: store.players)
            .filter { $0.positionPreferences[focused] == .strength }
            .map(\.firstName)
        return Text("Strength at \(focused.rawValue): \(names.isEmpty ? "Nobody" : names.joined(separator: ", "))")
            .font(.system(size: 13))
            .foregroundColor(.secondary)
    }
}

// MARK: - Pitching: pitcher by inning (left half)

struct DuoPitcherColumn: View {
    @EnvironmentObject var store: LineupStore
    @EnvironmentObject var purchaseManager: PurchaseManager
    @Environment(DuoPositionsModel.self) private var model

    private var isReadOnly: Bool { store.activeTeam.isReadOnly }
    private var inningCount: Int { store.lineup.innings.count }

    private struct Flag {
        let text: String
        let color: Color
    }

    /// One flag per row, most serious first.
    private func flag(for player: Player, inning: Int) -> Flag? {
        let status: PitchEligibilityStatus? = store.pitchingConfig.rulesEnabled
            ? PitchEligibilityEngine.status(
                for: player, gameLogs: store.gameLogs, config: store.pitchingConfig,
                referenceDate: store.lineup.gameDate)
            : nil

        if case .mustRest = status { return Flag(text: "Resting", color: .red) }

        let caughtEarlier = store.lineup.innings.prefix(inning)
            .contains { $0.assignments[player.id] == .catcher }
        if caughtEarlier { return Flag(text: "Caught earlier", color: .orange) }

        if purchaseManager.isPro {
            let pref = player.positionPreferences[.pitcher]
            if pref == nil || pref == .never { return Flag(text: "Not set to pitch", color: .orange) }
        }

        if case .limited = status {
            let pitchedSoFar = store.lineup.innings.prefix(inning + 1)
                .filter { $0.assignments[player.id] == .pitcher }.count
            if pitchedSoFar >= 3 { return Flag(text: "Near limit", color: .orange) }
        }
        return nil
    }

    private var counts: [(player: Player, count: Int)] {
        store.lineup.displayPlayers(from: store.players)
            .map { player in
                (player, store.lineup.innings.filter { $0.assignments[player.id] == .pitcher }.count)
            }
            .filter { $0.count > 0 }
            .sorted { a, b in
                a.count != b.count ? a.count > b.count : a.player.displayName < b.player.displayName
            }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Pitcher by inning")
                        .font(.system(size: 22, weight: .bold))
                        .tracking(-0.4)
                    Text("Tap an inning to change its pitcher.")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }

                DuoInningCard(count: inningCount) { inning in
                    inningRow(inning)
                }

                duoSectionLabel("INNINGS PITCHED THIS GAME")
                    .padding(.top, 4)
                if counts.isEmpty {
                    Text("Nobody yet")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                } else {
                    DuoCountTiles(counts: counts, useFirstName: false)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 16)
        }
        .background(Color(.systemGroupedBackground))
    }

    private func inningRow(_ inning: Int) -> some View {
        let player = store.lineup.innings[inning].player(at: .pitcher, in: store.players)
        let flag = player.flatMap { flag(for: $0, inning: inning) }
        let isEditing = model.picker?.position == .pitcher && model.picker?.inning == inning

        return Button {
            guard !isReadOnly else { return }
            model.picker = DuoPickerTarget(position: .pitcher, inning: inning, side: .trailing)
        } label: {
            HStack(spacing: 10) {
                Text("Inn \(inning + 1)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 52, alignment: .leading)

                DuoPositionBadge(position: .pitcher, minWidth: 28, verticalPadding: 3)

                Text(player?.displayName ?? "Open")
                    .font(.system(size: 16))
                    .foregroundColor(player == nil ? .orange : .primary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                if let flag {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                        Text(flag.text)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundColor(flag.color)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(.systemGray3))
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(isEditing ? Color.blue.opacity(0.1) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isReadOnly)
    }
}

// MARK: - Position Picker

/// Scrim plus the picker card, centered in one half and never across the fold.
/// It covers the half the coach did not tap, so the thing being edited stays
/// visible.
struct DuoPickerOverlay: View {
    let target: DuoPickerTarget
    let leftWidth: CGFloat
    let gutterWidth: CGFloat
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)

            HStack(spacing: 0) {
                ZStack {
                    if target.side == .leading {
                        DuoPositionPicker(target: target, onDone: onDismiss)
                    }
                }
                .frame(width: leftWidth)

                Color.clear.frame(width: gutterWidth).allowsHitTesting(false)

                ZStack {
                    if target.side == .trailing {
                        DuoPositionPicker(target: target, onDone: onDismiss)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 16)
        }
        .transition(.opacity)
    }
}

/// Who can play this position this inning, best fit first. Picking swaps: the
/// picked player takes the spot and its previous holder moves to the picked
/// player's old one (or the bench).
struct DuoPositionPicker: View {
    let target: DuoPickerTarget
    let onDone: () -> Void

    @EnvironmentObject var store: LineupStore
    @EnvironmentObject var purchaseManager: PurchaseManager

    /// An override the coach has to confirm before the swap goes through.
    private struct Warning: Identifiable {
        enum Kind { case template, pitch, never, bench }
        let kind: Kind
        let player: Player
        var id: String { "\(kind)-\(player.id)" }
    }
    @State private var warning: Warning?
    /// Set once the coach confirms the template override, so the rule warnings
    /// that follow still get their turn.
    @State private var templateOverrideConfirmed = false

    private var position: FieldPosition { target.position }
    private var inning: Int { min(target.inning, max(0, store.lineup.innings.count - 1)) }

    private var holder: Player? {
        store.lineup.innings[inning].player(at: position, in: store.players)
    }

    private func tier(_ player: Player) -> PositionPreferenceTier? {
        purchaseManager.isPro ? player.positionPreferences[position] : nil
    }

    /// `tierRank × 10 + (already placed this inning ? 1 : 0)`; the current
    /// holder always sits last.
    private func rank(_ player: Player) -> Int {
        let tierRank: Int
        switch tier(player) {
        case .strength:  tierRank = 0
        case .capable:   tierRank = 1
        case .none:      tierRank = 2
        case .emergency: tierRank = 3
        case .never:     tierRank = 4
        }
        let placed = store.lineup.innings[inning].position(for: player) != nil ? 1 : 0
        return tierRank * 10 + placed
    }

    private var candidates: [Player] {
        let present = store.lineup.displayPlayers(from: store.players)
            .filter { !store.lineup.isAbsent($0) }
        let others = present.enumerated()
            .filter { $0.element.id != holder?.id }
            .sorted { a, b in
                let (ra, rb) = (rank(a.element), rank(b.element))
                return ra != rb ? ra < rb : a.offset < b.offset
            }
            .map(\.element)
        return others + present.filter { $0.id == holder?.id }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(candidates) { player in
                        row(player)
                    }
                }
                .padding(10)
            }
            Text("Picking a player swaps them with whoever holds \(position.rawValue).")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 340)
        .frame(maxHeight: 540)
        .background(Color(.systemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.3), radius: 30, y: 24)
        .alert(
            alertTitle,
            isPresented: Binding(get: { warning != nil }, set: { if !$0 { warning = nil } }),
            presenting: warning
        ) { pending in
            Button(confirmTitle(pending.kind), role: .destructive) {
                switch pending.kind {
                case .template:
                    templateOverrideConfirmed = true
                    // Deferred so this alert finishes dismissing before a
                    // follow-on rule warning tries to present.
                    DispatchQueue.main.async { attempt(pending.player) }
                case .pitch, .never, .bench:
                    commit(pending.player)
                }
            }
            Button("Cancel", role: .cancel) { warning = nil }
        } message: { pending in
            Text(message(for: pending))
        }
    }

    // MARK: Warnings

    private var alertTitle: String {
        switch warning?.kind {
        case .template: return "Override Default Template?"
        case .pitch:    return "Pitch Eligibility Warning"
        case .never:    return "Position Preference Warning"
        case .bench:    return "Back-to-Back Bench Warning"
        case nil:       return ""
        }
    }

    private func confirmTitle(_ kind: Warning.Kind) -> String {
        switch kind {
        case .template: return "Change Anyway"
        case .pitch:    return "Assign Pitcher Anyway"
        case .never:    return "Assign Anyway"
        case .bench:    return "Assign Bench Anyway"
        }
    }

    private func message(for pending: Warning) -> String {
        let player = pending.player
        switch pending.kind {
        case .template:
            let name = store.defaultTemplateName ?? "your default template"
            if let holder, holder.id != player.id,
               store.isDefaultTemplateAssignment(inning: inning, position: position) {
                return "“\(name)” has \(holder.firstName) at \(position.displayName) for inning \(inning + 1). Putting \(player.firstName) there overrides your default template for this game. Continue?"
            }
            if let current = store.lineup.innings[inning].position(for: player) {
                return "“\(name)” has \(player.firstName) at \(current.displayName) for inning \(inning + 1). Moving them to \(position.displayName) overrides your default template for this game. Continue?"
            }
            return "This overrides “\(name)” for this game. Continue?"
        case .pitch:
            let label = pitchWarning(for: player)?.displayLabel ?? ""
            return "\(player.firstName) may not be eligible to pitch. \(label). You can still assign this position if needed."
        case .never:
            return "\(player.firstName) is marked Never for \(position.displayName). You can still assign this position if needed."
        case .bench:
            return "\(player.firstName) would be on the bench for two consecutive innings. You can still assign bench if needed."
        }
    }

    private func pitchWarning(for player: Player) -> PitchEligibilityStatus? {
        guard position == .pitcher, store.pitchingConfig.rulesEnabled else { return nil }
        let status = PitchEligibilityEngine.status(
            for: player, gameLogs: store.gameLogs, config: store.pitchingConfig,
            referenceDate: store.lineup.gameDate
        )
        return status.blocksAssignment ? status : nil
    }

    /// True when the swap would undo the default template, either by displacing
    /// whoever it put here or by pulling the picked player out of their slot.
    private func overridesDefaultTemplate(_ player: Player) -> Bool {
        guard store.lineup.innings[inning].position(for: player) != position else { return false }
        if let holder, holder.id != player.id,
           store.isDefaultTemplateAssignment(inning: inning, position: position) {
            return true
        }
        return store.isDefaultTemplateAssignment(player: player, inning: inning)
    }

    /// Where the previous holder lands: the picked player's old spot, or the bench.
    private func holderDestination(oldSpot: FieldPosition?) -> FieldPosition {
        if let oldSpot, oldSpot != .absent { return oldSpot }
        return .bench
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                DuoPositionBadge(position: position, minWidth: 34, fontSize: 13)
                Text("\(position.displayName) · Inning \(inning + 1)")
                    .font(.system(size: 17, weight: .bold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Button("Done", action: onDone)
                    .font(.system(size: 16, weight: .semibold))
            }
            Text(holder.map { "Currently \($0.displayName)" } ?? "Open position")
                .font(.system(size: 12.5))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .overlay(alignment: .bottom) { Divider() }
    }

    /// Where the player was the inning before, or their batting-order number
    /// in the first one.
    private func subline(_ player: Player) -> String {
        guard inning > 0 else {
            if let index = store.lineup.battingOrder.firstIndex(of: player.id) { return "#\(index + 1)" }
            return player.number.isEmpty ? "" : "#\(player.number)"
        }
        let previous = store.lineup.innings[inning - 1].position(for: player)
        let label = previous.map { $0.isBench ? "BN" : $0.rawValue } ?? "—"
        return "Inn \(inning): \(label)"
    }

    private func row(_ player: Player) -> some View {
        let playerTier = tier(player)
        let isHolder = player.id == holder?.id
        let current = store.lineup.innings[inning].position(for: player)

        return Button {
            attempt(player)
        } label: {
            HStack(spacing: 10) {
                DuoAvatar(player: player, size: 30, fontSize: 12)

                VStack(alignment: .leading, spacing: 1) {
                    Text(player.displayName)
                        .font(.system(size: 15))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text(subline(player))
                        .font(.system(size: 11.5))
                        .foregroundColor(Color(.tertiaryLabel))
                }

                Spacer(minLength: 4)

                if let playerTier { DuoTierCapsule(tier: playerTier) }

                if let current, current != .absent {
                    Text(current.isBench ? "BN" : current.rawValue)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .frame(minWidth: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(current.isBench ? Color(.systemGray) : current.badgeColor)
                        )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isHolder ? Color.blue.opacity(0.08) : Color(.systemBackground))
            )
            .opacity(playerTier == .never ? 0.45 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Runs the same checks, in the same order, as the iPad's picker. The
    /// first that applies asks for confirmation; none of them blocks.
    private func attempt(_ player: Player) {
        guard !store.activeTeam.isReadOnly else { onDone(); return }
        guard holder?.id != player.id else { onDone(); return }

        if !templateOverrideConfirmed, overridesDefaultTemplate(player) {
            warning = Warning(kind: .template, player: player)
            return
        }
        // The previous holder goes to the bench when the picked player had no
        // spot, so that is the move the no-consecutive-bench rule applies to.
        let oldSpot = store.lineup.innings[inning].position(for: player)
        if let holder, holderDestination(oldSpot: oldSpot) == .bench,
           store.fairPlayConfig.noConsecutiveBench,
           store.lineup.hasConsecutiveBench(player: holder, assigningBenchToInning: inning) {
            warning = Warning(kind: .bench, player: holder)
            return
        }
        if pitchWarning(for: player) != nil {
            warning = Warning(kind: .pitch, player: player)
            return
        }
        if purchaseManager.isPro, player.positionPreferences[position] == .never {
            warning = Warning(kind: .never, player: player)
            return
        }
        commit(player)
    }

    /// The swap: the picked player takes the spot, and its previous holder
    /// moves to the picked player's old one (or the bench).
    private func commit(_ player: Player) {
        defer { onDone() }
        let previousHolder = holder
        // Read before the assignment moves them.
        let oldSpot = store.lineup.innings[inning].position(for: player)

        store.assignPosition(player: player, inning: inning, position: position)
        if let previousHolder {
            store.assignPosition(
                player: previousHolder, inning: inning, position: holderDestination(oldSpot: oldSpot)
            )
        }
    }
}
