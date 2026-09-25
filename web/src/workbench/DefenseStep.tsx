// Game › Defense: the Field view (one inning on a diamond), the By Position
// grid (every inning), and Pitching, with a right rail of bench and playing
// time. Click a spot to pick, drag to swap, right-click for more.

import { type CSSProperties } from 'react';

import { openPositions } from '@/core/fairPlay';
import { clearPositions, shortName } from '@/core/lineupOps';
import { isInfield, isOutfield, POSITION_NAMES, type FieldPosition, type Player } from '@/core/model';
import { status as pitchStatus } from '@/core/pitching';
import { statusLabel } from '@/print/lineupPdf';

import { Icon } from './Icon';
import { playingTime } from './fairPlayIssues';
import { BORDER, FILL, StepTitle, SUB } from './Shell';
import { useWorkbench, type DefView } from './state';
import { badgeColor, C, tint } from './theme';

export function DefenseStep() {
  const w = useWorkbench();
  const n = w.lineup.innings.length;
  const hint = {
    field: `Click a position to pick a player. Drag to swap. Right-click for more. Keys 1-${Math.min(9, n)} switch innings.`,
    grid: 'Click a cell to pick a player. Drag names to swap or onto the bench. Right-click for more.',
    pitching: 'Who is pitching and who is ineligible.',
  }[w.defView];
  return (
    <>
      <StepTitle title="Set the defense" hint={hint} right={<ViewSwitch />} />
      <AutoFillExtras />
      <div style={{ display: 'flex', gap: 20, alignItems: 'flex-start' }}>
        <div style={{ flex: 1, minWidth: 0 }}>
          {w.defView === 'field' && <FieldView />}
          {w.defView === 'grid' && <GridView />}
          {w.defView === 'pitching' && <Pitching />}
        </div>
        {w.defView !== 'pitching' && (
          <div style={{ width: 220, flexShrink: 0, display: 'flex', flexDirection: 'column', gap: 12 }}>
            {w.defView === 'field' && <BenchBox />}
            <Totals />
          </div>
        )}
      </div>
    </>
  );
}

function ViewSwitch() {
  const w = useWorkbench();
  const opts: [DefView, string][] = [['field', 'Field'], ['grid', 'By Position'], ['pitching', 'Pitching']];
  return (
    <div role="tablist" style={{ display: 'flex', padding: 2, background: C.gray6, borderRadius: 8, height: 28, flexShrink: 0 }}>
      {opts.map(([id, label]) => {
        const on = w.defView === id;
        return (
          <button key={id} role="tab" aria-selected={on} onClick={() => w.setDefView(id)}
            style={{ padding: '0 12px', borderRadius: 6, fontSize: 13, fontWeight: on ? 600 : 500, background: on ? '#fff' : 'transparent', boxShadow: on ? '0 1px 2px rgba(0,0,0,0.08)' : 'none' }}>
            {label}
          </button>
        );
      })}
    </div>
  );
}

