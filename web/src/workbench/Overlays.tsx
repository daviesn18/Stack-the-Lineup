// The position picker popover (click a spot), the right-click menu, and the
// undo toast. Only one overlay is open at a time; a transparent scrim catches
// clicks and right-clicks outside it.

import { useState } from 'react';

import { keepForRemaining, toggleAbsent } from '@/core/lineupOps';
import { isInfield, isNonFielding, POSITION_NAMES, type Player } from '@/core/model';

import { useGate } from './pro';
import { useWorkbench } from './state';
import { badgeColor, C, playerAvatar, TIER_RANK, TIER_STYLE, tint } from './theme';

export function Overlays() {
  const w = useWorkbench();
  return (
    <>
      {(w.picker || w.menu) && (
        <div onClick={w.closeOverlays} onContextMenu={(e) => { e.preventDefault(); w.closeOverlays(); }}
          style={{ position: 'fixed', inset: 0, zIndex: 30 }} />
      )}
      {w.picker && <Picker />}
      {w.menu && <ContextMenu />}
      {w.toast && <Toast />}
    </>
  );
}

const initials = (p: Player) => `${p.firstName.charAt(0)}${p.lastName.charAt(0)}`.toUpperCase();

/**
 * Quick Set's "Apply to innings" (QuickSetSheet): which innings a pick applies
 * to. Starts with the inning that was clicked.
 */
function InningChips({ inning, selected, onChange }: { inning: number; selected: number[]; onChange(next: number[]): void }) {
  const w = useWorkbench();
  const count = w.lineup.innings.length;
  const all = Array.from({ length: count }, (_, i) => i);
  const toggle = (i: number) => {
    const next = selected.includes(i) ? selected.filter((x) => x !== i) : [...selected, i].sort((a, b) => a - b);
    onChange(next.length ? next : [inning]);
  };
  const chip = (on: boolean) => ({
    minWidth: 26, height: 24, borderRadius: 6, fontSize: 12, fontWeight: 600, padding: '0 6px',
    background: on ? C.blue : C.gray6, color: on ? '#fff' : C.label2,
  } as const);
  return (
    <div role="group" aria-label="Apply to innings" style={{ display: 'flex', alignItems: 'center', gap: 4, flexWrap: 'wrap' }}>
      <span style={{ fontSize: 11, color: C.label2, marginRight: 4 }}>Innings</span>
      {all.map((i) => (
        <button key={i} type="button" aria-pressed={selected.includes(i)} onClick={() => toggle(i)} style={chip(selected.includes(i))}>{i + 1}</button>
      ))}
      <button type="button" className="h-link" onClick={() => onChange(selected.length === count ? [inning] : all)}
        style={{ marginLeft: 'auto', fontSize: 12, color: C.blue }}>
        {selected.length === count ? 'Just this one' : 'All'}
      </button>
    </div>
  );
}

