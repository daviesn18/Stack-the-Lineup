// The Apple client-secret JWT the apple-revoke function signs (no database needed).
import assert from 'node:assert/strict';
import { generateKeyPairSync } from 'node:crypto';
import { test } from 'node:test';

import { makeAppleClientSecret, pemToPkcs8 } from '../functions/_shared/appleClientSecret';

const { privateKey, publicKey } = generateKeyPairSync('ec', { namedCurve: 'P-256' });
const pem = privateKey.export({ type: 'pkcs8', format: 'pem' }).toString();
const decode = (part: string) => JSON.parse(Buffer.from(part, 'base64url').toString());

test('signs an ES256 JWT Apple accepts the shape of', async () => {
  const jwt = await makeAppleClientSecret({
    teamId: 'TEAM123456', keyId: 'KEY1234567', clientId: 'com.example.app', privateKeyPem: pem, now: 1_700_000_000,
  });
  const [h, c, s] = jwt.split('.');
  assert.deepEqual(decode(h), { alg: 'ES256', kid: 'KEY1234567', typ: 'JWT' });
  assert.deepEqual(decode(c), {
    iss: 'TEAM123456', iat: 1_700_000_000, exp: 1_700_000_300, aud: 'https://appleid.apple.com', sub: 'com.example.app',
  });
  // Raw r||s (64 bytes), and it verifies against the public key.
  const sig = Buffer.from(s, 'base64url');
  assert.equal(sig.length, 64);
  const key = await crypto.subtle.importKey('spki', publicKey.export({ type: 'spki', format: 'der' }), { name: 'ECDSA', namedCurve: 'P-256' }, false, ['verify']);
  assert.ok(await crypto.subtle.verify({ name: 'ECDSA', hash: 'SHA-256' }, key, sig, new TextEncoder().encode(`${h}.${c}`)));
});

test('reads a key pasted with \\n escapes, as secrets often arrive', () => {
  const escaped = pem.trim().replace(/\n/g, '\\n');
  assert.deepEqual(pemToPkcs8(escaped), pemToPkcs8(pem));
});
