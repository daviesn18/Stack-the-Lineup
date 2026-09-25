// New game: finish the current game (archive it to season history with
// innings played, pitch counts and notes, as the iOS Archive Game sheet does)
// and set up the next one in the same step. Not in the handoffs yet, so it's
// built from the team-settings pieces: grouped rows, switch, stepper and
// number inputs, in the roster panel's dialog frame.

import { useMemo, useState } from 'react';

import { displayName } from '@/core/lineupOps';
import { hasGameDetails, pitchersIn } from '@/core/newGame';
import { useTeam } from '@/data/teamStore';

import {
  dateValue, DateTimeInputs, Dialog, Fade, fromInputs, Group, HAIR, NumInput, Row, Stepper, TextInput, timeValue, Toggle,
} from './controls';
import { Icon } from './Icon';
import { gameWhen } from './gameStatus';
import { PrimaryButton, SecondaryButton, SUB } from './Shell';
import { useWorkbench } from './state';
import { C } from './theme';

const WEEK = 7 * 86_400_000;
const MAX_PITCHES = 200;

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
  const [archive, setArchive] = useState(canArchive);
  const [innings, setInnings] = useState(l.innings.length);
  const [pitchers, setPitchers] = useState<string[]>(() => pitchersIn(l).filter((id) => w.byId.has(id)));
  const [counts, setCounts] = useState<Record<string, number | ''>>({});
  const [notes, setNotes] = useState('');
  const next = defaultNextDate(l.gameDate);
  const [opponent, setOpponent] = useState('');
  const [date, setDate] = useState(dateValue(next));
  const [time, setTime] = useState(timeValue(next));

  const gameDate = fromInputs(date, time);
  const tooMany = pitchers.filter((id) => Number(counts[id] || 0) > MAX_PITCHES);
  const ready = !!gameDate && (!archive || tooMany.length === 0);
  const addable = useMemo(() => w.players.filter((p) => !pitchers.includes(p.id)), [w.players, pitchers]);
  const nextTitle = opponent.trim() ? `vs ${opponent.trim()}` : 'the next game';
  const thisGame = l.opponent ? `vs ${l.opponent}` : 'this game';
  const day = gameWhen(l.gameDate).split(' · ')[0];

  const start = () => {
    if (!ready || !gameDate) return;
    const pitchCounts = Object.fromEntries(pitchers.map((id) => [id, Number(counts[id] || 0)]));
    startNewGame({ opponent, gameDate }, archive && canArchive ? { inningsPlayed: innings, notes, pitchCounts } : undefined);
    close();
    w.goStep(1);
    w.showToast(archive && canArchive ? `Archived ${l.opponent ? thisGame : `the ${day} game`}. Set up ${nextTitle}.` : `Set up ${nextTitle}.`);
  };

  return (
    <Dialog title="New game" subtitle={canArchive ? `Finish ${thisGame} and set up the next one` : 'Set up your next game'} onClose={close} width={600}
      footer={<>
        <span style={{ flex: 1, fontSize: 12, color: SUB, lineHeight: 1.4 }}>The batting order carries over. Everyone starts as present.</span>
        <SecondaryButton onClick={close}>Cancel</SecondaryButton>
        <PrimaryButton height={32} icon="calendar.badge.plus" onClick={start} disabled={!ready}
          title={!gameDate ? 'Pick a date and time' : tooMany.length ? `Pitch counts go up to ${MAX_PITCHES}` : undefined}>
          Start new game
        </PrimaryButton>
      </>}>
      <form onSubmit={(e) => { e.preventDefault(); start(); }} style={{ display: 'flex', flexDirection: 'column', gap: 24 }}>
        <Group label={l.opponent ? `This game · vs ${l.opponent}, ${day}` : `This game · ${day}`}>
          <Row label="Save to season history"
            help={!canArchive ? 'Nothing to save yet: no opponent or positions.'
              : archive ? 'Positions, innings played and pitch counts go into season stats and pitcher rest.'
                : "This game's positions are cleared without saving."}>
            <span style={{ opacity: canArchive ? 1 : 0.4, pointerEvents: canArchive ? undefined : 'none' }}>
              <Toggle on={archive && canArchive} label="Save to season history" onChange={() => setArchive(!archive)} />
            </span>
          </Row>
        </Group>

        {canArchive && (
          <Fade on={archive}>
            <Group label="Game summary">
              <Row label="Innings played" help="Only innings played count toward season stats.">
                <Stepper value={innings} min={1} max={l.innings.length} onChange={setInnings} label="Innings played" />
              </Row>
              <Row label="Pitch counts" stacked help="Pitches thrown today. They set each pitcher's rest days.">
                <div style={{ marginTop: 10, display: 'flex', flexDirection: 'column' }}>
                  {pitchers.length === 0 && <div style={{ fontSize: 13, color: SUB, padding: '6px 0' }}>Nobody pitched in this lineup. Add a pitcher to record a count.</div>}
                  {pitchers.map((id) => {
                    const p = w.byId.get(id);
                    if (!p) return null;
                    const over = tooMany.includes(id);
                    return (
                      <div key={id} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '8px 0', borderTop: HAIR }}>
                        <span style={{ flex: 1, minWidth: 0 }}>
                          <span className="ellipsis" style={{ display: 'block', fontSize: 14 }}>{displayName(p)}</span>
                          {over ? <span style={{ display: 'block', fontSize: 12, color: C.red }}>Up to {MAX_PITCHES} pitches</span>
                            : p.leagueAge === undefined && <span style={{ display: 'block', fontSize: 12, color: C.orange }}>Add a league age on the Roster page to track rest</span>}
                        </span>
                        <NumInput value={counts[id] ?? ''} onChange={(v) => setCounts({ ...counts, [id]: v })} label={`${displayName(p)} pitches`} placeholder="0" width={72} />
                        <button type="button" className="h-remove" title="Remove pitcher" aria-label={`Remove ${displayName(p)}`}
                          onClick={() => setPitchers(pitchers.filter((x) => x !== id))} style={{ display: 'grid', placeItems: 'center' }}>
                          <Icon name="minus.circle.fill" size={18} color={C.red} />
                        </button>
                      </div>
                    );
                  })}
                  {addable.length > 0 && (
                    <label className="h-link" style={{ position: 'relative', display: 'flex', alignItems: 'center', gap: 8, paddingTop: 8, borderTop: HAIR, fontSize: 14, fontWeight: 500, color: C.blue, cursor: 'pointer' }}>
                      <Icon name="plus.circle.fill" size={18} color={C.blue} />Add pitcher
                      <select aria-label="Add pitcher" value="" onChange={(e) => e.target.value && setPitchers([...pitchers, e.target.value])}
                        style={{ position: 'absolute', inset: 0, opacity: 0, cursor: 'pointer' }}>
                        <option value="">Add pitcher</option>
                        {addable.map((p) => <option key={p.id} value={p.id}>{displayName(p)}</option>)}
                      </select>
                    </label>
                  )}
                </div>
              </Row>
              <Row label="Notes" stacked>
                <textarea className="field" aria-label="Game notes" value={notes} onChange={(e) => setNotes(e.target.value)} rows={3}
                  placeholder="Score, standout moments, reminders (optional)"
                  style={{ width: '100%', marginTop: 10, borderRadius: 8, border: '1px solid rgba(60,60,67,0.14)', padding: '8px 10px', fontSize: 14, outline: 'none', resize: 'vertical', fontFamily: 'inherit' }} />
              </Row>
            </Group>
          </Fade>
        )}

        <Group label="Next game">
          <Row label="Opponent"><TextInput value={opponent} onChange={setOpponent} placeholder="Who you're playing" label="Next opponent" width={240} /></Row>
          <Row label="Date and time" help="Sets which pitchers are rested, and prints on the lineup.">
            <DateTimeInputs date={date} time={time} onDate={setDate} onTime={setTime} />
          </Row>
        </Group>
        <button type="submit" hidden />
      </form>
    </Dialog>
  );
}
