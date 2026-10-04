import XCTest
import PDFKit
@testable import Lineup_Builder

// Printouts are named "Team vs Opponent - Coaches Guide Oct 4" so a saved or
// printed file says which game it's for (the web pilot names them the same way).
@MainActor
final class PDFTitleTests: XCTestCase {
    private let oct4 = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 16))!

    func testTitleHasTeamOpponentKindAndDate() {
        XCTAssertEqual(PDFGenerator.title(type: .coachesGuide, teamName: "Wilsonville Fall Ball", opponent: "Lincoln 2", gameDate: oct4),
                       "Wilsonville Fall Ball vs Lincoln 2 - Coaches Guide Oct 4")
        XCTAssertEqual(PDFGenerator.title(type: .battingOrder, teamName: "Tigers", opponent: "  ", gameDate: oct4),
                       "Tigers - Batting Order Oct 4")
        XCTAssertEqual(PDFGenerator.title(type: .battingOrder, teamName: "", opponent: "", gameDate: oct4), "Batting Order Oct 4")
    }

    func testFilenameReplacesCharactersFilesCannotHold() {
        XCTAssertEqual(PDFGenerator.filename(title: "A/B: Team vs C? - Batting Order Oct 4"), "A-B- Team vs C- - Batting Order Oct 4.pdf")
    }

    func testGeneratedDocumentCarriesTheTitle() {
        let lineup = Lineup(gameDate: oct4, opponent: "Lincoln 2")
        let doc = PDFGenerator.generate(type: .coachesGuide, lineup: lineup, players: [], teamName: "Wilsonville Fall Ball")
        XCTAssertEqual(doc.title, "Wilsonville Fall Ball vs Lincoln 2 - Coaches Guide Oct 4")
        XCTAssertEqual(doc.filename, "Wilsonville Fall Ball vs Lincoln 2 - Coaches Guide Oct 4.pdf")
        let pdf = PDFKit.PDFDocument(data: doc.data)
        XCTAssertEqual(pdf?.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String, doc.title)
    }
}
