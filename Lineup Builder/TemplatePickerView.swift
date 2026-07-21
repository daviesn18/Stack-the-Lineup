import SwiftUI

// MARK: - TemplatePickerView
// Full-screen sheet listing the active team's saved lineup templates.
// Selecting a template replaces the active lineup's batting order and
// pre-fills any locked position assignments, leaving everything else open
// for manual assignment or AutoFill. Mirrors SchedulePickerView's structure.

struct TemplatePickerView: View {
    @EnvironmentObject var store: LineupStore
    @Environment(\.dismiss) var dismiss

    /// Set when a tapped template needs confirmation before it overwrites the
    /// current game. Nil means no alert is pending.
    @State private var pendingTemplate: LineupTemplate?

    var body: some View {
        NavigationStack {
            Group {
                if store.lineupTemplates.isEmpty {
                    emptyState
                } else {
                    templateList
                }
            }
            .navigationTitle("Apply Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert(
                "Replace current game?",
                isPresented: Binding(
                    get: { pendingTemplate != nil },
                    set: { if !$0 { pendingTemplate = nil } }
                ),
                presenting: pendingTemplate
            ) { template in
                Button("Cancel", role: .cancel) { pendingTemplate = nil }
                Button("Apply Template", role: .destructive) { apply(template) }
            } message: { template in
                Text(overwriteMessage(for: template))
            }
        }
    }

    /// Applying a template rebuilds the lineup from scratch, so anything the
    /// coach has already set up is lost. Warn only when there is actually
    /// something to lose — on an untouched game this would just be a speed bump.
    private func handleTap(_ template: LineupTemplate) {
        if store.currentGameHasLineup {
            pendingTemplate = template
        } else {
            apply(template)
        }
    }

    private func apply(_ template: LineupTemplate) {
        pendingTemplate = nil
        store.applyTemplate(template)
        dismiss()
    }

    /// Names what specifically gets wiped, since a coach mid-way through a grid
    /// has more to lose than one who has only set a batting order. Players who
    /// have left the roster are dropped silently, so this is the only mention.
    private func overwriteMessage(for template: LineupTemplate) -> String {
        let hasPositions = store.lineup.innings.contains { !$0.assignments.isEmpty }
        let existing = hasPositions
            ? "Your current game already has a batting order and players assigned to positions."
            : "Your current game already has a batting order."
        let replaced = hasPositions
            ? "Applying “\(template.name)” clears every position you've assigned and replaces the batting order."
            : "Applying “\(template.name)” replaces it."
        return "\(existing) \(replaced) Only the template's locked assignments are filled in — the rest of the field is unassigned."
    }

    // MARK: - Template List

    private var templateList: some View {
        List {
            Section {
                ForEach(store.lineupTemplates) { template in
                    Button {
                        handleTap(template)
                    } label: {
                        templateRow(template)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        defaultSwipeAction(template)
                    }
                }
                .onDelete { offsets in
                    for index in offsets {
                        store.deleteTemplate(id: store.lineupTemplates[index].id)
                    }
                }
            } footer: {
                Text(defaultFooter)
            }
        }
        .listStyle(.insetGrouped)
    }

    /// Setting the default lives on a leading swipe rather than a row tap,
    /// since tapping a row already means "apply this template right now".
    @ViewBuilder
    private func defaultSwipeAction(_ template: LineupTemplate) -> some View {
        if store.isDefaultTemplate(template.id) {
            Button {
                store.setDefaultTemplate(id: nil)
            } label: {
                Label("Remove Default", systemImage: "star.slash")
            }
            .tint(.gray)
        } else {
            Button {
                store.setDefaultTemplate(id: template.id)
            } label: {
                Label("Make Default", systemImage: "star")
            }
            .tint(.orange)
        }
    }

    private var defaultFooter: String {
        if let name = store.defaultTemplateName {
            return "“\(name)” fills in automatically when you start a new game. Swipe right on a template to change or remove your default."
        }
        return "Swipe right on a template to use it for every new game."
    }

    @ViewBuilder
    private func templateRow(_ template: LineupTemplate) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(template.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                if store.isDefaultTemplate(template.id) {
                    Label("Default", systemImage: "star.fill")
                        .font(.caption2.bold())
                        .foregroundColor(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.12))
                        .clipShape(Capsule())
                        .accessibilityLabel("Default template, applied to every new game")
                }
                Spacer()
                if !template.positionLocks.isEmpty {
                    Text("\(template.positionLocks.count) lock\(template.positionLocks.count == 1 ? "" : "s")")
                        .font(.caption.bold())
                        .foregroundColor(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(Capsule())
                }
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundColor(Color(.tertiaryLabel))
            }

            if let summary = lockSummary(template) {
                Text(summary)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    /// Builds a compact "Position: Player (innings), Player (innings)" summary
    /// per position, one line per position, sorted infield-then-outfield.
    private func lockSummary(_ template: LineupTemplate) -> String? {
        guard !template.positionLocks.isEmpty else { return nil }

        let byPosition = Dictionary(grouping: template.positionLocks, by: { $0.position })
        let orderedPositions = FieldPosition.fieldPositions.filter { byPosition[$0] != nil }

        let lines: [String] = orderedPositions.compactMap { position in
            guard let locks = byPosition[position] else { return nil }
            let parts = locks.sorted(by: { $0.innings.lowerBound < $1.innings.lowerBound }).map { lock -> String in
                let name = store.players.first(where: { $0.id == lock.playerID })?.shortName ?? "Unknown"
                let range = lock.innings.lowerBound == lock.innings.upperBound
                    ? "\(lock.innings.lowerBound + 1)"
                    : "\(lock.innings.lowerBound + 1)-\(lock.innings.upperBound + 1)"
                return "\(name) (\(range))"
            }
            return "\(position.rawValue): \(parts.joined(separator: ", "))"
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 48))
                .foregroundColor(Color(.systemGray3))
            Text("Save your first rotation")
                .font(.headline)
            Text("Build a lineup, then tap Save as Template to reuse it. Lock in the assignments you want repeated, and leave the rest open for next time.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}
