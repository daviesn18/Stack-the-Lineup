// The team list and .stlteam import for the web, in the workbench's design
// system: a white top bar with the account, then the page on the gray canvas.
// Teams are cards (color, name, players, next game); New team opens a dialog
// and writes an empty team; Import takes a dropped or chosen .stlteam file,
// previews it, then imports.

import { useFocusEffect, useRouter } from 'expo-router';
import { useCallback, useRef, useState, type DragEvent, type ReactNode } from 'react';

import { DEFAULT_INNING_COUNT } from '@/core/model';
import { useAuth, useIsPro } from '@/data/auth';
import { supabase } from '@/data/supabase';
import { createTeam, importTeam, listTeams, previewImport, type ImportOutcome, type ImportPreview, type TeamSummary } from '@/data/teams';

import { ColorSwatches, Dialog, GameLength, Group, HAIR, Row, TextInput } from './controls';
import { Icon } from './Icon';
import { plural } from './gameStatus';
import { BORDER, PrimaryButton, SecondaryButton, SUB } from './Shell';
import { C, CSS } from './theme';

// MARK: - Team list

export function TeamsPage() {
  const router = useRouter();
  const [teams, setTeams] = useState<TeamSummary[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [creating, setCreating] = useState(false);

  useFocusEffect(useCallback(() => {
    listTeams().then(setTeams, (e: Error) => setError(e.message));
  }, []));

  const open = (id: string) => router.push({ pathname: '/team/[id]', params: { id } });
  const actions = (
    <>
      <SecondaryButton icon="square.and.arrow.down" height={36} onClick={() => router.push('/import')}>Import from iPhone</SecondaryButton>
      <PrimaryButton icon="plus" onClick={() => setCreating(true)}>New team</PrimaryButton>
    </>
  );

  return (
    <AppFrame>
      <div style={{ display: 'flex', alignItems: 'flex-end', gap: 16, marginBottom: 24 }}>
        <div style={{ flex: 1, minWidth: 0 }}>
          <h1 style={{ margin: 0, fontSize: 28, fontWeight: 700, letterSpacing: '-0.015em' }}>Your teams</h1>
          <p style={{ margin: '4px 0 0', fontSize: 14, color: SUB }}>Pick a team to get its next game ready.</p>
        </div>
        {teams && teams.length > 0 && <div style={{ display: 'flex', gap: 8 }}>{actions}</div>}
      </div>

      {error && <Note kind="error">Couldn&apos;t load your teams: {error}</Note>}
      {!teams && !error && <div style={{ fontSize: 14, color: SUB }}>Loading your teams…</div>}

      {teams?.length === 0 && (
        <div style={{ background: '#fff', borderRadius: 14, padding: '40px 32px', textAlign: 'center' }}>
          <span style={{ width: 52, height: 52, borderRadius: 14, background: 'rgba(0,122,255,0.1)', display: 'inline-grid', placeItems: 'center' }}>
            <Icon name="person.3.fill" size={24} color={C.blue} />
          </span>
          <h2 style={{ margin: '14px 0 6px', fontSize: 20, fontWeight: 700 }}>Add your first team</h2>
          <p style={{ margin: '0 auto 20px', maxWidth: 440, fontSize: 14, lineHeight: 1.5, color: SUB }}>
            Start a new team and add your players, or bring a team over from Stack the Lineup on iPhone with its roster, rules and game history.
          </p>
          <div style={{ display: 'inline-flex', gap: 8 }}>{actions}</div>
        </div>
      )}

      {teams && teams.length > 0 && (
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(300px, 1fr))', gap: 16 }}>
          {teams.map((t) => <TeamCard key={t.id} t={t} onOpen={() => open(t.id)} />)}
        </div>
      )}

      {creating && <NewTeamDialog onClose={() => setCreating(false)} onCreated={open} />}
    </AppFrame>
  );
}

