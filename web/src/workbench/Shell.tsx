// The app frame from the design handoff: top bar, left sidebar (nav, batting
// order, absent players, legend), the main column, and the live fair-play
// panel. The page never scrolls; each column scrolls on its own.

import { useRouter } from 'expo-router';
import { useEffect, useRef, useState, type ReactNode } from 'react';

import { restoreAbsent, shortName } from '@/core/lineupOps';
import type { PositionPreferenceTier } from '@/core/model';
import { useTeam } from '@/data/teamStore';
import { listTeams, type TeamSummary } from '@/data/teams';

import { Icon } from './Icon';
import { playingTime } from './fairPlayIssues';
import { reorderTo, useWorkbench, type Screen } from './state';
import { C, TIER_RANK, TIER_STYLE } from './theme';

// MARK: - Top bar

export function TopBar({ demo }: { demo?: boolean }) {
  const w = useWorkbench();
  const { saving } = useTeam();
  const [teamMenu, setTeamMenu] = useState(false);
  const date = w.lineup.gameDate.toLocaleDateString('en-US', { month: 'long', day: 'numeric', year: 'numeric' });
  return (
    <header style={{ height: 52, flexShrink: 0, background: '#fff', borderBottom: C.hair, padding: '0 14px 0 20px', display: 'flex', alignItems: 'center', gap: 12, position: 'relative', zIndex: 5 }}>
      <button className="h-gray" onClick={() => setTeamMenu((v) => !v)} aria-haspopup="menu" aria-expanded={teamMenu}
        style={{ display: 'flex', alignItems: 'center', gap: 4, padding: '5px 8px', borderRadius: 8, color: C.blue, fontSize: 17, lineHeight: '22px', fontWeight: 600 }}>
        <span className="ellipsis" style={{ maxWidth: 320 }}>{w.team.name || 'Untitled team'}</span>
        <Icon name="chevron.down" size={14} color={C.blue} />
      </button>
      {teamMenu && <TeamMenu demo={demo} onClose={() => setTeamMenu(false)} />}
      <div style={{ width: 0.5, height: 20, background: C.sep }} />
      <span style={{ fontSize: 15, color: C.label2 }}>{date} · {w.lineup.innings.length} innings</span>
      <span style={{ fontSize: 13, color: C.label3, marginLeft: 8 }} aria-live="polite">{saving ? 'Saving…' : ''}</span>
      <div style={{ marginLeft: 'auto', display: 'flex', gap: 2 }}>
        <TopIcon name="calendar.badge.plus" title="Import schedule (coming soon)" />
        <TopIcon name="archivebox" title="Archive game (coming soon)" />
        <TopIcon name="gearshape.fill" title="Settings (coming soon)" />
      </div>
    </header>
  );
}

function TopIcon({ name, title, onClick }: { name: string; title: string; onClick?: () => void }) {
  return (
    <button className="h-gray" title={title} aria-label={title} onClick={onClick} disabled={!onClick}
      style={{ width: 34, height: 34, borderRadius: 8, display: 'grid', placeItems: 'center', opacity: onClick ? 1 : 0.4 }}>
      <Icon name={name} size={21} color={C.blue} />
    </button>
  );
}

