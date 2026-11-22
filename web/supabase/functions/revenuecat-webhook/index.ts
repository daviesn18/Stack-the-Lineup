// revenuecat-webhook: keeps public.entitlements in step with RevenueCat, so
// Pro bought on either platform works on both. App Store purchases (iOS) and
// Stripe purchases (web) both land on the RevenueCat customer whose app user
// id is the coach's Supabase user id.
//
// For every event it re-reads the named customers from RevenueCat's REST API
// and writes what that says (see _shared/revenuecat.ts), through
// apply_revenuecat_entitlement, which ignores reads older than the stored one
// and never touches a hand-granted (source 'manual') Pro.
//
// RevenueCat can't send a Supabase JWT, so verify_jwt is off for this function
// (config.toml) and the caller is checked against a shared Authorization
// header instead. Any non-200 makes RevenueCat retry (5 times over about 80
// minutes), so failures return 5xx on purpose.
//
// Secrets (supabase secrets set …, per project):
//   REVENUECAT_WEBHOOK_AUTH    the exact Authorization header value set on the
//                              webhook in RevenueCat's dashboard (e.g. "Bearer <random>")
//   REVENUECAT_SECRET_API_KEY  a RevenueCat v1 secret API key (sk_…)
//   REVENUECAT_ALLOW_SANDBOX   "true" on staging only: sandbox and Stripe
//                              test-mode purchases grant Pro there

import { createClient } from 'npm:@supabase/supabase-js@2';

import { accountsFromEvent, authMismatch, authorized, entitlementFromSubscriber } from '../_shared/revenuecat.ts';

const json = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json(405, { error: 'POST only' });

  const expectedAuth = Deno.env.get('REVENUECAT_WEBHOOK_AUTH');
  const apiKey = Deno.env.get('REVENUECAT_SECRET_API_KEY');
  if (!expectedAuth || !apiKey) return json(500, { error: 'RevenueCat secrets are not set' });
  const header = req.headers.get('Authorization');
  if (!authorized(header, expectedAuth)) {
    // Lengths and short hash prefixes only, never the values: enough to tell a
    // missing header or a different token from a formatting slip.
    const mismatch = await authMismatch(header, expectedAuth);
    console.warn('revenuecat-webhook: unauthorized', JSON.stringify(mismatch));
    return json(401, { error: 'Unauthorized', ...mismatch });
  }

  let body: unknown;
  try { body = await req.json(); } catch { return json(400, { error: 'Body is not JSON' }); }

  const type = (body as { event?: { type?: string } })?.event?.type ?? 'unknown';
  const accounts = accountsFromEvent(body);
  // TEST events and anonymous (signed-out) customers have no account to update.
  if (accounts.length === 0) return json(200, { type, updated: [] });

  const allowSandbox = Deno.env.get('REVENUECAT_ALLOW_SANDBOX') === 'true';
  const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const results: Record<string, string> = {};
  for (const { revenueCatId, userId } of accounts) {
    const res = await fetch(`https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(revenueCatId)}`, {
      headers: { Authorization: `Bearer ${apiKey}`, Accept: 'application/json' },
    });
    if (!res.ok) {
      console.error('revenuecat-webhook: subscriber read failed', type, res.status);
      return json(502, { error: 'RevenueCat read failed', status: res.status });
    }
    let state;
    try {
      state = entitlementFromSubscriber(await res.json(), { allowSandbox });
    } catch (e) {
      console.error('revenuecat-webhook: unreadable subscriber', type, String(e));
      return json(502, { error: 'Unreadable RevenueCat response' });
    }

    const { data, error } = await admin.rpc('apply_revenuecat_entitlement', {
      p_user_id: userId,
      p_is_pro: state.isPro,
      p_expires_at: state.expiresAt,
      p_store: state.store,
      p_product_id: state.productId,
      p_management_url: state.managementUrl,
      p_as_of: state.asOf,
    });
    if (error) {
      console.error('revenuecat-webhook: apply failed', type, error.code, error.message);
      return json(500, { error: 'Entitlement write failed' });
    }
    results[userId] = String(data);
  }

  // Ids and outcomes only (no receipts, emails or prices), for the function logs.
  console.log('revenuecat-webhook', type, JSON.stringify(results));
  return json(200, { type, updated: results });
});
