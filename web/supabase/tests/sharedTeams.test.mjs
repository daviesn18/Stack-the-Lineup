// Merge 4: Shared Teams (20261124000000_shared_teams). Every rule is checked
// as the role it applies to: owner, editor, viewer, a stranger, and anon.
import { after, before, describe, test } from 'node:test';
import assert from 'node:assert/strict';

import { asAnon, asUser, createUser, freshDb, uuid } from './harness.mjs';

let db;
before(async () => { db = await freshDb(); });
after(async () => { await db.close(); });

const DENIED = /permission denied|row-level security|Only the head coach/;

async function setPro(user, pro = true, expires = null) {
  await db.query('update public.entitlements set is_pro = $2, expires_at = $3 where user_id = $1', [user, pro, expires]);
}

/** An owner with Pro and a team with one player and one draft lineup. */
async function makeTeam(name = 'Cubs') {
  const owner = await createUser(db);
  await db.query(`update public.profiles set display_name = 'Sam Rivera' where id = $1`, [owner]);
  await setPro(owner);
  const team = uuid(), player = uuid(), lineup = uuid();
  await asUser(db, owner, async (d) => {
    await d.query(`insert into public.teams (id, name, coach_name) values ($1, $2, 'Sam')`, [team, name]);
    await d.query(`insert into public.players (id, team_id, first_name) values ($1, $2, 'Ava')`, [player, team]);
    await d.query(`insert into public.lineups (id, team_id, opponent) values ($1, $2, 'Tigers')`, [lineup, team]);
  });
  return { owner, team, player, lineup };
}

const invite = (owner, team, role = 'editor') =>
  asUser(db, owner, async (d) => (await d.query('select public.create_team_invite($1, $2) as t', [team, role])).rows[0].t);

const join = (user, token, name = '') =>
  asUser(db, user, async (d) => (await d.query('select public.accept_team_invite($1, $2) as id', [token, name])).rows[0].id);

/** A team with an editor and a viewer already on it. */
async function sharedTeam() {
  const t = await makeTeam();
  const editor = await createUser(db);
  const viewer = await createUser(db);
  await join(editor, await invite(t.owner, t.team, 'editor'), 'Jo Park');
  // The second link makes everyone a viewer (one role for all), so set the
  // editor back afterwards to get one of each for the access tests.
  await join(viewer, await invite(t.owner, t.team, 'viewer'), 'Lee Chen');
  await db.query(`update public.team_members set role = 'editor' where team_id = $1 and user_id = $2`, [t.team, editor]);
  return { ...t, editor, viewer };
}

const count = (user, sql, params) =>
  asUser(db, user, async (d) => (await d.query(sql, params)).rows.length);

