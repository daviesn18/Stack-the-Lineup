import Foundation
import SwiftUI

// MARK: - DebugDataSeeder
// Seeds a self-contained "Test Team" with fake players and game logs
// for History tab testing. Your real teams and rosters are never touched.
// Triggered by a long-press on the Version row in Settings.

enum DebugDataSeeder {

    // MARK: - Fake Roster
    // 10 players with varied preferences to exercise all UI states:
    // stripe bars (Never), gap chips (never played + not Never),
    // normal bars, and uneven bench distribution.

    static let fakePlayers: [Player] = [
        Player(
            firstName: "Jake", lastName: "Rivera", number: "4",
            leagueAge: 12,
            positionPreferences: [
                .pitcher: .strength, .catcher: .never,
                .firstBase: .capable, .secondBase: .capable,
                .leftField: .emergency
            ]
        ),
        Player(
            firstName: "Connor", lastName: "Walsh", number: "7",
            leagueAge: 11,
            positionPreferences: [
                .shortstop: .strength, .thirdBase: .strength,
                .secondBase: .capable, .centerField: .capable
            ]
        ),
        Player(
            firstName: "Tyler", lastName: "Nguyen", number: "11",
            leagueAge: 10,
            positionPreferences: [
                .catcher: .strength, .firstBase: .capable,
                .pitcher: .emergency, .rightField: .never
            ]
        ),
        Player(
            firstName: "Marcus", lastName: "Bell", number: "2",
            leagueAge: 12,
            positionPreferences: [
                .leftField: .strength, .centerField: .strength,
                .rightField: .capable, .pitcher: .never, .catcher: .never
            ]
        ),
        Player(
            firstName: "Drew", lastName: "Santos", number: "9",
            leagueAge: 11,
            positionPreferences: [
                .firstBase: .strength, .thirdBase: .capable,
                .pitcher: .capable, .centerField: .emergency
            ]
        ),
        Player(
            firstName: "Eli", lastName: "Park", number: "14",
            leagueAge: 10,
            positionPreferences: [
                .secondBase: .strength, .shortstop: .capable,
                .thirdBase: .capable, .catcher: .never
            ]
        ),
        Player(
            firstName: "Owen", lastName: "Fischer", number: "5",
            leagueAge: 11,
            positionPreferences: [
                .centerField: .strength, .rightField: .capable,
                .leftField: .capable, .catcher: .never
            ]
        ),
        Player(
            firstName: "Nate", lastName: "Coleman", number: "18",
            leagueAge: 13,
            positionPreferences: [
                .pitcher: .strength, .shortstop: .capable,
                .firstBase: .capable
            ]
        ),
        Player(
            firstName: "Leo", lastName: "Huang", number: "3",
            leagueAge: 12,
            positionPreferences: [
                .thirdBase: .strength, .secondBase: .capable,
                .leftField: .capable, .pitcher: .never
            ]
        ),
        Player(
            firstName: "Cam", lastName: "Torres", number: "21",
            leagueAge: 10,
            positionPreferences: [
                .rightField: .strength, .centerField: .capable,
                .firstBase: .capable, .pitcher: .never, .catcher: .never
            ]
        ),
    ]

    // MARK: - Public API

    static func seed(into store: LineupStore) {
        // Remember which team was active so we can switch back after
        let previousTeamID = store.activeTeamID

        // Create a fresh test team — addTeam switches to it automatically
        store.addTeam(name: "Test Team", color: .orange)
        let testTeamID = store.activeTeamID

        // Assign the Little League pitching rules preset so the test team
        // has pitch count/rest day limits configured out of the box.
        if let testTeamID {
            var pitchingConfig = PitchingConfig()
            pitchingConfig.applyLittleLeaguePreset()
            pitchingConfig.rulesEnabled = true
            store.updatePitchingConfig(pitchingConfig, for: testTeamID)
        }

        // Seed players into the test team
        for player in fakePlayers {
            store.addPlayer(player)
        }

        // Seed game logs into the test team
        for log in makeFakeGameLogs() {
            store.insertDebugGameLog(log)
        }

        // Seed a couple of lineup templates so the template picker/editor
        // has real data to exercise, including overlapping-position variety.
        for template in makeFakeTemplates() {
            store.saveTemplate(template)
        }

        // Seed a schedule by running mock .ics text through the real
        // ICalParser, exercising the actual import pipeline rather than
        // hand-building ScheduledGame values. Lets Pick from Schedule,
        // the upcoming-games filter, and practice/cancelled filtering all
        // be tested against the other seeded data in the same team.
        switch ICalParser.parse(data: makeFakeICalData()) {
        case .success(let events):
            let games = events.map { event in
                ScheduledGame(
                    icalUID: event.uid,
                    date: event.date,
                    opponent: event.opponent,
                    location: event.location,
                    rawSummary: event.rawSummary,
                    isCancelled: event.isCancelled
                )
            }
            store.mergeScheduledGames(games)
            store.setCalendarSubscriptionURL("https://example.com/test-team.ics")
        case .failure:
            break // seeding tool only — the mock text below is known-good
        }

        // Switch back to the original active team
        if let previousID = previousTeamID, previousID != testTeamID {
            store.switchTeam(to: previousID)
        }
    }

