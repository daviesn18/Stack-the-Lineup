// Positions: By Position (summary grid), By Inning (field view) and Pitching,
// with the Draft/Finalized strip on top and Clear positions at the bottom.

import { useState, type CSSProperties, type ReactNode } from 'react';

import { runAutoFill, type AutoFillOutcome } from '@/core/autofillCoordinator';
import { openPositions } from '@/core/fairPlay';
import { clearPositions, finalize, reopen } from '@/core/lineupOps';
import { isInfield, isOutfield, POSITION_NAMES, type FieldPosition, type Player } from '@/core/model';
import { status as pitchStatus } from '@/core/pitching';
import { useIsPro } from '@/data/auth';
import { statusLabel } from '@/print/lineupPdf';

import { Icon } from './Icon';
import { useWorkbench, type PosView } from './state';
import { badgeColor, C, tint } from './theme';
import { Segmented, Title } from './ui';

// MARK: - Screen

export function PositionsScreen() {
  const w = useWorkbench();
  const titles: Record<PosView, [string, string]> = {
    position: ['Position Summary', 'Drag names to swap · Right-click for options'],
    inning: ['Inning by inning', `Keys 1-${Math.min(9, w.lineup.innings.length)} or arrows switch innings`],
    pitching: ['Pitching', ''],
  };
  const [title, hint] = titles[w.posView];
  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', minWidth: 0, minHeight: 0 }}>
      <StatusStrip />
      <div style={{ flex: 1, overflowY: 'auto' }}>
        <div style={{ maxWidth: 900, margin: '0 auto', padding: '22px 28px 36px' }}>
          <Title hint={hint}>{title}</Title>
          <Segmented value={w.posView} onChange={w.setPosView}
            options={[['position', 'By Position'], ['inning', 'By Inning'], ['pitching', 'Pitching']]} />
          <div style={{ marginTop: 20 }}>
            {w.posView === 'position' && <SummaryGrid />}
            {w.posView === 'inning' && <ByInning />}
            {w.posView === 'pitching' && <Pitching />}
          </div>
        </div>
      </div>
      {w.posView !== 'pitching' && (
        <div style={{ flexShrink: 0, background: '#fff', borderTop: C.hair, padding: 10, display: 'flex', justifyContent: 'center' }}>
          <button className="h-bright" onClick={() => w.edit((l) => clearPositions(l), 'All positions cleared')}
            style={{ display: 'flex', alignItems: 'center', gap: 6, background: C.destructiveBg, border: `0.5px solid ${C.destructiveBorder}`, color: C.destructiveFg, fontSize: 15, fontWeight: 500, borderRadius: 8, padding: '7px 16px' }}>
            <Icon name="minus.circle.fill" size={15} color={C.destructiveFg} />Clear positions
          </button>
        </div>
      )}
    </div>
  );
}

