// The two printouts, drawn as real PDFs: a coordinate-for-coordinate port of
// PDFGenerator.swift (US Letter, 612 x 792 pt, 48 pt margins), so a coach
// gets the same page from the web as from the iPhone app.
//
// Fonts are the PDF standard Helvetica family (no embedding, tiny files); iOS
// uses the system font, so glyphs differ slightly but every box, row, column
// and number is placed the same. UIKit draws text from its top-left corner;
// PDF from the baseline, so text is placed at top + ASCENT * size.
//
// Only WinAnsi characters can be drawn with the standard fonts. Accented Latin
// names are fine; anything else (e.g. emoji in a name) is replaced with "?"
// rather than failing the whole printout.

import { PDFDocument, rgb, StandardFonts, type PDFFont, type PDFPage, type RGB } from 'pdf-lib';

import type { GameLog, Lineup, PitchingConfig, Player } from '@/core/model';
import { blocksAssignment, coachesGuideSummary, type PitchEligibilityStatus, type PitchingSummaryRow } from '@/core/pitching';

const PAGE_W = 612;
const PAGE_H = 792;
const MARGIN = 48;
const ASCENT = 0.93;          // top-of-line to baseline, as a fraction of size
const LINE = 1.2;             // line height, as a fraction of size

const gray = (v: number) => rgb(v, v, v);
const BLACK = gray(0);
const DARK_GRAY = gray(1 / 3);      // UIColor.darkGray
const GRAY = gray(0.5);             // UIColor.gray
const LIGHT_GRAY = gray(2 / 3);     // UIColor.lightGray
const SYSTEM_GRAY = rgb(0.557, 0.557, 0.576);
const ROW_EVEN = gray(0.95);
const HEADER_BG = gray(0.9);
const WHITE = gray(1);

export interface PrintInput {
  lineup: Lineup;
  players: Player[];
  teamName: string;
  /** "RRGGBB" */
  teamColorHex: string;
  gameLogs: GameLog[];
  pitchingConfig: PitchingConfig;
  /** For the footer; defaults to now. */
  generatedAt?: Date;
}

interface Fonts { regular: PDFFont; bold: PDFFont; italic: PDFFont }

class Canvas {
  page!: PDFPage;
  constructor(private doc: PDFDocument, readonly f: Fonts) {}

  newPage() { this.page = this.doc.addPage([PAGE_W, PAGE_H]); }

  text(s: string, x: number, top: number, size: number, font: PDFFont, color: RGB, opacity = 1) {
    this.page.drawText(safe(s, font), { x, y: PAGE_H - (top + ASCENT * size), size, font, color, opacity });
  }

  centered(s: string, rx: number, ry: number, rw: number, rh: number, size: number, font: PDFFont, color: RGB) {
    const t = safe(s, font);
    const w = font.widthOfTextAtSize(t, size);
    const top = ry + rh / 2 - (LINE * size) / 2;
    this.text(t, rx + rw / 2 - w / 2, top, size, font, color);
  }

  width(s: string, size: number, font: PDFFont) { return font.widthOfTextAtSize(safe(s, font), size); }

  roundedRect(x: number, top: number, w: number, h: number, r: number, color: RGB) {
    const path = `M ${r} 0 H ${w - r} A ${r} ${r} 0 0 1 ${w} ${r} V ${h - r} A ${r} ${r} 0 0 1 ${w - r} ${h} `
      + `H ${r} A ${r} ${r} 0 0 1 0 ${h - r} V ${r} A ${r} ${r} 0 0 1 ${r} 0 Z`;
    this.page.drawSvgPath(path, { x, y: PAGE_H - top, color, borderWidth: 0 });
  }

  line(x1: number, y: number, x2: number, color: RGB, thickness = 1, opacity = 1) {
    this.page.drawLine({ start: { x: x1, y: PAGE_H - y }, end: { x: x2, y: PAGE_H - y }, color, thickness, opacity });
  }
}

/** Replaces characters the standard fonts can't draw. */
function safe(s: string, font: PDFFont): string {
  const chars = new Set(font.getCharacterSet());
  return [...s].map((ch) => (chars.has(ch.codePointAt(0)!) ? ch : '?')).join('');
}

