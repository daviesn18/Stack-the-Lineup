// The two printouts, drawn as real PDFs from the v3 Coaches Guide redesign
// handoff: the matchup as the headline, a dark inning bar, zebra rows, one
// comma-separated bench line per inning, and pitch counts with a bar and a
// status shape (circle, triangle, square) so the statuses still read on a
// black-and-white printer. PDFGenerator.swift draws the same pages on iOS: US
// Letter, 612 x 792 pt; every handoff px value is x0.75 to get points.
//
// Set in Barlow and Barlow Condensed (pdfFonts.ts), embedded and subset, with
// tabular figures on. If the font files can't be fetched the printout falls
// back to the PDF standard Helvetica rather than failing. Text is placed by the
// top of its line box (1.2 x size, CSS "normal" for Barlow); PDF draws from
// the baseline, which sits `ascent` x size below that top.
//
// A character the font has no glyph for (e.g. emoji in a name) is replaced
// with "?" rather than failing the whole printout.

import fontkit from '@pdf-lib/fontkit';
import {
  PDFDocument, rgb, setCharacterSpacing, StandardFonts, type PDFFont, type PDFPage, type RGB,
} from 'pdf-lib';

import { activeFieldPositions, activePlayers } from '@/core/fairPlay';
import { gridNames } from '@/core/lineupOps';
import {
  defaultFairPlayConfig, isOutfield, type FairPlayConfig, type FieldPosition, type GameLog, type Lineup,
  type PitchingConfig, type Player,
} from '@/core/model';
import { coachesGuideSummary, type PitchEligibilityStatus, type PitchingSummaryRow } from '@/core/pitching';

import { FACES, loadFontFiles, type Face } from './pdfFonts';

const PAGE_W = 612;
const PAGE_H = 792;
const M_TOP = 33;
const M_SIDE = 36;
const M_BOTTOM = 24;
const LEFT = M_SIDE;
const RIGHT = PAGE_W - M_SIDE;
const CONTENT_W = PAGE_W - M_SIDE * 2;
const LINE = 1.2;             // line height, as a fraction of size

const hex = (n: number) => rgb(((n >> 16) & 255) / 255, ((n >> 8) & 255) / 255, (n & 255) / 255);
/** rgba(60,60,67,a) over white. */
const secondary = (a: number) => rgb((255 - a * 195) / 255, (255 - a * 195) / 255, (255 - a * 188) / 255);
const BLACK = rgb(0, 0, 0);
const WHITE = rgb(1, 1, 1);
const BLUE = hex(0x007aff);
const BAR = hex(0x1c1c1e);
const GROUPED = hex(0xf2f2f7);
const SEPARATOR = hex(0xc6c6c8);
const HAIRLINE = hex(0xe5e5ea);
const INFIELD = hex(0x0a4fa8);
const OUTFIELD = hex(0x1e6b34);
const BENCH = hex(0x3a3a3c);

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

interface TextOpts { tracking?: number; align?: 'left' | 'right' | 'center'; maxWidth?: number }

class Canvas {
  page!: PDFPage;
  constructor(private doc: PDFDocument, readonly f: Record<Face, PDFFont>, private ascent: number) {}

  newPage() { this.page = this.doc.addPage([PAGE_W, PAGE_H]); }

  /** Width of `s` with `tracking` (em) after every glyph, as CSS letter-spacing. */
  width(s: string, size: number, face: Face, tracking = 0) {
    const t = safe(s, this.f[face]);
    return this.f[face].widthOfTextAtSize(t, size) + [...t].length * tracking * size;
  }

  /** `s` cut to fit `maxWidth` with a trailing ellipsis. */
  fit(s: string, size: number, face: Face, maxWidth: number, tracking = 0) {
    if (this.width(s, size, face, tracking) <= maxWidth) return s;
    let t = s;
    while (t.length > 1 && this.width(`${t}…`, size, face, tracking) > maxWidth) t = t.slice(0, -1);
    return `${t.trimEnd()}…`;
  }

  /** Text whose line box starts at `top`; `x` is the left, right or center edge per `align`. */
  text(s: string, x: number, top: number, size: number, face: Face, color: RGB, o: TextOpts = {}) {
    this.baseline(s, x, top + this.ascent * size, size, face, color, o);
  }

