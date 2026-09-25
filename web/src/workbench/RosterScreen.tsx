// Roster: the team's players as a table (Players) or a grid of everyone's
// position preferences, a right-side panel to add or edit a player, and an
// Import menu (paste a list, or a GameChanger roster CSV). Team-level only:
// attendance lives on each game.

import { useEffect, useMemo, useRef, useState, type CSSProperties, type ReactNode } from 'react';

import { isInfield, type FieldPosition, type Player, type PositionPreferenceTier } from '@/core/model';
import { matchKey, parseRosterCsv, ROSTER_CSV_ERRORS, type ImportedPlayer } from '@/core/rosterCsv';
import { useTeam } from '@/data/teamStore';

import { seasonTotals } from './HistoryScreen';
import { Icon } from './Icon';
import { parseRosterList } from './rosterList';
import { BORDER, BORDER2, Kbd, PageHeader, PrimaryButton, SecondaryButton, SUB } from './Shell';
import { useWorkbench } from './state';
import { badgeColor, C, playerAvatar, TIER_STYLE } from './theme';
import { Modal, PillButton } from './ui';

type View = 'list' | 'matrix';
type Totals = ReturnType<typeof seasonTotals>;

const TIER_ORDER: PositionPreferenceTier[] = ['Strength', 'Capable', 'Emergency', 'Never'];
const byLastName = (a: Player, b: Player) =>
  a.lastName.localeCompare(b.lastName, undefined, { sensitivity: 'base' }) || a.firstName.localeCompare(b.firstName, undefined, { sensitivity: 'base' });
const initials = (p: Pick<Player, 'firstName' | 'lastName'>) => `${p.firstName.charAt(0)}${p.lastName.charAt(0)}`.toUpperCase() || '?';

export function RosterScreen() {
  const w = useWorkbench();
  const [view, setView] = useState<View>('list');
  const [q, setQ] = useState('');
  const [importOpen, setImportOpen] = useState(false);
  const [pasteOpen, setPasteOpen] = useState(false);
  const [csv, setCsv] = useState<{ players: ImportedPlayer[] } | { error: string } | null>(null);
  const file = useRef<HTMLInputElement>(null);
  const totals = useMemo(() => seasonTotals(w.players, w.gameLogs), [w.players, w.gameLogs]);

  const t = q.trim().toLowerCase();
  const shown = w.players.filter((p) => !t || `${p.firstName} ${p.lastName}`.toLowerCase().includes(t)).sort(byLastName);

  const readCsv = (f: File) => {
    f.text().then((text) => {
      const r = parseRosterCsv(text);
      setCsv(r.ok ? { players: r.players } : { error: ROSTER_CSV_ERRORS[r.error] });
    }, () => setCsv({ error: "Couldn't read the file. It may be corrupted." }));
  };

  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', minWidth: 0, background: '#fff' }}>
      <PageHeader right={<>
        <span style={{ position: 'relative' }}>
          <SecondaryButton icon="square.and.arrow.down" onClick={() => setImportOpen((v) => !v)}>
            Import<Icon name="chevron.down" size={12} color={SUB} />
          </SecondaryButton>
          {importOpen && (
            <ImportMenu onClose={() => setImportOpen(false)}
              onPaste={() => { setImportOpen(false); setPasteOpen(true); }}
              onCsv={() => { setImportOpen(false); file.current?.click(); }} />
          )}
        </span>
        <PrimaryButton icon="person.badge.plus" height={32} onClick={() => w.setPlayerModal({ id: 'new' })}>Add player</PrimaryButton>
      </>}>
        <span style={{ fontSize: 15, fontWeight: 600 }}>Roster</span>
        <span style={{ fontSize: 14, color: SUB }}>{w.players.length} {w.players.length === 1 ? 'player' : 'players'}</span>
      </PageHeader>
      <input ref={file} type="file" accept=".csv,text/csv" hidden
        onChange={(e) => { const f = e.target.files?.[0]; e.target.value = ''; if (f) readCsv(f); }} />

      <div style={{ padding: '16px 24px 12px', display: 'flex', alignItems: 'center', gap: 12, flexShrink: 0 }}>
        <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Search players" aria-label="Search players" className="field"
          style={{ width: 240, height: 32, borderRadius: 8, border: `1px solid ${BORDER2}`, padding: '0 10px', fontSize: 14, outline: 'none' }} />
        <div role="tablist" style={{ display: 'flex', padding: 2, background: C.gray6, borderRadius: 8, height: 32 }}>
          {([['list', 'Players'], ['matrix', 'Position preferences']] as [View, string][]).map(([id, label]) => {
            const on = view === id;
            return (
              <button key={id} role="tab" aria-selected={on} onClick={() => setView(id)}
                style={{ padding: '0 14px', borderRadius: 6, fontSize: 13, fontWeight: 500, background: on ? '#fff' : 'transparent', boxShadow: on ? '0 1px 2px rgba(0,0,0,0.08)' : 'none' }}>
                {label}
              </button>
            );
          })}
        </div>
        {view === 'list' && <span style={{ marginLeft: 'auto', fontSize: 13, color: SUB }}>Click a player to edit details and position preferences.</span>}
      </div>

      <div style={{ flex: 1, overflowY: 'auto', padding: '0 24px 24px' }}>
        {view === 'list' ? <PlayersTable players={shown} totals={totals} /> : <PrefsMatrix players={shown} />}
        {w.players.length === 0 && <p style={{ fontSize: 14, color: SUB }}>No players yet. Add them one at a time, or import a list.</p>}
        {w.players.length > 0 && shown.length === 0 && <p style={{ fontSize: 14, color: SUB }}>No players match &quot;{q.trim()}&quot;.</p>}
      </div>

      {pasteOpen && <PasteList onClose={() => setPasteOpen(false)} />}
      {csv && <CsvImport result={csv} onClose={() => setCsv(null)} />}
    </div>
  );
}

