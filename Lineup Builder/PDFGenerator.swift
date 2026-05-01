import UIKit
import PDFKit
import SwiftUI

class PDFGenerator {

    static func generate(type: PDFType, lineup: Lineup, players: [Player], teamName: String = "", teamColor: Color = .blue, showFairPlayRules: Bool = true) -> PDFDocument {
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
                                  pageWidth: pageWidth, pageHeight: pageHeight, margin: margin, teamName: teamName, teamColor: teamColor, showFairPlayRules: showFairPlayRules)
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

    private static func drawCoachesGuide(ctx: UIGraphicsPDFRendererContext, lineup: Lineup, players: [Player],
                                          pageWidth: CGFloat, pageHeight: CGFloat, margin: CGFloat, teamName: String = "", teamColor: Color = .blue, showFairPlayRules: Bool = true) {
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

        drawFooter(pageWidth: pageWidth, pageHeight: pageHeight, margin: margin)
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

    private static func drawColoredDot(color: UIColor, x: CGFloat, y: CGFloat) {
        let dotPath = UIBezierPath(ovalIn: CGRect(x: x, y: y, width: 8, height: 8))
        color.setFill()
        dotPath.fill()
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