function StatusStrip() {
  const w = useWorkbench();
  const done = w.lineup.status === 'finalized';
  const color = done ? C.green : C.label2;
  return (
    <div className="strip" style={{ height: 32, flexShrink: 0, background: done ? 'rgba(52,199,89,0.10)' : C.grouped, borderBottom: C.hair, padding: '0 20px', display: 'flex', alignItems: 'center', gap: 7 }}>
      <span style={{ width: 7, height: 7, borderRadius: 4, background: done ? C.green : C.gray1 }} />
      <span style={{ fontSize: 13, fontWeight: 600, color }}>{done ? 'Finalized' : 'Draft'}</span>
      {done && w.lineup.lastFinalizedAt && (
        <span style={{ fontSize: 13, color: C.label2 }}>
          {w.lineup.lastFinalizedBy ? `by ${w.lineup.lastFinalizedBy} ` : ''}{w.lineup.lastFinalizedAt.toLocaleString('en-US', { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' })}
        </span>
      )}
      <button className="h-link" style={{ marginLeft: 'auto', fontSize: 13, fontWeight: 600, color: C.blue }}
        onClick={() => w.edit((l) => (done ? reopen(l) : finalize(l, w.team.coachName)))}>
        {done ? 'Reopen' : 'Finalize lineup →'}
      </button>
    </div>
  );
}

// MARK: - Shared cell pieces

type InningState = 'ok' | 'partial' | 'empty';
function useInningState() {
  const w = useWorkbench();
  return (i: number): InningState => {
    const open = openPositions(w.lineup, i, w.players, w.team.fairPlayConfig).length;
    return open === 0 && w.active.length > 0 ? 'ok' : open === w.positions.length ? 'empty' : 'partial';
  };
}
const dotColor = (s: InningState) => (s === 'ok' ? C.green : s === 'partial' ? C.orange : C.gray3);

export function PosBadge({ pos, style }: { pos: FieldPosition; style?: CSSProperties }) {
  return (
    <span style={{ minWidth: 32, fontSize: 13, fontWeight: 700, color: '#fff', padding: '6px 0', borderRadius: 6, background: badgeColor(pos), textAlign: 'center', display: 'inline-block', ...style }}>
      {pos}
    </span>
  );
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

// MARK: - By Position

function SummaryGrid() {
  const w = useWorkbench();
  const state = useInningState();
  const innings = w.lineup.innings.map((_, i) => i);
  const cols = `132px repeat(${innings.length}, minmax(0, 1fr))`;
  const sections: [string, string, FieldPosition[]][] = [
    ['Infield', C.blue, w.positions.filter(isInfield)],
    ['Outfield', C.green, w.positions.filter(isOutfield)],
  ];
  const open = innings.reduce((n, i) => n + openPositions(w.lineup, i, w.players, w.team.fairPlayConfig).length, 0);
  return (
    <div>
      <AutoFillBar left={
        <span style={{ fontSize: 17, fontWeight: 500, color: open ? C.orange : C.green }}>
          {open ? `${open} open ${open === 1 ? 'spot' : 'spots'} across ${innings.length} innings` : 'Every inning is set'}
        </span>
      } />
      <div style={{ display: 'grid', gridTemplateColumns: cols, gap: 6, alignItems: 'center', marginTop: 16 }}>
        <span style={{ fontSize: 14, color: C.label2 }}>Position</span>
        {innings.map((i) => (
          <button key={i} className="inn-head" onClick={() => w.showInning(i)} title={`Open inning ${i + 1}`}
            style={{ fontSize: 14, fontWeight: 500, color: C.label2, borderRadius: 6, padding: '4px 0', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 5 }}>
            Inn {i + 1}<span className="inn-status" style={{ width: 6, height: 6, borderRadius: 3, background: dotColor(state(i)) }} />
          </button>
        ))}
      </div>
      {sections.map(([label, dot, list]) => list.length > 0 && (
        <div key={label}>
          <SectionLabel dot={dot}>{label}</SectionLabel>
          <div style={{ display: 'grid', gridTemplateColumns: cols, gap: 6 }}>
            {list.map((pos) => [
              <div key={pos} style={{ display: 'flex', alignItems: 'center', gap: 10, minWidth: 0 }}>
                <PosBadge pos={pos} />
                <span className="ellipsis" style={{ fontSize: 14, color: C.label2 }}>{POSITION_NAMES[pos]}</span>
              </div>,
              ...innings.map((i) => <GridCell key={`${pos}-${i}`} inning={i} pos={pos} />),
            ])}
          </div>
        </div>
      ))}
      <SectionLabel dot={C.gray1}>Bench</SectionLabel>
      <div style={{ display: 'grid', gridTemplateColumns: cols, gap: 6, alignItems: 'start' }}>
        <span style={{ fontSize: 12, lineHeight: '16px', color: C.label3, paddingTop: 4 }}>Drop here to bench</span>
        {innings.map((i) => <BenchColumn key={i} inning={i} />)}
      </div>
    </div>
  );
}

function SectionLabel({ dot, children }: { dot: string; children: string }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 8, margin: '18px 0 8px' }}>
      <span style={{ width: 8, height: 8, borderRadius: 4, background: dot }} />
      <span style={{ fontSize: 12, fontWeight: 600, letterSpacing: 0.6, color: C.label2, textTransform: 'uppercase' }}>{children}</span>
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
        height: 40, borderRadius: 8, fontSize: 14, fontWeight: s.p ? 600 : 500, textAlign: 'center', padding: '0 6px',
        background: s.p ? tint(pos) : '#fff', border: s.p ? 'none' : `1px dashed ${C.gray3}`,
        color: s.p ? (s.never ? C.red : C.label) : C.orange, boxShadow: s.ring,
      }}>
      {s.p ? w.nameOf(s.p) : 'Open'}
    </button>
  );
}

