// The Sign in with Apple "client secret": a short-lived ES256 JWT signed with
// the .p8 key, which Apple's /auth/token and /auth/revoke endpoints require.
// WebCrypto only, so it runs in Supabase Edge Functions (Deno) and in Node's
// tests unchanged. Mirrors web/scripts/apple-client-secret.mjs, which makes the
// long-lived web one by hand.

export interface AppleSecretInput {
  teamId: string;      // iss: the Apple Developer team ID
  keyId: string;       // kid: the Sign in with Apple key's ID
  clientId: string;    // sub: the app's bundle ID (iOS) or the Services ID (web)
  privateKeyPem: string; // the .p8 file's contents (PKCS#8 PEM)
  now?: number;        // seconds since 1970; tests pin it
  lifetime?: number;   // seconds; Apple allows up to 6 months, revokes need minutes
}

const b64url = (bytes: Uint8Array) =>
  btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const b64urlJson = (value: unknown) => b64url(new TextEncoder().encode(JSON.stringify(value)));

/** PEM → the raw PKCS#8 bytes WebCrypto imports. Accepts real newlines or "\n" escapes (as secrets often arrive). */
export function pemToPkcs8(pem: string): Uint8Array<ArrayBuffer> {
  const binary = atob(pem.replace(/\\n/g, '\n').replace(/-----(BEGIN|END) PRIVATE KEY-----/g, '').replace(/\s+/g, ''));
  const bytes = new Uint8Array(new ArrayBuffer(binary.length));
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

export async function makeAppleClientSecret(input: AppleSecretInput): Promise<string> {
  const now = input.now ?? Math.floor(Date.now() / 1000);
  const header = b64urlJson({ alg: 'ES256', kid: input.keyId, typ: 'JWT' });
  const claims = b64urlJson({
    iss: input.teamId, iat: now, exp: now + (input.lifetime ?? 300),
    aud: 'https://appleid.apple.com', sub: input.clientId,
  });
  const key = await crypto.subtle.importKey(
    'pkcs8', pemToPkcs8(input.privateKeyPem), { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign'],
  );
  // WebCrypto's ECDSA output is already the raw r||s form JOSE wants (not DER).
  const signature = new Uint8Array(await crypto.subtle.sign(
    { name: 'ECDSA', hash: 'SHA-256' }, key, new TextEncoder().encode(`${header}.${claims}`),
  ));
  return `${header}.${claims}.${b64url(signature)}`;
}