/** Instructions for Auto-Fill, its notes, and Clear. Auto-Fill itself is in the page header. */
function AutoFillExtras() {
  const w = useWorkbench();
  const notes = w.fillNotes;
  return (
    <div style={{ marginTop: -8, marginBottom: 14 }}>
      <div style={{ display: 'flex', gap: 16, fontSize: 13 }}>
        <details style={{ flex: 1 }}>
          <summary style={{ color: C.blue, cursor: 'pointer', width: 'fit-content' }}>{w.prompt.trim() ? 'Auto-Fill instructions (set)' : 'Auto-Fill instructions'}</summary>
          <div style={{ marginTop: 8, borderRadius: 10, border: `1px solid ${BORDER}`, padding: '8px 10px', maxWidth: 560 }}>
            <textarea value={w.prompt} onChange={(e) => w.setPrompt(e.target.value)} rows={3} aria-label="Auto-Fill instructions"
              placeholder={"Optional, one per line:\nJake pitches innings 1 to 2\ndon't have Connor catch"}
              style={{ width: '100%', border: 'none', outline: 'none', resize: 'vertical', fontSize: 14, lineHeight: '19px', background: 'transparent' }} />
            <div style={{ fontSize: 12, color: SUB }}>Auto-Fill follows these, fills open spots only, and keeps anything you&apos;ve set.</div>
          </div>
        </details>
        <button className="h-link" onClick={() => w.edit((l) => clearPositions(l), 'All positions cleared')}
          style={{ alignSelf: 'flex-start', color: C.red, fontSize: 13 }}>Clear positions</button>
      </div>
      {notes && (
        <div role="status" style={{ marginTop: 10, display: 'flex', flexDirection: 'column', gap: 8 }}>
          {notes.incompleteMessage && <Note color={C.orange} bg="rgba(255,149,0,0.10)" onClose={w.clearFillNotes}>{notes.incompleteMessage}</Note>}
          {notes.noticeMessage && <Note color={C.blue} bg="rgba(0,122,255,0.07)" onClose={w.clearFillNotes}>{notes.noticeMessage}</Note>}
        </div>
      )}
    </div>
  );
}

function Note({ color, bg, children, onClose }: { color: string; bg: string; children: string; onClose(): void }) {
  return (
    <div style={{ background: bg, borderRadius: 10, padding: '10px 12px', display: 'flex', gap: 8, alignItems: 'flex-start' }}>
      <Icon name="exclamationmark.triangle.fill" size={15} color={color} style={{ marginTop: 2 }} />
      <span style={{ flex: 1, fontSize: 13, lineHeight: '18px', whiteSpace: 'pre-line' }}>{children}</span>
      <button className="h-link" onClick={onClose} style={{ fontSize: 13, color: C.blue }}>Dismiss</button>
    </div>
  );
}

// MARK: - Shared spot logic

/** Innings in a back-to-back bench, by player: paints their bench chips and BN red. */
function useBackToBack() {
  const w = useWorkbench();
  const m = new Map<string, Set<number>>();
  for (const i of w.issues) if (i.pid && i.cells) m.set(i.pid, new Set(i.cells));
  return m;
}

type InningState = 'done' | 'partial' | 'empty';

/**
 * How filled an inning is. Fair-play problems aren't shown here: a bench-heavy
 * player can touch every inning, which would hide every check. They show on
 * the bench chips, the BN column and the fair-play box instead.
 */
function useInningState() {
  const w = useWorkbench();
  return (i: number): InningState => {
    const open = openPositions(w.lineup, i, w.players, w.team.fairPlayConfig).length;
    return open === 0 && w.active.length > 0 ? 'done' : open === w.positions.length ? 'empty' : 'partial';
  };
}

/** A check when every spot in the inning is filled; otherwise a dot (orange partial, gray empty). */
function InningMark({ state, onBlue }: { state: InningState; onBlue?: boolean }) {
  if (state === 'done') {
    return onBlue
      ? <Icon name="checkmark" size={14} color="#fff" style={{ strokeWidth: 3 }} />
      : <Icon name="checkmark.circle.fill" size={14} color={C.green} />;
  }
  const color = onBlue ? 'rgba(255,255,255,0.85)' : state === 'partial' ? C.orange : C.gray3;
  return <span style={{ width: 6, height: 6, borderRadius: 3, background: color }} />;
}

/** A field spot in one inning: click for the picker, right-click for the menu, drag to swap. */
function useSpot(inning: number, pos: FieldPosition, key: string) {
  const w = useWorkbench();
  const p = w.holder(inning, pos);
  return {
    p,
    never: !!p && p.positionPreferences[pos] === 'Never',
    ring: w.dropKey === key ? `inset 0 0 0 2px ${C.blue}` : undefined,
    handlers: {
      onClick: (e: { currentTarget: Element }) => w.openPicker(e.currentTarget, inning, pos),
      onContextMenu: (e: { clientX: number; clientY: number; preventDefault(): void }) => w.openMenu(e, p?.id, inning),
      ...w.dragProps(p?.id, 'cell'),
      ...w.dropProps(key, (src) => w.place(src.pid, inning, pos)),
    },
  };
}

