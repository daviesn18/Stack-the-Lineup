// Merge 4: an assistant coach opens the head coach's invite link
// (app.stackthelineup.com/join/<token>). On an iPhone with the app the link
// opens the app instead (apple-app-site-association); everywhere else it lands
// here.
//
// Joining needs an account, so a signed-out coach signs in (or makes one with
// Apple or Google) first, on this page. The invite waits (data/pendingInvite)
// until they're in, and then they join straight away and the team opens, with
// no second click and without opening the link again. A coach who was already
// signed in sees who invited them to which team and what they'll be able to
// do, and clicks Join.

import { useRouter } from 'expo-router';
import { useEffect, useRef, useState, type ReactNode } from 'react';

import { signal } from '@/data/analytics';
import { useAuth } from '@/data/auth';
import { forgetInvite, inviteFromAccount, METADATA_KEY, rememberInvite } from '@/data/pendingInvite';
import { supabase } from '@/data/supabase';
import { acceptInvite, inviteToken, previewInvite, ROLE_TEXT, type InvitePreview } from '@/data/sharing';

import { SignInPage } from './AuthPages.web';
import { Group, Row, TextInput } from './controls';
import { Icon } from './Icon';
import { PrimaryButton, SecondaryButton, SUB } from './Shell';
import { AppFrame, Note, TeamBadge } from './TeamPages.web';
import { C, CSS } from './theme';

type Phase =
  | { kind: 'loading' }
  | { kind: 'ready'; preview: InvitePreview }
  | { kind: 'invalid' }
  | { kind: 'failed'; message: string };

export function JoinPage({ token: raw, resume }: { token: string | undefined; resume?: boolean }) {
  const { session } = useAuth();
  const token = inviteToken(raw);
  // Signed out when the page opened: signing in here joins straight away.
  // (Set during render, React's pattern for state that follows a prop.)
  const [signedOutHere, setSignedOutHere] = useState(false);
  if (session === null && !signedOutHere) setSignedOutHere(true);

  // Signed out: keep the link for after Apple or Google sign-in brings the coach back.
  useEffect(() => { if (session === null && token) rememberInvite(token); }, [session, token]);

  if (session === undefined) return null;
  if (!session) {
    return token ? (
      <SignInPage
        intro={{ title: 'Make a free account to join', sub: "A head coach invited you to their team. Continue with Apple or Google to make an account, or sign in if you have one. You'll join as soon as you're in." }}
        footer="Your account works on the web, iPhone and iPad." />
    ) : <AppFrameless><Invalid /></AppFrameless>;
  }
  return (
    <AppFrame width={560}>
      {token
        ? <SignedIn token={token} defaultName={accountName(session.user.user_metadata)} auto={!!resume || signedOutHere} />
        : <Invalid />}
    </AppFrame>
  );
}