// MARK: - Players table

const LIST_COLS = '44px 1.3fr 44px 1.5fr 0.9fr 140px 16px';

function TierPill({ tier, children }: { tier: PositionPreferenceTier; children: string }) {
  return <span style={{ fontSize: 11, fontWeight: 600, padding: '2px 7px', borderRadius: 999, background: TIER_STYLE[tier].bg, color: TIER_STYLE[tier].fg }}>{children}</span>;
}

function Avatar({ p, size }: { p: Player | { firstName: string; lastName: string; positionPreferences: Player['positionPreferences'] }; size: number }) {
  const av = playerAvatar(p);
  return (
    <span style={{ width: size, height: size, borderRadius: size / 2, background: av.bg, color: av.fg, fontSize: size * 0.36, fontWeight: 600, display: 'grid', placeItems: 'center', flexShrink: 0 }}>
      {initials(p)}
    </span>
  );
}

function PlayersTable({ players, totals }: { players: Player[]; totals: Totals }) {
  const w = useWorkbench();
  if (!players.length) return null;
  const maxBench = Math.max(0, ...w.players.map((p) => totals.get(p.id)?.bench ?? 0));
  const head: CSSProperties = { fontSize: 11, fontWeight: 600, letterSpacing: '0.04em', textTransform: 'uppercase', color: SUB };
  return (
    <div role="table" style={{ borderRadius: 10, border: `1px solid ${BORDER}`, overflow: 'hidden' }}>
      <div role="row" style={{ display: 'grid', gridTemplateColumns: LIST_COLS, gap: 12, height: 34, alignItems: 'center', padding: '0 14px', background: '#F7F7FA', borderBottom: `1px solid ${BORDER}` }}>
        <span style={head}>#</span><span style={head}>Player</span><span style={head}>Age</span><span style={head}>Plays well</span><span style={head}>Never</span><span style={head}>This season</span><span />
      </div>
      {players.map((p, i) => {
        const prefs = Object.entries(p.positionPreferences) as [FieldPosition, PositionPreferenceTier][];
        const good = prefs.filter(([, t]) => t === 'Strength' || t === 'Capable')
          .sort((a, b) => TIER_ORDER.indexOf(a[1]) - TIER_ORDER.indexOf(b[1]));
        const never = prefs.filter(([, t]) => t === 'Never');
        const s = totals.get(p.id) ?? { infield: 0, outfield: 0, bench: 0 };
        const games = s.infield + s.outfield + s.bench;
        return (
          <button key={p.id} role="row" className="h-row3" onClick={() => w.setPlayerModal({ id: p.id })}
            style={{ display: 'grid', gridTemplateColumns: LIST_COLS, gap: 12, alignItems: 'center', minHeight: 56, width: '100%', padding: '8px 14px', borderTop: i ? '1px solid rgba(60,60,67,0.08)' : 'none', textAlign: 'left' }}>
            <span className="num" style={{ fontSize: 13, color: SUB }}>{p.number}</span>
            <span style={{ display: 'flex', alignItems: 'center', gap: 10, minWidth: 0 }}>
              <Avatar p={p} size={32} />
              <span className="ellipsis" style={{ fontSize: 14, fontWeight: 500 }}>{p.firstName} {p.lastName}</span>
            </span>
            <span className="num" style={{ fontSize: 13 }}>{p.leagueAge ?? ''}</span>
            <span style={{ display: 'flex', flexWrap: 'wrap', gap: 4 }}>
              {prefs.length === 0 ? <span style={{ fontSize: 12, color: 'rgb(133,79,10)' }}>No preferences set</span>
                : good.length === 0 ? <span style={{ fontSize: 12, color: C.label3 }}>None</span>
                  : good.map(([pos, t]) => <TierPill key={pos} tier={t}>{pos}</TierPill>)}
            </span>
            <span style={{ display: 'flex', flexWrap: 'wrap', gap: 4 }}>
              {never.length ? never.map(([pos]) => <TierPill key={pos} tier="Never">{pos}</TierPill>) : <span style={{ fontSize: 12, color: C.label3 }}>None</span>}
            </span>
            <span>
              {games === 0 ? <span style={{ fontSize: 11, color: SUB }}>No games yet</span> : (
                <>
                  <span style={{ display: 'flex', height: 6, borderRadius: 3, background: C.gray6, overflow: 'hidden' }}>
                    <span style={{ width: `${(s.infield / games) * 100}%`, background: C.blue }} />
                    <span style={{ width: `${(s.outfield / games) * 100}%`, background: C.green }} />
                    <span style={{ width: `${(s.bench / games) * 100}%`, background: C.gray2 }} />
                  </span>
                  <span className="num" style={{ display: 'block', fontSize: 11, marginTop: 4, color: s.bench === maxBench && maxBench > 0 ? 'rgb(133,79,10)' : SUB }}>
                    {s.infield} IF · {s.outfield} OF · {s.bench} BN
                  </span>
                </>
              )}
            </span>
            <Icon name="chevron.right" size={12} color={C.label3} />
          </button>
        );
      })}
    </div>
  );
}

