import XCTest
@testable import Lineup_Builder

// MARK: - TeamTombstoneTests
//
// Guards the deletion path. The bug these were written against: deleting a team
// never deleted its CKRecord, and the merge appends any server team with no
// local match — so on a fresh install every team the coach had ever deleted
// came back.
//
// The dangerous half of the fix is the guard, not the delete. Deleting the
// record for a team you merely *participate* in would destroy the owner's team
// and every other coach's copy. `testLeavingASharedTeamNeverDeletesTheRecord`
// is the one that must never be relaxed.

final class TeamTombstoneTests: XCTestCase {

    // MARK: Blocking

    func testAnEmptyLedgerBlocksNothing() {
        let tombstones = TeamTombstones()
        XCTAssertTrue(tombstones.isEmpty)
        XCTAssertFalse(tombstones.blocks(teamID: UUID(), recordName: "team-abc"))
    }

    func testARememberedTeamIDIsBlocked() {
        var tombstones = TeamTombstones()
        let id = UUID()
        tombstones.remember(teamID: id, recordName: nil)
        XCTAssertTrue(tombstones.blocks(teamID: id, recordName: nil))
    }

    func testARememberedRecordNameIsBlocked() {
        var tombstones = TeamTombstones()
        tombstones.remember(teamID: UUID(), recordName: "team-abc")
        // A different UUID, same record — still the team that was deleted.
        XCTAssertTrue(tombstones.blocks(teamID: UUID(), recordName: "team-abc"))
    }

    func testEitherIdentifierIsEnough() {
        // The whole reason both are stored: a team deleted before its first
        // upload has no record name, and a record re-created elsewhere has a new
        // name but the same team UUID.
        var tombstones = TeamTombstones()
        let id = UUID()
        tombstones.remember(teamID: id, recordName: "team-abc")

        XCTAssertTrue(tombstones.blocks(teamID: id, recordName: nil))
        XCTAssertTrue(tombstones.blocks(teamID: UUID(), recordName: "team-abc"))
        XCTAssertTrue(tombstones.blocks(teamID: id, recordName: "team-abc"))
    }

    func testAnUnrelatedTeamIsNotBlocked() {
        var tombstones = TeamTombstones()
        tombstones.remember(teamID: UUID(), recordName: "team-abc")
        XCTAssertFalse(tombstones.blocks(teamID: UUID(), recordName: "team-xyz"))
    }

    func testAnEmptyRecordNameIsNotAWildcard() {
        // A team with no record name must not match every other team with none.
        var tombstones = TeamTombstones()
        tombstones.remember(teamID: UUID(), recordName: "")
        XCTAssertFalse(tombstones.blocks(teamID: UUID(), recordName: ""))
        XCTAssertFalse(tombstones.blocks(teamID: UUID(), recordName: nil))
    }

    // MARK: Forgetting

    func testForgettingLetsATeamReturn() {
        // Re-accepting a share, or re-importing a team file, must not be blocked
        // by a tombstone from months ago.
        var tombstones = TeamTombstones()
        let id = UUID()
        tombstones.remember(teamID: id, recordName: "team-abc")
        XCTAssertTrue(tombstones.blocks(teamID: id, recordName: "team-abc"))

        tombstones.forget(teamID: id, recordName: "team-abc")
        XCTAssertFalse(tombstones.blocks(teamID: id, recordName: "team-abc"))
        XCTAssertTrue(tombstones.isEmpty)
    }

    func testForgettingByRecordNameAloneClearsTheWholeEntry() {
        // This is why entries are pairs. Share acceptance only knows the root
        // record name — the team UUID arrives later, with the fetch. If
        // forgetting the record name left the UUID behind, the re-invited team
        // would still be refused, silently and permanently.
        var tombstones = TeamTombstones()
        let id = UUID()
        tombstones.remember(teamID: id, recordName: "team-abc")

        tombstones.forget(teamID: nil, recordName: "team-abc")

        XCTAssertFalse(tombstones.blocks(teamID: id, recordName: nil))
        XCTAssertFalse(tombstones.blocks(teamID: id, recordName: "team-abc"))
        XCTAssertTrue(tombstones.isEmpty)
    }