async function newDoc(title: string): Promise<{ doc: PDFDocument; c: Canvas }> {
  const doc = await PDFDocument.create();
  doc.setTitle(title);
  doc.setCreator('Stack the Lineup');
  doc.setProducer('Stack the Lineup (web)');
  const f = {
    regular: await doc.embedFont(StandardFonts.Helvetica),
    bold: await doc.embedFont(StandardFonts.HelveticaBold),
    italic: await doc.embedFont(StandardFonts.HelveticaOblique),
  };
  return { doc, c: new Canvas(doc, f) };
}

const hexColor = (hex: string): RGB => {
  const n = /^[0-9a-f]{6}$/i.test(hex) ? parseInt(hex, 16) : 0x0000ff;
  return rgb(((n >> 16) & 255) / 255, ((n >> 8) & 255) / 255, (n & 255) / 255);
};

const displayName = (p: Player) => `${p.firstName} ${p.lastName}`;

/** Batting order, active players only (iOS Lineup.orderedPlayers). */
export function orderedPlayers(lineup: Lineup, players: Player[]): Player[] {
  const absent = new Set(lineup.absentPlayerIDs);
  return lineup.battingOrder
    .filter((id) => !absent.has(id))
    .map((id) => players.find((p) => p.id === id))
    .filter((p): p is Player => !!p);
}

function header(c: Canvas, title: string, input: PrintInput, top: number): number {
  let y = top;
  c.roundedRect(MARGIN, y, PAGE_W - MARGIN * 2, 40, 6, hexColor(input.teamColorHex));
  c.text(input.teamName || 'Stack the Lineup', MARGIN + 12, y + 10, 16, c.f.bold, WHITE);
  c.text(title, PAGE_W - MARGIN - 120, y + 10, 14, c.f.regular, WHITE, 0.85);
  y += 50;
  const date = input.lineup.gameDate.toLocaleDateString(undefined, { year: 'numeric', month: 'long', day: 'numeric' });
  c.text(`Date: ${date}`, MARGIN, y, 12, c.f.regular, DARK_GRAY);
  c.text(`vs. ${input.lineup.opponent || 'TBD'}`, PAGE_W / 2, y, 12, c.f.bold, BLACK);
  return y + 20;
}

function footer(c: Canvas, generatedAt: Date) {
  const stamp = generatedAt.toLocaleString(undefined, { dateStyle: 'short', timeStyle: 'short' });
  c.text(`Generated: ${stamp}`, MARGIN, PAGE_H - MARGIN + 10, 9, c.f.regular, LIGHT_GRAY);
  c.text('Stack the Lineup', PAGE_W - MARGIN - 90, PAGE_H - MARGIN + 10, 9, c.f.regular, LIGHT_GRAY);
}

// MARK: - Batting order

export async function battingOrderPdf(input: PrintInput): Promise<Uint8Array> {
  const { doc, c } = await newDoc('Batting Order');
  c.newPage();
  let y = header(c, 'Batting Order', input, MARGIN) + 24;

  const col2 = MARGIN + 80;
  const col3 = PAGE_W - MARGIN - 60;
  c.text('#', MARGIN, y, 11, c.f.bold, DARK_GRAY);
  c.text('Player', col2, y, 11, c.f.bold, DARK_GRAY);
  c.text('Jersey', col3, y, 11, c.f.bold, DARK_GRAY);
  y += 16;
  c.line(MARGIN, y, PAGE_W - MARGIN, LIGHT_GRAY);
  y += 12;

  const ordered = orderedPlayers(input.lineup, input.players);
  ordered.forEach((p, i) => {
    c.roundedRect(MARGIN, y - 4, PAGE_W - MARGIN * 2, 28, 4, i % 2 === 0 ? ROW_EVEN : WHITE);
    c.text(`${i + 1}.`, MARGIN + 8, y + 4, 14, c.f.bold, BLACK);
    c.text(displayName(p), col2, y + 4, 14, c.f.regular, BLACK);
    c.text(p.number ? `#${p.number}` : '—', col3, y + 4, 14, c.f.regular, DARK_GRAY);
    y += 32;
  });

  y += 12;
  c.text(`Total Players: ${ordered.length}`, MARGIN, y, 11, c.f.italic, GRAY);
  footer(c, input.generatedAt ?? new Date());
  return doc.save();
}