// MARK: - Position preferences grid

const CYCLE: (PositionPreferenceTier | undefined)[] = [undefined, 'Strength', 'Capable', 'Emergency', 'Never'];

function PrefsMatrix({ players }: { players: Player[] }) {
  const w = useWorkbench();
  const { updatePlayer } = useTeam();
  const positions = w.positions;
  const cols = `1.4fr repeat(${positions.length}, 1fr)`;
  const counts = positions.map((pos) => w.players.filter((p) => ['Strength', 'Capable'].includes(p.positionPreferences[pos] ?? '')).length);
  const thin = positions.filter((_, i) => counts[i] < 2);
  const cycle = (p: Player, pos: FieldPosition) => {
    const next = CYCLE[(CYCLE.indexOf(p.positionPreferences[pos]) + 1) % CYCLE.length];
    const prefs = { ...p.positionPreferences };
    if (next) prefs[pos] = next; else delete prefs[pos];
    updatePlayer({ ...p, positionPreferences: prefs });
  };
  const row: CSSProperties = { display: 'grid', gridTemplateColumns: cols, gap: 6, alignItems: 'center', padding: '5px 14px' };

  return (
    <>
      <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginBottom: 12 }}>
        <span style={{ fontSize: 13, color: SUB }}>Click a cell to cycle Strength, Capable, Emergency, Never. Auto-Fill uses these for every game.</span>
        <span style={{ marginLeft: 'auto', display: 'flex', gap: 6 }}>{TIER_ORDER.map((t) => <TierPill key={t} tier={t}>{t}</TierPill>)}</span>
      </div>
      <div style={{ borderRadius: 10, border: `1px solid ${BORDER}`, overflow: 'hidden' }}>
        <div style={{ ...row, background: '#F7F7FA', padding: '8px 14px', borderBottom: `1px solid ${BORDER}` }}>
          <span style={{ fontSize: 11, fontWeight: 600, letterSpacing: '0.04em', color: SUB }}>PLAYER</span>
          {positions.map((pos) => (
            <span key={pos} style={{ justifySelf: 'center', width: 36, fontSize: 12, fontWeight: 700, color: '#fff', background: badgeColor(pos), borderRadius: 6, padding: '4px 0', textAlign: 'center' }}>{pos}</span>
          ))}
        </div>
        {players.map((p) => (
          <div key={p.id} style={row}>
            <button className="h-bluetext" onClick={() => w.setPlayerModal({ id: p.id })} style={{ display: 'flex', alignItems: 'center', gap: 8, minWidth: 0 }}>
              <Avatar p={p} size={26} />
              <span className="ellipsis" style={{ fontSize: 14, fontWeight: 500 }}>{p.firstName} {p.lastName}</span>
            </button>
            {positions.map((pos) => {
              const t = p.positionPreferences[pos];
              return (
                <button key={pos} className="h-dim" onClick={() => cycle(p, pos)} title={`${pos}: ${t ?? 'No preference'}`}
                  aria-label={`${p.firstName} ${p.lastName} at ${pos}: ${t ?? 'no preference'}`}
                  style={{ height: 30, borderRadius: 7, fontSize: 12, fontWeight: 600, textAlign: 'center', overflow: 'hidden',
                    ...(t ? { background: TIER_STYLE[t].bg, color: TIER_STYLE[t].fg } : { background: '#fff', boxShadow: 'inset 0 0 0 1px rgba(60,60,67,0.12)' }) }}>
                  {t ?? ''}
                </button>
              );
            })}
          </div>
        ))}
        <div style={{ ...row, background: '#FAFAFC', padding: '10px 14px', borderTop: `1px solid ${BORDER}` }}>
          <span>
            <span style={{ display: 'block', fontSize: 13, fontWeight: 600 }}>Strength or Capable</span>
            <span style={{ display: 'block', fontSize: 11, color: SUB }}>Players Auto-Fill prefers</span>
          </span>
          {positions.map((pos, i) => (
            <span key={pos} className="num" style={{ justifySelf: 'center', fontSize: 16, fontWeight: 700, padding: '2px 10px', borderRadius: 6,
              ...(counts[i] < 2 ? { color: 'rgb(133,79,10)', background: 'rgba(255,149,0,0.14)' } : {}) }}>
              {counts[i]}
            </span>
          ))}
        </div>
      </div>
      {thin.length > 0 && w.players.length > 0 && (
        <div style={{ marginTop: 14, background: 'rgba(255,149,0,0.10)', borderRadius: 10, padding: '12px 14px', fontSize: 14, lineHeight: '19px' }}>
          <b style={{ color: 'rgb(133,79,10)', fontWeight: 600 }}>
            {thin.length === 1
              ? `${counts[positions.indexOf(thin[0])] === 0 ? 'No players are' : 'Only 1 player is'} marked Strength or Capable at ${thin[0]}.`
              : `${thin.join(', ')} have fewer than 2 players marked Strength or Capable.`}
          </b>{' '}
          Auto-Fill will fall back to players with no preference or Emergency there.
        </div>
      )}
    </>
  );
}

