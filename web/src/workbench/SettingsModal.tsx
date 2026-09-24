// Team settings: the iOS Edit Team sheet with its Fair Play Rules and
// Pitching Rules sheets folded in as three tabs. Everything is a draft until
// Save; Cancel or Esc drops it. Shortening the game when the lineup has
// positions past the new last inning asks first, as on iOS.

import { useState, type CSSProperties, type ReactNode } from 'react';

import { lastAssignedInning } from '@/core/lineupOps';
import {
  defaultFairPlayConfig, defaultPitchingConfig, type FairPlayConfig, type PitchingAgeBracket, type PitchingConfig,
  type PitchingLimits,
} from '@/core/model';
import { applyLittleLeaguePreset } from '@/core/pitching';
import { useTeam } from '@/data/teamStore';

import { Icon } from './Icon';
import { useWorkbench } from './state';
import { C } from './theme';
import { Modal, PillButton, Segmented, Switch } from './ui';

type Tab = 'team' | 'fairPlay' | 'pitching';

const COLORS = [
  'FF3B30', 'FF9500', 'FFCC00', '34C759', '30B0C7', '007AFF', '5856D6', 'AF52DE', 'FF2D55', 'A2845E', '8E8E93', '000000',
];
const BRACKETS: PitchingAgeBracket[] = ['7-8', '9-10', '11-12', '13-14', '15-16'];

/** Every fairness rule off. The field itself (no pitcher/catcher, outfielders) is left as it is. */
const rulesOff = (c: FairPlayConfig): FairPlayConfig => ({
  ...c, noConsecutiveBench: false, noConsecutivePosition: false, equalBenchTime: false, noRepeatPositions: false,
  minimumFieldingInnings: 0, minimumInfieldInnings: 0, minimumOutfieldInnings: 0,
  catcherToPitcherThreshold: 0, pitcherToCatcherThreshold: 0,
});
const anyRuleOn = (c: FairPlayConfig) => JSON.stringify(rulesOff(c)) !== JSON.stringify(c);

export function SettingsModal({ onClose }: { onClose(): void }) {
  const w = useWorkbench();
  const { updateTeam } = useTeam();
  const [tab, setTab] = useState<Tab>('team');
  const [name, setName] = useState(w.team.name);
  const [color, setColor] = useState(w.team.colorHex.toUpperCase());
  const [coach, setCoach] = useState(w.team.coachName);
  const [innings, setInnings] = useState(w.team.gameInningCount);
  const [fair, setFair] = useState<FairPlayConfig>(w.team.fairPlayConfig);
  const [pitch, setPitch] = useState<PitchingConfig>(w.team.pitchingConfig);
  const [confirmShorten, setConfirmShorten] = useState(false);

  const assignedThrough = lastAssignedInning(w.lineup);
  const cutsPositions = innings < w.lineup.innings.length && assignedThrough > innings;
  const valid = name.trim().length > 0;

  const save = (confirmed = false) => {
    if (!valid) return;
    if (cutsPositions && !confirmed) { setConfirmShorten(true); return; }
    updateTeam({
      ...w.team, name: name.trim(), colorHex: color, coachName: coach.trim(), gameInningCount: innings,
      fairPlayConfig: fair, pitchingConfig: pitch,
    });
    w.showToast('Settings saved');
    onClose();
  };

  const footer = confirmShorten ? (
    <>
      <span style={{ flex: 1, fontSize: 13, lineHeight: '18px', color: C.label }}>
        Your lineup has positions through inning {assignedThrough}. Shortening to {innings} removes them.
      </span>
      <PillButton onClick={() => setConfirmShorten(false)}>Cancel</PillButton>
      <PillButton kind="danger" onClick={() => save(true)}>Shorten to {innings} innings</PillButton>
    </>
  ) : (
    <span style={{ marginLeft: 'auto', display: 'flex', gap: 8 }}>
      <PillButton onClick={onClose}>Cancel</PillButton>
      <PillButton kind="primary" onClick={() => save()} disabled={!valid}>Save</PillButton>
    </span>
  );

  return (
    <Modal title="Team settings" onClose={onClose} width={640} footer={footer}>
      <Segmented<Tab> value={tab} onChange={setTab} options={[['team', 'Team'], ['fairPlay', 'Fair Play'], ['pitching', 'Pitching']]} />
      <div style={{ marginTop: 18 }}>
        {tab === 'team' && (
          <>
            <Group header="Team info">
              <Row label="Team name">
                <TextInput value={name} onChange={setName} placeholder="e.g. Yankees" width={260} autoFocus />
              </Row>
              <Row label="Your name" note="Shows who finalized the lineup.">
                <TextInput value={coach} onChange={setCoach} placeholder="Coach name" width={260} />
              </Row>
              <Row label="Team color" stacked>
                <ColorChoice value={color} onChange={setColor} />
              </Row>
            </Group>
            <Group header="Game settings" footer="Changes the lineup you're building now. Past archived games keep their original inning count.">
              <Row label="Game length" stacked>
                <div role="radiogroup" aria-label="Game length" style={{ display: 'grid', gridTemplateColumns: 'repeat(7, 1fr)', gap: 6 }}>
                  {[3, 4, 5, 6, 7, 8, 9].map((n) => {
                    const on = n === innings;
                    return (
                      <button key={n} role="radio" aria-checked={on} onClick={() => { setInnings(n); setConfirmShorten(false); }}
                        className={on ? '' : 'h-dim'}
                        style={{ height: 40, borderRadius: 9, fontSize: 16, fontWeight: 600, textAlign: 'center', background: on ? C.blue : C.gray6, color: on ? '#fff' : C.label }}>
                        {n}
                      </button>
                    );
                  })}
                </div>
                <div style={{ fontSize: 13, color: C.label2, marginTop: 6 }}>{innings} innings</div>
              </Row>
            </Group>
          </>
        )}
        {tab === 'fairPlay' && <FairPlayTab c={fair} set={setFair} />}
        {tab === 'pitching' && <PitchingTab c={pitch} set={setPitch} />}
      </div>
    </Modal>
  );
}

