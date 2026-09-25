// The app frame from the game-prep handoff: a left sidebar (team switcher,
// jump-to, nav, upcoming games, coach) beside the page. Also the pieces every
// page shares: the 60px page header, secondary buttons, status pills, and the
// fair-play box.

import { useRouter } from 'expo-router';
import { useEffect, useMemo, useRef, useState, type CSSProperties, type ReactNode } from 'react';

import { useAuth } from '@/data/auth';
import { supabase } from '@/data/supabase';
import { listTeams, type TeamSummary } from '@/data/teams';

import { Icon } from './Icon';
import { gameStatus, gameTitle, seasonLabel } from './gameStatus';
import { useWorkbench, type Screen } from './state';
import { C } from './theme';

export const SIDEBAR_BG = '#F7F7FA';
export const BORDER = 'rgba(60,60,67,0.12)';
export const BORDER2 = 'rgba(60,60,67,0.18)';
export const FILL = '#EFEFF4';
export const SUB = C.label2;

// MARK: - Sidebar

const NAV: [Screen, string, string][] = [
  ['home', 'Home', 'clock.arrow.circlepath'],
  ['game', 'Games', 'baseball.diamond.bases'],
  ['roster', 'Roster', 'person.3.fill'],
  ['stats', 'Season stats', 'list.number'],
];

