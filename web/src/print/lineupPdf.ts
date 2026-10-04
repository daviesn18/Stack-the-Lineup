// The two printouts, drawn as real PDFs from the Coaches Guide redesign
// handoff (ink-saver version, black-and-white friendly). PDFGenerator.swift
// draws the same pages on iOS: US Letter, 612 x 792 pt; every handoff px value
// is x0.75 to get points.
//
// Fonts are the PDF standard Helvetica family (no embedding, tiny files); iOS
// uses the system font, so glyphs differ slightly but every box, row, column
// and number is placed the same. Heavy (800) and semibold (600) both map to
// Helvetica-Bold, medium (500) to Helvetica. Helvetica digits are already
// tabular. Text is placed by the top of its line box; PDF draws from the
// baseline, so it lands at top + ASCENT * size.
//
// Only WinAnsi characters can be drawn with the standard fonts. Accented Latin
// names are fine; anything else (e.g. emoji in a name) is replaced with "?"
// rather than failing the whole printout.

import {
  PDFDocument, rgb, setCharacterSpacing, StandardFonts, type PDFFont, type PDFPage, type RGB,
} from 'pdf-lib';

import { activeFieldPositions, activePlayers } from '@/core/fairPlay';
import { gridNames } from '@/core/lineupOps';
import {
  defaultFairPlayConfig, isOutfield, type FairPlayConfig, type FieldPosition, type GameLog, type Lineup,
  type PitchingConfig, type Player,
} from '@/core/model';
import { blocksAssignment, coachesGuideSummary, type PitchEligibilityStatus, type PitchingSummaryRow } from '@/core/pitching';

const PAGE_W = 612;
const PAGE_H = 792;
const M_TOP = 33;
const M_SIDE = 36;
const M_BOTTOM = 27;
const CONTENT_W = PAGE_W - M_SIDE * 2;
const ASCENT = 0.93;          // top-of-line to baseline, as a fraction of size
const LINE = 1.2;             // line height, as a fraction of size

const hex = (n: number) => rgb(((n >> 16) & 255) / 255, ((n >> 8) & 255) / 255, (n & 255) / 255);
/** rgba(60,60,67,a) over white. */
const secondary = (a: number) => rgb((255 - a * 195) / 255, (255 - a * 195) / 255, (255 - a * 188) / 255);
const BLACK = rgb(0, 0, 0);
const WHITE = rgb(1, 1, 1);
const BLUE = hex(0x007aff);
const GROUPED = hex(0xf2f2f7);
const SEPARATOR = hex(0xc6c6c8);
const HAIRLINE = hex(0xe5e5ea);

export interface PrintInput {
  lineup: Lineup;
  players: Player[];
  teamName: string;
  /** "RRGGBB". Not drawn since the redesign; kept so callers don't change. */
  teamColorHex: string;
  gameLogs: GameLog[];
  pitchingConfig: PitchingConfig;
  /** Which field positions the guide lists (no P/C, four outfielders). Defaults to the standard nine. */
  fairPlayConfig?: FairPlayConfig;
  /** For the footer; defaults to now. */
  generatedAt?: Date;
}

interface Fonts { regular: PDFFont; bold: PDFFont }
interface TextOpts { tracking?: number; align?: 'left' | 'right' | 'center'; maxWidth?: number }

class Canvas {
  page!: PDFPage;
  constructor(private doc: PDFDocument, readonly f: Fonts) {}

  newPage() { this.page = this.doc.addPage([PAGE_W, PAGE_H]); }

  /** Width of `s` with `tracking` (em) after every glyph, as CSS letter-spacing. */
  width(s: string, size: number, font: PDFFont, tracking = 0) {
    const t = safe(s, font);
    return font.widthOfTextAtSize(t, size) + [...t].length * tracking * size;
  }

  /** `s` cut to fit `maxWidth` with a trailing ellipsis. */
  fit(s: string, size: number, font: PDFFont, maxWidth: number, tracking = 0) {
    if (this.width(s, size, font, tracking) <= maxWidth) return s;
    let t = s;
    while (t.length > 1 && this.width(`${t}…`, size, font, tracking) > maxWidth) t = t.slice(0, -1);
    return `${t.trimEnd()}…`;
  }

