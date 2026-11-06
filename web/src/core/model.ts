// Domain model — a TypeScript mirror of the iOS types in Models.swift.
//
// Field names and enum raw values match Swift exactly so .stlteam files and
// the shared parity fixtures round-trip without translation. Dictionaries that
// Swift keys by UUID or enum are plain Records here; the flat [k, v, k, v]
// encoding Swift uses on the wire is handled in stlteam.ts, not in the model.
//
// Pure data and small helpers only: no React, no Supabase.

export const FIELD_POSITIONS = [
  'P', 'C', '1B', '2B', 'SS', '3B', 'LF', 'LCF', 'CF', 'RCF', 'RF',
] as const;
export const ALL_POSITIONS = [...FIELD_POSITIONS, 'Bench', 'ABS'] as const;

export type FieldPosition = (typeof ALL_POSITIONS)[number];
export type FieldingPosition = (typeof FIELD_POSITIONS)[number];

const INFIELD: ReadonlySet<FieldPosition> = new Set(['P', 'C', '1B', '2B', 'SS', '3B']);
const OUTFIELD: ReadonlySet<FieldPosition> = new Set(['LF', 'LCF', 'CF', 'RCF', 'RF']);

export const isInfield = (p: FieldPosition) => INFIELD.has(p);
export const isOutfield = (p: FieldPosition) => OUTFIELD.has(p);
/** Bench or ABS: does not count as a fielding inning. */
export const isNonFielding = (p: FieldPosition) => p === 'Bench' || p === 'ABS';

export const POSITION_NAMES: Record<FieldPosition, string> = {
  P: 'Pitcher', C: 'Catcher', '1B': '1st Base', '2B': '2nd Base', SS: 'Shortstop',
  '3B': '3rd Base', LF: 'Left Field', LCF: 'Left Center', CF: 'Center Field',
  RCF: 'Right Center', RF: 'Right Field', Bench: 'Bench', ABS: 'Absent',
};

export type PositionPreferenceTier = 'Strength' | 'Capable' | 'Emergency' | 'Never';
export type LeagueRuleset = 'Little League' | 'Cal Ripken' | 'Babe Ruth' | 'Custom';
export type PitchingAgeBracket = '7-8' | '9-10' | '11-12' | '13-14' | '15-16';
export type RollingWindowType = 'Calendar Week' | 'Rolling 7 Days';
export type HittingStyle = 'Power' | 'Gap' | 'Singles';
export type SpeedRating = 'Fast' | 'Medium' | 'Slow';
export type OnBaseRating = 'High' | 'Medium' | 'Low';
export type LineupStatus = 'draft' | 'finalized';

/** Player UUID string. Always upper-case, as Swift writes it. */
export type PlayerID = string;

export interface HittingArchetype {
  hitting?: HittingStyle;
  speed?: SpeedRating;
  onBase?: OnBaseRating;
}

export interface Player {
  id: PlayerID;
  firstName: string;
  lastName: string;
  number: string;
  leagueAge?: number;
  positionPreferences: Partial<Record<FieldPosition, PositionPreferenceTier>>;
  hittingArchetype?: HittingArchetype;
}

export interface InningAssignment {
  assignments: Record<PlayerID, FieldPosition>;
}

export interface Lineup {
  gameDate: Date;
  opponent: string;
  battingOrder: PlayerID[];
  /** Runtime source of truth for inning count is innings.length, as on iOS. */
  innings: InningAssignment[];
  absentPlayerIDs: PlayerID[];
  status: LineupStatus;
  lastFinalizedBy?: string;
  lastFinalizedAt?: Date;
  defaultTemplateID?: string;
}

export interface PitchingLimits {
  dailyMax: number;
  restDay1Min: number;
  restDay2Min: number;
  restDay3Min?: number;
  restDay4Min?: number;
}

export interface PitchingConfig {
  rulesEnabled: boolean;
  ageLimits: Partial<Record<PitchingAgeBracket, PitchingLimits>>;
  weeklyLimitEnabled: boolean;
  weeklyLimit: number;
  rollingWindowType: RollingWindowType;
  rollingWindowDays: number;
}

