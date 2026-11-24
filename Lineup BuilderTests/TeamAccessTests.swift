import XCTest
@testable import Lineup_Builder

// MARK: - Merge 4: Shared Teams on the account
//
// The server decides access; these pin how the app reads it: each coach's role
// from the fetched team, what each role may do, the invite-link format, and the
// team_members rows decoding from the nested fetch.

final class TeamAccessTests: XCTestCase {

    private let owner = UUID(), editor = UUID(), viewer = UUID()
    private let t0 = Date(timeIntervalSince1970: 1_795_000_000)

    private var coaches: [TeamCoach] {
        [TeamCoach(userID: viewer, role: .viewer, name: "Lee", joinedAt: t0.addingTimeInterval(60)),
         TeamCoach(userID: editor, role: .editor, name: " Jo ", joinedAt: t0)]
    }

    // MARK: - Roles

    func testRolesResolveFromTheFetchedTeam() throws {
        let asOwner = try XCTUnwrap(TeamAccess.resolve(ownerID: owner, ownerName: "Sam", coaches: coaches, me: owner))
        XCTAssertEqual(asOwner.role, .owner)
        XCTAssertTrue(asOwner.isOwner && asOwner.canChangeSettings && asOwner.canEdit && asOwner.isShared)
        XCTAssertEqual(asOwner.coaches.map(\.userID), [editor, viewer], "oldest first")

        let asEditor = try XCTUnwrap(TeamAccess.resolve(ownerID: owner, ownerName: "Sam", coaches: coaches, me: editor))
        XCTAssertEqual(asEditor.role, .editor)
        XCTAssertTrue(asEditor.canEdit)
        XCTAssertFalse(asEditor.canChangeSettings, "team settings are the owner's (decision 1)")

        let asViewer = try XCTUnwrap(TeamAccess.resolve(ownerID: owner, ownerName: "Sam", coaches: coaches, me: viewer))
        XCTAssertFalse(asViewer.canEdit)
        XCTAssertFalse(asViewer.canChangeSettings)

        XCTAssertNil(TeamAccess.resolve(ownerID: owner, ownerName: "Sam", coaches: coaches, me: UUID()))
    }

    func testAnUnsharedTeamIsJustTheOwners() throws {
        let a = try XCTUnwrap(TeamAccess.resolve(ownerID: owner, ownerName: "", coaches: [], me: owner))
        XCTAssertFalse(a.isShared)
        XCTAssertEqual(a.ownerDisplayName, "the head coach")
    }

    func testNamesFallBack() {
        XCTAssertEqual(coaches[1].displayName, "Jo")
        XCTAssertEqual(TeamCoach(userID: UUID(), role: .editor, name: "  ", joinedAt: nil).displayName, "Coach")
    }

    // MARK: - Invite links

    private let token = String(repeating: "ab12", count: 16)

    func testInviteLinksRoundTrip() {
        let url = InviteLink.url(token: token)
        XCTAssertEqual(url.absoluteString, "https://app.stackthelineup.com/join/\(token)")
        XCTAssertEqual(InviteLink.token(from: url), token)
        XCTAssertEqual(InviteLink.token(from: URL(string: "https://APP.stackthelineup.com/join/\(token.uppercased())")!), token)
        XCTAssertEqual(InviteLink.token(from: URL(string: "stackthelineup://join/\(token)")!), token, "simulator testing")
    }

    func testOtherURLsAreNotInvites() {
        for s in ["https://app.stackthelineup.com/team/\(token)",
                  "https://evil.example.com/join/\(token)",
                  "https://app.stackthelineup.com/join/short",
                  "https://app.stackthelineup.com/join/\(token)/extra",
                  "https://app.stackthelineup.com/join/\(String(repeating: "z", count: 64))",
                  "stackthelineup://lineup",
                  "file:///tmp/Cubs.stlteam"] {
            XCTAssertNil(InviteLink.token(from: URL(string: s)!), s)
        }
    }

    // MARK: - Wire format