  /** Text whose line box starts at `top`; `x` is the left, right or center edge per `align`. */
  text(s: string, x: number, top: number, size: number, font: PDFFont, color: RGB, o: TextOpts = {}) {
    const tracking = o.tracking ?? 0;
    const t = safe(o.maxWidth ? this.fit(s, size, font, o.maxWidth, tracking) : s, font);
    // Trailing tracking isn't ink, so alignment ignores it.
    const w = this.width(t, size, font, tracking) - tracking * size;
    const left = o.align === 'right' ? x - w : o.align === 'center' ? x - w / 2 : x;
    if (tracking) this.page.pushOperators(setCharacterSpacing(tracking * size));
    this.page.drawText(t, { x: left, y: PAGE_H - (top + ASCENT * size), size, font, color });
    if (tracking) this.page.pushOperators(setCharacterSpacing(0));
  }

  /** Text vertically centered in a box `h` tall starting at `top`. */
  textMid(s: string, x: number, top: number, h: number, size: number, font: PDFFont, color: RGB, o: TextOpts = {}) {
    this.text(s, x, top + h / 2 - (LINE * size) / 2, size, font, color, o);
  }

  rect(x: number, top: number, w: number, h: number, color: RGB) {
    this.page.drawRectangle({ x, y: PAGE_H - top - h, width: w, height: h, color });
  }

  roundedRect(x: number, top: number, w: number, h: number, r: number, o: { fill?: RGB; stroke?: RGB; strokeWidth?: number }) {
    const path = `M ${r} 0 H ${w - r} A ${r} ${r} 0 0 1 ${w} ${r} V ${h - r} A ${r} ${r} 0 0 1 ${w - r} ${h} `
      + `H ${r} A ${r} ${r} 0 0 1 0 ${h - r} V ${r} A ${r} ${r} 0 0 1 ${r} 0 Z`;
    this.page.drawSvgPath(path, {
      x, y: PAGE_H - top, color: o.fill, borderColor: o.stroke, borderWidth: o.stroke ? o.strokeWidth ?? 1 : 0,
    });
  }

  hLine(x1: number, x2: number, y: number, color: RGB, thickness: number) {
    this.page.drawLine({ start: { x: x1, y: PAGE_H - y }, end: { x: x2, y: PAGE_H - y }, color, thickness });
  }

  vLine(x: number, top: number, bottom: number, color: RGB, thickness: number) {
    this.page.drawLine({ start: { x, y: PAGE_H - top }, end: { x, y: PAGE_H - bottom }, color, thickness });
  }

  dot(cx: number, cy: number, d: number, color: RGB) {
    this.page.drawCircle({ x: cx, y: PAGE_H - cy, size: d / 2, color });
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
  };
  return { doc, c: new Canvas(doc, f) };
}

const displayName = (p: Player) => `${p.firstName} ${p.lastName}`.trim();

/** Batting order, active players only (iOS Lineup.orderedPlayers). */
export function orderedPlayers(lineup: Lineup, players: Player[]): Player[] {
  const absent = new Set(lineup.absentPlayerIDs);
  return lineup.battingOrder
    .filter((id) => !absent.has(id))
    .map((id) => players.find((p) => p.id === id))
    .filter((p): p is Player => !!p);
}

// MARK: - Shared header and footer