/** Not designed yet: a plain menu of the coach's teams, plus import. */
function TeamMenu({ demo, onClose }: { demo?: boolean; onClose(): void }) {
  const router = useRouter();
  const w = useWorkbench();
  const [teams, setTeams] = useState<TeamSummary[] | null>(null);
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (demo) return;
    let live = true;
    listTeams().then((t) => { if (live) setTeams(t); }, () => { if (live) setTeams([]); });
    return () => { live = false; };
  }, [demo]);
  const go = (href: Parameters<typeof router.push>[0]) => { onClose(); router.push(href); };
  return (
    <>
      <div onClick={onClose} style={{ position: 'fixed', inset: 0, zIndex: 20 }} />
      <div ref={ref} role="menu" className="pop" style={{ position: 'absolute', top: 46, left: 14, zIndex: 21, width: 260, background: 'rgba(255,255,255,0.98)', borderRadius: 10, padding: 5, boxShadow: '0 10px 30px rgba(0,0,0,0.18), 0 0 0 0.5px rgba(0,0,0,0.14)' }}>
        <div style={{ fontSize: 12, fontWeight: 600, color: C.label2, padding: '6px 9px 4px' }}>Teams</div>
        {demo && <div style={{ fontSize: 14, color: C.label2, padding: '6px 9px' }}>Demo team only</div>}
        {!demo && teams === null && <div style={{ fontSize: 14, color: C.label2, padding: '6px 9px' }}>Loading…</div>}
        {teams?.map((t) => (
          <button key={t.id} role="menuitem" className="menu-item" onClick={() => (t.id === w.team.id ? onClose() : go({ pathname: '/team/[id]', params: { id: t.id } }))}
            style={{ display: 'flex', alignItems: 'center', gap: 8, width: '100%', padding: '6px 9px', borderRadius: 6, fontSize: 14 }}>
            <span style={{ width: 10, height: 10, borderRadius: 5, background: `#${t.colorHex}`, flexShrink: 0 }} />
            <span className="ellipsis" style={{ flex: 1, fontWeight: t.id === w.team.id ? 600 : 400 }}>{t.name || 'Untitled team'}</span>
            <span style={{ fontSize: 12, opacity: 0.6 }}>{t.playerCount}</span>
          </button>
        ))}
        <div style={{ height: 0.5, background: C.sep, margin: '5px 9px' }} />
        <button role="menuitem" className="menu-item" onClick={() => go('/')} style={{ display: 'block', width: '100%', padding: '6px 9px', borderRadius: 6, fontSize: 14 }}>All teams</button>
        {!demo && <button role="menuitem" className="menu-item" onClick={() => go('/import')} style={{ display: 'block', width: '100%', padding: '6px 9px', borderRadius: 6, fontSize: 14 }}>Import a team file…</button>}
      </div>
    </>
  );
}

// MARK: - Sidebar

const NAV: [Screen, string, string][] = [
  ['players', 'Players', 'person.3.fill'],
  ['lineup', 'Lineup', 'list.number'],
  ['positions', 'Positions', 'baseball.diamond.bases'],
  ['history', 'History', 'clock.arrow.circlepath'],
];

export function Sidebar() {
  const w = useWorkbench();
  const absent = w.players.filter((p) => w.lineup.absentPlayerIDs.includes(p.id));
  const meta = (s: Screen) =>
    s === 'players' ? String(w.active.length) : s === 'positions' && w.issues.length ? String(w.issues.length) : '';
  return (
    <aside style={{ width: 248, flexShrink: 0, background: C.grouped, borderRight: C.hair, display: 'flex', flexDirection: 'column', minHeight: 0 }}>
      <nav style={{ padding: '12px 10px 6px', display: 'flex', flexDirection: 'column', gap: 2 }} aria-label="Sections">
        {NAV.map(([id, label, icon]) => {
          const on = w.screen === id;
          return (
            <button key={id} onClick={() => w.go(id)} className={on ? '' : 'h-nav'} aria-current={on ? 'page' : undefined}
              style={{ height: 34, padding: '0 10px', borderRadius: 8, display: 'flex', alignItems: 'center', gap: 10, background: on ? 'rgba(0,122,255,0.12)' : 'transparent' }}>
              <Icon name={icon} size={18} color={on ? C.blue : C.label2} />
              <span style={{ fontSize: 15, fontWeight: on ? 600 : 400, color: on ? C.blue : C.label }}>{label}</span>
              <span className="num" style={{ marginLeft: 'auto', fontSize: 12, color: C.label3 }}>{meta(id)}</span>
            </button>
          );
        })}
      </nav>
      <div style={{ height: 0.5, background: C.sep, margin: '6px 16px 0' }} />
      <div style={{ padding: '14px 16px 6px 20px', display: 'flex', alignItems: 'center', gap: 8 }}>
        <span style={{ fontSize: 17, fontWeight: 600 }}>Roster</span>
        <span style={{ marginLeft: 'auto', fontSize: 13, color: C.label2 }}>{w.active.length} active</span>
        <button className="h-link" title="Add player" aria-label="Add player" onClick={() => { w.go('players'); w.setPlayerModal({ id: 'new' }); }}>
          <Icon name="plus.circle.fill" size={24} color={C.blue} />
        </button>
      </div>
      <div style={{ flex: 1, overflowY: 'auto', padding: '4px 12px 20px' }}>
        <div style={{ display: 'flex', alignItems: 'baseline', padding: '8px 8px 6px' }}>
          <span style={{ fontSize: 12, fontWeight: 500, letterSpacing: 0.4, textTransform: 'uppercase', color: C.label2 }}>Batting order</span>
          <span style={{ marginLeft: 'auto', fontSize: 11, color: C.label3 }}>Drag to reorder</span>
        </div>
        {w.active.length > 0 ? (
          <div style={{ background: '#fff', borderRadius: 12, overflow: 'hidden' }}>
            {w.active.map((p, i) => <OrderRow key={p.id} pid={p.id} index={i} />)}
          </div>
        ) : (
          <HelpCard>No active players. Add players on the Players screen.</HelpCard>
        )}

        <div style={{ fontSize: 15, fontWeight: 600, color: C.label2, padding: '18px 8px 8px' }}>Absent</div>
        {absent.length === 0 ? (
          <HelpCard>Right-click a player or use the Lineup tab to mark them absent.</HelpCard>
        ) : (
          <div style={{ background: '#fff', borderRadius: 12, overflow: 'hidden' }}>
            {absent.map((p) => (
              <div key={p.id} style={{ height: 38, display: 'flex', alignItems: 'center', gap: 8, padding: '0 10px', boxShadow: `inset 0 -0.5px 0 ${C.sep}` }}>
                <Icon name="minus.circle.fill" size={18} color={C.gray2} />
                <span className="ellipsis" style={{ fontSize: 15, color: C.label2, textDecoration: 'line-through', flex: 1 }}>{shortName(p)}</span>
                <button className="h-link" style={{ color: C.blue, fontSize: 15 }} onClick={() => w.edit((l) => restoreAbsent(l, p.id))}>Restore</button>
              </div>
            ))}
          </div>
        )}

        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', rowGap: 4, padding: '16px 8px 0', fontSize: 11, color: C.label2 }}>
          {(['Strength', 'Capable', 'Emergency', 'Never'] as PositionPreferenceTier[]).map((t) => (
            <span key={t}><b style={{ color: TIER_STYLE[t].fg, marginRight: 4 }}>{TIER_STYLE[t].letter}</b>{t}</span>
          ))}
        </div>
      </div>
    </aside>
  );
}