function TeamCard({ t, onOpen }: { t: TeamSummary; onOpen(): void }) {
  const next = t.nextGame;
  return (
    <button onClick={onOpen} className="h-card"
      style={{ background: '#fff', borderRadius: 14, padding: 0, textAlign: 'left', display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
      <span style={{ display: 'flex', alignItems: 'center', gap: 14, padding: '18px 18px 16px' }}>
        <TeamBadge name={t.name} hex={t.colorHex} />
        <span style={{ flex: 1, minWidth: 0 }}>
          <span className="ellipsis" style={{ display: 'block', fontSize: 16, fontWeight: 600 }}>{t.name || 'Untitled team'}</span>
          <span style={{ display: 'block', fontSize: 13, color: SUB, marginTop: 2 }}>
            {plural(t.playerCount, 'player')}{t.archivedGames > 0 && ` · ${plural(t.archivedGames, 'game')} played`}
          </span>
        </span>
        <Icon name="chevron.right" size={16} color={C.label3} />
      </span>
      <span style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '11px 18px', borderTop: HAIR, fontSize: 13, color: next ? C.label : SUB }}>
        <Icon name="calendar" size={14} color={next ? C.blue : C.label3} />
        {next
          ? <span className="ellipsis">vs {next.opponent} · {next.gameDate.toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' })}</span>
          : 'No game set up yet'}
      </span>
    </button>
  );
}

function TeamBadge({ name, hex, size = 44 }: { name: string; hex: string; size?: number }) {
  const initials = (name.trim() || '?').split(/\s+/).map((w) => w[0]).join('').slice(0, 2).toUpperCase();
  return (
    <span style={{ width: size, height: size, borderRadius: size * 0.27, background: `#${hex}`, color: '#fff', fontSize: size * 0.36, fontWeight: 700, display: 'grid', placeItems: 'center', flexShrink: 0, boxShadow: 'inset 0 0 0 1px rgba(0,0,0,0.08)' }}>
      {initials}
    </span>
  );
}

function NewTeamDialog({ onClose, onCreated }: { onClose(): void; onCreated(id: string): void }) {
  const [name, setName] = useState('');
  const [coach, setCoach] = useState('');
  const [color, setColor] = useState('1B2C5D');
  const [innings, setInnings] = useState(DEFAULT_INNING_COUNT);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const ready = name.trim().length > 0 && !busy;

  const create = async () => {
    if (!ready) return;
    setBusy(true); setError(null);
    const out = await createTeam({ name, coachName: coach, colorHex: color, gameInningCount: innings });
    setBusy(false);
    if (out.ok) onCreated(out.teamId); else setError(outcomeError(out));
  };

  return (
    <Dialog title="New team" subtitle="You can make changes in Team settings." onClose={onClose} width={600}
      footer={<span style={{ marginLeft: 'auto', display: 'flex', gap: 8 }}>
        <SecondaryButton onClick={onClose}>Cancel</SecondaryButton>
        <PrimaryButton height={32} onClick={create} disabled={!ready}>{busy ? 'Creating…' : 'Create team'}</PrimaryButton>
      </span>}>
      <form onSubmit={(e) => { e.preventDefault(); void create(); }} style={{ display: 'flex', flexDirection: 'column', gap: 24 }}>
        <Group label="Team">
          <Row label="Team name"><TextInput value={name} onChange={setName} placeholder="e.g. Mudcats 10U" label="Team name" autoFocus width={260} /></Row>
          <Row label="Your name" help="See who finalized the lineup."><TextInput value={coach} onChange={setCoach} placeholder="Coach name" label="Your name" width={260} /></Row>
          <Row label="Team color" stacked><div style={{ marginTop: 12 }}><ColorSwatches value={color} onChange={setColor} /></div></Row>
          <Row label="Game length" help="Innings in a regular game."><GameLength value={innings} onChange={setInnings} /></Row>
        </Group>
        {error && <Note kind="error">{error}</Note>}
        <p style={{ margin: '-8px 4px 0', fontSize: 13, color: SUB, lineHeight: 1.45 }}>
          Fair play starts with: no back-to-back bench, 4 innings in the field, 1 infield and 1 outfield. Add players next, on the Roster page.
        </p>
        <button type="submit" hidden />
      </form>
    </Dialog>
  );
}

// MARK: - Import

type Conflict = 'alreadyYours' | 'ownedElsewhere' | null;

export function ImportPage() {
  const router = useRouter();
  const fileInput = useRef<HTMLInputElement>(null);
  const [preview, setPreview] = useState<ImportPreview | null>(null);
  const [fileName, setFileName] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [conflict, setConflict] = useState<Conflict>(null);
  const [busy, setBusy] = useState(false);
  const [over, setOver] = useState(false);

  async function read(file: File | undefined) {
    setError(null); setConflict(null); setPreview(null);
    if (!file) return;
    if (!file.name.toLowerCase().endsWith('.stlteam')) {
      setError(`"${file.name}" isn't a team file. Choose the .stlteam file you exported from the iPhone app.`);
      return;
    }
    try {
      setFileName(file.name);
      setPreview(previewImport(await file.text()));
    } catch (e) {
      setError((e as Error).message);
    }
  }

  async function run(mode: 'new' | 'replace' | 'copy') {
    if (!preview) return;
    setBusy(true); setError(null);
    const out = await importTeam(preview.payload, mode);
    setBusy(false);
    if (out.ok) router.replace({ pathname: '/team/[id]', params: { id: out.teamId } });
    else if (out.reason === 'error') setError(out.message);
    else setConflict(out.reason);
  }

  const onDrop = (e: DragEvent) => { e.preventDefault(); setOver(false); void read(e.dataTransfer.files[0]); };
  const t = preview?.team;

  return (
    <AppFrame width={680}>
      <button className="h-link" onClick={() => router.replace('/')} style={{ display: 'flex', alignItems: 'center', gap: 4, fontSize: 14, color: C.blue, marginBottom: 16 }}>
        <Icon name="chevron.left" size={16} color={C.blue} />Your teams
      </button>
      <h1 style={{ margin: 0, fontSize: 28, fontWeight: 700, letterSpacing: '-0.015em' }}>Import a team from iPhone</h1>
      <p style={{ margin: '6px 0 24px', fontSize: 14, lineHeight: 1.5, color: SUB }}>
        Bring over the roster, rules, schedule, templates and game history. The web will not sync with iPhone until a future update.
      </p>

      <input ref={fileInput} type="file" accept=".stlteam" hidden onChange={(e) => { void read(e.target.files?.[0]); e.target.value = ''; }} />

      {!t && (
        <>
          <div style={{ background: '#fff', borderRadius: 14, padding: '6px 20px', marginBottom: 16 }}>
            {[
              'On your iPhone, open Stack the Lineup and go to the team.',
              'Choose Export Team and save the .stlteam file where this computer can get it: AirDrop, iCloud Drive, or email it to yourself.',
              'Drop the file below, or choose it.',
            ].map((s, i) => (
              <div key={s} style={{ display: 'flex', gap: 12, padding: '12px 0', borderTop: i ? HAIR : 'none', alignItems: 'baseline' }}>
                <span className="num" style={{ width: 22, height: 22, borderRadius: 11, background: C.gray6, fontSize: 12, fontWeight: 600, display: 'inline-grid', placeItems: 'center', flexShrink: 0 }}>{i + 1}</span>
                <span style={{ fontSize: 14, lineHeight: 1.45 }}>{s}</span>
              </div>
            ))}
          </div>
          <div onDragOver={(e) => { e.preventDefault(); setOver(true); }} onDragLeave={() => setOver(false)} onDrop={onDrop}
            onClick={() => fileInput.current?.click()} role="button" tabIndex={0}
            onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); fileInput.current?.click(); } }}
            style={{ borderRadius: 14, border: `2px dashed ${over ? C.blue : 'rgba(60,60,67,0.2)'}`, background: over ? 'rgba(0,122,255,0.05)' : '#fff', padding: '36px 24px', textAlign: 'center', cursor: 'pointer', transition: 'border-color .15s, background-color .15s' }}>
            <Icon name="square.and.arrow.down" size={28} color={C.blue} />
            <div style={{ fontSize: 15, fontWeight: 600, marginTop: 10 }}>Drop your .stlteam file here</div>
            <div style={{ fontSize: 13, color: SUB, marginTop: 4 }}>or <span style={{ color: C.blue, fontWeight: 500 }}>choose a file</span></div>
          </div>
        </>
      )}

      {error && <div style={{ marginTop: 16 }}><Note kind="error">{error}</Note></div>}

      {t && preview && (
        <div style={{ background: '#fff', borderRadius: 14, overflow: 'hidden' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 14, padding: '18px 20px', borderBottom: `1px solid ${BORDER}` }}>
            <TeamBadge name={t.name} hex={t.colorHex} />
            <span style={{ flex: 1, minWidth: 0 }}>
              <span className="ellipsis" style={{ display: 'block', fontSize: 17, fontWeight: 600 }}>{t.name || 'Untitled team'}</span>
              <span className="ellipsis" style={{ display: 'block', fontSize: 12, color: SUB, marginTop: 2 }}>
                {fileName} · exported {preview.exportedAt.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })} from version {preview.appVersion}
              </span>
            </span>
            <SecondaryButton onClick={() => fileInput.current?.click()}>Choose another</SecondaryButton>
          </div>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 8, padding: 20 }}>
            <Tile n={t.players.length} label={t.players.length === 1 ? 'player' : 'players'} />
            <Tile n={t.gameInningCount} label="innings a game" />
            <Tile n={t.gameLogs.length} label={t.gameLogs.length === 1 ? 'archived game' : 'archived games'} />
            <Tile n={t.scheduledGames.length} label={t.scheduledGames.length === 1 ? 'scheduled game' : 'scheduled games'} />
            <Tile n={preview.savedLineups} label={preview.savedLineups === 1 ? 'saved lineup' : 'saved lineups'} />
            <Tile n={t.lineupTemplates.length} label={t.lineupTemplates.length === 1 ? 'template' : 'templates'} />
          </div>
          {(preview.notes.length > 0 || conflict) && (
            <div style={{ display: 'flex', flexDirection: 'column', gap: 8, padding: '0 20px 20px' }}>
              {preview.notes.map((n) => <Note key={n} kind="warn">{n}</Note>)}
              {conflict === 'alreadyYours' && (
                <Note kind="warn">You already have this team here. Replacing it deletes everything and puts this file in its place.</Note>
              )}
              {conflict === 'ownedElsewhere' && (
                <Note kind="warn">Another coach already imported this team. Continue to create a new, standalone team.</Note>
              )}
            </div>
          )}
          <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 8, padding: '14px 20px', borderTop: `1px solid ${BORDER}` }}>
            <SecondaryButton onClick={() => router.replace('/')}>Cancel</SecondaryButton>
            {conflict === null && <PrimaryButton height={32} onClick={() => void run('new')} disabled={busy}>{busy ? 'Importing…' : 'Import team'}</PrimaryButton>}
            {conflict === 'alreadyYours' && <PrimaryButton height={32} color={C.red} onClick={() => void run('replace')} disabled={busy}>Replace my web copy</PrimaryButton>}
            {conflict === 'ownedElsewhere' && <PrimaryButton height={32} onClick={() => void run('copy')} disabled={busy}>Import my own copy</PrimaryButton>}
          </div>
        </div>
      )}
    </AppFrame>
  );
}

