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
    }
}
