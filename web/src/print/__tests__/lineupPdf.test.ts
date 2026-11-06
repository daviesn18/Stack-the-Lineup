import { PDFDict, PDFDocument, PDFName } from 'pdf-lib';

import { defaultFairPlayConfig, defaultPitchingConfig, emptyLineup, type Player } from '@/core/model';
import { applyLittleLeaguePreset } from '@/core/pitching';

import { battingOrderPdf, coachesGuidePdf, pdfFilename, pitchStatus, statusLabel, type PrintInput } from '../lineupPdf';
import { loadFontFiles } from '../pdfFonts';

// The browser fetches the fonts from /fonts; here they're read from public/fonts.
jest.mock('../pdfFonts', () => {
  const actual = jest.requireActual('../pdfFonts');
  const { readFileSync } = jest.requireActual('fs');
  const { join } = jest.requireActual('path');
  const files = Object.fromEntries(Object.entries(actual.FACES as Record<string, string>).map(([face, name]) => {
    const b: Buffer = readFileSync(join(__dirname, '../../../public/fonts', `${name}.ttf`));
    return [face, b.buffer.slice(b.byteOffset, b.byteOffset + b.byteLength)];
  }));
  return { ...actual, loadFontFiles: jest.fn(async () => files) };
});

const roster = (n: number, name = (i: number) => `Kid${i}`): Player[] =>
  Array.from({ length: n }, (_, i) => ({
    id: `P${i}`, firstName: name(i), lastName: 'Test', number: String(i), leagueAge: 10, positionPreferences: {},
  }));

const input = (players: Player[]): PrintInput => {
  const lineup = { ...emptyLineup(6), gameDate: new Date(2026, 8, 27, 17), battingOrder: players.map((p) => p.id) };
  // A filled grid, rotating who plays where; everyone else sits.
  const nine = ['P', 'C', '1B', '2B', 'SS', '3B', 'LF', 'CF', 'RF'] as const;
  lineup.innings.forEach((inn, i) => nine.forEach((pos, k) => {
    if (k < players.length) inn.assignments[players[(i + k) % players.length].id] = pos;
  }));
  return {
    lineup, players, teamName: 'Tigers', teamColorHex: 'E4572E', gameLogs: [],
    pitchingConfig: applyLittleLeaguePreset({ ...defaultPitchingConfig(), rulesEnabled: true }),
    generatedAt: new Date(2026, 8, 23, 21, 0),
  };
};

const pages = async (bytes: Uint8Array) => (await PDFDocument.load(bytes)).getPageCount();

/** The BaseFont of every font the PDF embeds, without pdf-lib's subset tag ("Barlow-Bold-5463"). */
const fontNames = async (bytes: Uint8Array) => {
  const doc = await PDFDocument.load(bytes);
  return doc.context.enumerateIndirectObjects()
    .map(([, obj]) => (obj instanceof PDFDict && obj.get(PDFName.of('Type')) === PDFName.of('Font') ? obj.get(PDFName.of('BaseFont')) : undefined))
    .filter((n): n is PDFName => n instanceof PDFName)
    .map((n) => n.decodeText().replace(/-\d+$/, ''));
};