function SignedIn({ token, defaultName, auto }: { token: string; defaultName: string; auto: boolean }) {
  const router = useRouter();
  const [phase, setPhase] = useState<Phase>({ kind: 'loading' });
  const [name, setName] = useState(defaultName);
  const [joining, setJoining] = useState(false);
  const [joinError, setJoinError] = useState<string | null>(null);

  const [attempt, setAttempt] = useState(0);
  // Each try (and Try again) reads the preview; state is only set when it answers.
  useEffect(() => {
    let live = true;
    previewInvite(token).then(
      (preview) => {
        if (!live) return;
        if (!preview) void finished();
        setPhase(preview ? { kind: 'ready', preview } : { kind: 'invalid' });
      },
      (e: Error) => { if (live) setPhase({ kind: 'failed', message: e.message }); },
    );
    return () => { live = false; };
  }, [token, attempt]);
  const load = () => { setPhase({ kind: 'loading' }); setAttempt((n) => n + 1); };

  const open = (id: string) => router.replace({ pathname: '/team/[id]', params: { id } });

  const join = async (p: InvitePreview) => {
    if (p.isMember) { await finished(); open(p.teamId); return; }
    setJoining(true); setJoinError(null);
    try {
      const id = await acceptInvite(token, name.trim());
      await finished();
      if (!id) { setPhase({ kind: 'invalid' }); return; }
      signal('sharing.account.joined', { role: p.role, via: auto ? 'afterSignIn' : 'link' });
      open(id);
    } catch (e) {
      setJoinError((e as Error).message);
      setJoining(false);
    }
  };

  // Back from signing in (or making an account): join without a second click.
  const autoJoined = useRef(false);
  useEffect(() => {
    if (!auto || autoJoined.current || phase.kind !== 'ready') return;
    autoJoined.current = true;
    void join(phase.preview);
  });

  if (phase.kind === 'loading') return <div style={{ fontSize: 14, color: SUB }}>Checking the invite…</div>;
  if (phase.kind === 'invalid') return <Invalid />;
  if (phase.kind === 'failed') {
    return (
      <Card icon="exclamationmark.triangle.fill" title="Couldn't open the invite" text={phase.message}>
        <SecondaryButton height={36} onClick={load}>Try again</SecondaryButton>
      </Card>
    );
  }

  const p = phase.preview;
  const owner = p.ownerName.trim() || 'A head coach';
  return (
    <div style={{ background: '#fff', borderRadius: 14, overflow: 'hidden' }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 14, padding: '22px 22px 18px' }}>
        <TeamBadge name={p.teamName} hex={p.colorHex} size={52} />
        <span style={{ flex: 1, minWidth: 0 }}>
          <span style={{ display: 'block', fontSize: 13, color: SUB }}>{p.isMember ? "You're on this team" : `${owner} invited you to coach`}</span>
          <span className="ellipsis" style={{ display: 'block', fontSize: 20, fontWeight: 700, marginTop: 2 }}>{p.teamName || 'Untitled team'}</span>
        </span>
      </div>
      {(!p.isMember || joinError) && <div style={{ padding: '0 22px 18px', display: 'flex', flexDirection: 'column', gap: 16 }}>
        {!p.isMember && (
          <>
            <div style={{ display: 'flex', gap: 10, alignItems: 'flex-start', background: C.gray6, borderRadius: 10, padding: '12px 14px' }}>
              <Icon name={p.role === 'viewer' ? 'eye' : 'pencil'} size={16} color={C.blue} style={{ marginTop: 2 }} />
              <span style={{ fontSize: 14, lineHeight: 1.45 }}>
                <span style={{ fontWeight: 600 }}>{ROLE_TEXT[p.role].title}.</span> {ROLE_TEXT[p.role].participant}
              </span>
            </div>
            <p style={{ margin: '-4px 2px 0', fontSize: 13, lineHeight: 1.45, color: SUB }}>
              Coach from your iPhone too: update Stack the Lineup from the App Store, then sign in with this account and the team is there.
            </p>
            <Group label="Your name">
              <Row label="Name" help={`${owner} and the other coaches see this.`}>
                <TextInput value={name} onChange={setName} placeholder="Coach name" label="Your name" width={220} />
              </Row>
            </Group>
          </>
        )}
        {joinError && <Note kind="error">{joinError}</Note>}
      </div>}
      <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 8, padding: '14px 22px', borderTop: '1px solid rgba(60,60,67,0.08)' }}>
        <SecondaryButton height={36} onClick={() => { void finished(); router.replace('/'); }}>Not now</SecondaryButton>
        <PrimaryButton onClick={() => void join(p)} disabled={joining}>
          {p.isMember ? 'Open team' : joining ? 'Joining…' : `Join ${p.teamName || 'team'}`}
        </PrimaryButton>
      </div>
    </div>
  );
}

function Invalid() {
  const router = useRouter();
  const { session } = useAuth();
  return (
    <Card icon="link" title="This invite link doesn't work"
      text="It may have been replaced, or the team stopped sharing. Ask the head coach to send you a new link.">
      {session && <SecondaryButton height={36} onClick={() => router.replace('/')}>Your teams</SecondaryButton>}
    </Card>
  );
}

function Card({ icon, title, text, children }: { icon: string; title: string; text: string; children?: ReactNode }) {
  return (
    <div style={{ background: '#fff', borderRadius: 14, padding: '36px 28px', textAlign: 'center' }}>
      <span style={{ width: 52, height: 52, borderRadius: 14, background: 'rgba(0,122,255,0.1)', display: 'inline-grid', placeItems: 'center' }}>
        <Icon name={icon} size={24} color={C.blue} />
      </span>
      <h2 style={{ margin: '14px 0 6px', fontSize: 20, fontWeight: 700 }}>{title}</h2>
      <p style={{ margin: '0 auto 18px', maxWidth: 400, fontSize: 14, lineHeight: 1.5, color: SUB }}>{text}</p>
      {children}
    </div>
  );
}

/** A bad link opened while signed out: no account header to show. */
function AppFrameless({ children }: { children: ReactNode }) {
  return (
    <div className="stl" style={{ position: 'fixed', inset: 0, overflow: 'auto', background: C.grouped, display: 'grid', placeItems: 'center', padding: 24 }}>
      <style>{CSS}</style>
      <div style={{ width: '100%', maxWidth: 520 }}>{children}</div>
    </div>
  );
}

/** Joined, declined, or the link no longer works: forget it here and on the account. */
async function finished() {
  forgetInvite();
  const { data } = await supabase.auth.getSession();
  if (inviteFromAccount(data.session?.user.user_metadata)) {
    await supabase.auth.updateUser({ data: { [METADATA_KEY]: null } });
  }
}

/** The name Apple or Google gave the account, as a starting point. */
function accountName(meta: Record<string, unknown> | undefined): string {
  const n = meta?.full_name ?? meta?.name;
  return typeof n === 'string' ? n.trim() : '';
}