  /** Text vertically centered in a box `h` tall starting at `top`. */
  textMid(s: string, x: number, top: number, h: number, size: number, face: Face, color: RGB, o: TextOpts = {}) {
    this.text(s, x, top + h / 2 - (LINE * size) / 2, size, face, color, o);
  }

  /** Text on a baseline `y` down the page. Returns the drawn width. */
  baseline(s: string, x: number, y: number, size: number, face: Face, color: RGB, o: TextOpts = {}) {
    const font = this.f[face];
    const tracking = o.tracking ?? 0;
    const t = safe(o.maxWidth !== undefined ? this.fit(s, size, face, o.maxWidth, tracking) : s, font);
    // Trailing tracking isn't ink, so alignment ignores it.
    const w = this.width(t, size, face, tracking) - tracking * size;
    const left = o.align === 'right' ? x - w : o.align === 'center' ? x - w / 2 : x;
    if (tracking) this.page.pushOperators(setCharacterSpacing(tracking * size));
    this.page.drawText(t, { x: left, y: PAGE_H - y, size, font, color });
    if (tracking) this.page.pushOperators(setCharacterSpacing(0));
    return w;
  }

  rect(x: number, top: number, w: number, h: number, color: RGB) {
    this.page.drawRectangle({ x, y: PAGE_H - top - h, width: w, height: h, color });
  }

  /** A rectangle with rounded corners; `bottom: false` squares off the bottom two. */
  roundedRect(x: number, top: number, w: number, h: number, r: number,
    o: { fill?: RGB; stroke?: RGB; strokeWidth?: number; bottom?: boolean }) {
    const rb = o.bottom === false ? 0 : r;
    const path = `M ${r} 0 H ${w - r} A ${r} ${r} 0 0 1 ${w} ${r} V ${h - rb} A ${rb} ${rb} 0 0 1 ${w - rb} ${h} `
      + `H ${rb} A ${rb} ${rb} 0 0 1 0 ${h - rb} V ${r} A ${r} ${r} 0 0 1 ${r} 0 Z`;
    this.page.drawSvgPath(path, {
      x, y: PAGE_H - top, color: o.fill, borderColor: o.stroke, borderWidth: o.stroke ? o.strokeWidth ?? 1 : 0,
    });
  }

