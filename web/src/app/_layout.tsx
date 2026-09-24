import { Stack } from 'expo-router';

import { AuthProvider, useAuth } from '@/data/auth';
import { Loading } from '@/ui/kit';

export default function RootLayout() {
  return (
    <AuthProvider>
      <Routes />
    </AuthProvider>
  );
}

/**
 * Signed out: only sign-in. Arrived from an invite or reset email: only
 * set-password. Otherwise the app. A blocked route falls back to the first
 * screen whose guard is on (redirectTo needs SDK 58).
 */
function Routes() {
  const { session, mustSetPassword } = useAuth();
  if (session === undefined) return <Loading />;
  const signedIn = !!session && !mustSetPassword;
  return (
    <Stack screenOptions={{ headerShown: false }}>
      <Stack.Protected guard={signedIn}>
        <Stack.Screen name="index" />
        <Stack.Screen name="import" />
        <Stack.Screen name="team/[id]" />
      </Stack.Protected>
      <Stack.Protected guard={!!session && mustSetPassword}>
        <Stack.Screen name="set-password" />
      </Stack.Protected>
      <Stack.Protected guard={!session}>
        <Stack.Screen name="sign-in" />
      </Stack.Protected>
      {/* Development-only preview on a made-up in-memory team (renders nothing in production). */}
      <Stack.Protected guard={__DEV__}>
        <Stack.Screen name="dev-grid" />
      </Stack.Protected>
    </Stack>
  );
}
