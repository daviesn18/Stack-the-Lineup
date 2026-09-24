// .stlteam reader — the TypeScript counterpart of TeamImporter.swift.
//
// Two things make this more than JSON.parse:
//
// 1. Swift's JSONEncoder writes a dictionary whose key is not String/Int (a
//    UUID or an enum) as a FLAT ARRAY: [k1, v1, k2, v2]. That covers
//    InningAssignment.assignments, positionPreferences, ageLimits and
//    gameLineups. pitchCounts is [String: Int], so it is a normal object.
//
// 2. The iOS decoders are deliberately forgiving, field by field: a bad or
//    missing field falls back to a default instead of failing the whole team.
//    Where Swift uses `(try? c.decode(...)) ?? default`, this file uses
//    `field(...)` with the same default. Where Swift decodes strictly
//    (synthesized Codable, or a plain `try`), a failure here throws, and the
//    nearest forgiving parent catches it — exactly as on iOS, including the
//    sharp edge that one malformed player empties the whole `players` array.
//
// Keep this file in step with Models.swift; the parity fixtures catch drift.

import {
  ALL_POSITIONS, DEFAULT_INNING_COUNT, defaultFairPlayConfig, defaultPitchingConfig,
  emptyLineup,
  type FairPlayConfig, type FieldPosition, type GameLog, type HittingArchetype,
  type InningAssignment, type Lineup, type LineupTemplate, type PitchingAgeBracket,
  type PitchingConfig, type PitchingLimits, type Player, type PlayerSnapshot,
  type PositionLock, type PositionPreferenceTier, type ScheduledGame, type Team,
} from './model';

export type ImportErrorKind = 'invalidData' | 'unsupportedVersion';

export class TeamImportError extends Error {
  constructor(public kind: ImportErrorKind, public formatVersion?: number) {
    // Same wording as TeamImporter.ImportError so coaches see one voice.
    super(
      kind === 'unsupportedVersion'
        ? `This file was created with a newer version of Stack the Lineup (format v${formatVersion}). Update the app and try again.`
        : "The file doesn't look like a valid team file. Make sure it was exported from Stack the Lineup.",
    );
  }
}

export interface ImportedTeam {
  team: Team;
  exportedAt: Date;
  appVersion: string;
}

/** Parses the text of a .stlteam file. Throws TeamImportError. */
export function parseStlTeam(text: string): ImportedTeam {
  let env: unknown;
  try {
    env = JSON.parse(text);
  } catch {
    throw new TeamImportError('invalidData');
  }
  try {
    const o = obj(env);
    const version = int(o.version);
    const exportedAtRaw = str(o.exportedAt);
    const appVersion = str(o.appVersion);
    const team = decodeTeam(o.team);
    if (version !== 1) throw new TeamImportError('unsupportedVersion', version);
    return { team, exportedAt: tryDate(exportedAtRaw) ?? new Date(), appVersion };
  } catch (e) {
    if (e instanceof TeamImportError) throw e;
    throw new TeamImportError('invalidData');
  }
}

// MARK: - Primitive decoders (throw on mismatch, like Swift's strict decode)

class DecodeError extends Error {}
const fail = (what: string): never => {
  throw new DecodeError(what);
};