// MARK: - Fair Play

function FairPlayTab({ c, set }: { c: FairPlayConfig; set(c: FairPlayConfig): void }) {
  const on = anyRuleOn(c);
  const patch = (p: Partial<FairPlayConfig>) => set({ ...c, ...p });
  const toggle = (key: keyof FairPlayConfig) => patch({ [key]: !c[key] });
  return (
    <>
      <Group footer="Turn off to switch off every fair play rule for this team. You can still set each rule below.">
        <Row label="Fair play rules">
          <Switch on={on} label="Fair play rules" onChange={() => set(on ? rulesOff(c) : { ...defaultFairPlayConfig(), noPitcher: c.noPitcher, noCatcher: c.noCatcher, outfielderCount: c.outfielderCount })} />
        </Row>
      </Group>
      <Group header="Positions" footer="A position that's switched off is taken off the field: Auto-Fill won't use it and it never shows as open. Anyone playing it now is unassigned when you save.">
        <Row label="No pitcher"><Switch on={c.noPitcher} label="No pitcher" onChange={() => toggle('noPitcher')} /></Row>
        <Row label="No catcher"><Switch on={c.noCatcher} label="No catcher" onChange={() => toggle('noCatcher')} /></Row>
        <Row label="Outfielders">
          <div style={{ width: 280 }}>
            <Segmented value={String(c.outfielderCount) as '3' | '4'} onChange={(v) => patch({ outfielderCount: Number(v) })}
              options={[['3', '3 · LF CF RF'], ['4', '4 · LF LCF RCF RF']]} />
          </div>
        </Row>
      </Group>
      <Group header="Bench" footer={[
        c.noConsecutiveBench && 'No player sits on the bench two innings in a row.',
        c.equalBenchTime && 'No player sits twice until everyone has sat once.',
      ].filter(Boolean).join(' ') || undefined}>
        <Row label="No back-to-back bench"><Switch on={c.noConsecutiveBench} label="No back-to-back bench" onChange={() => toggle('noConsecutiveBench')} /></Row>
        <Row label="Equal bench time"><Switch on={c.equalBenchTime} label="Equal bench time" onChange={() => toggle('equalBenchTime')} /></Row>
      </Group>
      <Group header="Fielding minimums" footer="Innings each player must play in the field. Set to Off to turn a minimum off.">
        <Row label="Innings in the field"><Stepper value={c.minimumFieldingInnings} onChange={(v) => patch({ minimumFieldingInnings: v })} label="Innings in the field" /></Row>
        <Row label="Infield innings"><Stepper value={c.minimumInfieldInnings} onChange={(v) => patch({ minimumInfieldInnings: v })} label="Infield innings" /></Row>
        <Row label="Outfield innings"><Stepper value={c.minimumOutfieldInnings} onChange={(v) => patch({ minimumOutfieldInnings: v })} label="Outfield innings" /></Row>
      </Group>
      <Group header="Catching and pitching" footer="Catcher to pitcher: a player who caught this many innings can't pitch. Pitcher to catcher: a player who pitched this many innings can't catch.">
        <Row label="Catcher to pitcher"><Stepper value={c.catcherToPitcherThreshold} onChange={(v) => patch({ catcherToPitcherThreshold: v })} label="Catcher to pitcher" /></Row>
        <Row label="Pitcher to catcher"><Stepper value={c.pitcherToCatcherThreshold} onChange={(v) => patch({ pitcherToCatcherThreshold: v })} label="Pitcher to catcher" /></Row>
      </Group>
      <Group header="Auto-Fill" footer="Auto-Fill tries to give each player a different position every inning. If there's no new spot for someone, it repeats one rather than leave a spot open.">
        <Row label="No repeat positions"><Switch on={c.noRepeatPositions} label="No repeat positions" onChange={() => toggle('noRepeatPositions')} /></Row>
      </Group>
      <ResetButton onClick={() => set(defaultFairPlayConfig())}
        note="Defaults: no back-to-back bench on; 4 innings in the field, 1 infield and 1 outfield; everything else off." />
    </>
  );
}