// MARK: - Import

function ImportMenu({ onClose, onPaste, onCsv }: { onClose(): void; onPaste(): void; onCsv(): void }) {
  const item = (icon: string, label: string, detail: string, onClick: () => void) => (
    <button role="menuitem" className="menu-row" onClick={onClick}
      style={{ display: 'flex', gap: 10, alignItems: 'flex-start', width: '100%', padding: '8px 10px', borderRadius: 7, textAlign: 'left' }}>
      <Icon name={icon} size={16} color={C.blue} style={{ marginTop: 1 }} />
      <span>
        <span style={{ display: 'block', fontSize: 14, fontWeight: 500 }}>{label}</span>
        <span style={{ display: 'block', fontSize: 12, color: SUB }}>{detail}</span>
      </span>
    </button>
  );
  return (
    <>
      <div onClick={onClose} style={{ position: 'fixed', inset: 0, zIndex: 20 }} />
      <div role="menu" className="pop" style={{ position: 'absolute', top: 38, right: 0, zIndex: 21, width: 290, background: 'rgba(255,255,255,0.98)', borderRadius: 10, padding: 5, boxShadow: '0 10px 30px rgba(0,0,0,0.18), 0 0 0 0.5px rgba(0,0,0,0.14)' }}>
        {item('doc.text', 'Paste a list of names', 'One player per line', onPaste)}
        {item('square.and.arrow.down', 'Import from GameChanger', 'Upload the roster CSV export', onCsv)}
      </div>
    </>
  );
}

