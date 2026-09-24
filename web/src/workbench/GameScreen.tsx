// The game page: header, the four-step bar (Attendance, Batting order,
// Defense, Review), the step, the fair-play box and the Back/Continue footer.
// Steps are never locked; Continue never blocks on fair-play issues.

import { useState, type DragEvent } from 'react';

import { finalize, moveBatter, restoreAbsent, toggleAbsent } from '@/core/lineupOps';
import { battingOrderPdf, coachesGuidePdf, pdfFilename } from '@/print/lineupPdf';
import { openPdfTab } from '@/print/openPdf';

import { DefenseStep } from './DefenseStep';
import { Icon } from './Icon';
import { gameStatus, gameTitle, gameWhen, plural } from './gameStatus';
import { BORDER, FairPlayBox, PageHeader, Pill, PrimaryButton, SecondaryButton, StepTitle, SUB } from './Shell';
import { useWorkbench, type Step } from './state';
import { C } from './theme';
import { Modal, PillButton, TextField } from './ui';

const LABELS = ['Attendance', 'Batting order', 'Defense', 'Review'];

export function GameScreen() {
  const w = useWorkbench();
  const st = gameStatus(w);
  const [gameOpen, setGameOpen] = useState(false);
  const [printError, setPrintError] = useState<string | null>(null);
  const n = w.lineup.innings.length;

  const print = (kind: 'battingOrder' | 'coachesGuide') => {
    setPrintError(null);
    const show = openPdfTab();   // must happen in the click, before any await
    const input = {
      lineup: w.lineup, players: w.players, gameLogs: w.gameLogs, teamName: w.team.name,
      teamColorHex: w.team.colorHex, pitchingConfig: w.team.pitchingConfig,
    };
    (kind === 'battingOrder' ? battingOrderPdf(input) : coachesGuidePdf(input))
      .then((bytes) => show(bytes, pdfFilename(kind, w.lineup.gameDate)))
      .catch((e: Error) => setPrintError(`Couldn't make the printout: ${e.message}`));
  };

  const foot = {
    1: st.here === st.total ? 'Everyone is coming' : `${st.here} of ${st.total} coming. Auto-Fill will fill the open spots.`,
    2: 'Order carries over to next week',
    3: st.fpOk ? `All ${n} innings pass fair play` : 'Fix the issues above, or continue anyway',
    4: st.finalized ? 'Finalized. Print what you need for the dugout.' : 'Finalizing locks the lineup until you edit it',
  }[w.step];

  const next = () => {
    if (w.step < 4) w.goStep((w.step + 1) as Step);
    else if (!st.finalized) w.edit((l) => finalize(l, w.team.coachName), 'Lineup finalized');
  };

  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', minWidth: 0, background: '#fff' }}>
      <PageHeader right={<>
        <SecondaryButton icon="bolt.fill" iconColor={C.blue} onClick={w.autoFill} title="Fill every open spot in every inning">Auto-Fill</SecondaryButton>
        <SecondaryButton icon="doc.richtext.fill" onClick={() => print('coachesGuide')}>Coaches Guide</SecondaryButton>
      </>}>
        <button className="h-link" onClick={() => w.go('home')} style={{ fontSize: 14, color: SUB }}>Games</button>
        <Icon name="chevron.right" size={12} color={SUB} />
        <button className="h-link" onClick={() => setGameOpen(true)} title="Edit opponent, date and time"
          style={{ display: 'flex', alignItems: 'baseline', gap: 10, minWidth: 0 }}>
          <span className="ellipsis" style={{ fontSize: 15, fontWeight: 600 }}>{gameTitle(w.lineup)}</span>
          <span style={{ fontSize: 14, color: SUB, whiteSpace: 'nowrap' }}>{gameWhen(w.lineup.gameDate)}</span>
        </button>
        <Pill kind={st.finalized ? 'green' : 'gray'}>{st.finalized ? 'Finalized' : 'Draft'}</Pill>
      </PageHeader>

      <StepBar />

      <div style={{ flex: 1, overflowY: 'auto', minHeight: 0 }}>
        <div style={{ padding: '22px 24px 16px' }}>
          {w.step === 1 && <Attendance />}
          {w.step === 2 && <BattingOrder />}
          {w.step === 3 && <DefenseStep />}
          {w.step === 4 && <Review print={print} />}
          {printError && <p role="alert" style={{ fontSize: 13, color: C.red, margin: '12px 0 0' }}>{printError}</p>}
        </div>
      </div>

      <FairPlayBox />
      <footer style={{ height: 64, flexShrink: 0, borderTop: `1px solid ${BORDER}`, padding: '0 24px', display: 'flex', alignItems: 'center', gap: 16 }}>
        <span style={{ opacity: w.step === 1 ? 0.4 : 1 }}>
          <SecondaryButton height={36} disabled={w.step === 1} onClick={() => w.goStep((w.step - 1) as Step)}>Back</SecondaryButton>
        </span>
        <span style={{ flex: 1, textAlign: 'center', fontSize: 13, color: SUB }}>{foot}</span>
        {w.step === 4 && st.finalized
          ? <PrimaryButton color={C.green} icon="checkmark.circle.fill" title="Any edit returns the lineup to Draft">Finalized</PrimaryButton>
          : <PrimaryButton onClick={next}>{w.step < 4 ? `Continue to ${LABELS[w.step].toLowerCase()}` : 'Finalize lineup'}</PrimaryButton>}
      </footer>
      {gameOpen && <GameModal onClose={() => setGameOpen(false)} />}
    </div>
  );
}

