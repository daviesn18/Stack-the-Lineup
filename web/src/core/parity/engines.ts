// The engines the parity tests check, as they get ported (Web 7).
//
// Each group stays undefined until its TypeScript port lands; the parity tests
// show those scenarios as pending rather than failing. When a port lands,
// register it here and its fixtures start running.

import type {
  FairPlayConfig, FieldPosition, GameLog, Lineup, PitchingConfig, Player, PlayerID,
} from '../model';

export interface FairPlayFindings {
  withoutInfield: Player[];
  withoutOutfield: Player[];
  underFieldingMinimum: Player[];
  backToBackBench: Player[];
  catcherThenPitcher: Player[];
  pitcherThenCatcher: Player[];
  minimumFieldingInnings: number;
}

export type PitchEligibilityStatus =
  | { kind: 'eligible' }
  | { kind: 'limited'; remaining: number }
  | { kind: 'mustRest'; until: Date }
  | { kind: 'unknownAge' };

export interface PitchingSummaryRow {
  player: Player;
  pitchesInWindow: number;
  dailyMax: number;
  available: number;
  restDaysRequired: number;
  status: PitchEligibilityStatus;
}

export type ConstraintTarget =
  | { kind: 'position'; position: FieldPosition }
  | { kind: 'infield' }
  | { kind: 'outfield' }
  | { kind: 'bench' };

export interface PlayerConstraint {
  playerID: PlayerID;
  target: ConstraintTarget;
  /** Zero-based, inclusive. */
  inningRange: [number, number];
  intent: 'assign' | 'avoid' | 'prioritize';
}

export interface ConstraintSet {
  playerConstraints: PlayerConstraint[];
  patternRules: { benchInConsecutivePairs: boolean };
}

export type UnfilledReason = 'rosterTooSmall' | 'neverPreferences' | 'pitcherReentry' | 'pitchCapacityLimited';
export type OverrideReason =
  | 'pitcherSoftCapBypassed'
  | 'pitcherSoftCapBypassedByFallback'
  | 'benchedOutOfTurn'
  | 'fairPlayZoneSkipped.infield'
  | 'fairPlayZoneSkipped.outfield';

export interface AutoFillResult {
  lineup: Lineup;
  filledCount: number;
  unfilledSlots: { inningIndex: number; position: FieldPosition; reason: UnfilledReason }[];
  constraintOverrides: { inningIndex: number; playerID: PlayerID; reason: OverrideReason }[];
  constraintRejections: { inningIndex: number; playerID: PlayerID; reason: string }[];
}

export type AutoFillScope = { kind: 'game' } | { kind: 'through'; inning: number } | { kind: 'inning'; inning: number };

export interface AutoFillInput {
  scope: AutoFillScope;
  lineup: Lineup;
  players: Player[];
  config: FairPlayConfig;
  pitchingConfig?: PitchingConfig;
  gameLogs: GameLog[];
  constraints: ConstraintSet;
  /** iOS reads "today" internally; the port takes it explicitly. */
  referenceDate: Date;
}

export interface Engines {
  fairPlay?: {
    activeFieldPositions(config: FairPlayConfig): FieldPosition[];
    openPositions(lineup: Lineup, inning: number, players: Player[], config: FairPlayConfig): FieldPosition[];
    fairPlayFindings(lineup: Lineup, players: Player[], config: FairPlayConfig): FairPlayFindings;
    backToBackBenchInnings(lineup: Lineup, player: Player): [number, number][];
  };
  pitching?: {
    compute(gameLogs: GameLog[], players: Player[], config: PitchingConfig, referenceDate: Date):
      Record<PlayerID, PitchEligibilityStatus>;
    status(player: Player, gameLogs: GameLog[], config: PitchingConfig, referenceDate: Date): PitchEligibilityStatus;
    pitchingSummaryRows(gameLogs: GameLog[], players: Player[], config: PitchingConfig, referenceDate: Date):
      PitchingSummaryRow[];
    coachesGuideSummary(gameLogs: GameLog[], players: Player[], config: PitchingConfig, referenceDate: Date):
      PitchingSummaryRow[] | null;
    pitchesRemaining(player: Player, gameLogs: GameLog[], config: PitchingConfig, referenceDate: Date): number | null;
    startOfPitchingWeek(date: Date): Date;
  };
  parser?: {
    parseDeterministically(players: Player[], inningCount: number, prompt: string):
      { constraints: PlayerConstraint[]; hasUnresolvedInstruction: boolean };
    detectedPatternRules(prompt: string): { benchInConsecutivePairs: boolean };
    shouldTrustDeterministic(
      parse: { constraints: PlayerConstraint[]; hasUnresolvedInstruction: boolean },
      patternDetected: boolean,
    ): boolean;
  };
  autofill?: {
    fill(input: AutoFillInput): AutoFillResult;
  };
}

/** Registered ports. Empty until Web 7 lands each engine. */
export const engines: Engines = {};
