// .stlteam writer — the TypeScript counterpart of TeamExporter.swift.
//
// Writes what Swift's JSONEncoder would for the same Team, so the iPhone app
// can import a team built on the web:
//  * dictionaries keyed by a UUID or an enum are FLAT ARRAYS [k1, v1, k2, v2]
//    (assignments, positionPreferences, ageLimits, gameLineups);
//  * ClosedRange is [lo, hi];
//  * dates are ISO 8601 with whole seconds (Swift's .iso8601 strategy rejects
//    fractional seconds on decode);
//  * nil optionals are left out, and keys are sorted (.sortedKeys).
//
// As on iOS, the open lineup is not exported: the importing device starts
// with a fresh one. Saved per-game lineups (gameLineups) do travel.
//
// Keep this in step with stlteam.ts; the round-trip test reads the output back.

import {
  emptyLineup,
  type FairPlayConfig, type GameLog, type InningAssignment, type Lineup, type LineupTemplate,
  type PitchingConfig, type Player, type ScheduledGame, type Team,
} from './model';

type Json = string | number | boolean | Json[] | { [k: string]: Json | undefined } | undefined;

/** Swift's .iso8601: `2026-11-06T18:04:05Z`, no milliseconds. */
export const swiftDate = (d: Date) => d.toISOString().replace(/\.\d{3}Z$/, 'Z');

const flat = <V>(o: Record<string, V | undefined>, value: (v: V) => Json): Json[] =>
  Object.entries(o).flatMap(([k, v]) => (v === undefined ? [] : [k, value(v)]));

const inning = (a: InningAssignment): Json => ({ assignments: flat(a.assignments, (p) => p) });

function player(p: Player): Json {
  const arch = p.hittingArchetype;
  return {
    id: p.id,
    firstName: p.firstName,
    lastName: p.lastName,
    number: p.number,
    leagueAge: p.leagueAge,
    positionPreferences: flat(p.positionPreferences, (t) => t),
    hittingArchetype: arch && (arch.hitting || arch.speed || arch.onBase)
      ? { hitting: arch.hitting, speed: arch.speed, onBase: arch.onBase }
      : undefined,
  };
}

function lineup(l: Lineup): Json {
  return {
    gameDate: swiftDate(l.gameDate),
    opponent: l.opponent,
    battingOrder: l.battingOrder,
    innings: l.innings.map(inning),
    absentPlayerIDs: l.absentPlayerIDs,
    status: l.status,
    lastFinalizedBy: l.lastFinalizedBy,
    lastFinalizedAt: l.lastFinalizedAt && swiftDate(l.lastFinalizedAt),
    defaultTemplateID: l.defaultTemplateID,
  };
}

function pitchingConfig(c: PitchingConfig): Json {
  return {
    rulesEnabled: c.rulesEnabled,
    ageLimits: flat(c.ageLimits, (l) => ({ ...l })),
    weeklyLimitEnabled: c.weeklyLimitEnabled,
    weeklyLimit: c.weeklyLimit,
    rollingWindowType: c.rollingWindowType,
    rollingWindowDays: c.rollingWindowDays,
  };
}

// pausedRules is web-only and iOS ignores it, so the iPhone sees what the web
// enforces (rules off while paused) and a web re-import keeps the coach's values.
const fairPlayConfig = (c: FairPlayConfig): Json => ({ ...c } as Json);

const template = (t: LineupTemplate): Json => ({
  id: t.id,
  name: t.name,
  battingOrder: t.battingOrder,
  positionLocks: t.positionLocks.map((l) => ({ id: l.id, playerID: l.playerID, position: l.position, innings: [...l.innings] })),
  createdAt: swiftDate(t.createdAt),
});

const gameLog = (g: GameLog): Json => ({
  id: g.id,
  gameDate: swiftDate(g.gameDate),
  opponent: g.opponent,
  inningsPlayed: g.inningsPlayed,
  battingOrder: g.battingOrder,
  innings: g.innings.map(inning),
  playerSnapshot: g.playerSnapshot.map((s) => ({ id: s.id, firstName: s.firstName, lastName: s.lastName, number: s.number })),
  archivedAt: swiftDate(g.archivedAt),
  pitchCounts: { ...g.pitchCounts },
  archivedBy: g.archivedBy,
  notes: g.notes,
});

const scheduledGame = (g: ScheduledGame): Json => ({
  id: g.id,
  icalUID: g.icalUID,
  date: swiftDate(g.date),
  opponent: g.opponent,
  location: g.location,
  rawSummary: g.rawSummary,
  isCancelled: g.isCancelled,
  lastSyncedAt: swiftDate(g.lastSyncedAt),
});

function teamJson(t: Team): Json {
  return {
    id: t.id,
    name: t.name,
    colorHex: t.colorHex,
    players: t.players.map(player),
    lineup: lineup(emptyLineup(t.gameInningCount)),
    gameLogs: t.gameLogs.map(gameLog),
    createdAt: swiftDate(t.createdAt),
    gameInningCount: t.gameInningCount,
    scheduledGames: t.scheduledGames.map(scheduledGame),
    calendarSubscriptionURL: t.calendarSubscriptionURL,
    fairPlayConfig: fairPlayConfig(t.fairPlayConfig),
    pitchingConfig: pitchingConfig(t.pitchingConfig),
    coachName: t.coachName,
    isReadOnly: false,
    lineupTemplates: t.lineupTemplates.map(template),
    defaultTemplateID: t.defaultTemplateID,
    gameLineups: flat(t.gameLineups, lineup),
    currentGameID: t.currentGameID,
  };
}

/** JSON.stringify with every object's keys sorted and undefined dropped (.sortedKeys). */
function sortedStringify(v: Json): string {
  const sort = (x: Json): Json => {
    if (Array.isArray(x)) return x.map(sort);
    if (x && typeof x === 'object') {
      const out: Record<string, Json> = {};
      for (const k of Object.keys(x).sort()) if (x[k] !== undefined) out[k] = sort(x[k]);
      return out;
    }
    return x;
  };
  return JSON.stringify(sort(v), null, 2);
}

/** The text of a .stlteam file (format v1) for this team. */
export function writeStlTeam(team: Team, appVersion: string, exportedAt = new Date()): string {
  return sortedStringify({ version: 1, exportedAt: swiftDate(exportedAt), appVersion, team: teamJson(team) });
}

/** TeamExporter.filename: `Team_Name_2026-11-06.stlteam`, local date. */
export function stlTeamFilename(teamName: string, now = new Date()): string {
  const pad = (n: number) => String(n).padStart(2, '0');
  const date = `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`;
  const safe = teamName.trim().replace(/ /g, '_').replace(/[^\p{L}\p{N}_-]/gu, '');
  return `${safe || 'Team'}_${date}.stlteam`;
}