function StepBar() {
  const w = useWorkbench();
  const st = gameStatus(w);
  const meta = [`${st.here} of ${st.total} coming`, plural(st.here, 'batter'), st.fpOk ? 'Fair play OK' : plural(st.issueCount, 'issue'), st.finalized ? 'Finalized' : 'Not finalized'];
  const done = [true, true, st.fpOk, st.finalized];
  return (
    <nav aria-label="Game steps" style={{ height: 56, flexShrink: 0, borderBottom: `1px solid ${BORDER}`, padding: '0 24px', display: 'flex', alignItems: 'center', gap: 12 }}>
      {LABELS.map((label, k) => {
        const n = (k + 1) as Step;
        const on = w.step === n;
        const warn = n === 3 && !st.fpOk;
        const [cbg, cfg] = on ? [C.blue, '#fff'] : warn ? ['rgba(255,59,48,0.12)', C.red] : done[k] ? ['rgba(52,199,89,0.16)', 'rgb(30,120,55)'] : [C.gray6, SUB];
        return [
          <button key={label} onClick={() => w.goStep(n)} aria-current={on ? 'step' : undefined} className={on ? '' : 'h-step'}
            style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '6px 12px 6px 6px', borderRadius: 999, background: on ? C.gray6 : 'transparent', flexShrink: 0 }}>
            <span className="num" style={{ width: 24, height: 24, borderRadius: 12, background: cbg, color: cfg, fontSize: 13, fontWeight: 600, display: 'grid', placeItems: 'center' }}>{n}</span>
            <span style={{ textAlign: 'left' }}>
              <span style={{ display: 'block', fontSize: 13, fontWeight: 600, color: on || done[k] || warn ? C.label : SUB }}>{label}</span>
              <span style={{ display: 'block', fontSize: 11, color: warn ? C.red : SUB }}>{meta[k]}</span>
            </span>
          </button>,
          k < 3 && <span key={`line-${k}`} style={{ flex: 1, height: 1, background: 'rgba(60,60,67,0.16)', minWidth: 16 }} />,
        ];
      })}
    </nav>
  );
}

// MARK: - Step 1: Attendance

function Attendance() {
  const w = useWorkbench();
  const absent = new Set(w.lineup.absentPlayerIDs);
  // Batting order first, then anyone absent, so the cards read like the lineup.
  const people = [...w.active, ...w.players.filter((p) => absent.has(p.id))];
  return (
    <>
      <StepTitle title="Who's coming?" hint="Click anyone who can't make it. Auto-Fill rebalances around them." />
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, minmax(0, 1fr))', gap: 10 }}>
        {people.map((p) => {
          const out = absent.has(p.id);
          return (
            <button key={p.id} role="switch" aria-checked={!out} aria-label={`${p.firstName} ${p.lastName} is coming`}
              onClick={() => w.edit((l) => (out ? restoreAbsent(l, p.id) : toggleAbsent(l, p.id)), out ? undefined : `${p.firstName} marked not coming`)}
              className="h-card"
              style={{ padding: 14, borderRadius: 12, textAlign: 'left', background: out ? 'rgba(255,59,48,0.04)' : '#fff', boxShadow: `inset 0 0 0 1px ${out ? 'rgba(255,59,48,0.35)' : 'rgba(60,60,67,0.12)'}` }}>
              <span style={{ display: 'flex', alignItems: 'flex-start', opacity: out ? 0.55 : 1 }}>
                <span style={{ width: 36, height: 36, borderRadius: 18, background: C.gray5, color: SUB, fontSize: 13, fontWeight: 600, display: 'grid', placeItems: 'center' }}>
                  {`${p.firstName.charAt(0)}${p.lastName.charAt(0)}`.toUpperCase()}
                </span>
                <span style={{ marginLeft: 'auto' }}><Icon name={out ? 'minus.circle.fill' : 'checkmark.circle.fill'} size={20} color={out ? C.red : C.green} /></span>
              </span>
              <span className="ellipsis" style={{ display: 'block', fontSize: 14, fontWeight: 600, marginTop: 12, opacity: out ? 0.55 : 1 }}>{p.firstName} {p.lastName}</span>
              <span style={{ display: 'block', fontSize: 12, color: out ? C.red : SUB }}>{out ? 'Not coming' : 'Coming'}</span>
            </button>
          );
        })}
      </div>
      {w.players.length === 0 && <p style={{ color: SUB }}>No players yet. Add them on the Roster page.</p>}
    </>
  );
}

