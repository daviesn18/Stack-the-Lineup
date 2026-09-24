import { PDFDocument } from 'pdf-lib';

import { defaultPitchingConfig, emptyLineup, type Player } from '@/core/model';
import { applyLittleLeaguePreset } from '@/core/pitching';

import { battingOrderPdf, coachesGuidePdf, pdfFilename, statusLabel, type PrintInput } from '../lineupPdf';

const roster = (n: number, name = (i: number) => `Kid${i}`): Player[] =>
  Array.from({ length: n }, (_, i) => ({
    id: `P${i}`, firstName: name(i), lastName: 'Test', number: String(i), leagueAge: 10, positionPreferences: {},
  }));

const input = (players: Player[]): PrintInput => {
  const lineup = { ...emptyLineup(6), gameDate: new Date(2026, 8, 27, 17), battingOrder: players.map((p) => p.id) };
  lineup.innings[0].assignments[players[0].id] = 'P';
  return {
    lineup, players, teamName: 'Tigers', teamColorHex: 'E4572E', gameLogs: [],
    pitchingConfig: applyLittleLeaguePreset({ ...defaultPitchingConfig(), rulesEnabled: true }),
    generatedAt: new Date(2026, 8, 23, 21, 0),
  };
};

const pages = async (bytes: Uint8Array) => (await PDFDocument.load(bytes)).getPageCount();

describe('printouts', () => {
  it('are one US Letter page each for a normal roster', async () => {
    const i = input(roster(12));
    const bo = await PDFDocument.load(await battingOrderPdf(i));
    expect(bo.getPageCount()).toBe(1);
    expect(bo.getPage(0).getSize()).toEqual({ width: 612, height: 792 });
    expect(await pages(await coachesGuidePdf(i))).toBe(1);
  });

  it('coaches guide flows onto a second page for a big roster (and keeps the pitch table)', async () => {
    expect(await pages(await coachesGuidePdf(input(roster(26))))).toBe(2);
  });

  it('does not fail on names the PDF font cannot draw', async () => {
    const odd = roster(3, (i) => ['José', 'Zoë 🙂', '李'][i]);
    await expect(battingOrderPdf(input(odd))).resolves.toBeInstanceOf(Uint8Array);
    await expect(coachesGuidePdf(input(odd))).resolves.toBeInstanceOf(Uint8Array);
  });

  it('names files and statuses like iOS', () => {
    expect(pdfFilename('battingOrder', new Date(2026, 8, 27))).toBe('BattingOrder_9-27-26.pdf');
    expect(pdfFilename('coachesGuide', new Date(2026, 10, 1))).toBe('CoachesGuide_11-1-26.pdf');
    expect(statusLabel({ kind: 'mustRest', until: new Date(2026, 8, 29) })).toBe('Available Tue 9/29');
    expect(statusLabel({ kind: 'unknownAge' })).toBe('Age not set');
  });
});
