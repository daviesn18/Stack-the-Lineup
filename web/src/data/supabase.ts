// The one Supabase client. Uses the PUBLISHABLE key; row-level security in the
// database decides what each coach can see (see supabase/migrations).

import AsyncStorage from '@react-native-async-storage/async-storage';
import { createClient } from '@supabase/supabase-js';
import { Platform } from 'react-native';

import { parseConfirmLink } from './confirmLink';

const url = process.env.EXPO_PUBLIC_SUPABASE_URL;
const key = process.env.EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
if (!url || !key) {
  throw new Error('Set EXPO_PUBLIC_SUPABASE_URL and EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY (see .env.example).');
}

/**
 * How this page load arrived, read BEFORE the client consumes the URL: an
 * invite or password-reset email link lands here with `type=invite|recovery`
 * in the hash, and the coach must choose a password before continuing.
 */
export const arrivedVia: 'invite' | 'recovery' | null = (() => {
  if (Platform.OS !== 'web' || typeof window === 'undefined') return null;
  // Our own links (/auth/confirm?token_hash=…&type=…, see confirmLink).
  const link = parseConfirmLink(window.location.pathname, window.location.search);
  if (link) return link.type === 'invite' || link.type === 'recovery' ? link.type : null;
  // Supabase's verify links, which land with the session in the hash.
  const type = new URLSearchParams(window.location.hash.slice(1)).get('type');
  return type === 'invite' || type === 'recovery' ? type : null;
})();

/**
 * An Apple or Google sign-in that came back with an error (`error_code` /
 * `error_description` in the query or hash), read before the client clears
 * the URL. The common one while sign-ups are off is `signup_disabled`: that
 * Apple or Google account has no Stack the Lineup account yet.
 */
export const oauthError: { code: string; description: string } | null = (() => {
  if (Platform.OS !== 'web' || typeof window === 'undefined') return null;
  for (const raw of [window.location.search.slice(1), window.location.hash.slice(1)]) {
    const p = new URLSearchParams(raw);
    if (!p.get('error')) continue;
    // Shown once on the sign-in page; a reload shouldn't show it again.
    window.history.replaceState(null, '', window.location.pathname);
    return { code: p.get('error_code') ?? p.get('error') ?? '', description: p.get('error_description') ?? '' };
  }
  return null;
})();

export const supabase = createClient(url, key, {
  auth: {
    storage: AsyncStorage,          // localStorage on web, device storage on Android
    autoRefreshToken: true,
    persistSession: true,
    detectSessionInUrl: Platform.OS === 'web',
  },
});
