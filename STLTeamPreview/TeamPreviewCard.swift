import SwiftUI

// MARK: - TeamPreviewCard
//
// The Quick Look preview for a `.stlteam` file. Display-only: a Quick Look preview
// cannot host a working "Import" button that launches the host app, so the card's
// job is to make the file read as a real, openable team and point at the import
// path (Share → Copy to Stack the Lineup).

struct TeamPreviewCard: View {
    let summary: TeamPreviewSummary?

    var body: some View {
        Group {
            if let summary {
                content(summary)
            } else {
                unreadable
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    private func content(_ summary: TeamPreviewSummary) -> some View {
        VStack(spacing: 0) {
            header(summary)

            VStack(spacing: 14) {
                statRow(icon: "person.2.fill",
                        label: "Players",
                        value: "\(summary.playerCount)")
                Divider()
                statRow(icon: "list.bullet.rectangle.portrait.fill",
                        label: "Archived games",
                        value: "\(summary.gameCount)")
                if summary.scheduledCount > 0 {
                    Divider()
                    statRow(icon: "calendar",
                            label: "Scheduled games",
                            value: "\(summary.scheduledCount)")
                }
                if let exported = summary.exportedAtFormatted {
                    Divider()
                    statRow(icon: "square.and.arrow.up",
                            label: "Exported",
                            value: exported)
                }
            }
            .padding(20)

            Spacer(minLength: 0)

            importHint
        }
    }

    private func header(_ summary: TeamPreviewSummary) -> some View {
        let teamColor = Color(hex: summary.colorHex)
        return VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(teamColor)
                    .frame(width: 56, height: 56)
                Image(systemName: "figure.baseball")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
            }
            Text(summary.teamName)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text("Stack the Lineup Team")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 28)
        .padding(.bottom, 20)
        .padding(.horizontal, 20)
        .background(teamColor.opacity(0.12))
    }

    private func statRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            Text(label)
                .foregroundStyle(.primary)
            Spacer()
            Text(value)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
        }
    }

    private var importHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.and.arrow.up")
                .font(.footnote)
            Text("To import: tap Share, then \u{201C}Copy to Stack the Lineup\u{201D}.")
                .font(.footnote)
        }
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemBackground))
    }

    private var unreadable: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.questionmark")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Can\u{2019}t read this team file")
                .font(.headline)
            Text("It may be corrupted or from a newer version of Stack the Lineup.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }
}

// MARK: - Local hex → Color
//
// The extension can't reach the app target's Color(hex:) helper (that lives in
// Models.swift, which we intentionally don't compile in here), so it carries its
// own tiny copy. Accepts "RRGGBB" or "#RRGGBB"; falls back to blue, matching the
// app's Team.color default.

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else {
            self = .blue
            return
        }
        self = Color(
            red: Double((value & 0xFF0000) >> 16) / 255,
            green: Double((value & 0x00FF00) >> 8) / 255,
            blue: Double(value & 0x0000FF) / 255
        )
    }
}
