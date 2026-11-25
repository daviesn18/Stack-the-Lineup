// Merge 4: the Coaches section of Team settings, the web's version of iOS
// AccountSharingView.
//
// The head coach makes one invite link, picks what every coach can do (one
// role for all, as on iPhone), sees who joined, removes a coach, or stops
// sharing. A coach who joined sees who shared it and what they can do, and can
// leave. The server decides all of it (20261124000000_shared_teams); after
// each change the team reloads so the list is the server's.

import { useRouter } from 'expo-router';
import { useCallback, useEffect, useState, type ReactNode } from 'react';

import { signal } from '@/data/analytics';
import {
  coachDisplayName, createInvite, inviteUrl, isOwner, isShared, leaveTeam, liveLink, ownerDisplayName, removeCoach,
  ROLE_TEXT, setInviteRole, stopSharing, SharingError, type LiveLink, type TeamAccess, type TeamCoach,
} from '@/data/sharing';
import { useTeam } from '@/data/teamStore';

import { Group, HAIR, HeaderButton, Heading, Row, Seg } from './controls';
import { Icon } from './Icon';
import { LockBadge, useGate } from './pro';
import { SUB } from './Shell';
import { useWorkbench } from './state';
import { C } from './theme';

export function CoachesSection() {
  const w = useWorkbench();
  return isOwner(w.access) ? <HeadCoach access={w.access} /> : <JoinedCoach access={w.access} />;
}

// MARK: - Head coach

function HeadCoach({ access }: { access: TeamAccess }) {
  const w = useWorkbench();
  const { reload } = useTeam();
  const gate = useGate('shared_teams');
  const teamId = w.team.id;
  const [link, setLink] = useState<LiveLink | null | undefined>(undefined);
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [removing, setRemoving] = useState<string | null>(null);
  const [confirmStop, setConfirmStop] = useState(false);

  const loadLink = useCallback(async () => {
    try { setLink(await liveLink(teamId)); } catch (e) { setLink(null); setError((e as Error).message); }
  }, [teamId]);
  useEffect(() => {
    let live = true;
    liveLink(teamId).then((l) => { if (live) setLink(l); }, (e: Error) => { if (live) { setLink(null); setError(e.message); } });
    return () => { live = false; };
  }, [teamId]);

  /** Runs a sharing change, then reloads the team and the link so both are the server's. */
  const run = async (label: string, body: () => Promise<void>) => {
    setBusy(label); setError(null);
    try {
      await body();
      await Promise.all([reload(), loadLink()]);
    } catch (e) {
      if (e instanceof SharingError && e.kind === 'proRequired') gate.ask();
      else setError((e as Error).message);
    } finally {
      setBusy(null);
    }
  };

  const create = () => {
    if (!gate.open) { gate.ask(); return; }
    void run('Creating link…', async () => {
      setLink(await createInvite(teamId, 'editor'));
      signal('sharing.account.linkCreated');
    });
  };

  const copy = async (url: string) => {
    try {
      await navigator.clipboard.writeText(url);
      w.showToast('Invite link copied');
      signal('sharing.account.linkCopied');
    } catch {
      setError("Couldn't copy the link. Select it and copy it instead.");
    }
  };

  return (
    <>
      <Heading title="Coaches" sub="Invite your assistant coaches to build lineups with you." />

      <Group label="Invite link">
        {link === undefined ? (
          <Row label="Checking…">{null}</Row>
        ) : link === null ? (
          <Row label="No invite link yet" help="Make a link and send it to your assistant coaches. They sign in to join, and the team shows up on their computer, iPhone and iPad.">
            <HeaderButton kind={gate.state === 'locked' ? 'plain' : 'primary'} onClick={create} disabled={!!busy || gate.state === 'pending'}>
              <span style={{ display: 'inline-flex', alignItems: 'center', gap: 6 }}>Create invite link{gate.state === 'locked' && <LockBadge />}</span>
            </HeaderButton>
          </Row>
        ) : (
          <>
            <Row label="Send this link" help="Anyone with the link can join after they sign in. Stop sharing to turn it off." stacked>
              <div style={{ display: 'flex', gap: 8, marginTop: 12 }}>
                <input readOnly value={inviteUrl(link.token)} aria-label="Invite link" onFocus={(e) => e.currentTarget.select()} className="field"
                  style={{ flex: 1, minWidth: 0, height: 32, borderRadius: 8, border: '1px solid rgba(60,60,67,0.18)', padding: '0 10px', fontSize: 13, color: SUB, background: C.gray6, fontFamily: 'ui-monospace, SFMono-Regular, Menlo, monospace' }} />
                <HeaderButton kind="primary" onClick={() => void copy(inviteUrl(link.token))}>
                  <span style={{ display: 'inline-flex', alignItems: 'center', gap: 6 }}><Icon name="doc.on.doc" size={13} color="#fff" />Copy link</span>
                </HeaderButton>
              </div>
            </Row>
            <Row label="What coaches can do" help={`${ROLE_TEXT[link.role].explanation} Changing it changes it for every coach.`}>
              <Seg value={link.role} label="What coaches can do"
                onChange={(role) => void run('Updating…', async () => { await setInviteRole(teamId, role); signal('sharing.account.roleChanged', { role }); })}
                options={[['editor', ROLE_TEXT.editor.title], ['viewer', ROLE_TEXT.viewer.title]]} />
            </Row>
          </>
        )}
      </Group>

      <Group label="Coaches">
        <CoachRow name={`${ownerDisplayName(access)} (you)`} detail="Head coach" />
        {access.coaches.length === 0 && <Row label="No one has joined yet" help={link ? 'Coaches show up here once they join from the link.' : undefined}>{null}</Row>}
        {access.coaches.map((c) => (
          <CoachRow key={c.userId} name={coachDisplayName(c)} detail={ROLE_TEXT[c.role].title}>
            {removing === c.userId ? (
              <span style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                <span style={{ fontSize: 13, color: SUB }}>They lose access right away.</span>
                <HeaderButton onClick={() => setRemoving(null)}>Cancel</HeaderButton>
                <HeaderButton kind="danger" disabled={!!busy}
                  onClick={() => void run('Removing…', async () => { await removeCoach(teamId, c.userId); setRemoving(null); signal('sharing.account.coachRemoved'); })}>
                  Remove
                </HeaderButton>
              </span>
            ) : (
              <HeaderButton onClick={() => setRemoving(c.userId)}>Remove…</HeaderButton>
            )}
          </CoachRow>
        ))}
      </Group>

      {(link || isShared(access)) && (
        <Group label="Stop sharing">
          <Row label="Stop sharing this team" help="Every coach loses access and the link stops working. Your team and its history stay with you.">
            {confirmStop ? (
              <span style={{ display: 'flex', gap: 8 }}>
                <HeaderButton onClick={() => setConfirmStop(false)}>Cancel</HeaderButton>
                <HeaderButton kind="danger" disabled={!!busy}
                  onClick={() => void run('Stopping…', async () => { await stopSharing(teamId); setConfirmStop(false); signal('sharing.account.stopped'); })}>
                  Stop sharing
                </HeaderButton>
              </span>
            ) : (
              <HeaderButton onClick={() => setConfirmStop(true)}>Stop sharing…</HeaderButton>
            )}
          </Row>
        </Group>
      )}

      <Status busy={busy} error={error} />
    </>
  );
}