describe('access by role', () => {
  test('owner, editor and viewer read the team and its rows; a stranger sees nothing', async () => {
    const s = await sharedTeam();
    const stranger = await createUser(db);
    for (const u of [s.owner, s.editor, s.viewer]) {
      assert.equal(await count(u, 'select 1 from public.teams where id = $1', [s.team]), 1);
      assert.equal(await count(u, 'select 1 from public.players where team_id = $1', [s.team]), 1);
      assert.equal(await count(u, 'select 1 from public.lineups where team_id = $1', [s.team]), 1);
    }
    assert.equal(await count(stranger, 'select 1 from public.teams where id = $1', [s.team]), 0);
    assert.equal(await count(stranger, 'select 1 from public.players where team_id = $1', [s.team]), 0);
  });

  test('owner and editor change roster and lineups; a viewer and a stranger cannot', async () => {
    const s = await sharedTeam();
    const stranger = await createUser(db);
    for (const u of [s.owner, s.editor]) {
      await asUser(db, u, (d) => d.query(`insert into public.players (id, team_id, first_name) values ($1, $2, 'New')`, [uuid(), s.team]));
      await asUser(db, u, (d) => d.query(`update public.lineups set opponent = 'Lions' where id = $1`, [s.lineup]));
    }
    for (const u of [s.viewer, stranger]) {
      await assert.rejects(asUser(db, u, (d) =>
        d.query(`insert into public.players (id, team_id, first_name) values ($1, $2, 'No')`, [uuid(), s.team])), DENIED);
      const changed = await asUser(db, u, (d) => d.query(`update public.lineups set opponent = 'X' where id = $1`, [s.lineup]));
      assert.equal(changed.affectedRows ?? 0, 0, 'RLS leaves nothing to update');
    }
    // Write functions go through the same check (refused as "not found", as
    // for any lineup the caller can't edit).
    await assert.rejects(asUser(db, s.viewer, (d) => d.query('select public.archive_game($1, 6)', [s.lineup])), /Lineup not found/);
    await asUser(db, s.editor, (d) => d.query('select public.archive_game($1, 6)', [s.lineup]));
  });

  test('only the owner changes the team row (decision 1)', async () => {
    const s = await sharedTeam();
    await asUser(db, s.owner, (d) => d.query(`update public.teams set name = 'Cubs 10U' where id = $1`, [s.team]));
    for (const u of [s.editor, s.viewer]) {
      await assert.rejects(asUser(db, u, (d) => d.query(`update public.teams set game_inning_count = 5 where id = $1`, [s.team])), DENIED);
      const deleted = await asUser(db, u, (d) => d.query('delete from public.teams where id = $1', [s.team]));
      assert.equal(deleted.affectedRows ?? 0, 0);
    }
    assert.equal((await db.query('select name, game_inning_count from public.teams where id = $1', [s.team])).rows[0].game_inning_count, 7);
  });

  test("a deleted team can't be edited by anyone, and its link stops working", async () => {
    const s = await sharedTeam();
    const token = (await asUser(db, s.owner, (d) => d.query('select * from public.team_invite_link($1)', [s.team]))).rows[0].token;
    await asUser(db, s.owner, (d) => d.query('update public.teams set deleted_at = now() where id = $1', [s.team]));
    await assert.rejects(asUser(db, s.editor, (d) =>
      d.query(`insert into public.players (id, team_id, first_name) values ($1, $2, 'No')`, [uuid(), s.team])), DENIED);
    assert.equal(await join(await createUser(db), token), null);
  });
});