// MARK: - Pitching

function PitchingTab({ c, set }: { c: PitchingConfig; set(c: PitchingConfig): void }) {
  const [open, setOpen] = useState<PitchingAgeBracket | null>(null);
  const [confirmPreset, setConfirmPreset] = useState(false);
  const patch = (p: Partial<PitchingConfig>) => set({ ...c, ...p });
  const setLimits = (b: PitchingAgeBracket, l: PitchingLimits | undefined) => {
    const ageLimits = { ...c.ageLimits };
    if (l) ageLimits[b] = l; else delete ageLimits[b];
    patch({ ageLimits });
  };
  const configured = BRACKETS.filter((b) => c.ageLimits[b]);
  const nextMissing = BRACKETS.find((b) => !c.ageLimits[b]);

  return (
    <>
      <Group footer="When this is on, pitch counts from archived games set each pitcher's rest days, and the lineup warns you when a pitcher still needs rest.">
        <Row label="Pitch count rules"><Switch on={c.rulesEnabled} label="Pitch count rules" onChange={() => patch({ rulesEnabled: !c.rulesEnabled })} /></Row>
      </Group>
      {c.rulesEnabled && (
        <>
          <Group header="Weekly cap" footer={!c.weeklyLimitEnabled
            ? 'Optionally cap how many pitches a player can throw in a week. Rest days still apply on their own.'
            : c.rollingWindowType === 'Calendar Week'
              ? 'The cap resets each Monday. A player who hits it on Saturday can pitch again Monday, if they’ve had their rest days.'
              : 'The cap counts any 7 days in a row. A game last Tuesday drops off this Tuesday.'}>
            <Row label="Weekly pitch cap">
              <Switch on={c.weeklyLimitEnabled} label="Weekly pitch cap"
                onChange={() => patch({ weeklyLimitEnabled: !c.weeklyLimitEnabled, weeklyLimit: c.weeklyLimit || 100 })} />
            </Row>
            {c.weeklyLimitEnabled && (
              <>
                <Row label="Most pitches per week">
                  <NumInput value={c.weeklyLimit || undefined} onChange={(v) => patch({ weeklyLimit: v ?? 0 })} label="Most pitches per week" placeholder="100" />
                </Row>
                <Row label="Cap resets">
                  <div style={{ width: 280 }}>
                    <Segmented value={c.rollingWindowType} onChange={(v) => patch({ rollingWindowType: v })}
                      options={[['Calendar Week', 'Every Monday'], ['Rolling 7 Days', 'Any 7 days']]} />
                  </div>
                </Row>
              </>
            )}
          </Group>

          <Group header="Age brackets" footer="Click a bracket to set its daily maximum and where each rest day starts. A player's league age picks their bracket.">
            {configured.length === 0 && <div style={{ padding: '12px 16px', fontSize: 15, color: C.label2 }}>No brackets yet.</div>}
            {configured.map((b) => (
              <BracketRow key={b} bracket={b} limits={c.ageLimits[b]!} open={open === b}
                onToggle={() => setOpen(open === b ? null : b)} onChange={(l) => setLimits(b, l)} />
            ))}
            <button className="h-tint" disabled={!nextMissing}
              onClick={() => { if (!nextMissing) return; setLimits(nextMissing, { dailyMax: 85, restDay1Min: 21, restDay2Min: 36, restDay3Min: 51, restDay4Min: 66 }); setOpen(nextMissing); }}
              style={{ ...rowStyle, width: '100%', color: nextMissing ? C.blue : C.label3, fontSize: 16, gap: 8, justifyContent: 'flex-start' }}>
              <Icon name="plus.circle.fill" size={18} color={nextMissing ? C.blue : C.label3} />Add age bracket
            </button>
          </Group>

          <div style={{ display: 'flex', flexDirection: 'column', gap: 8, marginBottom: 6 }}>
            {confirmPreset ? (
              <div style={{ background: '#fff', borderRadius: 12, padding: '12px 16px', display: 'flex', alignItems: 'center', gap: 8 }}>
                <span style={{ flex: 1, fontSize: 14, lineHeight: '19px' }}>Replace your age brackets with the standard Little League pitch counts? You can edit them after.</span>
                <PillButton onClick={() => setConfirmPreset(false)}>Cancel</PillButton>
                <PillButton kind="primary" onClick={() => { set(applyLittleLeaguePreset(c)); setConfirmPreset(false); setOpen(null); }}>Apply</PillButton>
              </div>
            ) : (
              <button className="h-tint" onClick={() => setConfirmPreset(true)} style={{ ...rowStyle, background: '#fff', borderRadius: 12, justifyContent: 'center', color: C.blue, fontSize: 16 }}>
                Use Little League pitch counts
              </button>
            )}
          </div>
          <ResetButton onClick={() => { set(defaultPitchingConfig()); setOpen(null); }}
            note="Reset clears every value and turns pitch count rules off." />
        </>
      )}
    </>
  );
}