export interface FairPlayConfig {
  noPitcher: boolean;
  noCatcher: boolean;
  outfielderCount: number;
  noConsecutiveBench: boolean;
  noConsecutivePosition: boolean;
  equalBenchTime: boolean;
  noRepeatPositions: boolean;
  minimumFieldingInnings: number;
  minimumInfieldInnings: number;
  minimumOutfieldInnings: number;
  catcherToPitcherThreshold: number;
  pitcherToCatcherThreshold: number;
  leagueRuleset: LeagueRuleset;
  /**
   * Web only. While fair play is paused the rule fields above are all off, so
   * the engine and the checks need no special case; the coach's own values
   * wait here until they turn it back on. iOS ignores the key.
   */
  pausedRules?: Partial<FairPlayConfig>;
}

export interface PositionLock {
  id: string;
  playerID: PlayerID;
  position: FieldPosition;
  /** 0-based inclusive range, [first, last]. Swift ClosedRange<Int>. */
  innings: [number, number];
}

export interface LineupTemplate {
  id: string;
  name: string;
  battingOrder: PlayerID[];
  positionLocks: PositionLock[];
  createdAt: Date;
}

export interface PlayerSnapshot {
  id: PlayerID;
  firstName: string;
  lastName: string;
  number: string;
}

export interface GameLog {
  id: string;
  gameDate: Date;
  opponent: string;
  inningsPlayed: number;
  battingOrder: PlayerID[];
  innings: InningAssignment[];
  playerSnapshot: PlayerSnapshot[];
  archivedAt: Date;
  /** Keyed by player UUID string. */
  pitchCounts: Record<PlayerID, number>;
  archivedBy: string;
  notes: string;
}

export interface ScheduledGame {
  id: string;
  icalUID: string;
  date: Date;
  opponent?: string;
  location?: string;
  rawSummary: string;
  isCancelled: boolean;
  lastSyncedAt: Date;
}

export interface Team {
  id: string;
  name: string;
  colorHex: string;
  players: Player[];
  lineup: Lineup;
  gameLogs: GameLog[];
  createdAt: Date;
  gameInningCount: number;
  scheduledGames: ScheduledGame[];
  calendarSubscriptionURL?: string;
  fairPlayConfig: FairPlayConfig;
  pitchingConfig: PitchingConfig;
  coachName: string;
  lineupTemplates: LineupTemplate[];
  defaultTemplateID?: string;
  /** Keyed by ScheduledGame.id. */
  gameLineups: Record<string, Lineup>;
  currentGameID?: string;
}

// MARK: - Defaults (mirror the Swift property defaults)

export const DEFAULT_INNING_COUNT = 7;

export const defaultFairPlayConfig = (): FairPlayConfig => ({
  noPitcher: false,
  noCatcher: false,
  outfielderCount: 3,
  noConsecutiveBench: true,
  noConsecutivePosition: false,
  equalBenchTime: false,
  noRepeatPositions: false,
  minimumFieldingInnings: 4,
  minimumInfieldInnings: 1,
  minimumOutfieldInnings: 1,
  catcherToPitcherThreshold: 0,
  pitcherToCatcherThreshold: 0,
  leagueRuleset: 'Custom',
});

export const defaultPitchingConfig = (): PitchingConfig => ({
  rulesEnabled: false,
  ageLimits: {},
  weeklyLimitEnabled: false,
  weeklyLimit: 0,
  rollingWindowType: 'Rolling 7 Days',
  rollingWindowDays: 7,
});

export const emptyLineup = (inningCount = DEFAULT_INNING_COUNT): Lineup => ({
  gameDate: new Date(),
  opponent: '',
  battingOrder: [],
  innings: Array.from({ length: inningCount }, () => ({ assignments: {} })),
  absentPlayerIDs: [],
  status: 'draft',
});

export const displayName = (p: Pick<Player, 'firstName' | 'lastName'>) =>
  `${p.firstName} ${p.lastName}`;
