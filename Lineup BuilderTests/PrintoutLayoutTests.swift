import XCTest
import PDFKit
@testable import Lineup_Builder

// The v3 printouts (PDFGenerator): the handoff's sample game fits one page
// each, the bundled Barlow faces are what's embedded, and the pitch status
// rule. To look at the pages, run with TEST_RUNNER_PRINTOUT_DIR=<folder> and
// the PDFs are written there.
@MainActor
final class PrintoutLayoutTests: XCTestCase {
    private let oct4 = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 10))!

    /// The handoff mock: Wilsonville Fall Ball vs. Lincoln 2, 16 players, 6 innings.
    private func sampleGame() -> (Lineup, [Player], [GameLog], PitchingConfig) {
        let names = [
            ("Remi", "Traughber"), ("Deacon", "Stoeklen"), ("Andrew", "Swan"), ("Caleb", "Van Vleet"),
            ("Lex", "Wisehart"), ("Caleb", "Johnston"), ("Noah", "Davies"), ("Nolan", "Robinson"),
            ("George", "Holman"), ("Archer", "Joslin"), ("Scyllice", "Nikolaisen"), ("Ian", "Nehez"),
            ("Noah", "Edwards"), ("Theo", "Traeger"), ("Cam", "White"), ("Tanner", "Davenport"),
        ]
        let players = names.enumerated().map { i, n in
            Player(firstName: n.0, lastName: n.1, number: i % 3 == 0 ? "" : "\(i + 2)", leagueAge: i % 2 == 0 ? 11 : 9)
        }
        var lineup = Lineup(gameDate: oct4, opponent: "Lincoln 2")
        lineup.battingOrder = players.map(\.id)
        lineup.innings = Array(repeating: InningAssignment(), count: 6)
        let nine: [FieldPosition] = [.pitcher, .catcher, .firstBase, .secondBase, .shortstop, .thirdBase,
                                     .leftField, .centerField, .rightField]
        for i in 0..<6 {
            for (k, pos) in nine.enumerated() { lineup.innings[i].assign(player: players[(i * 5 + k) % 16], position: pos) }
        }

        var config = PitchingConfig()
        config.rulesEnabled = true
        config.applyLittleLeaguePreset()
        config.weeklyLimitEnabled = true
        config.weeklyLimit = 110
        // A spread of statuses: some threw days ago (near the weekly limit), two yesterday (resting).
        let thrown: [(Int, Int, Int)] = [(15, 85, 4), (3, 80, 5), (1, 12, 6), (12, 20, 6), (2, 66, 1), (0, 41, 1)]
        let logs = thrown.map { idx, pitches, daysAgo in
            GameLog(gameDate: Calendar.current.date(byAdding: .day, value: -daysAgo, to: oct4)!, opponent: "Eagles",
                    inningsPlayed: 6, battingOrder: [players[idx].id], innings: Array(repeating: InningAssignment(), count: 7),
                    playerSnapshot: [PlayerSnapshot(from: players[idx])], pitchCounts: [players[idx].id.uuidString: pitches])
        }
        return (lineup, players, logs, config)
    }

    private func render(_ type: PDFType) -> PDFKit.PDFDocument {
        let (lineup, players, logs, config) = sampleGame()
        let doc = PDFGenerator.generate(type: type, lineup: lineup, players: players, teamName: "Wilsonville Fall Ball",
                                        gameLogs: logs, pitchingConfig: config)
        if let dir = ProcessInfo.processInfo.environment["PRINTOUT_DIR"] {
            try? doc.data.write(to: URL(fileURLWithPath: dir).appendingPathComponent(type == .battingOrder ? "batting-order.pdf" : "coaches-guide.pdf"))
        }
        return PDFKit.PDFDocument(data: doc.data)!
    }

    func testSampleGameFitsOnePageEach() {
        XCTAssertEqual(render(.coachesGuide).pageCount, 1)
        XCTAssertEqual(render(.battingOrder).pageCount, 1)
    }

    func testPrintoutsAreSetInBundledBarlow() throws {
        let page = try XCTUnwrap(render(.coachesGuide).page(at: 0)?.dataRepresentation)
        let raw = String(decoding: page, as: UTF8.self)
        XCTAssertTrue(raw.contains("BarlowCondensed-Bold"), "headline face not embedded")
        XCTAssertTrue(raw.contains("Barlow-SemiBold"), "body face not embedded")
    }

    func testHeaderNamesTheMatchupAndThePrintout() throws {
        // Letter-spaced labels extract with gaps ("C O AC H E S"), so compare without spaces.
        func squeezed(_ type: PDFType) throws -> String { try XCTUnwrap(render(type).string).filter { !$0.isWhitespace } }
        let guide = try squeezed(.coachesGuide)
        XCTAssertTrue(guide.contains("WILSONVILLEFALLBALLVS.LINCOLN2"), guide)
        XCTAssertTrue(guide.contains("COACHESGUIDE"), guide)
        XCTAssertTrue(try squeezed(.battingOrder).contains("BATTINGORDER"))
    }

    func testPitchStatusRule() {
        let p = Player(firstName: "A", lastName: "B", number: "")
        func row(_ available: Int, _ status: PitchEligibilityStatus) -> PitchingGuideSummaryRow {
            PitchingGuideSummaryRow(player: p, pitchesInWindow: 0, dailyMax: 85, available: available, restDaysRequired: 0, status: status)
        }
        XCTAssertEqual(PDFGenerator.PitchStatus(row(31, .eligible)), .eligible)
        XCTAssertEqual(PDFGenerator.PitchStatus(row(30, .eligible)), .nearLimit)
        XCTAssertEqual(PDFGenerator.PitchStatus(row(25, .limited(remaining: 25))), .nearLimit)
        XCTAssertEqual(PDFGenerator.PitchStatus(row(0, .mustRest(until: oct4))), .restNeeded)
        XCTAssertEqual(PDFGenerator.PitchStatus(row(0, .unknownAge)), .ageNotSet)
    }
}
