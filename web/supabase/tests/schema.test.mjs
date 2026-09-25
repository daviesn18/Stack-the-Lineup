// Schema tests: run with `npm run test:db`.
//
// Each block states the guarantee from the design doc it pins down.

import { after, before, describe, test } from 'node:test';
import assert from 'node:assert/strict';

import { asAnon, asUser, createUser, freshDb, uuid } from './harness.mjs';

let db;
before(async () => {
  db = await freshDb();
});
after(async () => {
  await db.close();
});

// ---------------------------------------------------------------------------
// Fixture helpers (all run as the given coach, through RLS)
// ---------------------------------------------------------------------------

async function makeTeam(userId, { innings = 6 } = {}) {
  const team = uuid();
  const players = [uuid(), uuid(), uuid()];
  const lineup = uuid();
  await asUser(db, userId, async (d) => {
    await d.query(
      `insert into public.teams (id, name, game_inning_count, coach_name) values ($1, 'Tigers', $2, ' Coach Nick ')`,
      [team, innings],
    );
    for (const [i, id] of players.entries()) {
      await d.query(
        `insert into public.players (id, team_id, first_name, last_name, number, roster_order)
         values ($1, $2, $3, 'Test', $4, $5)`,
        [id, team, `Kid${i + 1}`, String(10 + i), i],
      );
    }
    await d.query(
      `insert into public.lineups (id, team_id, inning_count, opponent, batting_order)
       values ($1, $2, $3, 'Eagles', $4)`,
      [lineup, team, innings, players],
    );
    await d.query(`update public.teams set current_lineup_id = $1 where id = $2`, [lineup, team]);
  });
  return { team, players, lineup };
}

/** Asserts the promise rejects with a Postgres error whose code/message matches. */
async function rejects(promise, { code, message } = {}) {
  await assert.rejects(promise, (e) => {
    if (code) assert.equal(e.code, code, `expected SQLSTATE ${code}, got ${e.code}: ${e.message}`);
    if (message) assert.match(e.message, message);
    return true;
  });
}

const cells = (d, lineup) =>
  d.query(
    `select inning, player_id::text as player, position from public.lineup_cells
     where lineup_id = $1 order by inning, position`,
    [lineup],
  );

// ---------------------------------------------------------------------------

describe('accounts', () => {
  test('a new account gets a profile and a non-Pro entitlement', async () => {
    const u = await createUser(db);
    const { rows } = await asUser(db, u, (d) =>
      d.query(`select e.is_pro, e.source, p.display_name
               from public.entitlements e join public.profiles p on p.id = e.user_id`),
    );
    assert.deepEqual(rows, [{ is_pro: false, source: 'manual', display_name: '' }]);
  });

  test('a coach cannot grant themselves Pro', async () => {
    const u = await createUser(db);
    await asUser(db, u, async (d) => {
      await rejects(d.query(`update public.entitlements set is_pro = true`), { code: '42501' });
      await rejects(
        d.query(`insert into public.entitlements (user_id, is_pro) values ($1, true)`, [u]),
        { code: '42501' },
      );
    });
  });

  test('a coach can rename themselves but not touch another profile', async () => {
    const a = await createUser(db);
    const b = await createUser(db);
    await asUser(db, a, async (d) => {
      await d.query(`update public.profiles set display_name = 'Nick'`);
      const other = await d.query(`update public.profiles set display_name = 'x' where id = $1`, [b]);
      assert.equal(other.affectedRows, 0);
      await rejects(d.query(`update public.profiles set id = $1`, [uuid()]), { code: '42501' });
    });
  });

  test('signed-out requests see and change nothing', async () => {
    const u = await createUser(db);
    await makeTeam(u);
    await asAnon(db, async (d) => {
      await rejects(d.query(`select * from public.teams`), { code: '42501' });
      await rejects(d.query(`select * from public.players`), { code: '42501' });
      await rejects(d.query(`select public.can_read_team($1)`, [uuid()]), { code: '42501' });
    });
  });

  test('signed-out requests cannot call any database function', async () => {
    const calls = [
      [`select public.save_innings($1, '{}')`, [uuid()]],
      [`select public.archive_game($1, 6)`, [uuid()]],
      [`select public.replace_pitch_counts($1, '{}')`, [uuid()]],
      [`select public.import_team('{}')`, []],
      [`select public.require_editable_lineup($1)`, [uuid()]],
      [`select public.revert_to_draft($1)`, [uuid()]],
      [`select public.can_edit_team($1)`, [uuid()]],
    ];
    await asAnon(db, async (d) => {
      for (const [sql, args] of calls) {
        // Must fail on the FUNCTION, not later on a table inside it.
        await rejects(d.query(sql, args), { code: '42501', message: /permission denied for function/ });
      }
    });
  });

  test('deleting an account deletes every team and row it owns', async () => {
    const u = await createUser(db);
    const { team } = await makeTeam(u);
    await db.query(`delete from auth.users where id = $1`, [u]);
    for (const t of ['teams', 'players', 'lineups', 'profiles', 'entitlements']) {
      const col = t === 'teams' ? 'id' : t === 'profiles' ? 'id' : t === 'entitlements' ? 'user_id' : 'team_id';
      const key = t === 'profiles' || t === 'entitlements' ? u : team;
      const { rows } = await db.query(`select 1 from public.${t} where ${col} = $1`, [key]);
      assert.equal(rows.length, 0, `${t} should be empty`);
    }
  });
});

