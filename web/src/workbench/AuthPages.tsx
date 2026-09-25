// Native (Android, later): the sign-in and set-password screens on the shared
// React Native kit. The web uses AuthPages.web.tsx.

import { useState } from 'react';
import { Platform, View } from 'react-native';

import { useAuth } from '@/data/auth';
import { supabase } from '@/data/supabase';
import { Body, Button, Card, Field, Notice, Page, Title } from '@/ui/kit';

export function SignInPage() {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [info, setInfo] = useState<string | null>(null);

  async function signIn() {
    setBusy(true); setError(null); setInfo(null);
    const { error } = await supabase.auth.signInWithPassword({ email: email.trim(), password });
    setBusy(false);
    if (error) {
      setError(error.message === 'Invalid login credentials'
        ? 'That email and password don\'t match. Check both, or reset your password below.'
        : error.message);
    }
  }

  async function resetPassword() {
    if (!email.trim()) { setError('Enter your email first, then choose Reset password.'); return; }
    setBusy(true); setError(null); setInfo(null);
    const redirectTo = Platform.OS === 'web' ? window.location.origin : undefined;
    const { error } = await supabase.auth.resetPasswordForEmail(email.trim(), { redirectTo });
    setBusy(false);
    if (error) setError(error.message);
    else setInfo(`If ${email.trim()} has an account, a reset link is on its way.`);
  }

  return (
    <Page width={440}>
      <Title>Stack the Lineup</Title>
      <Body muted>Web pilot. Accounts are by invitation.</Body>
      <Card>
        <Field label="Email" value={email} onChangeText={setEmail} autoComplete="email" keyboardType="email-address"
          autoCapitalize="none" textContentType="emailAddress" onSubmitEditing={signIn} />
        <Field label="Password" value={password} onChangeText={setPassword} secureTextEntry autoComplete="current-password"
          textContentType="password" onSubmitEditing={signIn} />
        {error && <Notice kind="error">{error}</Notice>}
        {info && <Notice>{info}</Notice>}
        <Button title="Sign in" onPress={signIn} busy={busy} disabled={!email || !password} />
        <View>
          <Button title="Reset password" kind="secondary" onPress={resetPassword} disabled={busy} />
        </View>
      </Card>
    </Page>
  );
}

/** Shown after an invite or password-reset link, before anything else. */
export function SetPasswordPage() {
  const { passwordSet } = useAuth();
  const [password, setPassword] = useState('');
  const [confirm, setConfirm] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function save() {
    if (password.length < 8) { setError('Use at least 8 characters.'); return; }
    if (password !== confirm) { setError('The two passwords don\'t match.'); return; }
    setBusy(true); setError(null);
    const { error } = await supabase.auth.updateUser({ password });
    setBusy(false);
    if (error) setError(error.message);
    else passwordSet();
  }

  return (
    <Page width={440}>
      <Title>Choose a password</Title>
      <Body muted>You&apos;ll use it with your email to sign in from now on.</Body>
      <Card>
        <Field label="New password" value={password} onChangeText={setPassword} secureTextEntry
          autoComplete="new-password" textContentType="newPassword" />
        <Field label="Confirm password" value={confirm} onChangeText={setConfirm} secureTextEntry
          autoComplete="new-password" textContentType="newPassword" onSubmitEditing={save} />
        {error && <Notice kind="error">{error}</Notice>}
        <Button title="Save password" onPress={save} busy={busy} disabled={!password || !confirm} />
      </Card>
    </Page>
  );
}
