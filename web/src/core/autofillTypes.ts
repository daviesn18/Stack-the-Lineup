// Auto-Fill types shared by the parser, the engine and the UI. Shapes mirror
// AutoFillConstraints.swift / AutoFillResult in AutoFillEngine.swift.

import type { FairPlayConfig, FieldPosition, GameLog, Lineup, PitchingConfig, Player, PlayerID } from './model';

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
  constraintOverrides: { inningIndex: number; playerID: PlayerID; target: ConstraintTarget; reason: OverrideReason }[];
  constraintRejections: { inningIndex: number; playerID: PlayerID; target: ConstraintTarget; reason: string }[];
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
