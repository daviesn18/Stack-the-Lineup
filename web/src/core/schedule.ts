// Picking a game from the imported schedule (SchedulePickerView and
// LineupStore.applyScheduledGame in Models.swift).
//
// Each scheduled game keeps its own lineup, which is what lets a coach build
// both games of a doubleheader. On the web a lineup is a row in `lineups`
// with scheduled_game_id set, and teams.current_lineup_id is the open one, so
// "stashing" the outgoing lineup is free: it's already saved in its own row.

import type { ScheduledGame } from './model';

/** ICalParser.practiceKeywords. */
export const PRACTICE_KEYWORDS = [
  'practice', 'batting practice', 'bp', 'team practice',
  'infield', 'skills', 'clinic', 'workout', 'scrimmage',
  'tryout', 'try-out', 'warm-up', 'warmup',
];

export const isPractice = (summary: string) => {
  const lower = summary.toLowerCase();
  return PRACTICE_KEYWORDS.some((k) => lower.includes(k));
};

/** The picker's list: from the start of today, not cancelled, no practices, soonest first. */
export function upcomingGames(games: ScheduledGame[], now = new Date()): ScheduledGame[] {
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
  return games
    .filter((g) => !g.isCancelled && g.date.getTime() >= today && !isPractice(g.rawSummary))
    .sort((a, b) => a.date.getTime() - b.date.getTime());
}

/** A scheduled game's saved lineup, as the picker needs it. */
export interface SavedGameLineup {
  lineupId: string;
  status: 'draft' | 'finalized';
  /** SchedulePickerView only shows a status when the lineup has something in it. */
  hasContent: boolean;
}

export type OpenGamePlan =
  /** The game is already open. */
  | { kind: 'noop' }
  /** Reopen the game's saved lineup exactly as it was left. */
  | { kind: 'reopen'; lineupId: string }
  /** First time attaching the ad-hoc lineup to a game: keep it, stamp the game's date and opponent. */
  | { kind: 'stamp' }
  /** Moving from one game to another with no lineup yet: start a fresh one. */
  | { kind: 'fresh' };

/** applyScheduledGame's three paths. */
export function planOpenGame(
  gameId: string, currentGameId: string | undefined, saved: Record<string, SavedGameLineup>,
): OpenGamePlan {
  if (gameId === currentGameId) return { kind: 'noop' };
  const s = saved[gameId];
  if (s) return { kind: 'reopen', lineupId: s.lineupId };
  return currentGameId === undefined ? { kind: 'stamp' } : { kind: 'fresh' };
}

/** "vs Opponent", or the calendar's own title when no opponent was parsed. */
export const scheduledTitle = (g: ScheduledGame) => (g.opponent ? `vs ${g.opponent}` : g.rawSummary || 'Game');
