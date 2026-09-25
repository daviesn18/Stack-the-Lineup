// Sign-in and set-password for the web, in the workbench's design system: a
// navy brand panel on the left (hidden on narrow windows) and the form on the
// right. Forgot password is its own view of the same form, and ends on a
// "check your email" confirmation.

import { useState, type FormEvent, type ReactNode } from 'react';

import { useAuth } from '@/data/auth';
import { arrivedVia, supabase } from '@/data/supabase';

import { Field, Input } from './controls';
import { Icon } from './Icon';
import { SUB } from './Shell';
import { C, CSS } from './theme';

const NAVY = '#1B2C5D';

export function SignInPage() {
  const [mode, setMode] = useState<'signIn' | 'reset' | 'sent'>('signIn');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const go = (m: typeof mode) => { setMode(m); setError(null); };

  async function signIn(e: FormEvent) {
    e.preventDefault();
    if (!email.trim() || !password) return;
    setBusy(true); setError(null);
    const { error } = await supabase.auth.signInWithPassword({ email: email.trim(), password });
    setBusy(false);
    if (error) {
      setError(error.message === 'Invalid login credentials'
        ? "That email and password don't match. Check both, or reset your password."
        : error.message);
    }
  }

  async function sendReset(e: FormEvent) {
    e.preventDefault();
    if (!email.trim()) return;
    setBusy(true); setError(null);
    const { error } = await supabase.auth.resetPasswordForEmail(email.trim(), { redirectTo: window.location.origin });
    setBusy(false);
    if (error) setError(error.message); else go('sent');
  }

  return (
    <Frame footer="Stack the Lineup on the web is invite-only while we test it with a few coaches.">
      {mode === 'signIn' && (
        <form onSubmit={signIn} style={FORM}>
          <Heading title="Sign in" sub="Welcome back, coach." />
          <Field label="Email"><Input type="email" value={email} onChange={setEmail} autoComplete="email" autoFocus height={40} /></Field>
          <Field label="Password" aside={<LinkButton onClick={() => go('reset')}>Forgot password?</LinkButton>}>
            <Input type="password" value={password} onChange={setPassword} autoComplete="current-password" height={40} />
          </Field>
          {error && <ErrorNote>{error}</ErrorNote>}
          <Submit busy={busy} disabled={!email.trim() || !password}>Sign in</Submit>
        </form>
      )}
      {mode === 'reset' && (
        <form onSubmit={sendReset} style={FORM}>
          <Heading title="Reset your password" sub="Enter your email and we'll send you a link to choose a new one." />
          <Field label="Email"><Input type="email" value={email} onChange={setEmail} autoComplete="email" autoFocus height={40} /></Field>
          {error && <ErrorNote>{error}</ErrorNote>}
          <Submit busy={busy} disabled={!email.trim()}>Send reset link</Submit>
          <LinkButton onClick={() => go('signIn')} center>Back to sign in</LinkButton>
        </form>
      )}
      {mode === 'sent' && (
        <div style={FORM}>
          <span style={{ width: 44, height: 44, borderRadius: 22, background: 'rgba(52,199,89,0.14)', display: 'grid', placeItems: 'center' }}>
            <Icon name="checkmark" size={22} color={C.green} />
          </span>
          <Heading title="Check your email" sub={`If ${email.trim()} has an account, a reset link is on its way. It can take a minute to arrive.`} />
          <LinkButton onClick={() => go('signIn')}>Back to sign in</LinkButton>
        </div>
      )}
    </Frame>
  );
}

export function SetPasswordPage() {
  const { session, passwordSet } = useAuth();
  const [password, setPassword] = useState('');
  const [confirm, setConfirm] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const invited = arrivedVia === 'invite';

  async function save(e: FormEvent) {
    e.preventDefault();
    if (password.length < 8) { setError('Use at least 8 characters.'); return; }
    if (password !== confirm) { setError("The two passwords don't match."); return; }
    setBusy(true); setError(null);
    const { error } = await supabase.auth.updateUser({ password });
    setBusy(false);
    if (error) setError(error.message); else passwordSet();
  }

  const email = session?.user.email;
  return (
    <Frame>
      <form onSubmit={save} style={FORM}>
        <Heading title={invited ? 'Welcome! Choose a password' : 'Choose a new password'}
          sub={email ? `You'll sign in with ${email} and this password.` : "You'll use it with your email to sign in."} />
        <Field label="New password" aside={<span style={{ fontSize: 12, color: SUB }}>At least 8 characters</span>}>
          <Input type="password" value={password} onChange={setPassword} autoComplete="new-password" autoFocus height={40} />
        </Field>
        <Field label="Confirm password"><Input type="password" value={confirm} onChange={setConfirm} autoComplete="new-password" height={40} /></Field>
        {error && <ErrorNote>{error}</ErrorNote>}
        <Submit busy={busy} disabled={!password || !confirm}>{invited ? 'Save and continue' : 'Save password'}</Submit>
      </form>
    </Frame>
  );
}

// MARK: - Frame

