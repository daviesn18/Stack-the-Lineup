// One archived game, opened from Season stats › Games (iOS GameLogDetailView):
// game details, pitch counts, batting order, the positions played each
// inning, and notes. Pitch counts and notes can be added or fixed later, and
// the game can be deleted. Innings after the last one played are dimmed.
//
// Not on the web yet: iOS's "Reuse this game" (copy to the current game, save
// as a template), which waits for templates in the spring.

import { useEffect, useState, type ReactNode } from 'react';

import { displayName, type FieldPosition, type GameLog } from '@/core/model';
import { useTeam } from '@/data/teamStore';

import { Dialog, HeaderButton, Row } from './controls';
import { Icon } from './Icon';
import { countsToSave, overLimit, PitchCountList, type Counts, type Pitcher } from './PitchCounts';
import { PageHeader, PrimaryButton, SecondaryButton, SUB } from './Shell';
import { useWorkbench } from './state';
import { badgeColor, C, tint } from './theme';
import { card } from './ui';

export const gameTitle = (g: GameLog) => (g.opponent ? `vs ${g.opponent}` : 'Game');
const shortDate = (d: Date) => d.toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' });

interface Person { id: string; name: string; number: string }

/**
 * Everyone in the game: names from the roster as it was that day, with the
 * live roster covering anyone the snapshot lacks (a player added since, or an
 * imported game with no snapshot).
 */
function usePeople(log: GameLog) {
  const w = useWorkbench();
  const find = (id: string): Person => {
    const p = log.playerSnapshot.find((s) => s.id === id) ?? w.byId.get(id);
    return p ? { id, name: displayName(p), number: p.number } : { id, name: 'Former player', number: '' };
  };
  const batting = log.battingOrder.map(find);
  // The grid: batting order first, then anyone else on that day's roster or in the grid, by name.
  const others = new Set([...log.playerSnapshot.map((s) => s.id), ...log.innings.flatMap((inn) => Object.keys(inn.assignments))]);
  for (const id of log.battingOrder) others.delete(id);
  const grid = [...batting, ...[...others].map(find).sort((a, b) => a.name.localeCompare(b.name))];
  return { find, batting, grid };
}

type Open = 'pitches' | 'notes' | 'delete' | null;