describe('the invite link', () => {
  test('needs the owner, and the owner needs Pro', async () => {
    const t = await makeTeam();
    const stranger = await createUser(db);
    await setPro(stranger);
    await assert.rejects(invite(stranger, t.team), /Only the head coach/);
    await setPro(t.owner, false);
    await assert.rejects(invite(t.owner, t.team), /needs Stack the Lineup Pro/);
    await setPro(t.owner, true, new Date(Date.now() - 86_400_000).toISOString());
    await assert.rejects(invite(t.owner, t.team), /needs Stack the Lineup Pro/, 'an expired Pro counts as no Pro');
  });

  test('joining gives the link role, copies the name, and is safe to repeat', async () => {
    const t = await makeTeam();
    const coach = await createUser(db);
    const token = await invite(t.owner, t.team, 'viewer');
    assert.match(token, /^[0-9a-f]{64}$/);
    assert.equal(await join(coach, token, '  Jo Park '), t.team);
    assert.equal(await join(coach, token, 'Other'), t.team);
    const rows = (await db.query('select role, name from public.team_members where team_id = $1', [t.team])).rows;
    assert.deepEqual(rows, [{ role: 'viewer', name: 'Jo Park' }]);
  });

  test("falls back to the coach's profile name", async () => {
    const t = await makeTeam();
    const coach = await createUser(db);
    await db.query(`update public.profiles set display_name = 'Pat Kim' where id = $1`, [coach]);
    await join(coach, await invite(t.owner, t.team));
    assert.equal((await db.query('select name from public.team_members where user_id = $1', [coach])).rows[0].name, 'Pat Kim');
  });

  test('the owner opening their own link changes nothing', async () => {
    const t = await makeTeam();
    assert.equal(await join(t.owner, await invite(t.owner, t.team)), t.team);
    assert.equal((await db.query('select count(*)::int as n from public.team_members where team_id = $1', [t.team])).rows[0].n, 0);
  });

  test('a new link replaces the old one; coaches who joined stay', async () => {
    const t = await makeTeam();
    const first = await createUser(db);
    const old = await invite(t.owner, t.team);
    await join(first, old);
    const fresh = await invite(t.owner, t.team);
    assert.notEqual(fresh, old);
    assert.equal(await join(await createUser(db), old), null, 'the old link is dead');
    assert.equal(await count(first, 'select 1 from public.teams where id = $1', [t.team]), 1);
    const live = (await asUser(db, t.owner, (d) => d.query('select * from public.team_invite_link($1)', [t.team]))).rows;
    assert.equal(live.length, 1);
    assert.equal(live[0].token, fresh, 'the owner can send the same link again');
  });

  test('one role for every coach: changing the link changes everyone (decision 2)', async () => {
    const s = await sharedTeam();
    await asUser(db, s.owner, (d) => d.query(`select public.set_invite_role($1, 'viewer')`, [s.team]));
    const roles = (await db.query('select distinct role from public.team_members where team_id = $1', [s.team])).rows;
    assert.deepEqual(roles, [{ role: 'viewer' }]);
    const link = (await asUser(db, s.owner, (d) => d.query('select * from public.team_invite_link($1)', [s.team]))).rows[0];
    assert.equal(link.role, 'viewer');
    await assert.rejects(asUser(db, s.editor, (d) => d.query(`select public.set_invite_role($1, 'editor')`, [s.team])), /Only the head coach/);
  });

  test('preview says who invited whom, and is empty for a dead link', async () => {
    const t = await makeTeam('Cubs');
    const coach = await createUser(db);
    const token = await invite(t.owner, t.team);
    const p = (await asUser(db, coach, (d) => d.query('select * from public.team_invite_preview($1)', [token]))).rows[0];
    assert.equal(p.team_id, t.team);
    assert.equal(p.team_name, 'Cubs');
    assert.equal(p.owner_name, 'Sam', "the team's coach name, as inside the team");
    assert.equal(p.role, 'editor');
    assert.equal(p.is_member, false);
    assert.equal((await asUser(db, coach, (d) => d.query('select * from public.team_invite_preview($1)', ['nope']))).rows.length, 0);
  });

  test("preview falls back to the account's name when the team has no coach name", async () => {
    const t = await makeTeam('Cubs');
    await db.query(`update public.teams set coach_name = '  ' where id = $1`, [t.team]);
    const coach = await createUser(db);
    const token = await invite(t.owner, t.team);
    const p = (await asUser(db, coach, (d) => d.query('select * from public.team_invite_preview($1)', [token]))).rows[0];
    assert.equal(p.owner_name, 'Sam Rivera');
  });

  test('too many bad links in a row are refused for a while', async () => {
    const t = await makeTeam();
    const guesser = await createUser(db);
    for (let i = 0; i < 20; i++) assert.equal(await join(guesser, `guess-${i}`), null);
    const good = await invite(t.owner, t.team);
    await assert.rejects(join(guesser, good), /Too many tries/);
    await assert.rejects(asUser(db, guesser, (d) => d.query('select * from public.team_invite_preview($1)', [good])), /Too many tries/);
    assert.equal(await join(await createUser(db), good), t.team, 'other coaches are unaffected');
  });

  test("the token can't be read from the table, even by the owner", async () => {
    const t = await makeTeam();
    await invite(t.owner, t.team);
    await assert.rejects(asUser(db, t.owner, (d) => d.query('select token from public.team_invites')), /permission denied/);
    await assert.rejects(asUser(db, t.owner, (d) => d.query('select * from public.team_invite_attempts')), /permission denied/);
  });
});

