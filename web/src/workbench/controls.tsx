// Form pieces from the team-settings handoff, shared by every page and
// dialog built in that style: grouped white cards of rows (label, help text,
// control on the right), the switch, stepper, segmented control, text and
// number inputs, the header buttons, and a centered dialog.

import { useEffect, type CSSProperties, type ReactNode } from 'react';

import { Icon } from './Icon';
import { BORDER, BORDER2, Kbd, SUB } from './Shell';
import { C } from './theme';

export const CANVAS = '#F2F2F7';
export const HAIR = '1px solid rgba(60,60,67,0.08)';

export function HeaderButton({ children, onClick, kind = 'plain', disabled, title }: {
  children: ReactNode; onClick(): void; kind?: 'plain' | 'primary' | 'danger'; disabled?: boolean; title?: string;
}) {
  const look: CSSProperties = kind === 'primary'
    ? { padding: '0 16px', background: C.blue, color: '#fff', fontWeight: 600 }
    : kind === 'danger' ? { padding: '0 16px', background: C.red, color: '#fff', fontWeight: 600 }
      : { padding: '0 14px', background: '#fff', border: `1px solid ${BORDER2}`, fontWeight: 500 };
  return (
    <button type="button" onClick={onClick} disabled={disabled} title={title} className={kind === 'plain' ? 'h-sec' : kind === 'primary' ? 'h-save' : 'h-bright'}
      style={{ height: 32, borderRadius: 8, fontSize: 13, opacity: disabled ? 0.45 : 1, ...look }}>
      {children}
    </button>
  );
}

export function Heading({ title, sub }: { title: string; sub: string }) {
  return (
    <div>
      <h1 style={{ margin: 0, fontSize: 22, fontWeight: 700, letterSpacing: '-0.01em' }}>{title}</h1>
      <div style={{ fontSize: 14, color: SUB, marginTop: 4 }}>{sub}</div>
    </div>
  );
}

export function Group({ label, children }: { label: string; children: ReactNode }) {
  return (
    <section>
      <div style={{ fontSize: 13, fontWeight: 600, padding: '0 4px', marginBottom: 8 }}>{label}</div>
      <div style={{ background: '#fff', borderRadius: 12, overflow: 'hidden' }}>{children}</div>
    </section>
  );
}

/** Faded groups under a master switch that's off. They stay editable. */
export function Fade({ on, children }: { on: boolean; children: ReactNode }) {
  return <div style={{ display: 'flex', flexDirection: 'column', gap: 24, opacity: on ? 1 : 0.45, transition: 'opacity .2s ease' }}>{children}</div>;
}

export function Row({ label, help, stacked, aside, children }: { label: string; help?: string; stacked?: boolean; aside?: string; children: ReactNode }) {
  const text = (
    <div style={{ minWidth: 0 }}>
      <div style={{ fontSize: 14, fontWeight: 500 }}>{label}</div>
      {help && <div style={{ fontSize: 13, lineHeight: 1.4, color: SUB, marginTop: 2, textWrap: 'pretty' } as CSSProperties}>{help}</div>}
    </div>
  );
  if (stacked) {
    return (
      <div style={{ padding: '14px 18px', borderTop: HAIR, marginTop: -1 }}>
        <div style={{ display: 'grid', gridTemplateColumns: 'minmax(0,1fr) auto', columnGap: 24 }}>
          {text}
          {aside && <span style={{ fontSize: 13, color: SUB }}>{aside}</span>}
        </div>
        {children}
      </div>
    );
  }
  return (
    <div style={{ display: 'grid', gridTemplateColumns: 'minmax(0,1fr) auto', columnGap: 24, alignItems: 'center', padding: '14px 18px', borderTop: HAIR, marginTop: -1 }}>
      {text}
      {children}
    </div>
  );
}

