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
    }
}