function Picker() {
  const w = useWorkbench();
  const pk = w.picker!;
  const [query, setQuery] = useState('');
  const [innings, setInnings] = useState<number[]>([pk.inning]);
  const pick = (pid: string, via: 'picker' | 'key') => w.placeMany(pid, innings, pk.pos, via);
  // Bench and ABS hold any number of players, so there's no one to swap with.
  const shared = isNonFielding(pk.pos);
  const current = shared ? undefined : w.holder(pk.inning, pk.pos);
  const q = query.trim().toLowerCase();
  // Preference hints are Pro (iOS shows no tier badges to a free coach).
  const prefsOn = useGate('player_preferences').open;
  const rows = w.active
    .filter((p) => !q || `${p.firstName} ${p.lastName}`.toLowerCase().includes(q))
    .map((p) => {
      const tier = prefsOn ? p.positionPreferences[pk.pos] : undefined;
      const now = w.posOf(p.id, pk.inning);
      const benched = now === undefined || now === 'Bench';
      return { p, tier, now, rank: TIER_RANK[tier ?? 'none'] * 10 + (benched ? 0 : 1) + (p.id === current?.id ? 100 : 0) };
    })
    .sort((a, b) => a.rank - b.rank);

  return (
    <div role="dialog" aria-label={`${POSITION_NAMES[pk.pos]}, inning ${pk.inning + 1}`} className="pop"
      style={{ position: 'fixed', left: pk.x, top: pk.y, width: 320, zIndex: 31, background: '#fff', borderRadius: 14, boxShadow: '0 12px 32px rgba(0,0,0,0.16), 0 0 0 0.5px rgba(0,0,0,0.12)', overflow: 'hidden' }}>
      <div style={{ padding: '12px 14px 10px', display: 'flex', alignItems: 'center', gap: 10 }}>
        <span style={{ minWidth: 32, fontSize: 13, fontWeight: 700, color: '#fff', padding: '6px 4px', borderRadius: 6, background: badgeColor(pk.pos), textAlign: 'center' }}>{pk.pos}</span>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ fontSize: 15, fontWeight: 600 }}>{POSITION_NAMES[pk.pos]} · Inning {pk.inning + 1}</div>
          <div className="ellipsis" style={{ fontSize: 12, color: C.label2 }}>
            {pk.pos === 'ABS' ? 'Late arrival or early departure' : current ? `Currently ${current.firstName} ${current.lastName}` : 'Open position'}
          </div>
        </div>
        <span style={{ fontSize: 11, fontFamily: 'ui-monospace, SFMono-Regular, Menlo, monospace', color: C.label2, background: C.gray6, borderRadius: 4, padding: '2px 5px' }}>esc</span>
      </div>
      <div style={{ padding: '0 12px 10px' }}>
        <input autoFocus value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Type a name" aria-label="Search players"
          onKeyDown={(e) => { if (e.key === 'Enter' && rows[0]) pick(rows[0].p.id, 'key'); }}
          style={{ width: '100%', height: 32, background: C.gray6, borderRadius: 8, border: 'none', outline: 'none', padding: '0 10px', fontSize: 15 }} />
      </div>
      <div style={{ padding: '0 14px 10px' }}>
        <InningChips inning={pk.inning} selected={innings} onChange={setInnings} />
      </div>
      <div style={{ maxHeight: 330, overflowY: 'auto', borderTop: C.hair }}>
        {rows.filter(({ now }) => !(shared && now === pk.pos)).map(({ p, tier, now }) => {
          const av = playerAvatar(p);
          const prev = pk.inning > 0 ? `Inn ${pk.inning}: ${w.posOf(p.id, pk.inning - 1) ?? '—'}` : p.number ? `#${p.number}` : '';
          return (
            <button key={p.id} className="pick-row" onClick={() => pick(p.id, 'picker')}
              style={{ display: 'flex', alignItems: 'center', gap: 10, width: '100%', padding: '8px 14px', opacity: tier === 'Never' ? 0.45 : 1, background: p.id === current?.id ? 'rgba(0,122,255,0.06)' : 'transparent' }}>
              <span style={{ width: 28, height: 28, borderRadius: 14, background: av.bg, color: av.fg, fontSize: 11, fontWeight: 600, display: 'grid', placeItems: 'center', flexShrink: 0 }}>{initials(p)}</span>
              <span style={{ flex: 1, minWidth: 0 }}>
                <span className="ellipsis" style={{ display: 'block', fontSize: 15 }}>{p.firstName} {p.lastName}</span>
                <span style={{ display: 'block', fontSize: 11, color: C.label2 }}>{prev}</span>
              </span>
              {tier && <span style={{ fontSize: 11, fontWeight: 600, borderRadius: 999, padding: '2px 8px', background: TIER_STYLE[tier].bg, color: TIER_STYLE[tier].fg }}>{tier}</span>}
              <span style={{ minWidth: 40, fontSize: 11, fontWeight: 700, textAlign: 'center', borderRadius: 5, padding: '4px 4px',
                background: now && now !== 'Bench' ? badgeColor(now) : C.gray5, color: now && now !== 'Bench' ? '#fff' : C.label2 }}>
                {now ?? '—'}
              </span>
            </button>
          );
        })}
        {rows.length === 0 && <div style={{ padding: '12px 14px', fontSize: 14, color: C.label2 }}>No one matches.</div>}
      </div>
      <div style={{ borderTop: C.hair, padding: '8px 14px', fontSize: 11, color: C.label2 }}>
        {pk.pos === 'ABS'
          ? 'Absent this inning only. Their spot opens up, and Auto-Fill leaves them out.'
          : innings.length > 1
            ? `Puts them at ${pk.pos} in ${innings.length} innings, swapping with whoever is there.`
            : `Picking a player swaps them with whoever is currently at ${pk.pos}.`}
      </div>
    </div>
  );
}

