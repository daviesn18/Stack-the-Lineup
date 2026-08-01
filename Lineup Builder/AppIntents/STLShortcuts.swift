import AppIntents

// MARK: - STLShortcuts
//
// The phrases Siri recognizes without the coach building anything in Shortcuts
// first. Every phrase must contain `\(.applicationName)` — the system rejects a
// provider at build time otherwise, since a bare "open Caleb" would collide
// across every installed app.
//
// Phrasing note: coaches say the app name a dozen different ways. `.applicationName`
// already covers the bundle display name and the CFBundleSpokenName, so the
// variants here are about the *verb* — "open", "show", "pull up" — which is where
// real transcripts actually differ.

nonisolated struct STLShortcuts: AppShortcutsProvider {

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenLineupIntent(),
            phrases: [
                "Open \(.applicationName)",
                "Show my lineup in \(.applicationName)",
                "Open today's lineup in \(.applicationName)",
            ],
            shortTitle: "Open Lineup",
            systemImageName: "list.number"
        )

        AppShortcut(
            intent: OpenPlayerIntent(),
            phrases: [
                "Open \(\.$player) in \(.applicationName)",
                "Show \(\.$player) in \(.applicationName)",
                "Pull up \(\.$player) in \(.applicationName)",
            ],
            shortTitle: "Open Player",
            systemImageName: "person.fill"
        )

        AppShortcut(
            intent: OpenTeamIntent(),
            phrases: [
                "Open \(\.$team) in \(.applicationName)",
                "Switch to \(\.$team) in \(.applicationName)",
            ],
            shortTitle: "Open Team",
            systemImageName: "person.3.fill"
        )

        // Deliberately parameter-free phrases. `throughInning` and
        // `instructions` are both optional, so Siri can run this from a bare
        // sentence and the coach adjusts the rest on screen — and a spoken
        // number in a phrase slot resolves far less reliably than an entity
        // does, which is a bad trade for a Pro action that rewrites the game.
        AppShortcut(
            intent: FillLineupIntent(),
            phrases: [
                "Fill my lineup in \(.applicationName)",
                "Auto-fill positions in \(.applicationName)",
                "Fill the positions in \(.applicationName)",
            ],
            shortTitle: "Fill Lineup",
            systemImageName: "bolt.fill"
        )

        // Parameter-free for the same reason as Fill Lineup, plus one of its
        // own: "how did we do" is a question about the last game roughly always,
        // and the intent already prompts when a doubleheader makes that
        // genuinely ambiguous. Making the coach name a game up front would tax
        // every ask to handle the rare one.
        AppShortcut(
            intent: GameRecapIntent(),
            phrases: [
                "How did we do in \(.applicationName)",
                "Recap my last game in \(.applicationName)",
                "Game recap in \(.applicationName)",
            ],
            shortTitle: "Game Recap",
            systemImageName: "sportscourt.fill"
        )

        // Three tiles rather than one with a spoken topic slot. `topic` has nine
        // cases whose names a coach would never say verbatim ("fielding
        // minimum"), so leaning on a phrase slot to transcribe one is the least
        // reliable part of the whole feature. Presetting the topic per tile
        // makes each phrase a sentence someone would actually say, and the
        // synonyms on RuleTopicAppEnum still cover the other cases for anyone
        // who builds their own shortcut.
        AppShortcut(
            intent: FairPlayRuleIntent(topic: .overview),
            phrases: [
                "What are my rules in \(.applicationName)",
                "My fair play rules in \(.applicationName)",
                "Check my team rules in \(.applicationName)",
            ],
            shortTitle: "My Rules",
            systemImageName: "checklist"
        )

        AppShortcut(
            intent: FairPlayRuleIntent(topic: .pitchLimit),
            phrases: [
                "What's my pitch limit in \(.applicationName)",
                "Pitch limits in \(.applicationName)",
                "How many pitches are allowed in \(.applicationName)",
            ],
            shortTitle: "Pitch Limits",
            systemImageName: "figure.baseball"
        )

        // No pitch count in the phrase, so this answers with the whole rest
        // ladder — which is the right answer to a question asked without a
        // number in it. A coach who has a specific count in mind sets it in
        // Shortcuts, where a typed number doesn't have to survive transcription.
        AppShortcut(
            intent: FairPlayRuleIntent(topic: .restDays),
            phrases: [
                "How many days rest in \(.applicationName)",
                "Rest day rules in \(.applicationName)",
                "When can my pitcher pitch again in \(.applicationName)",
            ],
            shortTitle: "Rest Days",
            systemImageName: "moon.zzz.fill"
        )
    }
}