export function Sidebar({ demo }: { demo?: boolean }) {
  const w = useWorkbench();
  const [teamMenu, setTeamMenu] = useState(false);
  const [jump, setJump] = useState(false);
  const [account, setAccount] = useState(false);
  const st = gameStatus(w);
  const meta = (s: Screen) => (s === 'game' ? String(1 + w.gameLogs.length) : s === 'roster' ? String(w.players.length) : '');
  const initials = (w.team.coachName || 'Coach').split(/\s+/).map((x) => x.charAt(0)).join('').slice(0, 2).toUpperCase();

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k') { e.preventDefault(); setJump(true); }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);

  return (
    <aside style={{ width: 236, flexShrink: 0, background: SIDEBAR_BG, borderRight: `1px solid ${BORDER}`, padding: '12px 10px', display: 'flex', flexDirection: 'column', gap: 16, minHeight: 0, position: 'relative' }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 2 }}>
        <button className="h-side" onClick={() => w.go('settings')} title="Team settings"
          style={{ flex: 1, minWidth: 0, display: 'flex', alignItems: 'center', gap: 10, padding: '6px 8px', borderRadius: 8 }}>
          <img src="/app-icon.png" alt="" width={28} height={28}
            style={{ borderRadius: 7, flexShrink: 0, boxShadow: `0 0 0 2px ${SIDEBAR_BG}, 0 0 0 3.5px #${w.team.colorHex}` }} />
          <span style={{ flex: 1, minWidth: 0, textAlign: 'left' }}>
            <span className="ellipsis" style={{ display: 'block', fontSize: 14, fontWeight: 600 }}>{w.team.name || 'Untitled team'}</span>
            <span style={{ display: 'block', fontSize: 12, color: SUB }}>{seasonLabel(w.lineup.gameDate)}</span>
          </span>
        </button>
        <button className="h-side" onClick={() => setTeamMenu((v) => !v)} aria-haspopup="menu" aria-expanded={teamMenu} aria-label="Switch team"
          title="Switch team" style={{ width: 26, height: 40, borderRadius: 7, display: 'grid', placeItems: 'center', flexShrink: 0 }}>
          <Icon name="chevron.down" size={14} color={SUB} />
        </button>
      </div>
      {teamMenu && <TeamMenu demo={demo} onClose={() => setTeamMenu(false)} />}

      <button onClick={() => setJump(true)} className="h-bright"
        style={{ height: 32, borderRadius: 8, background: '#fff', border: `1px solid rgba(60,60,67,0.14)`, padding: '0 8px 0 10px', display: 'flex', alignItems: 'center', gap: 8, width: '100%' }}>
        <span style={{ flex: 1, fontSize: 13, color: SUB }}>Jump to a game or player</span>
        <Kbd>⌘K</Kbd>
      </button>
      {jump && <JumpPalette onClose={() => setJump(false)} />}

      <nav aria-label="Sections" style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
        {NAV.map(([id, label, icon]) => {
          const on = w.screen === id;
          return (
            <button key={id} onClick={() => w.go(id)} className={on ? '' : 'h-side'} aria-current={on ? 'page' : undefined}
              style={{ height: 32, padding: '0 10px', borderRadius: 7, display: 'flex', alignItems: 'center', gap: 10, background: on ? 'rgba(60,60,67,0.10)' : 'transparent', width: '100%' }}>
              <Icon name={icon} size={16} color={on ? C.blue : SUB} />
              <span style={{ fontSize: 14, fontWeight: 500 }}>{label}</span>
              <span className="num" style={{ marginLeft: 'auto', fontSize: 12, color: SUB }}>{meta(id)}</span>
            </button>
          );
        })}
      </nav>

      <div>
        <div style={{ fontSize: 11, fontWeight: 600, letterSpacing: '0.04em', textTransform: 'uppercase', color: SUB, padding: '0 10px 6px' }}>Upcoming</div>
        <button onClick={() => w.goStep(w.step)} className={w.screen === 'game' ? '' : 'h-side'}
          style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '7px 10px', borderRadius: 7, width: '100%', background: w.screen === 'game' ? '#fff' : 'transparent' }}>
          <span style={{ width: 8, height: 8, borderRadius: 4, flexShrink: 0, background: st.finalized ? C.green : !st.started ? C.gray2 : st.fpOk ? C.blue : C.red }} />
          <span style={{ minWidth: 0 }}>
            <span className="ellipsis" style={{ display: 'block', fontSize: 13, fontWeight: 500 }}>{gameTitle(w.lineup)}</span>
            <span style={{ display: 'block', fontSize: 12, color: SUB }}>{w.lineup.gameDate.toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' })}</span>
          </span>
        </button>
      </div>

      <div style={{ marginTop: 'auto', borderTop: `1px solid ${BORDER}`, paddingTop: 12, display: 'flex', alignItems: 'center', gap: 10, padding: '12px 6px 0' }}>
        <button className="h-side" onClick={() => setAccount((v) => !v)} aria-haspopup="menu" aria-expanded={account} title="Account"
          style={{ flex: 1, minWidth: 0, display: 'flex', alignItems: 'center', gap: 10, padding: 3, margin: -3, borderRadius: 8 }}>
          <span style={{ width: 28, height: 28, borderRadius: 14, background: C.gray5, fontSize: 11, fontWeight: 600, color: SUB, display: 'grid', placeItems: 'center', flexShrink: 0 }}>{initials}</span>
          <span className="ellipsis" style={{ flex: 1, fontSize: 13, fontWeight: 500, textAlign: 'left' }}>{w.team.coachName || 'Coach'}</span>
          <Icon name="chevron.up" size={12} color={SUB} />
        </button>
        <button className={w.screen === 'settings' ? '' : 'h-side'} title="Team settings" aria-label="Team settings"
          aria-current={w.screen === 'settings' ? 'page' : undefined} onClick={() => w.go('settings')}
          style={{ width: 28, height: 28, borderRadius: 7, display: 'grid', placeItems: 'center', background: w.screen === 'settings' ? 'rgba(60,60,67,0.10)' : 'transparent' }}>
          <Icon name="gearshape.fill" size={16} color={w.screen === 'settings' ? C.blue : SUB} />
        </button>
      </div>
      {account && <AccountMenu demo={demo} onClose={() => setAccount(false)} />}
    </aside>
  );
}

/** Opens from the coach in the sidebar footer: who's signed in, all teams, sign out. */
function AccountMenu({ demo, onClose }: { demo?: boolean; onClose(): void }) {
  const router = useRouter();
  const w = useWorkbench();
  const { session } = useAuth();
  const item: CSSProperties = { display: 'flex', alignItems: 'center', gap: 8, width: '100%', padding: '6px 9px', borderRadius: 6, fontSize: 14 };
  return (
    <>
      <div onClick={onClose} style={{ position: 'fixed', inset: 0, zIndex: 20 }} />
      <div role="menu" className="pop" style={{ position: 'absolute', bottom: 58, left: 10, right: 10, zIndex: 21, background: 'rgba(255,255,255,0.98)', borderRadius: 10, padding: 5, boxShadow: '0 10px 30px rgba(0,0,0,0.18), 0 0 0 0.5px rgba(0,0,0,0.14)' }}>
        <div style={{ padding: '6px 9px 4px' }}>
          <div style={{ fontSize: 12, fontWeight: 600, color: SUB }}>Signed in as</div>
          <div className="ellipsis" style={{ fontSize: 13 }}>{demo ? 'Demo team' : session?.user.email ?? ''}</div>
        </div>
        <div style={{ height: 0.5, background: C.sep, margin: '5px 9px' }} />
        <button role="menuitem" className="menu-item" style={item} onClick={() => { onClose(); w.leave(() => router.push('/')); }}>All teams</button>
        <button role="menuitem" className="menu-item" style={item} disabled={demo}
          onClick={() => { onClose(); w.leave(() => { void supabase.auth.signOut({ scope: 'local' }); }); }}>Sign out</button>
      </div>
    </>
  );
}