function BracketRow({ bracket, limits, open, onToggle, onChange }: {
  bracket: PitchingAgeBracket; limits: PitchingLimits; open: boolean; onToggle(): void; onChange(l: PitchingLimits | undefined): void;
}) {
  const l = limits;
  const set = (p: Partial<PitchingLimits>) => {
    const next = { ...l, ...p };
    for (const k of ['restDay3Min', 'restDay4Min'] as const) if (next[k] === undefined) delete next[k];
    onChange(next);
  };
  // Each tier runs from its own start to one below the next tier's start (or the daily max).
  const upper1 = l.restDay2Min - 1;
  const upper2 = (l.restDay3Min ?? l.dailyMax + 1) - 1;
  const upper3 = (l.restDay4Min ?? l.dailyMax + 1) - 1;
  return (
    <div>
      <button onClick={onToggle} aria-expanded={open} className="h-row2" style={{ ...rowStyle, width: '100%' }}>
        <span style={{ fontSize: 16 }}>Ages {bracket}</span>
        <span style={{ marginLeft: 'auto', fontSize: 15, color: C.label2 }}>Max {l.dailyMax}</span>
        <Icon name="chevron.down" size={14} color={C.label2} style={{ transform: open ? 'rotate(180deg)' : undefined }} />
      </button>
      {open && (
        <div style={{ padding: '4px 16px 14px', display: 'flex', flexDirection: 'column', gap: 10 }}>
          <div style={{ display: 'flex', alignItems: 'center' }}>
            <span style={{ flex: 1 }}>
              <span style={{ display: 'block', fontSize: 15 }}>Daily max</span>
              <span style={{ fontSize: 12, color: C.label2 }}>pitches per game</span>
            </span>
            <NumInput value={l.dailyMax} onChange={(v) => v && set({ dailyMax: v })} label={`Ages ${bracket} daily max`} />
          </div>
          <div style={{ fontSize: 12, fontWeight: 600, color: C.label2, marginTop: 4 }}>REST DAYS</div>
          <div style={{ fontSize: 12, color: C.label3, marginTop: -6 }}>Enter the pitch count where each tier starts. Leave 3 or 4 blank to skip it.</div>
          <TierRow label="1 rest day" value={l.restDay1Min} upper={upper1} onChange={(v) => v && set({ restDay1Min: v })} />
          <TierRow label="2 rest days" value={l.restDay2Min} upper={upper2} onChange={(v) => v && set({ restDay2Min: v })} />
          <TierRow label="3 rest days" value={l.restDay3Min} upper={upper3} onChange={(v) => set({ restDay3Min: v })} optional />
          <TierRow label="4 rest days" value={l.restDay4Min} upper={l.dailyMax} onChange={(v) => set({ restDay4Min: v })} optional />
          <button className="h-link" onClick={() => onChange(undefined)}
            style={{ alignSelf: 'flex-start', display: 'flex', alignItems: 'center', gap: 6, color: C.red, fontSize: 14, marginTop: 2 }}>
            Remove ages {bracket}
          </button>
        </div>
      )}
    </div>
  );
}

