// End-to-end .stlteam import: file -> parseStlTeam -> toImportPayload ->
// the real import_team function, as a signed-in coach, in PGlite.
// Runs on the committed anonymized sample, plus any real export in
// fixtures/private/ (local only; gitignored).

import { afterEach, beforeEach, describe, test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

import { parseStlTeam } from '../../src/core/stlteam';
import { asSeparateCopy, dedupeInning, toImportPayload } from '../../src/data/teamPayload';
import { asUser, createUser, freshDb } from './harness.mjs';

const FIXTURES = join(import.meta.dirname, '../../fixtures');
const files = [
  join(FIXTURES, 'sample-fall-team.stlteam'),
  ...(existsSync(join(FIXTURES, 'private'))
    ? readdirSync(join(FIXTURES, 'private')).filter((f) => f.endsWith('.stlteam')).map((f) => join(FIXTURES, 'private', f))
    : []),
];

// A fresh database per test: the anonymized sample keeps the real export's
// ids (so they'd collide in one database), and team ids are global.
let db: any;
beforeEach(async () => { db = await freshDb(); });
afterEach(async () => { await db.close(); });

for (const file of files) {
  const label = file.includes('/private/') ? 'private export' : 'committed sample';

  describe(`import ${label}`, () => {
    const { team } = parseStlTeam(readFileSync(file, 'utf8'));
    const { payload, notes } = toImportPayload(team);

    test('the database accepts it and keeps every player, game and lineup cell', async () => {
      const coach = await createUser(db);
      await asUser(db, coach, async (d: any) => {
        const { rows: [{ id }] } = await d.query('select public.import_team($1) as id', [payload]);
        assert.equal(id.toUpperCase(), team.id);

        const count = async (sql: string) => Number((await d.query(sql, [id])).rows[0].n);
        assert.equal(await count('select count(*) n from public.players where team_id = $1'), team.players.length);
        assert.equal(await count('select count(*) n from public.scheduled_games where team_id = $1'), team.scheduledGames.length);
        assert.equal(await count('select count(*) n from public.game_logs where team_id = $1'), team.gameLogs.length);
        assert.equal(await count('select count(*) n from public.lineups where team_id = $1'), payload.lineups.length);

        const expectedCells = payload.lineups.reduce(
          (n, l: any) => n + Object.values(l.cells as Record<string, object>).reduce((m, inn) => m + Object.keys(inn).length, 0), 0);
        assert.equal(await count('select count(*) n from public.lineup_cells where team_id = $1'), expectedCells);

        const { rows: [t] } = await d.query(
          `select t.game_inning_count, t.fair_play_config, l.scheduled_game_id
           from public.teams t join public.lineups l on l.id = t.current_lineup_id where t.id = $1`, [id]);
        assert.equal(t.game_inning_count, team.gameInningCount);
        assert.deepEqual(t.fair_play_config, JSON.parse(JSON.stringify(team.fairPlayConfig)));
        if (team.currentGameID) assert.equal(t.scheduled_game_id?.toUpperCase(), team.currentGameID);
      });
    });

    test('saved per-game lineups arrive attached to their games', () => {
      const attached = payload.lineups.filter((l: any) => l.scheduled_game_id).map((l: any) => l.scheduled_game_id);
      for (const gameId of Object.keys(team.gameLineups)) assert.ok(attached.includes(gameId));
      assert.equal(new Set(attached).size, attached.length, 'one lineup per game');
    });

    test('a clean iOS file needs no cleanup notes', () => {
      assert.deepEqual(notes, []);
    });
  });
}

describe('cleanup of untidy iOS data', () => {
  test('a doubled-up position keeps the player higher in the batting order and leaves the rest open', () => {
    const { kept, dropped } = dedupeInning({ A: 'SS', B: 'SS', C: 'Bench', D: 'Bench' }, ['B', 'A', 'C', 'D']);
    assert.deepEqual(kept, { B: 'SS', C: 'Bench', D: 'Bench' });
    assert.equal(dropped, 1);
  });

  test('cells and locks for removed players, and lineups for removed games, are skipped with a note', async () => {
    const { team } = parseStlTeam(readFileSync(files[0], 'utf8'));
    const ghost = '00000000-0000-4000-8000-00000000DEAD';
    const game = Object.keys(team.gameLineups)[0];
    team.gameLineups[game].innings[0].assignments[ghost] = 'P';
    team.gameLineups['00000000-0000-4000-8000-00000000BEEF'] = team.gameLineups[game];
    team.lineupTemplates.push({
      id: '00000000-0000-4000-8000-00000000F00D', name: 'T', battingOrder: [], createdAt: new Date(),
      positionLocks: [{ id: '00000000-0000-4000-8000-00000000CAFE', playerID: ghost, position: 'P', innings: [0, 1] }],
    });
    const { payload, notes } = toImportPayload(team);
    assert.equal(notes.length, 3, notes.join(' | '));

    const coach = await createUser(db);
    await asUser(db, coach, (d: any) => d.query('select public.import_team($1)', [payload]));
  });
});

describe('two coaches importing the same shared team', () => {
  test("the second coach's plain import is refused, and a separate copy works with every reference intact", async () => {
    const { team } = parseStlTeam(readFileSync(files[files.length - 1], 'utf8'));
    const { payload } = toImportPayload(team);
    const [a, b] = [await createUser(db), await createUser(db)];
    await asUser(db, a, (d: any) => d.query('select public.import_team($1)', [payload]));
    await asUser(db, b, async (d: any) => {
      await assert.rejects(d.query('select public.import_team($1, true)', [payload]), (e: any) => e.code === '23505');
      const copy = asSeparateCopy(payload);
      const { rows: [{ id }] } = await d.query('select public.import_team($1) as id', [copy]);
      assert.notEqual(id.toUpperCase(), team.id);
      const n = async (sql: string) => Number((await d.query(sql, [id])).rows[0].n);
      assert.equal(await n('select count(*) n from public.players where team_id = $1'), team.players.length);
      const cells = payload.lineups.reduce(
        (k, l: any) => k + Object.values(l.cells as Record<string, object>).reduce((m, inn) => m + Object.keys(inn).length, 0), 0);
      assert.equal(await n('select count(*) n from public.lineup_cells where team_id = $1'), cells);
      // No id from the original survives anywhere in the copy.
      const text = JSON.stringify(copy).toUpperCase();
      for (const p of team.players) assert.ok(!text.includes(p.id), 'player id remapped');
    });
  });
});
