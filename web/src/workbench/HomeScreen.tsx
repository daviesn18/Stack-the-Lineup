// Home: how ready the next game is, plus the season so far (bench innings,
// the schedule and position coverage), from archived games.

import { useMemo, type ReactNode } from 'react';

import { shortName } from '@/core/lineupOps';
import { POSITION_NAMES, type FieldPosition } from '@/core/model';

import { seasonTotals } from './HistoryScreen';
import { Icon } from './Icon';
import { gameStatus, gameTitle, gameWhen, plural } from './gameStatus';
import { PageHeader, Pill, PrimaryButton, SUB, type PillKind } from './Shell';
import { useWorkbench, type Step } from './state';
import { badgeColor, C } from './theme';

const card = { background: '#fff', borderRadius: 14, padding: 22 } as const;
const HAIR = '1px solid rgba(60,60,67,0.08)';

export function HomeScreen() {
  const w = useWorkbench();
  const st = gameStatus(w);
  const totals = useMemo(() => seasonTotals(w.players, w.gameLogs), [w.players, w.gameLogs]);
  const days = Math.round((startOfDay(w.lineup.gameDate) - startOfDay(new Date())) / 86_400_000);
  const when = days === 0 ? 'Today' : days === 1 ? 'Tomorrow' : days > 1 ? `In ${days} days` : `${-days} day${days === -1 ? '' : 's'} ago`;

  const checklist: { label: string; meta: string; state: 'done' | 'warn' | 'todo'; cta: string; step: Step }[] = [
    { label: 'Attendance', meta: `${st.here} of ${st.total} coming`, state: 'done', cta: 'Edit', step: 1 },
    { label: 'Batting order', meta: `${plural(st.here, 'batter')}`, state: 'done', cta: 'Edit', step: 2 },
    {
      label: 'Defense', step: 3,
      meta: !st.started ? 'No positions yet' : st.fpOk ? `All ${w.lineup.innings.length} innings pass fair play` : plural(st.issueCount, 'fair-play issue'),
      state: !st.started ? 'todo' : st.fpOk ? 'done' : 'warn', cta: !st.started ? 'Set' : st.fpOk ? 'Edit' : 'Fix',
    },
    { label: 'Finalize lineup', meta: st.finalized ? 'Finalized. Coaches Guide is ready.' : 'Not finalized yet', state: st.finalized ? 'done' : 'todo', cta: st.finalized ? 'View' : 'Review', step: 4 },
  ];

  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', minWidth: 0, background: C.grouped }}>
      <PageHeader right={<PrimaryButton icon="calendar.badge.plus" onClick={() => w.setNewGameOpen(true)}>New game</PrimaryButton>}>
        <span style={{ fontSize: 15, fontWeight: 600 }}>Home</span>
      </PageHeader>
      <div style={{ flex: 1, overflowY: 'auto', padding: 24 }}>
        <div style={{ display: 'grid', gridTemplateColumns: '1.3fr 1fr', gap: 16, alignItems: 'stretch' }}>
          <section style={card} aria-label="Next game">
            <div style={{ display: 'flex', gap: 16 }}>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ fontSize: 12, fontWeight: 600, letterSpacing: '0.04em', textTransform: 'uppercase', color: C.blue }}>Next game · {when}</div>
                <div className="ellipsis" style={{ fontSize: 28, fontWeight: 700, letterSpacing: '-0.015em', marginTop: 4 }}>{gameTitle(w.lineup)}</div>
                <div style={{ fontSize: 14, color: SUB, marginTop: 2 }}>{gameWhen(w.lineup.gameDate)}</div>
              </div>
              <div style={{ textAlign: 'right' }}>
                <div className="num" style={{ fontSize: 28, fontWeight: 700 }}>{st.readiness}%</div>
                <div style={{ fontSize: 13, color: SUB }}>ready</div>
              </div>
            </div>
            <div style={{ height: 6, borderRadius: 3, background: C.gray6, margin: '18px 0 14px', overflow: 'hidden' }}>
              <div style={{ height: '100%', width: `${st.readiness}%`, background: C.green, borderRadius: 3, transition: 'width .3s ease' }} />
            </div>
            {checklist.map((c) => (
              <button key={c.label} onClick={() => w.goStep(c.step)} className="h-row2"
                style={{ display: 'flex', alignItems: 'center', gap: 12, width: '100%', padding: '13px 4px', borderTop: HAIR }}>
                <Icon name={c.state === 'done' ? 'checkmark.circle.fill' : c.state === 'warn' ? 'exclamationmark.triangle.fill' : 'plus.circle'}
                  size={20} color={c.state === 'done' ? C.green : c.state === 'warn' ? C.red : 'rgba(60,60,67,0.3)'} />
                <span style={{ flex: 1, minWidth: 0 }}>
                  <span style={{ display: 'block', fontSize: 14, fontWeight: 600 }}>{c.label}</span>
                  <span style={{ display: 'block', fontSize: 13, color: c.state === 'warn' ? C.red : SUB }}>{c.meta}</span>
                </span>
                <span style={{ fontSize: 14, fontWeight: 500, color: C.blue }}>{c.cta}</span>
              </button>
            ))}
          </section>

          <section style={card} aria-label="Bench innings this season">
            <CardTitle right={plural(w.gameLogs.length, 'game')}>Bench innings this season</CardTitle>
            <div style={{ fontSize: 13, color: SUB, marginTop: 2, marginBottom: 14 }}>Innings on the bench in archived games.</div>
            {w.gameLogs.length === 0 ? <Empty>Archive a game and bench time starts adding up here.</Empty> : <BenchBars totals={totals} />}
          </section>

          <section style={card} aria-label="Schedule">
            <CardTitle right={<span title="Coming soon" style={{ color: C.blue, opacity: 0.4, fontSize: 14 }}>Sync calendar</span>}>Schedule</CardTitle>
            <div style={{ marginTop: 10 }}>
              <ScheduleRow date={w.lineup.gameDate} upcoming title={gameTitle(w.lineup)} onClick={() => w.goStep(1)}
                meta={gameWhen(w.lineup.gameDate).split(' · ')[1]}
                pill={st.finalized ? ['green', 'Finalized'] : !st.started ? ['gray', 'Not started'] : st.fpOk ? ['green', 'Ready'] : ['red', plural(st.issueCount, 'issue')]} />
              {w.gameLogs.map((g) => (
                <ScheduleRow key={g.id} date={g.gameDate} title={g.opponent ? `vs ${g.opponent}` : 'Game'}
                  meta={`${g.inningsPlayed} innings`} pill={['teal', 'Archived']} />
              ))}
            </div>
          </section>

          <section style={card} aria-label="Position coverage">
            <CardTitle>Position coverage</CardTitle>
            <div style={{ fontSize: 13, color: SUB, marginTop: 2, marginBottom: 16 }}>How many players have played each spot this season.</div>
            {w.gameLogs.length === 0 ? <Empty>Coverage fills in as you archive games.</Empty> : <Coverage totals={totals} />}
          </section>
        </div>
      </div>
    </div>
  );
}