/** Active players on Bench (or with no spot) in an inning. */
function benched(w: ReturnType<typeof useWorkbench>, inning: number): Player[] {
  return w.active.filter((p) => { const x = w.posOf(p.id, inning); return x === undefined || x === 'Bench'; });
}

function BenchChip({ p, inning, size }: { p: Player; inning: number; size: 'lg' | 'sm' }) {
  const w = useWorkbench();
  const b2b = useBackToBack().get(p.id)?.has(inning);
  const unassigned = w.posOf(p.id, inning) === undefined;
  const border = b2b ? `1.5px solid ${C.red}` : unassigned ? `1px dashed ${C.gray2}` : '1px solid rgba(60,60,67,0.14)';
  return (
    <span {...w.dragProps(p.id, 'cell')} onContextMenu={(e) => w.openMenu(e, p.id, inning)}
      title={b2b ? `${p.firstName} sits back to back` : unassigned ? `${p.firstName} has no spot yet this inning` : undefined}
      className="ellipsis"
      style={size === 'lg'
        ? { fontSize: 15, fontWeight: 500, background: '#fff', borderRadius: 999, padding: '5px 14px', border }
        : { fontSize: 13, background: '#fff', borderRadius: 6, padding: '4px 6px', textAlign: 'center', border }}>
      {w.nameOf(p)}
    </span>
  );
}

// MARK: - Field view

const FIELD_XY: Partial<Record<FieldPosition, [number, number]>> = {
  CF: [280, 50], LF: [100, 118], RF: [460, 118], LCF: [188, 70], RCF: [372, 70],
  SS: [196, 204], '2B': [364, 204], '3B': [122, 300], '1B': [438, 300], P: [280, 282], C: [280, 392],
};
const SCALE = 0.92;

function FieldView() {
  const w = useWorkbench();
  const state = useInningState();
  return (
    <div style={{ display: 'flex', gap: 16 }}>
      <div role="tablist" aria-label="Innings" style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
        {w.lineup.innings.map((_, i) => {
          const on = i === w.inning;
          return (
            <button key={i} role="tab" aria-selected={on} onClick={() => w.setInning(i)} title={`Inning ${i + 1}${i < 9 ? ` (press ${i + 1})` : ''}`}
              className={on ? '' : 'h-dim'}
              style={{ width: 48, height: 46, borderRadius: 10, background: on ? C.blue : FILL, color: on ? '#fff' : C.label, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 3 }}>
              <span className="num" style={{ fontSize: 17, fontWeight: 700, lineHeight: '19px' }}>{i + 1}</span>
              <span style={{ height: 14, display: 'grid', placeItems: 'center' }}><InningMark state={state(i)} onBlue={on} /></span>
            </button>
          );
        })}
      </div>
      <div style={{ flex: 1, minWidth: 0, display: 'flex', justifyContent: 'center' }}>
        <div style={{ width: 560 * SCALE, height: 430 * SCALE, position: 'relative', flexShrink: 0 }}>
          <div style={{ position: 'absolute', left: 0, top: 0, width: 560, height: 430, transform: `scale(${SCALE})`, transformOrigin: '0 0' }}>
            {/* Outfield: quarter circle of radius 380 around home (280,405). Infield: 152px square turned 45°, centered at (280,298). */}
            <svg width={560} height={430} style={{ position: 'absolute', inset: 0, overflow: 'visible', pointerEvents: 'none' }} aria-hidden>
              <path d="M280 405 L11.3 136.3 A380 380 0 0 1 548.7 136.3 Z" fill="rgba(52,199,89,0.08)" />
              <path d="M280 190.5 L387.5 298 L280 405.5 L172.5 298 Z" fill="rgba(48,176,199,0.16)" />
            </svg>
            {w.positions.map((pos) => FIELD_XY[pos] && <FieldChip key={pos} pos={pos} xy={FIELD_XY[pos]!} />)}
          </div>
        </div>
      </div>
    </div>
  );
}