function obj(v: unknown): Record<string, unknown> {
  return v !== null && typeof v === 'object' && !Array.isArray(v)
    ? (v as Record<string, unknown>)
    : fail('object');
}
function arr(v: unknown): unknown[] {
  return Array.isArray(v) ? v : fail('array');
}
function str(v: unknown): string {
  return typeof v === 'string' ? v : fail('string');
}
function bool(v: unknown): boolean {
  return typeof v === 'boolean' ? v : fail('bool');
}
/** Swift Int rejects fractional numbers. */
function int(v: unknown): number {
  return typeof v === 'number' && Number.isInteger(v) ? v : fail('int');
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
/** Swift accepts either case and always writes upper-case. */
function uuid(v: unknown): string {
  const s = str(v);
  return UUID_RE.test(s) ? s.toUpperCase() : fail('uuid');
}

// .iso8601 strategy: internet date-time, whole seconds, no fractional part.
const ISO_RE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(Z|[+-]\d{2}:?\d{2})$/;
function date(v: unknown): Date {
  const s = str(v);
  const d = ISO_RE.test(s) ? new Date(s) : null;
  return d && !Number.isNaN(d.getTime()) ? d : fail('date');
}
function tryDate(s: string): Date | undefined {
  try {
    return date(s);
  } catch {
    return undefined;
  }
}

function oneOf<T extends string>(allowed: readonly T[]) {
  return (v: unknown): T => {
    const s = str(v);
    return (allowed as readonly string[]).includes(s) ? (s as T) : fail('enum');
  };
}

/** `(try? decode) ?? fallback` — the forgiving field pattern from Models.swift. */
function field<T>(decode: () => T, fallback: T): T {
  try {
    return decode();
  } catch {
    return fallback;
  }
}
/** `try? decode` for optionals: missing or malformed both become undefined. */
function optional<T>(v: unknown, decode: (v: unknown) => T): T | undefined {
  if (v === undefined || v === null) return undefined;
  try {
    return decode(v);
  } catch {
    return undefined;
  }
}

/**
 * A Swift dictionary with a non-String key: [k1, v1, k2, v2]. A key or value
 * that fails to decode fails the whole dictionary, as in Swift.
 */
function flatDict<K extends string, V>(
  v: unknown,
  key: (k: unknown) => K,
  value: (v: unknown) => V,
): Partial<Record<K, V>> {
  const a = arr(v);
  if (a.length % 2 !== 0) fail('odd dictionary');
  const out: Partial<Record<K, V>> = {};
  for (let i = 0; i < a.length; i += 2) out[key(a[i])] = value(a[i + 1]);
  return out;
}

// MARK: - Enums with custom Swift decoders

/** FieldPosition.init(from:) — unknown raw values become Bench. */
function position(v: unknown): FieldPosition {
  const s = str(v);
  return (ALL_POSITIONS as readonly string[]).includes(s) ? (s as FieldPosition) : 'Bench';
}

/** PositionPreferenceTier.init(from:) — legacy names map forward, else Capable. */
function tier(v: unknown): PositionPreferenceTier {
  const s = str(v);
  switch (s) {
    case 'Strength': case 'Capable': case 'Emergency': case 'Never': return s;
    case 'Primary': return 'Strength';
    default: return 'Capable';
  }
}

const bracket = oneOf<PitchingAgeBracket>(['7-8', '9-10', '11-12', '13-14', '15-16']);

// MARK: - Struct decoders

function inningAssignment(v: unknown): InningAssignment {
  // Synthesized Codable: `assignments` is required.
  return { assignments: flatDict(obj(v).assignments, uuid, position) as Record<string, FieldPosition> };
}

function hittingArchetype(v: unknown): HittingArchetype {
  const o = obj(v);
  return {
    hitting: optional(o.hitting, oneOf(['Power', 'Gap', 'Singles'] as const)),
    speed: optional(o.speed, oneOf(['Fast', 'Medium', 'Slow'] as const)),
    onBase: optional(o.onBase, oneOf(['High', 'Medium', 'Low'] as const)),
  };
}

function player(v: unknown): Player {
  const o = obj(v);
  // id, firstName, lastName, number are load-bearing: failures propagate.
  const p: Player = {
    id: uuid(o.id),
    firstName: str(o.firstName),
    lastName: str(o.lastName),
    number: str(o.number),
    positionPreferences: field(() => flatDict(o.positionPreferences, position, tier), {}),
  };
  if (o.leagueAge !== undefined && o.leagueAge !== null) p.leagueAge = int(o.leagueAge);
  const arch = optional(o.hittingArchetype, hittingArchetype);
  if (arch) p.hittingArchetype = arch;
  return p;
}

function lineup(v: unknown): Lineup {
  const o = obj(v);
  const l: Lineup = {
    gameDate: field(() => date(o.gameDate), new Date()),
    opponent: field(() => str(o.opponent), ''),
    battingOrder: field(() => arr(o.battingOrder).map(uuid), []),
    innings: field(() => arr(o.innings).map(inningAssignment), emptyLineup().innings),
    absentPlayerIDs: field(() => [...new Set(arr(o.absentPlayerIDs).map(uuid))], []),
    status: field(() => oneOf(['draft', 'finalized'] as const)(o.status), 'draft'),
  };
  const by = optional(o.lastFinalizedBy, str);
  if (by !== undefined) l.lastFinalizedBy = by;
  const at = optional(o.lastFinalizedAt, date);
  if (at) l.lastFinalizedAt = at;
  const tpl = optional(o.defaultTemplateID, uuid);
  if (tpl) l.defaultTemplateID = tpl;
  return l;
}

function pitchingLimits(v: unknown): PitchingLimits {
  const o = obj(v);
  const l: PitchingLimits = {
    dailyMax: field(() => int(o.dailyMax), 85),
    restDay1Min: field(() => int(o.restDay1Min), 1),
    restDay2Min: field(() => int(o.restDay2Min), 36),
  };
  const r3 = optional(o.restDay3Min, int);
  if (r3 !== undefined) l.restDay3Min = r3;
  const r4 = optional(o.restDay4Min, int);
  if (r4 !== undefined) l.restDay4Min = r4;
  return l;
}

function pitchingConfig(v: unknown): PitchingConfig {
  const o = obj(v);
  const d = defaultPitchingConfig();
  return {
    rulesEnabled: field(() => bool(o.rulesEnabled), d.rulesEnabled),
    ageLimits: field(() => flatDict(o.ageLimits, bracket, pitchingLimits), d.ageLimits),
    weeklyLimitEnabled: field(() => bool(o.weeklyLimitEnabled), d.weeklyLimitEnabled),
    weeklyLimit: field(() => int(o.weeklyLimit), d.weeklyLimit),
    rollingWindowType: field(
      () => oneOf(['Calendar Week', 'Rolling 7 Days'] as const)(o.rollingWindowType),
      d.rollingWindowType,
    ),
    rollingWindowDays: field(() => int(o.rollingWindowDays), d.rollingWindowDays),
  };
}

function fairPlayConfig(v: unknown): FairPlayConfig {
  const o = obj(v);
  const d = defaultFairPlayConfig();
  const b = (k: keyof FairPlayConfig) => field(() => bool(o[k]), d[k] as boolean);
  const n = (k: keyof FairPlayConfig) => field(() => int(o[k]), d[k] as number);
  return {
    noPitcher: b('noPitcher'),
    noCatcher: b('noCatcher'),
    outfielderCount: n('outfielderCount'),
    noConsecutiveBench: b('noConsecutiveBench'),
    noConsecutivePosition: b('noConsecutivePosition'),
    equalBenchTime: b('equalBenchTime'),
    noRepeatPositions: b('noRepeatPositions'),
    minimumFieldingInnings: n('minimumFieldingInnings'),
    minimumInfieldInnings: n('minimumInfieldInnings'),
    minimumOutfieldInnings: n('minimumOutfieldInnings'),
    catcherToPitcherThreshold: n('catcherToPitcherThreshold'),
    pitcherToCatcherThreshold: n('pitcherToCatcherThreshold'),
    leagueRuleset: field(
      () => oneOf(['Little League', 'Cal Ripken', 'Babe Ruth', 'Custom'] as const)(o.leagueRuleset),
      d.leagueRuleset,
    ),
  };
}

function positionLock(v: unknown): PositionLock {
  // Synthesized Codable: every key required. ClosedRange encodes as [lo, hi].
  const o = obj(v);
  const range = arr(o.innings).map(int);
  if (range.length !== 2 || range[0] > range[1]) fail('range');
  return {
    id: uuid(o.id),
    playerID: uuid(o.playerID),
    position: position(o.position),
    innings: [range[0], range[1]],
  };
}

function lineupTemplate(v: unknown): LineupTemplate {
  const o = obj(v);
  return {
    id: field(() => uuid(o.id), newUUID()),
    name: field(() => str(o.name), ''),
    battingOrder: field(() => arr(o.battingOrder).map(uuid), []),
    positionLocks: field(() => arr(o.positionLocks).map(positionLock), []),
    createdAt: field(() => date(o.createdAt), new Date()),
  };
}

function playerSnapshot(v: unknown): PlayerSnapshot {
  const o = obj(v);
  return { id: uuid(o.id), firstName: str(o.firstName), lastName: str(o.lastName), number: str(o.number) };
}

function gameLog(v: unknown): GameLog {
  const o = obj(v);
  return {
    id: field(() => uuid(o.id), newUUID()),
    gameDate: date(o.gameDate),
    opponent: str(o.opponent),
    inningsPlayed: int(o.inningsPlayed),
    battingOrder: arr(o.battingOrder).map(uuid),
    innings: arr(o.innings).map(inningAssignment),
    playerSnapshot: arr(o.playerSnapshot).map(playerSnapshot),
    archivedAt: field(() => date(o.archivedAt), new Date()),
    pitchCounts: field(() => {
      const pc = obj(o.pitchCounts);
      return Object.fromEntries(Object.entries(pc).map(([k, n]) => [k.toUpperCase(), int(n)]));
    }, {}),
    archivedBy: field(() => str(o.archivedBy), ''),
    notes: field(() => str(o.notes), ''),
  };
}

function scheduledGame(v: unknown): ScheduledGame {
  // Synthesized Codable: every non-optional key is required.
  const o = obj(v);
  const g: ScheduledGame = {
    id: uuid(o.id),
    icalUID: str(o.icalUID),
    date: date(o.date),
    rawSummary: str(o.rawSummary),
    isCancelled: bool(o.isCancelled),
    lastSyncedAt: date(o.lastSyncedAt),
  };
  if (o.opponent !== undefined && o.opponent !== null) g.opponent = str(o.opponent);
  if (o.location !== undefined && o.location !== null) g.location = str(o.location);
  return g;
}

function decodeTeam(v: unknown): Team {
  const o = obj(v);
  const t: Team = {
    id: field(() => uuid(o.id), newUUID()),
    name: field(() => str(o.name), ''),
    colorHex: field(() => str(o.colorHex), '0000FF'),
    players: field(() => arr(o.players).map(player), []),
    lineup: field(() => lineup(o.lineup), emptyLineup()),
    gameLogs: field(() => arr(o.gameLogs).map(gameLog), []),
    createdAt: field(() => date(o.createdAt), new Date()),
    gameInningCount: field(() => int(o.gameInningCount), DEFAULT_INNING_COUNT),
    scheduledGames: field(() => arr(o.scheduledGames).map(scheduledGame), []),
    fairPlayConfig: field(() => fairPlayConfig(o.fairPlayConfig), defaultFairPlayConfig()),
    pitchingConfig: field(() => pitchingConfig(o.pitchingConfig), defaultPitchingConfig()),
    coachName: field(() => str(o.coachName), ''),
    lineupTemplates: field(() => arr(o.lineupTemplates).map(lineupTemplate), []),
    gameLineups: field(
      () => flatDict(o.gameLineups, uuid, lineup) as Record<string, Lineup>,
      {},
    ),
  };
  const url = optional(o.calendarSubscriptionURL, str);
  if (url !== undefined) t.calendarSubscriptionURL = url;
  const tpl = optional(o.defaultTemplateID, uuid);
  if (tpl) t.defaultTemplateID = tpl;
  const game = optional(o.currentGameID, uuid);
  if (game) t.currentGameID = game;
  // ckRecordName / isReadOnly / isSharedParticipant / updatedAt are CloudKit
  // bookkeeping; the web app does not carry them (see the schema design doc).
  return t;
}

function newUUID(): string {
  return crypto.randomUUID().toUpperCase();
}
