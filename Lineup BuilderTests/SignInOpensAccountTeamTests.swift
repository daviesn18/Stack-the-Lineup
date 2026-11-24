import XCTest
@testable import Lineup_Builder

// MARK: - Signing in opens the account's team
//
// A fresh install starts on an empty "Unnamed Team". When the first sync pass
// after sign-in brings the account's teams down, the app should open one of
// them, but never at the cost of hiding a team the coach has put data into.

final class TeamUntouchedDefaultTests: XCTestCase {

    func testAFreshTeamIsUntouched() {
        XCTAssertTrue(Team().isUntouchedDefault)
    }

    func testAnythingTheCoachAddsCounts() {
        let player = Player(firstName: "Ava", lastName: "Lee", number: "7")
        let edits: [(String, (inout Team) -> Void)] = [
            ("name", { $0.name = "Reds" }),
            ("player", { $0.players = [player] }),
            ("color", { $0.colorHex = "FF0000" }),
            ("innings", { $0.gameInningCount = 6 }),
            ("opponent", { $0.lineup.opponent = "Cubs" }),
            ("batting order", { $0.lineup.battingOrder = [player.id] }),
            ("field position", { $0.lineup.innings[0].assignments[player.id] = .pitcher }),
            ("calendar", { $0.calendarSubscriptionURL = "webcal://example.com/team.ics" }),
            ("fair play", { $0.fairPlayConfig.equalBenchTime.toggle() }),
            ("pitching", { $0.pitchingConfig.rulesEnabled = true }),
            ("read-only", { $0.isReadOnly = true }),
            ("received share", { $0.isSharedParticipant = true }),
        ]
        for (label, edit) in edits {
            var team = Team()
            edit(&team)
            XCTAssertFalse(team.isUntouchedDefault, "\(label) is data")
        }
    }

    func testAWhitespaceNameIsStillUnnamed() {
        var team = Team()
        team.name = "  "
        XCTAssertTrue(team.isUntouchedDefault)
    }

    func testTheRule() {
        var used = Team()
        used.name = "Reds"
        XCTAssertTrue(LineupStore.opensAccountTeam(hadAccountTeams: false, active: Team(), activeIsAccountTeam: false))
        XCTAssertTrue(LineupStore.opensAccountTeam(hadAccountTeams: false, active: nil, activeIsAccountTeam: false))
        XCTAssertFalse(LineupStore.opensAccountTeam(hadAccountTeams: false, active: used, activeIsAccountTeam: false),
                       "a team with data stays open")
        XCTAssertFalse(LineupStore.opensAccountTeam(hadAccountTeams: true, active: Team(), activeIsAccountTeam: false),
                       "only the first account teams to arrive")
        XCTAssertFalse(LineupStore.opensAccountTeam(hadAccountTeams: false, active: Team(), activeIsAccountTeam: true))
    }
}

@MainActor
final class SignInOpensAccountTeamTests: XCTestCase {

    private var store: LineupStore!
    private var previousAccount: String?

    override func setUp() async throws {
        previousAccount = AccountTeamStore.signedInAccount()
        AccountTeamStore.setSignedInAccount(nil)
        store = LineupStore()
        store.teams = [Team()]
        store.activeTeamID = store.teams[0].id
        store.accountTeamIDs = []
        store.movedAwayTeamIDs = []
    }

    override func tearDown() async throws {
        store = nil
        AccountTeamStore.setSignedInAccount(previousAccount)
    }

    private func accountTeam(_ name: String) -> Team {
        var t = Team()
        t.name = name
        return t
    }

    private func apply(added: [Team]) {
        var outcome = TeamSyncOutcome(status: AccountSyncStatus(lastSyncAt: Date(), conflictCount: 0))
        outcome.addedTeams = added
        store.applySyncOutcome(outcome, editCountsAtStart: [:])
    }

    func testAFreshInstallOpensTheAccountTeam() {
        let stripe = accountTeam("Stripe Test 2")
        apply(added: [stripe])

        XCTAssertEqual(store.activeTeamID, stripe.id)
        XCTAssertEqual(store.teamName, "Stripe Test 2")
        XCTAssertEqual(store.teams.count, 2, "the empty team stays; nothing is deleted")
    }

    func testWithSeveralAccountTeamsTheFirstOpens() {
        let a = accountTeam("A"), b = accountTeam("B")
        apply(added: [a, b])
        XCTAssertEqual(store.activeTeamID, a.id)
    }

    func testALocalTeamWithDataStaysOpen() {
        store.teams[0].name = "My Reds"
        store.teams[0].players = [Player(firstName: "Ava", lastName: "Lee", number: "7")]
        let local = store.teams[0].id

        apply(added: [accountTeam("Stripe Test 2")])

        XCTAssertEqual(store.activeTeamID, local)
        XCTAssertEqual(store.teams[0].players.count, 1, "untouched")
    }

    func testALaterAccountTeamDoesNotTakeOver() {
        // The account's teams are already here; the coach then opened a new,
        // empty team on purpose. A team added on the web must not switch away.
        let first = accountTeam("Stripe Test 2")
        apply(added: [first])
        store.teams.append(Team())
        store.activeTeamID = store.teams.last!.id
        let blank = store.activeTeamID

        apply(added: [accountTeam("Added on the web")])

        XCTAssertEqual(store.activeTeamID, blank)
    }

    func testAPassThatAddsNothingChangesNothing() {
        let local = store.activeTeamID
        apply(added: [])
        XCTAssertEqual(store.activeTeamID, local)
    }

    func testAnAdoptedMoveIsNotAFirstSignIn() {
        // A team moved to the account elsewhere comes back as itself: the
        // open team stays the open team (MovedElsewhereTests covers adoption).
        var reds = Team()
        reds.name = "Reds"
        reds.ckRecordName = "team-\(reds.id.uuidString)"
        store.teams = [reds]
        store.activeTeamID = reds.id
        store.noteTeamsMovedElsewhere(.init(modifiedTeams: [reds], deletedRecordNames: [],
                                            movedRecordNames: [reds.ckRecordName!]))
        var copy = reds
        copy.ckRecordName = nil
        copy.isReadOnly = false

        apply(added: [copy])

        XCTAssertEqual(store.activeTeamID, reds.id)
        store.movedAwayTeamIDs = []
    }
}
