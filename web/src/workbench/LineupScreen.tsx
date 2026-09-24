// Lineup: the game card (date, opponent, status), the batting order with
// attendance switches, and the two printouts.

import { useState } from 'react';

import { openPositions } from '@/core/fairPlay';
import { restoreAbsent, toggleAbsent } from '@/core/lineupOps';
import { battingOrderPdf, coachesGuidePdf, pdfFilename } from '@/print/lineupPdf';
import { openPdfTab } from '@/print/openPdf';

import { Grip } from './Shell';
import { Icon } from './Icon';
import { reorderTo, useWorkbench } from './state';
import { C } from './theme';
import { card, Modal, PillButton, Switch, TextField } from './ui';

export function LineupScreen() {
  const w = useWorkbench();
  const [gameOpen, setGameOpen] = useState(false);
  const [printError, setPrintError] = useState<string | null>(null);
  const done = w.lineup.status === 'finalized';
  const absent = w.players.filter((p) => w.lineup.absentPlayerIDs.includes(p.id));
  const rows = [...w.active, ...absent];
  const clear = w.issues.length === 0;
  const red = w.issues.some((i) => i.severity === 'red');
  const open = w.lineup.innings.reduce((n, _, i) => n + openPositions(w.lineup, i, w.players, w.team.fairPlayConfig).length, 0);

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

  return (
    <div style={{ flex: 1, overflowY: 'auto' }}>
      <div style={{ maxWidth: 900, margin: '0 auto', padding: '22px 28px 36px' }}>
        <div style={card}>
          <button className="h-row2" onClick={() => setGameOpen(true)} aria-label="Edit game date and opponent"
            style={{ display: 'flex', alignItems: 'center', gap: 14, width: '100%', padding: '14px 16px', borderRadius: '12px 12px 0 0' }}>
            <Icon name="calendar" size={24} color={C.blue} />
            <span style={{ flex: 1, minWidth: 0 }}>
              <span style={{ display: 'block', fontSize: 20, fontWeight: 600 }}>
                {w.lineup.gameDate.toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' })}
                <span style={{ fontWeight: 400, color: w.lineup.opponent ? C.label2 : C.label3 }}> · {w.lineup.opponent ? `vs ${w.lineup.opponent}` : 'Add opponent'}</span>
              </span>
              <span style={{ display: 'inline-block', marginTop: 6, fontSize: 13, fontWeight: 500, padding: '2px 8px', borderRadius: 999, background: done ? 'rgba(52,199,89,0.15)' : C.gray5, color: done ? C.green : C.label2 }}>
                {done ? 'Finalized' : 'Draft'}
              </span>
            </span>
            <Icon name="chevron.right" size={14} color={C.label3} />
          </button>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', borderTop: C.hair }}>
            <button disabled title="Coming soon" style={{ padding: '12px 0', display: 'flex', justifyContent: 'center', alignItems: 'center', gap: 8, fontSize: 17, color: C.blue, opacity: 0.4 }}>
              <Icon name="calendar" size={18} color={C.blue} />Schedule
            </button>
            <button disabled title="Coming soon" style={{ padding: '12px 0', display: 'flex', justifyContent: 'center', alignItems: 'center', gap: 8, fontSize: 17, color: C.blue, borderLeft: C.hair, opacity: 0.4 }}>
              <Icon name="doc.text" size={18} color={C.blue} />Template
            </button>
          </div>
        </div>

        <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '24px 4px 10px' }}>
          <span style={{ fontSize: 20, fontWeight: 600, color: C.label2 }}>Batting Order</span>
          <Icon name={clear ? 'checkmark.shield.fill' : 'exclamationmark.triangle.fill'} size={17} color={clear ? C.green : red ? C.red : C.orange} />
          <span style={{ fontSize: 16, fontWeight: 500, color: clear ? C.green : red ? C.red : C.orange }}>
            {clear ? 'Fair play OK' : `${w.issues.length} fair-play issue${w.issues.length > 1 ? 's' : ''}`}
          </span>
          <span style={{ marginLeft: 'auto', fontSize: 13, color: C.label2 }}>Drag rows to reorder · toggle to mark absent</span>
        </div>
        <div style={{ ...card, overflow: 'hidden' }}>
          {rows.map((p, i) => {
            const isAbsent = i >= w.active.length;
            const key = `o-${p.id}`;
            const orderDrag = w.dragging?.from === 'order';
            return (
              <div key={p.id} {...(isAbsent ? {} : w.dragProps(p.id, 'order'))}
                {...(isAbsent ? {} : w.dropProps(key, (src) => w.edit((l) => reorderTo(l, w.active, src.pid, p.id)), (src) => src.from === 'order'))}
                style={{ height: 52, display: 'flex', alignItems: 'center', gap: 12, padding: '0 16px 0 14px', borderTop: i ? C.hair : 'none',
                  boxShadow: w.dropKey === key && orderDrag ? `inset 0 2px 0 ${C.blue}` : 'none', opacity: w.dragging?.pid === p.id && orderDrag ? 0.4 : 1 }}>
                <span style={{ opacity: isAbsent ? 0 : 1 }}><Grip /></span>
                <span className="num" style={{ width: 28, fontSize: 18, fontWeight: 600 }}>{isAbsent ? '' : `${i + 1}.`}</span>
                <span className="ellipsis" style={{ flex: 1, fontSize: 18, color: isAbsent ? C.label2 : C.label, textDecoration: isAbsent ? 'line-through' : 'none' }}>{p.firstName} {p.lastName}</span>
                {p.number && <span className="num" style={{ fontSize: 15, color: C.label2 }}>#{p.number}</span>}
                <Switch on={!isAbsent} label={`${p.firstName} ${p.lastName} is here`}
                  onChange={() => w.edit((l) => (isAbsent ? restoreAbsent(l, p.id) : toggleAbsent(l, p.id)))} />
              </div>
            );
          })}
          {rows.length === 0 && <div style={{ padding: 16, color: C.label2 }}>Add players on the Players screen.</div>}
        </div>

        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 14, marginTop: 20 }}>
          <PrintButton icon="doc.text" onClick={() => print('battingOrder')}>Batting Order</PrintButton>
          <PrintButton icon="doc.richtext.fill" onClick={() => print('coachesGuide')}>Coaches Guide</PrintButton>
        </div>
        <p style={{ fontSize: 13, color: open ? C.orange : C.label2, margin: '10px 4px 0' }}>
          {open
            ? `${open} field ${open === 1 ? 'spot is' : 'spots are'} still open. ${open === 1 ? 'It prints' : 'They print'} as blank.`
            : 'Opens a US Letter PDF in a new tab, ready to print or save.'}
        </p>
        {printError && <p role="alert" style={{ fontSize: 13, color: C.red, margin: '6px 4px 0' }}>{printError}</p>}
      </div>
      {gameOpen && <GameModal onClose={() => setGameOpen(false)} />}
    </div>
  );
}

function PrintButton({ icon, children, onClick }: { icon: string; children: string; onClick(): void }) {
  return (
    <button className="h-bright" onClick={onClick}
      style={{ height: 50, borderRadius: 14, background: C.blue, color: '#fff', fontSize: 17, fontWeight: 600, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8 }}>
      <Icon name={icon} size={18} color="#fff" />{children}
    </button>
  );
}

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
        <p style={{ margin: 0, fontSize: 13, color: C.label2 }}>The date sets which pitchers are rested, and prints on the lineup.</p>
        <button type="submit" hidden />
      </form>
    </Modal>
  );
}
