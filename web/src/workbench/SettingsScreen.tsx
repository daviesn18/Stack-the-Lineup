// Team settings, from the team-settings handoff: a page with a section rail
// (Team, Fair play, Pitching). Every control edits a draft; the header counts
// the unsaved changes and offers Discard and Save. Leaving the page with
// changes asks first (see state.leave).

import { useEffect, useMemo, useState, type CSSProperties, type ReactNode } from 'react';

import { activeFieldPositions } from '@/core/fairPlay';
import { lastAssignedInning } from '@/core/lineupOps';
import { POSITION_NAMES, type FairPlayConfig, type FieldPosition } from '@/core/model';
import { useTeam } from '@/data/teamStore';

import { Icon } from './Icon';
import {
  CANVAS, ColorSwatches, Fade, GameLength, Group, HAIR, HeaderButton, Heading, Master, NumInput, Row, Seg, Stepper, TextInput, Toggle,
} from './controls';
import { PageHeader, SUB } from './Shell';
import { useWorkbench } from './state';
import {
  changeCount, clampToGame, draftFromTeam, draftProblems, littleLeagueRows, nextBracket, railStatus, resetFairPlay,
  sortBrackets, teamBracket, teamFromDraft, tierCells, type BracketRow, type SettingsDraft,
} from './teamSettings';
import { C } from './theme';

type Section = 'team' | 'fair' | 'pitch';

const INFIELD = new Set<FieldPosition>(['P', 'C', '1B', '2B', 'SS', '3B']);
const plural = (n: number, s: string) => `${n} ${s}${n === 1 ? '' : 's'}`;

export function SettingsScreen() {
  const w = useWorkbench();
  const { updateTeam } = useTeam();
  const saved = useMemo(() => draftFromTeam(w.team), [w.team]);
  const [draft, setDraft] = useState<SettingsDraft>(saved);
  const [section, setSection] = useState<Section>('team');
  const [confirmShorten, setConfirmShorten] = useState(false);

  const changes = changeCount(saved, draft);
  const problems = draftProblems(draft);
  const assignedThrough = lastAssignedInning(w.lineup);
  const cutsPositions = draft.gameLen < w.lineup.innings.length && assignedThrough > draft.gameLen;
  const set = (p: Partial<SettingsDraft>) => { setConfirmShorten(false); setDraft((d) => ({ ...d, ...p })); };

  const { setSettingsDirty } = w;
  useEffect(() => {
    setSettingsDirty(changes > 0);
    if (changes === 0) return;
    const warn = (e: BeforeUnloadEvent) => { e.preventDefault(); };
    window.addEventListener('beforeunload', warn);
    return () => window.removeEventListener('beforeunload', warn);
  }, [changes, setSettingsDirty]);
  useEffect(() => () => setSettingsDirty(false), [setSettingsDirty]);

  const save = (confirmed = false) => {
    if (problems.length) return;
    if (cutsPositions && !confirmed) { setConfirmShorten(true); return; }
    setConfirmShorten(false);
    const next = teamFromDraft(w.team, draft);
    updateTeam(next);
    setDraft(draftFromTeam(next));
    w.showToast('Team settings saved');
  };

  const status = railStatus(draft);
  const rail: [Section, string, string][] = [
    ['team', 'Team', 'person.3.fill'], ['fair', 'Fair play', 'checkmark.shield.fill'], ['pitch', 'Pitching', 'figure.baseball.pitcher'],
  ];

  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', minWidth: 0 }}>
      <PageHeader right={confirmShorten ? (
        <>
          <span style={{ fontSize: 13, color: C.label, maxWidth: 420 }}>
            Your lineup has positions through inning {assignedThrough}. Shortening to {draft.gameLen} removes them.
          </span>
          <HeaderButton onClick={() => setConfirmShorten(false)}>Cancel</HeaderButton>
          <HeaderButton kind="danger" onClick={() => save(true)}>Shorten and save</HeaderButton>
        </>
      ) : changes === 0 ? (
        <span style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 13, color: SUB }}>
          <Icon name="checkmark.circle.fill" size={14} color={C.green} />All changes saved
        </span>
      ) : (
        <span style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
          <span style={{ fontSize: 13, color: SUB }}>{plural(changes, 'unsaved change')}</span>
          <HeaderButton onClick={() => { setDraft(saved); setConfirmShorten(false); }}>Discard</HeaderButton>
          <HeaderButton kind="primary" onClick={() => save()} disabled={problems.length > 0} title={problems.join(' ') || undefined}>Save changes</HeaderButton>
        </span>
      )}>
        <span style={{ fontSize: 15, fontWeight: 600 }}>Team settings</span>
      </PageHeader>

      <div style={{ flex: 1, minHeight: 0, display: 'flex', background: CANVAS }}>
        <nav aria-label="Settings sections" style={{ width: 200, flexShrink: 0, padding: '24px 12px 24px 20px', display: 'flex', flexDirection: 'column', gap: 2 }}>
          {rail.map(([id, label, icon]) => {
            const on = section === id;
            return (
              <button key={id} onClick={() => setSection(id)} aria-current={on ? 'true' : undefined} className={on ? '' : 'h-rail'}
                style={{ display: 'flex', alignItems: 'flex-start', gap: 10, padding: '9px 10px', borderRadius: 8, width: '100%', textAlign: 'left', background: on ? '#fff' : 'transparent', boxShadow: on ? '0 1px 2px rgba(0,0,0,0.06)' : 'none' }}>
                <Icon name={icon} size={16} color={on ? C.blue : SUB} style={{ marginTop: 2 }} />
                <span style={{ minWidth: 0 }}>
                  <span style={{ display: 'block', fontSize: 14, fontWeight: 500 }}>{label}</span>
                  <span className="ellipsis" style={{ display: 'block', fontSize: 12, color: SUB }}>{status[id]}</span>
                </span>
              </button>
            );
          })}
        </nav>
        <div style={{ flex: 1, minWidth: 0, overflowY: 'auto', padding: '24px 32px 56px 12px' }}>
          <div style={{ maxWidth: 720, display: 'flex', flexDirection: 'column', gap: 24 }}>
            {section === 'team' && <TeamSection d={draft} set={set} />}
            {section === 'fair' && <FairSection d={draft} set={set} />}
            {section === 'pitch' && <PitchSection d={draft} set={set} />}
          </div>
        </div>
      </div>
    </div>
  );
}

