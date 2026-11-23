// RevenueCat → entitlements: the pure parts of the revenuecat-webhook
// function, kept here so Node's tests run them unchanged.
//
// The webhook never trusts the event's own fields for access. It takes the
// account ids from the event, re-reads each customer from RevenueCat's REST API
// (GET /v1/subscribers/{id}, which RevenueCat recommends after every webhook),
// and turns that response into one entitlements row. That way duplicate,
// late or out-of-order deliveries all end in the same state.

/** The RevenueCat entitlement that means Pro. Both iOS products and the Stripe product attach to it. */
export const PRO_ENTITLEMENT = 'pro';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export interface Account {
  /** The id exactly as RevenueCat knows it (case-sensitive there), for the REST call. */
  revenueCatId: string;
  /** The Supabase auth user id it names, lower-cased the way Postgres prints uuids. */
  userId: string;
}

/**
 * The Supabase accounts a webhook event is about. App user ids are Supabase
 * user ids (the apps call logIn(user.id)), so anything that isn't a uuid is an
 * anonymous RevenueCat id ($RCAnonymousID:…) with no account to update. A TRANSFER names both sides, and both need a refresh:
 * one gains Pro, the other loses it.
 */
export function accountsFromEvent(body: unknown): Account[] {
  const event = (body as { event?: Record<string, unknown> } | null)?.event;
  if (!event || typeof event !== 'object') return [];
  // The dashboard's "Send test event" uses random uuids that look like real
  // accounts. Reading them would create junk customers in RevenueCat.
  if (event.type === 'TEST') return [];
  const list = (v: unknown) => (Array.isArray(v) ? v : []);
  const candidates = [
    event.app_user_id, event.original_app_user_id,
    ...list(event.aliases), ...list(event.transferred_from), ...list(event.transferred_to),
  ];
  const seen = new Map<string, Account>();
  for (const id of candidates) {
    if (typeof id !== 'string' || !UUID.test(id)) continue;
    const userId = id.toLowerCase();
    if (!seen.has(userId)) seen.set(userId, { revenueCatId: id, userId });
  }
  return [...seen.values()];
}

/** Where a purchase was made, in the entitlements.store vocabulary. */
export type Store = 'app_store' | 'play_store' | 'stripe' | 'promotional' | 'other';

export function storeFrom(revenueCatStore: unknown): Store {
  switch (typeof revenueCatStore === 'string' ? revenueCatStore.toLowerCase() : '') {
    case 'app_store': case 'mac_app_store': return 'app_store';
    case 'play_store': return 'play_store';
    case 'stripe': case 'rc_billing': return 'stripe'; // RevenueCat Web Billing runs on our Stripe account
    case 'promotional': return 'promotional';
    default: return 'other';
  }
}

export interface EntitlementState {
  isPro: boolean;
  /** When Pro ends (grace period included). null = never: the $4.99 lifetime purchase, or no Pro. */
  expiresAt: string | null;
  store: Store | null;
  productId: string | null;
  /** RevenueCat's link to manage the active subscription (App Store, or Stripe's portal), if any. */
  managementUrl: string | null;
  /** RevenueCat's request_date for this read. Writes older than the stored one are ignored. */
  asOf: string;
}

interface Purchase { store?: string; is_sandbox?: boolean; purchase_date?: string }

const later = (a: string | null | undefined, b: string | null | undefined) =>
  !a ? (b ?? null) : !b ? a : Date.parse(a) >= Date.parse(b) ? a : b;

/**
 * One GET /v1/subscribers response → the entitlements row. Pro means the `pro`
 * entitlement hasn't expired as of RevenueCat's own clock: a null
 * expires_date (lifetime) or one still in the future, counting Apple's
 * billing-grace period. Sandbox purchases (Xcode, TestFlight, Stripe test
 * mode) grant Pro only where allowSandbox is set, which is staging.
 */
export function entitlementFromSubscriber(
  response: unknown,
  { allowSandbox, entitlementId = PRO_ENTITLEMENT }: { allowSandbox: boolean; entitlementId?: string },
): EntitlementState {
  const r = response as {
    request_date?: string; request_date_ms?: number;
    subscriber?: {
      entitlements?: Record<string, { expires_date?: string | null; grace_period_expires_date?: string | null; product_identifier?: string }>;
      subscriptions?: Record<string, Purchase>;
      non_subscriptions?: Record<string, Purchase[]>;
      management_url?: string | null;
    };
  } | null;
  const nowMs = typeof r?.request_date_ms === 'number' ? r.request_date_ms : Date.parse(r?.request_date ?? '');
  if (!r?.subscriber || !Number.isFinite(nowMs)) throw new Error('Not a RevenueCat subscriber response');

  const sub = r.subscriber;
  const asOf = new Date(nowMs).toISOString();
  const managementUrl = sub.management_url ?? null;
  const ent = sub.entitlements?.[entitlementId];
  if (!ent) return { isPro: false, expiresAt: null, store: null, productId: null, managementUrl, asOf };

  const productId = ent.product_identifier ?? null;
  const purchases = productId ? sub.non_subscriptions?.[productId] : undefined;
  const purchase: Purchase | undefined = productId
    ? (sub.subscriptions?.[productId] ?? purchases?.[purchases.length - 1])
    : undefined;

  const expiresAt = ent.expires_date == null ? null : later(ent.expires_date, ent.grace_period_expires_date);
  const unexpired = expiresAt === null || Date.parse(expiresAt) > nowMs;
  const sandboxBlocked = purchase?.is_sandbox === true && !allowSandbox;
  const isPro = unexpired && !sandboxBlocked;

  return {
    isPro,
    expiresAt,
    store: isPro ? storeFrom(purchase?.store) : null,
    productId,
    managementUrl,
    asOf,
  };
}

/**
 * The token in an Authorization value: whitespace and any leading "Bearer "
 * (even doubled) removed. Pasting into RevenueCat's dashboard or a secrets
 * form easily adds or drops those, and the random token is what matters.
 */
export const authToken = (value: string) => value.trim().replace(/^(bearer(\s+|$))+/i, '').trim();

/** Constant-time check of the Authorization header's token against the one set in RevenueCat's dashboard. */
export function authorized(header: string | null, expected: string): boolean {
  if (!header || !expected) return false;
  const a = new TextEncoder().encode(authToken(header));
  const b = new TextEncoder().encode(authToken(expected));
  if (b.length === 0) return false;
  let diff = a.length ^ b.length;
  for (let i = 0; i < Math.max(a.length, b.length); i++) diff |= (a[i] ?? 0) ^ (b[i] ?? 0);
  return diff === 0;
}

/**
 * Why a header didn't match, without revealing either value: presence,
 * lengths, and a short SHA-256 prefix of each token. Equal fingerprints with
 * a failed check can't happen; different ones mean the token itself differs.
 */
export async function authMismatch(header: string | null, expected: string) {
  const fingerprint = async (v: string) =>
    Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(authToken(v)))))
      .slice(0, 4).map((b) => b.toString(16).padStart(2, '0')).join('');
  return {
    headerPresent: header != null,
    headerLength: header?.length ?? 0,
    headerTokenLength: header ? authToken(header).length : 0,
    headerFingerprint: header ? await fingerprint(header) : null,
    expectedTokenLength: authToken(expected).length,
    expectedFingerprint: await fingerprint(expected),
  };
}