function TierRow({ label, value, upper, onChange, optional }: {
  label: string; value: number | undefined; upper: number; onChange(v: number | undefined): void; optional?: boolean;
}) {
  const shown = value !== undefined && upper >= value && upper > 0 ? String(upper) : '—';
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
      <span style={{ flex: 1, fontSize: 15 }}>{label}</span>
      <NumInput value={value} onChange={(v) => (optional || v !== undefined) && onChange(v)} label={`${label} starts at`} placeholder="—" width={56} />
      <span style={{ width: 12, textAlign: 'center', color: C.label2 }}>–</span>
      <span className="num" style={{ width: 34, textAlign: 'right', fontSize: 15, color: C.label2 }}>{shown}</span>
      <span style={{ width: 48, fontSize: 12, color: C.label2 }}>pitches</span>
    </div>
  );
}

// MARK: - Form pieces

const rowStyle: CSSProperties = { minHeight: 48, padding: '8px 16px', display: 'flex', alignItems: 'center', gap: 12 };

function Group({ header, footer, children }: { header?: string; footer?: string; children: ReactNode }) {
  return (
    <section style={{ marginBottom: 22 }}>
      {header && <div style={{ fontSize: 13, color: C.label2, textTransform: 'uppercase', letterSpacing: 0.4, padding: '0 16px 6px' }}>{header}</div>}
      <div className="settings-group" style={{ background: '#fff', borderRadius: 12, overflow: 'hidden' }}>{children}</div>
      {footer && <div style={{ fontSize: 13, lineHeight: '18px', color: C.label2, padding: '6px 16px 0' }}>{footer}</div>}
    </section>
  );
}

function Row({ label, note, stacked, children }: { label: string; note?: string; stacked?: boolean; children: ReactNode }) {
  return (
    <div className="settings-row" style={stacked ? { padding: '12px 16px' } : rowStyle}>
      <span style={{ flex: 1, minWidth: 0, display: 'block', marginBottom: stacked ? 10 : 0 }}>
        <span style={{ display: 'block', fontSize: 16 }}>{label}</span>
        {note && <span style={{ display: 'block', fontSize: 12, color: C.label2, marginTop: 1 }}>{note}</span>}
      </span>
      {children}
    </div>
  );
}