/** Adds players to the end of the roster; returns how many. */
function useAddAll() {
  const { addPlayer } = useTeam();
  return (list: { firstName: string; lastName: string; number: string }[]) => {
    for (const p of list) addPlayer({ firstName: p.firstName, lastName: p.lastName, number: p.number, positionPreferences: {} });
    return list.length;
  };
}

function PasteList({ onClose }: { onClose(): void }) {
  const w = useWorkbench();
  const addAll = useAddAll();
  const [text, setText] = useState('');
  const parsed = parseRosterList(text);
  return (
    <Modal title="Paste a list of names" onClose={onClose}
      footer={<span style={{ marginLeft: 'auto', display: 'flex', gap: 8 }}>
        <PillButton onClick={onClose}>Cancel</PillButton>
        <PillButton kind="primary" disabled={!parsed.length} onClick={() => { const n = addAll(parsed); w.showToast(`Added ${n} ${n === 1 ? 'player' : 'players'}`); onClose(); }}>
          {parsed.length ? `Add ${parsed.length} ${parsed.length === 1 ? 'player' : 'players'}` : 'Add'}
        </PillButton>
      </span>}>
      <p style={{ margin: '0 0 8px', fontSize: 13, color: SUB }}>One player per line, with a jersey number if you like: &quot;Jake Rivera 4&quot;.</p>
      <textarea autoFocus value={text} onChange={(e) => setText(e.target.value)} rows={10} aria-label="Players, one per line"
        style={{ width: '100%', borderRadius: 8, border: `1px solid ${BORDER2}`, padding: 10, fontSize: 15, lineHeight: '21px', resize: 'vertical', outline: 'none' }} />
    </Modal>
  );
}