/** Active players on Bench (or unassigned) in an inning. */
function benched(w: ReturnType<typeof useWorkbench>, inning: number): Player[] {
  return w.active.filter((p) => { const x = w.posOf(p.id, inning); return x === undefined || x === 'Bench'; });
}

function BenchChip({ p, inning, capsule }: { p: Player; inning: number; capsule?: boolean }) {
  const w = useWorkbench();
  const unassigned = w.posOf(p.id, inning) === undefined;
  return (
    <span {...w.dragProps(p.id, 'cell')} onContextMenu={(e) => w.openMenu(e, p.id, inning)}
      title={unassigned ? `${p.firstName} has no spot yet this inning` : undefined}
      className="ellipsis"
      style={capsule
        ? { fontSize: 14, fontWeight: 500, background: C.gray6, borderRadius: 999, padding: '4px 12px', border: unassigned ? `1px dashed ${C.gray2}` : 'none' }
        : { fontSize: 13, color: C.label2, background: '#fff', borderRadius: 6, padding: '4px 6px', textAlign: 'center', border: unassigned ? `1px dashed ${C.gray2}` : `0.5px solid ${C.gray4}` }}>
      {w.nameOf(p)}
    </span>
  );
}

function BenchColumn({ inning }: { inning: number }) {
  const w = useWorkbench();
  const key = `b-${inning}`;
  return (
    <div {...w.dropProps(key, (src) => w.place(src.pid, inning, 'Bench'))}
      style={{ background: C.gray5, borderRadius: 8, padding: 4, display: 'flex', flexDirection: 'column', gap: 4, minHeight: 36, boxShadow: w.dropKey === key ? `inset 0 0 0 2px ${C.blue}` : undefined }}>
      {benched(w, inning).map((p) => <BenchChip key={p.id} p={p} inning={inning} />)}
    </div>
  );
}

// MARK: - By Inning

const FIELD_XY: Partial<Record<FieldPosition, [number, number]>> = {
  CF: [280, 50], LF: [100, 118], RF: [460, 118], LCF: [188, 70], RCF: [372, 70],
  SS: [196, 204], '2B': [364, 204], '3B': [122, 300], '1B': [438, 300], P: [280, 282], C: [280, 392],
};

/**
 * Auto-Fill with its optional instructions and result notes, under a view's
 * own heading (`left`). Fills every open spot in every inning, so it reads
 * the same on By Position and By Inning.
 */
function AutoFillBar({ left }: { left: ReactNode }) {
  const w = useWorkbench();
  // A new game length or field (team settings) makes the last run's notes stale.
  return <AutoFillControls key={`${w.lineup.innings.length}:${w.positions.join()}`} left={left} />;
}