// MARK: - Step 2: Batting order

function BattingOrder() {
  const w = useWorkbench();
  // While dragging, rows reorder live on screen; the lineup is saved once, on drop.
  const [live, setLive] = useState<string[] | null>(null);
  const [dragId, setDragId] = useState<string | null>(null);
  const order = live ?? w.active.map((p) => p.id);
  const absent = w.players.filter((p) => w.lineup.absentPlayerIDs.includes(p.id));

  const end = () => {
    if (live && dragId) {
      const to = live.indexOf(dragId);
      const from = w.active.findIndex((p) => p.id === dragId);
      if (to !== from) w.edit((l) => moveBatter({ ...l, battingOrder: w.active.map((p) => p.id) }, dragId, to));
    }
    setLive(null);
    setDragId(null);
  };
  const over = (id: string) => (e: DragEvent) => {
    if (!dragId) return;
    e.preventDefault();
    if (id === dragId) return;
    const o = order.slice();
    const to = o.indexOf(id);
    o.splice(o.indexOf(dragId), 1);
    o.splice(to, 0, dragId);
    setLive(o);
  };

  return (
    <>
      <StepTitle title="Batting order" hint="Drag rows to reorder. The order carries over to the next game." />
      <div style={{ maxWidth: 600, borderRadius: 10, border: `1px solid ${BORDER}`, overflow: 'hidden' }}>
        {order.map((id, i) => {
          const p = w.byId.get(id)!;
          return (
            <div key={id} draggable onDragStart={(e) => { setDragId(id); try { e.dataTransfer.effectAllowed = 'move'; e.dataTransfer.setData('text/plain', id); } catch { /* old browsers */ } }}
              onDragOver={over(id)} onDrop={(e) => { e.preventDefault(); end(); }} onDragEnd={end}
              className="h-row2"
              style={{ height: 46, padding: '0 14px', display: 'flex', alignItems: 'center', gap: 14, borderTop: i ? '1px solid rgba(60,60,67,0.08)' : 'none', background: dragId === id ? 'rgba(0,122,255,0.06)' : undefined }}>
              <span className="num" style={{ width: 22, fontSize: 14, fontWeight: 600, color: C.blue }}>{i + 1}</span>
              <span className="ellipsis" style={{ flex: 1, fontSize: 14, fontWeight: 500 }}>{p.firstName} {p.lastName}</span>
              {p.number && <span className="num" style={{ fontSize: 13, color: SUB }}>#{p.number}</span>}
              <Icon name="list.number" size={16} color={C.label3} />
            </div>
          );
        })}
        {absent.map((p) => (
          <div key={p.id} style={{ height: 46, padding: '0 14px', display: 'flex', alignItems: 'center', gap: 14, borderTop: '1px solid rgba(60,60,67,0.08)', opacity: 0.45 }}>
            <span style={{ width: 22 }} />
            <span className="ellipsis" style={{ flex: 1, fontSize: 14, fontWeight: 500 }}>{p.firstName} {p.lastName}</span>
            <span style={{ fontSize: 13, color: SUB }}>Not coming</span>
          </div>
        ))}
      </div>
    </>
  );
}

// MARK: - Step 4: Review

function Review({ print }: { print(kind: 'battingOrder' | 'coachesGuide'): void }) {
  const w = useWorkbench();
  const st = gameStatus(w);
  const rows: { label: string; meta: string; ok: boolean; step: Step }[] = [
    { label: 'Attendance', meta: `${st.here} of ${st.total} coming`, ok: true, step: 1 },
    { label: 'Batting order', meta: plural(st.here, 'batter'), ok: true, step: 2 },
    { label: 'Defense', meta: st.fpOk ? `All ${w.lineup.innings.length} innings pass fair play` : plural(st.issueCount, 'fair-play issue'), ok: st.fpOk, step: 3 },
  ];
  return (
    <>
      <StepTitle title="Review" hint="Check everything, finalize, then print what you need for the dugout." />
      <div style={{ borderRadius: 12, border: `1px solid ${BORDER}`, padding: '0 16px' }}>
        {rows.map((r, i) => (
          <div key={r.label} style={{ display: 'flex', alignItems: 'center', gap: 12, height: 56, borderTop: i ? '1px solid rgba(60,60,67,0.08)' : 'none' }}>
            <Icon name={r.ok ? 'checkmark.circle.fill' : 'exclamationmark.triangle.fill'} size={20} color={r.ok ? C.green : C.red} />
            <span style={{ flex: 1, fontSize: 14, fontWeight: 500 }}>{r.label}</span>
            <span style={{ fontSize: 13, color: r.ok ? SUB : C.red }}>{r.meta}</span>
            <button className="h-link" onClick={() => w.goStep(r.step)} style={{ fontSize: 14, fontWeight: 500, color: C.blue }}>Edit</button>
          </div>
        ))}
      </div>
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12, marginTop: 16 }}>
        <ExportCard icon="doc.richtext.fill" title="Coaches Guide PDF" detail="Every inning on one page, for the dugout." onClick={() => print('coachesGuide')} />
        <ExportCard icon="doc.text" title="Lineup card" detail="Batting order only, for the umpire." onClick={() => print('battingOrder')} />
      </div>
      {st.open > 0 && (
        <p style={{ fontSize: 13, color: C.orange, margin: '10px 2px 0' }}>
          {st.open} field {st.open === 1 ? 'spot is' : 'spots are'} still open. {st.open === 1 ? 'It prints' : 'They print'} blank.
        </p>
      )}
    </>
  );
}