function HelpCard({ children }: { children: ReactNode }) {
  return <div style={{ background: '#fff', borderRadius: 12, padding: '12px 14px', fontSize: 13, lineHeight: '18px', color: C.label2 }}>{children}</div>;
}

function OrderRow({ pid, index }: { pid: string; index: number }) {
  const w = useWorkbench();
  const p = w.byId.get(pid)!;
  const key = `o-${pid}`;
  const isOrderDrag = w.dragging?.from === 'order';
  const tags = Object.entries(p.positionPreferences)
    .filter(([pos, t]) => t && t !== 'Emergency' && w.positions.includes(pos as never))
    .sort((a, b) => TIER_RANK[a[1]!] - TIER_RANK[b[1]!])
    .slice(0, 3);
  return (
    <div {...w.dragProps(pid, 'order')}
      {...w.dropProps(key, (src) => w.edit((l) => reorderTo(l, w.active, src.pid, pid)), (src) => src.from === 'order')}
      onContextMenu={(e) => { e.preventDefault(); }}
      className="h-row"
      style={{
        height: 40, padding: '0 10px 0 8px', display: 'flex', alignItems: 'center', gap: 8,
        boxShadow: w.dropKey === key && isOrderDrag ? `inset 0 2px 0 ${C.blue}` : `inset 0 -0.5px 0 ${C.sep}`,
        opacity: w.dragging?.pid === pid && isOrderDrag ? 0.4 : 1,
      }}>
      <span className="num" style={{ width: 18, textAlign: 'right', fontSize: 14, color: C.label2 }}>{index + 1}</span>
      <span className="ellipsis" style={{ fontSize: 15, flex: 1, minWidth: 0 }}>{shortName(p)}</span>
      <span style={{ display: 'flex', gap: 3, flexShrink: 0 }}>
        {tags.map(([pos, t]) => (
          <span key={pos} style={{ fontSize: 10, fontWeight: 700, padding: '3px 4px', borderRadius: 4, background: TIER_STYLE[t!].bg, color: TIER_STYLE[t!].fg }}>{pos}</span>
        ))}
      </span>
      <Grip />
    </div>
  );
}

export function Grip() {
  return (
    <span aria-hidden style={{ display: 'flex', flexDirection: 'column', gap: 3, flexShrink: 0 }}>
      {[0, 1, 2].map((i) => <span key={i} style={{ width: 14, height: 1.5, background: C.gray3, borderRadius: 1 }} />)}
    </span>
  );
}

// MARK: - Fair play panel