export function GameLogDetail({ log }: { log: GameLog }) {
  const w = useWorkbench();
  const people = usePeople(log);
  const [open, setOpen] = useState<Open>(null);
  const pitches = Object.entries(log.pitchCounts).filter(([, n]) => n > 0).sort((a, b) => b[1] - a[1]);

  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', minWidth: 0, background: C.grouped }}>
      <PageHeader right={<SecondaryButton icon="trash" iconColor={C.red} onClick={() => setOpen('delete')}>Delete game</SecondaryButton>}>
        <button className="h-link" onClick={() => w.openGameLog(null)} style={{ display: 'flex', alignItems: 'center', gap: 2, fontSize: 15, color: C.blue }}>
          <Icon name="chevron.left" size={18} color={C.blue} />Games
        </button>
        <span style={{ fontSize: 15, fontWeight: 600, marginLeft: 8 }}>{gameTitle(log)}</span>
      </PageHeader>
      <div style={{ flex: 1, overflowY: 'auto' }}>
        <div style={{ maxWidth: 900, margin: '0 auto', padding: '24px 24px 36px', display: 'flex', flexDirection: 'column', gap: 26 }}>

          <Section title="Game">
            <Info label="Date">{log.gameDate.toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric', year: 'numeric' })}</Info>
            <Info label="Opponent">{log.opponent || 'No opponent'}</Info>
            <Info label="Innings played">{log.inningsPlayed} of {log.innings.length}</Info>
            <Info label="Archived">
              {log.archivedAt.toLocaleString('en-US', { month: 'short', day: 'numeric', year: 'numeric', hour: 'numeric', minute: '2-digit' })}
              {log.archivedBy ? ` by ${log.archivedBy}` : ''}
            </Info>
          </Section>

          <Section title="Pitch counts" action={pitches.length ? 'Edit' : 'Add'} onAction={() => setOpen('pitches')}>
            {pitches.length === 0
              ? <Empty icon="figure.baseball.pitcher" onClick={() => setOpen('pitches')}>No pitch counts recorded. Add them so this game counts toward pitcher rest.</Empty>
              : pitches.map(([id, n]) => (
                <Info key={id} label={people.find(id).name}>{n} {n === 1 ? 'pitch' : 'pitches'}</Info>
              ))}
          </Section>

          <Section title="Batting order">
            {people.batting.length === 0
              ? <div style={{ padding: '12px 16px', fontSize: 14, color: SUB }}>No batting order recorded.</div>
              : people.batting.map((s, i) => (
                <div key={s.id} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '10px 16px', fontSize: 15 }}>
                  <span className="num" style={{ width: 24, fontWeight: 600, color: SUB }}>{i + 1}.</span>
                  <span className="ellipsis" style={{ flex: 1 }}>{s.name}</span>
                  {s.number && <span className="num" style={{ fontSize: 13, color: SUB }}>#{s.number}</span>}
                </div>
              ))}
          </Section>

          <Section title="Positions">
            <PositionGrid log={log} players={people.grid} />
          </Section>

          <Section title="Notes" action={log.notes ? 'Edit' : 'Add'} onAction={() => setOpen('notes')}>
            {log.notes
              ? <div style={{ padding: '12px 16px', fontSize: 15, lineHeight: 1.45, whiteSpace: 'pre-wrap', overflowWrap: 'anywhere' }}>{log.notes}</div>
              : <Empty icon="doc.text" onClick={() => setOpen('notes')}>No notes recorded.</Empty>}
          </Section>
        </div>
      </div>

      {open === 'pitches' && <PitchCountsDialog log={log} onClose={() => setOpen(null)} />}
      {open === 'notes' && <NotesDialog log={log} onClose={() => setOpen(null)} />}
      {open === 'delete' && <DeleteDialog log={log} onClose={() => setOpen(null)} />}
    </div>
  );
}

function Section({ title, action, onAction, children }: { title: string; action?: string; onAction?(): void; children: ReactNode }) {
  return (
    <section>
      <div style={{ display: 'flex', alignItems: 'baseline', margin: '0 4px 8px' }}>
        <span style={{ fontSize: 13, fontWeight: 600 }}>{title}</span>
        {action && (
          <button className="h-link" onClick={onAction} style={{ marginLeft: 'auto', display: 'flex', alignItems: 'center', gap: 5, fontSize: 13, fontWeight: 500, color: C.blue }}>
            <Icon name={action === 'Add' ? 'plus.circle' : 'pencil'} size={14} color={C.blue} />{action}
          </button>
        )}
      </div>
      <div className="sep-rows" style={{ ...card, overflow: 'hidden' }}>{children}</div>
    </section>
  );
}

function Info({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 16, padding: '11px 16px', fontSize: 15 }}>
      <span className="ellipsis" style={{ flex: 1 }}>{label}</span>
      <span className="num" style={{ color: SUB, textAlign: 'right' }}>{children}</span>
    </div>
  );
}

function Empty({ icon, onClick, children }: { icon: string; onClick(): void; children: string }) {
  return (
    <button className="h-row" onClick={onClick} style={{ display: 'flex', alignItems: 'center', gap: 10, width: '100%', padding: '12px 16px', fontSize: 14, color: SUB, textAlign: 'left' }}>
      <Icon name={icon} size={18} color={C.gray1} />{children}
    </button>
  );
}

