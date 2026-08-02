import UIKit
import PDFKit
import SwiftUI

class PDFGenerator {

    static func generate(
        type: PDFType,
        lineup: Lineup,
        players: [Player],
        teamName: String = "",
        teamColor: Color = .blue,
        gameLogs: [GameLog] = [],
        pitchingConfig: PitchingConfig = PitchingConfig()
    ) -> PDFDocument {
        let pageWidth: CGFloat = 612   // US Letter
        let pageHeight: CGFloat = 792
        let margin: CGFloat = 48

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))

        let data = renderer.pdfData { ctx in
            switch type {
            case .battingOrder:
                drawBattingOrder(ctx: ctx, lineup: lineup, players: players,
                                  pageWidth: pageWidth, pageHeight: pageHeight, margin: margin, teamName: teamName, teamColor: teamColor)
            case .coachesGuide:
                drawCoachesGuide(ctx: ctx, lineup: lineup, players: players,
                                  pageWidth: pageWidth, pageHeight: pageHeight, margin: margin,
                                  teamName: teamName, teamColor: teamColor,
                                  gameLogs: gameLogs, pitchingConfig: pitchingConfig)
            }
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .short
        let dateStr = formatter.string(from: lineup.gameDate).replacingOccurrences(of: "/", with: "-")
        let filename = type == .battingOrder ? "BattingOrder_\(dateStr).pdf" : "CoachesGuide_\(dateStr).pdf"

        return PDFDocument(data: data, filename: filename)
    }

    // MARK: - Batting Order PDF

    private static func drawBattingOrder(ctx: UIGraphicsPDFRendererContext, lineup: Lineup, players: [Player],
                                          pageWidth: CGFloat, pageHeight: CGFloat, margin: CGFloat, teamName: String = "", teamColor: Color = .blue) {
        ctx.beginPage()
        var y: CGFloat = margin

        // Header
        y = drawHeader(title: "Batting Order", lineup: lineup,
                       pageWidth: pageWidth, margin: margin, y: y, teamName: teamName, teamColor: teamColor)
        y += 24

        // Column headers
        let col2: CGFloat = margin + 80
        let col3: CGFloat = pageWidth - margin - 60

        drawText("#", x: margin, y: y, font: .boldSystemFont(ofSize: 11), color: .darkGray)
        drawText("Player", x: col2, y: y, font: .boldSystemFont(ofSize: 11), color: .darkGray)
        drawText("Jersey", x: col3, y: y, font: .boldSystemFont(ofSize: 11), color: .darkGray)
        y += 16

        // Divider
        let dividerPath = UIBezierPath()
        dividerPath.move(to: CGPoint(x: margin, y: y))
        dividerPath.addLine(to: CGPoint(x: pageWidth - margin, y: y))
        UIColor.lightGray.setStroke()
        dividerPath.stroke()
        y += 12

        let orderedPlayers = lineup.orderedPlayers(from: players)

        for (index, player) in orderedPlayers.enumerated() {
            let rowBg = index % 2 == 0 ? UIColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1.0) : UIColor.white
            let rowRect = CGRect(x: margin, y: y - 4, width: pageWidth - margin * 2, height: 28)
            rowBg.setFill()
            UIBezierPath(roundedRect: rowRect, cornerRadius: 4).fill()

            drawText("\(index + 1).", x: margin + 8, y: y + 4, font: .boldSystemFont(ofSize: 14), color: .black)
            drawText(player.displayName, x: col2, y: y + 4, font: .systemFont(ofSize: 14), color: .black)
            
            // Only show jersey number if it exists
            let jerseyText = player.number.isEmpty ? "—" : "#\(player.number)"
            drawText(jerseyText, x: col3, y: y + 4, font: .systemFont(ofSize: 14), color: .darkGray)

            y += 32
        }

        // Total
        y += 12
        drawText("Total Players: \(orderedPlayers.count)", x: margin, y: y,
                 font: .italicSystemFont(ofSize: 11), color: .gray)

        drawFooter(pageWidth: pageWidth, pageHeight: pageHeight, margin: margin)
    }

    // MARK: - Coaches Guide PDF

    private static func drawCoachesGuide(
        ctx: UIGraphicsPDFRendererContext,
        lineup: Lineup,
        players: [Player],
        pageWidth: CGFloat,
        pageHeight: CGFloat,
        margin: CGFloat,
        teamName: String = "",
        teamColor: Color = .blue,
        gameLogs: [GameLog] = [],
        pitchingConfig: PitchingConfig = PitchingConfig()
    ) {
        ctx.beginPage()
        var y: CGFloat = margin

        // Header
        y = drawHeader(title: "Coaches Guide", lineup: lineup,
                       pageWidth: pageWidth, margin: margin, y: y, teamName: teamName, teamColor: teamColor)
        y += 20

        let orderedPlayers = lineup.orderedPlayers(from: players)
        let allPlayers = orderedPlayers.isEmpty ? players : orderedPlayers

        // Grid dimensions
        let gridLeft = margin + 120    // space for player name
        let gridRight = pageWidth - margin
        let colWidth = (gridRight - gridLeft) / CGFloat(lineup.innings.count)
        let rowHeight: CGFloat = 26

        // Draw inning header row
        drawText("Player", x: margin, y: y + 6, font: .boldSystemFont(ofSize: 10), color: .darkGray)

        for inning in 0..<lineup.innings.count {
            // Inning header cell
            let headerRect = CGRect(x: gridLeft + CGFloat(inning) * colWidth, y: y, width: colWidth - 2, height: rowHeight)
            UIColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1.0).setFill()
            UIBezierPath(roundedRect: headerRect, cornerRadius: 3).fill()
            drawCenteredText("Inn \(inning + 1)", in: headerRect, font: .boldSystemFont(ofSize: 10), color: .black)
        }
        y += rowHeight + 4

        // Player rows
        for (rowIndex, player) in allPlayers.enumerated() {
            let rowBg = rowIndex % 2 == 0 ? UIColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1.0) : UIColor.white
            let rowRect = CGRect(x: margin, y: y, width: pageWidth - margin * 2, height: rowHeight)
            rowBg.setFill()
            UIBezierPath(roundedRect: rowRect, cornerRadius: 3).fill()

            // Player name + batting order number
            let orderNum = orderedPlayers.firstIndex(where: { $0.id == player.id }).map { "\($0 + 1)." } ?? "—"
            drawText(orderNum, x: margin + 4, y: y + 7, font: .boldSystemFont(ofSize: 10), color: .darkGray)
            drawText(player.displayName, x: margin + 22, y: y + 7, font: .systemFont(ofSize: 10), color: .black)

            // Position cells
            for inning in 0..<lineup.innings.count {
                let cellX = gridLeft + CGFloat(inning) * colWidth
                let cellRect = CGRect(x: cellX + 1, y: y + 2, width: colWidth - 3, height: rowHeight - 4)

                if let pos = lineup.innings[inning].position(for: player) {
                    let cellColor: UIColor = pos.isAbsent ? .systemGray : .black
                    drawCenteredText(pos.rawValue, in: cellRect, font: .boldSystemFont(ofSize: 10), color: cellColor)
                } else {
                    drawCenteredText("—", in: cellRect, font: .systemFont(ofSize: 10), color: .lightGray)
                }
            }

            y += rowHeight + 2

            // Check page overflow
            if y > pageHeight - margin - 80 {
                drawFooter(pageWidth: pageWidth, pageHeight: pageHeight, margin: margin)
                ctx.beginPage()
                y = margin
            }
        }

        // MARK: - Pitch Count Section
        // Rows come from PitchEligibilityEngine, scoped to lineup.gameDate rather
        // than today so the numbers match what the coach sees in the Pitching tab
        // for this game. This file used to carry its own copy of that calculation
        // ("exact port of PositionSummaryView.pitchingRows()"); the engine owns it
        // now, so there's one place for the window maths to be right.

        let pitchRows = PitchEligibilityEngine.coachesGuideSummary(
            gameLogs: gameLogs,
            players: players,
            config: pitchingConfig,
            referenceDate: lineup.gameDate
        ) ?? []

        if !pitchRows.isEmpty {
            // Estimated height: divider+title (20) + header row (22) + rows in the taller column
            // Two-column layout means vertical rows = ceil(count / 2)
            let halfRows = Int(ceil(Double(pitchRows.count) / 2.0))
            let sectionHeight = CGFloat(20 + 22 + halfRows * 21 + 20)
            let spaceRemaining = pageHeight - margin - y

            if spaceRemaining < sectionHeight {
                // Not enough room — start a new page
                drawFooter(pageWidth: pageWidth, pageHeight: pageHeight, margin: margin)
                ctx.beginPage()
                y = margin
            } else {
                y += 16
            }

            drawPitchCountSection(
                rows: pitchRows,
                y: &y,
                pageWidth: pageWidth,
                pageHeight: pageHeight,
                margin: margin,
                ctx: ctx
            )
        }

        drawFooter(pageWidth: pageWidth, pageHeight: pageHeight, margin: margin)
    }

    // MARK: - Pitch Count Section Helper
    // Renders as two side-by-side mini-tables so the section stays on one page
    // regardless of roster size. Left table gets the first half of rows, right
    // gets the second half. Both share the same column proportions.

    private static func drawPitchCountSection(
        rows: [PitchingGuideSummaryRow],
        y: inout CGFloat,
        pageWidth: CGFloat,
        pageHeight: CGFloat,
        margin: CGFloat,
        ctx: UIGraphicsPDFRendererContext
    ) {
        // Section divider line
        let divPath = UIBezierPath()
        divPath.move(to: CGPoint(x: margin, y: y))
        divPath.addLine(to: CGPoint(x: pageWidth - margin, y: y))
        UIColor.lightGray.withAlphaComponent(0.6).setStroke()
        divPath.lineWidth = 0.5
        divPath.stroke()
        y += 6

        // Section title
        drawText("Pitch Counts", x: margin, y: y,
                 font: .boldSystemFont(ofSize: 11), color: .black)
        y += 14

        // Split rows into left and right halves
        let half = Int(ceil(Double(rows.count) / 2.0))
        let leftRows  = Array(rows.prefix(half))
        let rightRows = Array(rows.dropFirst(half))

        // Two mini-tables side by side with a gap between them
        let gap: CGFloat = 12
        let tableWidth = pageWidth - margin * 2
        let miniWidth = (tableWidth - gap) / 2

        // Column proportions within each mini-table
        // Player | Thrown | Avail | Rest | Status
        let pct: (player: CGFloat, thrown: CGFloat, avail: CGFloat, rest: CGFloat, status: CGFloat) =
            (0.32, 0.13, 0.13, 0.12, 0.30)

        let rowHeight: CGFloat = 20
        let headerBg  = UIColor(red: 0.90, green: 0.90, blue: 0.90, alpha: 1.0)
        let evenBg    = UIColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1.0)

        // Helper: draw one mini-table starting at (originX, originY)
        // Returns the Y of the bottom of the last row.
        func drawMiniTable(originX: CGFloat, originY: CGFloat, tableRows: [PitchingGuideSummaryRow]) -> CGFloat {
            var ty = originY
            let w = miniWidth

            // Column x positions
            let xPlayer = originX
            let xThrown = originX + w * pct.player
            let xAvail  = xThrown + w * pct.thrown
            let xRest   = xAvail  + w * pct.avail
            let xStatus = xRest   + w * pct.rest

            // Column widths
            let wPlayer = w * pct.player
            let wThrown = w * pct.thrown
            let wAvail  = w * pct.avail
            let wRest   = w * pct.rest

            // Header row
            let hRect = CGRect(x: originX, y: ty, width: w, height: rowHeight)
            headerBg.setFill()
            UIBezierPath(roundedRect: hRect, cornerRadius: 3).fill()

            drawText("Player",
                     x: xPlayer + 4, y: ty + 5,
                     font: .boldSystemFont(ofSize: 8), color: .darkGray)
            drawCenteredText("Thrown",
                             in: CGRect(x: xThrown, y: ty, width: wThrown, height: rowHeight),
                             font: .boldSystemFont(ofSize: 8), color: .darkGray)
            drawCenteredText("Avail",
                             in: CGRect(x: xAvail, y: ty, width: wAvail, height: rowHeight),
                             font: .boldSystemFont(ofSize: 8), color: .darkGray)
            drawCenteredText("Rest",
                             in: CGRect(x: xRest, y: ty, width: wRest, height: rowHeight),
                             font: .boldSystemFont(ofSize: 8), color: .darkGray)
            drawText("Status",
                     x: xStatus + 4, y: ty + 5,
                     font: .boldSystemFont(ofSize: 8), color: .darkGray)
            ty += rowHeight + 2

            // Data rows
            for (idx, row) in tableRows.enumerated() {
                let rowBg = idx % 2 == 0 ? evenBg : UIColor.white
                let rRect = CGRect(x: originX, y: ty, width: w, height: rowHeight)
                rowBg.setFill()
                UIBezierPath(roundedRect: rRect, cornerRadius: 3).fill()

                // Available color
                let availColor: UIColor
                switch row.status {
                case .eligible:
                    availColor = UIColor(red: 0.13, green: 0.55, blue: 0.13, alpha: 1.0)
                case .limited:
                    availColor = UIColor(red: 0.80, green: 0.50, blue: 0.0,  alpha: 1.0)
                case .mustRest, .unknownAge:
                    availColor = UIColor(red: 0.75, green: 0.10, blue: 0.10, alpha: 1.0)
                }

                // Player name — truncate to first name if too wide
                let nameFont = UIFont.systemFont(ofSize: 9)
                let fullName = row.player.displayName
                let nameAttrs: [NSAttributedString.Key: Any] = [.font: nameFont, .foregroundColor: UIColor.black]
                let nw = (fullName as NSString).size(withAttributes: nameAttrs).width
                let nameText = nw > wPlayer - 8 ? row.player.firstName : fullName
                drawText(nameText, x: xPlayer + 4, y: ty + 5,
                         font: nameFont, color: .black)

                // Thrown
                drawCenteredText("\(row.pitchesInWindow)",
                                 in: CGRect(x: xThrown, y: ty, width: wThrown, height: rowHeight),
                                 font: .systemFont(ofSize: 9), color: .darkGray)

                // Available
                let availText = row.status.isRestricted ? "—" : (row.dailyMax > 0 ? "\(row.available)" : "—")
                drawCenteredText(availText,
                                 in: CGRect(x: xAvail, y: ty, width: wAvail, height: rowHeight),
                                 font: .boldSystemFont(ofSize: 9), color: availColor)

                // Rest owed from their last outing. Only meaningful while they're
                // still inside it — once the days have elapsed the status flips to
                // eligible and the number is noise, so it's suppressed there.
                let restText = row.status.isRestricted && row.restDaysRequired > 0
                    ? "\(row.restDaysRequired)d"
                    : "—"
                drawCenteredText(restText,
                                 in: CGRect(x: xRest, y: ty, width: wRest, height: rowHeight),
                                 font: .systemFont(ofSize: 9), color: .darkGray)

                // Status
                drawText(row.status.displayLabel,
                         x: xStatus + 4, y: ty + 5,
                         font: .systemFont(ofSize: 8), color: .darkGray)

                ty += rowHeight + 1
            }
            return ty
        }

        let leftOriginX  = margin
        let rightOriginX = margin + miniWidth + gap

        let leftBottom  = drawMiniTable(originX: leftOriginX,  originY: y, tableRows: leftRows)
        let rightBottom = drawMiniTable(originX: rightOriginX, originY: y, tableRows: rightRows)

        // Advance y past whichever column is taller
        y = max(leftBottom, rightBottom)

        y += 4
        drawText("Available is the lower of the daily max and pitches remaining in the current weekly window. Rest is days still owed from the last outing.",
                 x: margin, y: y,
                 font: .italicSystemFont(ofSize: 7), color: .gray)
        y += 10
    }

    // MARK: - Helpers

    @discardableResult
    private static func drawHeader(title: String, lineup: Lineup, pageWidth: CGFloat, margin: CGFloat, y: CGFloat, teamName: String = "", teamColor: Color = .blue) -> CGFloat {
        var currentY = y

        // Title bar
        let titleRect = CGRect(x: margin, y: currentY, width: pageWidth - margin * 2, height: 40)
        UIColor(teamColor).setFill()
        UIBezierPath(roundedRect: titleRect, cornerRadius: 6).fill()

        let headerLabel = teamName.isEmpty ? "Lineup Builder" : teamName
        drawText(headerLabel, x: margin + 12, y: currentY + 10,
                 font: .boldSystemFont(ofSize: 16), color: .white)
        drawText(title, x: pageWidth - margin - 120, y: currentY + 10,
                 font: .systemFont(ofSize: 14), color: UIColor.white.withAlphaComponent(0.85))

        currentY += 50

        // Game info
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        let dateStr = formatter.string(from: lineup.gameDate)
        let opponent = lineup.opponent.isEmpty ? "TBD" : lineup.opponent

        drawText("Date: \(dateStr)", x: margin, y: currentY,
                 font: .systemFont(ofSize: 12), color: .darkGray)
        drawText("vs. \(opponent)", x: pageWidth / 2, y: currentY,
                 font: .boldSystemFont(ofSize: 12), color: .black)

        return currentY + 20
    }

    private static func drawText(_ text: String, x: CGFloat, y: CGFloat, font: UIFont, color: UIColor) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        text.draw(at: CGPoint(x: x, y: y), withAttributes: attrs)
    }

    /// Draws text centered both horizontally and vertically within the given rect.
    private static func drawCenteredText(_ text: String, in rect: CGRect, font: UIFont, color: UIColor) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let textSize = (text as NSString).size(withAttributes: attrs)
        let x = rect.midX - textSize.width / 2
        let y = rect.midY - textSize.height / 2
        text.draw(at: CGPoint(x: x, y: y), withAttributes: attrs)
    }

    private static func drawFooter(pageWidth: CGFloat, pageHeight: CGFloat, margin: CGFloat) {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        let timestamp = "Generated: \(formatter.string(from: Date()))"

        drawText(timestamp, x: margin, y: pageHeight - margin + 10,
                 font: .systemFont(ofSize: 9), color: .lightGray)
        drawText("Stack the Lineup", x: pageWidth - margin - 90, y: pageHeight - margin + 10,
                 font: .systemFont(ofSize: 9), color: .lightGray)
    }
}