    func testForgettingOneTeamLeavesTheOthers() {
        var tombstones = TeamTombstones()
        let kept = UUID()
        let dropped = UUID()
        tombstones.remember(teamID: kept, recordName: "team-kept")
        tombstones.remember(teamID: dropped, recordName: "team-dropped")

        tombstones.forget(teamID: dropped, recordName: "team-dropped")

        XCTAssertFalse(tombstones.blocks(teamID: dropped, recordName: "team-dropped"))
        XCTAssertTrue(tombstones.blocks(teamID: kept, recordName: "team-kept"))
    }

    // MARK: Bookkeeping

    func testRememberingTwiceDoesNotDuplicate() {
        var tombstones = TeamTombstones()
        let id = UUID()
        tombstones.remember(teamID: id, recordName: "team-abc")
        tombstones.remember(teamID: id, recordName: "team-abc")
        XCTAssertEqual(tombstones.entries.count, 1)
    }

    func testTheLedgerIsCappedAndDropsTheOldest() {
        var tombstones = TeamTombstones()
        let first = UUID()
        tombstones.remember(teamID: first, recordName: "team-first")

        for i in 0..<TeamTombstones.limit {
            tombstones.remember(teamID: UUID(), recordName: "team-\(i)")
        }

        XCTAssertEqual(tombstones.entries.count, TeamTombstones.limit)
        // Oldest evicted; a team deleted 200 deletions ago can come back, which
        // is the accepted trade for a bounded ledger.
        XCTAssertFalse(tombstones.blocks(teamID: first, recordName: "team-first"))
    }

    func testItSurvivesACodableRoundTrip() throws {
        // It's persisted alongside the teams blob; if it doesn't decode, every
        // tombstone is lost on the next launch and the resurrection returns.
        var tombstones = TeamTombstones()
        let id = UUID()
        tombstones.remember(teamID: id, recordName: "team-abc")

        let data = try JSONEncoder().encode(tombstones)
        let decoded = try JSONDecoder().decode(TeamTombstones.self, from: data)

        XCTAssertEqual(decoded, tombstones)
        XCTAssertTrue(decoded.blocks(teamID: id, recordName: "team-abc"))
    }

    // MARK: The guard that must never be relaxed

    func testLeavingASharedTeamNeverDeletesTheRecord() {
        // Participants must never delete the shared record — that would destroy
        // the owner's team and every other coach's copy. Only an owned team
        // yields a record name to delete.
        var owned = Team(name: "Tigers")
        owned.ckRecordName = "team-owned"
        owned.isReadOnly = false
        owned.isSharedParticipant = false

        var participant = Team(name: "Eagles")
        participant.ckRecordName = "team-someone-elses"
        participant.isSharedParticipant = true

        var readOnly = Team(name: "Hawks")
        readOnly.ckRecordName = "team-read-only"
        readOnly.isReadOnly = true

        XCTAssertEqual(LineupStore.recordNameToDelete(for: owned), "team-owned")
        XCTAssertNil(LineupStore.recordNameToDelete(for: participant))
        XCTAssertNil(LineupStore.recordNameToDelete(for: readOnly))
    }

    func testATeamNeverUploadedHasNothingToDelete() {
        var team = Team(name: "Tigers")
        team.ckRecordName = nil
        XCTAssertNil(LineupStore.recordNameToDelete(for: team))
    }
}

// MARK: - RemoteDeletionClassificationTests
//
// The other half of cross-device deletion: what the device that still HAS the
// team does when CloudKit reports the record gone.
//
// A shared team vanishes — the owner deleted it and a participant's copy has no
// independent existence. An owned team is never removed silently, because a
// spurious deletion would destroy a roster; it raises a prompt instead.

final class RemoteDeletionClassificationTests: XCTestCase {

    private func team(
        _ name: String,
        recordName: String?,
        readOnly: Bool = false,
        participant: Bool = false
    ) -> Team {
        var team = Team(name: name)
        team.ckRecordName = recordName
        team.isReadOnly = readOnly
        team.isSharedParticipant = participant
        return team
    }