// MARK: - Coaches guide

export async function coachesGuidePdf(input: PrintInput): Promise<Uint8Array> {
  const { doc, c } = await newDoc('Coaches Guide');
  const generatedAt = input.generatedAt ?? new Date();
  const { lineup } = input;
  c.newPage();
  let y = header(c, 'Coaches Guide', input, MARGIN) + 20;

  const ordered = orderedPlayers(lineup, input.players);
  const rows = ordered.length ? ordered : input.players;

  const gridLeft = MARGIN + 120;
  const gridRight = PAGE_W - MARGIN;
  const colWidth = (gridRight - gridLeft) / lineup.innings.length;
  const rowHeight = 26;

  c.text('Player', MARGIN, y + 6, 10, c.f.bold, DARK_GRAY);
  lineup.innings.forEach((_, i) => {
    const x = gridLeft + i * colWidth;
    c.roundedRect(x, y, colWidth - 2, rowHeight, 3, HEADER_BG);
    c.centered(`Inn ${i + 1}`, x, y, colWidth - 2, rowHeight, 10, c.f.bold, BLACK);
  });
  y += rowHeight + 4;

  rows.forEach((p, r) => {
    c.roundedRect(MARGIN, y, PAGE_W - MARGIN * 2, rowHeight, 3, r % 2 === 0 ? ROW_EVEN : WHITE);
    const order = ordered.findIndex((x) => x.id === p.id);
    c.text(order >= 0 ? `${order + 1}.` : '—', MARGIN + 4, y + 7, 10, c.f.bold, DARK_GRAY);
    c.text(displayName(p), MARGIN + 22, y + 7, 10, c.f.regular, BLACK);
    lineup.innings.forEach((inn, i) => {
      const x = gridLeft + i * colWidth + 1;
      const pos = inn.assignments[p.id];
      if (pos) c.centered(pos, x, y + 2, colWidth - 3, rowHeight - 4, 10, c.f.bold, pos === 'ABS' ? SYSTEM_GRAY : BLACK);
      else c.centered('—', x, y + 2, colWidth - 3, rowHeight - 4, 10, c.f.regular, LIGHT_GRAY);
    });
    y += rowHeight + 2;
    if (y > PAGE_H - MARGIN - 80) {
      footer(c, generatedAt);
      c.newPage();
      y = MARGIN;
    }
  });

  // Pitch counts, as of the GAME date (matches the Pitching view for this game).
  const pitchRows = coachesGuideSummary(input.gameLogs, input.players, input.pitchingConfig, lineup.gameDate) ?? [];
  if (pitchRows.length) {
    const halfRows = Math.ceil(pitchRows.length / 2);
    const sectionHeight = 20 + 22 + halfRows * 21 + 20;
    if (PAGE_H - MARGIN - y < sectionHeight) {
      footer(c, generatedAt);
      c.newPage();
      y = MARGIN;
    } else {
      y += 16;
    }
    y = pitchCountSection(c, pitchRows, y);
  }

  footer(c, generatedAt);
  return doc.save();
}

/** iOS PitchEligibilityStatus.displayLabel ("Available Tue 9/29" uses EEE M/d). */
export function statusLabel(s: PitchEligibilityStatus): string {
  switch (s.kind) {
    case 'eligible': return 'Eligible';
    case 'limited': return 'Limited';
    case 'unknownAge': return 'Age not set';
    case 'mustRest': {
      const d = s.until;
      const day = d.toLocaleDateString('en-US', { weekday: 'short' });
      return `Available ${day} ${d.getMonth() + 1}/${d.getDate()}`;
    }
  }
}

