// Merge 3: game logs record which scheduled game they came from and who
// archived them (20261123000000_game_log_archiver).
import { after, before, describe, test } from 'node:test';
import assert from 'node:assert/strict';

import { asAnon, asUser, createUser, freshDb, uuid } from './harness.mjs';

let db;
before(async () => { db = await freshDb(); });
after(async () => { await db.close(); });

async function makeTeam(userId) {
  const team = uuid();
  const lineup = uuid();
  const game = uuid();
  await asUser(db, userId, async (d) => {
    await d.query(`insert into public.teams (id, name, coach_name) values ($1, 'Tigers', 'Team Owner')`, [team]);
    await d.query(`insert into public.scheduled_games (id, team_id, ical_uid, starts_at) values ($1, $2, $3, now())`,
      [game, team, `uid-${game}`]);
    await d.query(`insert into public.lineups (id, team_id, scheduled_game_id, opponent) values ($1, $2, $3, 'Eagles')`,
      [lineup, team, game]);
  });
  return { team, lineup, game };
}

const log = async (id) => (await db.query(
  'select scheduled_game_id, archived_by_user, archived_by_name, archived_by from public.game_logs where id = $1', [id])).rows[0];

describe('game log archiver', () => {
  test('archive_game records the scheduled game and the coach who archived it', async () => {
    const coach = await createUser(db);
    await db.query(`update public.profiles set display_name = ' Sam Rivera ' where id = $1`, [coach]);
    const { lineup, game } = await makeTeam(coach);
    const id = await asUser(db, coach, async (d) =>
      (await d.query(`select public.archive_game($1, 6) as id`, [lineup])).rows[0].id);
    const r = await log(id);
    assert.equal(r.scheduled_game_id, game);
    assert.equal(r.archived_by_user, coach);
    assert.equal(r.archived_by_name, 'Sam Rivera', 'trimmed profile name');
    assert.equal(r.archived_by, 'Team Owner', 'the old text column is unchanged');
  });

  test('falls back to the sign-in name, then to empty', async () => {
    const google = await createUser(db);
    await db.query(`update auth.users set raw_user_meta_data = '{"full_name":"Jo Park"}' where id = $1`, [google]);
    const a = await makeTeam(google);
    const id = await asUser(db, google, async (d) => (await d.query(`select public.archive_game($1, 6) as id`, [a.lineup])).rows[0].id);
    assert.equal((await log(id)).archived_by_name, 'Jo Park');

    const nameless = await createUser(db);
    const b = await makeTeam(nameless);
    const id2 = await asUser(db, nameless, async (d) => (await d.query(`select public.archive_game($1, 6) as id`, [b.lineup])).rows[0].id);
    assert.equal((await log(id2)).archived_by_name, '');
  });

  test('a client-written log is stamped by the server, and the stamp never changes', async () => {
    const coach = await createUser(db);
    const other = await createUser(db);
    await db.query(`update public.profiles set display_name = 'Real Coach' where id = $1`, [coach]);
    const { team, game } = await makeTeam(coach);
    const id = uuid();
    await asUser(db, coach, async (d) => {
      // What the iOS sync sends: its own row, claiming someone else.
      await d.query(
        `insert into public.game_logs (id, team_id, game_date, innings_played, scheduled_game_id, archived_by_user, archived_by_name)
         values ($1, $2, now(), 6, $3, $4, 'Spoofed')`, [id, team, game, other]);
      const r = await log(id);
      assert.equal(r.scheduled_game_id, game, 'the client says which game');
      assert.equal(r.archived_by_user, coach, 'but not who archived it');
      assert.equal(r.archived_by_name, 'Real Coach');

      await d.query(`update public.game_logs set notes = 'later', archived_by_user = $2, archived_by_name = 'X' where id = $1`, [id, other]);
      const after = await log(id);
      assert.equal(after.archived_by_user, coach);
      assert.equal(after.archived_by_name, 'Real Coach');
    });
  });

  test('the trigger function cannot be called directly', async () => {
    const coach = await createUser(db);
    await asAnon(db, (d) => assert.rejects(d.query('select public.stamp_archiver()'), /permission denied for function/));
    await asUser(db, coach, (d) => assert.rejects(d.query('select public.stamp_archiver()'), /permission denied for function/));
  });
});
