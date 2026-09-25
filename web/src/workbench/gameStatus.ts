// Derived game-prep status shared by Home, the sidebar and the game page:
// who's coming, fair play, finalized, and how ready the game is.

import { openPositions } from '@/core/fairPlay';
import type { Lineup } from '@/core/model';

import type { Workbench } from './state';

export const gameTitle = (l: Lineup) => (l.opponent ? `vs ${l.opponent}` : 'Next game');

export const gameWhen = (d: Date) =>
  `${d.toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' })} · ${d.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' })}`;

/** "Fall 2026": Mar-Jul is spring, Aug-Nov fall, the rest winter. */
export function seasonLabel(d: Date) {
  const m = d.getMonth();
  const season = m >= 2 && m <= 6 ? 'Spring' : m >= 7 && m <= 10 ? 'Fall' : 'Winter';
  return `${season} ${d.getFullYear()}`;
}

export const plural = (n: number, word: string) => `${n} ${word}${n === 1 ? '' : 's'}`;

export function gameStatus(w: Pick<Workbench, 'lineup' | 'players' | 'active' | 'issues' | 'team'>) {
  const here = w.active.length;
  const total = w.players.length;
  const finalized = w.lineup.status === 'finalized';
  // Until the first position is set there's nothing to check: every spot is open by definition.
  const started = w.lineup.innings.some((inn) => Object.keys(inn.assignments).length > 0);
  const issueCount = started ? w.issues.length : 0;
  const fpOk = started && issueCount === 0;
  const open = w.lineup.innings.reduce((n, _, i) => n + openPositions(w.lineup, i, w.players, w.team.fairPlayConfig).length, 0);
  // A quarter each: attendance and batting order (always set), fair play, finalized.
  const readiness = 50 + (fpOk ? 25 : 0) + (finalized ? 25 : 0);
  return { here, total, fpOk, finalized, started, open, readiness, issueCount };
}
