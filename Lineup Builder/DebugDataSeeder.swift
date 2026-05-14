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

        // Seed players into the test team
        for player in fakePlayers {
            store.addPlayer(player)
        }

        // Seed game logs into the test team
        for log in makeFakeGameLogs() {
            store.insertDebugGameLog(log)
        }

        // Switch back to the original active team
        if let previousID = previousTeamID, previousID != testTeamID {
            store.switchTeam(to: previousID)
        }
    }

    // MARK: - Game Log Construction

    private static func makeFakeGameLogs() -> [GameLog] {
        let opponents    = ["Tigers", "Blue Jays", "Cardinals", "Marlins", "Eagles"]
        let inningCounts = [6, 6, 5, 6, 5]
        let dayOffsets: [TimeInterval] = [-28, -21, -14, -7, -2]

        // Snapshots built from fakePlayers so IDs match the live roster
        let snapshots = fakePlayers.map { PlayerSnapshot(from: $0) }

        // Pitch counts for the most recent game (-2 days) so eligibility warnings
        // fire immediately when testing. Jake threw 55 pitches (3 rest days for ages 11-12),
        // Nate threw 22 (1 rest day). Older games have no pitch data — realistic for
        // a team that just enabled pitch tracking.
        let jakeID   = fakePlayers.first { $0.firstName == "Jake" }?.id.uuidString ?? ""
        let nateID   = fakePlayers.first { $0.firstName == "Nate" }?.id.uuidString ?? ""
        let drewID   = fakePlayers.first { $0.firstName == "Drew" }?.id.uuidString ?? ""
        let recentPitchCounts: [String: Int] = [
            jakeID: 55,   // 3 rest days — ineligible for several days
            nateID: 22,   // 1 rest day — ineligible today, available tomorrow
            drewID: 12,   // 0 rest days — eligible
        ]

        return zip(zip(opponents, inningCounts), dayOffsets).enumerated().map { index, args in
            let ((opponent, innings), offset) = args
            let date = Date().addingTimeInterval(offset * 86_400)
            // Only the most recent game (index 4, offset -2) gets pitch counts
            let pitchCounts = index == 4 ? recentPitchCounts : [:]
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
    // Intentionally leaves gaps and gives Marcus heavy bench time so all
    // UI states are visible in the Players tab.

    private static func makeAssignments(snapshots: [PlayerSnapshot]) -> [InningAssignment] {
        let sequences: [[FieldPosition]] = [
            // Jake Rivera — pitcher-heavy, never catches, gaps at SS/3B
            [.pitcher, .firstBase, .pitcher, .secondBase, .pitcher, .bench, .leftField],
            // Connor Walsh — SS/3B specialist, some outfield
            [.shortstop, .thirdBase, .secondBase, .shortstop, .centerField, .thirdBase, .bench],
            // Tyler Nguyen — catcher-heavy, gap at LF/CF (Never RF so shouldn't show)
            [.catcher, .firstBase, .catcher, .bench, .catcher, .firstBase, .catcher],
            // Marcus Bell — pure outfielder, heavy bench (sitting-more state)
            [.leftField, .bench, .centerField, .bench, .leftField, .bench, .centerField],
            // Drew Santos — 1B/3B, occasional pitcher, gap at SS/2B
            [.firstBase, .pitcher, .thirdBase, .firstBase, .bench, .pitcher, .thirdBase],
            // Eli Park — 2B/SS focus, gap at outfield
            [.secondBase, .shortstop, .secondBase, .thirdBase, .secondBase, .shortstop, .bench],
            // Owen Fischer — CF/RF only, gap at infield (Never C so shouldn't show)
            [.centerField, .rightField, .centerField, .leftField, .rightField, .centerField, .bench],
            // Nate Coleman — pitcher/SS, some 1B, gap at outfield
            [.pitcher, .shortstop, .firstBase, .pitcher, .shortstop, .bench, .pitcher],
            // Leo Huang — 3B/2B, some LF, gap at RF (Never P so P shouldn't show)
            [.thirdBase, .secondBase, .thirdBase, .bench, .thirdBase, .leftField, .secondBase],
            // Cam Torres — RF/CF/1B, gap at SS/2B/3B (Never P/C so those shouldn't show)
            [.rightField, .firstBase, .centerField, .rightField, .bench, .rightField, .centerField],
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