type SectionProps = { d: SettingsDraft; set(p: Partial<SettingsDraft>): void };

// MARK: - Team

function TeamSection({ d, set }: SectionProps) {
  return (
    <>
      <Heading title="Team" sub="Name, color and length of games." />
      <Group label="Team info">
        <Row label="Team name"><TextInput value={d.name} onChange={(name) => set({ name })} placeholder="e.g. Mudcats 10U" label="Team name" /></Row>
        <Row label="Your name" help="See who finalized the lineup."><TextInput value={d.coach} onChange={(coach) => set({ coach })} placeholder="Coach name" label="Your name" /></Row>
        <Row label="Team color" help="Used in the team menu and on the Coaches Guide." stacked>
          <div style={{ marginTop: 12 }}><ColorSwatches value={d.color} onChange={(color) => set({ color })} /></div>
        </Row>
      </Group>
      <Group label="Games">
        <Row label="Game length" help="Changes the lineup you're building now. Archived games keep their original inning count.">
          <GameLength value={d.gameLen} onChange={(n) => set({ gameLen: n, fair: clampToGame(d.fair, n) })} />
        </Row>
      </Group>
    </>
  );
}

// MARK: - Fair play

function FairSection({ d, set }: SectionProps) {
  const f = d.fair;
  const len = d.gameLen;
  const patch = (p: Partial<FairPlayConfig>) => set({ fair: { ...f, ...p } });
  const field = activeFieldPositions(f);
  const chips: FieldPosition[] = ['P', 'C', '1B', '2B', 'SS', '3B', ...(f.outfielderCount === 4 ? ['LF', 'LCF', 'RCF', 'RF'] as const : ['LF', 'CF', 'RF'] as const)];
  const inn = (n: number) => plural(n, 'inning');
  return (
    <>
      <Heading title="Fair play" sub="The rules Auto-Fill follows and the lineup checks before you finalize." />
      <Master label="Fair play rules" help="Turn off to pause every rule for this team. Your settings are retained."
        on={d.fp} onChange={() => set({ fp: !d.fp })} />
      <Fade on={d.fp}>
        <Group label="Positions">
          <Row label="Positions in play" stacked
            help="Click P or C to take it off the field for coach pitch or tee ball. Anyone playing it now is unassigned when you save."
            aside={`${field.length} on the field`}>
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6, marginTop: 12 }}>
              {chips.map((pos) => {
                const toggle = pos === 'P' ? 'noPitcher' : pos === 'C' ? 'noCatcher' : null;
                const off = toggle ? f[toggle] : false;
                const style: CSSProperties = {
                  minWidth: 42, padding: '7px 0', borderRadius: 6, fontSize: 12, fontWeight: 700, textAlign: 'center',
                  transition: 'background-color .15s ease, box-shadow .15s ease',
                  background: off ? '#EFEFF4' : INFIELD.has(pos) ? C.blue : C.green,
                  color: off ? 'rgba(60,60,67,0.4)' : '#fff', textDecoration: off ? 'line-through' : undefined,
                  boxShadow: off ? 'inset 0 0 0 1px rgba(60,60,67,0.18)' : toggle ? '0 0 0 2px #fff, 0 0 0 3px rgba(0,122,255,0.35)' : undefined,
                };
                if (!toggle) return <span key={pos} style={style} title={POSITION_NAMES[pos]}>{pos}</span>;
                const name = POSITION_NAMES[pos].toLowerCase();
                return (
                  <button key={pos} role="switch" aria-checked={!off} aria-label={`${POSITION_NAMES[pos]} on the field`} style={style}
                    title={off ? `Put ${name} back on the field` : `Take ${name} off the field`}
                    onClick={() => patch({ [toggle]: !off })}>{pos}</button>
                );
              })}
            </div>
          </Row>
          <Row label="Outfielders">
            <Seg value={String(f.outfielderCount)} onChange={(v) => patch({ outfielderCount: Number(v) })}
              options={[['3', '3 · LF CF RF'], ['4', '4 · LF LCF RCF RF']]} label="Outfielders" />
          </Row>
        </Group>

        <Group label="Bench">
          <Row label="No back-to-back bench" help="Nobody sits two innings in a row.">
            <Toggle on={f.noConsecutiveBench} label="No back-to-back bench" onChange={() => patch({ noConsecutiveBench: !f.noConsecutiveBench })} />
          </Row>
          <Row label="Equal bench time" help="Nobody sits twice until everyone has sat once.">
            <Toggle on={f.equalBenchTime} label="Equal bench time" onChange={() => patch({ equalBenchTime: !f.equalBenchTime })} />
          </Row>
        </Group>

        <Group label="Fielding minimums">
          <Row label="Innings in the field" help={f.minimumFieldingInnings ? `Every player plays at least ${f.minimumFieldingInnings} of ${len} innings.` : 'Off. No minimum.'}>
            <Stepper value={f.minimumFieldingInnings} max={len} label="Innings in the field" onChange={(v) => patch({ minimumFieldingInnings: v })} />
          </Row>
          <Row label="Infield innings" help={f.minimumInfieldInnings ? `At least ${inn(f.minimumInfieldInnings)} at P, C, 1B, 2B, SS or 3B.` : 'Off. No infield minimum.'}>
            <Stepper value={f.minimumInfieldInnings} max={len} label="Infield innings" onChange={(v) => patch({ minimumInfieldInnings: v })} />
          </Row>
          <Row label="Outfield innings" help={f.minimumOutfieldInnings ? `At least ${inn(f.minimumOutfieldInnings)} in the outfield.` : 'Off. No outfield minimum.'}>
            <Stepper value={f.minimumOutfieldInnings} max={len} label="Outfield innings" onChange={(v) => patch({ minimumOutfieldInnings: v })} />
          </Row>
        </Group>

        <Group label="Catching and pitching">
          <Row label="Catcher to pitcher" help={f.catcherToPitcherThreshold ? `A player who caught ${inn(f.catcherToPitcherThreshold)} can't pitch in the same game.` : 'Off. Catchers can pitch later in the game.'}>
            <Stepper value={f.catcherToPitcherThreshold} max={len} label="Catcher to pitcher" onChange={(v) => patch({ catcherToPitcherThreshold: v })} />
          </Row>
          <Row label="Pitcher to catcher" help={f.pitcherToCatcherThreshold ? `A player who pitched ${inn(f.pitcherToCatcherThreshold)} can't catch in the same game.` : 'Off. Pitchers can catch later in the game.'}>
            <Stepper value={f.pitcherToCatcherThreshold} max={len} label="Pitcher to catcher" onChange={(v) => patch({ pitcherToCatcherThreshold: v })} />
          </Row>
        </Group>

        <Group label="Auto-Fill">
          <Row label="No repeat positions" help="Auto-Fill gives each player a different spot every inning. If there's no new spot, it repeats one rather than leave it open.">
            <Toggle on={f.noRepeatPositions} label="No repeat positions" onChange={() => patch({ noRepeatPositions: !f.noRepeatPositions })} />
          </Row>
        </Group>
      </Fade>

      <div style={{ display: 'flex', alignItems: 'center', gap: 16, padding: '0 4px' }}>
        <button className="h-reset" onClick={() => set({ fair: clampToGame(resetFairPlay(f), len), fp: true })}
          style={{ height: 32, padding: '0 14px', borderRadius: 8, background: '#fff', border: '1px solid rgba(255,59,48,0.35)', color: C.red, fontSize: 13, fontWeight: 500, flexShrink: 0 }}>
          Reset to defaults
        </button>
        <span style={{ fontSize: 13, color: SUB, lineHeight: 1.4 }}>No back-to-back bench on. 4 innings in the field, 1 infield and 1 outfield. Everything else off.</span>
      </div>
    </>
  );
}

