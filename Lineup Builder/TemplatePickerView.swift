import SwiftUI

// MARK: - TemplatePickerView
// Full-screen sheet listing the active team's saved lineup templates.
// Selecting a template replaces the active lineup's batting order and
// pre-fills any locked position assignments, leaving everything else open
// for manual assignment or AutoFill. Mirrors SchedulePickerView's structure.

struct TemplatePickerView: View {
    @EnvironmentObject var store: LineupStore
    @Environment(\.dismiss) var dismiss

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
        }
    }

    // MARK: - Template List

    private var templateList: some View {
        List {
            ForEach(store.lineupTemplates) { template in
                Button {
                    store.applyTemplate(template)
                    dismiss()
                } label: {
                    templateRow(template)
                }
            }
            .onDelete { offsets in
                for index in offsets {
                    store.deleteTemplate(id: store.lineupTemplates[index].id)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private func templateRow(_ template: LineupTemplate) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(template.name)
                    .font(.headline)
                    .foregroundColor(.primary)
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