/** Preview of a GameChanger (or any roster) CSV, as on iOS: duplicates by full name are skipped by default. */
function CsvImport({ result, onClose }: { result: { players: ImportedPlayer[] } | { error: string }; onClose(): void }) {
  const w = useWorkbench();
  const addAll = useAddAll();
  const [skipDupes, setSkipDupes] = useState(true);
  if ('error' in result) {
    return (
      <Modal title="Couldn't import that file" onClose={onClose} width={440}
        footer={<span style={{ marginLeft: 'auto' }}><PillButton kind="primary" onClick={onClose}>OK</PillButton></span>}>
        <p style={{ margin: 0, fontSize: 14, lineHeight: '20px' }}>{result.error}</p>
        <p style={{ margin: '8px 0 0', fontSize: 13, color: SUB }}>In GameChanger, export your team&apos;s roster or season stats as a CSV, then choose that file.</p>
      </Modal>
    );
  }
  const existing = new Set(w.players.map(matchKey));
  const dupes = result.players.filter((p) => existing.has(matchKey(p)));
  const toAdd = skipDupes ? result.players.filter((p) => !existing.has(matchKey(p))) : result.players;
  return (
    <Modal title="Import from GameChanger" onClose={onClose} width={520}
      footer={<span style={{ marginLeft: 'auto', display: 'flex', gap: 8 }}>
        <PillButton onClick={onClose}>Cancel</PillButton>
        <PillButton kind="primary" disabled={!toAdd.length} onClick={() => { const n = addAll(toAdd); w.showToast(`Added ${n} ${n === 1 ? 'player' : 'players'}`); onClose(); }}>
          {toAdd.length ? `Add ${toAdd.length} ${toAdd.length === 1 ? 'player' : 'players'}` : 'Nothing to add'}
        </PillButton>
      </span>}>
      <p style={{ margin: '0 0 10px', fontSize: 13, color: SUB }}>Found {result.players.length} {result.players.length === 1 ? 'player' : 'players'}. Set positions and league ages after they&apos;re added.</p>
      {dupes.length > 0 && (
        <label style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 14, marginBottom: 10 }}>
          <input type="checkbox" checked={skipDupes} onChange={(e) => setSkipDupes(e.target.checked)} />
          Skip {dupes.length} already on the roster
        </label>
      )}
      <div style={{ borderRadius: 10, border: `1px solid ${BORDER}`, overflow: 'hidden' }}>
        {result.players.map((p, i) => {
          const dupe = existing.has(matchKey(p));
          return (
            <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 10, height: 38, padding: '0 12px', borderTop: i ? '1px solid rgba(60,60,67,0.08)' : 'none', opacity: dupe && skipDupes ? 0.45 : 1 }}>
              <span className="num" style={{ width: 28, fontSize: 13, color: SUB }}>{p.number}</span>
              <span className="ellipsis" style={{ flex: 1, fontSize: 14 }}>{p.firstName} {p.lastName}</span>
              {dupe && <span style={{ fontSize: 12, color: SUB }}>Already on roster</span>}
            </div>
          );
        })}
      </div>
    </Modal>
  );
}

// MARK: - Add / edit player panel

const SEGMENTS: [PositionPreferenceTier | undefined, string][] = [['Strength', 'Strength'], ['Capable', 'Capable'], [undefined, 'No pref'], ['Emergency', 'Emergency'], ['Never', 'Never']];

