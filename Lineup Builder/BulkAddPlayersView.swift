import SwiftUI

// MARK: - BulkAddPlayersView
// Lets a coach type or paste their full roster as plain text — one player per line.
// Supports three formats:
//   "Jake Rivera"              → first + last, no number
//   "Jake Rivera 12"           → first + last + number (number must be last token)
//   "#12 Jake Rivera"          → number prefixed with #, first + last follow
//
// A live preview list shows exactly what will be imported before committing.
// Duplicate jersey numbers are flagged inline. Players with duplicate names
// (against existing roster) are shown with a warning but are still importable —
// coaches may have two players with the same name.

struct BulkAddPlayersView: View {
    @EnvironmentObject var store: LineupStore
    @Environment(\.dismiss) var dismiss

    @State private var rawText: String = ""
    @State private var parsedPlayers: [BulkEntry] = []
    @FocusState private var textFieldFocused: Bool

    // MARK: - Parsed Entry

    struct BulkEntry: Identifiable {
        let id = UUID()
        let firstName: String
        let lastName: String
        let number: String
        var warning: String?

        var displayName: String { "\(firstName) \(lastName)" }
        var hasNumber: Bool { !number.isEmpty }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // MARK: Input area
                VStack(alignment: .leading, spacing: 8) {
                    Text("One player per line. Jersey number is optional.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.top, 16)

                    Text("Examples: \"Jake Rivera\", \"Jake Rivera 12\", \"#12 Jake Rivera\"")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 16)

                    TextEditor(text: $rawText)
                        .font(.body.monospaced())
                        .frame(minHeight: 160, maxHeight: 220)
                        .padding(10)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .padding(.horizontal, 16)
                        .focused($textFieldFocused)
                        .onChange(of: rawText) { _, _ in
                            parsedPlayers = parse(rawText)
                        }
                }
                .background(Color(.systemBackground))

                Divider()

                // MARK: Preview list
                if parsedPlayers.isEmpty {
                    ContentUnavailableView(
                        "No players yet",
                        systemImage: "person.3",
                        description: Text("Type or paste your roster above.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        Section {
                            ForEach(parsedPlayers) { entry in
                                HStack(spacing: 12) {
                                    // Jersey number badge or placeholder
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(entry.hasNumber ? Color.blue.opacity(0.12) : Color(.systemGray5))
                                            .frame(width: 40, height: 32)
                                        if entry.hasNumber {
                                            Text("#\(entry.number)")
                                                .font(.caption.bold())
                                                .foregroundColor(.blue)
                                        } else {
                                            Text("—")
                                                .font(.caption)
                                                .foregroundColor(Color(.systemGray3))
                                        }
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.displayName)
                                            .font(.body)
                                        if let warning = entry.warning {
                                            Text(warning)
                                                .font(.caption)
                                                .foregroundColor(.orange)
                                        }
                                    }

                                    Spacer()

                                    if entry.warning != nil {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(.orange)
                                            .font(.caption)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        } header: {
                            Text("\(Plural.players(parsedPlayers.count)) to add")
                        }
                    }
                    .listStyle(.insetGrouped)
                }

                // MARK: Bottom CTA
                VStack(spacing: 12) {
                    Button {
                        commit()
                    } label: {
                        Text(parsedPlayers.isEmpty
                             ? "Add Players"
                             : "Add \(Plural.players(parsedPlayers.count).capitalized)")
                            .font(.body.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(parsedPlayers.isEmpty ? Color(.systemGray4) : Color.blue)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(parsedPlayers.isEmpty)

                    Button("Cancel") { dismiss() }
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .background(.bar)
            }
            .navigationTitle("Add Players")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                textFieldFocused = true
            }
        }
    }

    // MARK: - Parser

    /// Parses raw text into BulkEntry values. Each non-empty line becomes one player.
    /// Supported formats:
    ///   "Jake Rivera"        → firstName=Jake, lastName=Rivera, number=""
    ///   "Jake Rivera 12"     → firstName=Jake, lastName=Rivera, number="12"
    ///   "#12 Jake Rivera"    → firstName=Jake, lastName=Rivera, number="12"
    private func parse(_ text: String) -> [BulkEntry] {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var seenNumbers: [String: Int] = [:] // number → line index for dupe detection
        var entries: [BulkEntry] = []

        for (lineIndex, line) in lines.enumerated() {
            var tokens = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard !tokens.isEmpty else { continue }

            var number = ""

            // Check for #number prefix (e.g. "#12 Jake Rivera")
            if tokens.first?.hasPrefix("#") == true {
                let raw = String(tokens.removeFirst().dropFirst())
                if raw.allSatisfy({ $0.isNumber }) && !raw.isEmpty {
                    number = raw
                } else {
                    // Malformed # token — treat whole line as name only
                    tokens.insert("#" + raw, at: 0)
                }
            }

            // Check for trailing number (e.g. "Jake Rivera 12")
            if number.isEmpty,
               let last = tokens.last,
               last.allSatisfy({ $0.isNumber }),
               tokens.count >= 3 {
                number = last
                tokens.removeLast()
            }

            // Remaining tokens form the name
            guard tokens.count >= 2 else {
                // Single token — use as first name, empty last name not valid
                // Skip silently; partially typed lines shouldn't block the flow
                continue
            }

            let firstName = tokens.first!
            let lastName = tokens.dropFirst().joined(separator: " ")

            // Build warning
            var warning: String? = nil

            // Duplicate number check
            if !number.isEmpty {
                if let existingLine = seenNumbers[number] {
                    warning = "Jersey #\(number) already used on line \(existingLine + 1)"
                } else if store.players.contains(where: { $0.number == number }) {
                    warning = "Jersey #\(number) already in your roster"
                } else {
                    seenNumbers[number] = lineIndex
                }
            }

            // Duplicate name check (warning only, not blocking)
            let fullName = "\(firstName) \(lastName)"
            if store.players.contains(where: { $0.displayName.lowercased() == fullName.lowercased() }) {
                let nameWarning = "\(fullName) is already in your roster"
                warning = warning.map { $0 + " · " + nameWarning } ?? nameWarning
            }

            entries.append(BulkEntry(
                firstName: firstName,
                lastName: lastName,
                number: number,
                warning: warning
            ))
        }

        return entries
    }

    // MARK: - Commit

    private func commit() {
        guard !parsedPlayers.isEmpty else { return }

        let newPlayers = parsedPlayers.map { entry in
            Player(
                firstName: entry.firstName,
                lastName: entry.lastName,
                number: entry.number
            )
        }

        store.addPlayers(newPlayers)

        Analytics.signal("roster.bulk_add.completed", parameters: [
            "count": "\(newPlayers.count)",
            "withNumbers": "\(newPlayers.filter { !$0.number.isEmpty }.count)"
        ])

        dismiss()
    }
}

// MARK: - Preview

#Preview {
    BulkAddPlayersView()
        .environmentObject(LineupStore())
}
