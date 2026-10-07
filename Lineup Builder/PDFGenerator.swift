import UIKit
import PDFKit
import SwiftUI
import CoreText
import os

// MARK: - PDF Generator
//
// The Batting Order and Coaches Guide printouts, from the v3 Coaches Guide
// redesign handoff: the matchup as the headline, a dark inning bar, zebra
// rows, one comma-separated bench line per inning, and pitch counts with a bar
// and a status shape (circle, triangle, square) so the statuses still read on
// a black-and-white printer. US Letter, 612 x 792 pt; the handoff's px values
// are x0.75.
//
// Set in Barlow and Barlow Condensed, bundled in Fonts/ (SIL OFL) so the web
// pilot (web/src/print/lineupPdf.ts), which draws the same pages, prints the
// same glyphs. Every face turns on tabular figures.

class PDFGenerator {
    /// Nonisolated to avoid the iOS 26.0-26.3 isolated-deinit crash; see
    /// AutoFillNLConstraintService's deinit.
    nonisolated deinit {}

    /// `teamColor` is no longer drawn (the redesigned header is black and
    /// white); it stays so callers don't change.
    static func generate(
        type: PDFType,
        lineup: Lineup,
        players: [Player],
        teamName: String = "",
        teamColor: Color = .blue,
        gameLogs: [GameLog] = [],
        pitchingConfig: PitchingConfig = PitchingConfig(),
        fairPlayConfig: FairPlayConfig = FairPlayConfig()
    ) -> PDFDocument {
        let title = Self.title(type: type, teamName: teamName, opponent: lineup.opponent, gameDate: lineup.gameDate)
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String: title, kCGPDFContextCreator as String: "Stack the Lineup"]
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: Page.width, height: Page.height), format: format)
        let generatedAt = Date()

        let data = renderer.pdfData { ctx in
            switch type {
            case .battingOrder:
                drawBattingOrder(ctx: ctx, lineup: lineup, players: players, teamName: teamName, generatedAt: generatedAt)
            case .coachesGuide:
                drawCoachesGuide(ctx: ctx, lineup: lineup, players: players, teamName: teamName,
                                 gameLogs: gameLogs, pitchingConfig: pitchingConfig,
                                 fairPlayConfig: fairPlayConfig, generatedAt: generatedAt)
            }
        }

        return PDFDocument(data: data, title: title, filename: filename(title: title))
    }

    /// "Wilsonville Fall Ball vs Lincoln 2 - Coaches Guide Oct 4", or without an
    /// opponent "Wilsonville Fall Ball - Coaches Guide Oct 4". The PDF's title,
    /// the preview's title, and (as a filename) what Share and Print save it as.
    /// The web names its printouts the same way (pdfTitle in lineupPdf.ts).
    static func title(type: PDFType, teamName: String, opponent: String, gameDate: Date) -> String {
        let team = teamName.trimmingCharacters(in: .whitespacesAndNewlines)
        let opp = opponent.trimmingCharacters(in: .whitespacesAndNewlines)
        let lead = [team, opp.isEmpty ? "" : "vs \(opp)"].filter { !$0.isEmpty }.joined(separator: " ")
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        let doc = "\(type == .battingOrder ? "Batting Order" : "Coaches Guide") \(formatter.string(from: gameDate))"
        return lead.isEmpty ? doc : "\(lead) - \(doc)"
    }

    /// The title as a filename: characters files can't hold become "-", plus ".pdf".
    static func filename(title: String) -> String {
        let unsafe = CharacterSet(charactersIn: "\\/:*?\"<>|").union(.newlines)
        let cleaned = title.unicodeScalars.map { unsafe.contains($0) ? "-" : String($0) }.joined()
        return cleaned.split(whereSeparator: \.isWhitespace).joined(separator: " ") + ".pdf"
    }

    // MARK: - Pitch status

    /// A pitcher with this many pitches or fewer left today is "Near limit".
    static let nearLimitPitches = 30

    /// The pitch-count table's status for a summary row. The web uses the same rule (pitchStatus in lineupPdf.ts).
    enum PitchStatus: Equatable {
        case eligible, nearLimit, restNeeded, ageNotSet

        init(_ row: PitchingGuideSummaryRow) {
            switch row.status {
            case .unknownAge: self = .ageNotSet
            case .mustRest: self = .restNeeded
            case .eligible, .limited: self = row.available <= PDFGenerator.nearLimitPitches ? .nearLimit : .eligible
            }
        }

        var label: String {
            switch self {
            case .eligible: "Eligible"
            case .nearLimit: "Near limit"
            case .restNeeded: "Rest needed"
            case .ageNotSet: "Age not set"
            }
        }
    }

    // MARK: - Page and tokens

    private enum Page {
        static let width: CGFloat = 612
        static let height: CGFloat = 792
        static let top: CGFloat = 33
        static let side: CGFloat = 36
        static let bottom: CGFloat = 24
        static let left = side
        static let right = width - side
        static let contentWidth = width - side * 2
        static let footerTextTop = height - bottom - 7.5 * lineFactor
        static let footerRule = footerTextTop - 7.5
        /// Lowest y page content may reach, leaving room above the footer rule.
        static let contentBottom = footerRule - 12
    }

    /// Line box height as a fraction of font size (CSS "normal" for Barlow: ascent 1.0 + descent 0.2).
    private static let lineFactor: CGFloat = 1.2

    private enum Ink {
        static let black = UIColor.black
        static let white = UIColor.white
        static let blue = hex(0x007AFF)
        static let bar = hex(0x1C1C1E)
        static let grouped = hex(0xF2F2F7)
        static let separator = hex(0xC6C6C8)
        static let hairline = hex(0xE5E5EA)
        static let infield = hex(0x0A4FA8)
        static let outfield = hex(0x1E6B34)
        static let bench = hex(0x3A3A3C)
        /// rgba(60,60,67,a)
        static func secondary(_ a: CGFloat) -> UIColor { UIColor(red: 60 / 255, green: 60 / 255, blue: 67 / 255, alpha: a) }
        static func hex(_ v: UInt32) -> UIColor {
            UIColor(red: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
        }

        /// (shape, text) colors per status.
        static func status(_ s: PitchStatus) -> (shape: UIColor, text: UIColor) {
            switch s {
            case .eligible: (hex(0x34C759), hex(0x248A3D))
            case .nearLimit: (hex(0xFF9500), hex(0xC93400))
            case .restNeeded: (hex(0xFF3B30), hex(0xD70015))
            case .ageNotSet: (secondary(0.5), secondary(0.75))
            }
        }

        static func barFill(_ s: PitchStatus) -> UIColor {
            switch s {
            case .eligible, .ageNotSet: hex(0x8E8E93)
            case .nearLimit: hex(0xFF9500)
            case .restNeeded: hex(0xFF3B30)
            }
        }
    }

    // MARK: - Fonts

    private enum Face: String, CaseIterable {
        case regular = "Barlow-Regular"
        case medium = "Barlow-Medium"
        case semibold = "Barlow-SemiBold"
        case bold = "Barlow-Bold"
        case condensed = "BarlowCondensed-Bold"

        var fallbackWeight: UIFont.Weight {
            switch self {
            case .regular: .regular
            case .medium: .medium
            case .semibold: .semibold
            case .bold: .bold
            case .condensed: .heavy
            }
        }
    }

    /// Registers the bundled faces with this process, once. A face that won't
    /// load is logged and drawn in the system font instead; the export never fails over it.
    private static let fontsRegistered: Void = {
        for face in Face.allCases where UIFont(name: face.rawValue, size: 12) == nil {
            guard let url = Bundle.main.url(forResource: face.rawValue, withExtension: "ttf")
                    ?? Bundle.main.url(forResource: face.rawValue, withExtension: "ttf", subdirectory: "Fonts") else {
                Log.printouts.warning("Printout font \(face.rawValue, privacy: .public) is not in the bundle; using the system font")
                continue
            }
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                let reason = error?.takeRetainedValue().localizedDescription ?? "unknown error"
                Log.printouts.warning("Printout font \(face.rawValue, privacy: .public) failed to register: \(reason, privacy: .public)")
            }
        }
    }()

    private static func font(_ face: Face, _ size: CGFloat) -> UIFont {
        _ = fontsRegistered
        let base = UIFont(name: face.rawValue, size: size) ?? .systemFont(ofSize: size, weight: face.fallbackWeight)
        let tabular = base.fontDescriptor.addingAttributes([.featureSettings: [[
            UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
            UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector,
        ]]])
        return UIFont(descriptor: tabular, size: size)
    }

    // MARK: - Batting Order PDF

    private static func drawBattingOrder(ctx: UIGraphicsPDFRendererContext, lineup: Lineup, players: [Player],
                                         teamName: String, generatedAt: Date) {
        ctx.beginPage()
        let ordered = lineup.orderedPlayers(from: players)

        let numW: CGFloat = 48
        let jerseyW: CGFloat = 72
        let left = Page.left
        let playerX = left + numW
        let jerseyX = Page.right - jerseyW
        let headH: CGFloat = 6 * 2 + 11.25 * lineFactor
        let countH: CGFloat = 7.5 + 9 * lineFactor

        var top = drawHeader(eyebrow: "Batting Order", lineup: lineup, teamName: teamName) + 15
        // Rows shrink from 33 to 24 to fit; past that the list continues on another page.
        let room = Page.contentBottom - top - headH - countH
        let rowH = max(24, min(33, room / CGFloat(max(1, ordered.count))))
        let nameSize: CGFloat = rowH < 27 ? 12 : 13.5

        func table(_ rows: ArraySlice<Player>) {
            let h = headH + CGFloat(rows.count) * rowH
            let box = CGRect(x: left, y: top, width: Page.contentWidth, height: h)
            clipped(to: box) {
                fill(CGRect(x: left, y: top, width: Page.contentWidth, height: headH), Ink.bar)
                for (k, i) in rows.indices.enumerated() where i % 2 == 1 {
                    fill(CGRect(x: left, y: top + headH + CGFloat(k) * rowH, width: Page.contentWidth, height: rowH), Ink.grouped)
                }
                vLine(x: playerX, from: top + headH, to: top + h, Ink.hairline, 0.75)
                vLine(x: jerseyX, from: top + headH, to: top + h, Ink.hairline, 0.75)
            }
            text("#", x: left + numW / 2, top: top, height: headH, size: 11.25, face: .condensed, color: Ink.white,
                 tracking: 0.06, align: .center)
            text("PLAYER", x: playerX + 10.5, top: top, height: headH, size: 11.25, face: .condensed, color: Ink.white, tracking: 0.06)
            text("JERSEY", x: jerseyX + jerseyW / 2, top: top, height: headH, size: 11.25, face: .condensed, color: Ink.white,
                 tracking: 0.06, align: .center)
            for (k, i) in rows.indices.enumerated() {
                let player = rows[i]
                let y = top + headH + CGFloat(k) * rowH
                text("\(i + 1)", x: left + numW / 2, top: y, height: rowH, size: 18, face: .condensed, color: Ink.black,
                     align: .center)
                text(player.displayName, x: playerX + 10.5, top: y, height: rowH, size: nameSize, face: .semibold,
                     color: Ink.black, maxWidth: jerseyX - playerX - 21)
                // No number: left blank for the coach to write in.
                if !player.number.isEmpty {
                    text(player.number, x: jerseyX + jerseyW / 2, top: y, height: rowH, size: 12.75, face: .bold,
                         color: Ink.black, align: .center, maxWidth: jerseyW - 12)
                }
            }
            strokeRounded(box, radius: 6, Ink.separator, 0.75)
            top += h
        }

        var i = 0
        repeat {
            let fits = max(1, Int((Page.contentBottom - top - headH - countH) / rowH))
            let end = min(ordered.count, i + fits)
            table(ordered[i..<end])
            i = end
            if i < ordered.count {
                drawFooter(generatedAt: generatedAt)
                ctx.beginPage()
                top = Page.top
            }
        } while i < ordered.count

        text("\(ordered.count) \(ordered.count == 1 ? "player" : "players")", x: left, top: top + 7.5,
             size: 9, face: .regular, color: Ink.secondary(0.75))
        drawFooter(generatedAt: generatedAt)
    }

    // MARK: - Coaches Guide PDF

    private static let gridHeadH: CGFloat = max(5.25 * 2 + 7.1 * lineFactor, 4.5 * 2 + 15.75 * lineFactor)
    private static let positionColumn: CGFloat = 42
    /// The rule between the infield and outfield rows, and the bench's top rule.
    private static let gridRule: CGFloat = 1.125
    private static let benchLine: CGFloat = 8.25 * 1.4
    private static let pitchTitleH: CGFloat = 15.75 * lineFactor
    private static let pitchHeadH: CGFloat = 7.1 * lineFactor + 3.75 + 1.125

    private static func drawCoachesGuide(
        ctx: UIGraphicsPDFRendererContext,
        lineup: Lineup,
        players: [Player],
        teamName: String,
        gameLogs: [GameLog],
        pitchingConfig: PitchingConfig,
        fairPlayConfig: FairPlayConfig,
        generatedAt: Date
    ) {
        ctx.beginPage()
        var top = drawHeader(eyebrow: "Coaches Guide", lineup: lineup, teamName: teamName) + 13.5

        // By position: a row per field position, then Bench; each cell names who is there that inning.
        let positions = lineup.activeFieldPositions(config: fairPlayConfig)
        let active = lineup.activePlayers(from: players)
        let orderedPlayers = lineup.orderedPlayers(from: players)
        let sitOrder = orderedPlayers + active.filter { p in !orderedPlayers.contains(where: { $0.id == p.id }) }
        // First name, or "Caleb J." when two active players share one (as on the field view).
        var firstNameCounts: [String: Int] = [:]
        for p in active { firstNameCounts[p.firstName, default: 0] += 1 }
        let name: (Player) -> String = { p in (firstNameCounts[p.firstName] ?? 0) > 1 ? p.shortName : p.firstName }

        let innings = max(1, lineup.innings.count)
        let colW = (Page.contentWidth - positionColumn) / CGFloat(innings)
        // Bench: everyone with no field spot that inning, in batting order, as one comma-separated list.
        let benchLines: [[String]] = lineup.innings.map { inning in
            let names = sitOrder.filter { p in
                let pos = inning.position(for: p)
                return pos == nil || pos == .bench
            }.map(name)
            return commaLines(names, maxWidth: colW - 12, face: .regular, size: 8.25)
        }
        let mostLines = benchLines.map(\.count).max() ?? 0
        let benchH = gridRule + max(6 * 2 + CGFloat(mostLines) * benchLine, 6 * 2 + 9.75 * lineFactor)

        // Pitch counts, scoped to lineup.gameDate rather than today so the
        // numbers match what the coach sees in the Pitching tab for this game.
        // Hidden when no one can pitch.
        let pitchRows = PitchEligibilityEngine.coachesGuideSummary(
            gameLogs: gameLogs,
            players: players,
            config: pitchingConfig,
            referenceDate: lineup.gameDate
        ) ?? []

        // Overflow, per the handoff: shorten the pitch rows, then the grid rows; then move pitch counts to page 2.
        let hasDivider = (positions.firstIndex(where: { $0.isOutfield }) ?? 0) > 0
        func gridHeight(_ row: CGFloat) -> CGFloat {
            gridHeadH + CGFloat(positions.count) * row + (hasDivider ? gridRule : 0) + benchH
        }
        func pitchHeight(_ row: CGFloat) -> CGFloat {
            pitchRows.isEmpty ? 0 : 18 + pitchTitleH + 6 + pitchHeadH + CGFloat((pitchRows.count + 1) / 2) * row
        }
        let room = Page.contentBottom - top
        var gridRow: CGFloat = 24.75
        var pitchRow: CGFloat = 19.5
        if gridHeight(gridRow) + pitchHeight(pitchRow) > room { pitchRow = 16.5 }
        if gridHeight(gridRow) + pitchHeight(pitchRow) > room { gridRow = 22.5 }

        top = drawDefenseGrid(
            top: top, lineup: lineup, positions: positions, active: active, benchLines: benchLines,
            benchHeight: benchH, rowH: gridRow, name: name
        )

        if !pitchRows.isEmpty {
            if top + pitchHeight(pitchRow) > Page.contentBottom {
                drawFooter(generatedAt: generatedAt)
                ctx.beginPage()
                top = Page.top - 18
            }
            drawPitchCounts(rows: pitchRows, top: top + 18, rowH: pitchRow)
        }

        drawFooter(generatedAt: generatedAt)
    }

    private static func drawDefenseGrid(
        top: CGFloat, lineup: Lineup, positions: [FieldPosition], active: [Player], benchLines: [[String]],
        benchHeight: CGFloat, rowH: CGFloat, name: (Player) -> String
    ) -> CGFloat {
        let left = Page.left
        let innings = lineup.innings.count
        let colW = (Page.contentWidth - positionColumn) / CGFloat(max(1, innings))
        func colX(_ i: Int) -> CGFloat { left + positionColumn + CGFloat(i) * colW }
        let nameSize: CGFloat = innings >= 7 ? 9.75 : 10.5
        let rowsTop = top + gridHeadH
        let firstOutfield = positions.firstIndex(where: { $0.isOutfield }).flatMap { $0 > 0 ? $0 : nil }
        func rowTop(_ r: Int) -> CGFloat {
            rowsTop + CGFloat(r) * rowH + (firstOutfield.map { r >= $0 } == true ? gridRule : 0)
        }
        let benchTop = rowTop(positions.count)
        let bottom = benchTop + benchHeight
        let box = CGRect(x: left, y: top, width: Page.contentWidth, height: bottom - top)

        clipped(to: box) {
            fill(CGRect(x: left, y: top, width: Page.contentWidth, height: gridHeadH), Ink.bar)
            for r in positions.indices where r % 2 == 1 {
                fill(CGRect(x: left, y: rowTop(r), width: Page.contentWidth, height: rowH), Ink.grouped)
            }
            for i in 0..<innings { vLine(x: colX(i), from: rowsTop, to: bottom, Ink.hairline, 0.75) }
            if let firstOutfield {
                fill(CGRect(x: left, y: rowTop(firstOutfield) - gridRule, width: Page.contentWidth, height: gridRule), Ink.separator)
            }
            fill(CGRect(x: left, y: benchTop, width: Page.contentWidth, height: gridRule), Ink.black)
        }

        // Header bar: just the inning numbers.
        text("INN", x: left + 7.5, top: top, height: gridHeadH, size: 7.1, face: .bold, color: Ink.white, tracking: 0.08)
        for i in 0..<innings {
            text("\(i + 1)", x: colX(i) + colW / 2, top: top, height: gridHeadH, size: 15.75, face: .condensed,
                 color: Ink.white, align: .center)
        }

        // Position rows: the label, then who plays there each inning.
        for (r, position) in positions.enumerated() {
            let y = rowTop(r)
            text(position.rawValue, x: left + 7.5, top: y, height: rowH, size: 9.75, face: .bold,
                 color: position.isOutfield ? Ink.outfield : Ink.infield)
            for i in 0..<innings {
                if let player = lineup.innings[i].player(at: position, in: active) {
                    text(name(player), x: colX(i) + colW / 2, top: y, height: rowH, size: nameSize, face: .semibold,
                         color: Ink.black, tracking: -0.01, align: .center, maxWidth: colW - 9)
                } else {
                    text("—", x: colX(i) + colW / 2, top: y, height: rowH, size: nameSize, face: .regular,
                         color: Ink.secondary(0.6), align: .center)
                }
            }
        }

        // Bench.
        let benchTextTop = benchTop + gridRule + 6
        text("BN", x: left + 7.5, top: benchTextTop, size: 9.75, face: .bold, color: Ink.bench)
        for (i, lines) in benchLines.enumerated() {
            for (k, line) in lines.enumerated() {
                text(line, x: colX(i) + colW / 2, top: benchTextTop + CGFloat(k) * benchLine, height: benchLine,
                     size: 8.25, face: .regular, color: Ink.secondary(0.75), align: .center, maxWidth: colW - 12)
            }
        }

        strokeRounded(box, radius: 6, Ink.separator, 0.75)
        return bottom
    }

    /// "Pitch counts" title, then two tables side by side (first half, rounded up, on the left).
    /// Rows arrive sorted: who can throw, most pitches available first, then those who must rest.
    private static func drawPitchCounts(rows: [PitchingGuideSummaryRow], top: CGFloat, rowH: CGFloat) {
        let left = Page.left
        text("PITCH COUNTS", x: left, top: top, size: 15.75, face: .condensed, color: Ink.black)

        let gap: CGFloat = 18
        let tableW = (Page.contentWidth - gap) / 2
        let half = (rows.count + 1) / 2
        let tablesTop = top + pitchTitleH + 6

        func table(x: CGFloat, list: ArraySlice<PitchingGuideSummaryRow>) {
            // Player (flexible) | Thrown / Max 69 | Rest 19.5 | Status 60, 4.5 apart, inset 4.5.
            let statusX = x + tableW - 4.5 - 60
            let restR = statusX - 4.5
            let thrownX = restR - 19.5 - 4.5 - 69
            let playerX = x + 4.5
            let barW: CGFloat = 69 - 4.5 - 28.5

            let head = Ink.secondary(0.75)
            text("PLAYER", x: playerX, top: tablesTop, size: 7.1, face: .bold, color: head, tracking: 0.08)
            text("THROWN / MAX", x: thrownX, top: tablesTop, size: 7.1, face: .bold, color: head, tracking: 0.08)
            text("REST", x: restR, top: tablesTop, size: 7.1, face: .bold, color: head, tracking: 0.08, align: .right)
            text("STATUS", x: statusX, top: tablesTop, size: 7.1, face: .bold, color: head, tracking: 0.08)
            fill(CGRect(x: x, y: tablesTop + 7.1 * lineFactor + 3.75, width: tableW, height: 1.125), Ink.black)

            for (k, row) in list.enumerated() {
                let y = tablesTop + pitchHeadH + CGFloat(k) * rowH
                let mid = y + rowH / 2
                let status = PitchStatus(row)
                let resting = status == .restNeeded || status == .ageNotSet
                if k % 2 == 1 { fill(CGRect(x: x, y: y, width: tableW, height: rowH), Ink.grouped) }

                text(row.player.displayName, x: playerX, top: y, height: rowH, size: 9.4, face: .semibold,
                     color: resting ? Ink.secondary(0.6) : Ink.black, maxWidth: thrownX - 4.5 - playerX)

                // Thrown / max: a bar (full for Rest needed), then "50 / 75".
                let bar = CGRect(x: thrownX, y: mid - 5.25 / 2, width: barW, height: 5.25)
                fillRounded(bar, radius: 1.5, Ink.white)
                let share: CGFloat = switch status {
                case .restNeeded: 1
                case .ageNotSet: 0
                default: row.dailyMax > 0 ? min(1, CGFloat(row.pitchesInWindow) / CGFloat(row.dailyMax)) : 0
                }
                if share > 0 {
                    clipped(to: bar, radius: 1.5) {
                        fill(CGRect(x: bar.minX, y: bar.minY, width: bar.width * share, height: bar.height), Ink.barFill(status))
                    }
                }
                strokeRounded(bar.insetBy(dx: 0.375, dy: 0.375), radius: 1.5 - 0.375, Ink.separator, 0.75)
                text("\(row.pitchesInWindow) / \(row.dailyMax)", x: thrownX + 69, top: y, height: rowH, size: 7.9,
                     face: .regular, color: Ink.secondary(0.85), align: .right)

                // Rest owed is only meaningful while they're still inside it; 0 otherwise (no dashes).
                text("\(status == .restNeeded ? row.restDaysRequired : 0)", x: restR, top: y, height: rowH, size: 9.4,
                     face: .regular, color: Ink.secondary(0.75), align: .right)

                let colors = Ink.status(status)
                let shapeW = drawStatusShape(status, x: statusX, midY: mid, color: colors.shape)
                text(status.label, x: statusX + shapeW + 4.5, top: y, height: rowH, size: 8.25, face: .bold,
                     color: colors.text, maxWidth: 60 - shapeW - 4.5)
            }
        }

        table(x: left, list: rows[0..<half])
        table(x: left + tableW + gap, list: rows[half...])
    }

    /// Circle (eligible), upward triangle (near limit), or square (rest needed). Returns its width.
    private static func drawStatusShape(_ status: PitchStatus, x: CGFloat, midY: CGFloat, color: UIColor) -> CGFloat {
        color.setFill()
        switch status {
        case .eligible:
            UIBezierPath(ovalIn: CGRect(x: x, y: midY - 3, width: 6, height: 6)).fill()
            return 6
        case .nearLimit:
            let path = UIBezierPath()
            path.move(to: CGPoint(x: x + 3.75, y: midY - 3.375))
            path.addLine(to: CGPoint(x: x + 7.5, y: midY + 3.375))
            path.addLine(to: CGPoint(x: x, y: midY + 3.375))
            path.close()
            path.fill()
            return 7.5
        case .restNeeded, .ageNotSet:
            UIBezierPath(rect: CGRect(x: x, y: midY - 3, width: 6, height: 6)).fill()
            return 6
        }
    }

    // MARK: - Shared header and footer

    /// One word of the matchup headline.
    private struct Word {
        let text: String
        let size: CGFloat
        let color: UIColor
    }

    /// The matchup ("WILSONVILLE FALL BALL vs. LINCOLN 2") on the left; the
    /// eyebrow and date on the right; both bottom-aligned over a 1.5 pt black
    /// rule. Returns the rule's bottom.
    private static func drawHeader(eyebrow: String, lineup: Lineup, teamName: String) -> CGFloat {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEMMMdyyyy")
        let date = formatter.string(from: lineup.gameDate)
        let eyebrowText = eyebrow.uppercased()
        let eyebrowW = width(eyebrowText, .bold, 8.25, tracking: 0.12) - 0.12 * 8.25
        let rightW = max(eyebrowW, width(date, .semibold, 9.75))
        let rightH = 8.25 * lineFactor + 1.5 + 9.75 * lineFactor + 2.25

        let maxW = Page.contentWidth - rightW - 18
        let (lines, scale) = layoutMatchup(matchupWords(team: teamName, opponent: lineup.opponent), maxWidth: maxW)
        let lineH = 30 * scale * 1.1
        let leftH = CGFloat(lines.count) * lineH
        let bottom = Page.top + max(leftH, rightH)

        for (n, line) in lines.enumerated() {
            // The 1.1 line box is tighter than the font's 1.2; its baseline sits 0.95 em down.
            let baseline = bottom - leftH + CGFloat(n) * lineH + 0.95 * 30 * scale
            var x = Page.left
            for (k, i) in line.indices.enumerated() {
                let word = line[i]
                if k > 0 { x += width(" ", .condensed, min(line[i - 1].size, word.size) * scale) }
                let f = font(.condensed, word.size * scale)
                let attrs: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: word.color]
                let t = fit(word.text, attrs: attrs, maxWidth: Page.left + maxW - x)
                (t as NSString).draw(at: CGPoint(x: x, y: baseline - f.ascender), withAttributes: attrs)
                x += (t as NSString).size(withAttributes: attrs).width
            }
        }

        text(eyebrowText, x: Page.right, top: bottom - rightH, size: 8.25, face: .bold, color: Ink.blue,
             tracking: 0.12, align: .right)
        text(date, x: Page.right, top: bottom - 2.25 - 9.75 * lineFactor, size: 9.75, face: .semibold,
             color: Ink.secondary(0.75), align: .right)

        let ruleTop = bottom + 10.5
        fill(CGRect(x: Page.left, y: ruleTop, width: Page.contentWidth, height: 1.5), Ink.black)
        return ruleTop + 1.5
    }

    /// Team and opponent at 30 pt, upper-cased, with a smaller gray "VS." between.
    private static func matchupWords(team: String, opponent: String) -> [Word] {
        let teamText = team.trimmingCharacters(in: .whitespacesAndNewlines)
        let opp = opponent.trimmingCharacters(in: .whitespacesAndNewlines)
        func words(_ s: String) -> [Word] {
            s.uppercased().split(whereSeparator: \.isWhitespace).map { Word(text: String($0), size: 30, color: Ink.black) }
        }
        var all = words(teamText.isEmpty ? "Stack the Lineup" : teamText)
        if !opp.isEmpty {
            all.append(Word(text: "VS.", size: 19.5, color: Ink.secondary(0.75)))
            all += words(opp)
        }
        return all
    }

    private static func lineWidth(_ words: ArraySlice<Word>, scale: CGFloat) -> CGFloat {
        var w: CGFloat = 0
        for (k, i) in words.indices.enumerated() {
            if k > 0 { w += width(" ", .condensed, min(words[i - 1].size, words[i].size) * scale) }
            w += width(words[i].text, .condensed, words[i].size * scale)
        }
        return w
    }

    /// One line if it fits, else two balanced lines. Only if a balanced line
    /// still overflows does it shrink, from 30 pt to no less than 24; past that
    /// the words are cut with an ellipsis.
    private static func layoutMatchup(_ words: [Word], maxWidth: CGFloat) -> (lines: [ArraySlice<Word>], scale: CGFloat) {
        func split(_ scale: CGFloat) -> [ArraySlice<Word>] {
            if words.count < 2 || lineWidth(words[...], scale: scale) <= maxWidth { return [words[...]] }
            let worst = { (k: Int) in max(lineWidth(words[..<k], scale: scale), lineWidth(words[k...], scale: scale)) }
            let k = (1..<words.count).min { worst($0) < worst($1) } ?? 1
            return [words[..<k], words[k...]]
        }
        var scale: CGFloat = 1
        var lines = split(scale)
        while scale > 0.8 + 0.001, lines.contains(where: { lineWidth($0, scale: scale) > maxWidth }) {
            scale -= 0.025
            lines = split(scale)
        }
        return (lines, scale)
    }

    private static func drawFooter(generatedAt: Date) {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        hLine(from: Page.left, to: Page.right, y: Page.footerRule, Ink.separator, 0.75)
        text("Generated \(formatter.string(from: generatedAt))", x: Page.left, top: Page.footerTextTop,
             size: 7.5, face: .regular, color: Ink.secondary(0.5))
        text("Stack the Lineup", x: Page.right, top: Page.footerTextTop, size: 7.5, face: .semibold,
             color: Ink.secondary(0.5), align: .right)
    }

    /// `names` as comma-separated lines no wider than `maxWidth`, never
    /// breaking inside a name ("Caleb J." stays together), balanced so the
    /// lines come out about the same length.
    private static func commaLines(_ names: [String], maxWidth: CGFloat, face: Face, size: CGFloat) -> [String] {
        guard !names.isEmpty else { return [] }
        let tokens = names.enumerated().map { $0.offset < names.count - 1 ? $0.element + "," : $0.element }
        func wrap(_ w: CGFloat) -> [String] {
            var lines: [String] = []
            var line = ""
            for token in tokens {
                let next = line.isEmpty ? token : line + " " + token
                if line.isEmpty || width(next, face, size) <= w {
                    line = next
                } else {
                    lines.append(line)
                    line = token
                }
            }
            return lines + [line]
        }
        let greedy = wrap(maxWidth)
        guard greedy.count > 1 else { return greedy }
        // The narrowest width that still needs no more lines than the greedy fill.
        var lo: CGFloat = 0
        var hi = maxWidth
        for _ in 0..<12 {
            let mid = (lo + hi) / 2
            if wrap(mid).count <= greedy.count { hi = mid } else { lo = mid }
        }
        return wrap(hi)
    }

    // MARK: - Drawing helpers

    private enum Align { case left, center, right }

    private static func attributes(_ face: Face, _ size: CGFloat, color: UIColor = .black,
                                   tracking: CGFloat = 0) -> [NSAttributedString.Key: Any] {
        [.font: font(face, size), .foregroundColor: color, .kern: tracking * size]
    }

    /// Width of `s` with `tracking` (em) after every glyph, as CSS letter-spacing.
    private static func width(_ s: String, _ face: Face, _ size: CGFloat, tracking: CGFloat = 0) -> CGFloat {
        (s as NSString).size(withAttributes: attributes(face, size, tracking: tracking)).width
    }

    /// `s`, cut with an ellipsis if it is wider than `maxWidth`.
    private static func fit(_ s: String, attrs: [NSAttributedString.Key: Any], maxWidth: CGFloat) -> String {
        guard (s as NSString).size(withAttributes: attrs).width > maxWidth else { return s }
        var t = s
        while t.count > 1 && ((t + "…") as NSString).size(withAttributes: attrs).width > maxWidth { t.removeLast() }
        return t.trimmingCharacters(in: .whitespaces) + "…"
    }

    /// One line of text. Its CSS line box (size x 1.2) starts at `top`, or, with
    /// `height`, it is vertically centered in a box that tall. `x` is the left,
    /// center or right edge per `align`. Past `maxWidth` it ends in an ellipsis.
    private static func text(_ s: String, x: CGFloat, top: CGFloat, height: CGFloat? = nil, size: CGFloat,
                             face: Face, color: UIColor, tracking: CGFloat = 0, align: Align = .left,
                             maxWidth: CGFloat? = nil) {
        let attrs = attributes(face, size, color: color, tracking: tracking)
        let t = maxWidth.map { fit(s, attrs: attrs, maxWidth: $0) } ?? s
        // Trailing tracking isn't ink, so alignment ignores it.
        let w = (t as NSString).size(withAttributes: attrs).width - tracking * size
        let f = attrs[.font] as! UIFont
        let boxTop = height.map { top + $0 / 2 - lineFactor * size / 2 } ?? top
        let y = boxTop + (lineFactor * size - f.lineHeight) / 2
        let originX: CGFloat
        switch align {
        case .left: originX = x
        case .center: originX = x - w / 2
        case .right: originX = x - w
        }
        (t as NSString).draw(at: CGPoint(x: originX, y: y), withAttributes: attrs)
    }

    /// Runs `draw` clipped to `rect` with rounded corners (the containers clip their contents).
    private static func clipped(to rect: CGRect, radius: CGFloat = 6, _ draw: () -> Void) {
        let ctx = UIGraphicsGetCurrentContext()
        ctx?.saveGState()
        UIBezierPath(roundedRect: rect, cornerRadius: radius).addClip()
        draw()
        ctx?.restoreGState()
    }

    private static func fill(_ rect: CGRect, _ color: UIColor) {
        color.setFill()
        UIBezierPath(rect: rect).fill()
    }

    private static func fillRounded(_ rect: CGRect, radius: CGFloat, _ color: UIColor) {
        color.setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: radius).fill()
    }

    private static func strokeRounded(_ rect: CGRect, radius: CGFloat, _ color: UIColor, _ lineWidth: CGFloat) {
        color.setStroke()
        let path = UIBezierPath(roundedRect: rect, cornerRadius: radius)
        path.lineWidth = lineWidth
        path.stroke()
    }

    private static func hLine(from x1: CGFloat, to x2: CGFloat, y: CGFloat, _ color: UIColor, _ thickness: CGFloat) {
        fill(CGRect(x: x1, y: y - thickness / 2, width: x2 - x1, height: thickness), color)
    }

    private static func vLine(x: CGFloat, from top: CGFloat, to bottom: CGFloat, _ color: UIColor, _ thickness: CGFloat) {
        fill(CGRect(x: x - thickness / 2, y: top, width: thickness, height: bottom - top), color)
    }
}
