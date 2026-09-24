// Players: team card, add players, and the roster with each player's
// position preferences. Clicking a player opens the editor (a centered sheet,
// like the iPad's Edit Player).

import { useRouter } from 'expo-router';
import { useState } from 'react';

import type { FieldPosition, Player, PositionPreferenceTier } from '@/core/model';
import { useTeam } from '@/data/teamStore';

import { Icon } from './Icon';
import { parseRosterList } from './rosterList';
import { useWorkbench } from './state';
import { avatarStyle, C, TIER_STYLE } from './theme';
import { PageHeader, PrimaryButton } from './Shell';
import { card, Modal, PillButton, TextField } from './ui';

export function PlayersScreen({ demo }: { demo?: boolean }) {
  const w = useWorkbench();
  const router = useRouter();
  const [setupOpen, setSetupOpen] = useState(false);
  const [addOpen, setAddOpen] = useState(false);
  const [pasteOpen, setPasteOpen] = useState(false);

  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', minWidth: 0, background: C.grouped }}>
      <PageHeader right={<PrimaryButton icon="person.badge.plus" onClick={() => w.setPlayerModal({ id: 'new' })}>Add player</PrimaryButton>}>
        <span style={{ fontSize: 15, fontWeight: 600 }}>Roster</span>
      </PageHeader>
      <div style={{ flex: 1, overflowY: 'auto' }}>
      <div style={{ maxWidth: 900, margin: '0 auto', padding: '24px 24px 36px' }}>

        <div style={card}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 14, padding: '14px 16px' }}>
            <span style={{ width: 26, height: 26, borderRadius: 13, background: `#${w.team.colorHex}` }} />
            <span className="ellipsis" style={{ fontSize: 20, fontWeight: 700, flex: 1 }}>{w.team.name || 'Untitled team'}</span>
            <button className="h-link" title="Team settings" aria-label="Team settings" onClick={() => w.setSettingsOpen(true)} style={{ display: 'flex' }}><Icon name="gearshape" size={20} color={C.blue} /></button>
            <span style={{ width: 0.5, height: 20, background: C.sep }} />
            <button className="h-link" style={{ fontSize: 17, color: C.blue }} onClick={() => router.push('/')} disabled={demo}>Switch</button>
          </div>
          <button onClick={() => setSetupOpen((v) => !v)} aria-expanded={setupOpen}
            style={{ width: '100%', borderTop: C.hair, padding: '10px 0', fontSize: 15, color: C.label2, display: 'flex', justifyContent: 'center', alignItems: 'center', gap: 6 }}>
            Team setup <Icon name="chevron.down" size={14} color={C.label2} style={{ transform: setupOpen ? 'rotate(180deg)' : undefined }} />
          </button>
          {setupOpen && (
            <div style={{ borderTop: C.hair, padding: '12px 16px', fontSize: 15, display: 'grid', gridTemplateColumns: '180px 1fr', rowGap: 8 }}>
              <span style={{ color: C.label2 }}>Innings per game</span><span>{w.team.gameInningCount}</span>
              <span style={{ color: C.label2 }}>Coach</span><span>{w.team.coachName || '—'}</span>
              <span style={{ color: C.label2 }}>Outfielders</span><span>{w.team.fairPlayConfig.outfielderCount}</span>
              <span style={{ color: C.label2 }}>Pitch count rules</span><span>{w.team.pitchingConfig.rulesEnabled ? 'On' : 'Off'}</span>
              <button className="h-link" onClick={() => w.setSettingsOpen(true)} style={{ gridColumn: '1 / -1', justifySelf: 'start', fontSize: 15, color: C.blue }}>Change in team settings</button>
            </div>
          )}
        </div>

        <div style={{ ...card, marginTop: 14 }}>
          <button className="h-row2" onClick={() => setAddOpen((v) => !v)} aria-expanded={addOpen}
            style={{ display: 'flex', alignItems: 'center', gap: 14, width: '100%', padding: '12px 16px', borderRadius: 12 }}>
            <span style={{ width: 32, height: 32, borderRadius: 8, background: 'rgba(0,122,255,0.15)', display: 'grid', placeItems: 'center' }}>
              <Icon name="person.badge.plus" size={18} color={C.blue} />
            </span>
            <span style={{ fontSize: 17 }}>Add players</span>
            <span style={{ marginLeft: 'auto', fontSize: 13, color: C.label2 }}>One at a time, paste a list, or import from GameChanger</span>
            <Icon name="chevron.down" size={14} color={C.label3} style={{ transform: addOpen ? 'rotate(180deg)' : undefined }} />
          </button>
          {addOpen && (
            <div style={{ borderTop: C.hair, display: 'flex' }}>
              <AddOption onClick={() => w.setPlayerModal({ id: 'new' })}>One at a time</AddOption>
              <AddOption onClick={() => setPasteOpen(true)}>Paste a list</AddOption>
              <AddOption disabled>GameChanger (coming soon)</AddOption>
            </div>
          )}
        </div>

        <div style={{ fontSize: 15, fontWeight: 600, color: C.label2, padding: '22px 4px 8px' }}>
          Roster · {w.players.length} {w.players.length === 1 ? 'player' : 'players'}
        </div>
        <div style={{ ...card, overflow: 'hidden' }}>
          {w.players.map((p, i) => <PlayerRow key={p.id} p={p} first={i === 0} />)}
          {w.players.length === 0 && <div style={{ padding: 16, color: C.label2 }}>No players yet. Add them above.</div>}
        </div>
      </div>
      </div>
      {pasteOpen && <PasteList onClose={() => setPasteOpen(false)} />}
    </div>
  );
}

