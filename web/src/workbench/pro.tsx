// Pro for the workbench: one entitlement read for the whole page (not one per
// locked control), the gate hook every Pro feature uses, and the paywall sheet.
//
// Until web checkout exists (the web payments decision), the paywall can't
// sell anything. It says where Pro is sold and lets a coach check again after
// subscribing. Signals match iOS: paywall.shown / paywall.dismissed + source.

import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from 'react';

import { useAuth } from '@/data/auth';
import { setAnalyticsTier, signal } from '@/data/analytics';
import { supabase } from '@/data/supabase';

import { Dialog, HeaderButton } from './controls';
import { Icon } from './Icon';
import { gate, PAYWALL_GROUPS, type Entitlement, type GateContext, type GateState, type ProFeature } from './proGate';
import { C } from './theme';

interface ProState {
  entitlement: Entitlement;
  /** Opens the paywall, leading with `feature`. */
  ask(feature: ProFeature): void;
}

/** The signed-in coach's Pro status, or null when the read failed (keep the last answer rather than lock a Pro coach out). */
async function readIsPro(): Promise<boolean | null> {
  const { data, error } = await supabase.from('entitlements').select('is_pro, expires_at').maybeSingle();
  if (error) return null;
  const expired = data?.expires_at ? new Date(data.expires_at) < new Date() : false;
  return !!data?.is_pro && !expired;
}

const Ctx = createContext<ProState>({ entitlement: 'pro', ask: () => {} });

/** `demo` (the signed-out demo grid) is treated as Pro so every feature can be shown. */
export function ProProvider({ demo, children }: { demo?: boolean; children: ReactNode }) {
  const { session } = useAuth();
  const userId = session?.user.id;
  const [loaded, setLoaded] = useState<{ userId: string; isPro: boolean } | null>(null);
  const [checking, setChecking] = useState(false);
  const [paywall, setPaywall] = useState<ProFeature | null>(null);

  useEffect(() => {
    if (!userId || demo) return;
    let live = true;
    void readIsPro().then((isPro) => { if (live && isPro !== null) setLoaded({ userId, isPro }); });
    return () => { live = false; };
  }, [userId, demo]);

  const entitlement: Entitlement = demo ? 'pro'
    : userId && loaded?.userId === userId ? (loaded.isPro ? 'pro' : 'free') : 'loading';

  // Every signal carries tier, as on iOS.
  useEffect(() => { setAnalyticsTier(entitlement === 'loading' ? null : entitlement); }, [entitlement]);

  const ask = useCallback((feature: ProFeature) => {
    signal('paywall.shown', { source: feature });
    setPaywall(feature);
  }, []);

  const close = () => {
    if (paywall) signal('paywall.dismissed', { source: paywall });
    setPaywall(null);
  };

  const checkAgain = async () => {
    if (!userId) return;
    setChecking(true);
    const isPro = await readIsPro();
    if (isPro !== null) setLoaded({ userId, isPro });
    setChecking(false);
  };

  const value = useMemo(() => ({ entitlement, ask }), [entitlement, ask]);
  return (
    <Ctx.Provider value={value}>
      {children}
      {/* Becoming Pro (checked again after subscribing) closes the sheet by itself. */}
      {/* .stl: the sheet sits beside the page frame, so it takes the page's type styles itself. */}
      {paywall && entitlement !== 'pro' && (
        <div className="stl"><Paywall lead={paywall} checking={checking} onCheck={() => void checkAgain()} onClose={close} /></div>
      )}
    </Ctx.Provider>
  );
}

export function useEntitlement(): Entitlement {
  return useContext(Ctx).entitlement;
}

/** A Pro feature's state here, and `ask()` to open the paywall for it. */
export function useGate(feature: ProFeature, ctx?: GateContext): { state: GateState; open: boolean; ask(): void } {
  const { entitlement, ask } = useContext(Ctx);
  const state = gate(feature, entitlement, ctx);
  return { state, open: state === 'open', ask: () => ask(feature) };
}

