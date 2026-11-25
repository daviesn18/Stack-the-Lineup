// Merge 5: push for account teams (20261125000000_push). The database sends
// the push: these check who it goes to, when it fires and when it doesn't,
// and the device-token functions. net.http_post is the harness stand-in, so
// each "push" is a row in net.calls.
import { after, before, beforeEach, describe, test } from 'node:test';
import assert from 'node:assert/strict';

import { asAnon, asUser, createUser, freshDb, uuid } from './harness.mjs';

let db;
before(async () => {
  db = await freshDb();
  await db.query(`insert into vault.decrypted_secrets values
    ('push_worker_url', 'https://push.example.com/'), ('push_worker_secret', 's3cret')`);
});
after(async () => { await db.close(); });
beforeEach(async () => { await db.query('delete from net.calls'); });

const hex = (n) => n.toString(16).padStart(2, '0').repeat(32);
const calls = async () => (await db.query('select url, body, headers from net.calls order by id')).rows;

const register = (user, token, env = 'production') =>
  asUser(db, user, (d) => d.query(`select public.register_device_token($1, 'ios', $2, '4.0')`, [token, env]));

/** Owner with Pro, a team and a draft lineup; an editor who joined; a device each. */
async function sharedTeam() {
  const owner = await createUser(db), editor = await createUser(db);
  await db.query('update public.entitlements set is_pro = true where user_id = $1', [owner]);
  const team = uuid(), lineup = uuid();
  await asUser(db, owner, async (d) => {
    await d.query(`insert into public.teams (id, name, coach_name) values ($1, 'Cubs', 'Sam')`, [team]);
    await d.query(`insert into public.lineups (id, team_id, opponent) values ($1, $2, 'Tigers')`, [lineup, team]);
  });
  const ownerToken = hex(Math.floor(Math.random() * 120) + 1), editorToken = hex(Math.floor(Math.random() * 120) + 130);
  await register(owner, ownerToken);
  await register(editor, editorToken, 'sandbox');
  const token = await asUser(db, owner, async (d) => (await d.query(`select public.create_team_invite($1, 'editor') as t`, [team])).rows[0].t);
  await asUser(db, editor, (d) => d.query(`select public.accept_team_invite($1, 'Jo Park')`, [token]));
  return { owner, editor, team, lineup, ownerToken, editorToken };
}

const finalize = (user, lineup, at = new Date()) =>
  asUser(db, user, (d) => d.query(
    `update public.lineups set status = 'finalized', last_finalized_by = 'Sam', last_finalized_at = $2 where id = $1`,
    [lineup, at.toISOString()]));

describe('lineup finalized', () => {
  test("goes to every coach but the head coach who finalized, through the Worker's v2 route", async () => {
    const s = await sharedTeam();
    await db.query('delete from net.calls');
    await finalize(s.owner, s.lineup);
    const [c, ...rest] = await calls();
    assert.equal(rest.length, 0);
    assert.equal(c.url, 'https://push.example.com/v2/send');
    assert.equal(c.headers.Authorization, 'Bearer s3cret');
    assert.equal(c.body.eventType, 'lineup_finalized');
    assert.equal(c.body.teamID, s.team.toUpperCase());
    assert.deepEqual(c.body.metadata, { teamName: 'Cubs', triggeredBy: 'Sam', opponent: 'Tigers' });
    assert.deepEqual(c.body.tokens, [{ token: s.editorToken, env: 'sandbox' }], "not the finalizer's own device");
  });

  test('saving an already finalized lineup again sends nothing', async () => {
    const s = await sharedTeam();
    await finalize(s.owner, s.lineup);
    await db.query('delete from net.calls');
    await finalize(s.owner, s.lineup);
    await asUser(db, s.editor, (d) => d.query(`update public.lineups set opponent = 'Lions' where id = $1`, [s.lineup]));
    assert.equal((await calls()).length, 0);
  });

  test('an old finalize (a team being uploaded) sends nothing', async () => {
    const s = await sharedTeam();
    await db.query('delete from net.calls');
    await finalize(s.owner, s.lineup, new Date(Date.now() - 3 * 3600 * 1000));
    assert.equal((await calls()).length, 0);
  });

  test('a team nobody shares sends nothing', async () => {
    const owner = await createUser(db);
    const team = uuid(), lineup = uuid();
    await asUser(db, owner, async (d) => {
      await d.query(`insert into public.teams (id, name) values ($1, 'Solo')`, [team]);
      await d.query(`insert into public.lineups (id, team_id) values ($1, $2)`, [lineup, team]);
    });
    await register(owner, hex(250));
    await finalize(owner, lineup);
    assert.equal((await calls()).length, 0);
  });

  test('coaches without a device token are skipped, and with none at all nothing is sent', async () => {
    const s = await sharedTeam();
    await asUser(db, s.editor, (d) => d.query('select public.unregister_device_token($1)', [s.editorToken]));
    await db.query('delete from net.calls');
    await finalize(s.owner, s.lineup);
    assert.equal((await calls()).length, 0);
  });

  test('without the Vault secrets nothing is sent and the finalize still saves', async () => {
    const s = await sharedTeam();
    await db.query(`delete from vault.decrypted_secrets where name = 'push_worker_secret'`);
    await db.query('delete from net.calls');
    try {
      await finalize(s.owner, s.lineup);
      assert.equal((await calls()).length, 0);
      const { rows } = await db.query('select status from public.lineups where id = $1', [s.lineup]);
      assert.equal(rows[0].status, 'finalized');
    } finally {
      await db.query(`insert into vault.decrypted_secrets values ('push_worker_secret', 's3cret')`);
    }
  });
});

