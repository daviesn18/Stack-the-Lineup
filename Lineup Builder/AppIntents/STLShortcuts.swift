import AppIntents

// MARK: - STLShortcuts
//
// The phrases Siri recognizes without the coach building anything in Shortcuts
// first. Every phrase must contain `\(.applicationName)` — the system rejects a
// provider at build time otherwise, since a bare "open Caleb" would collide
// across every installed app.
//
// Phrasing note: coaches say the app name a dozen different ways. `.applicationName`
// covers `CFBundleDisplayName` plus whatever `INAlternativeAppNames` lists — and
// until 2 Aug 2026 that list did not exist, so only the exact three words
// "Stack the Lineup" resolved. The alternates now live in the Info.plist.
//
// WHERE THE APP NAME SITS IS NOT COSMETIC. Device testing on 2 Aug 2026 found
// that phrases ending "...in Stack the Lineup" lose to Siri's own handlers,
// which commit to a system intent before the phrase ever names us:
//
//   "Open ⟨player⟩ in …"       → "I can't find that in Apple Music"
//   "Switch to ⟨team⟩ in …"    → "It doesn't look like you have an app called that"
//   "Can ⟨player⟩ pitch in …"  → "Would you like to use ChatGPT for that?"
//
// None of those is the app failing to resolve a name — Siri never routed here,
// so `entities(matching:)` was never called. The five that failed now lead with
// `.applicationName` and avoid verbs the system owns ("open", "show",
// "switch to"). **The four that passed are deliberately untouched**, trailing
// app name and all, so the next device run is a controlled comparison rather
// than a fresh guess: if the reworked five start working and the four keep
// working, the placement theory holds.

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

        // FAILED ON DEVICE 2 Aug 2026, reworded. "Open ⟨name⟩" and "Show ⟨name⟩"
        // are phrases the system owns — a bare proper noun after either goes to
        // apps or media. "Look up" and "pull up" are verbs Siri doesn't claim.
        AppShortcut(
            intent: OpenPlayerIntent(),
            phrases: [
                "In \(.applicationName), look up \(\.$player)",
                "In \(.applicationName), pull up \(\.$player)",
                "Look up \(\.$player) in \(.applicationName)",
            ],
            shortTitle: "Open Player",
            systemImageName: "person.fill"
        )

        // FAILED ON DEVICE 2 Aug 2026, and the failure named the cause: Siri
        // answered "it doesn't look like you have an app called that", having
        // taken the spoken *team* name for an app name. "Switch my team to"
        // gives the slot a noun of its own so it can't read as a launch target.
        AppShortcut(
            intent: OpenTeamIntent(),
            phrases: [
                "In \(.applicationName), switch my team to \(\.$team)",
                "In \(.applicationName), look up \(\.$team)",
                "Switch my team to \(\.$team) in \(.applicationName)",
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
        //
        // FAILED ON DEVICE 2 Aug 2026, reworded. "How did we do" reads as a
        // general question right up until the phrase says whose — by which point
        // Siri has already handed it to world knowledge. Naming the app first
        // settles that before the question starts.
        AppShortcut(
            intent: GameRecapIntent(),
            phrases: [
                "In \(.applicationName), how did we do",
                "In \(.applicationName), recap my last game",
                "Recap my last game in \(.applicationName)",
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

        // FAILED ON DEVICE 2 Aug 2026, reworded — and it was the *only* one of
        // the three rules tiles that failed. My Rules and Rest Days run the same
        // intent with a different topic and both worked, so the intent is sound
        // and the phrasing lost. "What's my pitch limit" is the most
        // world-knowledge-shaped question in the whole set.
        AppShortcut(
            intent: FairPlayRuleIntent(topic: .pitchLimit),
            phrases: [
                "In \(.applicationName), what's my pitch limit",
                "In \(.applicationName), how many pitches are allowed",
                "Pitch limits in \(.applicationName)",
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

        // The one rules-adjacent intent that *does* take a parameter in its
        // phrases. A player name is the entity type already proven to resolve
        // through EntityStringQuery in Spotlight, and unlike a spoken inning
        // number a wrong match is obvious in the answer rather than silent.
        //
        // FAILED ON DEVICE 2 Aug 2026, reworded. Every trailing form fell
        // through to "Would you like to use ChatGPT for that?" — which is Siri
        // never having matched the phrase, not the entity failing to resolve.
        AppShortcut(
            intent: PitchEligibilityIntent(),
            phrases: [
                "In \(.applicationName), can \(\.$player) pitch",
                "In \(.applicationName), is \(\.$player) rested",
                "Can \(\.$player) pitch in \(.applicationName)",
            ],
            shortTitle: "Can They Pitch",
            systemImageName: "figure.baseball"
        )
    }
}