export function PlayerPanel() {
  const w = useWorkbench();
  const { addPlayer, updatePlayer, deletePlayer } = useTeam();
  const m = w.playerModal!;
  const existing = m.id === 'new' ? undefined : w.byId.get(m.id);
  const [first, setFirst] = useState(existing?.firstName ?? '');
  const [last, setLast] = useState(existing?.lastName ?? '');
  const [num, setNum] = useState(existing?.number ?? '');
  const [age, setAge] = useState(existing?.leagueAge === undefined ? '' : String(existing.leagueAge));
  const [prefs, setPrefs] = useState<Player['positionPreferences']>({ ...(existing?.positionPreferences ?? {}) });
  const [confirmRemove, setConfirmRemove] = useState(false);
  const totals = useMemo(() => seasonTotals(w.players, w.gameLogs), [w.players, w.gameLogs]);
  const close = () => w.setPlayerModal(null);
  const valid = first.trim().length > 0;
  const fullName = `${first.trim()} ${last.trim()}`.trim();

  const save = () => {
    if (!valid) return;
    const fields: Omit<Player, 'id'> = {
      firstName: first.trim(), lastName: last.trim(), number: num.trim(), positionPreferences: prefs,
      ...(age ? { leagueAge: Number(age) } : {}),
      ...(existing?.hittingArchetype ? { hittingArchetype: existing.hittingArchetype } : {}),
    };
    if (existing) updatePlayer({ ...fields, id: existing.id }); else addPlayer(fields);
    w.showToast(`${existing ? 'Saved' : 'Added'} ${fullName}`);
    close();
  };
  const remove = () => {
    if (!existing) return;
    if (!confirmRemove) { setConfirmRemove(true); return; }
    deletePlayer(existing.id);
    w.showToast(`Removed ${existing.firstName} ${existing.lastName}`.trim());
    close();
  };
  const setTier = (pos: FieldPosition, t: PositionPreferenceTier | undefined) => {
    const next = { ...prefs };
    if (t) next[pos] = t; else delete next[pos];
    setPrefs(next);
  };

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') w.setPlayerModal(null); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [w]);

  const s = existing ? totals.get(existing.id) : undefined;
  const maxBench = Math.max(0, ...w.players.map((p) => totals.get(p.id)?.bench ?? 0));
  const hasSeason = !!s && s.infield + s.outfield + s.bench > 0;

  return (
    <div>
      <div onClick={close} style={{ position: 'fixed', inset: 0, zIndex: 40, background: 'rgba(0,0,0,0.12)' }} />
      <aside role="dialog" aria-modal aria-label={existing ? 'Edit player' : 'Add player'} className="slide-in"
        style={{ position: 'fixed', top: 0, right: 0, bottom: 0, width: 440, zIndex: 41, background: '#fff', boxShadow: '-12px 0 32px rgba(0,0,0,0.12)', display: 'flex', flexDirection: 'column' }}>
        <header style={{ height: 64, flexShrink: 0, borderBottom: `1px solid ${BORDER}`, padding: '0 20px', display: 'flex', alignItems: 'center', gap: 12 }}>
          <Avatar p={{ firstName: first || '?', lastName: last, positionPreferences: prefs }} size={36} />
          <span style={{ flex: 1, minWidth: 0 }}>
            <span style={{ display: 'block', fontSize: 17, fontWeight: 600 }}>{existing ? 'Edit player' : 'Add player'}</span>
            <span className="ellipsis" style={{ display: 'block', fontSize: 12, color: SUB }}>{existing ? fullName || 'Unnamed player' : 'New to the roster'}</span>
          </span>
          <button onClick={close} aria-label="Close"><Kbd>esc</Kbd></button>
        </header>

        <form onSubmit={(e) => { e.preventDefault(); save(); }} style={{ flex: 1, overflowY: 'auto', padding: 20, display: 'flex', flexDirection: 'column', gap: 20 }}>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
            <Field label="First name"><Input value={first} onChange={setFirst} autoFocus /></Field>
            <Field label="Last name"><Input value={last} onChange={setLast} /></Field>
          </div>
          <div style={{ display: 'flex', gap: 12, alignItems: 'flex-end' }}>
            <Field label="Number"><Input value={num} onChange={(v) => setNum(v.replace(/\D/g, '').slice(0, 3))} width={96} numeric /></Field>
            <Field label="League age"><Input value={age} onChange={(v) => setAge(v.replace(/\D/g, '').slice(0, 2))} width={96} numeric /></Field>
            <span style={{ fontSize: 12, color: SUB, paddingBottom: 10 }}>Used for pitch count rules.</span>
          </div>

          {hasSeason && (
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 8 }}>
              <Tile value={s!.infield} label="Infield innings" />
              <Tile value={s!.outfield} label="Outfield innings" />
              <Tile value={s!.bench} label="Bench innings" warn={s!.bench === maxBench && maxBench > 0} />
            </div>
          )}

          <div>
            <div style={{ display: 'flex', alignItems: 'baseline', marginBottom: 8 }}>
              <span style={{ fontSize: 11, fontWeight: 600, letterSpacing: '0.04em', textTransform: 'uppercase', color: SUB }}>Positions</span>
              <button type="button" className="h-link" onClick={() => setPrefs({})} style={{ marginLeft: 'auto', fontSize: 13, color: C.blue }}>Clear all</button>
            </div>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
              {w.positions.map((pos) => (
                <div key={pos} style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                  <span style={{ width: 34, fontSize: 12, fontWeight: 700, color: '#fff', background: isInfield(pos) ? C.blue : C.green, borderRadius: 6, padding: '5px 0', textAlign: 'center', flexShrink: 0 }}>{pos}</span>
                  <div role="radiogroup" aria-label={`${pos} preference`} style={{ flex: 1, display: 'grid', gridTemplateColumns: 'repeat(5, 1fr)', background: C.gray6, borderRadius: 8, padding: 2 }}>
                    {SEGMENTS.map(([t, label]) => {
                      const on = prefs[pos] === t;
                      const look = on ? (t ? { background: TIER_STYLE[t].bg, color: TIER_STYLE[t].fg } : { background: '#fff', color: C.label }) : { color: SUB };
                      return (
                        <button key={label} type="button" role="radio" aria-checked={on} onClick={() => setTier(pos, t)}
                          style={{ height: 28, borderRadius: 6, fontSize: 11, fontWeight: on ? 600 : 400, textAlign: 'center', boxShadow: on ? '0 1px 2px rgba(0,0,0,0.08)' : 'none', ...look }}>
                          {label}
                        </button>
                      );
                    })}
                  </div>
                </div>
              ))}
            </div>
            <p style={{ fontSize: 12, lineHeight: '17px', color: SUB, margin: '10px 0 0' }}>
              Auto-Fill prioritizes Strength and Capable positions. Emergency is used as a last resort. Never positions are never assigned.
            </p>
          </div>
          <button type="submit" hidden />
        </form>

        <footer style={{ height: 64, flexShrink: 0, borderTop: `1px solid ${BORDER}`, padding: '0 20px', display: 'flex', alignItems: 'center', gap: 8 }}>
          {existing && (
            <button onClick={remove} onBlur={() => setConfirmRemove(false)} className="h-bright"
              style={{ height: 32, padding: '0 12px', borderRadius: 8, fontSize: 13, fontWeight: 500, color: C.red, background: confirmRemove ? 'rgba(255,59,48,0.12)' : 'rgba(255,59,48,0.05)', border: '0.5px solid rgba(255,59,48,0.4)' }}>
              {confirmRemove ? 'Click again to remove' : 'Remove player'}
            </button>
          )}
          <span style={{ marginLeft: 'auto', display: 'flex', gap: 8 }}>
            <SecondaryButton onClick={close}>Cancel</SecondaryButton>
            <PrimaryButton height={32} onClick={save} disabled={!valid}>Save</PrimaryButton>
          </span>
        </footer>
      </aside>
    </div>
  );
}