// MARK: - A coach who joined

function JoinedCoach({ access }: { access: TeamAccess }) {
  const router = useRouter();
  const w = useWorkbench();
  const [confirm, setConfirm] = useState(false);
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const role = access.role === 'viewer' ? 'viewer' : 'editor';
  const owner = ownerDisplayName(access);

  const leave = async () => {
    setBusy('Leaving…'); setError(null);
    try {
      await leaveTeam(w.team.id);
      signal('sharing.account.left');
      router.replace('/');
    } catch (e) {
      setError((e as Error).message);
      setBusy(null);
    }
  };

  return (
    <>
      <Heading title="Coaches" sub={`${owner} shared this team with you.`} />
      <Group label="Your access">
        <Row label={ROLE_TEXT[role].title} help={ROLE_TEXT[role].participant}>{null}</Row>
      </Group>
      <Group label="Coaches">
        <CoachRow name={owner} detail="Head coach" />
        {access.coaches.map((c: TeamCoach) => <CoachRow key={c.userId} name={coachDisplayName(c)} detail={ROLE_TEXT[c.role].title} />)}
      </Group>
      <Group label="Leave team">
        <Row label="Leave this team" help={`You lose access on every device. ${owner} can invite you again.`}>
          {confirm ? (
            <span style={{ display: 'flex', gap: 8 }}>
              <HeaderButton onClick={() => setConfirm(false)}>Cancel</HeaderButton>
              <HeaderButton kind="danger" disabled={!!busy} onClick={() => void leave()}>Leave team</HeaderButton>
            </span>
          ) : (
            <HeaderButton onClick={() => setConfirm(true)}>Leave team…</HeaderButton>
          )}
        </Row>
      </Group>
      <Status busy={busy} error={error} />
    </>
  );
}

// MARK: - Pieces

function CoachRow({ name, detail, children }: { name: string; detail: string; children?: ReactNode }) {
  const initials = name.replace(/\(you\)/, '').trim().split(/\s+/).map((x) => x.charAt(0)).join('').slice(0, 2).toUpperCase() || '?';
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '12px 18px', borderTop: HAIR, marginTop: -1, minHeight: 56 }}>
      <span style={{ width: 32, height: 32, borderRadius: 16, background: C.gray6, display: 'grid', placeItems: 'center', fontSize: 12, fontWeight: 600, color: SUB, flexShrink: 0 }}>{initials}</span>
      <span style={{ flex: 1, minWidth: 0 }}>
        <span className="ellipsis" style={{ display: 'block', fontSize: 14, fontWeight: 500 }}>{name}</span>
        <span style={{ display: 'block', fontSize: 12, color: SUB }}>{detail}</span>
      </span>
      {children}
    </div>
  );
}

function Status({ busy, error }: { busy: string | null; error: string | null }) {
  if (error) {
    return (
      <div role="alert" style={{ display: 'flex', gap: 8, alignItems: 'flex-start', padding: '10px 12px', borderRadius: 8, background: 'rgba(255,59,48,0.08)', color: C.red, fontSize: 13 }}>
        <Icon name="exclamationmark.triangle.fill" size={15} color={C.red} style={{ marginTop: 1 }} />
        <span>{error}</span>
      </div>
    );
  }
  return busy ? <div aria-live="polite" style={{ fontSize: 13, color: SUB, padding: '0 4px' }}>{busy}</div> : null;
}
