// One team, loaded from Supabase, with edits applied to the screen at once and
// saved in the background, strictly in order (a queue), so quick grid edits
// can't land out of sequence. If a save fails the team is reloaded from the
// database and the error is shown: the screen never pretends a failed save
// worked.

import { createContext, useCallback, useContext, useEffect, useRef, useState, type ReactNode } from 'react';

import { addToBattingOrder, changedInnings, completeBattingOrder, removePlayer } from '../core/lineupOps';
import {
  defaultFairPlayConfig, defaultPitchingConfig, type FairPlayConfig, type FieldPosition, type GameLog, type Lineup,
  type PitchingConfig, type Player,
} from '../core/model';
import { supabase } from './supabase';
import { upperId } from './teams';

export interface TeamInfo {
  id: string;
  name: string;
  colorHex: string;
  coachName: string;
  gameInningCount: number;
  fairPlayConfig: FairPlayConfig;
  pitchingConfig: PitchingConfig;
}

export interface TeamData {
  team: TeamInfo;
  players: Player[];
  /** The lineup open for editing (teams.current_lineup_id). */
  lineup: Lineup & { id: string };
  /** Archived games, newest first, with pitch counts (pitch rules read these). */
  gameLogs: GameLog[];
}

type Row = Record<string, any>;

const up = (ids: string[] | null | undefined) => (ids ?? []).map(upperId);
const upKeys = <T,>(o: Record<string, T>) => Object.fromEntries(Object.entries(o ?? {}).map(([k, v]) => [upperId(k), v]));

function toPlayer(r: Row): Player {
  const p: Player = {
    id: upperId(r.id), firstName: r.first_name, lastName: r.last_name, number: r.number,
    positionPreferences: r.position_preferences ?? {},
  };
  if (r.league_age !== null) p.leagueAge = r.league_age;
  if (r.hitting_style || r.speed || r.on_base) {
    p.hittingArchetype = {
      ...(r.hitting_style ? { hitting: r.hitting_style } : {}),
      ...(r.speed ? { speed: r.speed } : {}),
      ...(r.on_base ? { onBase: r.on_base } : {}),
    };
  }
  return p;
}

function toLineup(r: Row): Lineup & { id: string } {
  const innings = Array.from({ length: r.inning_count }, () => ({ assignments: {} as Record<string, FieldPosition> }));
  for (const c of r.lineup_cells ?? []) {
    if (innings[c.inning]) innings[c.inning].assignments[upperId(c.player_id)] = c.position;
  }
  return {
    id: upperId(r.id),
    gameDate: new Date(r.game_date),
    opponent: r.opponent,
    battingOrder: up(r.batting_order),
    innings,
    absentPlayerIDs: up(r.absent_player_ids),
    status: r.status,
    ...(r.last_finalized_by ? { lastFinalizedBy: r.last_finalized_by } : {}),
    ...(r.last_finalized_at ? { lastFinalizedAt: new Date(r.last_finalized_at) } : {}),
    ...(r.default_template_id ? { defaultTemplateID: upperId(r.default_template_id) } : {}),
  };
}

function toGameLog(r: Row): GameLog {
  return {
    id: upperId(r.id), gameDate: new Date(r.game_date), opponent: r.opponent, inningsPlayed: r.innings_played,
    battingOrder: up(r.batting_order),
    innings: (r.innings ?? []).map((a: Record<string, FieldPosition>) => ({ assignments: upKeys(a) })),
    playerSnapshot: r.player_snapshot ?? [], archivedAt: new Date(r.archived_at), archivedBy: r.archived_by,
    notes: r.notes,
    pitchCounts: Object.fromEntries((r.pitch_counts ?? []).map((pc: Row) => [upperId(pc.player_id), pc.pitches])),
  };
}

async function must<T>(p: PromiseLike<{ data: T; error: { message: string } | null }>): Promise<T> {
  const { data, error } = await p;
  if (error) throw new Error(error.message);
  return data;
}