function Tile({ n, label }: { n: number; label: string }) {
  return (
    <div style={{ background: C.gray6, borderRadius: 10, padding: '10px 12px' }}>
      <div className="num" style={{ fontSize: 20, fontWeight: 700, color: n ? C.label : C.label3 }}>{n}</div>
      <div style={{ fontSize: 12, color: SUB }}>{label}</div>
    </div>
  );
}

// MARK: - Frame and pieces

function AppFrame({ children, width = 1040 }: { children: ReactNode; width?: number }) {
  const { session } = useAuth();
  const isPro = useIsPro();
  const email = session?.user.email ?? '';
  return (
    <div className="stl" style={{ position: 'fixed', inset: 0, overflow: 'auto', background: C.grouped }}>
      <style>{CSS}</style>
      <header style={{ height: 60, background: '#fff', borderBottom: `1px solid ${BORDER}`, padding: '0 24px', display: 'flex', alignItems: 'center', gap: 12, position: 'sticky', top: 0, zIndex: 5 }}>
        <img src="/app-icon.png" alt="" width={28} height={28} style={{ borderRadius: 7 }} />
        <span style={{ fontSize: 15, fontWeight: 600 }}>Stack the Lineup</span>
        <span style={{ marginLeft: 'auto', display: 'flex', alignItems: 'center', gap: 12 }}>
          {isPro && <span style={{ fontSize: 11, fontWeight: 700, letterSpacing: '0.06em', color: C.blue, background: 'rgba(0,122,255,0.1)', borderRadius: 999, padding: '3px 8px' }}>PRO</span>}
          <span style={{ fontSize: 13, color: SUB }}>{email}</span>
          <SecondaryButton onClick={() => void supabase.auth.signOut()}>Sign out</SecondaryButton>
        </span>
      </header>
      <main style={{ maxWidth: width, margin: '0 auto', padding: '36px 24px 64px' }}>{children}</main>
    </div>
  );
}

function Note({ kind, children }: { kind: 'warn' | 'error'; children: ReactNode }) {
  const [bg, fg] = kind === 'error' ? ['rgba(255,59,48,0.08)', C.red] : ['rgba(255,149,0,0.10)', 'rgb(133,79,10)'];
  return (
    <div role={kind === 'error' ? 'alert' : undefined} style={{ display: 'flex', gap: 8, alignItems: 'flex-start', padding: '10px 12px', borderRadius: 8, background: bg, color: fg, fontSize: 13, lineHeight: 1.4 }}>
      <Icon name="exclamationmark.triangle.fill" size={15} color={fg} style={{ marginTop: 1 }} />
      <span>{children}</span>
    </div>
  );
}

const outcomeError = (o: Exclude<ImportOutcome, { ok: true }>) => (o.reason === 'error' ? o.message : "Couldn't create the team. Try again.");