describe('team isolation (row-level security)', () => {
  test("coach B cannot see, change, or add to coach A's team", async () => {
    const a = await createUser(db);
    const b = await createUser(db);
    const { team, players, lineup } = await makeTeam(a);

    await asUser(db, b, async (d) => {
      for (const t of ['teams', 'players', 'lineups']) {
        const { rows } = await d.query(`select * from public.${t}`);
        assert.equal(rows.length, 0, `B sees no ${t}`);
      }
      const upd = await d.query(`update public.players set first_name = 'Hacked' where team_id = $1`, [team]);
      assert.equal(upd.affectedRows, 0);
      const del = await d.query(`delete from public.teams where id = $1`, [team]);
      assert.equal(del.affectedRows, 0);
      await rejects(
        d.query(`insert into public.players (id, team_id, first_name) values ($1, $2, 'Spy')`, [uuid(), team]),
        { code: '42501' },
      );
      await rejects(d.query(`select public.save_innings($1, '{"0":{}}')`, [lineup]), { code: 'P0002' });
    });

    const { rows } = await asUser(db, a, (d) =>
      d.query(`select first_name from public.players where id = $1`, [players[0]]),
    );
    assert.equal(rows[0].first_name, 'Kid1');
  });

  test('a team cannot be created for someone else, or handed over', async () => {
    const a = await createUser(db);
    const b = await createUser(db);
    await asUser(db, a, async (d) => {
      await rejects(
        d.query(`insert into public.teams (id, owner_id) values ($1, $2)`, [uuid(), b]),
        { code: '42501' },
      );
    });
    const { team } = await makeTeam(a);
    await asUser(db, a, async (d) => {
      await rejects(d.query(`update public.teams set owner_id = $1 where id = $2`, [b, team]), { code: '42501' });
    });
  });

  test("a row cannot claim a different team than its parent", async () => {
    const a = await createUser(db);
    const one = await makeTeam(a);
    const two = await makeTeam(a);
    await asUser(db, a, async (d) => {
      // Player from team two placed into team one's lineup.
      await rejects(
        d.query(
          `insert into public.lineup_cells (lineup_id, team_id, inning, player_id, position)
           values ($1, $2, 0, $3, 'SS')`,
          [one.lineup, one.team, two.players[0]],
        ),
        { code: '23503' },
      );
      // Cell row that lies about its team.
      await rejects(
        d.query(
          `insert into public.lineup_cells (lineup_id, team_id, inning, player_id, position)
           values ($1, $2, 0, $3, 'SS')`,
          [one.lineup, two.team, one.players[0]],
        ),
        { code: '23503' },
      );
    });
  });

  test('a soft-deleted team is read-only until restored', async () => {
    const a = await createUser(db);
    const { team, lineup, players } = await makeTeam(a);
    await asUser(db, a, async (d) => {
      await d.query(`update public.teams set deleted_at = now() where id = $1`, [team]);
      const { rows } = await d.query(`select id from public.teams where id = $1`, [team]);
      assert.equal(rows.length, 1, 'owner still sees it (so a syncing device learns of the delete)');
      await rejects(d.query(`select public.save_innings($1, $2)`, [lineup, { 0: { [players[0]]: 'P' } }]), {
        code: 'P0002',
      });
      await d.query(`update public.teams set deleted_at = null where id = $1`, [team]);
      await d.query(`select public.save_innings($1, $2)`, [lineup, { 0: { [players[0]]: 'P' } }]);
    });
  });
});