describe('coach joined', () => {
  test('tells the head coach, by the name the coach joined with', async () => {
    const s = await sharedTeam();
    const joins = (await db.query(`select body from net.calls where body->>'eventType' = 'coach_joined'`)).rows;
    assert.equal(joins.length, 1);
    assert.deepEqual(joins[0].body.tokens, [{ token: s.ownerToken, env: 'production' }], 'only the head coach');
    assert.deepEqual(joins[0].body.metadata, { teamName: 'Cubs', triggeredBy: 'Jo Park', role: 'editor' });
  });
});

describe('device tokens', () => {
  test('register, re-register, move to another account, unregister', async () => {
    const a = await createUser(db), b = await createUser(db);
    const t = hex(77);
    await register(a, t.toUpperCase());
    let { rows } = await db.query('select user_id, apns_env from public.device_tokens where token = $1', [t]);
    assert.equal(rows[0].user_id, a, 'stored lower-case');
    await register(b, t, 'sandbox');
    ({ rows } = await db.query('select user_id, apns_env from public.device_tokens where token = $1', [t]));
    assert.deepEqual(rows[0], { user_id: b, apns_env: 'sandbox' }, 'one phone, the coach now signed in');
    await asUser(db, a, (d) => d.query('select public.unregister_device_token($1)', [t]));
    assert.equal((await db.query('select 1 from public.device_tokens where token = $1', [t])).rows.length, 1, "a can't remove b's");
    await asUser(db, b, (d) => d.query('select public.unregister_device_token($1)', [t]));
    assert.equal((await db.query('select 1 from public.device_tokens where token = $1', [t])).rows.length, 0);
  });

  test('a token not seen for 60 days is dropped at the next registration', async () => {
    const a = await createUser(db);
    await register(a, hex(201));
    await db.query(`update public.device_tokens set updated_at = now() - interval '61 days' where token = $1`, [hex(201)]);
    await register(a, hex(202));
    assert.equal((await db.query('select 1 from public.device_tokens where token = $1', [hex(201)])).rows.length, 0);
  });

  test('rejects junk and signed-out callers; the table is closed to clients', async () => {
    const a = await createUser(db);
    await assert.rejects(register(a, 'not-a-token'), /Not a device token/);
    await assert.rejects(asAnon(db, (d) => d.query(`select public.register_device_token($1, 'ios', 'production', '')`, [hex(9)])), /permission denied/);
    await assert.rejects(asUser(db, a, (d) => d.query('select * from public.device_tokens')), /permission denied/);
    for (const fn of ['public.send_push(null::uuid[], null, null, null)', 'public.team_coach_ids(null)']) {
      await assert.rejects(asUser(db, a, (d) => d.query(`select ${fn}`)), /permission denied/, fn);
    }
  });
});
