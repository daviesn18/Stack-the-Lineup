import { useState } from 'react';

import { useAuth } from '@/data/auth';
import { supabase } from '@/data/supabase';
import { Body, Button, Card, Field, Notice, Page, Title } from '@/ui/kit';

/** Shown after an invite or password-reset link, before anything else. */
export default function SetPassword() {
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
