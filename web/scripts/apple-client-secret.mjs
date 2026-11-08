#!/usr/bin/env node
// Makes the Sign in with Apple "client secret" that Supabase's Apple provider
// needs for web sign-in (Auth → Sign In / Providers → Apple → Secret Key).
//
// Apple caps this JWT at 6 months, so it has to be made again before it
// expires (see the rotation task in Asana). Native iOS sign-in doesn't use it.
//
// The secret is copied to the clipboard and never printed, so it stays out of
// terminals, logs and chat. The .p8 key is only read, never copied anywhere.
//
//   node scripts/apple-client-secret.mjs --key ~/Downloads/AuthKey_ABC123.p8 --key-id ABC123
//
// Defaults: --team 6R6HA6RU2S, --client com.nickdavies.LineupBuilder.web

import { createPrivateKey, sign } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { homedir } from 'node:os';

const args = Object.fromEntries(
  process.argv.slice(2).reduce((pairs, a, i, all) => (a.startsWith('--') ? [...pairs, [a.slice(2), all[i + 1]]] : pairs), []),
);
const keyPath = args.key?.replace(/^~/, homedir());
const keyId = args['key-id'];
const team = args.team ?? '6R6HA6RU2S';
const client = args.client ?? 'com.nickdavies.LineupBuilder.web';
if (!keyPath || !keyId) {
  console.error('Usage: node scripts/apple-client-secret.mjs --key <AuthKey_XXXX.p8> --key-id <XXXX> [--team ID] [--client ServicesID]');
  process.exit(1);
}

const SIX_MONTHS = 15_777_000; // Apple's maximum lifetime, in seconds
const now = Math.floor(Date.now() / 1000);
const b64 = (v) => Buffer.from(typeof v === 'string' ? v : JSON.stringify(v)).toString('base64url');

const header = b64({ alg: 'ES256', kid: keyId, typ: 'JWT' });
const claims = b64({ iss: team, iat: now, exp: now + SIX_MONTHS, aud: 'https://appleid.apple.com', sub: client });
const key = createPrivateKey(readFileSync(keyPath));
// JOSE wants the raw r||s signature, not DER.
const signature = sign('sha256', Buffer.from(`${header}.${claims}`), { key, dsaEncoding: 'ieee-p1363' }).toString('base64url');

execFileSync('pbcopy', { input: `${header}.${claims}.${signature}` });
const expires = new Date((now + SIX_MONTHS) * 1000).toISOString().slice(0, 10);
console.log(`Client secret for ${client} copied to the clipboard. It expires ${expires}; make a new one before then.`);
