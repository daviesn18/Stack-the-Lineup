// Renders the web printouts from fixtures/print/print-input.json (the same
// inputs ParityFixtureWriter used for ios-*.pdf), so the two can be compared
// page for page:
//
//   TZ=America/Los_Angeles npx tsx scripts/compare-print.ts
//   (then open fixtures/print/{ios,web}-*.pdf side by side)

import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

import type { FieldPosition, GameLog, Lineup, Player } from '../src/core/model';
import { battingOrderPdf, coachesGuidePdf, type PrintInput } from '../src/print/lineupPdf';

// The printouts fetch their fonts from /fonts/*.ttf, which only resolves in a
// browser. Serve those paths from public/fonts so this script renders Barlow
// like the app does, instead of falling back to Helvetica.
const realFetch = globalThis.fetch;
globalThis.fetch = (async (url: Parameters<typeof fetch>[0], init?: RequestInit) => {
  if (typeof url === 'string' && url.startsWith('/fonts/')) {
    return new Response(readFileSync(join(__dirname, '../public', url)));
  }
  return realFetch(url, init);
}) as typeof fetch;

const dir = join(__dirname, '../fixtures/print');
const j = JSON.parse(readFileSync(join(dir, 'print-input.json'), 'utf8'));

const inning = (a: Record<string, FieldPosition>) => ({ assignments: { ...a } });
const lineup: Lineup = {
  gameDate: new Date(j.lineup.gameDate), opponent: j.lineup.opponent, battingOrder: j.lineup.battingOrder,
  innings: j.lineup.innings.map(inning), absentPlayerIDs: j.lineup.absentPlayerIDs, status: j.lineup.status,
};
const players: Player[] = j.players.map((p: Player) => ({ ...p }));
const gameLogs: GameLog[] = j.gameLogs.map((g: GameLog & { gameDate: string; archivedAt: string }) => ({
  ...g, gameDate: new Date(g.gameDate), archivedAt: new Date(g.archivedAt), innings: [],
}));

const input: PrintInput = {
  lineup, players, gameLogs, teamName: j.teamName, teamColorHex: j.teamColorHex, pitchingConfig: j.pitchingConfig,
};

(async () => {
  writeFileSync(join(dir, 'web-batting-order.pdf'), await battingOrderPdf(input));
  writeFileSync(join(dir, 'web-coaches-guide.pdf'), await coachesGuidePdf(input));
  console.log(`wrote ${dir}/web-{batting-order,coaches-guide}.pdf`);
})();