export async function loadTeam(teamId: string): Promise<TeamData> {
  const t = await must(supabase.from('teams').select('*').eq('id', teamId).single());
  let lineupId: string | null = t.current_lineup_id;
  if (!lineupId) {
    // A team with no open lineup (new team, or every lineup archived): start one.
    lineupId = crypto.randomUUID();
    await must(supabase.from('lineups').insert({ id: lineupId, team_id: teamId, inning_count: t.game_inning_count }));
    await must(supabase.from('teams').update({ current_lineup_id: lineupId }).eq('id', teamId));
  }
  const [players, lineup, logs] = await Promise.all([
    must(supabase.from('players').select('*').eq('team_id', teamId).is('deleted_at', null)
      .order('roster_order').order('created_at')),
    must(supabase.from('lineups').select('*, lineup_cells(inning, player_id, position)').eq('id', lineupId).single()),
    must(supabase.from('game_logs').select('*, pitch_counts(player_id, pitches)').eq('team_id', teamId)
      .is('deleted_at', null).order('game_date', { ascending: false })),
  ]);
  const roster = (players as Row[]).map(toPlayer);
  const saved = toLineup(lineup);
  const complete = { ...completeBattingOrder(saved, roster), id: saved.id };
  if (complete.battingOrder !== saved.battingOrder) {
    // Repair a partial batting order once, so every screen and printout has everyone.
    await must(supabase.from('lineups').update({ batting_order: complete.battingOrder }).eq('id', saved.id));
  }
  return {
    team: {
      id: upperId(t.id), name: t.name, colorHex: t.color_hex, coachName: t.coach_name,
      gameInningCount: t.game_inning_count,
      fairPlayConfig: { ...defaultFairPlayConfig(), ...(t.fair_play_config ?? {}) },
      pitchingConfig: { ...defaultPitchingConfig(), ...(t.pitching_config ?? {}) },
    },
    players: roster,
    lineup: complete,
    gameLogs: (logs as Row[]).map(toGameLog),
  };
}

// MARK: - Persistence of a lineup change

async function saveLineup(before: Lineup & { id: string }, after: Lineup & { id: string }) {
  const innings = changedInnings(before, after);
  if (innings.length) {
    const body = Object.fromEntries(innings.map((i) => [String(i), after.innings[i].assignments]));
    await must(supabase.rpc('save_innings', { p_lineup_id: after.id, p_innings: body }));
  }
  const fields: Row = {};
  const same = (a: unknown, b: unknown) => JSON.stringify(a) === JSON.stringify(b);
  if (!same(before.battingOrder, after.battingOrder)) fields.batting_order = after.battingOrder;
  if (!same(before.absentPlayerIDs, after.absentPlayerIDs)) fields.absent_player_ids = after.absentPlayerIDs;
  if (before.opponent !== after.opponent) fields.opponent = after.opponent;
  if (before.gameDate.getTime() !== after.gameDate.getTime()) fields.game_date = after.gameDate.toISOString();
  if (before.status !== after.status || before.lastFinalizedAt?.getTime() !== after.lastFinalizedAt?.getTime()) {
    fields.status = after.status;
    fields.last_finalized_by = after.lastFinalizedBy ?? null;
    fields.last_finalized_at = after.lastFinalizedAt?.toISOString() ?? null;
  }
  if (before.innings.length !== after.innings.length) fields.inning_count = after.innings.length;
  if (Object.keys(fields).length) await must(supabase.from('lineups').update(fields).eq('id', after.id));
}

// MARK: - Store

interface TeamStore {
  data: TeamData | null;
  loadError: string | null;
  saveError: string | null;
  saving: boolean;
  dismissSaveError(): void;
  /** Apply a lineup edit now; save it in the background. */
  editLineup(edit: (l: Lineup) => Lineup): void;
  addPlayer(p: Omit<Player, 'id'>): void;
  updatePlayer(p: Player): void;
  deletePlayer(id: string): void;
  reload(): Promise<void>;
}

const Ctx = createContext<TeamStore | null>(null);

/**
 * `demo` (development only) runs the store on in-memory data: nothing is
 * loaded from or saved to Supabase. Used by the /dev-grid preview.
 */