function AutoFillControls({ left }: { left: ReactNode }) {
  const w = useWorkbench();
  const isPro = useIsPro();
  const [prompt, setPrompt] = useState('');
  const [showPrompt, setShowPrompt] = useState(false);
  const [result, setResult] = useState<AutoFillOutcome | null>(null);

  const autoFill = () => {
    const outcome = runAutoFill({
      scope: { kind: 'through', inning: w.lineup.innings.length - 1 }, prompt,
      lineup: w.lineup, players: w.players, config: w.team.fairPlayConfig, pitchingConfig: w.team.pitchingConfig, gameLogs: w.gameLogs,
    });
    setResult(outcome);
    if (outcome.filledCount > 0) w.edit(() => outcome.lineup, 'Open positions filled');
    else w.showToast('Nothing to fill: every spot is already set');
  };

  return (
    <div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 12, minHeight: 40 }}>
        {left}
        <div style={{ marginLeft: 'auto', display: 'flex', alignItems: 'center', gap: 14 }}>
          <button className="h-link" style={{ fontSize: 14, color: C.blue }} onClick={() => setShowPrompt((v) => !v)}>
            {showPrompt ? 'Hide instructions' : prompt.trim() ? 'Edit instructions' : 'Add instructions'}
          </button>
          <button className="h-bright" onClick={autoFill} disabled={isPro === false}
            title={isPro === false ? 'Auto-Fill is a Pro feature' : 'Fill every open spot in every inning'}
            style={{ height: 40, padding: '0 18px', borderRadius: 12, background: C.blue, color: '#fff', fontSize: 16, fontWeight: 600, display: 'flex', alignItems: 'center', gap: 8, opacity: isPro === false ? 0.5 : 1 }}>
            <Icon name="bolt.fill" size={16} color="#fff" />Auto-Fill Open Positions
          </button>
        </div>
      </div>
      {showPrompt && (
        <div style={{ marginTop: 12, background: '#fff', borderRadius: 12, padding: '10px 12px' }}>
          <textarea value={prompt} onChange={(e) => setPrompt(e.target.value)} rows={3} aria-label="Auto-Fill instructions"
            placeholder={'Optional, one per line:\nJake pitches innings 1 to 2\nkeep Nate off pitcher'}
            style={{ width: '100%', border: 'none', outline: 'none', resize: 'vertical', fontSize: 15, lineHeight: '20px', background: 'transparent' }} />
          <div style={{ fontSize: 12, color: C.label2 }}>Auto-Fill follows these, fills open spots only, and keeps anything you&apos;ve set.</div>
        </div>
      )}
      {result && (result.incompleteMessage || result.noticeMessage) && (
        <div role="status" style={{ marginTop: 12, display: 'flex', flexDirection: 'column', gap: 8 }}>
          {result.incompleteMessage && <Note color={C.orange} bg="rgba(255,149,0,0.10)" onClose={() => setResult(null)}>{result.incompleteMessage}</Note>}
          {result.noticeMessage && <Note color={C.blue} bg="rgba(0,122,255,0.07)" onClose={() => setResult(null)}>{result.noticeMessage}</Note>}
        </div>
      )}
    </div>
  );
}