const startOfDay = (d: Date) => new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();

function CardTitle({ children, right }: { children: ReactNode; right?: ReactNode }) {
  return (
    <div style={{ display: 'flex', alignItems: 'baseline', gap: 12 }}>
      <span style={{ fontSize: 16, fontWeight: 600 }}>{children}</span>
      {right && <span style={{ marginLeft: 'auto', fontSize: 13, color: SUB }}>{right}</span>}
    </div>
  );
}

function Empty({ children }: { children: string }) {
  return <div style={{ fontSize: 14, color: SUB, lineHeight: '20px', padding: '8px 0' }}>{children}</div>;
}

type Totals = ReturnType<typeof seasonTotals>;

function BenchBars({ totals }: { totals: Totals }) {
  const w = useWorkbench();
  const rows = w.players.map((p) => ({ p, n: totals.get(p.id)!.bench })).sort((a, b) => b.n - a.n);
  const max = Math.max(1, ...rows.map((r) => r.n));
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
      {rows.map(({ p, n }) => {
        const top = n === max && n > 0;
        return (
          <div key={p.id} style={{ display: 'grid', gridTemplateColumns: '92px 1fr 22px', gap: 10, alignItems: 'center' }}>
            <span className="ellipsis" style={{ fontSize: 14 }}>{shortName(p)}</span>
            <span style={{ height: 10, borderRadius: 5, background: C.gray6, overflow: 'hidden' }}>
              <span style={{ display: 'block', height: '100%', width: `${(n / max) * 100}%`, borderRadius: 5, background: top ? C.orange : 'rgba(0,122,255,0.55)' }} />
            </span>
            <span className="num" style={{ fontSize: 14, textAlign: 'right', color: top ? 'rgb(133,79,10)' : C.label }}>{n}</span>
          </div>
        );
      })}
    </div>
  );
}

