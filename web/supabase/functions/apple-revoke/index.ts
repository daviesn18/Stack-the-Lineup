// apple-revoke: revokes a coach's Sign in with Apple token before their
// account is deleted. Apple requires apps that offer account deletion to do
// this, and Supabase doesn't.
//
// The iOS app asks Apple for a fresh authorization when the coach taps Delete
// Account and posts its one-time authorization_code here. This exchanges the
// code for a refresh token and revokes that, which removes the app from the
// coach's Apple ID › Sign in with Apple list. The app then calls
// delete_account itself, so a failed revoke stops the deletion.
//
// Signed-in coaches only: verify_jwt is on (the default), and the caller must
// still exist. The function holds the Apple key, never sees a password, and
// keeps nothing.
//
// Secrets (supabase secrets set …, per project):
//   APPLE_TEAM_ID       6R6HA6RU2S
//   APPLE_KEY_ID        the Sign in with Apple key's ID (same key as the web secret)
//   APPLE_PRIVATE_KEY   the .p8 file's contents
//   APPLE_IOS_CLIENT_ID com.nickdavies.LineupBuilder.Lineup-Builder

import { createClient } from 'npm:@supabase/supabase-js@2';

import { makeAppleClientSecret } from '../_shared/appleClientSecret.ts';

const json = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json(405, { error: 'POST only' });

  // Who's calling: the platform already checked the JWT; this makes sure the account still exists.
  const auth = req.headers.get('Authorization') ?? '';
  const supabase = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!, {
    global: { headers: { Authorization: auth } },
  });
  const { data: { user }, error: userError } = await supabase.auth.getUser();
  if (userError || !user) return json(401, { error: 'Not signed in' });

  let code: unknown;
  try { ({ authorization_code: code } = await req.json()); } catch { /* falls through */ }
  if (typeof code !== 'string' || !code) return json(400, { error: 'authorization_code is required' });

  const teamId = Deno.env.get('APPLE_TEAM_ID');
  const keyId = Deno.env.get('APPLE_KEY_ID');
  const privateKeyPem = Deno.env.get('APPLE_PRIVATE_KEY');
  const clientId = Deno.env.get('APPLE_IOS_CLIENT_ID');
  if (!teamId || !keyId || !privateKeyPem || !clientId) return json(500, { error: 'Apple secrets are not set' });

  const clientSecret = await makeAppleClientSecret({ teamId, keyId, clientId, privateKeyPem });
  const form = (fields: Record<string, string>) =>
    ({ method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams(fields) });

  // 1. The one-time code → a refresh token.
  const tokenRes = await fetch('https://appleid.apple.com/auth/token', form({
    client_id: clientId, client_secret: clientSecret, code, grant_type: 'authorization_code',
  }));
  const tokens = await tokenRes.json().catch(() => ({}));
  if (!tokenRes.ok || !tokens.refresh_token) {
    // Apple's error codes (invalid_grant etc.) only; never echo tokens.
    console.error('apple-revoke: token exchange failed', tokenRes.status, tokens.error);
    return json(502, { error: 'Apple token exchange failed', apple: tokens.error ?? tokenRes.status });
  }

  // 2. Revoke it.
  const revokeRes = await fetch('https://appleid.apple.com/auth/revoke', form({
    client_id: clientId, client_secret: clientSecret, token: tokens.refresh_token, token_type_hint: 'refresh_token',
  }));
  if (!revokeRes.ok) {
    console.error('apple-revoke: revoke failed', revokeRes.status);
    return json(502, { error: 'Apple revoke failed', apple: revokeRes.status });
  }
  return json(200, { revoked: true });
});