export function Master({ label, help, on, onChange }: { label: string; help: string; on: boolean; onChange(): void }) {
  return (
    <div style={{ background: '#fff', borderRadius: 12, display: 'grid', gridTemplateColumns: 'minmax(0,1fr) auto', columnGap: 24, alignItems: 'center', padding: '16px 18px' }}>
      <div>
        <div style={{ fontSize: 15, fontWeight: 600 }}>{label}</div>
        <div style={{ fontSize: 13, lineHeight: 1.4, color: SUB, marginTop: 2 }}>{help}</div>
      </div>
      <Toggle on={on} label={label} onChange={onChange} />
    </div>
  );
}

export function Toggle({ on, onChange, label }: { on: boolean; onChange(): void; label: string }) {
  return (
    <button type="button" role="switch" aria-checked={on} aria-label={label} onClick={onChange}
      style={{ position: 'relative', width: 42, height: 26, borderRadius: 13, flexShrink: 0, background: on ? C.green : 'rgba(120,120,128,0.16)', transition: 'background-color .2s ease' }}>
      <span style={{ position: 'absolute', top: 2, left: on ? 18 : 2, width: 22, height: 22, borderRadius: 11, background: '#fff', boxShadow: '0 1px 3px rgba(0,0,0,0.25)', transition: 'left .2s ease' }} />
    </button>
  );
}

/** − value +, from `min` to `max`; 0 reads "Off". */
export function Stepper({ value, min = 0, max, onChange, label }: { value: number; min?: number; max: number; onChange(v: number): void; label: string }) {
  const btn = (enabled: boolean, dir: 'Fewer' | 'More', icon: string, next: number) => (
    <button type="button" aria-label={`${dir}: ${label}`} disabled={!enabled} onClick={() => enabled && onChange(next)}
      style={{ display: 'grid', placeItems: 'center', opacity: enabled ? 1 : 0.3 }}>
      <Icon name={icon} size={22} color={C.blue} />
    </button>
  );
  return (
    <span role="group" aria-label={label} style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
      {btn(value > min, 'Fewer', 'minus.circle.fill', value - 1)}
      <span className="num" aria-live="polite" style={{ minWidth: 36, textAlign: 'center', fontSize: 15, fontWeight: value ? 600 : 400, color: value ? C.label : SUB }}>{value || 'Off'}</span>
      {btn(value < max, 'More', 'plus.circle.fill', value + 1)}
    </span>
  );
}

export function Seg<T extends string>({ value, onChange, options, label }: { value: T; onChange(v: T): void; options: [T, string][]; label: string }) {
  return (
    <div role="radiogroup" aria-label={label} style={{ display: 'flex', padding: 2, borderRadius: 8, background: CANVAS }}>
      {options.map(([id, text]) => {
        const on = id === value;
        return (
          <button type="button" key={id} role="radio" aria-checked={on} onClick={() => onChange(id)}
            style={{ height: 28, padding: '0 14px', borderRadius: 6, fontSize: 13, fontWeight: on ? 600 : 500, whiteSpace: 'nowrap', background: on ? '#fff' : 'transparent', boxShadow: on ? '0 1px 2px rgba(0,0,0,0.08)' : 'none' }}>
            {text}
          </button>
        );
      })}
    </div>
  );
}

export function TextInput({ value, onChange, placeholder, label, autoFocus, width = 280 }: {
  value: string; onChange(v: string): void; placeholder: string; label: string; autoFocus?: boolean; width?: number;
}) {
  return (
    <input className="field" aria-label={label} value={value} onChange={(e) => onChange(e.target.value)} placeholder={placeholder} autoFocus={autoFocus}
      style={{ width, height: 34, borderRadius: 8, border: '1px solid rgba(60,60,67,0.14)', padding: '0 10px', fontSize: 14, outline: 'none', background: '#fff' }} />
  );
}