    func testASharedTeamIsRemovedWithoutAsking() {
        let shared = team("Eagles", recordName: "team-eagles", readOnly: true)
        let outcome = LineupStore.classifyRemoteDeletions(
            recordNames: ["team-eagles"],
            teams: [shared],
            declined: []
        )
        XCTAssertEqual(outcome.autoRemove, [shared.id])
        XCTAssertTrue(outcome.prompt.isEmpty)
    }

    func testAnOwnedTeamAsksInsteadOfVanishing() {
        // The guard that makes this feature safe. If this ever auto-removes, a
        // misread deletion silently destroys a coach's roster and history.
        let owned = team("Rockhounds", recordName: "team-rockhounds")
        let outcome = LineupStore.classifyRemoteDeletions(
            recordNames: ["team-rockhounds"],
            teams: [owned],
            declined: []
        )
        XCTAssertTrue(outcome.autoRemove.isEmpty)
        XCTAssertEqual(outcome.prompt.count, 1)
        XCTAssertEqual(outcome.prompt.first?.teamID, owned.id)
        XCTAssertEqual(outcome.prompt.first?.teamName, "Rockhounds")
    }

    func testATeamAlreadyKeptDoesNotAskAgain() {
        // A prompt that reappears on every sync is worse than no prompt.
        let owned = team("Rockhounds", recordName: "team-rockhounds")
        let outcome = LineupStore.classifyRemoteDeletions(
            recordNames: ["team-rockhounds"],
            teams: [owned],
            declined: ["team-rockhounds"]
        )
        XCTAssertTrue(outcome.autoRemove.isEmpty)
        XCTAssertTrue(outcome.prompt.isEmpty)
    }

    func testAnUnknownRecordIsIgnored() {
        // Deletions for teams this device never had must not prompt about
        // nothing — every install replays deletions it has no local copy of.
        let owned = team("Rockhounds", recordName: "team-rockhounds")
        let outcome = LineupStore.classifyRemoteDeletions(
            recordNames: ["team-someone-elses"],
            teams: [owned],
            declined: []
        )
        XCTAssertTrue(outcome.autoRemove.isEmpty)
        XCTAssertTrue(outcome.prompt.isEmpty)
    }

    func testAnEmptyRecordNameMatchesNoTeam() {
        // Teams that were never uploaded have a nil record name; an empty
        // string in the deletion list must not sweep them all up.
        let never = team("Tigers", recordName: nil)
        let outcome = LineupStore.classifyRemoteDeletions(
            recordNames: [""],
            teams: [never],
            declined: []
        )
        XCTAssertTrue(outcome.autoRemove.isEmpty)
        XCTAssertTrue(outcome.prompt.isEmpty)
    }

    func testSharedAndOwnedAreHandledInOneBatch() {
        let shared = team("Eagles", recordName: "team-eagles", readOnly: true)
        let owned = team("Rockhounds", recordName: "team-rockhounds")
        let untouched = team("Tigers", recordName: "team-tigers")

        let outcome = LineupStore.classifyRemoteDeletions(
            recordNames: ["team-eagles", "team-rockhounds"],
            teams: [shared, owned, untouched],
            declined: []
        )

        XCTAssertEqual(outcome.autoRemove, [shared.id])
        XCTAssertEqual(outcome.prompt.map(\.teamID), [owned.id])
        XCTAssertFalse(outcome.autoRemove.contains(untouched.id))
    }

    func testAPromptIsIdentifiedByItsRecord() {
        // The declined ledger is keyed on record name, so the prompt's identity
        // has to be too or the two can disagree about what was answered.
        let owned = team("Rockhounds", recordName: "team-rockhounds")
        let outcome = LineupStore.classifyRemoteDeletions(
            recordNames: ["team-rockhounds"],
            teams: [owned],
            declined: []
        )
        XCTAssertEqual(outcome.prompt.first?.id, "team-rockhounds")
    }

    func testAnUnnamedTeamStillReadsAsSomething() {
        let unnamed = team("", recordName: "team-blank")
        let outcome = LineupStore.classifyRemoteDeletions(
            recordNames: ["team-blank"],
            teams: [unnamed],
            declined: []
        )
        XCTAssertEqual(outcome.prompt.first?.displayName, "This team")
    }
}
