import XCTest
@testable import Lineup_Builder

// MARK: - TeamExporter / TeamImporter round-trip tests
//
// The `.stlteam` share format had NO automated coverage: a coach exports a team,
// sends the file, and it's re-imported by TeamImporter.parse. `gameLineups`
// ([UUID: Lineup]) and `updatedAt` were both added to `Team` AFTER the exporter and
// importer were last touched, and neither had ever been exercised on this path.
//
// These tests pin the contract end to end:
//   export(team:) -> Data -> parse(data:) -> ImportedTeam
// including the two things the exporter does ON PURPOSE (reset the active lineup,
// never persist isSharedParticipant) and the two failure modes the importer must
// report distinctly (unsupported version vs. invalid data).
//
// All fixture dates are whole seconds. TeamExporter encodes dates as .iso8601
// (`.withInternetDateTime`, no fractional seconds), so whole-second dates round-trip
// exactly and let us assert equality without an accuracy window.

// TeamExporter / TeamImporter default to MainActor isolation (the app target is
// MainActor-by-default and they aren't marked nonisolated), so the suite is
// @MainActor — same as TeamStorageTests.
@MainActor
final class TeamExportRoundTripTests: XCTestCase {

    // MARK: - Fixture

    /// Deterministic JSON encoder for comparing sub-structs that aren't Equatable
    /// (FairPlayConfig / PitchingConfig) by their encoded bytes.
    private func encoded<T: Encodable>(_ value: T) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return (try? encoder.encode(value)) ?? Data()
    }

    private func date(_ offset: TimeInterval) -> Date {
        // A fixed, whole-second base so every fixture date round-trips exactly.
        Date(timeIntervalSince1970: 1_700_000_000 + offset)
    }

    /// A team populated across every field the exporter is responsible for,
    /// deliberately including a non-empty `gameLineups` and a stamped `updatedAt`.
    private func makeRichTeam() -> Team {
        let p1 = Player(firstName: "Sam", lastName: "Rivera", number: "7", leagueAge: 11,
                        positionPreferences: [.pitcher: .strength, .shortstop: .capable])
        let p2 = Player(firstName: "Alex", lastName: "Chen", number: "12", leagueAge: 10)
        let p3 = Player(firstName: "Jordan", lastName: "Lee", number: "3", leagueAge: 11,
                        hittingArchetype: HittingArchetype(hitting: .power, speed: .fast, onBase: .high))

        // Two independent per-game lineups keyed by ScheduledGame.id — the
        // doubleheader stash. Distinct fields so we can tell them apart on decode.
        let gameA = UUID()
        let gameB = UUID()
        var lineupA = Lineup()
        lineupA.opponent = "Sharks"
        lineupA.gameDate = date(3_600)
        lineupA.status = .finalized
        lineupA.battingOrder = [p1.id, p2.id, p3.id]
        var lineupB = Lineup()
        lineupB.opponent = "Bandits"
        lineupB.gameDate = date(7_200)
        lineupB.status = .draft
        lineupB.battingOrder = [p3.id, p2.id, p1.id]

        // The active working lineup — the exporter must reset THIS to a fresh
        // Lineup(), so it must NOT appear in the imported copy.
        var activeLineup = Lineup()
        activeLineup.opponent = "SHOULD-NOT-EXPORT"
        activeLineup.status = .finalized
        activeLineup.battingOrder = [p1.id]

        var fairPlay = FairPlayConfig()
        fairPlay.noConsecutiveBench = false
        fairPlay.outfielderCount = 4
        fairPlay.minimumInfieldInnings = 2

        let template = LineupTemplate(name: "Starters",
                                      battingOrder: [p1.id, p2.id, p3.id],
                                      positionLocks: [],
                                      createdAt: date(100))

        let scheduled = ScheduledGame(icalUID: "evt-123", date: date(9_000),
                                      opponent: "Sharks", location: "Field 4",
                                      rawSummary: "vs Sharks @ Field 4")

        return Team(
            id: UUID(),
            name: "Wilsonville Fall Ball",
            colorHex: "FF8800",
            players: [p1, p2, p3],
            lineup: activeLineup,
            gameLogs: [],
            createdAt: date(0),
            gameInningCount: 6,
            scheduledGames: [scheduled],
            calendarSubscriptionURL: "webcal://example.com/cal.ics",
            fairPlayConfig: fairPlay,
            pitchingConfig: PitchingConfig(),
            coachName: "Coach Nick",
            ckRecordName: "team-record-abc",
            isReadOnly: false,
            isSharedParticipant: true,          // must NOT survive export
            lineupTemplates: [template],
            defaultTemplateID: template.id,
            gameLineups: [gameA: lineupA, gameB: lineupB],
            currentGameID: gameA,
            updatedAt: date(12_345)
        )
    }

    private func parseExported(_ team: Team,
                               file: StaticString = #filePath,
                               line: UInt = #line) throws -> TeamImporter.ImportedTeam {
        let data = try XCTUnwrap(TeamExporter.export(team: team),
                                 "export returned nil", file: file, line: line)
        switch TeamImporter.parse(data: data) {
        case .success(let imported):
            return imported
        case .failure(let error):
            XCTFail("expected success, got \(error)", file: file, line: line)
            throw error
        }
    }

    // MARK: - Round-trip

    func testScalarFieldsRoundTrip() throws {
        let original = makeRichTeam()
        let imported = try parseExported(original).team

        XCTAssertEqual(imported.id, original.id)
        XCTAssertEqual(imported.name, original.name)
        XCTAssertEqual(imported.colorHex, original.colorHex)
        XCTAssertEqual(imported.coachName, original.coachName)
        XCTAssertEqual(imported.gameInningCount, original.gameInningCount)
        XCTAssertEqual(imported.calendarSubscriptionURL, original.calendarSubscriptionURL)
        XCTAssertEqual(imported.ckRecordName, original.ckRecordName)
        XCTAssertEqual(imported.isReadOnly, original.isReadOnly)
        XCTAssertEqual(imported.createdAt, original.createdAt)
        XCTAssertEqual(imported.defaultTemplateID, original.defaultTemplateID)
        XCTAssertEqual(imported.currentGameID, original.currentGameID)
    }

    func testPlayersAndTemplatesRoundTrip() throws {
        let original = makeRichTeam()
        let imported = try parseExported(original).team

        // Player and LineupTemplate are Equatable — assert full equality.
        XCTAssertEqual(imported.players, original.players)
        XCTAssertEqual(imported.lineupTemplates, original.lineupTemplates)
    }

    func testConfigsRoundTrip() throws {
        let original = makeRichTeam()
        let imported = try parseExported(original).team

        // Compared by encoded bytes: these configs aren't Equatable.
        XCTAssertEqual(encoded(imported.fairPlayConfig), encoded(original.fairPlayConfig))
        XCTAssertEqual(encoded(imported.pitchingConfig), encoded(original.pitchingConfig))
    }

    func testScheduledGamesRoundTrip() throws {
        let original = makeRichTeam()
        let imported = try parseExported(original).team

        XCTAssertEqual(imported.scheduledGames.count, 1)
        let g = try XCTUnwrap(imported.scheduledGames.first)
        let o = try XCTUnwrap(original.scheduledGames.first)
        XCTAssertEqual(g.id, o.id)
        XCTAssertEqual(g.icalUID, o.icalUID)
        XCTAssertEqual(g.date, o.date)
        XCTAssertEqual(g.opponent, o.opponent)
        XCTAssertEqual(g.location, o.location)
    }

    /// The regression this suite exists for: `gameLineups` ([UUID: Lineup]) was
    /// never exercised on the export path.
    func testGameLineupsStashRoundTrips() throws {
        let original = makeRichTeam()
        let imported = try parseExported(original).team

        XCTAssertEqual(Set(imported.gameLineups.keys), Set(original.gameLineups.keys),
                       "per-game lineup keys must survive export")

        for (key, expected) in original.gameLineups {
            let actual = try XCTUnwrap(imported.gameLineups[key],
                                       "missing lineup for game \(key)")
            XCTAssertEqual(actual.opponent, expected.opponent)
            XCTAssertEqual(actual.gameDate, expected.gameDate)
            XCTAssertEqual(actual.status, expected.status)
            XCTAssertEqual(actual.battingOrder, expected.battingOrder)
        }
    }

    /// The other field added after the exporter was written.
    func testUpdatedAtRoundTrips() throws {
        let original = makeRichTeam()
        let imported = try parseExported(original).team
        XCTAssertEqual(imported.updatedAt, original.updatedAt)
    }

    // MARK: - Deliberate exporter behavior

    func testActiveLineupIsResetOnExport() throws {
        let original = makeRichTeam()
        let imported = try parseExported(original).team

        // Exporter replaces the working lineup with a fresh Lineup() so the recipient
        // starts clean. The populated active lineup must not leak.
        XCTAssertEqual(imported.lineup.opponent, "")
        XCTAssertEqual(imported.lineup.status, .draft)
        XCTAssertTrue(imported.lineup.battingOrder.isEmpty)
        XCTAssertNotEqual(imported.lineup.opponent, "SHOULD-NOT-EXPORT")
    }

    func testIsSharedParticipantNeverPersists() throws {
        let original = makeRichTeam()   // set to true in the fixture
        let imported = try parseExported(original).team
        XCTAssertFalse(imported.isSharedParticipant,
                       "isSharedParticipant is re-derived from the fetch path, never from the blob")
    }

    // MARK: - Importer metadata

    func testImportedMetadata() throws {
        let original = makeRichTeam()
        let imported = try parseExported(original)

        XCTAssertEqual(imported.playerCount, 3)
        XCTAssertEqual(imported.gameCount, original.gameLogs.count)
        XCTAssertFalse((imported.appVersion).isEmpty)
        // exportedAt is stamped at export time — within a minute of now.
        XCTAssertLessThan(abs(imported.exportedAt.timeIntervalSinceNow), 60)
    }

    // MARK: - Failure modes

    func testUnsupportedVersionIsReportedDistinctly() {
        let envelope = """
        {"version": 2, "exportedAt": "2026-09-19T12:00:00Z", "appVersion": "9.9", "team": {}}
        """.data(using: .utf8)!

        switch TeamImporter.parse(data: envelope) {
        case .success:
            XCTFail("a v2 file must not import on a v1 reader")
        case .failure(let error):
            guard case .unsupportedVersion(let v) = error else {
                return XCTFail("expected .unsupportedVersion, got \(error)")
            }
            XCTAssertEqual(v, 2)
        }
    }

    func testGarbageDataIsInvalid() {
        switch TeamImporter.parse(data: Data("not a team file".utf8)) {
        case .success:
            XCTFail("arbitrary bytes must not import")
        case .failure(let error):
            guard case .invalidData = error else {
                return XCTFail("expected .invalidData, got \(error)")
            }
        }
    }

    /// An empty `team: {}` still decodes because Team's decoder is fully tolerant;
    /// the envelope only fails when a top-level required key is missing/wrong-typed.
    func testMissingTopLevelKeyIsInvalid() {
        let noVersion = """
        {"exportedAt": "2026-09-19T12:00:00Z", "appVersion": "3.5", "team": {}}
        """.data(using: .utf8)!

        switch TeamImporter.parse(data: noVersion) {
        case .success:
            XCTFail("envelope without a version must not import")
        case .failure(let error):
            guard case .invalidData = error else {
                return XCTFail("expected .invalidData, got \(error)")
            }
        }
    }
}