function ContextMenu() {
  const w = useWorkbench();
  const m = w.menu!;
  const [innings, setInnings] = useState<number[]>([m.inning]);
  const prefsOn = useGate('player_preferences').open;
  const p = w.byId.get(m.pid);
  if (!p) return null;
  const now = w.posOf(p.id, m.inning);
  const item = { display: 'flex', width: '100%', padding: '6px 9px', borderRadius: 6, fontSize: 14 } as const;
  return (
    <div role="menu" aria-label={`${p.firstName} ${p.lastName}, inning ${m.inning + 1}`} className="pop"
      style={{ position: 'fixed', left: m.x, top: m.y, width: 264, zIndex: 31, background: 'rgba(255,255,255,0.98)', borderRadius: 10, padding: 5, boxShadow: '0 10px 30px rgba(0,0,0,0.18), 0 0 0 0.5px rgba(0,0,0,0.14)' }}>
      <div style={{ fontSize: 12, fontWeight: 600, color: C.label2, padding: '5px 9px 6px' }}>{p.firstName} {p.lastName} · Inning {m.inning + 1}</div>
      <div style={{ padding: '0 9px 8px' }}>
        <InningChips inning={m.inning} selected={innings} onChange={setInnings} />
      </div>
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(5, 1fr)', gap: 4, padding: '0 4px 6px' }}>
        {w.positions.map((pos) => {
          const never = prefsOn && p.positionPreferences[pos] === 'Never';
          return (
            <button key={pos} className="menu-tile" onClick={() => w.placeMany(p.id, innings, pos, 'menu')} title={never ? `${p.firstName} is marked Never at ${pos}` : undefined}
              style={{ fontSize: 12, fontWeight: 700, borderRadius: 6, padding: '6px 0', textAlign: 'center',
                background: never ? C.gray5 : tint(pos), color: never ? C.label3 : isInfield(pos) ? TIER_STYLE.Capable.fg : TIER_STYLE.Strength.fg,
                boxShadow: now === pos ? `inset 0 0 0 2px ${C.blue}` : 'none' }}>
              {pos}
            </button>
          );
        })}
      </div>
      <div style={{ height: 0.5, background: C.sep, margin: '2px 9px 4px' }} />
      <button role="menuitem" className="menu-item" style={item} onClick={() => w.placeMany(p.id, innings, 'Bench', 'menu')}>
        Move to bench<span style={{ marginLeft: 'auto', opacity: 0.6 }}>B</span>
      </button>
      <button role="menuitem" className="menu-item" style={item} disabled={m.inning === w.lineup.innings.length - 1}
        onClick={() => { w.closeOverlays(); w.edit((l) => keepForRemaining(l, p.id, m.inning)); }}>
        Keep here for remaining innings
      </button>
      <button role="menuitem" className="menu-item" style={item} onClick={() => w.place(p.id, m.inning, null, 'menu')}>Unassign this inning</button>
      <div style={{ height: 0.5, background: C.sep, margin: '4px 9px' }} />
      {now === 'ABS'
        ? (
          <button role="menuitem" className="menu-item" style={item} onClick={() => w.place(p.id, m.inning, 'Bench', 'menu')}>
            Here this inning (to bench)
          </button>
        ) : (
          <button role="menuitem" className="menu-item" style={item} onClick={() => w.place(p.id, m.inning, 'ABS', 'menu')}
            title="Late arrival or early departure">
            Absent this inning<span style={{ marginLeft: 'auto', opacity: 0.6 }}>A</span>
          </button>
        )}
      <button role="menuitem" className="menu-item danger" style={{ ...item, color: C.red }}
        onClick={() => { w.closeOverlays(); w.edit((l) => toggleAbsent(l, p.id), `${p.firstName} marked absent`); }}>
        Absent all game
      </button>
    </div>
  );
}

function Toast() {
  const w = useWorkbench();
  const t = w.toast!;
  return (
    <div key={t.id} role="status" className="toast"
      style={{ position: 'fixed', left: '50%', bottom: 84, transform: 'translateX(-50%)', zIndex: 50, background: '#000', color: '#fff', borderRadius: 999, padding: '10px 18px', fontSize: 14, fontWeight: 500, display: 'flex', gap: 16, alignItems: 'center', boxShadow: '0 8px 24px rgba(0,0,0,0.2)', whiteSpace: 'nowrap' }}>
      {t.text}
      {t.before && <button onClick={w.undo} style={{ color: C.yellow, fontWeight: 600 }}>Undo</button>}
    </div>
  );
}
