import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct STLEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

// MARK: - Placeholder

extension WidgetSnapshot {
    static let placeholder = WidgetSnapshot(
        teamName:          "Blue Sox",
        teamColorHex:      "4A90D9",
        lineupStatus:      "draft",
        activePlayerCount: 11,
        totalInnings:      6,
        filledInningCount: 4,
        gameDate:          Date(),
        opponent:          "Red Hawks",
        isToday:           true,
        nextGameDate:      nil,
        nextGameOpponent:  nil,
        hasRoster:         true,
        updatedAt:         Date()
    )
}

// MARK: - Timeline Provider

struct STLProvider: TimelineProvider {

    func placeholder(in context: Context) -> STLEntry {
        STLEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (STLEntry) -> Void) {
        completion(STLEntry(date: Date(), snapshot: WidgetSnapshot.load() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<STLEntry>) -> Void) {
        let entry       = STLEntry(date: Date(), snapshot: WidgetSnapshot.load())
        let nextRefresh = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

// MARK: - Supporting Views

private struct StatusPillView: View {
    let status: LineupDisplayStatus

    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(status == .finalized ? Color.green : Color.secondary.opacity(0.5))
                .frame(width: 5, height: 5)
            Text(status.label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(status == .finalized ? Color.green : Color.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(
                status == .finalized
                    ? Color.green.opacity(0.15)
                    : Color.secondary.opacity(0.1)
            )
        )
    }
}

private struct StatCell: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .monospacedDigit()
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }
}

private struct TeamHeader: View {
    let snap: WidgetSnapshot

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(snap.accentColor)
                .frame(width: 7, height: 7)
            Text(snap.teamName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

private struct EmptyWidgetView: View {
    let accent: Color
    let compact: Bool

    var body: some View {
        VStack(spacing: compact ? 8 : 10) {
            Image(systemName: "baseball.fill")
                .font(.system(size: compact ? 22 : 28))
                .foregroundStyle(accent)
            Text("Open Stack the Lineup to get started")
                .font(.system(size: compact ? 11 : 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(.fill, for: .widget)
    }
}

// MARK: - Small Widget View (systemSmall)

private struct STLSmallView: View {
    let entry: STLEntry

    var body: some View {
        if let snap = entry.snapshot, snap.hasRoster {
            VStack(alignment: .leading, spacing: 0) {
                TeamHeader(snap: snap)

                StatusPillView(status: snap.displayStatus)
                    .padding(.top, 4)

                Spacer(minLength: 8)

                gameContent(snap)

                Spacer(minLength: 6)

                Label {
                    Text("\(snap.activePlayerCount) active")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .containerBackground(.fill, for: .widget)
        } else {
            EmptyWidgetView(
                accent: entry.snapshot?.accentColor ?? .blue,
                compact: true
            )
        }
    }

    @ViewBuilder
    private func gameContent(_ snap: WidgetSnapshot) -> some View {
        if snap.isToday {
            Text(snap.gameDate, format: .dateTime.hour().minute())
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.75)
                .lineLimit(1)
            Text(snap.opponent.isEmpty ? "Game day" : "vs. \(snap.opponent)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)

        } else if let nextDate = snap.nextGameDate {
            Text("NEXT GAME")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
                .tracking(0.4)
            Text(nextDate, format: .dateTime.weekday(.abbreviated).month().day())
                .font(.system(size: 15, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let opp = snap.nextGameOpponent {
                Text("vs. \(opp)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

        } else {
            Text("No game scheduled")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Medium Widget View (systemMedium)

private struct STLMediumView: View {
    let entry: STLEntry

    var body: some View {
        if let snap = entry.snapshot, snap.hasRoster {
            VStack(alignment: .leading, spacing: 0) {

                // Top row: opponent + time
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        TeamHeader(snap: snap)

                        if snap.isToday {
                            Text(snap.opponent.isEmpty ? "Game today" : "vs. \(snap.opponent)")
                                .font(.system(size: 17, weight: .bold))
                                .lineLimit(1)
                            Text(snap.gameDate, format: .dateTime.weekday(.abbreviated).month().day())
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)

                        } else if let nextDate = snap.nextGameDate {
                            Text(snap.nextGameOpponent.map { "vs. \($0)" } ?? "Next game")
                                .font(.system(size: 17, weight: .bold))
                                .lineLimit(1)
                            Text(nextDate, format: .dateTime.weekday(.abbreviated).month().day())
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)

                        } else {
                            Text("No game scheduled")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        let displayDate: Date? = snap.isToday ? snap.gameDate : snap.nextGameDate
                        if let d = displayDate {
                            Text(d, format: .dateTime.hour().minute())
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                        }
                        StatusPillView(status: snap.displayStatus)
                    }
                }

                Divider()
                    .padding(.vertical, 8)

                // Bottom stats row
                HStack(spacing: 0) {
                    StatCell(value: "\(snap.activePlayerCount)", label: "Active players")
                    Divider()
                        .frame(height: 28)
                        .padding(.horizontal, 10)
                    StatCell(value: "\(snap.totalInnings)", label: "Innings")
                    Divider()
                        .frame(height: 28)
                        .padding(.horizontal, 10)
                    StatCell(
                        value: "\(snap.filledInningCount) / \(snap.totalInnings)",
                        label: "Innings set"
                    )

                    Spacer()

                    HStack(spacing: 3) {
                        Text("Open app")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .containerBackground(.fill, for: .widget)

        } else {
            EmptyWidgetView(
                accent: entry.snapshot?.accentColor ?? .blue,
                compact: false
            )
        }
    }
}

// MARK: - Widget Entry View (family router)

struct STLWidgetEntryView: View {
    let entry: STLEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        Group {
            switch family {
            case .systemSmall:  STLSmallView(entry: entry)
            case .systemMedium: STLMediumView(entry: entry)
            default:            STLSmallView(entry: entry)
            }
        }
        .widgetURL(URL(string: "stackthelineup://lineup"))
    }
}

// MARK: - Widget

struct STLWidget: Widget {
    let kind = "com.nickdavies.LineupBuilder.STLWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: STLProvider()) { entry in
            STLWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Stack the Lineup")
        .description("Today's game and lineup status for your active team.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Widget Bundle

@main
struct STLWidgetBundle: WidgetBundle {
    var body: some Widget {
        STLWidget()
    }
}