function PositionGrid({ log, players }: { log: GameLog; players: Person[] }) {
  const cols = `minmax(140px, 1.6fr) repeat(${log.innings.length}, minmax(44px, 1fr))`;
  return (
    <div style={{ overflowX: 'auto' }}>
      <div role="table" aria-label="Positions by inning" style={{ minWidth: 140 + 48 * log.innings.length }}>
        <div role="row" style={{ display: 'grid', gridTemplateColumns: cols, gap: 4, padding: '10px 12px 8px 16px', fontSize: 12, fontWeight: 600, color: SUB, boxShadow: `inset 0 -0.5px 0 ${C.sep}` }}>
          <span role="columnheader">Player</span>
          {log.innings.map((_, i) => (
            <span key={i} role="columnheader" style={{ textAlign: 'center', opacity: i < log.inningsPlayed ? 1 : 0.4 }}
              title={i < log.inningsPlayed ? undefined : 'Not played'}>{i + 1}</span>
          ))}
        </div>
        {players.map((s, r) => (
          <div key={s.id} role="row" style={{ display: 'grid', gridTemplateColumns: cols, gap: 4, alignItems: 'center', padding: '5px 12px 5px 16px', borderTop: r ? C.hair : 'none' }}>
            <span role="rowheader" className="ellipsis" style={{ fontSize: 14 }}>{s.name}</span>
            {log.innings.map((inn, i) => <Cell key={i} pos={inn.assignments[s.id]} played={i < log.inningsPlayed} label={`${s.name}, inning ${i + 1}`} />)}
          </div>
        ))}
      </div>
    </div>
  );
}

function Cell({ pos, played, label }: { pos: FieldPosition | undefined; played: boolean; label: string }) {
  if (!played || !pos) {
    return <span role="cell" aria-label={`${label}: ${played ? 'unassigned' : 'not played'}`} style={{ textAlign: 'center', fontSize: 13, color: C.label3 }}>—</span>;
  }
  const bench = pos === 'Bench';
  return (
    <span role="cell" aria-label={`${label}: ${pos}`}
      style={{ textAlign: 'center', fontSize: 12, fontWeight: 700, borderRadius: 6, padding: '5px 0', background: bench ? 'transparent' : tint(pos), color: bench ? C.label2 : badgeColor(pos) }}>
      {bench ? 'Bench' : pos}
    </span>
  );
}

// MARK: - Dialogs

function PitchCountsDialog({ log, onClose }: { log: GameLog; onClose(): void }) {
  const { updateGameLog } = useTeam();
  const w = useWorkbench();
  const people = usePeople(log);
  // Existing counts, or else whoever pitched in the innings played (iOS RetroactivePitchCountSheet).
  const [ids, setIds] = useState<string[]>(() => {
    const recorded = Object.entries(log.pitchCounts).filter(([, n]) => n > 0).sort((a, b) => b[1] - a[1]).map(([id]) => id);
    if (recorded.length) return recorded;
    const pitched: string[] = [];
    for (const inn of log.innings.slice(0, log.inningsPlayed)) {
      for (const [id, pos] of Object.entries(inn.assignments)) if (pos === 'P' && !pitched.includes(id)) pitched.push(id);
    }
    return pitched;
  });
  const [counts, setCounts] = useState<Counts>(() => ({ ...log.pitchCounts }));
  const tooMany = overLimit(ids, counts);
  const listed: Pitcher[] = ids.map((id) => ({ id, name: people.find(id).name }));
  const addable: Pitcher[] = people.grid.filter((p) => !ids.includes(p.id))
    .map((p) => ({ id: p.id, name: p.name })).sort((a, b) => a.name.localeCompare(b.name));

  const save = () => {
    if (tooMany.length) return;
    updateGameLog(log.id, { pitchCounts: countsToSave(ids, counts) });
    w.showToast(`Saved pitch counts for ${gameTitle(log)}`);
    onClose();
  };
  return (
    <Dialog title="Pitch counts" subtitle={`${gameTitle(log)} · ${shortDate(log.gameDate)}`} onClose={onClose} width={520}
      footer={<>
        <span style={{ flex: 1, fontSize: 12, color: SUB, lineHeight: 1.4 }}>Changes update pitcher rest from now on.</span>
        <SecondaryButton onClick={onClose}>Cancel</SecondaryButton>
        <PrimaryButton height={32} onClick={save} disabled={tooMany.length > 0}>Save</PrimaryButton>
      </>}>
      <form onSubmit={(e) => { e.preventDefault(); save(); }}>
        <div style={{ ...card, overflow: 'hidden' }}>
          <Row label="Pitches thrown" stacked help="Remove a pitcher to clear their count.">
            <PitchCountList pitchers={listed} addable={addable} counts={counts} onCounts={setCounts}
              onRemove={(id) => setIds(ids.filter((x) => x !== id))} onAdd={(id) => setIds([...ids, id])}
              empty="No pitchers listed. Add a pitcher to record a count." />
          </Row>
        </div>
        <button type="submit" hidden />
      </form>
    </Dialog>
  );
}