/** Digits only, up to 3. Blank is ''. */
export function NumInput({ value, onChange, label, placeholder, width, block, maxWidth, fill = CANVAS, color = C.blue }: {
  value: number | ''; onChange(v: number | ''): void; label: string; placeholder?: string; width?: number; block?: boolean;
  maxWidth?: number; fill?: string; color?: string;
}) {
  return (
    <input className="num-field num" inputMode="numeric" aria-label={label} placeholder={placeholder} value={value === '' ? '' : String(value)}
      onChange={(e) => {
        const digits = e.target.value.replace(/\D/g, '').slice(0, 3);
        onChange(digits === '' ? '' : Number(digits));
      }}
      style={{ width: block ? '100%' : width, maxWidth, display: block ? 'block' : undefined, margin: block ? '0 auto' : undefined, height: 34, borderRadius: 8, border: 'none', background: fill, textAlign: 'center', fontSize: 14, fontWeight: 600, color, outline: 'none' }} />
  );
}

/** Date and time input values in local time. */
const pad = (n: number) => String(n).padStart(2, '0');
export const dateValue = (d: Date) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
export const timeValue = (d: Date) => `${pad(d.getHours())}:${pad(d.getMinutes())}`;
/** The Date for a date and time input pair, or null while either is incomplete. */
export function fromInputs(date: string, time: string): Date | null {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date) || !/^\d{2}:\d{2}$/.test(time)) return null;
  const [y, m, d] = date.split('-').map(Number);
  const [hh, mm] = time.split(':').map(Number);
  return new Date(y, m - 1, d, hh, mm);
}

export function DateTimeInputs({ date, time, onDate, onTime }: { date: string; time: string; onDate(v: string): void; onTime(v: string): void }) {
  const style: CSSProperties = { height: 34, borderRadius: 8, border: '1px solid rgba(60,60,67,0.14)', padding: '0 10px', fontSize: 14, outline: 'none', background: '#fff' };
  return (
    <span style={{ display: 'flex', gap: 8 }}>
      <input className="field" type="date" aria-label="Date" value={date} onChange={(e) => onDate(e.target.value)} style={{ ...style, width: 160 }} />
      <input className="field" type="time" aria-label="Time" value={time} onChange={(e) => onTime(e.target.value)} style={{ ...style, width: 112 }} />
    </span>
  );
}

/**
 * A centered dialog in the roster panel's style: white header with a title,
 * subtitle and esc, the gray canvas for grouped rows, and a footer of buttons.
 * Esc or a click outside closes it.
 */
export function Dialog({ title, subtitle, onClose, width = 560, footer, children }: {
  title: string; subtitle?: string; onClose(): void; width?: number; footer: ReactNode; children: ReactNode;
}) {
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose(); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose]);
  return (
    <div onMouseDown={(e) => { if (e.target === e.currentTarget) onClose(); }}
      style={{ position: 'fixed', inset: 0, zIndex: 40, background: 'rgba(0,0,0,0.2)', display: 'grid', placeItems: 'center', padding: 24 }}>
      <div role="dialog" aria-modal aria-label={title} className="pop"
        style={{ width, maxWidth: '100%', maxHeight: 'calc(100vh - 48px)', background: CANVAS, borderRadius: 14, overflow: 'hidden', display: 'flex', flexDirection: 'column', boxShadow: '0 12px 32px rgba(0,0,0,0.2)' }}>
        <header style={{ height: 64, flexShrink: 0, background: '#fff', borderBottom: `1px solid ${BORDER}`, padding: '0 20px', display: 'flex', alignItems: 'center', gap: 12 }}>
          <span style={{ flex: 1, minWidth: 0 }}>
            <span style={{ display: 'block', fontSize: 17, fontWeight: 600 }}>{title}</span>
            {subtitle && <span className="ellipsis" style={{ display: 'block', fontSize: 12, color: SUB }}>{subtitle}</span>}
          </span>
          <button type="button" onClick={onClose} aria-label="Close"><Kbd>esc</Kbd></button>
        </header>
        <div style={{ flex: 1, minHeight: 0, overflowY: 'auto', padding: 20, display: 'flex', flexDirection: 'column', gap: 24 }}>{children}</div>
        <footer style={{ minHeight: 64, flexShrink: 0, background: '#fff', borderTop: `1px solid ${BORDER}`, padding: '12px 20px', display: 'flex', alignItems: 'center', gap: 8 }}>
          {footer}
        </footer>
      </div>
    </div>
  );
}
