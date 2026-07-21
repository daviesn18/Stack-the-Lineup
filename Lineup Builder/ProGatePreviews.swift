import SwiftUI

// MARK: - ProGate Backdrop Mocks
// Static, self-contained sample screens shown blurred behind the paywall for
// features that don't have a cheap live preview. Sample data only — no store
// access — so they render deterministically as a backdrop. They mirror the real
// UIs closely enough to communicate "this is what you'd be editing."

// MARK: Position Preferences

/// Mocks a player's edit screen with the Position Preferences section filled in.
struct PreferencesPreviewView: View {
    private struct Row { let position: String; let tier: String; let color: Color }

    private let rows: [Row] = [
        Row(position: "Pitcher",      tier: "Strength",  color: .green),
        Row(position: "Catcher",      tier: "Capable",   color: .blue),
        Row(position: "First Base",   tier: "Strength",  color: .green),
        Row(position: "Second Base",  tier: "Capable",   color: .blue),
        Row(position: "Third Base",   tier: "Emergency", color: .orange),
        Row(position: "Shortstop",    tier: "Strength",  color: .green),
        Row(position: "Left Field",   tier: "Capable",   color: .blue),
        Row(position: "Center Field", tier: "Strength",  color: .green),
        Row(position: "Right Field",  tier: "Never",     color: .red),
    ]

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(Color.blue.opacity(0.15)).frame(width: 44, height: 44)
                        Text("7").font(.headline).foregroundColor(.blue)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Jordan Vega").font(.body.weight(.semibold))
                        Text("#7").font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 2)
            }

            Section {
                ForEach(rows, id: \.position) { row in
                    HStack {
                        Text(row.position)
                        Spacer()
                        HStack(spacing: 4) {
                            Text(row.tier)
                                .font(.caption.bold())
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(row.color, in: Capsule())
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("Position Preferences")
            } footer: {
                Text("AutoFill will prioritize Strength and Capable positions. Emergency is used as a last resort. Never positions are never assigned.")
            }
        }
        .listStyle(.insetGrouped)
    }
}

// MARK: Template Lock Grid

/// Mocks the Save-as-Template lock grid: positions down the side, innings across
/// the top, some cells locked (filled) and some open (dashed).
struct TemplateLockPreviewView: View {
    private struct GridRow { let position: String; let cells: [Cell] }
    private struct Cell { let name: String; let locked: Bool }

    private let labelWidth: CGFloat = 52
    private let cellWidth: CGFloat = 60
    private let inningCount = 5

    private let rows: [GridRow] = [
        GridRow(position: "P",  cells: [Cell(name: "Vega", locked: true),  Cell(name: "Vega", locked: true),  Cell(name: "Ruiz", locked: false), Cell(name: "Ruiz", locked: false), Cell(name: "Cole", locked: false)]),
        GridRow(position: "C",  cells: [Cell(name: "Diaz", locked: true),  Cell(name: "Diaz", locked: true),  Cell(name: "Diaz", locked: true),  Cell(name: "Kim",  locked: false), Cell(name: "Kim",  locked: false)]),
        GridRow(position: "1B", cells: [Cell(name: "Shaw", locked: false), Cell(name: "Shaw", locked: false), Cell(name: "Pena", locked: true),  Cell(name: "Pena", locked: true),  Cell(name: "Shaw", locked: false)]),
        GridRow(position: "2B", cells: [Cell(name: "Kim",  locked: false), Cell(name: "Cole", locked: false), Cell(name: "Cole", locked: false), Cell(name: "Vega", locked: false), Cell(name: "Vega", locked: false)]),
        GridRow(position: "SS", cells: [Cell(name: "Ruiz", locked: true),  Cell(name: "Ruiz", locked: true),  Cell(name: "Vega", locked: false), Cell(name: "Diaz", locked: false), Cell(name: "Diaz", locked: false)]),
        GridRow(position: "3B", cells: [Cell(name: "Pena", locked: false), Cell(name: "Kim",  locked: false), Cell(name: "Shaw", locked: false), Cell(name: "Cole", locked: false), Cell(name: "Pena", locked: false)]),
        GridRow(position: "LF", cells: [Cell(name: "Cole", locked: false), Cell(name: "Pena", locked: false), Cell(name: "Kim",  locked: false), Cell(name: "Shaw", locked: false), Cell(name: "Ruiz", locked: false)]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header row
            HStack(spacing: 4) {
                Text("All")
                    .font(.caption2.bold())
                    .foregroundColor(.accentColor)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                    .frame(width: labelWidth, alignment: .leading)
                ForEach(0..<inningCount, id: \.self) { inning in
                    Text("Inn \(inning + 1)")
                        .font(.caption2)
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                        .frame(width: cellWidth, alignment: .center)
                }
            }

            ForEach(rows, id: \.position) { row in
                HStack(spacing: 4) {
                    Text(row.position)
                        .font(.caption.bold())
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                        .frame(width: labelWidth, alignment: .leading)
                    ForEach(Array(row.cells.enumerated()), id: \.offset) { _, cell in
                        gridCell(cell)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func gridCell(_ cell: Cell) -> some View {
        VStack(spacing: 2) {
            Text(cell.name)
                .font(.caption2.bold())
                .lineLimit(1)
            Image(systemName: cell.locked ? "lock.fill" : "lock.open")
                .font(.system(size: 9))
        }
        .frame(width: cellWidth, height: 40)
        .foregroundColor(cell.locked ? .white : .secondary)
        .background(cell.locked ? Color.blue : Color(.secondarySystemBackground))
        .overlay {
            if !cell.locked {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color(.systemGray3), style: StrokeStyle(lineWidth: 1, dash: [3]))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
