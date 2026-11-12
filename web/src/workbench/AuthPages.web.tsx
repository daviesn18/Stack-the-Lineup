// Sign-in and set-password for the web, in the workbench's design system: a
// navy brand panel on the left (hidden on narrow windows) and the form on the
// right. Continue with Apple / Google sit above the email form. Forgot
// password is its own view of the same form, and ends on a "check your email"
// confirmation.

import { useRouter } from 'expo-router';
import { useEffect, useRef, useState, type FormEvent, type ReactNode } from 'react';

import { useAuth } from '@/data/auth';
import { needsPassword, parseConfirmLink } from '@/data/confirmLink';
import { arrivedVia, oauthError, supabase } from '@/data/supabase';

import { Field, Input } from './controls';
import { oauthMessage } from './oauthMessage';
import { Icon } from './Icon';
import { SUB } from './Shell';
import { C, CSS } from './theme';

const NAVY = '#1B2C5D';

export function SignInPage() {
  const [mode, setMode] = useState<'signIn' | 'reset' | 'sent'>('signIn');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  // An Apple or Google sign-in that bounced back shows its reason once.
  const [error, setError] = useState<string | null>(() => oauthMessage(oauthError));
  const [provider, setProvider] = useState<Provider | null>(null);
  const go = (m: typeof mode) => { setMode(m); setError(null); };

  async function continueWith(p: Provider) {
    setProvider(p); setError(null);
    // Leaves the page for Apple or Google, which send the coach back here signed in.
    const { error } = await supabase.auth.signInWithOAuth({ provider: p, options: { redirectTo: window.location.origin } });
    if (error) { setProvider(null); setError(error.message); }
  }

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
          <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
            <OAuthButton provider="apple" busy={provider === 'apple'} disabled={!!provider} onClick={() => void continueWith('apple')} />
            <OAuthButton provider="google" busy={provider === 'google'} disabled={!!provider} onClick={() => void continueWith('google')} />
          </div>
          <Divider />
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
          <Heading title="Reset your password" sub="Enter your email and we'll send you a link to choose a new password." />
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
          <Heading title="Check your email" sub={`If ${email.trim()} has an account, a reset link is on its way.`} />
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
          sub={email ? `Sign in with ${email} and this password.` : "You'll use it with your email to sign in."} />
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

// MARK: - Email links

/**
 * Finishes the sign-in from an auth email (data/confirmLink): verifies the
 * one-time token here, in the page, then moves on to Choose a password or
 * the app. A used or expired link explains itself instead of failing silently.
 */
export function ConfirmPage() {
  const router = useRouter();
  const { session, passwordSet } = useAuth();
  const [verified, setVerified] = useState(false);
  // Read once. The token stays in the address bar (Expo Router keeps the URL), but it works only once.
  const [link] = useState(() => parseConfirmLink(window.location.pathname, window.location.search));
  const [error, setError] = useState<string | null>(link ? null : "This link isn't complete. Open it again from the email, or sign in.");
  const started = useRef(false);

  useEffect(() => {
    if (!link || started.current) return;   // once, even when React runs effects twice in development
    started.current = true;
    void supabase.auth.verifyOtp({ token_hash: link.tokenHash, type: link.type }).then(({ error }) => {
      if (error) {
        passwordSet();   // a failed link mustn't leave a signed-in coach stuck on Choose a password
        setError(/expired|invalid/i.test(error.message)
          ? 'This link has expired or was already used. Links work once, for 24 hours.'
          : `This link didn't work: ${error.message}`);
        return;
      }
      setVerified(true);
    });
  }, [link, passwordSet]);

  // Move on once the new session has reached the app, so the route guards let the coach through.
  useEffect(() => {
    if (verified && link && session) router.replace(needsPassword(link.type) ? '/set-password' : '/');
  }, [verified, link, session, router]);

  return (
    <Frame>
      {error ? (
        <div style={FORM}>
          <Heading title="That link didn't work" sub={error} />
          {link?.type === 'recovery' && <p style={{ margin: 0, fontSize: 14, color: SUB }}>Ask for a new one from Forgot password on the sign-in page.</p>}
          <LinkButton onClick={() => router.replace(session ? '/' : '/sign-in')}>{session ? 'Go to the app' : 'Go to sign in'}</LinkButton>
        </div>
      ) : (
        <div style={FORM}>
          <Heading title="One moment…" sub={link && needsPassword(link.type) ? 'Checking your link. Next, you choose a password.' : 'Checking your link.'} />
        </div>
      )}
    </Frame>
  );
}

// MARK: - Apple and Google

type Provider = 'apple' | 'google';

/** Apple's and Google's own button styles: black with the Apple logo, white with the Google G. */
function OAuthButton({ provider, busy, disabled, onClick }: { provider: Provider; busy: boolean; disabled: boolean; onClick(): void }) {
  const apple = provider === 'apple';
  return (
    <button type="button" onClick={onClick} disabled={disabled} className={apple ? 'auth-apple' : 'auth-google'}
      style={{ height: 40, borderRadius: 8, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8, fontSize: 14, fontWeight: 600,
        background: apple ? '#000' : '#fff', color: apple ? '#fff' : '#1f1f1f', border: apple ? 'none' : '1px solid #747775',
        opacity: disabled && !busy ? 0.45 : 1 }}>
      {apple ? <AppleLogo /> : <GoogleLogo />}
      {busy ? 'One moment…' : `Continue with ${apple ? 'Apple' : 'Google'}`}
    </button>
  );
}

function AppleLogo() {
  return (
    <svg width="14" height="17" viewBox="0 0 814 1000" aria-hidden fill="#fff">
      <path d="M788.1 340.9c-5.8 4.5-108.2 62.2-108.2 190.5 0 148.4 130.3 200.9 134.2 202.2-.6 3.2-20.7 71.9-68.7 141.9-42.8 61.6-87.5 123.1-155.5 123.1s-85.5-39.5-164-39.5c-76.5 0-103.7 40.8-165.9 40.8s-105.6-57-155.5-127C46.7 790.7 0 663 0 541.8c0-194.4 126.4-297.5 250.8-297.5 66.1 0 121.2 43.4 162.7 43.4 39.5 0 101.1-46 176.3-46 28.5 0 130.9 2.6 198.3 99.2zm-234-181.5c31.1-36.9 53.1-88.1 53.1-139.3 0-7.1-.6-14.3-1.9-20.1-50.6 1.9-110.8 33.7-147.1 75.8-28.5 32.4-55.1 83.6-55.1 135.5 0 7.8 1.3 15.6 1.9 18.1 3.2.6 8.4 1.3 13.6 1.3 45.4 0 102.5-30.4 135.5-71.3z" />
    </svg>
  );
}

function GoogleLogo() {
  return (
    <svg width="18" height="18" viewBox="0 0 18 18" aria-hidden>
      <path fill="#EA4335" d="M9 3.48c1.69 0 2.83.73 3.48 1.34l2.54-2.48C13.46.89 11.43 0 9 0 5.48 0 2.44 2.02.96 4.96l2.91 2.26C4.6 5.05 6.62 3.48 9 3.48z" />
      <path fill="#4285F4" d="M17.64 9.2c0-.74-.06-1.28-.19-1.84H9v3.34h4.96c-.1.83-.64 2.08-1.84 2.92l2.84 2.2c1.7-1.57 2.68-3.88 2.68-6.62z" />
      <path fill="#FBBC05" d="M3.88 10.78A5.54 5.54 0 0 1 3.58 9c0-.62.11-1.22.29-1.78L.96 4.96A9.008 9.008 0 0 0 0 9c0 1.45.35 2.82.96 4.04l2.92-2.26z" />
      <path fill="#34A853" d="M9 18c2.43 0 4.47-.8 5.96-2.18l-2.84-2.2c-.76.53-1.78.9-3.12.9-2.38 0-4.4-1.57-5.12-3.74L.97 13.04C2.45 15.98 5.48 18 9 18z" />
    </svg>
  );
}

function Divider() {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 12, fontSize: 12, color: SUB }}>
      <span style={{ flex: 1, height: 1, background: 'rgba(60,60,67,0.14)' }} />or<span style={{ flex: 1, height: 1, background: 'rgba(60,60,67,0.14)' }} />
    </div>
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
          <h2 style={{ margin: 0, fontSize: 32, lineHeight: 1.15, fontWeight: 700, letterSpacing: '-0.02em' }}>Fair lineups in minutes.</h2>
          <p style={{ margin: '14px 0 32px', fontSize: 16, lineHeight: 1.5, color: 'rgba(255,255,255,0.72)', maxWidth: 400 }}>
            Build the batting order and defense for every inning, check fair play, and print the Coaches Guide.
          </p>
          <Feature icon="bolt.fill" title="Auto-Fill" text="Fills every inning with players' positions." />
          <Feature icon="checkmark.shield.fill" title="Fair play checks" text="Bench time, infield and outfield minimums, and pitcher rest." />
          <Feature icon="doc.richtext.fill" title="Coaches Guide" text="Defensive assignments for every inning." />
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
.stl .auth-apple:hover:not(:disabled) { background: #222 !important; }
.stl .auth-google:hover:not(:disabled) { background: #f6f8fc !important; }
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