function ByInning() {
  const w = useWorkbench();
  const state = useInningState();
  const cur = w.inning;
  const open = openPositions(w.lineup, cur, w.players, w.team.fairPlayConfig).length;

  return (
    <div>
      <AutoFillBar left={<>
        <span style={{ fontSize: 28, fontWeight: 700 }}>Inning {cur + 1}</span>
        <span style={{ fontSize: 17, fontWeight: 500, color: open ? C.orange : C.green, alignSelf: 'flex-end', marginBottom: 4 }}>
          {open ? `${open} open` : 'Field set'}
        </span>
      </>} />

      <div style={{ display: 'flex', gap: 24, marginTop: 16 }}>
        <div role="tablist" aria-label="Innings" style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
          {w.lineup.innings.map((_, i) => {
            const on = i === cur;
            return (
              <button key={i} role="tab" aria-selected={on} onClick={() => w.setInning(i)} title={`Inning ${i + 1}${i < 9 ? ` (press ${i + 1})` : ''}`}
                className={on ? '' : 'h-dim'}
                style={{ width: 52, height: 50, borderRadius: 10, background: on ? C.blue : C.gray5, color: on ? '#fff' : C.label, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 4 }}>
                <span style={{ fontSize: 18, fontWeight: 700, lineHeight: '20px' }}>{i + 1}</span>
                <span style={{ width: 6, height: 6, borderRadius: 3, background: on ? 'rgba(255,255,255,0.85)' : dotColor(state(i)) }} />
              </button>
            );
          })}
        </div>
        <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
          <div style={{ position: 'relative', width: 560, height: 430, flexShrink: 0 }}>
            {/* Outfield: quarter circle of radius 380 around home (280,405). Infield: 152px square turned 45°, centered at (280,298). */}
            <svg width={560} height={430} style={{ position: 'absolute', inset: 0, overflow: 'visible', pointerEvents: 'none' }} aria-hidden>
              <path d="M280 405 L11.3 136.3 A380 380 0 0 1 548.7 136.3 Z" fill="rgba(52,199,89,0.08)" />
              <path d="M280 190.5 L387.5 298 L280 405.5 L172.5 298 Z" fill="rgba(48,176,199,0.16)" />
            </svg>
            {w.positions.map((pos) => FIELD_XY[pos] && <FieldChip key={pos} pos={pos} xy={FIELD_XY[pos]!} />)}
          </div>
          <BenchStrip />
        </div>
      </div>
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

function FieldChip({ pos, xy }: { pos: FieldPosition; xy: [number, number] }) {
  const w = useWorkbench();
  const s = useSpot(w.inning, pos, `f-${pos}`);
  return (
    <button className="field-chip" {...s.handlers}
      aria-label={`${POSITION_NAMES[pos]}: ${s.p ? `${s.p.firstName} ${s.p.lastName}` : 'open'}`}
      style={{ position: 'absolute', left: xy[0], top: xy[1], transform: 'translate(-50%, -50%)', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4, padding: 4, borderRadius: 10, boxShadow: s.ring }}>
      <span style={{ fontSize: 14, fontWeight: 700, color: '#fff', padding: '7px 6px', borderRadius: 7, background: badgeColor(pos), minWidth: 36, textAlign: 'center', lineHeight: '16px' }}>{pos}</span>
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

function BenchStrip() {
  const w = useWorkbench();
  const list = benched(w, w.inning);
  return (
    <div {...w.dropProps('bn', (src) => w.place(src.pid, w.inning, 'Bench'))}
      style={{ alignSelf: 'stretch', marginTop: 8, background: '#fff', borderRadius: 12, padding: '10px 12px', display: 'flex', alignItems: 'center', flexWrap: 'wrap', gap: 8, boxShadow: w.dropKey === 'bn' ? `inset 0 0 0 2px ${C.blue}` : undefined }}>
      <span style={{ fontSize: 12, fontWeight: 600, letterSpacing: 0.6, color: C.label2, marginRight: 4 }}>BENCH</span>
      {list.map((p) => <BenchChip key={p.id} p={p} inning={w.inning} capsule />)}
      {list.length === 0 && <span style={{ fontSize: 13, color: C.label3 }}>Nobody on the bench</span>}
      <span style={{ marginLeft: 'auto', fontSize: 12, color: C.label3 }}>Drag a player onto a position to swap</span>
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
  const cell: CSSProperties = { padding: '12px 18px', fontSize: 17 };
  return (
    <div>
      <div style={{ background: '#fff', borderRadius: 12, maxWidth: 620, overflow: 'hidden' }}>
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 90px 180px', fontSize: 12, fontWeight: 500, letterSpacing: 0.6, color: C.label2, boxShadow: `inset 0 -0.5px 0 ${C.sep}` }}>
          <span style={{ padding: '10px 18px' }}>PITCHER</span><span style={{ padding: '10px 18px' }}>INNINGS</span><span style={{ padding: '10px 18px' }}>REST</span>
        </div>
        {rows.map(({ p, n }, i) => (
          <div key={p.id} style={{ display: 'grid', gridTemplateColumns: '1fr 90px 180px', borderTop: i ? C.hair : 'none' }}>
            <span className="ellipsis" style={cell}>{p.firstName} {p.lastName}</span>
            <span className="num" style={{ ...cell, fontWeight: 600 }}>{n}</span>
            <span style={{ ...cell, fontSize: 15, color: rest(p).warn ? C.red : C.label2 }}>{rest(p).text}</span>
          </div>
        ))}
        {rows.length === 0 && <div style={{ ...cell, fontSize: 15, color: C.label2 }}>No one is pitching yet.</div>}
      </div>
      <p style={{ fontSize: 13, color: C.label2, marginTop: 10, maxWidth: 620 }}>
        {rules
          ? 'Rest is from your pitch count rules and the pitch counts in archived games, as of this game’s date.'
          : 'Pitch count rules are off for this team, so rest isn’t tracked.'}
      </p>
    </div>
  );
}

/** Players who can pitch (Strength or Capable) are listed even before they're given an inning. */
const canPitch = (p: Player) => p.positionPreferences.P === 'Strength' || p.positionPreferences.P === 'Capable';