    // MARK: - Mock Schedule (.ics) Construction
    // Builds real iCalendar text and runs it through ICalParser rather than
    // hand-building ScheduledGame values, so seeding exercises the same
    // pipeline a real GameChanger/LeagueApps export would go through.
    // Covers: UTC datetime, TZID datetime, STATUS:CANCELLED, a practice
    // event (should be filtered from "upcoming games" but still stored),
    // and a same-opponent rematch against a team from the fake game logs.

    private static func makeFakeICalData() -> Data {
        let utcFormatter = DateFormatter()
        utcFormatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        utcFormatter.timeZone = TimeZone(identifier: "UTC")

        let localFormatter = DateFormatter()
        localFormatter.dateFormat = "yyyyMMdd'T'HHmmss"
        localFormatter.timeZone = TimeZone(identifier: "America/New_York")

        func utcStamp(daysFromNow: Int, hour: Int, minute: Int) -> String {
            var comps = DateComponents()
            comps.day = daysFromNow
            comps.hour = hour
            comps.minute = minute
            let date = Calendar.current.date(byAdding: comps, to: Calendar.current.startOfDay(for: Date()))!
            return utcFormatter.string(from: date)
        }

        func localStamp(daysFromNow: Int, hour: Int, minute: Int) -> String {
            var comps = DateComponents()
            comps.day = daysFromNow
            comps.hour = hour
            comps.minute = minute
            let date = Calendar.current.date(byAdding: comps, to: Calendar.current.startOfDay(for: Date()))!
            return localFormatter.string(from: date)
        }

        let events: [String] = [
            """
            BEGIN:VEVENT
            UID:stl-test-1@stackthelineup.debug
            DTSTAMP:\(utcStamp(daysFromNow: 1, hour: 23, minute: 30))
            DTSTART:\(utcStamp(daysFromNow: 1, hour: 23, minute: 30))
            SUMMARY:Test Team @ Cardinals
            LOCATION:Riverside Park Field 1
            END:VEVENT
            """,
            """
            BEGIN:VEVENT
            UID:stl-test-2@stackthelineup.debug
            DTSTAMP:\(utcStamp(daysFromNow: 3, hour: 22, minute: 0))
            DTSTART:\(utcStamp(daysFromNow: 3, hour: 22, minute: 0))
            SUMMARY:Warriors @ Wildcats
            LOCATION:City Park Field 2
            END:VEVENT
            """,
            """
            BEGIN:VEVENT
            UID:stl-test-3@stackthelineup.debug
            DTSTAMP:\(localStamp(daysFromNow: 6, hour: 18, minute: 30))
            DTSTART;TZID=America/New_York:\(localStamp(daysFromNow: 6, hour: 18, minute: 30))
            SUMMARY:Test Team vs Tigers
            LOCATION:Home Field
            END:VEVENT
            """,
            """
            BEGIN:VEVENT
            UID:stl-test-4@stackthelineup.debug
            DTSTAMP:\(utcStamp(daysFromNow: 5, hour: 23, minute: 0))
            DTSTART:\(utcStamp(daysFromNow: 5, hour: 23, minute: 0))
            SUMMARY:Test Team vs Eagles
            STATUS:CANCELLED
            END:VEVENT
            """,
            """
            BEGIN:VEVENT
            UID:stl-test-5@stackthelineup.debug
            DTSTAMP:\(utcStamp(daysFromNow: 2, hour: 21, minute: 0))
            DTSTART:\(utcStamp(daysFromNow: 2, hour: 21, minute: 0))
            SUMMARY:Team Practice - Batting Cages
            LOCATION:Indoor Facility
            END:VEVENT
            """,
            """
            BEGIN:VEVENT
            UID:stl-test-6@stackthelineup.debug
            DTSTAMP:\(utcStamp(daysFromNow: 10, hour: 22, minute: 30))
            DTSTART:\(utcStamp(daysFromNow: 10, hour: 22, minute: 30))
            SUMMARY:Test Team vs. Blue Jays
            LOCATION:Eastside Complex
            END:VEVENT
            """,
        ]

        let text = "BEGIN:VCALENDAR\nVERSION:2.0\n" + events.joined(separator: "\n") + "\nEND:VCALENDAR"
        return Data(text.utf8)
    }