describe('server-stamped timestamps', () => {
  test('updated_at ignores the client clock; created_at never changes', async () => {
    const a = await createUser(db);
    const { team } = await makeTeam(a);
    await asUser(db, a, async (d) => {
      const before = (await d.query(`select created_at from public.teams where id = $1`, [team])).rows[0];
      await d.query(
        `update public.teams set name = 'Lions', updated_at = '2001-01-01', created_at = '2001-01-01' where id = $1`,
        [team],
      );
      const { rows } = await d.query(`select created_at, updated_at from public.teams where id = $1`, [team]);
      assert.equal(rows[0].created_at.getTime(), before.created_at.getTime());
      assert.ok(rows[0].updated_at.getFullYear() >= 2026, 'updated_at is server time');
    });
  });

  test('an imported created_at is kept', async () => {
    const a = await createUser(db);
    await asUser(db, a, async (d) => {
      const id = uuid();
      await d.query(`insert into public.teams (id, created_at) values ($1, '2026-08-13T03:25:44Z')`, [id]);
      const { rows } = await d.query(`select created_at from public.teams where id = $1`, [id]);
      assert.equal(rows[0].created_at.toISOString(), '2026-08-13T03:25:44.000Z');
    });
  });
});

describe('save_innings', () => {
  test('rejects two fielders at one position in an inning', async () => {
    const a = await createUser(db);
    const { lineup, players: [p1, p2] } = await makeTeam(a);
    await asUser(db, a, async (d) => {
      await rejects(d.query(`select public.save_innings($1, $2)`, [lineup, { 0: { [p1]: 'SS', [p2]: 'SS' } }]), {
        code: '23P01',
      });
      // Bench and ABS are shared freely.
      await d.query(`select public.save_innings($1, $2)`, [lineup, { 0: { [p1]: 'Bench', [p2]: 'Bench' } }]);
    });
  });

  test('a swap inside one save is fine', async () => {
    const a = await createUser(db);
    const { lineup, players: [p1, p2] } = await makeTeam(a);
    await asUser(db, a, async (d) => {
      await d.query(`select public.save_innings($1, $2)`, [lineup, { 2: { [p1]: 'SS', [p2]: '2B' } }]);
      await d.query(`select public.save_innings($1, $2)`, [lineup, { 2: { [p1]: '2B', [p2]: 'SS' } }]);
      const { rows } = await cells(d, lineup);
      assert.deepEqual(rows.map((r) => [r.inning, r.player, r.position]), [
        [2, p1, '2B'],
        [2, p2, 'SS'],
      ]);
    });
  });

  test('replaces only the innings it is given', async () => {
    const a = await createUser(db);
    const { lineup, players: [p1, p2] } = await makeTeam(a);
    await asUser(db, a, async (d) => {
      await d.query(`select public.save_innings($1, $2)`, [lineup, { 0: { [p1]: 'P' }, 1: { [p1]: 'C' } }]);
      await d.query(`select public.save_innings($1, $2)`, [lineup, { 1: { [p2]: 'C' } }]);
      const { rows } = await cells(d, lineup);
      assert.deepEqual(rows.map((r) => [r.inning, r.player]), [
        [0, p1],
        [1, p2],
      ]);
    });
  });

  test('rejects an inning past the end of the lineup and unknown positions', async () => {
    const a = await createUser(db);
    const { lineup, players: [p1] } = await makeTeam(a, { innings: 6 });
    await asUser(db, a, async (d) => {
      await rejects(d.query(`select public.save_innings($1, $2)`, [lineup, { 6: { [p1]: 'P' } }]), {
        code: '22023',
      });
      await rejects(d.query(`select public.save_innings($1, $2)`, [lineup, { 0: { [p1]: 'DH' } }]), {
        code: '23514',
      });
    });
  });

  test('editing a finalized lineup returns it to draft (revertToDraftIfFinalized)', async () => {
    const a = await createUser(db);
    const { lineup, players: [p1] } = await makeTeam(a);
    await asUser(db, a, async (d) => {
      await d.query(
        `update public.lineups set status = 'finalized', last_finalized_by = 'Nick', last_finalized_at = now()
         where id = $1`,
        [lineup],
      );
      await d.query(`select public.save_innings($1, $2)`, [lineup, { 0: { [p1]: 'P' } }]);
      const { rows } = await d.query(
        `select status, last_finalized_by, last_finalized_at from public.lineups where id = $1`,
        [lineup],
      );
      assert.deepEqual(rows[0], { status: 'draft', last_finalized_by: null, last_finalized_at: null });
    });
  });
});

