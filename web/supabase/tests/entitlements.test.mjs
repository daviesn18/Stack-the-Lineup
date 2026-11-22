// apply_revenuecat_entitlement: the one writer of RevenueCat state.
import { after, before, describe, test } from 'node:test';
import assert from 'node:assert/strict';

import { asAnon, asUser, createUser, freshDb, uuid } from './harness.mjs';

let db;
before(async () => { db = await freshDb(); });
after(async () => { await db.close(); });

const SIG = 'public.apply_revenuecat_entitlement($1, $2, $3, $4, $5, $6, $7)';
const apply = (d, userId, { isPro, expiresAt = null, store = null, productId = null, url = null, asOf }) =>
  d.query(`select ${SIG} as result`, [userId, isPro, expiresAt, store, productId, url, asOf]).then((r) => r.rows[0].result);

async function asService(fn) {
  await db.exec('set role service_role');
  try { return await fn(db); } finally { await db.exec('reset role'); }
}
const row = async (userId) =>
  (await db.query('select is_pro, source, expires_at, store, product_id, management_url from public.entitlements where user_id = $1', [userId])).rows[0];

describe('apply_revenuecat_entitlement', () => {
  test('grants and then removes Pro, recording where it was bought', async () => {
    const coach = await createUser(db);
    assert.equal(await asService((d) => apply(d, coach, {
      isPro: true, expiresAt: '2027-11-21T00:00:00Z', store: 'app_store', productId: 'com.stackthelineup.pro.yearly',
      url: 'https://apps.apple.com/account/subscriptions', asOf: '2026-11-21T00:00:00Z',
    })), 'pro');
    const pro = await row(coach);
    assert.equal(pro.is_pro, true);
    assert.equal(pro.source, 'revenuecat');
    assert.equal(pro.store, 'app_store');

    assert.equal(await asService((d) => apply(d, coach, { isPro: false, expiresAt: '2026-11-22T00:00:00Z', asOf: '2026-11-23T00:00:00Z' })), 'free');
    assert.equal((await row(coach)).is_pro, false);
  });

  test('a lifetime purchase is Pro with no expiry', async () => {
    const coach = await createUser(db);
    await asService((d) => apply(d, coach, { isPro: true, store: 'app_store', productId: 'com.stackthelineup.pro', asOf: '2026-11-21T00:00:00Z' }));
    const r = await row(coach);
    assert.equal(r.is_pro, true);
    assert.equal(r.expires_at, null);
  });

  test('an older read arriving late changes nothing', async () => {
    const coach = await createUser(db);
    await asService((d) => apply(d, coach, { isPro: true, store: 'stripe', asOf: '2026-11-21T10:00:00Z' }));
    assert.equal(await asService((d) => apply(d, coach, { isPro: false, asOf: '2026-11-21T09:00:00Z' })), 'stale');
    assert.equal((await row(coach)).is_pro, true);
  });

  test('a hand-granted Pro is never removed, but purchase details are kept', async () => {
    const coach = await createUser(db);
    await db.query(`update public.entitlements set is_pro = true, source = 'manual' where user_id = $1`, [coach]);
    assert.equal(await asService((d) => apply(d, coach, { isPro: false, asOf: '2026-11-21T00:00:00Z' })), 'kept_manual');
    assert.equal(await asService((d) => apply(d, coach, {
      isPro: true, store: 'stripe', productId: 'w', url: 'https://billing.stripe.com/p/x', asOf: '2026-11-22T00:00:00Z',
    })), 'kept_manual');
    const r = await row(coach);
    assert.equal(r.is_pro, true);
    assert.equal(r.source, 'manual');
    assert.equal(r.store, 'stripe');
    assert.equal(r.management_url, 'https://billing.stripe.com/p/x');
  });

  test('an unknown or deleted account is reported, not created', async () => {
    assert.equal(await asService((d) => apply(d, uuid(), { isPro: true, asOf: '2026-11-21T00:00:00Z' })), 'no_account');
  });

  test('coaches and signed-out callers cannot grant themselves Pro', async () => {
    const coach = await createUser(db);
    await assert.rejects(asUser(db, coach, (d) => apply(d, coach, { isPro: true, asOf: '2027-01-01T00:00:00Z' })), /permission denied for function/);
    await assert.rejects(asAnon(db, (d) => apply(d, coach, { isPro: true, asOf: '2027-01-01T00:00:00Z' })), /permission denied for function/);
    await assert.rejects(asUser(db, coach, (d) => d.query(`update public.entitlements set is_pro = true where user_id = $1`, [coach])), /permission denied/);
    assert.equal((await row(coach)).is_pro, false);
  });

  test('a coach can read the new columns on their own row', async () => {
    const coach = await createUser(db);
    await asService((d) => apply(d, coach, { isPro: true, store: 'app_store', url: 'https://apps.apple.com/account/subscriptions', asOf: '2026-11-21T00:00:00Z' }));
    const { rows } = await asUser(db, coach, (d) => d.query('select is_pro, store, management_url from public.entitlements'));
    assert.deepEqual(rows, [{ is_pro: true, store: 'app_store', management_url: 'https://apps.apple.com/account/subscriptions' }]);
  });
});