function FieldChip({ pos, xy }: { pos: FieldPosition; xy: [number, number] }) {
  const w = useWorkbench();
  const s = useSpot(w.inning, pos, `f-${pos}`);
  return (
    <button className="field-chip" {...s.handlers}
      aria-label={`${POSITION_NAMES[pos]}: ${s.p ? `${s.p.firstName} ${s.p.lastName}` : 'open'}`}
      style={{ position: 'absolute', left: xy[0], top: xy[1], transform: 'translate(-50%, -50%)', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4, padding: 4, borderRadius: 12, boxShadow: s.ring }}>
      <span style={{ fontSize: 14, fontWeight: 700, color: '#fff', padding: '7px 6px', borderRadius: 7, background: badgeColor(pos), minWidth: 34, textAlign: 'center', lineHeight: '16px' }}>{pos}</span>
      <span className="ellipsis" style={{
        maxWidth: 120, fontSize: 15, fontWeight: s.p ? 600 : 500, background: '#fff', borderRadius: 7, padding: '4px 10px',
        boxShadow: '0 1px 3px rgba(0,0,0,0.12)', color: s.p ? (s.never ? C.red : C.label) : C.orange,
        border: s.p ? '0.5px solid transparent' : `1px dashed ${C.orange}`,
      }}>
        {s.p ? w.nameOf(s.p) : 'Open'}
      </span>
    </button>
  );
}

function BenchBox() {
  const w = useWorkbench();
  const list = benched(w, w.inning);
  return (
    <div {...w.dropProps('bn', (src) => w.place(src.pid, w.inning, 'Bench'))}
      style={{ background: C.gray6, borderRadius: 12, padding: '10px 12px', boxShadow: w.dropKey === 'bn' ? `inset 0 0 0 2px ${C.blue}` : undefined }}>
      <div style={{ fontSize: 11, fontWeight: 600, letterSpacing: '0.05em', color: SUB, textTransform: 'uppercase', marginBottom: 8 }}>Bench · Inning {w.inning + 1}</div>
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6 }}>
        {list.map((p) => <BenchChip key={p.id} p={p} inning={w.inning} size="lg" />)}
        {list.length === 0 && <span style={{ fontSize: 13, color: SUB }}>Nobody</span>}
      </div>
      <div style={{ fontSize: 12, lineHeight: '16px', color: C.label3, marginTop: 8 }}>Drag a player here to bench or onto a position to swap</div>
    </div>
  );
}

// MARK: - Right rail totals

function Totals() {
  const w = useWorkbench();
  const b2b = useBackToBack();
  const absent = w.players.filter((p) => w.lineup.absentPlayerIDs.includes(p.id));
  const cols = '1fr 30px 30px 30px';
  const head: CSSProperties = { fontSize: 11, fontWeight: 600, color: SUB, textAlign: 'center' };
  return (
    <div style={{ borderRadius: 10, border: `1px solid ${BORDER}`, overflow: 'hidden' }}>
      <div style={{ display: 'grid', gridTemplateColumns: cols, height: 28, alignItems: 'center', padding: '0 10px 0 12px', background: '#F7F7FA', borderBottom: `1px solid ${BORDER}` }}>
        <span style={{ ...head, textAlign: 'left', letterSpacing: '0.04em' }}>PLAYER</span><span style={head}>IF</span><span style={head}>OF</span><span style={head}>BN</span>
      </div>
      {w.active.map((p, i) => {
        const t = playingTime(w.lineup, p);
        const bn = w.lineup.innings.filter((inn) => inn.assignments[p.id] === 'Bench').length;
        return (
          <div key={p.id} className="num" style={{ display: 'grid', gridTemplateColumns: cols, height: 28, alignItems: 'center', padding: '0 10px 0 12px', fontSize: 13, borderTop: i ? '1px solid rgba(60,60,67,0.08)' : 'none' }}>
            <span className="ellipsis">{shortName(p)}</span>
            <span style={{ textAlign: 'center' }}>{t.infield}</span>
            <span style={{ textAlign: 'center' }}>{t.outfield}</span>
            <span style={{ textAlign: 'center', fontWeight: 600, color: b2b.has(p.id) ? C.red : C.label }}>{bn}</span>
          </div>
        );
      })}
      {absent.map((p) => (
        <div key={p.id} style={{ display: 'grid', gridTemplateColumns: cols, height: 28, alignItems: 'center', padding: '0 10px 0 12px', fontSize: 13, borderTop: '1px solid rgba(60,60,67,0.08)', opacity: 0.4 }}>
          <span className="ellipsis">{shortName(p)}</span><span /><span /><span style={{ textAlign: 'center', fontWeight: 600 }}>Out</span>
        </div>
      ))}
    </div>
  );
}