    // MARK: - Template Construction
    // Two templates covering different lock patterns: a standard home
    // rotation with a pitcher/catcher platoon, and a shorter, more locked-down
    // variant for testing a template with heavier coverage.

    private static func makeFakeTemplates() -> [LineupTemplate] {
        let jakeID   = fakePlayers.first { $0.firstName == "Jake" }!.id
        let nateID   = fakePlayers.first { $0.firstName == "Nate" }!.id
        let drewID   = fakePlayers.first { $0.firstName == "Drew" }!.id
        let tylerID  = fakePlayers.first { $0.firstName == "Tyler" }!.id
        let connorID = fakePlayers.first { $0.firstName == "Connor" }!.id
        let battingOrder = fakePlayers.map { $0.id }

        let homeRotation = LineupTemplate(
            name: "Home Rotation",
            battingOrder: battingOrder,
            positionLocks: [
                PositionLock(playerID: jakeID, position: .pitcher, innings: 0...1),
                PositionLock(playerID: nateID, position: .pitcher, innings: 4...6),
                PositionLock(playerID: tylerID, position: .catcher, innings: 0...2),
                PositionLock(playerID: connorID, position: .shortstop, innings: 0...0),
            ]
        )

        let awayRotation = LineupTemplate(
            name: "Away Rotation — short bench",
            battingOrder: battingOrder,
            positionLocks: [
                PositionLock(playerID: drewID, position: .pitcher, innings: 0...1),
                PositionLock(playerID: jakeID, position: .pitcher, innings: 2...3),
                PositionLock(playerID: tylerID, position: .catcher, innings: 0...5),
            ]
        )

        return [homeRotation, awayRotation]
    }

    // MARK: - Game Log Construction

    private static func makeFakeGameLogs() -> [GameLog] {
        let opponents    = ["Tigers", "Blue Jays", "Cardinals", "Marlins", "Eagles"]
        let inningCounts = [6, 6, 5, 6, 5]
        let dayOffsets: [TimeInterval] = [-28, -21, -14, -7, -2]

        // Snapshots built from fakePlayers so IDs match the live roster
        let snapshots = fakePlayers.map { PlayerSnapshot(from: $0) }

        // Pitch counts spread across all 5 games rather than just the most
        // recent one — needed to exercise the weekly rolling-window total,
        // not just single-game rest day math. Jake and Nate pitch in the
        // last two games (offsets -7 and -2, both inside a 7-day window),
        // so their combined weekly totals should trip weekly-limit warnings
        // if a team's PitchingConfig has one configured. Drew only shows up
        // in a couple of games — realistic for a spot-start reliever.
        let jakeID = fakePlayers.first { $0.firstName == "Jake" }?.id.uuidString ?? ""
        let nateID = fakePlayers.first { $0.firstName == "Nate" }?.id.uuidString ?? ""
        let drewID = fakePlayers.first { $0.firstName == "Drew" }?.id.uuidString ?? ""

        let pitchCountsByGame: [[String: Int]] = [
            // Game 0 — Tigers, 28 days ago
            [jakeID: 40, nateID: 15],
            // Game 1 — Blue Jays, 21 days ago
            [drewID: 30, jakeID: 20],
            // Game 2 — Cardinals, 14 days ago
            [nateID: 45, drewID: 10],
            // Game 3 — Marlins, 7 days ago (inside the rolling week with game 4)
            [jakeID: 35, nateID: 18],
            // Game 4 — Eagles, 2 days ago (most recent, drives current eligibility)
            [jakeID: 55, nateID: 22, drewID: 12],
        ]

        return zip(zip(opponents, inningCounts), dayOffsets).enumerated().map { index, args in
            let ((opponent, innings), offset) = args
            let date = Date().addingTimeInterval(offset * 86_400)
            let pitchCounts = pitchCountsByGame[index]
            return GameLog(
                gameDate: date,
                opponent: opponent,
                inningsPlayed: innings,
                battingOrder: snapshots.map { $0.id },
                innings: makeAssignments(snapshots: snapshots),
                playerSnapshot: snapshots,
                pitchCounts: pitchCounts
            )
        }
    }

