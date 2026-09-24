// The engines the parity tests check, as they get ported (Web 7).
//
// Each group stays undefined until its TypeScript port lands; the parity tests
// show those scenarios as pending rather than failing. When a port lands,
// register it here and its fixtures start running.

import * as fairPlay from '../fairPlay';
import type { FairPlayFindings } from '../fairPlay';
import { fill } from '../autofillEngine';
import * as parser from '../autofillParser';
import type {
  AutoFillInput, AutoFillResult, AutoFillScope, ConstraintSet, ConstraintTarget, OverrideReason,
  PlayerConstraint, UnfilledReason,
} from '../autofillTypes';
import * as pitching from '../pitching';
import type { PitchEligibilityStatus, PitchingSummaryRow } from '../pitching';
import type {
  FairPlayConfig, FieldPosition, GameLog, Lineup, PitchingConfig, Player, PlayerID,
} from '../model';

export type {
  AutoFillInput, AutoFillResult, AutoFillScope, ConstraintSet, ConstraintTarget, FairPlayFindings,
  OverrideReason, PitchEligibilityStatus, PitchingSummaryRow, PlayerConstraint, UnfilledReason,
};

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

/** Registered ports; groups not yet ported stay undefined. */
export const engines: Engines = {
  fairPlay: {
    activeFieldPositions: fairPlay.activeFieldPositions,
    openPositions: fairPlay.openPositions,
    fairPlayFindings: fairPlay.fairPlayFindings,
    backToBackBenchInnings: fairPlay.backToBackBenchInnings,
  },
  pitching: {
    compute: pitching.compute,
    status: pitching.status,
    pitchingSummaryRows: pitching.pitchingSummaryRows,
    coachesGuideSummary: pitching.coachesGuideSummary,
    pitchesRemaining: pitching.pitchesRemaining,
    startOfPitchingWeek: pitching.startOfPitchingWeek,
  },
  parser: {
    parseDeterministically: (players, inningCount, prompt) =>
      new parser.AutoFillParser(players, inningCount).parseDeterministically(prompt),
    detectedPatternRules: parser.detectedPatternRules,
    shouldTrustDeterministic: parser.shouldTrustDeterministic,
  },
  autofill: { fill },
};