export function TeamProvider({ teamId, demo, children }: { teamId: string; demo?: TeamData; children: ReactNode }) {
  const [data, setData] = useState<TeamData | null>(demo ?? null);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [saveError, setSaveError] = useState<string | null>(null);
  const [pending, setPending] = useState(0);
  const current = useRef<TeamData | null>(null);
  const queue = useRef<Promise<void>>(Promise.resolve());

  const set = (next: TeamData) => { current.current = next; setData(next); };

  const reload = useCallback(async () => {
    try { set(await loadTeam(teamId)); setLoadError(null); } catch (e) { setLoadError((e as Error).message); }
  }, [teamId]);

  // Initial load: state is only set when the fetch resolves, and never after unmount.
  useEffect(() => {
    if (demo) { current.current = demo; return; }
    let live = true;
    loadTeam(teamId).then(
      (d) => { if (live) { current.current = d; setData(d); } },
      (e: Error) => { if (live) setLoadError(e.message); },
    );
    return () => { live = false; };
  }, [teamId, demo]);

  /** Runs `work` after every earlier save; on failure, reload and report. */
  const enqueue = useCallback((work: () => Promise<void>) => {
    if (demo) return;
    setPending((n) => n + 1);
    queue.current = queue.current.then(work).catch(async (e: Error) => {
      setSaveError(`${e.message}. Your last change wasn't saved; the lineup has been reloaded.`);
      await reload();
    }).finally(() => setPending((n) => n - 1));
  }, [reload, demo]);

  const editLineup = useCallback((edit: (l: Lineup) => Lineup) => {
    const now = current.current;
    if (!now) return;
    const next = { ...edit(now.lineup), id: now.lineup.id };
    set({ ...now, lineup: next });
    enqueue(() => saveLineup(now.lineup, next));
  }, [enqueue]);

  const addPlayer = useCallback((fields: Omit<Player, 'id'>) => {
    const now = current.current;
    if (!now) return;
    const player: Player = { ...fields, id: crypto.randomUUID().toUpperCase() };
    const lineup = { ...addToBattingOrder(now.lineup, player.id), id: now.lineup.id };
    set({ ...now, players: [...now.players, player], lineup });
    enqueue(async () => {
      await must(supabase.from('players').insert({ ...playerRow(player), team_id: now.team.id, roster_order: now.players.length }));
      await saveLineup(now.lineup, lineup);
    });
  }, [enqueue]);

  const updatePlayer = useCallback((player: Player) => {
    const now = current.current;
    if (!now) return;
    set({ ...now, players: now.players.map((p) => (p.id === player.id ? player : p)) });
    enqueue(async () => { await must(supabase.from('players').update(playerRow(player)).eq('id', player.id)); });
  }, [enqueue]);

  const deletePlayer = useCallback((id: string) => {
    const now = current.current;
    if (!now) return;
    const lineup = { ...removePlayer(now.lineup, id), id: now.lineup.id };
    set({ ...now, players: now.players.filter((p) => p.id !== id), lineup });
    enqueue(async () => {
      // Soft delete keeps the player recoverable; their cells go, as on iOS.
      await must(supabase.from('players').update({ deleted_at: new Date().toISOString() }).eq('id', id));
      await must(supabase.from('lineup_cells').delete().eq('player_id', id));
      await saveLineup({ ...now.lineup, innings: lineup.innings }, lineup);
    });
  }, [enqueue]);

  const store: TeamStore = {
    data, loadError, saveError, saving: pending > 0, dismissSaveError: () => setSaveError(null),
    editLineup, addPlayer, updatePlayer, deletePlayer, reload,
  };
  return <Ctx.Provider value={store}>{children}</Ctx.Provider>;
}

function playerRow(p: Player) {
  return {
    id: p.id, first_name: p.firstName, last_name: p.lastName, number: p.number,
    league_age: p.leagueAge ?? null, position_preferences: p.positionPreferences,
    hitting_style: p.hittingArchetype?.hitting ?? null, speed: p.hittingArchetype?.speed ?? null,
    on_base: p.hittingArchetype?.onBase ?? null,
  };
}

export function useTeam(): TeamStore {
  const s = useContext(Ctx);
  if (!s) throw new Error('useTeam outside TeamProvider');
  return s;
}
