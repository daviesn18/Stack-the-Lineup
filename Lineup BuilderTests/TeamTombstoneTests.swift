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
        // ⚠️ This branch is unreachable in production and this test does not
        // show otherwise — it calls the classifier directly. The only caller
        // feeds it `fetchChanges().deletedRecordNames`, which comes from the
        // coach's own private zone, and a received team's record lives in the
        // owner's zone in the shared database. A head coach deleting a shared
        // team is handled by `classifyRevokedShares` instead. Kept because the
        // rule is correct if this input ever does carry a shared record.
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

// MARK: - RevokedShareClassificationTests
//
// A team the coach was invited to, that the head coach then deleted or stopped
// sharing. The classifier above cannot see this: its input comes from the
// private database's own zone, and a received team's record lives in the
// owner's zone in the shared database.
//
// Absence from the shared fetch is the whole signal, so these tests are mostly
// about the cases where absence must NOT mean revoked.

final class RevokedShareClassificationTests: XCTestCase {

    private func team(_ name: String, recordName: String?) -> Team {
        var team = Team(name: name)
        team.ckRecordName = recordName
        return team
    }

    func testAReceivedTeamMissingFromTheFetchIsRevoked() {
        let received = team("Eagles", recordName: "team-eagles")
        let revoked = LineupStore.classifyRevokedShares(
            teams: [received],
            fetchedRecordNames: [],
            receivedRecordNames: ["team-eagles"]
        )
        XCTAssertEqual(revoked.count, 1)
        XCTAssertEqual(revoked.first?.teamID, received.id)
        XCTAssertEqual(revoked.first?.teamName, "Eagles")
    }

    func testAReceivedTeamStillInTheFetchIsLeftAlone() {
        let received = team("Eagles", recordName: "team-eagles")
        let revoked = LineupStore.classifyRevokedShares(
            teams: [received],
            fetchedRecordNames: ["team-eagles"],
            receivedRecordNames: ["team-eagles"]
        )
        XCTAssertTrue(revoked.isEmpty)
    }

    func testAnOwnedTeamIsNeverRevoked() {
        // The guard that makes this safe, and the mirror of
        // testAnOwnedTeamAsksInsteadOfVanishing. An owned team is absent from
        // every shared fetch by definition — it lives in the coach's own private
        // zone. Only the ledger separates the two, so if this ever passes an
        // owned team through, the shared fetch silently deletes the coach's own
        // teams on a device that has ever joined a share.
        let owned = team("Rockhounds", recordName: "team-rockhounds")
        let revoked = LineupStore.classifyRevokedShares(
            teams: [owned],
            fetchedRecordNames: [],
            receivedRecordNames: ["team-eagles"]
        )
        XCTAssertTrue(revoked.isEmpty)
    }

    func testATeamWithNoRecordNameIsSkippedRatherThanGuessedAt() {
        // The state bug (a) used to create by clearing record names on received
        // teams. There is nothing to match against the fetch, so the safe answer
        // is to leave it alone.
        let orphan = team("Eagles", recordName: nil)
        let revoked = LineupStore.classifyRevokedShares(
            teams: [orphan],
            fetchedRecordNames: [],
            receivedRecordNames: ["team-eagles"]
        )
        XCTAssertTrue(revoked.isEmpty)
    }

    func testAnEmptyRecordNameIsNotAWildcard() {
        let blank = team("Eagles", recordName: "")
        let revoked = LineupStore.classifyRevokedShares(
            teams: [blank],
            fetchedRecordNames: [],
            receivedRecordNames: [""]
        )
        XCTAssertTrue(revoked.isEmpty)
    }

    func testOwnedAndRevokedAreSeparatedInOneBatch() {
        let owned    = team("Rockhounds", recordName: "team-rockhounds")
        let kept     = team("Cyclones",   recordName: "team-cyclones")
        let revokedT = team("Eagles",     recordName: "team-eagles")
        let revoked = LineupStore.classifyRevokedShares(
            teams: [owned, kept, revokedT],
            fetchedRecordNames: ["team-cyclones"],
            receivedRecordNames: ["team-cyclones", "team-eagles"]
        )
        XCTAssertEqual(revoked.map { $0.teamID }, [revokedT.id])
    }

    func testARevocationIsIdentifiedByItsRecord() {
        let received = team("Eagles", recordName: "team-eagles")
        let revoked = LineupStore.classifyRevokedShares(
            teams: [received],
            fetchedRecordNames: [],
            receivedRecordNames: ["team-eagles"]
        )
        XCTAssertEqual(revoked.first?.id, "team-eagles")
    }

    func testAnUnnamedTeamStillReadsAsSomething() {
        let unnamed = team("", recordName: "team-blank")
        let revoked = LineupStore.classifyRevokedShares(
            teams: [unnamed],
            fetchedRecordNames: [],
            receivedRecordNames: ["team-blank"]
        )
        XCTAssertEqual(revoked.first?.displayName, "A shared team")
    }
}

// MARK: - CoachNamePlaceholderTests
//
// What counts as "this coach hasn't told us their name". Both askers — the
// invite path in TeamSharingView and the join path in CoachNamePrompt — go
// through this one rule, and the device-name case is the load-bearing half:
// since iOS 16 `UIDevice.current.name` returns the model, so the default every
// team is seeded with is "iPhone" and looks like a real value.

final class CoachNamePlaceholderTests: XCTestCase {

    func testAnEmptyNameIsAPlaceholder() {
        XCTAssertTrue(LineupStore.isPlaceholderCoachName("", deviceName: "iPhone"))
    }

    func testWhitespaceOnlyIsAPlaceholder() {
        XCTAssertTrue(LineupStore.isPlaceholderCoachName("   ", deviceName: "iPhone"))
    }

    func testTheDeviceNameIsAPlaceholder() {
        XCTAssertTrue(LineupStore.isPlaceholderCoachName("iPhone", deviceName: "iPhone"))
    }

    func testTheDeviceNameIsAPlaceholderEvenWithWhitespace() {
        XCTAssertTrue(LineupStore.isPlaceholderCoachName("  iPhone  ", deviceName: "iPhone"))
    }

    func testARealNameIsNotAPlaceholder() {
        XCTAssertFalse(LineupStore.isPlaceholderCoachName("Nick", deviceName: "iPhone"))
    }

    func testACoachActuallyCalledAfterTheirDeviceIsComparedLive() {
        // An iPad-owning coach named "iPhone" is not a case worth designing for,
        // but a coach on a device whose name differs from the string they set is:
        // the comparison is against this device's name today, not a value frozen
        // at team creation, which is what lets the test repair old teams.
        XCTAssertFalse(LineupStore.isPlaceholderCoachName("iPhone", deviceName: "iPad"))
    }
}