/** The small lock that sits on a locked control. */
export function LockBadge({ size = 12 }: { size?: number }) {
  return <Icon name="lock.fill" size={size} color={C.label3} />;
}

/** Stands in for a locked section: what it is, and a way into the paywall. Renders nothing while the entitlement loads. */
export function LockedPanel({ feature, title, text, compact, onGray }: {
  feature: ProFeature; title: string; text: string; compact?: boolean;
  /** On a gray page (rather than inside a white card), the panel is a white card itself. */
  onGray?: boolean;
}) {
  const g = useGate(feature);
  if (g.state !== 'locked') return null;
  return (
    <div style={{ display: 'flex', gap: 12, alignItems: 'flex-start', background: onGray ? '#fff' : C.gray6, borderRadius: 12, padding: compact ? '12px 14px' : '18px 18px' }}>
      <Icon name="lock.fill" size={compact ? 16 : 20} color={C.label2} style={{ marginTop: 1 }} />
      <span style={{ flex: 1, minWidth: 0 }}>
        <span style={{ display: 'block', fontSize: compact ? 14 : 15, fontWeight: 600 }}>{title}</span>
        <span style={{ display: 'block', fontSize: 13, color: C.label2, lineHeight: 1.4, marginTop: 2 }}>{text}</span>
        <button type="button" className="h-link" onClick={g.ask} style={{ marginTop: 8, fontSize: 13, fontWeight: 600, color: C.blue }}>See what&apos;s in Pro</button>
      </span>
    </div>
  );
}

const TINT: Record<string, string> = { blue: C.blue, green: C.green, purple: '#AF52DE', red: C.red, orange: C.orange };

function Paywall({ lead, checking, onCheck, onClose }: { lead: ProFeature; checking: boolean; onCheck(): void; onClose(): void }) {
  const all = PAYWALL_GROUPS.flatMap((g) => g.features);
  const hero = all.find((f) => f.id === lead);
  return (
    <Dialog title="Stack the Lineup Pro" subtitle={hero ? `${hero.title} is a Pro feature` : undefined} onClose={onClose} width={520}
      footer={<>
        <span style={{ flex: 1 }} />
        <HeaderButton onClick={onClose}>Not now</HeaderButton>
        <HeaderButton kind="primary" onClick={onCheck} disabled={checking}>{checking ? 'Checking…' : 'I subscribed. Check again'}</HeaderButton>
      </>}>
      <p style={{ margin: '0 4px', fontSize: 14, lineHeight: 1.5 }}>
        Pro is sold in Stack the Lineup on iPhone and iPad for now. Subscribing on the web is coming soon.
        If your account already has Pro, check again.
      </p>
      {PAYWALL_GROUPS.map((g) => (
        <section key={g.title}>
          <div style={{ fontSize: 13, fontWeight: 600, padding: '0 4px', marginBottom: 8 }}>{g.title}</div>
          <div style={{ background: '#fff', borderRadius: 12, overflow: 'hidden' }}>
            {g.features.map((f, i) => (
              <div key={f.id} style={{ display: 'flex', gap: 12, alignItems: 'flex-start', padding: '12px 16px', borderTop: i ? C.hair : undefined,
                background: f.id === lead ? 'rgba(0,122,255,0.06)' : undefined }}>
                <Icon name={f.icon} size={18} color={TINT[f.color] ?? C.blue} style={{ marginTop: 1, flexShrink: 0 }} />
                <span>
                  <span style={{ display: 'block', fontSize: 14, fontWeight: 600 }}>{f.title}</span>
                  <span style={{ display: 'block', fontSize: 13, color: C.label2, lineHeight: 1.4 }}>{f.text}</span>
                </span>
              </div>
            ))}
          </div>
        </section>
      ))}
    </Dialog>
  );
}