function AddOption({ children, onClick, disabled }: { children: string; onClick?: () => void; disabled?: boolean }) {
  return (
    <button className="h-tint" onClick={onClick} disabled={disabled}
      style={{ flex: 1, padding: '12px 0', textAlign: 'center', fontSize: 15, color: disabled ? C.label3 : C.blue, borderLeft: C.hair, marginLeft: -0.5 }}>
      {children}
    </button>
  );
}

const tiersOf = (p: Player, t: PositionPreferenceTier) =>
  Object.entries(p.positionPreferences).filter(([, x]) => x === t).map(([k]) => k);

function Pill({ tier, children }: { tier: PositionPreferenceTier; children: string }) {
  return <span style={{ fontSize: 13, fontWeight: 600, padding: '3px 8px', borderRadius: 5, background: TIER_STYLE[tier].bg, color: TIER_STYLE[tier].fg }}>{children}</span>;
}

function PlayerRow({ p, first }: { p: Player; first: boolean }) {
  const w = useWorkbench();
  const absent = w.lineup.absentPlayerIDs.includes(p.id);
  const av = avatarStyle(p.id);
  const strength = tiersOf(p, 'Strength');
  const capable = tiersOf(p, 'Capable');
  const never = tiersOf(p, 'Never');
  const emergency = tiersOf(p, 'Emergency');
  const avoid = never.length + emergency.length > 0;
  return (
    <button className="h-row2" onClick={() => w.setPlayerModal({ id: p.id })}
      style={{ display: 'flex', gap: 14, width: '100%', padding: '14px 16px', borderTop: first ? 'none' : C.hair, opacity: absent ? 0.55 : 1 }}>
      <span style={{ width: 40, height: 40, borderRadius: 20, background: av.bg, color: av.fg, fontSize: 15, fontWeight: 600, display: 'grid', placeItems: 'center', flexShrink: 0 }}>
        {`${p.firstName.charAt(0)}${p.lastName.charAt(0)}`.toUpperCase()}
      </span>
      <span style={{ flex: 1, minWidth: 0 }}>
        <span style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <span style={{ fontSize: 17 }}>{p.firstName} {p.lastName}</span>
          {p.number && <span style={{ fontSize: 12, fontWeight: 500, color: C.label2, background: C.gray5, borderRadius: 4, padding: '2px 5px' }}>#{p.number}</span>}
          {absent && <span style={{ fontSize: 12, color: C.label2 }}>Absent</span>}
          {p.leagueAge === undefined && w.team.pitchingConfig.rulesEnabled && <span style={{ fontSize: 12, color: C.orange }}>No league age</span>}
        </span>
        {(strength.length + capable.length > 0 || avoid) && (
          <span style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', marginTop: 8, gap: 12 }}>
            <span>
              {strength.length + capable.length > 0 && <Label>Plays</Label>}
              <span style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
                {strength.length > 0 && <Pill tier="Strength">{strength.join(', ')}</Pill>}
                {capable.length > 0 && <Pill tier="Capable">{capable.join(', ')}</Pill>}
              </span>
            </span>
            <span>
              {avoid && <Label>Avoid</Label>}
              <span style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
                {never.length > 0 && <Pill tier="Never">{never.join(', ')}</Pill>}
                {emergency.map((pos) => <Pill key={pos} tier="Emergency">{`${pos}*`}</Pill>)}
              </span>
            </span>
          </span>
        )}
      </span>
      <Icon name="chevron.right" size={14} color={C.label3} style={{ marginTop: 4 }} />
    </button>
  );
}

function Label({ children }: { children: string }) {
  return <span style={{ display: 'block', fontSize: 11, fontWeight: 500, letterSpacing: 0.6, color: C.label2, textTransform: 'uppercase', marginBottom: 4 }}>{children}</span>;
}

// MARK: - Editor

const TIERS: (PositionPreferenceTier | null)[] = ['Strength', 'Capable', null, 'Emergency', 'Never'];

export function PlayerModal() {
  const w = useWorkbench();
  const { addPlayer, updatePlayer, deletePlayer } = useTeam();
  const m = w.playerModal!;
  const existing = m.id === 'new' ? undefined : w.byId.get(m.id);
  const [first, setFirst] = useState(existing?.firstName ?? '');
  const [last, setLast] = useState(existing?.lastName ?? '');
  const [num, setNum] = useState(existing?.number ?? '');
  const [age, setAge] = useState(existing?.leagueAge === undefined ? '' : String(existing.leagueAge));
  const [prefs, setPrefs] = useState<Player['positionPreferences']>({ ...(existing?.positionPreferences ?? {}) });
  const [confirmDelete, setConfirmDelete] = useState(false);
  const close = () => w.setPlayerModal(null);

  const ageOk = age.trim() === '' || /^\d{1,2}$/.test(age.trim());
  const valid = first.trim().length > 0 && ageOk;
  const save = () => {
    if (!valid) return;
    const leagueAge = age.trim() === '' ? undefined : Number(age);
    const fields: Omit<Player, 'id'> = {
      firstName: first.trim(), lastName: last.trim(), number: num.trim(), positionPreferences: prefs,
      ...(leagueAge !== undefined ? { leagueAge } : {}),
      ...(existing?.hittingArchetype ? { hittingArchetype: existing.hittingArchetype } : {}),
    };
    if (existing) updatePlayer({ ...fields, id: existing.id }); else addPlayer(fields);
    close();
  };
  const setTier = (pos: FieldPosition, t: PositionPreferenceTier | null) => {
    const next = { ...prefs };
    if (t) next[pos] = t; else delete next[pos];
    setPrefs(next);
  };

  return (
    <Modal title={existing ? 'Edit Player' : 'Add Player'} onClose={close} width={600}
      footer={<>
        {existing && !confirmDelete && <PillButton kind="danger" onClick={() => setConfirmDelete(true)}>Remove player</PillButton>}
        {existing && confirmDelete && (
          <>
            <span style={{ fontSize: 14 }}>Remove {existing.firstName} from the team?</span>
            <PillButton kind="danger" onClick={() => { deletePlayer(existing.id); close(); }}>Remove</PillButton>
            <PillButton onClick={() => setConfirmDelete(false)}>Keep</PillButton>
          </>
        )}
        <span style={{ marginLeft: 'auto', display: 'flex', gap: 8 }}>
          <PillButton onClick={close}>Cancel</PillButton>
          <PillButton kind="primary" onClick={save} disabled={!valid}>{existing ? 'Save' : 'Add'}</PillButton>
        </span>
      </>}>
      <form onSubmit={(e) => { e.preventDefault(); save(); }} style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
        <div style={{ display: 'flex', gap: 10 }}>
          <TextField label="First name" value={first} onChange={setFirst} autoFocus />
          <TextField label="Last name" value={last} onChange={setLast} />
        </div>
        <div style={{ display: 'flex', gap: 10 }}>
          <TextField label="Number" value={num} onChange={setNum} width={120} />
          <TextField label="League age" value={age} onChange={setAge} width={120} inputMode="numeric" />
          <span style={{ alignSelf: 'flex-end', fontSize: 13, color: ageOk ? C.label2 : C.red, paddingBottom: 8 }}>
            {ageOk ? 'Used for pitch count rules.' : 'League age should be a number, like 10.'}
          </span>
        </div>
        <div>
          <Label>Positions</Label>
          <div style={{ ...card, overflow: 'hidden' }}>
            {w.positions.map((pos, i) => (
              <div key={pos} style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '6px 10px', borderTop: i ? C.hair : 'none' }}>
                <span style={{ width: 36, fontWeight: 700, fontSize: 14 }}>{pos}</span>
                <div role="radiogroup" aria-label={`${pos} preference`} style={{ display: 'flex', gap: 4, marginLeft: 'auto' }}>
                  {TIERS.map((t) => {
                    const on = (prefs[pos] ?? null) === t;
                    const s = t ? TIER_STYLE[t] : { bg: C.gray5, fg: C.label };
                    return (
                      <button key={String(t)} type="button" role="radio" aria-checked={on} onClick={() => setTier(pos, t)}
                        style={{ fontSize: 12, fontWeight: 600, padding: '4px 10px', borderRadius: 999, background: on ? s.bg : 'transparent', color: on ? s.fg : C.label3, boxShadow: on ? `inset 0 0 0 1px ${s.fg}` : 'none' }}>
                        {t ?? 'No preference'}
                      </button>
                    );
                  })}
                </div>
              </div>
            ))}
          </div>
        </div>
        <button type="submit" hidden />
      </form>
    </Modal>
  );
}

function PasteList({ onClose }: { onClose(): void }) {
  const { addPlayer } = useTeam();
  const [text, setText] = useState('');
  const parsed = parseRosterList(text);
  return (
    <Modal title="Paste a list" onClose={onClose}
      footer={<span style={{ marginLeft: 'auto', display: 'flex', gap: 8 }}>
        <PillButton onClick={onClose}>Cancel</PillButton>
        <PillButton kind="primary" disabled={!parsed.length} onClick={() => { parsed.forEach(addPlayer); onClose(); }}>
          {parsed.length ? `Add ${parsed.length} ${parsed.length === 1 ? 'player' : 'players'}` : 'Add'}
        </PillButton>
      </span>}>
      <p style={{ margin: '0 0 8px', fontSize: 13, color: C.label2 }}>One player per line, with a jersey number if you like: &quot;Jake Rivera 4&quot;.</p>
      <textarea autoFocus value={text} onChange={(e) => setText(e.target.value)} rows={10} aria-label="Players, one per line"
        style={{ width: '100%', borderRadius: 8, border: `0.5px solid ${C.gray4}`, padding: 10, fontSize: 15, lineHeight: '21px', resize: 'vertical', outline: 'none' }} />
    </Modal>
  );
}