describe('printouts', () => {
  it('are one US Letter page each for a normal roster', async () => {
    const i = input(roster(12));
    const bo = await PDFDocument.load(await battingOrderPdf(i));
    expect(bo.getPageCount()).toBe(1);
    expect(bo.getPage(0).getSize()).toEqual({ width: 612, height: 792 });
    expect(await pages(await coachesGuidePdf(i))).toBe(1);
  });

  it('coaches guide fits 26 players on a page, and flows onto a second for 40 (keeping the pitch table)', async () => {
    expect(await pages(await coachesGuidePdf(input(roster(26))))).toBe(1);
    expect(await pages(await coachesGuidePdf(input(roster(40))))).toBe(2);
  });

  it('coaches guide lists by position, with four outfielders, a full bench and an absence, on one page', async () => {
    const i = input(roster(12));
    i.fairPlayConfig = { ...defaultFairPlayConfig(), outfielderCount: 4 };
    i.lineup.absentPlayerIDs = ['P11'];
    i.lineup.innings.forEach((inn) => { delete inn.assignments.P11; });
    expect(await pages(await coachesGuidePdf(i))).toBe(1);
  });

  it('is set in the bundled Barlow faces', async () => {
    const fonts = await fontNames(await coachesGuidePdf(input(roster(12))));
    expect(fonts).toEqual(expect.arrayContaining(['BarlowCondensed-Bold', 'Barlow-SemiBold', 'Barlow-Bold']));
  });

  it('falls back to Helvetica when the fonts cannot be fetched', async () => {
    jest.mocked(loadFontFiles).mockResolvedValueOnce(null).mockResolvedValueOnce(null);
    expect(await fontNames(await coachesGuidePdf(input(roster(12))))).toEqual(expect.arrayContaining(['Helvetica', 'Helvetica-Bold']));
    expect(await pages(await battingOrderPdf(input(roster(12))))).toBe(1);
  });

  it('marks pitchers near the limit at 30 pitches left or fewer', () => {
    const p = roster(1)[0];
    const row = (available: number, status: Parameters<typeof statusLabel>[0]) =>
      ({ player: p, pitchesInWindow: 0, dailyMax: 85, available, restDaysRequired: 0, status });
    expect(pitchStatus(row(31, { kind: 'eligible' }))).toBe('eligible');
    expect(pitchStatus(row(30, { kind: 'eligible' }))).toBe('nearLimit');
    expect(pitchStatus(row(25, { kind: 'limited', remaining: 25 }))).toBe('nearLimit');
    expect(pitchStatus(row(0, { kind: 'mustRest', until: new Date(2026, 9, 5) }))).toBe('restNeeded');
    expect(pitchStatus(row(0, { kind: 'unknownAge' }))).toBe('ageNotSet');
  });

  it('does not fail on names the PDF font cannot draw', async () => {
    const odd = roster(3, (i) => ['José', 'Zoë 🙂', '李'][i]);
    await expect(battingOrderPdf(input(odd))).resolves.toBeInstanceOf(Uint8Array);
    await expect(coachesGuidePdf(input(odd))).resolves.toBeInstanceOf(Uint8Array);
  });

  it('titles the PDF with team, opponent, kind and date', async () => {
    const i = { ...input(roster(9)), teamName: 'Wilsonville Fall Ball' };
    i.lineup = { ...i.lineup, opponent: 'Lincoln 2', gameDate: new Date(2026, 9, 4, 16) };
    expect((await PDFDocument.load(await coachesGuidePdf(i))).getTitle()).toBe('Wilsonville Fall Ball vs Lincoln 2 - Coaches Guide Oct 4');
    expect((await PDFDocument.load(await battingOrderPdf(i))).getTitle()).toBe('Wilsonville Fall Ball vs Lincoln 2 - Batting Order Oct 4');
  });

  it('names files and statuses like iOS', () => {
    expect(pdfFilename('coachesGuide', 'Wilsonville Fall Ball', 'Lincoln 2', new Date(2026, 9, 4)))
      .toBe('Wilsonville Fall Ball vs Lincoln 2 - Coaches Guide Oct 4.pdf');
    expect(pdfFilename('battingOrder', 'Tigers', ' ', new Date(2026, 8, 27))).toBe('Tigers - Batting Order Sep 27.pdf');
    expect(pdfFilename('battingOrder', 'A/B: Team', 'C?', new Date(2026, 10, 1))).toBe('A-B- Team vs C- - Batting Order Nov 1.pdf');
    expect(statusLabel({ kind: 'mustRest', until: new Date(2026, 8, 29) })).toBe('Available Tue 9/29');
    expect(statusLabel({ kind: 'unknownAge' })).toBe('Age not set');
  });
});