/** Eyebrow + team name on the left, opponent + date on the right, over a 1.5 pt black rule. Returns the rule's bottom. */
function header(c: Canvas, eyebrow: string, input: PrintInput): number {
  const leftH = 8.25 * LINE + 3 + 21 * 1.05;
  const rightH = 15 * LINE + 2.25 + 9.75 * LINE;
  const bottom = M_TOP + Math.max(leftH, rightH);
  const right = PAGE_W - M_SIDE;

  const opponent = `vs. ${input.lineup.opponent || 'TBD'}`;
  const date = input.lineup.gameDate.toLocaleDateString('en-US', { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric' });
  const rightW = Math.max(c.width(opponent, 15, c.f.bold, -0.01), c.width(date, 9.75, c.f.regular));
  c.text(opponent, right, bottom - rightH, 15, c.f.bold, BLACK, { tracking: -0.01, align: 'right', maxWidth: CONTENT_W / 2 });
  c.text(date, right, bottom - 9.75 * LINE, 9.75, c.f.regular, secondary(0.75), { align: 'right' });

  c.text(eyebrow.toUpperCase(), M_SIDE, bottom - leftH, 8.25, c.f.bold, BLUE, { tracking: 0.12 });
  // The 1.05 line box is tighter than LINE; center the glyphs in it.
  c.text(input.teamName || 'Stack the Lineup', M_SIDE, bottom - 21 * 1.05 - (LINE - 1.05) * 21 / 2, 21, c.f.bold, BLACK,
    { tracking: -0.02, maxWidth: CONTENT_W - Math.min(rightW, CONTENT_W / 2) - 12 });

  const ruleTop = bottom + 10.5;
  c.rect(M_SIDE, ruleTop, CONTENT_W, 1.5, BLACK);
  return ruleTop + 1.5;
}

const FOOTER_TEXT_TOP = PAGE_H - M_BOTTOM - 7.5 * LINE;
const FOOTER_RULE = FOOTER_TEXT_TOP - 7.5;
/** Lowest y page content may reach, leaving room above the footer rule. */
const CONTENT_BOTTOM = FOOTER_RULE - 12;

function footer(c: Canvas, generatedAt: Date) {
  const stamp = generatedAt.toLocaleString('en-US', { dateStyle: 'short', timeStyle: 'short' });
  c.hLine(M_SIDE, PAGE_W - M_SIDE, FOOTER_RULE, HAIRLINE, 0.75);
  c.text(`Generated ${stamp}`, M_SIDE, FOOTER_TEXT_TOP, 7.5, c.f.regular, secondary(0.6));
  c.text('Stack the Lineup', PAGE_W - M_SIDE, FOOTER_TEXT_TOP, 7.5, c.f.bold, secondary(0.6), { align: 'right' });
}

/** Ink-saver position badge: white, black text, 1.125 pt black border. */
function badge(c: Canvas, label: string, x: number, top: number) {
  const inset = 1.125 / 2;   // CSS border-box: the border sits inside the 22.5 x 16.5 box
  c.roundedRect(x + inset, top + inset, 22.5 - 1.125, 16.5 - 1.125, 4.5 - inset, { fill: WHITE, stroke: BLACK, strokeWidth: 1.125 });
  c.textMid(label, x + 22.5 / 2, top, 16.5, 9, c.f.bold, BLACK, { align: 'center' });
}

// MARK: - Batting order

export async function battingOrderPdf(input: PrintInput): Promise<Uint8Array> {
  const { doc, c } = await newDoc(pdfTitle('battingOrder', input.teamName, input.lineup.opponent, input.lineup.gameDate));
  const generatedAt = input.generatedAt ?? new Date();
  c.newPage();
  const ordered = orderedPlayers(input.lineup, input.players);

  const numW = 48;
  const jerseyW = 72;
  const playerX = M_SIDE + numW;
  const jerseyX = PAGE_W - M_SIDE - jerseyW;
  const headH = 7.5 * 2 + 7.5 * LINE;
  const countH = 7.5 + 8.25 * LINE;

  let top = header(c, 'Batting Order', input) + 15;
  // Rows shrink from 30.75 to 24 to fit; past that the list continues on another page.
  const room = CONTENT_BOTTOM - top - headH - countH;
  const rowH = Math.max(24, Math.min(30.75, room / Math.max(1, ordered.length)));
  const nameSize = rowH < 27 ? 11.25 : 12.75;

  const table = (rows: Player[], first: number) => {
    const h = headH + rows.length * rowH;
    // Grouped fill clipped to the corners; white rows painted over it (square is fine: the page is white).
    c.roundedRect(M_SIDE, top, CONTENT_W, h, 6, { fill: GROUPED });
    rows.forEach((p, k) => {
      const i = first + k;
      const y = top + headH + k * rowH;
      if (i % 2 === 0) c.rect(M_SIDE, y, CONTENT_W, rowH, WHITE);
      if (k > 0) c.hLine(M_SIDE, PAGE_W - M_SIDE, y, HAIRLINE, 0.75);
      c.textMid(String(i + 1), M_SIDE + numW / 2, y, rowH, 15, c.f.bold, BLACK, { align: 'center' });
      c.textMid(displayName(p), playerX + 10.5, y, rowH, nameSize, c.f.bold, BLACK,
        { tracking: -0.01, maxWidth: jerseyX - playerX - 21 });
      if (p.number) c.textMid(p.number, jerseyX + jerseyW / 2, y, rowH, 11.25, c.f.bold, BLACK, { align: 'center', maxWidth: jerseyW - 12 });
    });
    c.hLine(M_SIDE, PAGE_W - M_SIDE, top + headH, SEPARATOR, 0.75);
    c.vLine(playerX, top, top + h, HAIRLINE, 0.75);
    c.vLine(jerseyX, top, top + h, HAIRLINE, 0.75);
    const label = { size: 7.5, font: c.f.bold, color: secondary(0.7), tracking: 0.08 };
    c.textMid('#', M_SIDE + numW / 2, top, headH, label.size, label.font, label.color, { align: 'center', tracking: label.tracking });
    c.textMid('PLAYER', playerX + 10.5, top, headH, label.size, label.font, label.color, { tracking: label.tracking });
    c.textMid('JERSEY', jerseyX + jerseyW / 2, top, headH, label.size, label.font, label.color, { align: 'center', tracking: label.tracking });
    c.roundedRect(M_SIDE, top, CONTENT_W, h, 6, { stroke: SEPARATOR, strokeWidth: 0.75 });
    top += h;
  };

  let i = 0;
  do {
    const fits = Math.max(1, Math.floor((CONTENT_BOTTOM - top - headH - countH) / rowH));
    const rows = ordered.slice(i, i + fits);
    table(rows, i);
    i += rows.length;
    if (i < ordered.length) {
      footer(c, generatedAt);
      c.newPage();
      top = M_TOP;
    }
  } while (i < ordered.length);

  c.text(`${ordered.length} ${ordered.length === 1 ? 'player' : 'players'}`, M_SIDE, top + 7.5, 8.25, c.f.regular, secondary(0.7));
  footer(c, generatedAt);
  return doc.save();
}

// MARK: - Coaches guide

const GRID_HEAD_H = 4.5 + 6.75 * LINE + 13.5 * 1.1 + 4.5;
const POS_ROW_H = 25.5;
const BADGE_COL = 48;

export async function coachesGuidePdf(input: PrintInput): Promise<Uint8Array> {
  const { doc, c } = await newDoc(pdfTitle('coachesGuide', input.teamName, input.lineup.opponent, input.lineup.gameDate));
  const generatedAt = input.generatedAt ?? new Date();
  const { lineup } = input;
  c.newPage();
  let top = header(c, 'Coaches Guide', input) + 15;

  // By position: a row per field position, then Bench; each cell names who is there that inning.
  const positions = activeFieldPositions(input.fairPlayConfig ?? defaultFairPlayConfig());
  const active = activePlayers(lineup, input.players);
  const names = gridNames(active);
  const nameOf = (p: Player) => names.get(p.id) ?? p.firstName;
  const ordered = orderedPlayers(lineup, input.players);
  const sitOrder = [...ordered, ...active.filter((p) => !ordered.includes(p))];
  const sitters = lineup.innings.map((inn) => sitOrder.filter((p) => { const x = inn.assignments[p.id]; return x === undefined || x === 'Bench'; }));
  const most = Math.max(0, ...sitters.map((s) => s.length));

  // Pitch counts, as of the GAME date (matches the Pitching view for this game). Hidden with no pitchers.
  const pitchRows = coachesGuideSummary(input.gameLogs, input.players, input.pitchingConfig, lineup.gameDate) ?? [];

  // Overflow, per the handoff: tighten the bench lines, then the pitch rows; then move pitch counts to page 2.
  const benchH = (line: number) => Math.max(7.5 * 2 + 16.5, 6 * 2 + most * line);
  const gridH = (line: number) => GRID_HEAD_H + positions.length * POS_ROW_H + 0.75 + benchH(line);
  const pitchH = (row: number) => (pitchRows.length ? 19.5 + PITCH_TITLE_H + 6 + PITCH_HEAD_H + Math.ceil(pitchRows.length / 2) * row : 0);
  const room = CONTENT_BOTTOM - top;
  let benchLine = 12.75;
  let pitchRow = 18.75;
  if (gridH(benchLine) + pitchH(pitchRow) > room) benchLine = 11.25;
  if (gridH(benchLine) + pitchH(pitchRow) > room) pitchRow = 16.5;

  top = defenseGrid(c, {
    top, innings: lineup.innings.length, positions, benchLine, benchH: benchH(benchLine), sitters, nameOf,
    holder: (i, pos) => {
      const inn = lineup.innings[i];
      return active.find((p) => inn.assignments[p.id] === pos);
    },
  });

  if (pitchRows.length) {
    if (top + pitchH(pitchRow) > CONTENT_BOTTOM) {
      footer(c, generatedAt);
      c.newPage();
      top = M_TOP - 19.5;
    }
    pitchCounts(c, pitchRows, top + 19.5, pitchRow);
  }

  footer(c, generatedAt);
  return doc.save();
}

function defenseGrid(c: Canvas, g: {
  top: number; innings: number; positions: FieldPosition[]; benchLine: number; benchH: number;
  sitters: Player[][]; nameOf: (p: Player) => string; holder: (inning: number, pos: FieldPosition) => Player | undefined;
}): number {
  const { top, innings } = g;
  const colW = (CONTENT_W - BADGE_COL) / innings;
  const colX = (i: number) => M_SIDE + BADGE_COL + i * colW;
  const nameSize = innings >= 7 ? 9.75 : 10.5;
  const rowsTop = top + GRID_HEAD_H;
  const firstOutfield = g.positions.findIndex(isOutfield);
  const rowTop = (r: number) => rowsTop + r * POS_ROW_H + (firstOutfield > 0 && r >= firstOutfield ? 0.75 : 0);
  const benchTop = rowTop(g.positions.length);
  const bottom = benchTop + g.benchH;
  const h = bottom - top;

  // Fills: the grouped header and bench, the white body between. The container clips to its 6 pt corners.
  c.roundedRect(M_SIDE, top, CONTENT_W, h, 6, { fill: GROUPED });
  c.rect(M_SIDE, rowsTop, CONTENT_W, benchTop - rowsTop, WHITE);

  // Header row.
  c.text('POS', M_SIDE + 9, top + GRID_HEAD_H - 6 - 7.5 * LINE, 7.5, c.f.bold, secondary(0.7), { tracking: 0.08 });
  for (let i = 0; i < innings; i++) {
    c.text('INNING', colX(i) + 7.5, top + 4.5, 6.75, c.f.bold, secondary(0.6), { tracking: 0.08 });
    c.text(String(i + 1), colX(i) + 7.5, top + 4.5 + 6.75 * LINE + (1.1 - LINE) * 13.5 / 2, 13.5, c.f.bold, BLACK);
  }
  c.hLine(M_SIDE, PAGE_W - M_SIDE, rowsTop, SEPARATOR, 0.75);

  // Position rows: badge, then who plays there each inning.
  g.positions.forEach((pos, r) => {
    const y = rowTop(r);
    if (r > 0 && r !== firstOutfield) c.hLine(M_SIDE, PAGE_W - M_SIDE, y, HAIRLINE, 0.75);
    if (r > 0 && r === firstOutfield) c.hLine(M_SIDE, PAGE_W - M_SIDE, y, SEPARATOR, 1.5);
    badge(c, pos, M_SIDE + 9, y + (POS_ROW_H - 16.5) / 2);
    for (let i = 0; i < innings; i++) {
      const p = g.holder(i, pos);
      if (p) c.textMid(g.nameOf(p), colX(i) + 7.5, y, POS_ROW_H, nameSize, c.f.bold, BLACK, { tracking: -0.01, maxWidth: colW - 15 });
      else c.textMid('—', colX(i) + 7.5, y, POS_ROW_H, nameSize, c.f.regular, secondary(0.6));
    }
  });

  // Bench: everyone with no field spot that inning, in batting order, one name per line.
  c.hLine(M_SIDE, PAGE_W - M_SIDE, benchTop + 0.75, SEPARATOR, 1.5);
  badge(c, 'BN', M_SIDE + 9, benchTop + 1.5 + 7.5);
  g.sitters.forEach((list, i) => {
    list.forEach((p, k) => {
      const lineTop = benchTop + 1.5 + 6 + k * g.benchLine;
      c.textMid(g.nameOf(p), colX(i) + 7.5, lineTop, g.benchLine, 9, c.f.regular, secondary(0.85), { maxWidth: colW - 15 });
    });
  });

  for (let i = 0; i < innings; i++) c.vLine(colX(i), top, bottom, HAIRLINE, 0.75);
  c.roundedRect(M_SIDE, top, CONTENT_W, h, 6, { stroke: SEPARATOR, strokeWidth: 0.75 });
  return bottom;
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

const PITCH_TITLE_H = 12.75 * LINE;
const PITCH_HEAD_H = 7.1 * LINE + 3.75 + 1.125;

/** "Pitch counts" title, then two tables side by side (first half, rounded up, on the left). */
function pitchCounts(c: Canvas, rows: PitchingSummaryRow[], top: number, rowH: number) {
  c.text('Pitch counts', M_SIDE, top, 12.75, c.f.bold, BLACK, { tracking: -0.01 });
  // Shares the title's baseline.
  c.text('Avail: pitches left today. Rest: days off still needed.', PAGE_W - M_SIDE, top + ASCENT * (12.75 - 8.25), 8.25,
    c.f.regular, secondary(0.7), { align: 'right' });

  const gap = 18;
  const tableW = (CONTENT_W - gap) / 2;
  const labels = rows.map((r) => statusLabel(r.status));
  // Status is 52.5 wide in the handoff; a rest date ("Available Tue 9/29") needs more, taken from Player.
  const statusW = Math.max(52.5, ...labels.map((l) => 5.25 + 3.75 + c.width(l, 8.25, c.f.bold) + 3));
  const half = Math.ceil(rows.length / 2);
  const tablesTop = top + PITCH_TITLE_H + 6;

  const table = (x: number, list: PitchingSummaryRow[], labelOf: (k: number) => string) => {
    const right = x + tableW - 3;
    const restR = right - statusW;
    const availR = restR - 25.5;
    const thrownR = availR - 31.5;
    const head = { size: 7.1, font: c.f.bold, color: secondary(0.7), tracking: 0.08, align: 'right' as const };
    c.text('PLAYER', x + 3, tablesTop, head.size, head.font, head.color, { tracking: head.tracking });
    c.text('THROWN', thrownR, tablesTop, head.size, head.font, head.color, head);
    c.text('AVAIL', availR, tablesTop, head.size, head.font, head.color, head);
    c.text('REST', restR, tablesTop, head.size, head.font, head.color, head);
    c.text('STATUS', right, tablesTop, head.size, head.font, head.color, head);
    c.rect(x, tablesTop + 7.1 * LINE + 3.75, tableW, 1.125, BLACK);

    list.forEach((row, k) => {
      const y = tablesTop + PITCH_HEAD_H + k * rowH;
      const restricted = blocksAssignment(row.status);
      c.textMid(displayName(row.player), x + 3, y, rowH, 9.4, c.f.bold, BLACK, { maxWidth: thrownR - 34.5 - x - 3 });
      c.textMid(String(row.pitchesInWindow), thrownR, y, rowH, 9.4, c.f.regular, secondary(0.75), { align: 'right' });
      c.textMid(String(restricted ? 0 : row.available), availR, y, rowH, 9.4, c.f.bold, BLACK, { align: 'right' });
      c.textMid(String(restricted ? row.restDaysRequired : 0), restR, y, rowH, 9.4, c.f.regular, secondary(0.75), { align: 'right' });
      const label = labelOf(k);
      const labelW = c.width(label, 8.25, c.f.bold);
      c.textMid(label, right, y, rowH, 8.25, c.f.bold, BLACK, { align: 'right' });
      c.dot(right - labelW - 3.75 - 5.25 / 2, y + rowH / 2, 5.25, BLACK);
      c.hLine(x, x + tableW, y + rowH - 0.75 / 2, HAIRLINE, 0.75);
    });
  };

  table(M_SIDE, rows.slice(0, half), (k) => labels[k]);
  table(M_SIDE + tableW + gap, rows.slice(half), (k) => labels[half + k]);
}

/**
 * "Wilsonville Fall Ball vs Lincoln 2 - Coaches Guide Oct 4": the PDF's
 * title, which browsers show and suggest when printing or saving. Without an
 * opponent it's "Wilsonville Fall Ball - Coaches Guide Oct 4". iOS names its
 * printouts the same way (PDFGenerator.title).
 */
export function pdfTitle(kind: 'battingOrder' | 'coachesGuide', teamName: string, opponent: string, gameDate: Date): string {
  const lead = [teamName.trim(), opponent.trim() ? `vs ${opponent.trim()}` : ''].filter(Boolean).join(' ');
  const date = gameDate.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
  const doc = `${kind === 'battingOrder' ? 'Batting Order' : 'Coaches Guide'} ${date}`;
  return lead ? `${lead} - ${doc}` : doc;
}

/** The title as a filename: characters files can't hold become "-", plus ".pdf". */
export function pdfFilename(kind: 'battingOrder' | 'coachesGuide', teamName: string, opponent: string, gameDate: Date): string {
  return `${pdfTitle(kind, teamName, opponent, gameDate).replace(/[\\/:*?"<>|]/g, '-').replace(/\s+/g, ' ')}.pdf`;
}