// MARK: - Pitching

function PitchSection({ d, set }: SectionProps) {
  const w = useWorkbench();
  const mine = useMemo(() => teamBracket(w.players), [w.players]);
  const add = nextBracket(d.brackets);
  const setRow = (i: number, r: BracketRow) => set({ brackets: d.brackets.map((x, j) => (j === i ? r : x)) });
  return (
    <>
      <Heading title="Pitching" sub="Pitch counts from archived games set each pitcher's rest days." />
      <Master label="Pitch count rules" help="The lineup warns you when a pitcher still needs rest." on={d.pc} onChange={() => set({ pc: !d.pc })} />
      <Fade on={d.pc}>
        <Group label="Weekly cap">
          <Row label="Weekly pitch cap">
            <Toggle on={d.cap} label="Weekly pitch cap" onChange={() => set({ cap: !d.cap, capN: d.capN || 100 })} />
          </Row>
          <div style={{ opacity: d.cap ? 1 : 0.4, transition: 'opacity .2s ease' }}>
            <Row label="Most pitches per week">
              <NumInput value={d.capN} onChange={(capN) => set({ capN })} label="Most pitches per week" width={80} />
            </Row>
            <Row label="Cap resets" help={d.capReset === 'Calendar Week'
              ? 'Starts over every Monday.'
              : 'Counts any 7 days in a row. A game last Tuesday drops off this Tuesday.'}>
              <Seg value={d.capReset} onChange={(capReset) => set({ capReset })} label="Cap resets"
                options={[['Calendar Week', 'Every Monday'], ['Rolling 7 Days', 'Any 7 days']]} />
            </Row>
          </div>
        </Group>

        <section>
          <div style={{ display: 'flex', alignItems: 'baseline', gap: 12, padding: '0 4px', marginBottom: 8 }}>
            <span style={{ fontSize: 13, fontWeight: 600 }}>Age brackets</span>
            <span style={{ marginLeft: 'auto', fontSize: 12, color: SUB }}>Pitch count where each rest tier starts. Leave 3 or 4 blank to skip it.</span>
          </div>
          <div style={{ background: '#fff', borderRadius: 12, overflow: 'hidden' }}>
            <div style={{ ...GRID, background: '#FAFAFC', padding: '9px 18px', fontSize: 12, fontWeight: 600, color: SUB }}>
              <span>Ages</span>
              {['Daily max', '1 rest day', '2 rest days', '3 rest days', '4 rest days'].map((h) => <span key={h} style={{ textAlign: 'center' }}>{h}</span>)}
              <span />
            </div>
            {d.brackets.length === 0 && (
              <div style={{ padding: '14px 18px', borderTop: HAIR, fontSize: 14, color: SUB }}>
                No age brackets yet.{' '}
                <button className="h-link" onClick={() => set({ brackets: littleLeagueRows() })} style={{ color: C.blue, fontSize: 14 }}>Use Little League pitch counts</button>
              </div>
            )}
            {d.brackets.map((r, i) => (
              <BracketLine key={r.bracket} r={r} mine={r.bracket === mine} onChange={(x) => setRow(i, x)}
                onRemove={() => set({ brackets: d.brackets.filter((_, j) => j !== i) })} />
            ))}
            <button className={add ? 'h-row3' : ''} disabled={!add} onClick={() => add && set({ brackets: sortBrackets([...d.brackets, add]) })}
              style={{ display: 'flex', alignItems: 'center', gap: 8, width: '100%', padding: '12px 18px', borderTop: HAIR, fontSize: 14, fontWeight: 500, color: add ? C.blue : C.label3 }}>
              <Icon name="plus.circle.fill" size={18} color={add ? C.blue : C.label3} />
              {add ? 'Add age bracket' : 'Every age bracket is in the table'}
            </button>
          </div>
        </section>
      </Fade>
    </>
  );
}

