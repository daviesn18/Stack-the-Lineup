// Turns a decoded .stlteam Team into the payload for the `import_team`
// database function (supabase/migrations/20260924000100_write_functions.sql).
//
// Pure: no network. The database is strict (composite team keys, one fielder
// per position, fielding-only template locks), and real iOS data isn't always
// that tidy, so this cleans what iOS itself tolerates rather than letting one
// bad cell fail the whole import. Everything dropped or changed is reported in
// `notes` so the import screen can say so.
//
// How the iOS lineup model maps (see the schema design doc):
//  * Team.lineup is the lineup being edited. When currentGameID is set it IS
//    that game's lineup (iOS swaps it out of gameLineups while it's open), so
//    it's imported attached to that game and becomes current_lineup_id.
//    (The .stlteam export blanks it, so it arrives empty.)
//  * Team.gameLineups[gameID] are the other games' saved lineups.

import { isNonFielding, type FieldPosition, type Lineup, type Team } from '../core/model';

export interface ImportPayload {
  team: Record<string, unknown>;
  players: Record<string, unknown>[];
  scheduled_games: Record<string, unknown>[];
  lineup_templates: Record<string, unknown>[];
  lineups: Record<string, unknown>[];
  game_logs: Record<string, unknown>[];
}

export interface PayloadResult {
  payload: ImportPayload;
  /** Coach-readable notes about anything cleaned up. Empty when the file was clean. */
  notes: string[];
}

const clamp = (n: number, lo: number, hi: number) => Math.max(lo, Math.min(hi, n));
const iso = (d: Date) => d.toISOString();

/**
 * InningAssignment.deduplicatingFieldingPositions: when two players hold one
 * fielding position, the one earliest in the batting order keeps it and the
 * others are left unassigned (not benched), so the cell shows as open.
 */
export function dedupeInning(
  assignments: Record<string, FieldPosition>, battingOrder: string[],
): { kept: Record<string, FieldPosition>; dropped: number } {
  const rank = (id: string) => {
    const i = battingOrder.indexOf(id);
    return i < 0 ? Number.MAX_SAFE_INTEGER : i;
  };
  const ordered = Object.entries(assignments).sort(([a], [b]) => rank(a) - rank(b) || (a < b ? -1 : a > b ? 1 : 0));
  const taken = new Set<FieldPosition>();
  const kept: Record<string, FieldPosition> = {};
  let dropped = 0;
  for (const [id, pos] of ordered) {
    if (isNonFielding(pos)) kept[id] = pos;
    else if (!taken.has(pos)) { taken.add(pos); kept[id] = pos; }
    else dropped += 1;
  }
  return { kept, dropped };
}