describe('leaving, removing, stopping', () => {
  test('a coach can leave; the owner can remove one or stop sharing', async () => {
    const s = await sharedTeam();
    await asUser(db, s.viewer, (d) => d.query('select public.leave_team($1)', [s.team]));
    assert.equal(await count(s.viewer, 'select 1 from public.teams where id = $1', [s.team]), 0);

    await assert.rejects(asUser(db, s.editor, (d) => d.query('select public.remove_team_member($1, $2)', [s.team, s.owner])), /Only the head coach/);
    await asUser(db, s.owner, (d) => d.query('select public.remove_team_member($1, $2)', [s.team, s.editor]));
    assert.equal(await count(s.editor, 'select 1 from public.players where team_id = $1', [s.team]), 0);

    const again = await createUser(db);
    const token = await invite(s.owner, s.team);
    await join(again, token);
    await asUser(db, s.owner, (d) => d.query('select public.stop_sharing($1)', [s.team]));
    assert.equal(await count(again, 'select 1 from public.teams where id = $1', [s.team]), 0);
    assert.equal(await join(await createUser(db), token), null, 'the link is dead');
    assert.equal(await count(s.owner, 'select 1 from public.teams where id = $1', [s.team]), 1, 'the team stays the owner\'s');
  });

  test("every coach sees who's on the team; a stranger sees no one", async () => {
    const s = await sharedTeam();
    for (const u of [s.owner, s.editor, s.viewer]) {
      assert.equal(await count(u, 'select 1 from public.team_members where team_id = $1', [s.team]), 2);
    }
    assert.equal(await count(await createUser(db), 'select 1 from public.team_members', []), 0);
    await assert.rejects(asUser(db, s.editor, (d) =>
      d.query(`update public.team_members set role = 'editor' where user_id = $1`, [s.viewer])), /permission denied/);
    await assert.rejects(asUser(db, s.viewer, (d) =>
      d.query(`insert into public.team_members (team_id, user_id, role) values ($1, $2, 'editor')`, [s.team, s.viewer])), /permission denied/);
  });
});

describe("the owner's Pro lapses (decision 3)", () => {
  test('coaches keep access; only a new link is blocked', async () => {
    const s = await sharedTeam();
    await setPro(s.owner, false);
    await asUser(db, s.editor, (d) => d.query(`update public.lineups set opponent = 'Bears' where id = $1`, [s.lineup]));
    assert.equal(await count(s.viewer, 'select 1 from public.players where team_id = $1', [s.team]), 1);
    await assert.rejects(invite(s.owner, s.team), /needs Stack the Lineup Pro/);
    // The live link still works for a coach joining late.
    const live = (await asUser(db, s.owner, (d) => d.query('select * from public.team_invite_link($1)', [s.team]))).rows[0];
    assert.equal(await join(await createUser(db), live.token), s.team);
  });
});