const GRID: CSSProperties = { display: 'grid', gridTemplateColumns: '128px repeat(5, minmax(0,1fr)) 24px', columnGap: 10, alignItems: 'center' };

function BracketLine({ r, mine, onChange, onRemove }: { r: BracketRow; mine: boolean; onChange(r: BracketRow): void; onRemove(): void }) {
  const cells = tierCells(r);
  const setTier = (i: number, v: number | '') => { const t = [...r.t] as BracketRow['t']; t[i] = v; onChange({ ...r, t }); };
  const under = (children: ReactNode, color: string = SUB) => (
    <div className="num" style={{ fontSize: 11, color, textAlign: 'center', marginTop: 4, height: 14 }}>{children}</div>
  );
  return (
    <div style={{ ...GRID, alignItems: 'start', padding: '10px 18px 8px', borderTop: HAIR, background: mine ? 'rgba(0,122,255,0.03)' : undefined }}>
      <div style={{ paddingTop: 7 }}>
        <div style={{ fontSize: 14, fontWeight: 500 }}>Ages {r.bracket}</div>
        {mine && <span style={{ display: 'inline-block', marginTop: 2, fontSize: 11, fontWeight: 600, padding: '1px 7px', borderRadius: 999, background: 'rgba(0,122,255,0.12)', color: C.blue }}>Your team</span>}
      </div>
      <div>
        <NumInput value={r.max} onChange={(max) => onChange({ ...r, max })} label={`Ages ${r.bracket} daily max`} color={C.label} block />
        {under('per game')}
      </div>
      {r.t.map((v, i) => {
        const c = cells[i];
        return (
          <div key={i}>
            <NumInput value={v} onChange={(x) => setTier(i, x)} label={`Ages ${r.bracket}: ${i + 1} rest day${i ? 's' : ''} starts at`}
              placeholder="Skip" block maxWidth={76} fill={v === '' ? '#F7F7FA' : 'rgba(0,122,255,0.08)'} />
            {c.kind === 'skipped' ? under('Skipped', C.label3) : c.kind === 'check' ? under('Check order', C.red) : under(c.text)}
          </div>
        );
      })}
      <button className="h-remove" title="Remove bracket" aria-label={`Remove ages ${r.bracket}`} onClick={onRemove}
        style={{ display: 'grid', placeItems: 'center', height: 34 }}>
        <Icon name="minus.circle.fill" size={18} color={C.red} />
      </button>
    </div>
  );
}

