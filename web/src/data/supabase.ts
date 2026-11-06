// The one Supabase client. Uses the PUBLISHABLE key; row-level security in the
// database decides what each coach can see (see supabase/migrations).

import AsyncStorage from '@react-native-async-storage/async-storage';
import { createClient } from '@supabase/supabase-js';
import { Platform } from 'react-native';

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
  const type = new URLSearchParams(window.location.hash.slice(1)).get('type');
  return type === 'invite' || type === 'recovery' ? type : null;
})();

export const supabase = createClient(url, key, {
  auth: {
    storage: AsyncStorage,          // localStorage on web, device storage on Android
    autoRefreshToken: true,
    persistSession: true,
    detectSessionInUrl: Platform.OS === 'web',
  },
});
