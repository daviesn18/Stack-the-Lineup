import Foundation

// MARK: - Plural
//
// The count-plus-noun phrases that appear in coach-facing copy, in one place.
//
// These were hand-rolled as `count == 1 ? "inning" : "innings"` in eight
// different files, which is eight chances to ship "1 innings" and eight places
// to fix it when someone does. `TeamRulesAnswerBuilder` already had the right
// shape as private helpers; this is those, promoted.
//
// Deliberately not a general pluralization engine. English is irregular and a
// naive `+ "s"` is how you get "1 catchs" — every phrase here is written out,
// and adding a new noun means adding a function.
//
// `nonisolated` because the project defaults types to `@MainActor` and these
// are pure functions over Int. App Intents answering off the main actor use
// them.

nonisolated enum Plural {

    /// "1 inning" / "6 innings"
    static func innings(_ count: Int) -> String {
        count == 1 ? "1 inning" : "\(count) innings"
    }

    /// "1 pitch" / "34 pitches"
    static func pitches(_ count: Int) -> String {
        count == 1 ? "1 pitch" : "\(count) pitches"
    }

    /// "1 player" / "9 players"
    static func players(_ count: Int) -> String {
        count == 1 ? "1 player" : "\(count) players"
    }

    /// "1 lock" / "3 locks"
    static func locks(_ count: Int) -> String {
        count == 1 ? "1 lock" : "\(count) locks"
    }

    /// The bare noun, for copy that places the number itself — a heading that
    /// reads "Under 4 Innings Fielded", say, where `innings(_:)` would repeat it.
    static func inningNoun(_ count: Int) -> String {
        count == 1 ? "inning" : "innings"
    }
}