function NotesDialog({ log, onClose }: { log: GameLog; onClose(): void }) {
  const { updateGameLog } = useTeam();
  const w = useWorkbench();
  const [notes, setNotes] = useState(log.notes);
  const save = () => {
    updateGameLog(log.id, { notes });
    w.showToast(`Saved notes for ${gameTitle(log)}`);
    onClose();
  };
  return (
    <Dialog title="Game notes" subtitle={`${gameTitle(log)} · ${shortDate(log.gameDate)}`} onClose={onClose} width={520}
      footer={<>
        <span style={{ flex: 1 }} />
        <SecondaryButton onClick={onClose}>Cancel</SecondaryButton>
        <PrimaryButton height={32} onClick={save} disabled={notes.trim() === log.notes}>Save</PrimaryButton>
      </>}>
      <div>
        <textarea className="field" aria-label="Game notes" value={notes} onChange={(e) => setNotes(e.target.value)} rows={7} autoFocus
          placeholder="Score, standout moments, reminders for next time"
          style={{ width: '100%', borderRadius: 10, border: '1px solid rgba(60,60,67,0.14)', padding: '10px 12px', fontSize: 15, lineHeight: 1.45, outline: 'none', resize: 'vertical', fontFamily: 'inherit', background: '#fff' }} />
      </div>
    </Dialog>
  );
}

function DeleteDialog({ log, onClose }: { log: GameLog; onClose(): void }) {
  const { deleteGameLog } = useTeam();
  const w = useWorkbench();
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose(); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose]);
  const remove = () => {
    deleteGameLog(log.id);
    w.openGameLog(null);
    w.showToast(`Deleted ${gameTitle(log)}, ${shortDate(log.gameDate)}`);
  };
  return (
    <div onMouseDown={(e) => { if (e.target === e.currentTarget) onClose(); }}
      style={{ position: 'fixed', inset: 0, zIndex: 45, background: 'rgba(0,0,0,0.2)', display: 'grid', placeItems: 'center' }}>
      <div role="alertdialog" aria-modal aria-label="Delete this game?" className="pop"
        style={{ width: 360, background: '#fff', borderRadius: 14, padding: 20, boxShadow: '0 12px 32px rgba(0,0,0,0.2)' }}>
        <div style={{ fontSize: 15, fontWeight: 600 }}>Delete this game?</div>
        <div style={{ fontSize: 13, color: SUB, marginTop: 6, lineHeight: 1.4 }}>
          {gameTitle(log)} on {shortDate(log.gameDate)} will no longer count toward season stats or pitcher rest. This can&apos;t be undone.
        </div>
        <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 8, marginTop: 18 }}>
          <HeaderButton onClick={onClose}>Cancel</HeaderButton>
          <HeaderButton kind="danger" onClick={remove}>Delete</HeaderButton>
        </div>
      </div>
    </div>
  );
}