describe('archive_game', () => {
  test('freezes the game, records pitch counts, and clears the grid like iOS', async () => {
    const a = await createUser(db);
    const { team, lineup, players: [p1, p2, p3] } = await makeTeam(a, { innings: 6 });
    const game = uuid();
    await asUser(db, a, async (d) => {
      await d.query(
        `insert into public.scheduled_games (id, team_id, ical_uid, starts_at) values ($1, $2, 'uid-1', now())`,
        [game, team],
      );
      await d.query(`update public.lineups set scheduled_game_id = $1 where id = $2`, [game, lineup]);
      await d.query(`select public.save_innings($1, $2)`, [
        lineup,
        { 0: { [p1]: 'P', [p2]: 'C', [p3]: 'Bench' }, 5: { [p1]: 'SS' } },
      ]);

      const { rows: [{ id: logId }] } = await d.query(
        `select public.archive_game($1, 9, '  great game \n', $2) as id`,
        [lineup, { [p1]: 42, [p2]: 7 }],
      );

      const { rows: [log] } = await d.query(`select * from public.game_logs where id = $1`, [logId]);
      assert.equal(log.innings_played, 6, 'clamped to the game length');
      assert.equal(log.opponent, 'Eagles');
      assert.equal(log.archived_by, 'Coach Nick', 'trimmed coach name');
      assert.equal(log.notes, 'great game');
      assert.equal(log.innings.length, 6, 'every inning frozen, empty ones included');
      assert.deepEqual(log.innings[0], {
        [p1.toUpperCase()]: 'P', [p2.toUpperCase()]: 'C', [p3.toUpperCase()]: 'Bench',
      });
      assert.deepEqual(log.innings[1], {});
      assert.deepEqual(log.innings[5], { [p1.toUpperCase()]: 'SS' });
      assert.deepEqual(log.player_snapshot.map((s) => s.firstName), ['Kid1', 'Kid2', 'Kid3']);
      assert.equal(log.player_snapshot[0].id, p1.toUpperCase());
      assert.deepEqual(log.batting_order, [p1, p2, p3]);

      const { rows: pcs } = await d.query(
        `select player_id::text as player, pitches from public.pitch_counts where game_log_id = $1 order by pitches`,
        [logId],
      );
      assert.deepEqual(pcs, [{ player: p2, pitches: 7 }, { player: p1, pitches: 42 }]);

      const { rows: left } = await cells(d, lineup);
      assert.equal(left.length, 0, 'grid cleared');
      const { rows: [l] } = await d.query(
        `select scheduled_game_id, opponent, batting_order, inning_count from public.lineups where id = $1`,
        [lineup],
      );
      assert.equal(l.scheduled_game_id, null, 'detached from the played game');
      assert.equal(l.opponent, 'Eagles', 'opponent kept, as iOS clearPositions does');
      assert.deepEqual(l.batting_order, [p1, p2, p3], 'batting order kept');
    });
  });

  test('replace_pitch_counts replaces the whole set', async () => {
    const a = await createUser(db);
    const { lineup, players: [p1, p2] } = await makeTeam(a);
    await asUser(db, a, async (d) => {
      const { rows: [{ id }] } = await d.query(`select public.archive_game($1, 6, '', $2) as id`, [
        lineup,
        { [p1]: 30, [p2]: 20 },
      ]);
      await d.query(`select public.replace_pitch_counts($1, $2)`, [id, { [p2]: 25 }]);
      const { rows } = await d.query(
        `select player_id::text as player, pitches from public.pitch_counts where game_log_id = $1`,
        [id],
      );
      assert.deepEqual(rows, [{ player: p2, pitches: 25 }]);
    });
  });

  // History: what the web's updateGameLog / deleteGameLog send.
  test('notes and soft delete on an archived game: its coach only', async () => {
    const a = await createUser(db);
    const b = await createUser(db);
    const { lineup, players: [p1] } = await makeTeam(a);
    const id = await asUser(db, a, async (d) =>
      (await d.query(`select public.archive_game($1, 6, '', $2) as id`, [lineup, { [p1]: 30 }])).rows[0].id);

    await asUser(db, b, async (d) => {
      const notes = await d.query(`update public.game_logs set notes = 'hijacked' where id = $1`, [id]);
      const del = await d.query(`update public.game_logs set deleted_at = now() where id = $1`, [id]);
      assert.equal(notes.affectedRows, 0);
      assert.equal(del.affectedRows, 0);
      await rejects(d.query(`select public.replace_pitch_counts($1, '{}')`, [id]), { message: /Game log not found/ });
    });

    await asUser(db, a, async (d) => {
      await d.query(`update public.game_logs set notes = 'Won 9-6' where id = $1`, [id]);
      await d.query(`update public.game_logs set deleted_at = now() where id = $1`, [id]);
      const { rows: [log] } = await d.query(`select notes, deleted_at is not null as deleted from public.game_logs where id = $1`, [id]);
      assert.deepEqual(log, { notes: 'Won 9-6', deleted: true });
      // A deleted game's pitch counts can't be edited any more.
      await rejects(d.query(`select public.replace_pitch_counts($1, '{}')`, [id]), { message: /Game log not found/ });
    });
  });
});