function TextInput({ value, onChange, placeholder, width, autoFocus }: {
  value: string; onChange(v: string): void; placeholder?: string; width?: number; autoFocus?: boolean;
}) {
  return (
    <input value={value} onChange={(e) => onChange(e.target.value)} placeholder={placeholder} autoFocus={autoFocus}
      style={{ width, height: 34, borderRadius: 8, border: `0.5px solid ${C.gray4}`, padding: '0 10px', fontSize: 15, outline: 'none', textAlign: 'right' }} />
  );
}

/** Whole numbers only; blank is `undefined`. */
function NumInput({ value, onChange, label, placeholder, width = 72 }: {
  value: number | undefined; onChange(v: number | undefined): void; label: string; placeholder?: string; width?: number;
}) {
  return (
    <input inputMode="numeric" aria-label={label} placeholder={placeholder} value={value === undefined ? '' : String(value)}
      onChange={(e) => {
        const digits = e.target.value.replace(/\D/g, '').slice(0, 3);
        const n = Number(digits);
        onChange(digits && n > 0 ? n : undefined);
      }}
      className="num"
      style={{ width, height: 32, borderRadius: 7, border: 'none', background: C.gray6, textAlign: 'center', fontSize: 15, fontWeight: 600, color: C.blue, outline: 'none' }} />
  );
}

/** − value + in 0…9, where 0 reads "Off". */
function Stepper({ value, onChange, label }: { value: number; onChange(v: number): void; label: string }) {
  const btn = (enabled: boolean): CSSProperties => ({ display: 'grid', placeItems: 'center', opacity: enabled ? 1 : 0.35 });
  return (
    <span role="group" aria-label={label} style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
      <button aria-label={`Fewer: ${label}`} disabled={value <= 0} onClick={() => onChange(value - 1)} style={btn(value > 0)}>
        <Icon name="minus.circle.fill" size={24} color={value > 0 ? C.blue : C.gray2} />
      </button>
      <span className="num" aria-live="polite" style={{ minWidth: 30, textAlign: 'center', fontSize: 16, color: value ? C.label : C.label2 }}>{value || 'Off'}</span>
      <button aria-label={`More: ${label}`} disabled={value >= 9} onClick={() => onChange(value + 1)} style={btn(value < 9)}>
        <Icon name="plus.circle.fill" size={24} color={value < 9 ? C.blue : C.gray2} />
      </button>
    </span>
  );
}

function ColorChoice({ value, onChange }: { value: string; onChange(hex: string): void }) {
  const custom = !COLORS.includes(value);
  return (
    <div role="radiogroup" aria-label="Team color" style={{ display: 'flex', flexWrap: 'wrap', gap: 10, alignItems: 'center' }}>
      {COLORS.map((hex) => {
        const on = hex === value;
        return (
          <button key={hex} role="radio" aria-checked={on} aria-label={`#${hex}`} onClick={() => onChange(hex)}
            style={{ width: 30, height: 30, borderRadius: 15, background: `#${hex}`, boxShadow: on ? `0 0 0 2px #fff, 0 0 0 4px #${hex}` : 'none' }} />
        );
      })}
      <label title="Pick any color" style={{ position: 'relative', width: 30, height: 30, borderRadius: 15, cursor: 'pointer',
        background: custom ? `#${value}` : 'conic-gradient(#FF3B30, #FFCC00, #34C759, #30B0C7, #007AFF, #AF52DE, #FF3B30)',
        boxShadow: custom ? `0 0 0 2px #fff, 0 0 0 4px #${value}` : 'none' }}>
        <input type="color" aria-label="Custom team color" value={`#${value}`} onChange={(e) => onChange(e.target.value.slice(1).toUpperCase())}
          style={{ position: 'absolute', inset: 0, opacity: 0, cursor: 'pointer', width: '100%', height: '100%' }} />
      </label>
    </div>
  );
}

function ResetButton({ onClick, note }: { onClick(): void; note: string }) {
  return (
    <section style={{ marginBottom: 4 }}>
      <button className="h-tint" onClick={onClick} style={{ ...rowStyle, width: '100%', background: '#fff', borderRadius: 12, justifyContent: 'center', color: C.red, fontSize: 16 }}>
        Reset to defaults
      </button>
      <div style={{ fontSize: 13, lineHeight: '18px', color: C.label2, padding: '6px 16px 0' }}>{note}</div>
    </section>
  );
}