// MARK: - By Position grid

function GridView() {
  const w = useWorkbench();
  const state = useInningState();
  const innings = w.lineup.innings.map((_, i) => i);
  const cols = `120px repeat(${innings.length}, minmax(0, 1fr))`;
  const sections: [string, string, FieldPosition[]][] = [
    ['Infield', C.blue, w.positions.filter(isInfield)],
    ['Outfield', C.green, w.positions.filter(isOutfield)],
  ];
  return (
    <div>
      <div style={{ display: 'grid', gridTemplateColumns: cols, gap: 5, alignItems: 'center' }}>
        <span />
        {innings.map((i) => (
          <button key={i} className="inn-head" onClick={() => w.showInning(i)} title={`Open inning ${i + 1} on the field`}
            style={{ fontSize: 13, fontWeight: 500, color: SUB, borderRadius: 6, padding: '4px 0', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 5 }}>
            Inn {i + 1}<InningMark state={state(i)} />
          </button>
        ))}
      </div>
      {sections.map(([label, color, list]) => list.length > 0 && (
        <div key={label}>
          <SectionLabel dot={color}>{label}</SectionLabel>
          <div style={{ display: 'grid', gridTemplateColumns: cols, gap: 5 }}>
            {list.map((pos) => [
              <div key={pos} style={{ display: 'flex', alignItems: 'center', gap: 8, minWidth: 0 }}>
                <span style={{ width: 30, fontSize: 12, fontWeight: 700, color: '#fff', padding: '5px 0', borderRadius: 6, background: badgeColor(pos), textAlign: 'center', flexShrink: 0 }}>{pos}</span>
                <span className="ellipsis" style={{ fontSize: 13, color: SUB }}>{POSITION_NAMES[pos]}</span>
              </div>,
              ...innings.map((i) => <GridCell key={`${pos}-${i}`} inning={i} pos={pos} />),
            ])}
          </div>
        </div>
      ))}
      <SectionLabel dot={C.gray1}>Bench</SectionLabel>
      <div style={{ display: 'grid', gridTemplateColumns: cols, gap: 5, alignItems: 'start' }}>
        <span style={{ fontSize: 12, lineHeight: '16px', color: C.label3, paddingTop: 4 }}>Drop here to bench</span>
        {innings.map((i) => <BenchColumn key={i} inning={i} />)}
      </div>
    </div>
  );
}

function SectionLabel({ dot, children }: { dot: string; children: string }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 8, margin: '14px 0 7px' }}>
      <span style={{ width: 8, height: 8, borderRadius: 4, background: dot }} />
      <span style={{ fontSize: 11, fontWeight: 600, letterSpacing: '0.05em', color: SUB, textTransform: 'uppercase' }}>{children}</span>
    </div>
  );
}