function pitchCountSection(c: Canvas, rows: PitchingSummaryRow[], top: number): number {
  let y = top;
  c.line(MARGIN, y, PAGE_W - MARGIN, LIGHT_GRAY, 0.5, 0.6);
  y += 6;
  c.text('Pitch Counts', MARGIN, y, 11, c.f.bold, BLACK);
  y += 14;

  const half = Math.ceil(rows.length / 2);
  const gap = 12;
  const miniWidth = (PAGE_W - MARGIN * 2 - gap) / 2;
  const pct = { player: 0.32, thrown: 0.13, avail: 0.13, rest: 0.12 };
  const rowHeight = 20;

  const table = (originX: number, originY: number, tableRows: PitchingSummaryRow[]): number => {
    let ty = originY;
    const w = miniWidth;
    const xThrown = originX + w * pct.player;
    const xAvail = xThrown + w * pct.thrown;
    const xRest = xAvail + w * pct.avail;
    const xStatus = xRest + w * pct.rest;
    const [wPlayer, wThrown, wAvail, wRest] = [w * pct.player, w * pct.thrown, w * pct.avail, w * pct.rest];

    c.roundedRect(originX, ty, w, rowHeight, 3, HEADER_BG);
    c.text('Player', originX + 4, ty + 5, 8, c.f.bold, DARK_GRAY);
    c.centered('Thrown', xThrown, ty, wThrown, rowHeight, 8, c.f.bold, DARK_GRAY);
    c.centered('Avail', xAvail, ty, wAvail, rowHeight, 8, c.f.bold, DARK_GRAY);
    c.centered('Rest', xRest, ty, wRest, rowHeight, 8, c.f.bold, DARK_GRAY);
    c.text('Status', xStatus + 4, ty + 5, 8, c.f.bold, DARK_GRAY);
    ty += rowHeight + 2;

    tableRows.forEach((row, i) => {
      c.roundedRect(originX, ty, w, rowHeight, 3, i % 2 === 0 ? ROW_EVEN : WHITE);
      const restricted = blocksAssignment(row.status);
      const availColor = row.status.kind === 'eligible' ? rgb(0.13, 0.55, 0.13)
        : row.status.kind === 'limited' ? rgb(0.8, 0.5, 0) : rgb(0.75, 0.1, 0.1);
      const full = displayName(row.player);
      const name = c.width(full, 9, c.f.regular) > wPlayer - 8 ? row.player.firstName : full;
      c.text(name, originX + 4, ty + 5, 9, c.f.regular, BLACK);
      c.centered(String(row.pitchesInWindow), xThrown, ty, wThrown, rowHeight, 9, c.f.regular, DARK_GRAY);
      c.centered(restricted ? '—' : row.dailyMax > 0 ? String(row.available) : '—', xAvail, ty, wAvail, rowHeight, 9, c.f.bold, availColor);
      c.centered(restricted && row.restDaysRequired > 0 ? `${row.restDaysRequired}d` : '—', xRest, ty, wRest, rowHeight, 9, c.f.regular, DARK_GRAY);
      c.text(statusLabel(row.status), xStatus + 4, ty + 5, 8, c.f.regular, DARK_GRAY);
      ty += rowHeight + 1;
    });
    return ty;
  };

  const leftBottom = table(MARGIN, y, rows.slice(0, half));
  const rightBottom = table(MARGIN + miniWidth + gap, y, rows.slice(half));
  y = Math.max(leftBottom, rightBottom) + 4;
  c.text('Available is the lower of the daily max and pitches remaining in the current weekly window. Rest is days still owed from the last outing.',
    MARGIN, y, 7, c.f.italic, GRAY);
  return y + 10;
}

/** "BattingOrder_9-27-26.pdf" / "CoachesGuide_9-27-26.pdf", as iOS names them. */
export function pdfFilename(kind: 'battingOrder' | 'coachesGuide', gameDate: Date): string {
  const d = `${gameDate.getMonth() + 1}-${gameDate.getDate()}-${String(gameDate.getFullYear()).slice(-2)}`;
  return `${kind === 'battingOrder' ? 'BattingOrder' : 'CoachesGuide'}_${d}.pdf`;
}
