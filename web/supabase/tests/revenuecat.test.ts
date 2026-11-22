// The revenuecat-webhook function's pure parts (no database or network).
import assert from 'node:assert/strict';
import { describe, test } from 'node:test';

import { accountsFromEvent, authMismatch, authorized, entitlementFromSubscriber, storeFrom } from '../functions/_shared/revenuecat';

const A = '3f1c2b4a-1111-4222-8333-444455556666';
const B = '9e8d7c6b-aaaa-4bbb-8ccc-ddddeeeeffff';

describe('accountsFromEvent', () => {
  test('takes every uuid the event names, once, lower-cased', () => {
    const got = accountsFromEvent({ api_version: '1.0', event: {
      type: 'RENEWAL', app_user_id: A.toUpperCase(), original_app_user_id: A, aliases: [A, '$RCAnonymousID:abc'],
    } });
    assert.deepEqual(got, [{ revenueCatId: A.toUpperCase(), userId: A }]);
  });

  test('a TRANSFER refreshes both sides', () => {
    const got = accountsFromEvent({ event: {
      type: 'TRANSFER', app_user_id: B, original_app_user_id: B, aliases: [B], transferred_from: [A], transferred_to: [B],
    } });
    assert.deepEqual(got.map((a) => a.userId).sort(), [A, B].sort());
  });

  test('a dashboard TEST event names no account, even with uuid-shaped ids', () => {
    // Shape of RevenueCat's real "Send test event" payload (2026-11-22).
    assert.deepEqual(accountsFromEvent({ api_version: '1.0', event: {
      type: 'TEST', app_user_id: A, original_app_user_id: A, aliases: [A, B], environment: 'SANDBOX',
    } }), []);
  });

  test('anonymous customers and TEST events name no account', () => {
    assert.deepEqual(accountsFromEvent({ event: { type: 'TEST', app_user_id: 'test_user', aliases: ['$RCAnonymousID:x'] } }), []);
    assert.deepEqual(accountsFromEvent({}), []);
    assert.deepEqual(accountsFromEvent(null), []);
  });
});

const NOW = Date.parse('2026-11-21T12:00:00Z');
const at = (days: number) => new Date(NOW + days * 86_400_000).toISOString();
const subscriber = (s: Record<string, unknown>) => ({ request_date: new Date(NOW).toISOString(), request_date_ms: NOW, subscriber: s });

describe('entitlementFromSubscriber', () => {
  test('an active App Store yearly subscription is Pro until it expires', () => {
    const r = entitlementFromSubscriber(subscriber({
      entitlements: { pro: { expires_date: at(200), product_identifier: 'com.stackthelineup.pro.yearly' } },
      subscriptions: { 'com.stackthelineup.pro.yearly': { store: 'app_store', is_sandbox: false } },
      management_url: 'https://apps.apple.com/account/subscriptions',
    }), { allowSandbox: false });
    assert.deepEqual(r, {
      isPro: true, expiresAt: at(200), store: 'app_store', productId: 'com.stackthelineup.pro.yearly',
      managementUrl: 'https://apps.apple.com/account/subscriptions', asOf: new Date(NOW).toISOString(),
    });
  });

  test('the $4.99 lifetime purchase is Pro with no end date', () => {
    const r = entitlementFromSubscriber(subscriber({
      entitlements: { pro: { expires_date: null, product_identifier: 'com.stackthelineup.pro' } },
      non_subscriptions: { 'com.stackthelineup.pro': [{ id: 'x', store: 'app_store', is_sandbox: false }] },
    }), { allowSandbox: false });
    assert.equal(r.isPro, true);
    assert.equal(r.expiresAt, null);
    assert.equal(r.store, 'app_store');
  });

  test('an expired subscription is not Pro', () => {
    const r = entitlementFromSubscriber(subscriber({
      entitlements: { pro: { expires_date: at(-1), product_identifier: 'stl_pro_yearly_web' } },
      subscriptions: { stl_pro_yearly_web: { store: 'rc_billing', is_sandbox: false } },
    }), { allowSandbox: false });
    assert.equal(r.isPro, false);
    assert.equal(r.store, null);
  });

  test("Apple's billing grace period keeps Pro and sets the end to the grace end", () => {
    const r = entitlementFromSubscriber(subscriber({
      entitlements: { pro: { expires_date: at(-1), grace_period_expires_date: at(5), product_identifier: 'y' } },
      subscriptions: { y: { store: 'app_store', is_sandbox: false } },
    }), { allowSandbox: false });
    assert.equal(r.isPro, true);
    assert.equal(r.expiresAt, at(5));
  });

  test('a web (Stripe) purchase reports store stripe', () => {
    const r = entitlementFromSubscriber(subscriber({
      entitlements: { pro: { expires_date: at(300), product_identifier: 'w' } },
      subscriptions: { w: { store: 'stripe', is_sandbox: false } },
    }), { allowSandbox: false });
    assert.equal(r.store, 'stripe');
  });

  test('sandbox purchases grant Pro only where sandbox is allowed (staging)', () => {
    const body = subscriber({
      entitlements: { pro: { expires_date: at(1), product_identifier: 'y' } },
      subscriptions: { y: { store: 'app_store', is_sandbox: true } },
    });
    assert.equal(entitlementFromSubscriber(body, { allowSandbox: false }).isPro, false);
    assert.equal(entitlementFromSubscriber(body, { allowSandbox: true }).isPro, true);
  });

  test('no pro entitlement at all is free', () => {
    const r = entitlementFromSubscriber(subscriber({ entitlements: {}, subscriptions: {} }), { allowSandbox: true });
    assert.equal(r.isPro, false);
    assert.equal(r.expiresAt, null);
  });

  test('rejects something that is not a subscriber response', () => {
    assert.throws(() => entitlementFromSubscriber({ code: 7225, message: 'Invalid API key' }, { allowSandbox: false }));
  });
});

test('storeFrom maps RevenueCat store names', () => {
  assert.equal(storeFrom('APP_STORE'), 'app_store');
  assert.equal(storeFrom('mac_app_store'), 'app_store');
  assert.equal(storeFrom('rc_billing'), 'stripe');
  assert.equal(storeFrom('promotional'), 'promotional');
  assert.equal(storeFrom('amazon'), 'other');
  assert.equal(storeFrom(undefined), 'other');
});

test('authorized compares the token, forgiving whitespace and Bearer prefixes', () => {
  assert.equal(authorized('Bearer s3cret', 'Bearer s3cret'), true);
  assert.equal(authorized('Bearer s3cret ', 'Bearer s3cret'), true);
  assert.equal(authorized('Bearer s3cret', 's3cret\n'), true);
  assert.equal(authorized('s3cret', 'Bearer s3cret'), true);
  assert.equal(authorized('Bearer s3cret', 'Bearer Bearer s3cret'), true);
  assert.equal(authorized('Bearer s3cre', 'Bearer s3cret'), false);
  assert.equal(authorized('Bearer s3cretX', 'Bearer s3cret'), false);
  assert.equal(authorized(null, 'Bearer s3cret'), false);
  assert.equal(authorized('Bearer ', 'Bearer '), false);
  assert.equal(authorized('', ''), false);
});

test('authMismatch reports shape and fingerprints, never the values', async () => {
  const m = await authMismatch('Bearer abc ', 'abc');
  assert.equal(m.headerFingerprint, m.expectedFingerprint);
  assert.equal(m.headerTokenLength, 3);
  assert.ok(!JSON.stringify(m).includes('abc'));
  const missing = await authMismatch(null, 'abc');
  assert.equal(missing.headerPresent, false);
  assert.equal(missing.headerFingerprint, null);
});