export function Kbd({ children }: { children: string }) {
  return <span style={{ fontSize: 11, fontFamily: 'ui-monospace, SFMono-Regular, Menlo, monospace', color: SUB, background: C.gray6, borderRadius: 4, padding: '2px 5px' }}>{children}</span>;
}

/** Not designed yet: a plain menu of the coach's teams, plus import. */
function TeamMenu({ demo, onClose }: { demo?: boolean; onClose(): void }) {
  const router = useRouter();
  const w = useWorkbench();
  const [teams, setTeams] = useState<TeamSummary[] | null>(null);
  useEffect(() => {
    if (demo) return;
    let live = true;
    listTeams().then((t) => { if (live) setTeams(t); }, () => { if (live) setTeams([]); });
    return () => { live = false; };
  }, [demo]);
  const go = (href: Parameters<typeof router.push>[0]) => { onClose(); w.leave(() => router.push(href)); };
  const item: CSSProperties = { display: 'flex', alignItems: 'center', gap: 8, width: '100%', padding: '6px 9px', borderRadius: 6, fontSize: 14 };
  return (
    <>
      <div onClick={onClose} style={{ position: 'fixed', inset: 0, zIndex: 20 }} />
      <div role="menu" className="pop" style={{ position: 'absolute', top: 54, left: 10, zIndex: 21, width: 260, background: 'rgba(255,255,255,0.98)', borderRadius: 10, padding: 5, boxShadow: '0 10px 30px rgba(0,0,0,0.18), 0 0 0 0.5px rgba(0,0,0,0.14)' }}>
        <div style={{ fontSize: 12, fontWeight: 600, color: SUB, padding: '6px 9px 4px' }}>Teams</div>
        {demo && <div style={{ fontSize: 14, color: SUB, padding: '6px 9px' }}>Demo team only</div>}
        {!demo && teams === null && <div style={{ fontSize: 14, color: SUB, padding: '6px 9px' }}>Loading…</div>}
        {teams?.map((t) => (
          <button key={t.id} role="menuitem" className="menu-item" style={item}
            onClick={() => (t.id === w.team.id ? onClose() : go({ pathname: '/team/[id]', params: { id: t.id } }))}>
            <span style={{ width: 10, height: 10, borderRadius: 5, background: `#${t.colorHex}`, flexShrink: 0 }} />
            <span className="ellipsis" style={{ flex: 1, fontWeight: t.id === w.team.id ? 600 : 400 }}>{t.name || 'Untitled team'}</span>
            <span style={{ fontSize: 12, opacity: 0.6 }}>{t.playerCount}</span>
          </button>
        ))}
        <div style={{ height: 0.5, background: C.sep, margin: '5px 9px' }} />
        <button role="menuitem" className="menu-item" style={item} onClick={() => { onClose(); w.go('settings'); }}>Team settings…</button>
        <button role="menuitem" className="menu-item" style={item} onClick={() => go('/')}>All teams</button>
        {!demo && <button role="menuitem" className="menu-item" style={item} onClick={() => go('/import')}>Import a team file…</button>}
        {!demo && (
          <>
            <div style={{ height: 0.5, background: C.sep, margin: '5px 9px' }} />
            <button role="menuitem" className="menu-item" style={item} onClick={() => { onClose(); w.leave(() => { void supabase.auth.signOut({ scope: 'local' }); }); }}>Sign out</button>
          </>
        )}
      </div>
    </>
  );
}

/**
 * Not designed yet: a minimal ⌘K palette. Type to find the game, a player
 * (opens their editor) or a page; ↑↓ and Enter pick.
 */
