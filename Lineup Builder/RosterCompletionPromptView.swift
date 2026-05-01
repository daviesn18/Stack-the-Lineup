import SwiftUI

// MARK: - RosterCompletionPromptView
// Shown right after a successful roster import. Newly-imported players have
// only names and jersey numbers — they're missing league age and position
// preferences, which power fair play rules and Auto-Fill suggestions.
// This sheet surfaces those features once and offers a guided "Show Me How"
// path that opens the first imported player's edit sheet directly.

struct RosterCompletionPromptView: View {
    @Environment(\.dismiss) var dismiss

    let importedCount: Int
    let onShowMeHow: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 28) {
                        // Header
                        VStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 56))
                                .foregroundColor(.green)
                                .padding(.top, 12)

                            VStack(spacing: 6) {
                                Text("\(importedCount) \(importedCount == 1 ? "Player" : "Players") Imported")
                                    .font(.title2.bold())
                                Text("Add a few more details to get the most out of the app.")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .padding(.horizontal, 24)

                        // Feature callouts
                        VStack(spacing: 16) {
                            featureRow(
                                icon: "calendar.badge.clock",
                                iconColor: .blue,
                                title: "League Age",
                                detail: "Used for age-based fair play rules and roster planning."
                            )
                            featureRow(
                                icon: "star.circle.fill",
                                iconColor: .yellow,
                                title: "Position Preferences",
                                detail: "Mark each player's strengths so Auto-Fill can suggest the right positions."
                            )
                        }
                        .padding(.horizontal, 24)

                        Spacer(minLength: 24)
                    }
                }

                // Action buttons pinned to the bottom
                VStack(spacing: 12) {
                    Button {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            onShowMeHow()
                        }
                    } label: {
                        HStack {
                            Spacer()
                            Text("Show Me How")
                                .font(.body.bold())
                            Image(systemName: "arrow.right")
                                .font(.caption.bold())
                            Spacer()
                        }
                        .padding(.vertical, 14)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Button {
                        dismiss()
                    } label: {
                        Text("Maybe Later")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
                .padding(.top, 12)
                .background(.bar)
            }
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(false)
        }
    }

    @ViewBuilder
    private func featureRow(icon: String, iconColor: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(iconColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

#Preview {
    RosterCompletionPromptView(importedCount: 8, onShowMeHow: {})
}
