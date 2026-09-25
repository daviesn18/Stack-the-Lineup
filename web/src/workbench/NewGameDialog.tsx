// New game: set up the next game, and optionally archive the last one first
// (innings played, pitch counts and notes, as the iOS Archive Game sheet
// does). The next game leads; archiving is a switch that expands in place.
// Not in the handoffs yet, so it's built from the team-settings pieces:
// grouped rows, switch, stepper and number inputs, in the roster panel's
// dialog frame. The pitch count list is shared with History (PitchCounts).

import { useMemo, useState } from 'react';

import { displayName } from '@/core/lineupOps';
import { hasGameDetails, pitchersIn } from '@/core/newGame';
import { useTeam } from '@/data/teamStore';

import {
  dateValue, DateTimeInputs, Dialog, fromInputs, Group, Row, Stepper, TextInput, timeValue, Toggle,
} from './controls';
import { gameWhen } from './gameStatus';
import { countsToSave, MAX_PITCHES, overLimit, PitchCountList, type Counts } from './PitchCounts';
import { PrimaryButton, SecondaryButton, SUB } from './Shell';
import { useWorkbench } from './state';

const WEEK = 7 * 86_400_000;

/** A week after this game (or after today, if this game is past), at the same time of day. */
function defaultNextDate(current: Date): Date {
  const base = current.getTime() > Date.now() ? new Date(current) : new Date();
  const d = new Date(base.getTime() + WEEK);
  d.setHours(current.getHours(), current.getMinutes(), 0, 0);
  return d;
}

export function NewGameDialog() {
  const w = useWorkbench();
  const { startNewGame } = useTeam();
  const l = w.lineup;
  const close = () => w.setNewGameOpen(false);
  const canArchive = hasGameDetails(l);
  const [archive, setArchive] = useState(false);
  const [innings, setInnings] = useState(l.innings.length);
  const [pitchers, setPitchers] = useState<string[]>(() => pitchersIn(l).filter((id) => w.byId.has(id)));
  const [counts, setCounts] = useState<Counts>({});
  const [notes, setNotes] = useState('');
  const next = defaultNextDate(l.gameDate);
  const [opponent, setOpponent] = useState('');
  const [date, setDate] = useState(dateValue(next));
  const [time, setTime] = useState(timeValue(next));

  const gameDate = fromInputs(date, time);
  const tooMany = overLimit(pitchers, counts);
  const ready = !!gameDate && (!archive || !canArchive || tooMany.length === 0);
  const addable = useMemo(() => w.players.filter((p) => !pitchers.includes(p.id)), [w.players, pitchers]);
  const nextTitle = opponent.trim() ? `vs ${opponent.trim()}` : 'the next game';
  const thisGame = l.opponent ? `vs ${l.opponent}` : 'this game';
  const day = gameWhen(l.gameDate).split(' · ')[0];

  const archiving = archive && canArchive;

  const start = () => {
    if (!ready || !gameDate) return;
    const pitchCounts = countsToSave(pitchers, counts);
    startNewGame({ opponent, gameDate }, archiving ? { inningsPlayed: innings, notes, pitchCounts } : undefined);
    close();
    w.goStep(1);
    w.showToast(archiving ? `Archived ${l.opponent ? thisGame : `the ${day} game`}. Set up ${nextTitle}.` : `Set up ${nextTitle}.`);
  };

  return (
    <Dialog title="New game" subtitle="Set up your next game" onClose={close} width={600}
      footer={<>
        <span style={{ flex: 1, fontSize: 12, color: SUB, lineHeight: 1.4 }}>The batting order carries over.</span>
        <SecondaryButton onClick={close}>Cancel</SecondaryButton>
        <PrimaryButton height={32} icon={archiving ? 'archivebox' : 'calendar.badge.plus'} onClick={start} disabled={!ready}
          title={!gameDate ? 'Pick a date and time' : tooMany.length ? `Pitch counts go up to ${MAX_PITCHES}` : undefined}>
          {archiving ? 'Archive and start new game' : 'Start new game'}
        </PrimaryButton>
      </>}>
      <form onSubmit={(e) => { e.preventDefault(); start(); }} style={{ display: 'flex', flexDirection: 'column', gap: 24 }}>
        <Group label="Next game">
          <Row label="Opponent"><TextInput value={opponent} onChange={setOpponent} placeholder="Who you're playing" label="Next opponent" width={240} autoFocus /></Row>
          <Row label="Date and time" help="Sets which pitchers are rested.">
            <DateTimeInputs date={date} time={time} onDate={setDate} onTime={setTime} />
          </Row>
        </Group>
        {canArchive && (
          <Group label={l.opponent ? `Last game · vs ${l.opponent}, ${day}` : `Last game · ${day}`}>
            <Row label={`Archive ${thisGame}`}
              help={archiving ? 'Saves its positions, innings played and pitch counts to season history.'
                : 'Season stats and pitcher rest only count archived games.'}>
              <Toggle on={archiving} label={`Archive ${thisGame}`} onChange={() => setArchive(!archive)} />
            </Row>
            {!archiving && (
              <div style={{ margin: '0 18px 14px', padding: '10px 12px', borderRadius: 8, background: 'rgba(255,149,0,0.10)', fontSize: 13, lineHeight: 1.4, color: 'rgb(133,79,10)' }}>
                Without archiving, {thisGame}&apos;s positions are cleared and it won&apos;t count toward season stats or pitcher rest.
              </div>
            )}
            {archiving && (
              <>
                <Row label="Innings played" help="Only innings played count toward season stats.">
                  <Stepper value={innings} min={1} max={l.innings.length} onChange={setInnings} label="Innings played" />
                </Row>
                <Row label="Pitch counts" stacked help="Pitches thrown today.">
                  <PitchCountList
                    pitchers={pitchers.flatMap((id) => {
                      const p = w.byId.get(id);
                      return p ? [{ id, name: displayName(p), warning: p.leagueAge === undefined ? 'Add a league age on the Roster page to track rest' : undefined }] : [];
                    })}
                    addable={addable.map((p) => ({ id: p.id, name: displayName(p) }))}
                    counts={counts} onCounts={setCounts}
                    onRemove={(id) => setPitchers(pitchers.filter((x) => x !== id))}
                    onAdd={(id) => setPitchers([...pitchers, id])}
                    empty="Nobody pitched in this lineup. Add a pitcher to record a count." />
                </Row>
                <Row label="Notes" stacked>
                  <textarea className="field" aria-label="Game notes" value={notes} onChange={(e) => setNotes(e.target.value)} rows={3}
                    placeholder="Score, standout moments, reminders (optional)"
                    style={{ width: '100%', marginTop: 10, borderRadius: 8, border: '1px solid rgba(60,60,67,0.14)', padding: '8px 10px', fontSize: 14, outline: 'none', resize: 'vertical', fontFamily: 'inherit' }} />
                </Row>
              </>
            )}
          </Group>
        )}
        <button type="submit" hidden />
      </form>
    </Dialog>
  );
}