export function FairPlayPanel() {
  const w = useWorkbench();
  const inningCount = w.lineup.innings.length;
  const clear = w.issues.length === 0;
  const red = w.issues.some((i) => i.severity === 'red');
  const color = clear ? C.green : red ? C.red : C.orange;
  const bg = clear ? 'rgba(52,199,89,0.12)' : red ? 'rgba(255,59,48,0.09)' : 'rgba(255,149,0,0.12)';
  return (
    <aside style={{ width: 288, flexShrink: 0, background: '#fff', borderLeft: C.hair, padding: '18px 20px 24px', overflowY: 'auto' }} aria-label="Fair play">
      <div style={{ fontSize: 22, fontWeight: 700, lineHeight: '28px' }}>Fair play</div>
      <div style={{ fontSize: 14, color: C.label2, marginTop: 2 }}>Live as you build the lineup</div>
      <div role="status" style={{ marginTop: 14, padding: '10px 12px', borderRadius: 10, background: bg, display: 'flex', alignItems: 'center', gap: 8 }}>
        <Icon name={clear ? 'checkmark.shield.fill' : 'exclamationmark.triangle.fill'} size={17} color={color} />
        <span style={{ fontSize: 16, fontWeight: 600, color }}>
          {clear ? 'Fair play: all clear' : `${w.issues.length} fair-play issue${w.issues.length > 1 ? 's' : ''}`}
        </span>
      </div>
      {clear && w.active.length > 0 && (
        <div style={{ marginTop: 10, padding: '10px 12px', borderRadius: 10, background: 'rgba(52,199,89,0.08)', fontSize: 13, lineHeight: '18px', color: C.label2 }}>
          Every player meets your fair play rules.
        </div>
      )}
      {w.issues.map((i) => {
        const c = i.severity === 'red' ? C.red : C.orange;
        return (
          <button key={i.key} className="issue h-dim" onClick={() => w.showInning(i.inning)} title={`Show inning ${i.inning + 1}`}
            style={{ display: 'block', width: '100%', marginTop: 10, padding: '10px 12px', borderRadius: 10, background: i.severity === 'red' ? 'rgba(255,59,48,0.07)' : 'rgba(255,149,0,0.10)' }}>
            <span style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
              <Icon name="exclamationmark.triangle.fill" size={15} color={c} />
              <span style={{ fontSize: 15, fontWeight: 600 }}>{i.title}</span>
            </span>
            <span style={{ display: 'block', paddingLeft: 23, marginTop: 2, fontSize: 13, lineHeight: '18px', color: C.label2 }}>{i.detail}</span>
          </button>
        );
      })}
      <div style={{ height: 0.5, background: C.sep, margin: '18px 0 12px' }} />
      <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
        <span style={{ fontSize: 13, fontWeight: 500, letterSpacing: 0.6, color: C.label2, textTransform: 'uppercase' }}>Playing time</span>
        <span style={{ marginLeft: 'auto', display: 'flex', gap: 8, fontSize: 12, color: C.label2 }}>
          <Legend color={C.blue}>Infield</Legend><Legend color={C.green}>Outfield</Legend>
        </span>
      </div>
      {w.active.map((p) => {
        const t = playingTime(w.lineup, p);
        return (
          <div key={p.id} title={`${t.infield} infield, ${t.outfield} outfield`}
            style={{ height: 36, display: 'grid', gridTemplateColumns: '64px 1fr 30px', gap: 10, alignItems: 'center', boxShadow: `inset 0 -0.5px 0 ${C.sep}` }}>
            <span className="ellipsis" style={{ fontSize: 15 }}>{w.nameOf(p)}</span>
            <span style={{ height: 10, borderRadius: 5, background: C.gray5, display: 'flex', overflow: 'hidden' }}>
              <span className="pt-bar" style={{ width: `${(t.infield / inningCount) * 100}%`, background: C.blue }} />
              <span className="pt-bar" style={{ width: `${(t.outfield / inningCount) * 100}%`, background: C.green }} />
            </span>
            <span className="num" style={{ fontSize: 14, fontWeight: 600, color: C.label2, textAlign: 'right' }}>
              {t.infield + t.outfield}<span style={{ color: C.label3 }}>/{inningCount}</span>
            </span>
          </div>
        );
      })}
    </aside>
  );
}

function Legend({ color, children }: { color: string; children: ReactNode }) {
  return <span style={{ display: 'flex', alignItems: 'center', gap: 4 }}><span style={{ width: 8, height: 8, borderRadius: 2, background: color }} />{children}</span>;
}