describe('import_team', () => {
  const payload = (teamId, p1, p2, gameId, lineupId) => ({
    team: {
      id: teamId, name: 'Imported', color_hex: '361793', coach_name: 'Nick', game_inning_count: 6,
      fair_play_config: { minimumFieldingInnings: 3 }, pitching_config: {},
      created_at: '2026-08-13T03:25:44Z', current_lineup_id: lineupId,
    },
    players: [
      { id: p1, first_name: 'Player', last_name: '01', number: '4', league_age: 9,
        position_preferences: { SS: 'Strength' }, roster_order: 0 },
      { id: p2, first_name: 'Player', last_name: '02', number: '8', roster_order: 1 },
    ],
    scheduled_games: [{ id: gameId, ical_uid: 'abc', starts_at: '2026-09-13T23:30:00Z', opponent: 'Opponent A' }],
    lineups: [{
      id: lineupId, scheduled_game_id: gameId, inning_count: 7, opponent: 'Opponent A',
      batting_order: [p1, p2], status: 'finalized', last_finalized_by: 'Nick',
      last_finalized_at: '2026-09-12T20:00:00Z', cells: { 0: { [p1]: 'SS', [p2]: 'Bench' } },
    }],
    game_logs: [{
      id: uuid(), game_date: '2026-09-06T18:00:00Z', innings_played: 6, batting_order: [p1, p2],
      innings: [{ [p1.toUpperCase()]: 'P' }], player_snapshot: [], pitch_counts: { [p1]: 55 },
    }],
  });

  test('writes the whole team and keeps its ids and status', async () => {
    const a = await createUser(db);
    const [t, p1, p2, g, l] = [uuid(), uuid(), uuid(), uuid(), uuid()];
    await asUser(db, a, async (d) => {
      const { rows: [{ id }] } = await d.query(`select public.import_team($1) as id`, [payload(t, p1, p2, g, l)]);
      assert.equal(id, t);
      const { rows: [team] } = await d.query(`select * from public.teams where id = $1`, [t]);
      assert.equal(team.current_lineup_id, l);
      assert.equal(team.created_at.toISOString(), '2026-08-13T03:25:44.000Z');
      assert.deepEqual(team.fair_play_config, { minimumFieldingInnings: 3 });

      const { rows: [lineup] } = await d.query(`select * from public.lineups where id = $1`, [l]);
      assert.equal(lineup.status, 'finalized', 'imported status survives the cell write');
      assert.equal(lineup.inning_count, 7, 'lineup keeps its own inning count (can differ from the team)');
      assert.equal((await cells(d, l)).rows.length, 2);

      const { rows: pcs } = await d.query(`select pitches from public.pitch_counts where team_id = $1`, [t]);
      assert.deepEqual(pcs, [{ pitches: 55 }]);
    });
  });

  test('refuses a second import of the same team unless replacing', async () => {
    const a = await createUser(db);
    const [t, p1, p2, g, l] = [uuid(), uuid(), uuid(), uuid(), uuid()];
    await asUser(db, a, async (d) => {
      await d.query(`select public.import_team($1)`, [payload(t, p1, p2, g, l)]);
      await rejects(d.query(`select public.import_team($1)`, [payload(t, p1, p2, g, l)]), {
        message: /already have this team/,
      });
      const renamed = payload(t, p1, p2, g, l);
      renamed.team.name = 'Replaced';
      await d.query(`select public.import_team($1, true)`, [renamed]);
      const { rows } = await d.query(`select name from public.teams where id = $1`, [t]);
      assert.deepEqual(rows, [{ name: 'Replaced' }]);
    });
  });

  test("cannot overwrite another coach's team with the same id", async () => {
    const a = await createUser(db);
    const b = await createUser(db);
    const [t, p1, p2, g, l] = [uuid(), uuid(), uuid(), uuid(), uuid()];
    await asUser(db, a, (d) => d.query(`select public.import_team($1)`, [payload(t, p1, p2, g, l)]));
    await asUser(db, b, async (d) => {
      await rejects(d.query(`select public.import_team($1, true)`, [payload(t, uuid(), uuid(), uuid(), uuid())]), {
        code: '23505',
      });
    });
    const { rows } = await db.query(`select owner_id from public.teams where id = $1`, [t]);
    assert.equal(rows[0].owner_id, a);
  });

  test('a failed import leaves nothing behind', async () => {
    const a = await createUser(db);
    const [t, p1, p2, g, l] = [uuid(), uuid(), uuid(), uuid(), uuid()];
    const bad = payload(t, p1, p2, g, l);
    bad.lineups[0].cells = { 0: { [p1]: 'SS', [p2]: 'SS' } };
    await asUser(db, a, async (d) => {
      await rejects(d.query(`select public.import_team($1)`, [bad]), { code: '23P01' });
      const { rows } = await d.query(`select 1 from public.teams where id = $1`, [t]);
      assert.equal(rows.length, 0);
    });
  });
});
