// Pro for the workbench: one entitlement read for the whole page (not one per
// locked control), the gate hook every Pro feature uses, and the paywall sheet.
//
// The paywall sells the yearly subscription through RevenueCat's checkout
// (see data/billing), and tells a coach who already pays on iPhone how to bring
// that Pro here. Signals match iOS: paywall.shown / paywall.dismissed + source,
// plus the purchase.* signals for the web checkout.

import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from 'react';

import { useAuth } from '@/data/auth';
import { setAnalyticsTier, signal } from '@/data/analytics';
import { checkout, checkoutAvailable, loadOffer, readAccountPro, waitForPro, type Offer } from '@/data/billing';

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
  return (await readAccountPro())?.isPro ?? null;
}

const Ctx = createContext<ProState>({ entitlement: 'pro', ask: () => {} });
/** Whether a ProProvider is above: outside one (the team list), there's no paywall to open. */
const HasProvider = createContext(false);

/** `demo` (the signed-out demo grid) is treated as Pro so every feature can be shown. */
export function ProProvider({ demo, children }: { demo?: boolean; children: ReactNode }) {
  const { session } = useAuth();
  const userId = session?.user.id;
  const email = session?.user.email;
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

  /** RevenueCat already says Pro: unlock now, and let the row catch up behind it. */
  const purchased = (proActive: boolean) => {
    if (!userId) return;
    if (proActive) setLoaded({ userId, isPro: true });
    void waitForPro().then((pro) => { if (pro) setLoaded({ userId, isPro: true }); });
  };

  const value = useMemo(() => ({ entitlement, ask }), [entitlement, ask]);
  return (
    <HasProvider.Provider value={!demo}>
    <Ctx.Provider value={value}>
      {children}
      {/* Becoming Pro (checked again after subscribing) closes the sheet by itself. */}
      {/* .stl: the sheet sits beside the page frame, so it takes the page's type styles itself. */}
      {paywall && entitlement !== 'pro' && (
        <div className="stl">
          <Paywall lead={paywall} userId={userId} email={email} checking={checking}
            onCheck={() => void checkAgain()} onPurchased={purchased} onClose={close} />
        </div>
      )}
    </Ctx.Provider>
    </HasProvider.Provider>
  );
}