function GridCell({ inning, pos }: { inning: number; pos: FieldPosition }) {
  const w = useWorkbench();
  const s = useSpot(inning, pos, `c-${inning}-${pos}`);
  return (
    <button className="field-cell ellipsis" {...s.handlers}
      aria-label={`${POSITION_NAMES[pos]}, inning ${inning + 1}: ${s.p ? `${s.p.firstName} ${s.p.lastName}` : 'open'}`}
      style={{
        height: 36, borderRadius: 8, fontSize: 14, fontWeight: s.p ? 600 : 500, textAlign: 'center', padding: '0 6px',
        background: s.p ? tint(pos) : '#fff', border: s.p ? 'none' : `1px dashed ${C.gray3}`,
        color: s.p ? (s.never ? C.red : C.label) : C.orange, boxShadow: s.ring,
      }}>
      {s.p ? w.nameOf(s.p) : 'Open'}
    </button>
  );
}

function BenchColumn({ inning }: { inning: number }) {
  const w = useWorkbench();
  const key = `b-${inning}`;
  return (
    <div {...w.dropProps(key, (src) => w.place(src.pid, inning, 'Bench'))}
      style={{ background: FILL, borderRadius: 8, padding: 4, display: 'flex', flexDirection: 'column', gap: 4, minHeight: 36, boxShadow: w.dropKey === key ? `inset 0 0 0 2px ${C.blue}` : undefined }}>
      {benched(w, inning).map((p) => <BenchChip key={p.id} p={p} inning={inning} size="sm" />)}
    </div>
  );
}

// MARK: - Pitching

function Pitching() {
  const w = useWorkbench();
  const rules = w.team.pitchingConfig.rulesEnabled;
  const rows = w.active
    .map((p) => ({ p, n: w.lineup.innings.filter((inn) => inn.assignments[p.id] === 'P').length }))
    .filter((r) => r.n > 0 || canPitch(r.p))
    .sort((a, b) => b.n - a.n);
  const rest = (p: Player) => {
    if (!rules) return { text: '—', warn: false };
    const s = pitchStatus(p, w.gameLogs, w.team.pitchingConfig, w.lineup.gameDate);
    return { text: s.kind === 'eligible' ? 'Ready' : statusLabel(s), warn: s.kind === 'mustRest' || s.kind === 'unknownAge' };
  };
  const cols = '1fr 90px 200px';
  return (
    <div style={{ maxWidth: 640 }}>
      <div style={{ borderRadius: 10, border: `1px solid ${BORDER}`, overflow: 'hidden' }}>
        <div style={{ display: 'grid', gridTemplateColumns: cols, height: 30, alignItems: 'center', padding: '0 14px', fontSize: 11, fontWeight: 600, letterSpacing: '0.04em', color: SUB, background: '#F7F7FA', borderBottom: `1px solid ${BORDER}` }}>
          <span>PITCHER</span><span>INNINGS</span><span>REST</span>
        </div>
        {rows.map(({ p, n }, i) => {
          const r = rest(p);
          return (
            <div key={p.id} style={{ display: 'grid', gridTemplateColumns: cols, height: 40, alignItems: 'center', padding: '0 14px', fontSize: 14, borderTop: i ? '1px solid rgba(60,60,67,0.08)' : 'none' }}>
              <span className="ellipsis">{p.firstName} {p.lastName}</span>
              <span className="num" style={{ fontWeight: 600 }}>{n}</span>
              <span style={{ fontSize: 13, color: r.warn ? C.red : SUB }}>{r.text}</span>
            </div>
          );
        })}
        {rows.length === 0 && <div style={{ padding: '12px 14px', fontSize: 14, color: SUB }}>No one is pitching yet.</div>}
      </div>
      <p style={{ fontSize: 13, color: SUB, marginTop: 10 }}>
        {rules
          ? 'Rest is informed by your pitch count rules and archived games.'
          : 'Pitch count rules are turned off for this team. Turn them on in Team settings.'}
      </p>
    </div>
  );
}

/** Players who can pitch (Strength or Capable) are listed even before they're given an inning. */
const canPitch = (p: Player) => p.positionPreferences.P === 'Strength' || p.positionPreferences.P === 'Capable';