function ExportCard({ icon, title, detail, onClick }: { icon: string; title: string; detail: string; onClick(): void }) {
  return (
    <button onClick={onClick} className="h-ring" style={{ display: 'flex', gap: 14, alignItems: 'flex-start', padding: 18, borderRadius: 12, border: `1px solid ${BORDER}`, textAlign: 'left' }}>
      <Icon name={icon} size={24} color={C.blue} />
      <span>
        <span style={{ display: 'block', fontSize: 15, fontWeight: 600 }}>{title}</span>
        <span style={{ display: 'block', fontSize: 13, color: SUB, marginTop: 2 }}>{detail}</span>
      </span>
    </button>
  );
}

// MARK: - Game details (opponent, date, time)

const pad = (n: number) => String(n).padStart(2, '0');
const dateValue = (d: Date) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
const timeValue = (d: Date) => `${pad(d.getHours())}:${pad(d.getMinutes())}`;

function GameModal({ onClose }: { onClose(): void }) {
  const w = useWorkbench();
  const [opponent, setOpponent] = useState(w.lineup.opponent);
  const [date, setDate] = useState(dateValue(w.lineup.gameDate));
  const [time, setTime] = useState(timeValue(w.lineup.gameDate));
  const valid = /^\d{4}-\d{2}-\d{2}$/.test(date) && /^\d{2}:\d{2}$/.test(time);
  const save = () => {
    if (!valid) return;
    const [y, m, d] = date.split('-').map(Number);
    const [hh, mm] = time.split(':').map(Number);
    const gameDate = new Date(y, m - 1, d, hh, mm);
    w.edit((l) => ({ ...l, opponent: opponent.trim(), gameDate }));
    onClose();
  };
  return (
    <Modal title="Game" onClose={onClose} width={440}
      footer={<span style={{ marginLeft: 'auto', display: 'flex', gap: 8 }}>
        <PillButton onClick={onClose}>Cancel</PillButton>
        <PillButton kind="primary" onClick={save} disabled={!valid}>Save</PillButton>
      </span>}>
      <form onSubmit={(e) => { e.preventDefault(); save(); }} style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
        <TextField label="Opponent" value={opponent} onChange={setOpponent} placeholder="Who you're playing" autoFocus />
        <div style={{ display: 'flex', gap: 10 }}>
          <TextField label="Date" type="date" value={date} onChange={setDate} />
          <TextField label="Time" type="time" value={time} onChange={setTime} width={140} />
        </div>
        <p style={{ margin: 0, fontSize: 13, color: SUB }}>The date sets which pitchers are rested, and prints on the lineup.</p>
        <button type="submit" hidden />
      </form>
    </Modal>
  );
}
