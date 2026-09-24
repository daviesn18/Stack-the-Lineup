// Session state for the whole app, plus the coach's Pro entitlement.

import type { Session } from '@supabase/supabase-js';
import { createContext, useContext, useEffect, useState, type ReactNode } from 'react';

import { arrivedVia, supabase } from './supabase';

interface AuthState {
  /** undefined while the stored session is still loading. */
  session: Session | null | undefined;
  /** True after an invite or reset link, until the coach has set a password. */
  mustSetPassword: boolean;
  passwordSet(): void;
}

const AuthContext = createContext<AuthState>({ session: undefined, mustSetPassword: false, passwordSet: () => {} });

export function AuthProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null | undefined>(undefined);
  const [mustSetPassword, setMustSetPassword] = useState(arrivedVia !== null);

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => setSession(data.session));
    const { data } = supabase.auth.onAuthStateChange((event, next) => {
      setSession(next);
      if (event === 'PASSWORD_RECOVERY') setMustSetPassword(true);
      if (event === 'SIGNED_OUT') setMustSetPassword(false);
    });
    return () => data.subscription.unsubscribe();
  }, []);

  return (
    <AuthContext.Provider value={{ session, mustSetPassword, passwordSet: () => setMustSetPassword(false) }}>
      {children}
    </AuthContext.Provider>
  );
}

export const useAuth = () => useContext(AuthContext);

/**
 * Pro, from the entitlements row the database creates for every account.
 * Coaches can read it but never write it; during the pilot Nick sets it in the
 * dashboard, later a RevenueCat webhook does.
 */
export function useIsPro(): boolean | undefined {
  const { session } = useAuth();
  const userId = session?.user.id;
  const [loaded, setLoaded] = useState<{ userId: string; isPro: boolean } | null>(null);
  useEffect(() => {
    if (!userId) return;
    let live = true;
    supabase.from('entitlements').select('is_pro, expires_at').maybeSingle().then(({ data }) => {
      if (!live) return;
      const expired = data?.expires_at ? new Date(data.expires_at) < new Date() : false;
      setLoaded({ userId, isPro: !!data?.is_pro && !expired });
    });
    return () => { live = false; };
  }, [userId]);
  // Only trust a result loaded for the user who is signed in now.
  return userId && loaded?.userId === userId ? loaded.isPro : undefined;
}
