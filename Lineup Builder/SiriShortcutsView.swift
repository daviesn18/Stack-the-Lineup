import AppIntents
import SwiftUI

// MARK: - Siri Shortcuts
//
// The place a coach goes back to after `AskSiriTip` has been dismissed. A tour
// tip fires once; the phrase list has to live somewhere permanent or the whole
// feature is only discoverable by guessing the right words into Spotlight.
//
// Deliberately a plain list rather than anything clever. These strings are the
// *same* phrases registered in STLShortcuts, so the two files have to be
// changed together — there's no way to read an AppShortcut's phrases back out
// at runtime, which is exactly why this is written down here as a warning
// rather than derived.

struct SiriShortcutsView: View {

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Say these to Siri, or find them in Spotlight by pulling down on your home screen. You can rename any of them in the Shortcuts app.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                ForEach(Self.groups) { group in
                    Section {
                        ForEach(group.phrases, id: \.self) { phrase in
                            Text("\u{201C}\(phrase)\u{201D}")
                                .font(.callout)
                        }
                    } header: {
                        Label(group.title, systemImage: group.symbol)
                    } footer: {
                        Text(group.footnote)
                    }
                }

                Section {
                    // The system's own entry point. Sends the coach to this
                    // app's shortcuts inside the Shortcuts app, where they can
                    // rename a phrase or build something on top of one.
                    ShortcutsLink()
                        .shortcutsLinkStyle(.automatic)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Siri Shortcuts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Content

    private struct PhraseGroup: Identifiable {
        let id = UUID()
        let title: String
        let symbol: String
        let phrases: [String]
        let footnote: String
    }

    /// Mirrors `STLShortcuts.appShortcuts`. Grouped by what the coach is trying
    /// to do rather than by intent, since "recap" and "can they pitch" are the
    /// same kind of question to everyone except the compiler.
    ///
    /// `\(.applicationName)` resolves to the app's display name at runtime, so
    /// these are written out with the real name a coach would say.
    private static let groups: [PhraseGroup] = [
        PhraseGroup(
            title: "Build a lineup",
            symbol: "bolt.fill",
            phrases: [
                "Fill my lineup in Stack the Lineup",
                "Auto-fill positions in Stack the Lineup",
                "Open today's lineup in Stack the Lineup"
            ],
            footnote: "Auto-Fill is part of Pro. Filling opens the app so you can see the grid before the game."
        ),
        PhraseGroup(
            title: "After the game",
            symbol: "sportscourt.fill",
            phrases: [
                "How did we do in Stack the Lineup",
                "Recap my last game in Stack the Lineup"
            ],
            footnote: "Game recaps are part of Pro. Siri answers without opening the app."
        ),
        PhraseGroup(
            title: "Check a rule",
            symbol: "checklist",
            phrases: [
                "What are my rules in Stack the Lineup",
                "What's my pitch limit in Stack the Lineup",
                "How many days rest in Stack the Lineup"
            ],
            footnote: "Free. Answers come from this team's own Fair Play and Pitching Rules — not from a league rulebook."
        ),
        PhraseGroup(
            title: "Check a pitcher",
            symbol: "figure.baseball",
            phrases: [
                "Can Caleb pitch in Stack the Lineup",
                "Is Caleb eligible to pitch in Stack the Lineup"
            ],
            footnote: "Free. Use any player's name. Needs Pitching Rules switched on and a league age on their player page."
        ),
        PhraseGroup(
            title: "Find someone",
            symbol: "magnifyingglass",
            phrases: [
                "Open Caleb in Stack the Lineup",
                "Switch to my other team in Stack the Lineup"
            ],
            footnote: "Free. Players and teams also appear when you search Spotlight directly."
        )
    ]
}

#Preview {
    SiriShortcutsView()
}