  path(d: string, x: number, top: number, color: RGB) {
    this.page.drawSvgPath(d, { x, y: PAGE_H - top, color, borderWidth: 0 });
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

/** Replaces characters the font can't draw. */
function safe(s: string, font: PDFFont): string {
  const chars = new Set(font.getCharacterSet());
  return [...s].map((ch) => (chars.has(ch.codePointAt(0)!) ? ch : '?')).join('');
}

async function newDoc(title: string): Promise<{ doc: PDFDocument; c: Canvas }> {
  const doc = await PDFDocument.create();
  doc.setTitle(title);
  doc.setCreator('Stack the Lineup');
  doc.setProducer('Stack the Lineup (web)');
  const files = await loadFontFiles();
  if (files) {
    doc.registerFontkit(fontkit);
    const faces = Object.keys(FACES) as Face[];
    const embedded = await Promise.all(faces.map((face) => doc.embedFont(files[face], { subset: true, features: { tnum: true } })));
    return { doc, c: new Canvas(doc, Object.fromEntries(faces.map((face, i) => [face, embedded[i]])) as Record<Face, PDFFont>, 1) };
  }
  const regular = await doc.embedFont(StandardFonts.Helvetica);
  const bold = await doc.embedFont(StandardFonts.HelveticaBold);
  return { doc, c: new Canvas(doc, { regular, medium: regular, semibold: bold, bold, condensed: bold }, 0.93) };
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

interface Word { text: string; size: number; color: RGB }

/** Team and opponent at 30 pt, upper-cased, with a smaller gray "VS." between. */
function matchupWords(team: string, opponent: string): Word[] {
  const words = (s: string) => s.toUpperCase().split(/\s+/).filter(Boolean).map((text) => ({ text, size: 30, color: BLACK }));
  const all = words(team.trim() || 'Stack the Lineup');
  if (opponent.trim()) all.push({ text: 'VS.', size: 19.5, color: secondary(0.75) }, ...words(opponent));
  return all;
}

function lineWidth(c: Canvas, words: Word[], scale: number): number {
  return words.reduce((w, word, k) =>
    w + (k > 0 ? c.width(' ', Math.min(words[k - 1].size, word.size) * scale, 'condensed') : 0)
      + c.width(word.text, word.size * scale, 'condensed'), 0);
}

/**
 * One line if it fits, else two balanced lines. Only if a balanced line
 * still overflows does it shrink, from 30 pt to no less than 24; past that
 * the words are cut with an ellipsis.
 */
function layoutMatchup(c: Canvas, words: Word[], maxWidth: number): { lines: Word[][]; scale: number } {
  const split = (scale: number): Word[][] => {
    if (words.length < 2 || lineWidth(c, words, scale) <= maxWidth) return [words];
    const worst = (k: number) => Math.max(lineWidth(c, words.slice(0, k), scale), lineWidth(c, words.slice(k), scale));
    let best = 1;
    for (let k = 2; k < words.length; k++) if (worst(k) < worst(best)) best = k;
    return [words.slice(0, best), words.slice(best)];
  };
  let scale = 1;
  let lines = split(scale);
  while (scale > 0.8 + 0.001 && lines.some((l) => lineWidth(c, l, scale) > maxWidth)) {
    scale -= 0.025;
    lines = split(scale);
  }
  return { lines, scale };
}

/**
 * The matchup ("WILSONVILLE FALL BALL vs. LINCOLN 2") on the left; the
 * eyebrow and date on the right; both bottom-aligned over a 1.5 pt black
 * rule. Returns the rule's bottom.
 */
function header(c: Canvas, eyebrow: string, input: PrintInput): number {
  const date = input.lineup.gameDate.toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric', year: 'numeric' });
  const eyebrowText = eyebrow.toUpperCase();
  const rightW = Math.max(c.width(eyebrowText, 8.25, 'bold', 0.12) - 0.12 * 8.25, c.width(date, 9.75, 'semibold'));
  const rightH = 8.25 * LINE + 1.5 + 9.75 * LINE + 2.25;

  const maxW = CONTENT_W - rightW - 18;
  const { lines, scale } = layoutMatchup(c, matchupWords(input.teamName, input.lineup.opponent), maxW);
  const lineH = 30 * scale * 1.1;
  const leftH = lines.length * lineH;
  const bottom = M_TOP + Math.max(leftH, rightH);

  lines.forEach((line, n) => {
    // The 1.1 line box is tighter than the font's 1.2; its baseline sits 0.95 em down.
    const y = bottom - leftH + n * lineH + 0.95 * 30 * scale;
    let x = LEFT;
    line.forEach((word, k) => {
      if (k > 0) x += c.width(' ', Math.min(line[k - 1].size, word.size) * scale, 'condensed');
      x += c.baseline(word.text, x, y, word.size * scale, 'condensed', word.color, { maxWidth: LEFT + maxW - x });
    });
  });

  c.text(eyebrowText, RIGHT, bottom - rightH, 8.25, 'bold', BLUE, { tracking: 0.12, align: 'right' });
  c.text(date, RIGHT, bottom - 2.25 - 9.75 * LINE, 9.75, 'semibold', secondary(0.75), { align: 'right' });

  const ruleTop = bottom + 10.5;
  c.rect(LEFT, ruleTop, CONTENT_W, 1.5, BLACK);
  return ruleTop + 1.5;
}

const FOOTER_TEXT_TOP = PAGE_H - M_BOTTOM - 7.5 * LINE;
const FOOTER_RULE = FOOTER_TEXT_TOP - 7.5;
/** Lowest y page content may reach, leaving room above the footer rule. */
const CONTENT_BOTTOM = FOOTER_RULE - 12;

function footer(c: Canvas, generatedAt: Date) {
  const stamp = generatedAt.toLocaleString('en-US', { dateStyle: 'short', timeStyle: 'short' });
  c.hLine(LEFT, RIGHT, FOOTER_RULE, SEPARATOR, 0.75);
  c.text(`Generated ${stamp}`, LEFT, FOOTER_TEXT_TOP, 7.5, 'regular', secondary(0.5));
  c.text('Stack the Lineup', RIGHT, FOOTER_TEXT_TOP, 7.5, 'semibold', secondary(0.5), { align: 'right' });
}

/**
 * `names` as comma-separated lines no wider than `maxWidth`, never breaking
 * inside a name ("Caleb J." stays together), balanced so the lines come out
 * about the same length.
 */
function commaLines(c: Canvas, names: string[], maxWidth: number, face: Face, size: number): string[] {
  if (!names.length) return [];
  const tokens = names.map((n, i) => (i < names.length - 1 ? `${n},` : n));
  const wrap = (w: number) => {
    const lines: string[] = [];
    let line = '';
    for (const token of tokens) {
      const next = line ? `${line} ${token}` : token;
      if (!line || c.width(next, size, face) <= w) line = next;
      else { lines.push(line); line = token; }
    }
    return [...lines, line];
  };
  const greedy = wrap(maxWidth);
  if (greedy.length < 2) return greedy;
  // The narrowest width that still needs no more lines than the greedy fill.
  let lo = 0;
  let hi = maxWidth;
  for (let i = 0; i < 12; i++) {
    const mid = (lo + hi) / 2;
    if (wrap(mid).length <= greedy.length) hi = mid; else lo = mid;
  }
  return wrap(hi);
}

// MARK: - Batting order

export async function battingOrderPdf(input: PrintInput): Promise<Uint8Array> {
  const { doc, c } = await newDoc(pdfTitle('battingOrder', input.teamName, input.lineup.opponent, input.lineup.gameDate));
  const generatedAt = input.generatedAt ?? new Date();
  c.newPage();
  const ordered = orderedPlayers(input.lineup, input.players);

  const numW = 48;
  const jerseyW = 72;
  const playerX = LEFT + numW;
  const jerseyX = RIGHT - jerseyW;
  const headH = 6 * 2 + 11.25 * LINE;
  const countH = 7.5 + 9 * LINE;

  let top = header(c, 'Batting Order', input) + 15;
  // Rows shrink from 33 to 24 to fit; past that the list continues on another page.
  const room = CONTENT_BOTTOM - top - headH - countH;
  const rowH = Math.max(24, Math.min(33, room / Math.max(1, ordered.length)));
  const nameSize = rowH < 27 ? 12 : 13.5;

  const table = (rows: Player[], first: number) => {
    const h = headH + rows.length * rowH;
    // Gray container clipped to its corners, white rows painted over it (square is fine: the page is white).
    c.roundedRect(LEFT, top, CONTENT_W, h, 6, { fill: GROUPED });
    rows.forEach((_, k) => { if ((first + k) % 2 === 0) c.rect(LEFT, top + headH + k * rowH, CONTENT_W, rowH, WHITE); });
    c.roundedRect(LEFT, top, CONTENT_W, headH, 6, { fill: BAR, bottom: false });
    c.vLine(playerX, top + headH, top + h, HAIRLINE, 0.75);
    c.vLine(jerseyX, top + headH, top + h, HAIRLINE, 0.75);
    const label = { tracking: 0.06 };
    c.textMid('#', LEFT + numW / 2, top, headH, 11.25, 'condensed', WHITE, { ...label, align: 'center' });
    c.textMid('PLAYER', playerX + 10.5, top, headH, 11.25, 'condensed', WHITE, label);
    c.textMid('JERSEY', jerseyX + jerseyW / 2, top, headH, 11.25, 'condensed', WHITE, { ...label, align: 'center' });
    rows.forEach((p, k) => {
      const y = top + headH + k * rowH;
      c.textMid(String(first + k + 1), LEFT + numW / 2, y, rowH, 18, 'condensed', BLACK, { align: 'center' });
      c.textMid(displayName(p), playerX + 10.5, y, rowH, nameSize, 'semibold', BLACK, { maxWidth: jerseyX - playerX - 21 });
      // No number: left blank for the coach to write in.
      if (p.number) c.textMid(p.number, jerseyX + jerseyW / 2, y, rowH, 12.75, 'bold', BLACK, { align: 'center', maxWidth: jerseyW - 12 });
    });
    c.roundedRect(LEFT, top, CONTENT_W, h, 6, { stroke: SEPARATOR, strokeWidth: 0.75 });
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

  c.text(`${ordered.length} ${ordered.length === 1 ? 'player' : 'players'}`, LEFT, top + 7.5, 9, 'regular', secondary(0.75));
  footer(c, generatedAt);
  return doc.save();
}

// MARK: - Coaches guide

const GRID_HEAD_H = Math.max(5.25 * 2 + 7.1 * LINE, 4.5 * 2 + 15.75 * LINE);
const POSITION_COL = 42;
/** The rule between the infield and outfield rows, and the bench's top rule. */
const GRID_RULE = 1.125;
const BENCH_LINE = 8.25 * 1.4;
const PITCH_TITLE_H = 15.75 * LINE;
const PITCH_HEAD_H = 7.1 * LINE + 3.75 + 1.125;

export async function coachesGuidePdf(input: PrintInput): Promise<Uint8Array> {
  const { doc, c } = await newDoc(pdfTitle('coachesGuide', input.teamName, input.lineup.opponent, input.lineup.gameDate));
  const generatedAt = input.generatedAt ?? new Date();
  const { lineup } = input;
  c.newPage();
  let top = header(c, 'Coaches Guide', input) + 13.5;

  // By position: a row per field position, then Bench; each cell names who is there that inning.
  const positions = activeFieldPositions(input.fairPlayConfig ?? defaultFairPlayConfig());
  const active = activePlayers(lineup, input.players);
  const names = gridNames(active);
  const nameOf = (p: Player) => names.get(p.id) ?? p.firstName;
  const ordered = orderedPlayers(lineup, input.players);
  const sitOrder = [...ordered, ...active.filter((p) => !ordered.includes(p))];
  const colW = (CONTENT_W - POSITION_COL) / Math.max(1, lineup.innings.length);
  // Bench: everyone with no field spot that inning, in batting order, as one comma-separated list.
  const benchLines = lineup.innings.map((inn) => commaLines(c,
    sitOrder.filter((p) => { const x = inn.assignments[p.id]; return x === undefined || x === 'Bench'; }).map(nameOf),
    colW - 12, 'regular', 8.25));
  const mostLines = Math.max(0, ...benchLines.map((l) => l.length));
  const benchH = GRID_RULE + Math.max(6 * 2 + mostLines * BENCH_LINE, 6 * 2 + 9.75 * LINE);

  // Pitch counts, as of the GAME date (matches the Pitching view for this game). Hidden with no pitchers.
  const pitchRows = coachesGuideSummary(input.gameLogs, input.players, input.pitchingConfig, lineup.gameDate) ?? [];

  // Overflow, per the handoff: shorten the pitch rows, then the grid rows; then move pitch counts to page 2.
  const hasDivider = positions.findIndex(isOutfield) > 0;
  const gridH = (row: number) => GRID_HEAD_H + positions.length * row + (hasDivider ? GRID_RULE : 0) + benchH;
  const pitchH = (row: number) => (pitchRows.length ? 18 + PITCH_TITLE_H + 6 + PITCH_HEAD_H + Math.ceil(pitchRows.length / 2) * row : 0);
  const room = CONTENT_BOTTOM - top;
  let gridRow = 24.75;
  let pitchRow = 19.5;
  if (gridH(gridRow) + pitchH(pitchRow) > room) pitchRow = 16.5;
  if (gridH(gridRow) + pitchH(pitchRow) > room) gridRow = 22.5;

  top = defenseGrid(c, {
    top, innings: lineup.innings.length, positions, benchLines, benchH, rowH: gridRow, nameOf,
    holder: (i, pos) => {
      const inn = lineup.innings[i];
      return active.find((p) => inn.assignments[p.id] === pos);
    },
  });

  if (pitchRows.length) {
    if (top + pitchH(pitchRow) > CONTENT_BOTTOM) {
      footer(c, generatedAt);
      c.newPage();
      top = M_TOP - 18;
    }
    pitchCounts(c, pitchRows, top + 18, pitchRow);
  }

  footer(c, generatedAt);
  return doc.save();
}

function defenseGrid(c: Canvas, g: {
  top: number; innings: number; positions: FieldPosition[]; benchLines: string[][]; benchH: number; rowH: number;
  nameOf: (p: Player) => string; holder: (inning: number, pos: FieldPosition) => Player | undefined;
}): number {
  const { top, innings, rowH } = g;
  const colW = (CONTENT_W - POSITION_COL) / Math.max(1, innings);
  const colX = (i: number) => LEFT + POSITION_COL + i * colW;
  const nameSize = innings >= 7 ? 9.75 : 10.5;
  const rowsTop = top + GRID_HEAD_H;
  const firstOutfield = g.positions.findIndex(isOutfield);
  const divider = firstOutfield > 0;
  const rowTop = (r: number) => rowsTop + r * rowH + (divider && r >= firstOutfield ? GRID_RULE : 0);
  const benchTop = rowTop(g.positions.length);
  const bottom = benchTop + g.benchH;
  const h = bottom - top;

  // Fills: a white container clipped to its 6 pt corners, the dark bar, gray even rows.
  c.roundedRect(LEFT, top, CONTENT_W, h, 6, { fill: WHITE });
  c.roundedRect(LEFT, top, CONTENT_W, GRID_HEAD_H, 6, { fill: BAR, bottom: false });
  g.positions.forEach((_, r) => { if (r % 2 === 1) c.rect(LEFT, rowTop(r), CONTENT_W, rowH, GROUPED); });
  for (let i = 0; i < innings; i++) c.vLine(colX(i), rowsTop, bottom, HAIRLINE, 0.75);
  if (divider) c.rect(LEFT, rowTop(firstOutfield) - GRID_RULE, CONTENT_W, GRID_RULE, SEPARATOR);
  c.rect(LEFT, benchTop, CONTENT_W, GRID_RULE, BLACK);

  // Header bar: just the inning numbers.
  c.textMid('INN', LEFT + 7.5, top, GRID_HEAD_H, 7.1, 'bold', WHITE, { tracking: 0.08 });
  for (let i = 0; i < innings; i++) {
    c.textMid(String(i + 1), colX(i) + colW / 2, top, GRID_HEAD_H, 15.75, 'condensed', WHITE, { align: 'center' });
  }

  // Position rows: the label, then who plays there each inning.
  g.positions.forEach((pos, r) => {
    const y = rowTop(r);
    c.textMid(pos, LEFT + 7.5, y, rowH, 9.75, 'bold', isOutfield(pos) ? OUTFIELD : INFIELD);
    for (let i = 0; i < innings; i++) {
      const p = g.holder(i, pos);
      if (p) c.textMid(g.nameOf(p), colX(i) + colW / 2, y, rowH, nameSize, 'semibold', BLACK, { tracking: -0.01, align: 'center', maxWidth: colW - 9 });
      else c.textMid('—', colX(i) + colW / 2, y, rowH, nameSize, 'regular', secondary(0.6), { align: 'center' });
    }
  });

  // Bench.
  const benchTextTop = benchTop + GRID_RULE + 6;
  c.text('BN', LEFT + 7.5, benchTextTop, 9.75, 'bold', BENCH);
  g.benchLines.forEach((lines, i) => {
    lines.forEach((line, k) => {
      c.textMid(line, colX(i) + colW / 2, benchTextTop + k * BENCH_LINE, BENCH_LINE, 8.25, 'regular', secondary(0.75),
        { align: 'center', maxWidth: colW - 12 });
    });
  });

  c.roundedRect(LEFT, top, CONTENT_W, h, 6, { stroke: SEPARATOR, strokeWidth: 0.75 });
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

/** A pitcher with this many pitches or fewer left today is "Near limit". */
export const NEAR_LIMIT_PITCHES = 30;

export type PitchStatus = 'eligible' | 'nearLimit' | 'restNeeded' | 'ageNotSet';

/** The pitch-count table's status for a summary row (iOS PDFGenerator.PitchStatus). */
export function pitchStatus(row: PitchingSummaryRow): PitchStatus {
  switch (row.status.kind) {
    case 'unknownAge': return 'ageNotSet';
    case 'mustRest': return 'restNeeded';
    default: return row.available <= NEAR_LIMIT_PITCHES ? 'nearLimit' : 'eligible';
  }
}

const PITCH_STATUS: Record<PitchStatus, { label: string; shape: RGB; text: RGB; bar: RGB }> = {
  eligible: { label: 'Eligible', shape: hex(0x34c759), text: hex(0x248a3d), bar: hex(0x8e8e93) },
  nearLimit: { label: 'Near limit', shape: hex(0xff9500), text: hex(0xc93400), bar: hex(0xff9500) },
  restNeeded: { label: 'Rest needed', shape: hex(0xff3b30), text: hex(0xd70015), bar: hex(0xff3b30) },
  ageNotSet: { label: 'Age not set', shape: secondary(0.5), text: secondary(0.75), bar: hex(0x8e8e93) },
};

/** Circle (eligible), upward triangle (near limit), or square (rest needed). Returns its width. */
function statusShape(c: Canvas, status: PitchStatus, x: number, midY: number, color: RGB): number {
  if (status === 'eligible') { c.dot(x + 3, midY, 6, color); return 6; }
  if (status === 'nearLimit') { c.path('M 3.75 0 L 7.5 6.75 L 0 6.75 Z', x, midY - 3.375, color); return 7.5; }
  c.rect(x, midY - 3, 6, 6, color);
  return 6;
}

/**
 * "Pitch counts" title, then two tables side by side (first half, rounded up, on the left).
 * Rows arrive sorted: who can throw, most pitches available first, then those who must rest.
 */
function pitchCounts(c: Canvas, rows: PitchingSummaryRow[], top: number, rowH: number) {
  c.text('PITCH COUNTS', LEFT, top, 15.75, 'condensed', BLACK);

  const gap = 18;
  const tableW = (CONTENT_W - gap) / 2;
  const half = Math.ceil(rows.length / 2);
  const tablesTop = top + PITCH_TITLE_H + 6;

  const table = (x: number, list: PitchingSummaryRow[]) => {
    // Player (flexible) | Thrown / Max 69 | Rest 19.5 | Status 60, 4.5 apart, inset 4.5.
    const statusX = x + tableW - 4.5 - 60;
    const restR = statusX - 4.5;
    const thrownX = restR - 19.5 - 4.5 - 69;
    const playerX = x + 4.5;
    const barW = 69 - 4.5 - 28.5;

    const head = { tracking: 0.08 };
    c.text('PLAYER', playerX, tablesTop, 7.1, 'bold', secondary(0.75), head);
    c.text('THROWN / MAX', thrownX, tablesTop, 7.1, 'bold', secondary(0.75), head);
    c.text('REST', restR, tablesTop, 7.1, 'bold', secondary(0.75), { ...head, align: 'right' });
    c.text('STATUS', statusX, tablesTop, 7.1, 'bold', secondary(0.75), head);
    c.rect(x, tablesTop + 7.1 * LINE + 3.75, tableW, 1.125, BLACK);

    list.forEach((row, k) => {
      const y = tablesTop + PITCH_HEAD_H + k * rowH;
      const mid = y + rowH / 2;
      const status = pitchStatus(row);
      const style = PITCH_STATUS[status];
      const resting = status === 'restNeeded' || status === 'ageNotSet';
      if (k % 2 === 1) c.rect(x, y, tableW, rowH, GROUPED);

      c.textMid(displayName(row.player), playerX, y, rowH, 9.4, 'semibold', resting ? secondary(0.6) : BLACK,
        { maxWidth: thrownX - 4.5 - playerX });

      // Thrown / max: a bar (full for Rest needed), then "50 / 75".
      const barTop = mid - 5.25 / 2;
      c.roundedRect(thrownX, barTop, barW, 5.25, 1.5, { fill: WHITE });
      const share = status === 'restNeeded' ? 1 : status === 'ageNotSet' || row.dailyMax <= 0 ? 0
        : Math.min(1, row.pitchesInWindow / row.dailyMax);
      if (share > 0) {
        const w = barW * share;
        c.roundedRect(thrownX, barTop, w, 5.25, Math.min(1.5, w / 2), { fill: style.bar });
      }
      c.roundedRect(thrownX + 0.375, barTop + 0.375, barW - 0.75, 5.25 - 0.75, 1.5 - 0.375, { stroke: SEPARATOR, strokeWidth: 0.75 });
      c.textMid(`${row.pitchesInWindow} / ${row.dailyMax}`, thrownX + 69, y, rowH, 7.9, 'regular', secondary(0.85), { align: 'right' });

      // Rest owed is only meaningful while they're still inside it; 0 otherwise (no dashes).
      c.textMid(String(status === 'restNeeded' ? row.restDaysRequired : 0), restR, y, rowH, 9.4, 'regular', secondary(0.75), { align: 'right' });

      const shapeW = statusShape(c, status, statusX, mid, style.shape);
      c.textMid(style.label, statusX + shapeW + 4.5, y, rowH, 8.25, 'bold', style.text, { maxWidth: 60 - shapeW - 4.5 });
    });
  };

  table(LEFT, rows.slice(0, half));
  table(LEFT + tableW + gap, rows.slice(half));
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
