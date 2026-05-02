import SwiftUI

// MARK: - RosterImportInstructionsView
// Shown when a coach taps "Import Roster" in PlayersView before the file
// picker opens. Explains where to get the roster file from GameChanger so
// coaches aren't left wondering what file to look for.

struct RosterImportInstructionsView: View {
    @Environment(\.dismiss) var dismiss

    /// Called when the coach taps "Choose File" — dismisses this sheet and
    /// opens the file picker in the parent view.
    let onChooseFile: () -> Void

    private let gcURL = URL(string: "gamechanger://")!
    private let gcAppStoreURL = URL(string: "https://apps.apple.com/app/id1308415878")!

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 28) {
                        // Icon + headline
                        VStack(spacing: 12) {
                            Image(systemName: "square.and.arrow.down.on.square")
                                .font(.system(size: 52))
                                .foregroundColor(.blue)
                                .padding(.top, 16)

                            Text("Import Your Roster")
                                .font(.title2.bold())
                        }
                        .padding(.horizontal, 24)

                        // GameChanger instructions
                        VStack(alignment: .leading, spacing: 16) {
                            instructionRow(number: "1", text: "Open GameChanger and go to your team.")
                            instructionRow(number: "2", text: "Tap Stats, then Export.")
                            instructionRow(number: "3", text: "Share the file and select Stack the Lineup.")
                        }
                        .padding(.horizontal, 24)

                        // Open GC button
                        Button {
                            if UIApplication.shared.canOpenURL(gcURL) {
                                UIApplication.shared.open(gcURL)
                            } else {
                                UIApplication.shared.open(gcAppStoreURL)
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.up.right.square")
                                Text("Open GameChanger")
                            }
                            .font(.subheadline.bold())
                            .foregroundColor(.blue)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.blue.opacity(0.1))
                            )
                        }
                        .padding(.horizontal, 24)

                        // Alternative path note
                        Text("You can also save the file to Files first and import it from there.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)

                        Spacer(minLength: 24)
                    }
                }

                // CTA pinned to bottom
                VStack(spacing: 12) {
                    Button {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            onChooseFile()
                        }
                    } label: {
                        HStack {
                            Spacer()
                            Text("Choose File")
                                .font(.body.bold())
                            Image(systemName: "folder")
                                .font(.body)
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
                        Text("Cancel")
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
        }
    }

    @ViewBuilder
    private func instructionRow(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(number)
                .font(.headline)
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.blue))

            Text(text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
    }
}

#Preview {
    RosterImportInstructionsView(onChooseFile: {})
}
