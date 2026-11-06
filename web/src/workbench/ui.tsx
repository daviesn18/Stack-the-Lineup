// Small shared pieces for the web workbench: segmented control,
// iOS switch, modal sheet and form fields, styled to the handoff tokens.

import { useEffect, type CSSProperties, type ReactNode } from 'react';

import { C } from './theme';

export function Segmented<T extends string>({ value, onChange, options }: { value: T; onChange(v: T): void; options: [T, string][] }) {
  return (
    <div role="tablist" style={{ display: 'grid', gridTemplateColumns: `repeat(${options.length}, 1fr)`, padding: 2, background: 'rgba(118,118,128,0.12)', borderRadius: 9 }}>
      {options.map(([id, label]) => {
        const on = id === value;
        return (
          <button key={id} role="tab" aria-selected={on} onClick={() => onChange(id)}
            style={{ borderRadius: 7, padding: '6px 0', fontSize: 14, textAlign: 'center', fontWeight: on ? 600 : 400, background: on ? '#fff' : 'transparent', boxShadow: on ? '0 1px 3px rgba(0,0,0,0.12), 0 0 0 0.5px rgba(0,0,0,0.04)' : 'none' }}>
            {label}
          </button>
        );
      })}
    </div>
  );
}

export function Switch({ on, onChange, label }: { on: boolean; onChange(): void; label: string }) {
  return (
    <button role="switch" aria-checked={on} aria-label={label} onClick={onChange} className="switch"
      style={{ width: 51, height: 31, borderRadius: 16, padding: 2, background: on ? C.green : C.gray5, flexShrink: 0 }}>
      <span className="switch-knob" style={{ display: 'block', width: 27, height: 27, borderRadius: 14, background: '#fff', boxShadow: '0 3px 8px rgba(0,0,0,0.15), 0 1px 1px rgba(0,0,0,0.16)', transform: on ? 'translateX(20px)' : 'none' }} />
    </button>
  );
}

export const card: CSSProperties = { background: '#fff', borderRadius: 12 };

export function PillButton({ children, onClick, disabled, kind = 'plain', type = 'button' }: {
  children: ReactNode; onClick?: () => void; disabled?: boolean; kind?: 'plain' | 'primary' | 'danger'; type?: 'button' | 'submit';
}) {
  const style: CSSProperties = kind === 'primary'
    ? { background: C.blue, color: '#fff', fontWeight: 600 }
    : kind === 'danger' ? { background: C.destructiveBg, color: C.destructiveFg, border: `0.5px solid ${C.destructiveBorder}` }
      : { background: C.gray6, color: C.blue };
  return (
    <button type={type} className="h-bright" onClick={onClick} disabled={disabled}
      style={{ height: 34, padding: '0 16px', borderRadius: 999, fontSize: 15, opacity: disabled ? 0.45 : 1, ...style }}>
      {children}
    </button>
  );
}

/** A centered sheet over a dimmed page. Esc or a click outside closes it. */
export function Modal({ title, onClose, children, footer, width = 560 }: {
  title: string; onClose(): void; children: ReactNode; footer?: ReactNode; width?: number;
}) {
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose(); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose]);
  return (
    <div onMouseDown={(e) => { if (e.target === e.currentTarget) onClose(); }}
      style={{ position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.25)', zIndex: 40, display: 'grid', placeItems: 'center', padding: 24 }}>
      <div role="dialog" aria-modal aria-label={title} className="pop"
        style={{ width, maxWidth: '100%', maxHeight: 'calc(100vh - 48px)', background: C.grouped, borderRadius: 14, boxShadow: '0 12px 32px rgba(0,0,0,0.2)', display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
        <div style={{ padding: '14px 18px', borderBottom: C.hair, background: '#fff', display: 'flex', alignItems: 'center' }}>
          <span style={{ fontSize: 17, fontWeight: 600 }}>{title}</span>
        </div>
        <div style={{ padding: 18, overflowY: 'auto' }}>{children}</div>
        {footer && <div style={{ padding: '12px 18px', borderTop: C.hair, background: '#fff', display: 'flex', gap: 8, alignItems: 'center' }}>{footer}</div>}
      </div>
    </div>
  );
}

export function TextField({ label, value, onChange, placeholder, width, inputMode, autoFocus, type = 'text' }: {
  label: string; value: string; onChange(v: string): void; placeholder?: string; width?: number | string;
  inputMode?: 'numeric' | 'text'; autoFocus?: boolean; type?: string;
}) {
  return (
    <label style={{ display: 'flex', flexDirection: 'column', gap: 4, width, flex: width ? undefined : 1, minWidth: 0 }}>
      <span style={{ fontSize: 12, fontWeight: 500, color: C.label2, letterSpacing: 0.4, textTransform: 'uppercase' }}>{label}</span>
      <input value={value} onChange={(e) => onChange(e.target.value)} placeholder={placeholder} inputMode={inputMode} autoFocus={autoFocus} type={type}
        style={{ height: 36, borderRadius: 8, border: `0.5px solid ${C.gray4}`, background: '#fff', padding: '0 10px', fontSize: 15, outline: 'none' }} />
    </label>
  );
}