function Field({ label, children }: { label: string; children: ReactNode }) {
  return (
    <label style={{ display: 'flex', flexDirection: 'column', gap: 6, minWidth: 0 }}>
      <span style={{ fontSize: 11, fontWeight: 600, letterSpacing: '0.04em', textTransform: 'uppercase', color: SUB }}>{label}</span>
      {children}
    </label>
  );
}

function Input({ value, onChange, width, numeric, autoFocus }: { value: string; onChange(v: string): void; width?: number; numeric?: boolean; autoFocus?: boolean }) {
  return (
    <input value={value} onChange={(e) => onChange(e.target.value)} inputMode={numeric ? 'numeric' : undefined} autoFocus={autoFocus} className="field"
      style={{ width: width ?? '100%', height: 36, borderRadius: 8, border: `1px solid ${BORDER2}`, padding: '0 10px', fontSize: 15, outline: 'none' }} />
  );
}

function Tile({ value, label, warn }: { value: number; label: string; warn?: boolean }) {
  return (
    <div style={{ background: C.gray6, borderRadius: 10, padding: '10px 12px' }}>
      <div className="num" style={{ fontSize: 18, fontWeight: 700, color: warn ? C.orange : C.label }}>{value}</div>
      <div style={{ fontSize: 11, color: SUB }}>{label}</div>
    </div>
  );
}