function JumpPalette({ onClose }: { onClose(): void }) {
  const w = useWorkbench();
  const [q, setQ] = useState('');
  const [sel, setSel] = useState(0);
  const ref = useRef<HTMLInputElement>(null);
  const items = useMemo(() => {
    const all: { key: string; label: string; meta: string; run(): void }[] = [
      { key: 'game', label: gameTitle(w.lineup), meta: 'Game', run: () => w.goStep(w.step) },
      { key: 'new-game', label: 'New game', meta: 'Action', run: () => w.leave(() => w.setNewGameOpen(true)) },
      { key: 'home', label: 'Home', meta: 'Page', run: () => w.go('home') },
      { key: 'roster', label: 'Roster', meta: 'Page', run: () => w.go('roster') },
      { key: 'stats', label: 'Season stats', meta: 'Page', run: () => w.go('stats') },
      { key: 'settings', label: 'Team settings', meta: 'Page', run: () => w.go('settings') },
      ...w.players.map((p) => ({
        key: p.id, label: `${p.firstName} ${p.lastName}`, meta: p.number ? `Player · #${p.number}` : 'Player',
        run: () => w.leave(() => { w.go('roster'); w.setPlayerModal({ id: p.id }); }),
      })),
    ];
    const t = q.trim().toLowerCase();
    return (t ? all.filter((i) => i.label.toLowerCase().includes(t)) : all).slice(0, 8);
  }, [q, w]);
  const pick = (i: number) => { const it = items[i]; if (!it) return; onClose(); it.run(); };
  return (
    <div onMouseDown={(e) => { if (e.target === e.currentTarget) onClose(); }}
      style={{ position: 'fixed', inset: 0, zIndex: 45, background: 'rgba(0,0,0,0.12)', display: 'flex', justifyContent: 'center', paddingTop: '14vh' }}>
      <div role="dialog" aria-label="Jump to" className="pop"
        style={{ width: 520, maxWidth: 'calc(100% - 32px)', alignSelf: 'flex-start', background: '#fff', borderRadius: 14, overflow: 'hidden', boxShadow: '0 12px 32px rgba(0,0,0,0.16), 0 0 0 0.5px rgba(0,0,0,0.12)' }}>
        <input ref={ref} autoFocus value={q} placeholder="Jump to a game or player" aria-label="Jump to"
          onChange={(e) => { setQ(e.target.value); setSel(0); }}
          onKeyDown={(e) => {
            if (e.key === 'Escape') { e.stopPropagation(); onClose(); }
            else if (e.key === 'ArrowDown') { e.preventDefault(); setSel((s) => Math.min(items.length - 1, s + 1)); }
            else if (e.key === 'ArrowUp') { e.preventDefault(); setSel((s) => Math.max(0, s - 1)); }
            else if (e.key === 'Enter') pick(sel);
          }}
          style={{ width: '100%', height: 48, border: 'none', borderBottom: `1px solid ${BORDER}`, padding: '0 16px', fontSize: 16, outline: 'none' }} />
        <div role="listbox" style={{ padding: 6 }}>
          {items.map((it, i) => (
            <button key={it.key} role="option" aria-selected={i === sel} onMouseEnter={() => setSel(i)} onClick={() => pick(i)}
              style={{ display: 'flex', alignItems: 'center', width: '100%', padding: '8px 10px', borderRadius: 8, background: i === sel ? 'rgba(0,122,255,0.08)' : 'transparent' }}>
              <span className="ellipsis" style={{ flex: 1, fontSize: 14 }}>{it.label}</span>
              <span style={{ fontSize: 12, color: SUB }}>{it.meta}</span>
            </button>
          ))}
          {items.length === 0 && <div style={{ padding: '10px', fontSize: 14, color: SUB }}>No matches</div>}
        </div>
      </div>
    </div>
  );
}

// MARK: - Shared page pieces

/** The 60px white header every page starts with. */
export function PageHeader({ children, right }: { children: ReactNode; right?: ReactNode }) {
  return (
    <header style={{ height: 60, flexShrink: 0, background: '#fff', borderBottom: `1px solid ${BORDER}`, padding: '0 24px', display: 'flex', alignItems: 'center', gap: 10 }}>
      {children}
      {right && <div style={{ marginLeft: 'auto', display: 'flex', alignItems: 'center', gap: 8 }}>{right}</div>}
    </header>
  );
}

export function SecondaryButton({ icon, iconColor, children, onClick, disabled, title, height = 32 }: {
  icon?: string; iconColor?: string; children: ReactNode; onClick?(): void; disabled?: boolean; title?: string; height?: number;
}) {
  return (
    <button className="h-sec" onClick={onClick} disabled={disabled} title={title}
      style={{ height, padding: '0 12px', borderRadius: 8, border: `1px solid ${BORDER2}`, fontSize: 13, fontWeight: 500, display: 'flex', alignItems: 'center', gap: 6, opacity: disabled ? 0.4 : 1, background: '#fff' }}>
      {icon && <Icon name={icon} size={14} color={iconColor ?? C.label} />}{children}
    </button>
  );
}