    // MARK: - Assignment Grid
    //
    // Every inning here is a *valid* defensive alignment: each of the nine
    // field positions is filled exactly once, and the tenth player sits. Read
    // any column top to bottom and you get P, C, 1B, 2B, 3B, SS, LF, CF, RF
    // plus one bench — no position is ever double-filled.
    //
    // This matters beyond looking right in the History tab: seeded games get
    // applied to real lineups via History → Apply, and a grid with two
    // pitchers in an inning produces a lineup the app's own editing rules
    // would never allow. GameLogReuseTests.testSeededGameLogsAreValidLineups
    // guards the invariant.
    //
    // Within that constraint the rotation still leaves the gaps and Never
    // stripes the Players tab needs: nobody plays every position, and no
    // player is ever assigned a position they've marked Never.
    //
    // Bench time is necessarily thin — ten players against nine positions is
    // exactly one bench slot per inning, so seven slots across the game. They
    // are spread unevenly (Nate sits twice; Jake, Connor, Leo and Cam never
    // sit) so the bench-distribution UI still has something to show, and no
    // player sits in back-to-back innings.

    /// The seeded grid, built against the standard fake roster. Exists so the
    /// tests can assert the alignment invariant without seeding a whole team.
    static func debugAssignmentGrid() -> [InningAssignment] {
        makeAssignments(snapshots: fakePlayers.map { PlayerSnapshot(from: $0) })
    }

    private static func makeAssignments(snapshots: [PlayerSnapshot]) -> [InningAssignment] {
        // One row per player, in fakePlayers order. Seven innings per row.
        let sequences: [[FieldPosition]] = [
            // Jake Rivera — pitcher-heavy. Never C. Gaps at SS/3B/CF/RF.
            [.pitcher, .firstBase, .leftField, .pitcher, .secondBase, .pitcher, .firstBase],
            // Connor Walsh — SS/3B specialist, one inning in center.
            [.shortstop, .thirdBase, .shortstop, .centerField, .thirdBase, .shortstop, .thirdBase],
            // Tyler Nguyen — everyday catcher. Gaps at LF/CF (Never RF shouldn't show).
            [.catcher, .catcher, .catcher, .catcher, .catcher, .catcher, .bench],
            // Marcus Bell — pure outfielder. Never P/C. Gap at CF.
            [.leftField, .leftField, .bench, .leftField, .rightField, .rightField, .leftField],
            // Drew Santos — 1B/3B, spot starts on the mound, backup catcher.
            [.firstBase, .bench, .pitcher, .thirdBase, .firstBase, .centerField, .catcher],
            // Eli Park — 2B/SS focus. Never C. Gap at outfield.
            [.secondBase, .shortstop, .secondBase, .bench, .shortstop, .secondBase, .shortstop],
            // Owen Fischer — outfield only. Never C. Gap at infield.
            [.centerField, .centerField, .centerField, .rightField, .bench, .leftField, .centerField],
            // Nate Coleman — pitcher/SS, some 1B. Gap at outfield. Sits twice.
            [.bench, .pitcher, .firstBase, .shortstop, .pitcher, .bench, .pitcher],
            // Leo Huang — 3B/2B, one inning in left. Never P. Gap at RF.
            [.thirdBase, .secondBase, .thirdBase, .secondBase, .leftField, .thirdBase, .secondBase],
            // Cam Torres — RF/CF/1B. Never P/C. Gaps at SS/2B/3B.
            [.rightField, .rightField, .rightField, .firstBase, .centerField, .firstBase, .rightField],
        ]

        var result: [InningAssignment] = (0..<7).map { _ in InningAssignment() }

        for (playerIndex, snap) in snapshots.enumerated() {
            guard playerIndex < sequences.count else { continue }
            for inningIndex in 0..<7 {
                result[inningIndex].assignments[snap.id] = sequences[playerIndex][inningIndex]
            }
        }

        return result
    }
}
