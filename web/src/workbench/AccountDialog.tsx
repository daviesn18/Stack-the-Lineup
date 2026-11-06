// The Account dialog (team list header and the sidebar's account menu): who
// is signed in, and Delete account. Deleting asks the coach to type DELETE,
// because it erases every team and can't be undone. Also the shared
// type-DELETE confirmation that Delete team uses.

import { useState, type ReactNode } from 'react';

import { deleteAccount, useAuth } from '@/data/auth';

import { Dialog, Group, HeaderButton, Row, TextInput } from './controls';
import { Icon } from './Icon';
import { C } from './theme';

export function AccountDialog({ onClose }: { onClose(): void }) {
  const { session } = useAuth();
  const [confirming, setConfirming] = useState(false);
  const email = session?.user.email ?? '';

  if (confirming) {
    return (
      <ConfirmDelete title="Delete your account?" action="Delete account" onClose={() => setConfirming(false)}
        // On success the session ends and the app returns to sign-in, closing this.
        run={deleteAccount}>
        This erases your sign-in ({email}) and every team you have on the web, with their rosters, lineups and game
        history. Teams in the iPhone app are not affected. This can&apos;t be undone.
      </ConfirmDelete>
    );
  }

  return (
    <Dialog title="Account" onClose={onClose} width={520}
      footer={<span style={{ marginLeft: 'auto' }}><HeaderButton onClick={onClose}>Done</HeaderButton></span>}>
      <Group label="Signed in as">
        <Row label={email || 'Unknown'} help="To change your password, sign out and choose Forgot password.">{null}</Row>
      </Group>
      <Group label="Delete account">
        <Row label="Delete my account and data" help="Erases your sign-in and every team you have on the web. Teams in the iPhone app are not affected.">
          <HeaderButton kind="danger" onClick={() => setConfirming(true)}>Delete account…</HeaderButton>
        </Row>
      </Group>
    </Dialog>
  );
}

/**
 * "Type DELETE to confirm" for something that can't be undone. `run` returns
 * an error message to show, or null when it worked (the caller then navigates
 * away or the app does).
 */
export function ConfirmDelete({ title, action, children, run, onClose }: {
  title: string; action: string; children: ReactNode; run(): Promise<string | null>; onClose(): void;
}) {
  const [typed, setTyped] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const ready = typed.trim().toUpperCase() === 'DELETE' && !busy;

  const go = async () => {
    if (!ready) return;
    setBusy(true); setError(null);
    const failed = await run();
    if (failed) { setBusy(false); setError(failed); }
  };

  return (
    <Dialog title={title} onClose={busy ? () => {} : onClose} width={520}
      footer={<span style={{ marginLeft: 'auto', display: 'flex', gap: 8 }}>
        <HeaderButton onClick={onClose} disabled={busy}>Cancel</HeaderButton>
        <HeaderButton kind="danger" onClick={() => void go()} disabled={!ready}>{busy ? 'Deleting…' : action}</HeaderButton>
      </span>}>
      <form onSubmit={(e) => { e.preventDefault(); void go(); }} style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
        <p style={{ margin: '0 4px', fontSize: 14, lineHeight: 1.5 }}>{children}</p>
        <Group label="Confirm">
          <Row label="Type DELETE to confirm"><TextInput value={typed} onChange={setTyped} placeholder="DELETE" label="Type DELETE to confirm" autoFocus width={160} /></Row>
        </Group>
        {error && (
          <div role="alert" style={{ display: 'flex', gap: 8, alignItems: 'flex-start', padding: '10px 12px', borderRadius: 8, background: 'rgba(255,59,48,0.08)', color: C.red, fontSize: 13, lineHeight: 1.4 }}>
            <Icon name="exclamationmark.triangle.fill" size={15} color={C.red} style={{ marginTop: 1 }} />
            <span>Nothing was deleted: {error}</span>
          </div>
        )}
        <button type="submit" hidden />
      </form>
    </Dialog>
  );
}