/** Opens the paywall, or null outside the workbench (and in the demo), where there's none. */
export function useProAsk(): ((feature: ProFeature) => void) | null {
  const has = useContext(HasProvider);
  const { ask } = useContext(Ctx);
  return has ? ask : null;
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

type Sale =
  | { step: 'loading' }
  | { step: 'ready'; offer: Offer }
  | { step: 'buying'; offer: Offer }
  | { step: 'finishing' }
  | { step: 'unavailable' }
  | { step: 'failed'; offer: Offer | null; message: string };

function Paywall({ lead, userId, email, checking, onCheck, onPurchased, onClose }: {
  lead: ProFeature; userId: string | undefined; email: string | undefined; checking: boolean;
  onCheck(): void; onPurchased(proActive: boolean): void; onClose(): void;
}) {
  const all = PAYWALL_GROUPS.flatMap((g) => g.features);
  const hero = all.find((f) => f.id === lead);
  const [sale, setSale] = useState<Sale>(checkoutAvailable && userId ? { step: 'loading' } : { step: 'unavailable' });

  useEffect(() => {
    if (!checkoutAvailable || !userId) return;
    let live = true;
    loadOffer(userId).then(
      (offer) => { if (live) setSale(offer ? { step: 'ready', offer } : { step: 'unavailable' }); },
      () => { if (live) setSale({ step: 'failed', offer: null, message: "Couldn't load the price. Check your connection and try again." }); },
    );
    return () => { live = false; };
  }, [userId]);

  const buy = async (offer: Offer) => {
    if (!userId) return;
    setSale({ step: 'buying', offer });
    signal('purchase.started', { source: lead, platform: 'web' });
    const result = await checkout(userId, offer, email);
    if (result.kind === 'purchased') {
      signal('purchase.completed', { source: lead, platform: 'web' });
      setSale({ step: 'finishing' });
      onPurchased(result.proActive);
    } else if (result.kind === 'cancelled') {
      signal('purchase.cancelled', { source: lead, platform: 'web' });
      setSale({ step: 'ready', offer });
    } else {
      signal('purchase.failed', { source: lead, platform: 'web' });
      setSale({ step: 'failed', offer, message: result.message });
    }
  };

  const offer = sale.step === 'ready' || sale.step === 'buying' ? sale.offer : sale.step === 'failed' ? sale.offer : null;
  const busy = sale.step === 'buying' || sale.step === 'finishing';
  const primary = sale.step === 'unavailable'
    ? <HeaderButton kind="primary" onClick={onCheck} disabled={checking}>{checking ? 'Checking…' : 'Check again'}</HeaderButton>
    : <HeaderButton kind="primary" onClick={() => { if (offer) void buy(offer); }} disabled={!offer || busy}>
        {sale.step === 'loading' ? 'Loading…' : sale.step === 'buying' ? 'Opening checkout…' : sale.step === 'finishing' ? 'Unlocking Pro…'
          : offer ? `Subscribe · ${offer.price}${offer.per ? ` a ${offer.per}` : ''}` : 'Subscribe'}
      </HeaderButton>;

  return (
    <Dialog title="Stack the Lineup Pro" subtitle={hero ? `${hero.title} is a Pro feature` : undefined} onClose={busy ? () => {} : onClose} width={520}
      footer={<>
        <span style={{ flex: 1 }} />
        <HeaderButton onClick={onClose} disabled={busy}>Not now</HeaderButton>
        {primary}
      </>}>
      {sale.step === 'unavailable' ? (
        <p style={{ margin: '0 4px', fontSize: 14, lineHeight: 1.5 }}>
          Pro is sold in Stack the Lineup on iPhone and iPad for now. Subscribing on the web is coming soon.
          If your account already has Pro, check again.
        </p>
      ) : (
        <>
          {offer?.trialDays && (
            <p style={{ margin: '0 4px', fontSize: 14, lineHeight: 1.5 }}>
              New subscribers get the first {offer.trialDays} days free. Cancel any time from Account.
            </p>
          )}
          {sale.step === 'finishing' && (
            <p role="status" style={{ margin: '0 4px', fontSize: 14, lineHeight: 1.5 }}>Thanks for subscribing. Unlocking Pro on your account…</p>
          )}
          {sale.step === 'failed' && (
            <div role="alert" style={{ display: 'flex', gap: 8, alignItems: 'flex-start', padding: '10px 12px', borderRadius: 8, background: 'rgba(255,59,48,0.08)', color: C.red, fontSize: 13, lineHeight: 1.4 }}>
              <Icon name="exclamationmark.triangle.fill" size={15} color={C.red} style={{ marginTop: 1 }} />
              <span>{sale.message} You haven&apos;t been charged.</span>
            </div>
          )}
          <AlreadyPro checking={checking} onCheck={onCheck} />
        </>
      )}
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

/** For a coach who already pays on iPhone: their Pro reaches the web once that app links it to this account. */
function AlreadyPro({ checking, onCheck }: { checking: boolean; onCheck(): void }) {
  return (
    <div style={{ display: 'flex', gap: 12, alignItems: 'flex-start', background: '#fff', borderRadius: 12, padding: '12px 16px' }}>
      <Icon name="iphone" size={18} color={C.label2} style={{ marginTop: 1, flexShrink: 0 }} />
      <span style={{ flex: 1, minWidth: 0 }}>
        <span style={{ display: 'block', fontSize: 14, fontWeight: 600 }}>Already Pro on iPhone or iPad?</span>
        <span style={{ display: 'block', fontSize: 13, color: C.label2, lineHeight: 1.4 }}>
          Open Stack the Lineup there and sign in with this account once. Your Pro then works here too, at no extra cost.
        </span>
        <button type="button" className="h-link" onClick={onCheck} disabled={checking}
          style={{ marginTop: 6, fontSize: 13, fontWeight: 600, color: C.blue }}>{checking ? 'Checking…' : 'I signed in. Check again'}</button>
      </span>
    </div>
  );
}