export function PrimaryButton({ icon, children, onClick, disabled, color = C.blue, height = 36, title }: {
  icon?: string; children: ReactNode; onClick?(): void; disabled?: boolean; color?: string; height?: number; title?: string;
}) {
  return (
    <button className="h-bright" onClick={onClick} disabled={disabled} title={title}
      style={{ height, padding: '0 16px', borderRadius: 8, background: color, color: '#fff', fontSize: 13, fontWeight: 600, display: 'flex', alignItems: 'center', gap: 6, opacity: disabled ? 0.5 : 1 }}>
      {icon && <Icon name={icon} size={14} color="#fff" />}{children}
    </button>
  );
}

export type PillKind = 'green' | 'red' | 'gray' | 'teal';
const PILL: Record<PillKind, [string, string]> = {
  green: ['rgba(52,199,89,0.16)', 'rgb(30,120,55)'],
  red: ['rgba(255,59,48,0.10)', C.red],
  gray: [C.gray6, 'rgba(60,60,67,0.8)'],
  teal: ['rgba(48,176,199,0.14)', 'rgb(20,110,128)'],
};
export function Pill({ kind, children }: { kind: PillKind; children: ReactNode }) {
  const [bg, fg] = PILL[kind];
  return <span style={{ fontSize: 12, fontWeight: 500, padding: '3px 9px', borderRadius: 999, background: bg, color: fg, whiteSpace: 'nowrap' }}>{children}</span>;
}

/** Fair play at a glance, on every game step. Chips jump to the inning. Hidden until the first position is set. */
export function FairPlayBox() {
  const w = useWorkbench();
  if (!gameStatus(w).started) return null;
  const ok = w.issues.length === 0;
  const red = w.issues.some((i) => i.severity === 'red');
  const [bg, border, color] = ok
    ? ['rgba(52,199,89,0.07)', 'rgba(52,199,89,0.25)', C.green]
    : red ? ['rgba(255,59,48,0.05)', 'rgba(255,59,48,0.2)', C.red] : ['rgba(255,149,0,0.07)', 'rgba(255,149,0,0.3)', C.orange];
  return (
    <div style={{ padding: '0 24px 12px', flexShrink: 0 }}>
      <div role="status" style={{ padding: '9px 14px', borderRadius: 10, background: bg, border: `1px solid ${border}`, display: 'flex', flexWrap: 'wrap', alignItems: 'center', gap: '6px 10px' }}>
        <Icon name={ok ? 'checkmark.shield.fill' : 'exclamationmark.triangle.fill'} size={16} color={color} />
        <span style={{ fontSize: 13, fontWeight: 600 }}>{ok ? 'Fair play OK' : `${w.issues.length} fair-play issue${w.issues.length === 1 ? '' : 's'}`}</span>
        {ok && <span style={{ fontSize: 13, color: SUB }}>Every player meets your fair play rules.</span>}
        {w.issues.map((i) => {
          const fg = i.severity === 'red' ? C.red : 'rgb(133,79,10)';
          return (
            <button key={i.key} className="h-bright" onClick={() => w.showInning(i.inning)} title={`Show inning ${i.inning + 1}`}
              style={{ fontSize: 12, fontWeight: 500, padding: '4px 10px', borderRadius: 999, background: '#fff', color: fg, boxShadow: `inset 0 0 0 1px ${i.severity === 'red' ? 'rgba(255,59,48,0.3)' : 'rgba(255,149,0,0.4)'}` }}>
              {i.title}: {i.detail}
            </button>
          );
        })}
      </div>
    </div>
  );
}

export function StepTitle({ title, hint, right }: { title: string; hint: string; right?: ReactNode }) {
  return (
    <div style={{ display: 'flex', alignItems: 'flex-end', gap: 16, marginBottom: 18 }}>
      <div style={{ flex: 1, minWidth: 0 }}>
        <h1 style={{ margin: 0, fontSize: 22, fontWeight: 700, letterSpacing: '-0.01em' }}>{title}</h1>
        <div style={{ fontSize: 14, color: SUB, marginTop: 4 }}>{hint}</div>
      </div>
      {right}
    </div>
  );
}
