import UIKit
import PDFKit
import SwiftUI

// MARK: - PDF Generator
//
// The Batting Order and Coaches Guide printouts, from the Coaches Guide
// redesign handoff (the ink-saver version: white position badges with black
// borders, no row tints, black status dots, so it prints cleanly in black and
// white). US Letter, 612 x 792 pt; the handoff's px values are x0.75.
// The web pilot draws the same pages (web/src/print/lineupPdf.ts).

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
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: Page.width, height: Page.height))
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

        let formatter = DateFormatter()
        formatter.dateStyle = .short
        let dateStr = formatter.string(from: lineup.gameDate).replacingOccurrences(of: "/", with: "-")
        let filename = type == .battingOrder ? "BattingOrder_\(dateStr).pdf" : "CoachesGuide_\(dateStr).pdf"

        return PDFDocument(data: data, filename: filename)
    }

    // MARK: - Page and tokens

    private enum Page {
        static let width: CGFloat = 612
        static let height: CGFloat = 792
        static let top: CGFloat = 33
        static let side: CGFloat = 36
        static let bottom: CGFloat = 27
        static let contentWidth = width - side * 2
        static let footerTextTop = height - bottom - 7.5 * lineFactor
        static let footerRule = footerTextTop - 7.5
        /// Lowest y page content may reach, leaving room above the footer rule.
        static let contentBottom = footerRule - 12
    }

    /// Line box height as a fraction of font size (CSS "normal").
    private static let lineFactor: CGFloat = 1.2

    private enum Ink {
        static let black = UIColor.black
        static let white = UIColor.white
        static let blue = UIColor(red: 0, green: 122 / 255, blue: 1, alpha: 1)
        static let grouped = UIColor(red: 242 / 255, green: 242 / 255, blue: 247 / 255, alpha: 1)
        static let separator = UIColor(red: 198 / 255, green: 198 / 255, blue: 200 / 255, alpha: 1)
        static let hairline = UIColor(red: 229 / 255, green: 229 / 255, blue: 234 / 255, alpha: 1)
        /// rgba(60,60,67,a)
        static func secondary(_ a: CGFloat) -> UIColor { UIColor(red: 60 / 255, green: 60 / 255, blue: 67 / 255, alpha: a) }
    }

    // MARK: - Batting Order PDF

    private static func drawBattingOrder(ctx: UIGraphicsPDFRendererContext, lineup: Lineup, players: [Player],
                                         teamName: String, generatedAt: Date) {
        ctx.beginPage()
        let ordered = lineup.orderedPlayers(from: players)

        let numW: CGFloat = 48
        let jerseyW: CGFloat = 72
        let left = Page.side
        let right = Page.width - Page.side
        let playerX = left + numW
        let jerseyX = right - jerseyW
        let headH: CGFloat = 7.5 * 2 + 7.5 * lineFactor
        let countH: CGFloat = 7.5 + 8.25 * lineFactor

        var top = drawHeader(eyebrow: "Batting Order", lineup: lineup, teamName: teamName) + 15
        // Rows shrink from 30.75 to 24 to fit; past that the list continues on another page.
        let room = Page.contentBottom - top - headH - countH
        let rowH = max(24, min(30.75, room / CGFloat(max(1, ordered.count))))
        let nameSize: CGFloat = rowH < 27 ? 11.25 : 12.75

        func table(_ rows: ArraySlice<Player>) {
            let h = headH + CGFloat(rows.count) * rowH
            // Grouped fill clipped to the corners; white rows painted over it (square is fine: the page is white).
            fillRounded(CGRect(x: left, y: top, width: Page.contentWidth, height: h), radius: 6, Ink.grouped)
            for (k, i) in rows.indices.enumerated() {
                let player = rows[i]
                let y = top + headH + CGFloat(k) * rowH
                if i % 2 == 0 { fill(CGRect(x: left, y: y, width: Page.contentWidth, height: rowH), Ink.white) }
                if k > 0 { hLine(from: left, to: right, y: y, Ink.hairline, 0.75) }
                text("\(i + 1)", x: left + numW / 2, top: y, height: rowH, size: 15, weight: .heavy, color: Ink.black,
                     align: .center, digits: true)
                text(player.displayName, x: playerX + 10.5, top: y, height: rowH, size: nameSize, weight: .semibold,
                     color: Ink.black, tracking: -0.01, maxWidth: jerseyX - playerX - 21)
                if !player.number.isEmpty {
                    text(player.number, x: jerseyX + jerseyW / 2, top: y, height: rowH, size: 11.25, weight: .bold,
                         color: Ink.black, align: .center, maxWidth: jerseyW - 12, digits: true)
                }
            }
            hLine(from: left, to: right, y: top + headH, Ink.separator, 0.75)
            vLine(x: playerX, from: top, to: top + h, Ink.hairline, 0.75)
            vLine(x: jerseyX, from: top, to: top + h, Ink.hairline, 0.75)
            let labelColor = Ink.secondary(0.7)
            text("#", x: left + numW / 2, top: top, height: headH, size: 7.5, weight: .bold, color: labelColor,
                 tracking: 0.08, align: .center)
            text("PLAYER", x: playerX + 10.5, top: top, height: headH, size: 7.5, weight: .bold, color: labelColor, tracking: 0.08)
            text("JERSEY", x: jerseyX + jerseyW / 2, top: top, height: headH, size: 7.5, weight: .bold, color: labelColor,
                 tracking: 0.08, align: .center)
            strokeRounded(CGRect(x: left, y: top, width: Page.contentWidth, height: h), radius: 6, Ink.separator, 0.75)
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
             size: 8.25, weight: .regular, color: Ink.secondary(0.7))
        drawFooter(generatedAt: generatedAt)
    }

    // MARK: - Coaches Guide PDF

    private static let gridHeadH: CGFloat = 4.5 + 6.75 * lineFactor + 13.5 * 1.1 + 4.5
    private static let positionRowH: CGFloat = 25.5
    private static let badgeColumn: CGFloat = 48
    private static let pitchTitleH: CGFloat = 12.75 * lineFactor
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
        var top = drawHeader(eyebrow: "Coaches Guide", lineup: lineup, teamName: teamName) + 15

        // By position: a row per field position, then Bench; each cell names who is there that inning.
        let positions = lineup.activeFieldPositions(config: fairPlayConfig)
        let active = lineup.activePlayers(from: players)
        let orderedPlayers = lineup.orderedPlayers(from: players)
        let sitOrder = orderedPlayers + active.filter { p in !orderedPlayers.contains(where: { $0.id == p.id }) }
        let sitters: [[Player]] = lineup.innings.map { inning in
            sitOrder.filter { p in
                let pos = inning.position(for: p)
                return pos == nil || pos == .bench
            }
        }
        let most = sitters.map(\.count).max() ?? 0
        // First name, or "Caleb J." when two active players share one (as on the field view).
        var firstNameCounts: [String: Int] = [:]
        for p in active { firstNameCounts[p.firstName, default: 0] += 1 }
        let name: (Player) -> String = { p in (firstNameCounts[p.firstName] ?? 0) > 1 ? p.shortName : p.firstName }

        // Pitch counts, scoped to lineup.gameDate rather than today so the
        // numbers match what the coach sees in the Pitching tab for this game.
        // Hidden when no one can pitch.
        let pitchRows = PitchEligibilityEngine.coachesGuideSummary(
            gameLogs: gameLogs,
            players: players,
            config: pitchingConfig,
            referenceDate: lineup.gameDate
        ) ?? []

        // Overflow, per the handoff: tighten the bench lines, then the pitch rows; then move pitch counts to page 2.
        func benchHeight(_ line: CGFloat) -> CGFloat { max(7.5 * 2 + 16.5, 6 * 2 + CGFloat(most) * line) }
        func gridHeight(_ line: CGFloat) -> CGFloat {
            gridHeadH + CGFloat(positions.count) * positionRowH + 0.75 + benchHeight(line)
        }
        func pitchHeight(_ row: CGFloat) -> CGFloat {
            pitchRows.isEmpty ? 0 : 19.5 + pitchTitleH + 6 + pitchHeadH + CGFloat((pitchRows.count + 1) / 2) * row
        }
        let room = Page.contentBottom - top
        var benchLine: CGFloat = 12.75
        var pitchRow: CGFloat = 18.75
        if gridHeight(benchLine) + pitchHeight(pitchRow) > room { benchLine = 11.25 }
        if gridHeight(benchLine) + pitchHeight(pitchRow) > room { pitchRow = 16.5 }

        top = drawDefenseGrid(
            top: top, lineup: lineup, positions: positions, active: active, sitters: sitters,
            benchLine: benchLine, benchHeight: benchHeight(benchLine), name: name
        )

        if !pitchRows.isEmpty {
            if top + pitchHeight(pitchRow) > Page.contentBottom {
                drawFooter(generatedAt: generatedAt)
                ctx.beginPage()
                top = Page.top - 19.5
            }
            drawPitchCounts(rows: pitchRows, top: top + 19.5, rowH: pitchRow)
        }

        drawFooter(generatedAt: generatedAt)
    }

    private static func drawDefenseGrid(
        top: CGFloat, lineup: Lineup, positions: [FieldPosition], active: [Player], sitters: [[Player]],
        benchLine: CGFloat, benchHeight: CGFloat, name: (Player) -> String
    ) -> CGFloat {
        let left = Page.side
        let right = Page.width - Page.side
        let innings = lineup.innings.count
        let colW = (Page.contentWidth - badgeColumn) / CGFloat(innings)
        func colX(_ i: Int) -> CGFloat { left + badgeColumn + CGFloat(i) * colW }
        let nameSize: CGFloat = innings >= 7 ? 9.75 : 10.5
        let rowsTop = top + gridHeadH
        let firstOutfield = positions.firstIndex(where: { $0.isOutfield })
        func rowTop(_ r: Int) -> CGFloat {
            rowsTop + CGFloat(r) * positionRowH + ((firstOutfield ?? Int.max) > 0 && r >= (firstOutfield ?? Int.max) ? 0.75 : 0)
        }
        let benchTop = rowTop(positions.count)
        let bottom = benchTop + benchHeight
        let box = CGRect(x: left, y: top, width: Page.contentWidth, height: bottom - top)

        // Fills: the grouped header and bench, the white body between. The container clips to its 6 pt corners.
        fillRounded(box, radius: 6, Ink.grouped)
        fill(CGRect(x: left, y: rowsTop, width: Page.contentWidth, height: benchTop - rowsTop), Ink.white)

        // Header row.
        text("POS", x: left + 9, top: top + gridHeadH - 6 - 7.5 * lineFactor, size: 7.5, weight: .bold,
             color: Ink.secondary(0.7), tracking: 0.08)
        for i in 0..<innings {
            text("INNING", x: colX(i) + 7.5, top: top + 4.5, size: 6.75, weight: .bold, color: Ink.secondary(0.6), tracking: 0.08)
            text("\(i + 1)", x: colX(i) + 7.5, top: top + 4.5 + 6.75 * lineFactor + (1.1 - lineFactor) * 13.5 / 2,
                 size: 13.5, weight: .heavy, color: Ink.black, digits: true)
        }
        hLine(from: left, to: right, y: rowsTop, Ink.separator, 0.75)

        // Position rows: badge, then who plays there each inning.
        for (r, position) in positions.enumerated() {
            let y = rowTop(r)
            if r > 0 && r == firstOutfield {
                hLine(from: left, to: right, y: y, Ink.separator, 1.5)
            } else if r > 0 {
                hLine(from: left, to: right, y: y, Ink.hairline, 0.75)
            }
            drawBadge(position.rawValue, x: left + 9, top: y + (positionRowH - 16.5) / 2)
            for i in 0..<innings {
                if let player = lineup.innings[i].player(at: position, in: active) {
                    text(name(player), x: colX(i) + 7.5, top: y, height: positionRowH, size: nameSize, weight: .semibold,
                         color: Ink.black, tracking: -0.01, maxWidth: colW - 15)
                } else {
                    text("—", x: colX(i) + 7.5, top: y, height: positionRowH, size: nameSize, weight: .regular,
                         color: Ink.secondary(0.6))
                }
            }
        }

        // Bench: everyone with no field spot that inning, in batting order, one name per line.
        hLine(from: left, to: right, y: benchTop + 0.75, Ink.separator, 1.5)
        drawBadge("BN", x: left + 9, top: benchTop + 1.5 + 7.5)
        for (i, list) in sitters.enumerated() {
            for (k, player) in list.enumerated() {
                text(name(player), x: colX(i) + 7.5, top: benchTop + 1.5 + 6 + CGFloat(k) * benchLine, height: benchLine,
                     size: 9, weight: .medium, color: Ink.secondary(0.85), maxWidth: colW - 15)
            }
        }

        for i in 0..<innings { vLine(x: colX(i), from: top, to: bottom, Ink.hairline, 0.75) }
        strokeRounded(box, radius: 6, Ink.separator, 0.75)
        return bottom
    }

    /// "Pitch counts" title, then two tables side by side (first half, rounded up, on the left).
    private static func drawPitchCounts(rows: [PitchingGuideSummaryRow], top: CGFloat, rowH: CGFloat) {
        let left = Page.side
        let right = Page.width - Page.side
        text("Pitch counts", x: left, top: top, size: 12.75, weight: .bold, color: Ink.black, tracking: -0.01)
        // Shares the title's baseline: solve the note's line top so both baselines land on the same y.
        let titleFont = UIFont.systemFont(ofSize: 12.75, weight: .bold)
        let noteFont = UIFont.systemFont(ofSize: 8.25)
        let baseline = top + (lineFactor * 12.75 - titleFont.lineHeight) / 2 + titleFont.ascender
        let noteTop = baseline - noteFont.ascender - (lineFactor * 8.25 - noteFont.lineHeight) / 2
        text("Avail: pitches left today. Rest: days off still needed.", x: right, top: noteTop,
             size: 8.25, weight: .regular, color: Ink.secondary(0.7), align: .right)

        let gap: CGFloat = 18
        let tableW = (Page.contentWidth - gap) / 2
        let labels = rows.map { $0.status.displayLabel }
        let labelFont = UIFont.systemFont(ofSize: 8.25, weight: .semibold)
        // Status is 52.5 wide in the handoff; a rest date ("Available Tue 9/29") needs more, taken from Player.
        let statusW = max(52.5, labels.map { 5.25 + 3.75 + ($0 as NSString).size(withAttributes: [.font: labelFont]).width + 3 }.max() ?? 0)
        let half = (rows.count + 1) / 2
        let tablesTop = top + pitchTitleH + 6

        func table(x: CGFloat, list: ArraySlice<PitchingGuideSummaryRow>) {
            let tRight = x + tableW - 3
            let restR = tRight - statusW
            let availR = restR - 25.5
            let thrownR = availR - 31.5
            let head = Ink.secondary(0.7)
            text("PLAYER", x: x + 3, top: tablesTop, size: 7.1, weight: .bold, color: head, tracking: 0.08)
            text("THROWN", x: thrownR, top: tablesTop, size: 7.1, weight: .bold, color: head, tracking: 0.08, align: .right)
            text("AVAIL", x: availR, top: tablesTop, size: 7.1, weight: .bold, color: head, tracking: 0.08, align: .right)
            text("REST", x: restR, top: tablesTop, size: 7.1, weight: .bold, color: head, tracking: 0.08, align: .right)
            text("STATUS", x: tRight, top: tablesTop, size: 7.1, weight: .bold, color: head, tracking: 0.08, align: .right)
            fill(CGRect(x: x, y: tablesTop + 7.1 * lineFactor + 3.75, width: tableW, height: 1.125), Ink.black)

            for (k, i) in list.indices.enumerated() {
                let row = list[i]
                let y = tablesTop + pitchHeadH + CGFloat(k) * rowH
                let restricted = row.status.isRestricted
                text(row.player.displayName, x: x + 3, top: y, height: rowH, size: 9.4, weight: .semibold, color: Ink.black,
                     maxWidth: thrownR - 34.5 - x - 3)
                text("\(row.pitchesInWindow)", x: thrownR, top: y, height: rowH, size: 9.4, weight: .regular,
                     color: Ink.secondary(0.75), align: .right, digits: true)
                text("\(restricted ? 0 : row.available)", x: availR, top: y, height: rowH, size: 9.4, weight: .bold,
                     color: Ink.black, align: .right, digits: true)
                // Rest owed is only meaningful while they're still inside it; 0 otherwise (no dashes).
                text("\(restricted ? row.restDaysRequired : 0)", x: restR, top: y, height: rowH, size: 9.4, weight: .regular,
                     color: Ink.secondary(0.75), align: .right, digits: true)
                let label = labels[i]
                let labelW = (label as NSString).size(withAttributes: [.font: labelFont]).width
                text(label, x: tRight, top: y, height: rowH, size: 8.25, weight: .semibold, color: Ink.black, align: .right)
                let d: CGFloat = 5.25
                Ink.black.setFill()
                UIBezierPath(ovalIn: CGRect(x: tRight - labelW - 3.75 - d, y: y + rowH / 2 - d / 2, width: d, height: d)).fill()
                hLine(from: x, to: x + tableW, y: y + rowH - 0.375, Ink.hairline, 0.75)
            }
        }

        table(x: left, list: rows[0..<half])
        table(x: left + tableW + gap, list: rows[half...])
    }

    // MARK: - Shared header and footer

    /// Eyebrow + team name on the left, opponent + date on the right, over a
    /// 1.5 pt black rule. Returns the rule's bottom.
    private static func drawHeader(eyebrow: String, lineup: Lineup, teamName: String) -> CGFloat {
        let leftH: CGFloat = 8.25 * lineFactor + 3 + 21 * 1.05
        let rightH: CGFloat = 15 * lineFactor + 2.25 + 9.75 * lineFactor
        let bottom = Page.top + max(leftH, rightH)
        let left = Page.side
        let right = Page.width - Page.side

        let opponent = "vs. \(lineup.opponent.isEmpty ? "TBD" : lineup.opponent)"
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        let date = formatter.string(from: lineup.gameDate)
        let rightW = max(width(opponent, size: 15, weight: .bold, tracking: -0.01), width(date, size: 9.75, weight: .medium))
        text(opponent, x: right, top: bottom - rightH, size: 15, weight: .bold, color: Ink.black, tracking: -0.01,
             align: .right, maxWidth: Page.contentWidth / 2)
        text(date, x: right, top: bottom - 9.75 * lineFactor, size: 9.75, weight: .medium, color: Ink.secondary(0.75), align: .right)

        text(eyebrow.uppercased(), x: left, top: bottom - leftH, size: 8.25, weight: .bold, color: Ink.blue, tracking: 0.12)
        // The 1.05 line box is tighter than lineFactor; center the glyphs in it.
        text(teamName.isEmpty ? "Stack the Lineup" : teamName, x: left,
             top: bottom - 21 * 1.05 - (lineFactor - 1.05) * 21 / 2, size: 21, weight: .heavy, color: Ink.black,
             tracking: -0.02, maxWidth: Page.contentWidth - min(rightW, Page.contentWidth / 2) - 12)

        let ruleTop = bottom + 10.5
        fill(CGRect(x: left, y: ruleTop, width: Page.contentWidth, height: 1.5), Ink.black)
        return ruleTop + 1.5
    }

    private static func drawFooter(generatedAt: Date) {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        hLine(from: Page.side, to: Page.width - Page.side, y: Page.footerRule, Ink.hairline, 0.75)
        text("Generated \(formatter.string(from: generatedAt))", x: Page.side, top: Page.footerTextTop,
             size: 7.5, weight: .regular, color: Ink.secondary(0.6))
        text("Stack the Lineup", x: Page.width - Page.side, top: Page.footerTextTop, size: 7.5, weight: .semibold,
             color: Ink.secondary(0.6), align: .right)
    }

    /// Ink-saver position badge: white, black text, 1.125 pt black border.
    private static func drawBadge(_ label: String, x: CGFloat, top: CGFloat) {
        let inset: CGFloat = 1.125 / 2   // CSS border-box: the border sits inside the 22.5 x 16.5 box
        let rect = CGRect(x: x + inset, y: top + inset, width: 22.5 - 1.125, height: 16.5 - 1.125)
        fillRounded(rect, radius: 4.5 - inset, Ink.white)
        strokeRounded(rect, radius: 4.5 - inset, Ink.black, 1.125)
        text(label, x: x + 22.5 / 2, top: top, height: 16.5, size: 9, weight: .heavy, color: Ink.black, align: .center)
    }

    // MARK: - Drawing helpers

    private enum Align { case left, center, right }

    private static func font(size: CGFloat, weight: UIFont.Weight, digits: Bool) -> UIFont {
        digits ? .monospacedDigitSystemFont(ofSize: size, weight: weight) : .systemFont(ofSize: size, weight: weight)
    }

    private static func attributes(size: CGFloat, weight: UIFont.Weight, color: UIColor = .black,
                                   tracking: CGFloat = 0, digits: Bool = false) -> [NSAttributedString.Key: Any] {
        [.font: font(size: size, weight: weight, digits: digits), .foregroundColor: color, .kern: tracking * size]
    }

    /// Width of `s` with `tracking` (em) after every glyph, as CSS letter-spacing.
    private static func width(_ s: String, size: CGFloat, weight: UIFont.Weight, tracking: CGFloat = 0, digits: Bool = false) -> CGFloat {
        (s as NSString).size(withAttributes: attributes(size: size, weight: weight, tracking: tracking, digits: digits)).width
    }

    /// One line of text. Its CSS line box (size x 1.2) starts at `top`, or, with
    /// `height`, it is vertically centered in a box that tall. `x` is the left,
    /// center or right edge per `align`. Past `maxWidth` it ends in an ellipsis.
    private static func text(_ s: String, x: CGFloat, top: CGFloat, height: CGFloat? = nil, size: CGFloat,
                             weight: UIFont.Weight, color: UIColor, tracking: CGFloat = 0, align: Align = .left,
                             maxWidth: CGFloat? = nil, digits: Bool = false) {
        let attrs = attributes(size: size, weight: weight, color: color, tracking: tracking, digits: digits)
        var t = s
        if let maxWidth, (t as NSString).size(withAttributes: attrs).width > maxWidth {
            while t.count > 1 && ((t + "…") as NSString).size(withAttributes: attrs).width > maxWidth { t.removeLast() }
            t = t.trimmingCharacters(in: .whitespaces) + "…"
        }
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