function ScheduleRow({ date, title, meta, pill, upcoming, onClick }: {
  date: Date; title: string; meta: string; pill: [PillKind, string]; upcoming?: boolean; onClick?(): void;
}) {
  const body = (
    <>
      <span style={{ width: 40, textAlign: 'center', flexShrink: 0 }}>
        <span style={{ display: 'block', fontSize: 11, fontWeight: 600, textTransform: 'uppercase', color: upcoming ? C.red : SUB }}>{date.toLocaleDateString('en-US', { month: 'short' })}</span>
        <span className="num" style={{ display: 'block', fontSize: 19, fontWeight: 700, lineHeight: '22px' }}>{date.getDate()}</span>
      </span>
      <span style={{ flex: 1, minWidth: 0, textAlign: 'left' }}>
        <span className="ellipsis" style={{ display: 'block', fontSize: 14, fontWeight: 600 }}>{title}</span>
        <span style={{ display: 'block', fontSize: 13, color: SUB }}>{date.toLocaleDateString('en-US', { weekday: 'short' })} · {meta}</span>
      </span>
      <Pill kind={pill[0]}>{pill[1]}</Pill>
    </>
  );
  const style = { display: 'flex', alignItems: 'center', gap: 14, width: '100%', padding: '11px 0', borderTop: HAIR } as const;
  return onClick ? <button className="h-row2" style={style} onClick={onClick}>{body}</button> : <div style={style}>{body}</div>;
}

const VERB: Partial<Record<FieldPosition, string>> = { P: 'pitched', C: 'caught' };

function Coverage({ totals }: { totals: Totals }) {
  const w = useWorkbench();
  const counts = w.positions.map((pos) => ({ pos, n: w.players.filter((p) => totals.get(p.id)!.played.has(pos)).length }));
  const thin = counts.reduce((a, b) => (b.n < a.n ? b : a), counts[0]);
  return (
    <>
      <div style={{ display: 'grid', gridTemplateColumns: `repeat(${counts.length}, 1fr)`, gap: 6 }}>
        {counts.map(({ pos, n }) => (
          <div key={pos} style={{ textAlign: 'center' }} title={`${n} players have played ${POSITION_NAMES[pos]}`}>
            <div style={{ fontSize: 11, fontWeight: 700, color: '#fff', background: badgeColor(pos), borderRadius: 6, padding: '4px 0' }}>{pos}</div>
            <div className="num" style={{ fontSize: 18, fontWeight: 700, marginTop: 6 }}>{n}</div>
          </div>
        ))}
      </div>
      {thin && thin.n <= 2 && (
        <div style={{ marginTop: 18, background: 'rgba(255,149,0,0.10)', borderRadius: 10, padding: '12px 14px', fontSize: 14, lineHeight: '19px' }}>
          <b style={{ color: 'rgb(133,79,10)', fontWeight: 600 }}>
            {thin.n === 0 ? 'Nobody has' : thin.n === 1 ? 'Only 1 player has' : `Only ${thin.n} players have`} {VERB[thin.pos] ?? `played ${POSITION_NAMES[thin.pos]}`}{thin.n === 0 ? ' yet' : ''}.
          </b>{' '}
          Set {POSITION_NAMES[thin.pos].toLowerCase()} preferences on the Roster page to widen the pool.
        </div>
      )}
    </>
  );
}
