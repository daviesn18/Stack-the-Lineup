#!/usr/bin/env node
// Turns a real .stlteam export into a fixture that is safe to commit.
//
//   node scripts/anonymize-stlteam.mjs fixtures/private/<real>.stlteam fixtures/<name>.stlteam
//
// This repo is PUBLIC. Real exports carry kids' names and a private calendar
// subscription link (the GameChanger URL embeds an account token), so they live
// only in fixtures/private/ (gitignored). This script replaces every name,
// opponent, location and link, keeps all IDs and structure (UUIDs identify
// nothing on their own), and then refuses to write if any original name string
// survives anywhere in the output.

import { readFileSync, writeFileSync } from 'node:fs';

const [src, dest] = process.argv.slice(2);
if (!src || !dest) {
  console.error('usage: anonymize-stlteam.mjs <input.stlteam> <output.stlteam>');
  process.exit(1);
}

const file = JSON.parse(readFileSync(src, 'utf8'));
const team = file.team;
const secrets = new Set();
const remember = (s) => typeof s === 'string' && s.trim().length >= 2 && secrets.add(s.trim());

// Players: "Player 01" … with a stable per-player surname so sort order holds.
const nameFor = new Map();
(team.players ?? []).forEach((p, i) => {
  remember(p.firstName);
  remember(p.lastName);
  const n = String(i + 1).padStart(2, '0');
  nameFor.set(p.id, { firstName: `Player`, lastName: n });
  p.firstName = 'Player';
  p.lastName = n;
});

// Game-log roster snapshots reuse the same fake names.
for (const log of team.gameLogs ?? []) {
  remember(log.opponent);
  log.opponent = 'Opponent';
  log.notes = log.notes ? 'Sample notes.' : '';
  if (log.archivedBy) log.archivedBy = 'Coach';
  for (const s of log.playerSnapshot ?? []) {
    remember(s.firstName);
    remember(s.lastName);
    Object.assign(s, nameFor.get(s.id) ?? { firstName: 'Former', lastName: 'Player' });
  }
}

// Schedule: opponents, locations and raw calendar text.
const opponents = new Map();
const letter = (o) => {
  if (!opponents.has(o)) opponents.set(o, `Opponent ${String.fromCharCode(65 + opponents.size)}`);
  return opponents.get(o);
};
for (const g of team.scheduledGames ?? []) {
  remember(g.opponent);
  remember(g.location);
  remember(g.rawSummary);
  if (g.opponent) g.opponent = letter(g.opponent);
  if (g.location) g.location = 'Sample Field';
  g.rawSummary = g.opponent ? `vs ${g.opponent}` : 'Game';
}

// Lineups (live + per-game) carry an opponent string.
const scrubLineup = (l) => {
  if (l && l.opponent) {
    remember(l.opponent);
    l.opponent = letter(l.opponent);
  }
  if (l && l.lastFinalizedBy) l.lastFinalizedBy = 'Coach';
};
scrubLineup(team.lineup);
for (let i = 1; i < (team.gameLineups ?? []).length; i += 2) scrubLineup(team.gameLineups[i]);

remember(team.name);
remember(team.coachName);
team.name = 'Sample Team';
team.coachName = 'Coach';
if (team.calendarSubscriptionURL) {
  secrets.add(team.calendarSubscriptionURL);
  team.calendarSubscriptionURL = 'https://example.com/calendar.ics';
}
for (const t of team.lineupTemplates ?? []) {
  remember(t.name);
  t.name = 'Sample Template';
}

const out = JSON.stringify(file, null, 2) + '\n';

// Guard: no original string may survive. Short tokens (e.g. a two-letter
// surname) are matched as whole quoted JSON values to avoid false alarms.
const leaks = [...secrets].filter((s) =>
  s.length >= 4 ? out.toLowerCase().includes(s.toLowerCase()) : out.includes(JSON.stringify(s)),
);
if (leaks.length) {
  console.error(`Refusing to write: ${leaks.length} original value(s) still present.`);
  process.exit(2);
}

writeFileSync(dest, out);
console.log(`Wrote ${dest}: ${team.players?.length ?? 0} players, ${team.gameLogs?.length ?? 0} game logs, ` +
  `${team.scheduledGames?.length ?? 0} scheduled games. ${secrets.size} values scrubbed.`);