describe('only the owner finalizes (decision 4)', () => {
  const finalize = (u, lineup) => asUser(db, u, (d) =>
    d.query(`update public.lineups set status = 'finalized', last_finalized_by = 'X', last_finalized_at = now() where id = $1`, [lineup]));
  const upsertFinalized = (u, team, lineup, by) => asUser(db, u, (d) => d.query(
    `insert into public.lineups (id, team_id, opponent, status, last_finalized_by, last_finalized_at)
     values ($1, $2, 'Tigers', 'finalized', $3, now())
     on conflict (id) do update set opponent = excluded.opponent, status = excluded.status,
       last_finalized_by = excluded.last_finalized_by, last_finalized_at = excluded.last_finalized_at`,
    [lineup, team, by]));
  const state = async (lineup) => (await db.query(
    'select status, last_finalized_by from public.lineups where id = $1', [lineup])).rows[0];

  test("an editor can't finalize, by update or by upsert", async () => {
    const s = await sharedTeam();
    await assert.rejects(finalize(s.editor, s.lineup), /Only the head coach can finalize/);
    await assert.rejects(upsertFinalized(s.editor, s.team, s.lineup, 'Jo'), /Only the head coach can finalize/);
    await assert.rejects(upsertFinalized(s.editor, s.team, uuid(), 'Jo'), /Only the head coach can finalize/, 'nor create a finalized lineup');
    assert.equal((await state(s.lineup)).status, 'draft');
  });

  test('the owner finalizes; an editor re-sending it unchanged is fine and keeps the owner as finalizer', async () => {
    const s = await sharedTeam();
    await asUser(db, s.owner, (d) => d.query(
      `update public.lineups set status = 'finalized', last_finalized_by = 'Sam', last_finalized_at = now() where id = $1`, [s.lineup]));
    await upsertFinalized(s.editor, s.team, s.lineup, 'Jo');   // the iOS sync echoing the row
    assert.deepEqual(await state(s.lineup), { status: 'finalized', last_finalized_by: 'Sam' });
  });

  test("an editor's edit can still move a finalized lineup back to draft", async () => {
    const s = await sharedTeam();
    await asUser(db, s.owner, (d) => d.query(`update public.lineups set status = 'finalized' where id = $1`, [s.lineup]));
    await asUser(db, s.editor, (d) => d.query(`update public.lineups set status = 'draft', opponent = 'Lions' where id = $1`, [s.lineup]));
    assert.equal((await state(s.lineup)).status, 'draft');
  });
});

describe('deleting an account', () => {
  test("a coach's account removes their memberships; an owner's removes the team for everyone", async () => {
    const s = await sharedTeam();
    await asUser(db, s.viewer, (d) => d.query('select public.delete_account()'));
    assert.equal((await db.query('select count(*)::int as n from public.team_members where user_id = $1', [s.viewer])).rows[0].n, 0);
    await asUser(db, s.owner, (d) => d.query('select public.delete_account()'));
    assert.equal(await count(s.editor, 'select 1 from public.teams where id = $1', [s.team]), 0);
    assert.equal((await db.query('select count(*)::int as n from public.team_members where team_id = $1', [s.team])).rows[0].n, 0);
  });
});

describe('anon and direct calls', () => {
  const api = [
    ['create_team_invite', '$1::uuid', [uuid()]],
    ['team_invite_link', '$1::uuid', [uuid()]],
    ['set_invite_role', "$1::uuid, 'viewer'", [uuid()]],
    ['remove_team_member', '$1::uuid, $1::uuid', [uuid()]],
    ['stop_sharing', '$1::uuid', [uuid()]],
    ['team_invite_preview', "'x'", []],
    ['accept_team_invite', "'x'", []],
    ['leave_team', '$1::uuid', [uuid()]],
  ];
  const internal = [
    ['user_has_pro', '$1::uuid', [uuid()]],
    ['require_owned_team', '$1::uuid', [uuid()]],
    ['coach_display_name', '$1::uuid', [uuid()]],
    ['invite_attempts_exceeded', '$1::uuid', [uuid()]],
    ['guard_lineup_finalize', '', []],
  ];

  test('anon can call none of them', async () => {
    for (const [fn, args, params] of [...api, ...internal]) {
      await asAnon(db, (d) => assert.rejects(d.query(`select public.${fn}(${args})`, params), /permission denied for function/, fn));
    }
    await asAnon(db, (d) => assert.rejects(d.query('select * from public.team_members'), /permission denied/));
  });

  test('signed-in coaches cannot call the internal helpers', async () => {
    const coach = await createUser(db);
    for (const [fn, args, params] of internal) {
      await asUser(db, coach, (d) => assert.rejects(d.query(`select public.${fn}(${args})`, params), /permission denied for function/, fn));
    }
  });
});