function Frame({ children, footer }: { children: ReactNode; footer?: string }) {
  return (
    <div className="stl" style={{ position: 'fixed', inset: 0, overflow: 'auto', display: 'flex', background: C.grouped }}>
      <style>{CSS + AUTH_CSS}</style>
      <aside className="auth-brand" style={{ flex: '0 0 44%', maxWidth: 560, background: `linear-gradient(160deg, ${NAVY} 0%, #14203F 100%)`, color: '#fff', padding: '40px 48px', flexDirection: 'column' }}>
        <Brand light />
        <div style={{ marginTop: 'auto', marginBottom: 'auto', paddingTop: 48 }}>
          <h2 style={{ margin: 0, fontSize: 32, lineHeight: 1.15, fontWeight: 700, letterSpacing: '-0.02em' }}>Fair lineups, set before first pitch.</h2>
          <p style={{ margin: '14px 0 32px', fontSize: 16, lineHeight: 1.5, color: 'rgba(255,255,255,0.72)', maxWidth: 400 }}>
            Build the batting order and defense for every inning, check fair play, and print the Coaches Guide for the dugout.
          </p>
          <Feature icon="bolt.fill" title="Auto-Fill" text="Fills every inning around attendance and each player's positions." />
          <Feature icon="checkmark.shield.fill" title="Fair play checks" text="Bench time, infield and outfield minimums, and pitcher rest." />
          <Feature icon="doc.richtext.fill" title="Coaches Guide" text="Every inning on one printed page." />
        </div>
        <div style={{ fontSize: 12, color: 'rgba(255,255,255,0.5)' }}>Also on iPhone and iPad.</div>
      </aside>
      <main style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', padding: '48px 24px' }}>
        <div style={{ width: '100%', maxWidth: 380 }}>
          <div className="auth-brand-small" style={{ marginBottom: 32 }}><Brand /></div>
          <div style={{ background: '#fff', borderRadius: 14, padding: 28, boxShadow: '0 1px 2px rgba(0,0,0,0.04), 0 8px 24px rgba(0,0,0,0.06)' }}>
            {children}
          </div>
          {footer && <p style={{ margin: '16px 4px 0', fontSize: 12, color: SUB, lineHeight: 1.5, textAlign: 'center' }}>{footer}</p>}
        </div>
      </main>
    </div>
  );
}

/** Below 900px the brand panel hides and a small logo sits above the form. */
const AUTH_CSS = `
.stl .auth-brand { display: flex; }
.stl .auth-brand-small { display: none; }
@media (max-width: 900px) {
  .stl .auth-brand { display: none; }
  .stl .auth-brand-small { display: block; }
}
.stl .auth-submit:hover:not(:disabled) { background: #0066d6 !important; }
`;

function Brand({ light }: { light?: boolean }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
      <img src="/app-icon.png" alt="" width={36} height={36} style={{ borderRadius: 9, boxShadow: light ? '0 0 0 1px rgba(255,255,255,0.15)' : undefined }} />
      <span style={{ fontSize: 16, fontWeight: 600, color: light ? '#fff' : C.label }}>Stack the Lineup</span>
    </div>
  );
}

function Feature({ icon, title, text }: { icon: string; title: string; text: string }) {
  return (
    <div style={{ display: 'flex', gap: 14, marginTop: 18 }}>
      <span style={{ width: 32, height: 32, borderRadius: 8, background: 'rgba(255,255,255,0.1)', display: 'grid', placeItems: 'center', flexShrink: 0 }}>
        <Icon name={icon} size={16} color="#fff" />
      </span>
      <span>
        <span style={{ display: 'block', fontSize: 14, fontWeight: 600 }}>{title}</span>
        <span style={{ display: 'block', fontSize: 13, lineHeight: 1.4, color: 'rgba(255,255,255,0.65)', marginTop: 2 }}>{text}</span>
      </span>
    </div>
  );
}

// MARK: - Pieces

const FORM = { display: 'flex', flexDirection: 'column', gap: 18 } as const;

function Heading({ title, sub }: { title: string; sub: string }) {
  return (
    <div>
      <h1 style={{ margin: 0, fontSize: 22, fontWeight: 700, letterSpacing: '-0.01em' }}>{title}</h1>
      <p style={{ margin: '6px 0 0', fontSize: 14, lineHeight: 1.45, color: SUB }}>{sub}</p>
    </div>
  );
}

function Submit({ children, busy, disabled }: { children: string; busy: boolean; disabled: boolean }) {
  return (
    <button type="submit" className="auth-submit" disabled={disabled || busy}
      style={{ height: 40, borderRadius: 8, background: C.blue, color: '#fff', fontSize: 14, fontWeight: 600, textAlign: 'center', opacity: disabled ? 0.45 : 1, marginTop: 2 }}>
      {busy ? 'One moment…' : children}
    </button>
  );
}

function LinkButton({ children, onClick, center }: { children: string; onClick(): void; center?: boolean }) {
  return (
    <button type="button" className="h-link" onClick={onClick}
      style={{ fontSize: 13, fontWeight: 500, color: C.blue, alignSelf: center ? 'center' : 'flex-start', textTransform: 'none', letterSpacing: 0 }}>
      {children}
    </button>
  );
}

function ErrorNote({ children }: { children: string }) {
  return (
    <div role="alert" style={{ display: 'flex', gap: 8, alignItems: 'flex-start', padding: '10px 12px', borderRadius: 8, background: 'rgba(255,59,48,0.08)', color: C.red, fontSize: 13, lineHeight: 1.4 }}>
      <Icon name="exclamationmark.triangle.fill" size={15} color={C.red} style={{ marginTop: 1 }} />
      <span>{children}</span>
    </div>
  );
}