    func testTeamMembersDecodeFromTheNestedFetch() throws {
        let teamID = "6f1d2c34-1111-4aaa-8bbb-0123456789ab"
        let json = """
        [{"id":"\(teamID)","owner_id":"\(owner.uuidString.lowercased())","name":"Cubs","color_hex":"0000FF",
          "coach_name":"Sam Rivera","game_inning_count":6,"fair_play_config":{},"pitching_config":{},
          "calendar_subscription_url":null,"default_template_id":null,"current_lineup_id":null,
          "created_at":"2026-09-21T13:46:40.123456+00:00","updated_at":"2026-09-21T13:46:40+00:00","deleted_at":null,
          "players":[],"scheduled_games":[],"lineup_templates":[],"lineups":[],"game_logs":[],
          "team_members":[
            {"user_id":"\(editor.uuidString.lowercased())","role":"editor","name":"Jo","joined_at":"2026-11-24T01:00:00.5+00:00"},
            {"user_id":"\(viewer.uuidString.lowercased())","role":"someday-a-new-role","name":null,"joined_at":null}]}]
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { d in
            let s = try d.singleValueContainer().decode(String.self)
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = f.date(from: s) { return date }
            f.formatOptions = [.withInternetDateTime]
            if let date = f.date(from: s) { return date }
            throw DecodingError.dataCorruptedError(in: try d.singleValueContainer(), debugDescription: s)
        }
        let team = try XCTUnwrap(decoder.decode([ServerTeam].self, from: Data(json.utf8)).first)
        let m = try XCTUnwrap(team.membership)
        XCTAssertEqual(m.ownerID, owner)
        XCTAssertEqual(m.ownerName, "Sam Rivera")
        XCTAssertEqual(m.coaches.map(\.userID), [editor], "an unknown role is skipped, not a decode failure")
        XCTAssertEqual(m.coaches.first?.role, .editor)
    }

    func testATeamFromADatabaseWithoutSharingStillDecodes() throws {
        let json = """
        [{"id":"6f1d2c34-1111-4aaa-8bbb-0123456789ab","owner_id":"\(owner.uuidString)","name":"Cubs",
          "color_hex":"0000FF","coach_name":"","game_inning_count":6,"fair_play_config":{},"pitching_config":{},
          "calendar_subscription_url":null,"default_template_id":null,"current_lineup_id":null,
          "created_at":"2026-09-21T13:46:40+00:00","updated_at":"2026-09-21T13:46:40+00:00","deleted_at":null}]
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let team = try XCTUnwrap(decoder.decode([ServerTeam].self, from: Data(json.utf8)).first)
        XCTAssertEqual(team.membership?.coaches, [])
    }

    // MARK: - Sync state

    func testSyncStateFromBeforeSharingStillLoads() throws {
        // sync.json written by a build without `role`.
        let old = #"{"slots":{},"refused":false,"conflicts":0}"#
        if let decoded = try? JSONDecoder().decode(TeamSyncState.self, from: Data(old.utf8)) {
            XCTAssertNil(decoded.role)
        }
        var state = TeamSyncState()
        state.role = .viewer
        let round = try JSONDecoder().decode(TeamSyncState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(round.role, .viewer)
    }
}

// MARK: - The store's owner-only rules

@MainActor
final class TeamAccessStoreTests: XCTestCase {

    private func storeWithAccountTeam(role: TeamRole) -> (LineupStore, UUID) {
        let store = LineupStore()
        let id = store.activeTeam.id
        store.accountTeamIDs.insert(id)
        let me = UUID(), owner = role == .owner ? me : UUID()
        let coaches = role == .owner ? [] : [TeamCoach(userID: me, role: role, name: "Jo", joinedAt: nil)]
        store.teamAccess = [id: TeamAccess.resolve(ownerID: owner, ownerName: "Sam", coaches: coaches, me: me)!]
        return (store, id)
    }

    func testOnlyTheOwnerFinalizes() {
        let (editorStore, _) = storeWithAccountTeam(role: .editor)
        XCTAssertEqual(editorStore.finalizeWaitingOn, "Sam")
        editorStore.finalizeLineup()
        XCTAssertEqual(editorStore.lineup.status, .draft, "the store refuses it too, not just the button")

        let (ownerStore, _) = storeWithAccountTeam(role: .owner)
        XCTAssertNil(ownerStore.finalizeWaitingOn)
        ownerStore.finalizeLineup()
        XCTAssertEqual(ownerStore.lineup.status, .finalized)
    }

    func testOnlyTheOwnerChangesTeamSettings() {
        let (editorStore, id) = storeWithAccountTeam(role: .editor)
        XCTAssertFalse(editorStore.canChangeTeamSettings(id))
        let (ownerStore, ownID) = storeWithAccountTeam(role: .owner)
        XCTAssertTrue(ownerStore.canChangeTeamSettings(ownID))
    }

    func testTeamsOutsideTheAccountAreUnaffected() {
        let store = LineupStore()
        let id = store.activeTeam.id
        // Access recorded for an id that isn't an account team (a stale entry).
        store.teamAccess = [id: TeamAccess(role: .viewer, ownerID: UUID(), ownerName: "Sam", coaches: [])]
        XCTAssertNil(store.access(for: id))
        XCTAssertTrue(store.canChangeTeamSettings(id))
        XCTAssertNil(store.finalizeWaitingOn)
    }
}