export function toImportPayload(team: Team, newId: () => string = () => crypto.randomUUID()): PayloadResult {
  const notes: string[] = [];
  const playerIds = new Set(team.players.map((p) => p.id));
  const gameIds = new Set(team.scheduledGames.map((g) => g.id));

  const players = team.players.map((p, i) => ({
    id: p.id,
    first_name: p.firstName,
    last_name: p.lastName,
    number: p.number,
    league_age: p.leagueAge ?? null,
    position_preferences: p.positionPreferences,
    hitting_style: p.hittingArchetype?.hitting ?? null,
    speed: p.hittingArchetype?.speed ?? null,
    on_base: p.hittingArchetype?.onBase ?? null,
    roster_order: i,
  }));

  const scheduled_games = team.scheduledGames.map((g) => ({
    id: g.id,
    ical_uid: g.icalUID,
    starts_at: iso(g.date),
    opponent: g.opponent ?? null,
    location: g.location ?? null,
    raw_summary: g.rawSummary,
    is_cancelled: g.isCancelled,
    last_synced_at: iso(g.lastSyncedAt),
  }));

  let droppedLocks = 0;
  const lineup_templates = team.lineupTemplates.map((t) => ({
    id: t.id,
    name: t.name,
    batting_order: t.battingOrder,
    created_at: iso(t.createdAt),
    locks: t.positionLocks
      .filter((l) => {
        const ok = !isNonFielding(l.position) && playerIds.has(l.playerID);
        if (!ok) droppedLocks += 1;
        return ok;
      })
      .map((l) => ({
        id: l.id,
        player_id: l.playerID,
        position: l.position,
        first_inning: clamp(l.innings[0], 0, 8),
        last_inning: clamp(l.innings[1], 0, 8),
      })),
  }));
  if (droppedLocks) notes.push(`${droppedLocks} template lock(s) pointed at a removed player and were skipped.`);
  const templateIds = new Set(team.lineupTemplates.map((t) => t.id));

  let droppedCells = 0;
  let dedupedCells = 0;
  const lineupRow = (l: Lineup, scheduledGameId: string | null) => {
    const inningCount = clamp(l.innings.length || team.gameInningCount, 1, 9);
    const cells: Record<string, Record<string, FieldPosition>> = {};
    for (let i = 0; i < inningCount; i++) {
      const known: Record<string, FieldPosition> = {};
      for (const [id, pos] of Object.entries(l.innings[i]?.assignments ?? {})) {
        if (playerIds.has(id)) known[id] = pos;
        else droppedCells += 1;
      }
      const { kept, dropped } = dedupeInning(known, l.battingOrder);
      dedupedCells += dropped;
      if (Object.keys(kept).length) cells[String(i)] = kept;
    }
    return {
      id: newId(),
      scheduled_game_id: scheduledGameId,
      game_date: iso(l.gameDate),
      opponent: l.opponent,
      inning_count: inningCount,
      batting_order: l.battingOrder,
      absent_player_ids: l.absentPlayerIDs,
      status: l.status,
      last_finalized_by: l.lastFinalizedBy ?? null,
      last_finalized_at: l.lastFinalizedAt ? iso(l.lastFinalizedAt) : null,
      default_template_id: l.defaultTemplateID && templateIds.has(l.defaultTemplateID) ? l.defaultTemplateID : null,
      cells,
    };
  };

  const currentGame = team.currentGameID && gameIds.has(team.currentGameID) ? team.currentGameID : null;
  const working = lineupRow(team.lineup, currentGame && !(currentGame in team.gameLineups) ? currentGame : null);
  const lineups = [working];
  let orphanLineups = 0;
  for (const [gameId, l] of Object.entries(team.gameLineups)) {
    if (!gameIds.has(gameId)) { orphanLineups += 1; continue; }
    if (gameId === working.scheduled_game_id) continue;
    lineups.push(lineupRow(l, gameId));
  }
  if (orphanLineups) notes.push(`${orphanLineups} saved lineup(s) belonged to games no longer on the schedule and were skipped.`);
  if (droppedCells) notes.push(`${droppedCells} lineup cell(s) referred to players no longer on the roster and were skipped.`);
  if (dedupedCells) notes.push(`${dedupedCells} lineup cell(s) doubled up a position in the same inning; the player higher in the batting order kept it, and the rest are left open.`);

  const game_logs = team.gameLogs.map((g) => ({
    id: g.id,
    game_date: iso(g.gameDate),
    opponent: g.opponent,
    innings_played: clamp(g.inningsPlayed, 1, 9),
    batting_order: g.battingOrder,
    innings: g.innings.map((inn) => inn.assignments),
    player_snapshot: g.playerSnapshot,
    archived_at: iso(g.archivedAt),
    archived_by: g.archivedBy,
    notes: g.notes,
    pitch_counts: Object.fromEntries(
      Object.entries(g.pitchCounts).filter(([, n]) => Number.isInteger(n) && n >= 0 && n <= 200),
    ),
  }));

  const colorOk = /^[0-9A-Fa-f]{6}$/.test(team.colorHex);
  const payload: ImportPayload = {
    team: {
      id: team.id,
      name: team.name,
      color_hex: colorOk ? team.colorHex : '0000FF',
      coach_name: team.coachName,
      game_inning_count: clamp(team.gameInningCount, 3, 9),
      fair_play_config: team.fairPlayConfig,
      pitching_config: team.pitchingConfig,
      calendar_subscription_url: team.calendarSubscriptionURL ?? null,
      created_at: iso(team.createdAt),
      default_template_id: team.defaultTemplateID && templateIds.has(team.defaultTemplateID) ? team.defaultTemplateID : null,
      current_lineup_id: working.id,
    },
    players,
    scheduled_games,
    lineup_templates,
    lineups,
    game_logs,
  };
  return { payload, notes };
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * The same team under fresh ids, for when another account already owns these
 * ids (two coaches of one shared iOS team each importing it). Every id the
 * payload defines gets a new one, and every reference to it (batting orders,
 * cell keys, snapshots, pitch counts, pointers) follows, whatever its case.
 * Strings that aren't ids the payload defines are left alone.
 */
export function asSeparateCopy(payload: ImportPayload, newId: () => string = () => crypto.randomUUID()): ImportPayload {
  const map = new Map<string, string>();
  const define = (id: unknown) => {
    if (typeof id === 'string' && UUID_RE.test(id) && !map.has(id.toUpperCase())) {
      map.set(id.toUpperCase(), newId().toUpperCase());
    }
  };
  define(payload.team.id);
  for (const list of [payload.players, payload.scheduled_games, payload.lineup_templates, payload.lineups, payload.game_logs]) {
    for (const row of list) define(row.id);
  }
  for (const t of payload.lineup_templates) for (const l of (t.locks as { id: string }[])) define(l.id);

  const swap = (s: string) => (UUID_RE.test(s) ? map.get(s.toUpperCase()) ?? s : s);
  const walk = (v: unknown): unknown => {
    if (typeof v === 'string') return swap(v);
    if (Array.isArray(v)) return v.map(walk);
    if (v && typeof v === 'object') {
      return Object.fromEntries(Object.entries(v).map(([k, x]) => [swap(k), walk(x)]));
    }
    return v;
  };
  return walk(payload) as ImportPayload;
}