// MARK: - Pieces

/** "Discard unsaved changes?" when leaving Team settings with edits. */
export function LeaveDialog() {
  const w = useWorkbench();
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') w.resolveLeave(false); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [w]);
  return (
    <div onMouseDown={(e) => { if (e.target === e.currentTarget) w.resolveLeave(false); }}
      style={{ position: 'fixed', inset: 0, zIndex: 45, background: 'rgba(0,0,0,0.2)', display: 'grid', placeItems: 'center' }}>
      <div role="alertdialog" aria-modal aria-label="Discard unsaved changes?" className="pop"
        style={{ width: 340, background: '#fff', borderRadius: 14, padding: 20, boxShadow: '0 12px 32px rgba(0,0,0,0.2)' }}>
        <div style={{ fontSize: 15, fontWeight: 600 }}>Discard unsaved changes?</div>
        <div style={{ fontSize: 13, color: SUB, marginTop: 6, lineHeight: 1.4 }}>Your team settings edits haven&apos;t been saved.</div>
        <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 8, marginTop: 18 }}>
          <HeaderButton onClick={() => w.resolveLeave(false)}>Keep editing</HeaderButton>
          <HeaderButton kind="danger" onClick={() => w.resolveLeave(true)}>Discard</HeaderButton>
        </div>
      </div>
    </div>
  );
}
