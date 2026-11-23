// Web checkout and the coach's subscription, read from the account.
//
// Pro is account-level. Whatever the store (App Store on iPhone, Stripe on the
// web through RevenueCat Billing), RevenueCat tells the revenuecat-webhook
// Edge Function, which writes public.entitlements. That row is the one answer
// every app reads; this file only adds what the web needs on top of it:
//
// - selling Pro here, with RevenueCat's purchases-js (its own Stripe checkout
//   sheet), under the same app user ID iOS uses: the Supabase user id,
//   lower-cased (RevenueCat ids are case-sensitive);
// - saying where an active Pro is billed, so a coach who pays through the App
//   Store is sent to their iPhone to manage it instead of to Stripe.
//
// purchases-js loads only when a coach opens the paywall, so every other page
// stays as light as it was.

import type { Package, Purchases } from '@revenuecat/purchases-js';

import { supabase } from './supabase';

/** RevenueCat's public Web Billing key (rcb_…, or rcb_sb_… for the sandbox). Unset turns web checkout off. */
const WEB_KEY = process.env.EXPO_PUBLIC_REVENUECAT_WEB_KEY ?? '';

/** The entitlement identifier in RevenueCat, the same one the webhook reads. */
export const ENTITLEMENT_ID = 'pro';

export const checkoutAvailable = WEB_KEY.length > 0;

export type Store = 'app_store' | 'play_store' | 'stripe' | 'promotional' | 'other';

/** The coach's entitlements row, as the web uses it. */
export interface AccountPro {
  isPro: boolean;
  /** When Pro ends. null = never (lifetime, a hand grant) or not Pro. */
  expiresAt: string | null;
  store: Store | null;
  /** RevenueCat's manage link: the Stripe customer portal, or Apple's subscriptions page. */
  managementUrl: string | null;
  /** 'manual' for Pro granted by hand from the dashboard. */
  source: string | null;
}

interface Row {
  is_pro?: boolean | null; expires_at?: string | null; store?: string | null;
  management_url?: string | null; source?: string | null;
}

const STORES: readonly Store[] = ['app_store', 'play_store', 'stripe', 'promotional', 'other'];

/** Pure: a row (or none) to what the web shows. An expired row isn't Pro, whatever is_pro says. */
export function proFromRow(row: Row | null | undefined, now: Date = new Date()): AccountPro {
  const expiresAt = row?.expires_at ?? null;
  const expired = expiresAt ? new Date(expiresAt) < now : false;
  const store = STORES.includes(row?.store as Store) ? (row!.store as Store) : null;
  return {
    isPro: !!row?.is_pro && !expired,
    expiresAt,
    store,
    managementUrl: row?.management_url ?? null,
    source: row?.source ?? null,
  };
}

/** The signed-in coach's row, or null when the read failed (keep the last answer rather than lock a Pro coach out). */
export async function readAccountPro(): Promise<AccountPro | null> {
  const { data, error } = await supabase.from('entitlements')
    .select('is_pro, expires_at, store, management_url, source').maybeSingle();
  if (error) return null;
  return proFromRow(data);
}

/** How the Account dialog describes the subscription. */
export type Billing =
  | { kind: 'free' }
  | { kind: 'web'; renewsOrEnds: string | null; manageUrl: string | null }
  | { kind: 'app_store'; lifetime: boolean; manageUrl: string | null }
  | { kind: 'granted' }
  | { kind: 'other'; manageUrl: string | null };

/** Pure: where an active Pro is billed, and so where the coach manages it. */
export function billingFor(pro: AccountPro): Billing {
  if (!pro.isPro) return { kind: 'free' };
  // A hand grant stays Pro whatever RevenueCat last said (see the webhook), so it wins.
  if (pro.source === 'manual') return { kind: 'granted' };
  switch (pro.store) {
    case 'stripe': return { kind: 'web', renewsOrEnds: pro.expiresAt, manageUrl: pro.managementUrl };
    case 'app_store': return { kind: 'app_store', lifetime: pro.expiresAt === null, manageUrl: pro.managementUrl };
    case 'promotional': return { kind: 'granted' };
    default: return { kind: 'other', manageUrl: pro.managementUrl };
  }
}

const dateWords = (iso: string, locale?: string) => new Date(iso).toLocaleDateString(locale, { year: 'numeric', month: 'long', day: 'numeric' });

/** Pure: the Subscription row's words for each way Pro can be billed. */
export function subscriptionWords(b: Billing, locale?: string): { label: string; help: string } {
  switch (b.kind) {
    case 'free': return { label: 'Free', help: 'Pro adds Auto-Fill, position preferences, the Coaches Guide PDF, game history and more.' };
    case 'web': return {
      label: b.renewsOrEnds ? `Pro through ${dateWords(b.renewsOrEnds, locale)}` : 'Pro',
      help: 'Billed yearly on the web. Change your card or cancel from Manage.',
    };
    case 'app_store': return b.lifetime
      ? { label: 'Pro for life', help: 'Bought in the iPhone app. Nothing to manage.' }
      : { label: 'Pro, billed by the App Store', help: 'Manage or cancel it on your iPhone or iPad: Settings, then your name, then Subscriptions.' };
    case 'granted': return { label: 'Pro', help: 'Added to your account by Stack the Lineup.' };
    case 'other': return { label: 'Pro', help: 'Manage it where you subscribed.' };
  }
}

// MARK: - Checkout

/** What the paywall's button says. */
export interface Offer {
  pkg: Package;
  /** "$9.99" */
  price: string;
  /** "year", "month", … */
  per: string | null;
  /** Days of free trial the product has. Whether this coach gets it is checked at checkout (never subscribed before). */
  trialDays: number | null;
}

let instance: { userId: string; purchases: Purchases } | null = null;

async function purchasesFor(userId: string): Promise<Purchases> {
  const appUserId = userId.toLowerCase();
  if (instance?.userId === appUserId) return instance.purchases;
  const { Purchases } = await import('@revenuecat/purchases-js');
  // One instance per page: a different coach signing in on this tab switches it.
  if (instance) {
    await instance.purchases.changeUser(appUserId);
    instance = { userId: appUserId, purchases: instance.purchases };
  } else {
    instance = { userId: appUserId, purchases: Purchases.configure({ apiKey: WEB_KEY, appUserId }) };
  }
  return instance.purchases;
}

/** Pure: an ISO 8601 duration (P1Y, P1M, P7D, P1W) to the paywall's words. */
export function periodWords(iso: string | null | undefined): { per: string | null; days: number | null } {
  const m = iso ? /^P(\d+)([DWMY])$/.exec(iso) : null;
  if (!m) return { per: null, days: null };
  const n = Number(m[1]);
  const unit = { D: 'day', W: 'week', M: 'month', Y: 'year' }[m[2] as 'D' | 'W' | 'M' | 'Y'];
  const days = m[2] === 'D' ? n : m[2] === 'W' ? n * 7 : null;
  return { per: n === 1 ? unit : `${n} ${unit}s`, days };
}

/** The yearly web package from the current offering, or null when RevenueCat has none set up for the web. */
export async function loadOffer(userId: string): Promise<Offer | null> {
  if (!checkoutAvailable) return null;
  const purchases = await purchasesFor(userId);
  const offerings = await purchases.getOfferings();
  const current = offerings.current;
  const pkg = current?.annual ?? current?.availablePackages[0] ?? null;
  if (!pkg) return null;
  const product = pkg.webBillingProduct;
  const option = product.defaultSubscriptionOption;
  return {
    pkg,
    price: product.currentPrice.formattedPrice,
    per: periodWords(product.normalPeriodDuration).per,
    trialDays: periodWords(option?.trial?.periodDuration).days,
  };
}

export type CheckoutResult =
  | { kind: 'purchased'; proActive: boolean }
  | { kind: 'cancelled' }
  | { kind: 'failed'; message: string };

/** Opens RevenueCat's checkout sheet. The email is the account's, so the coach isn't asked for it again. */
export async function checkout(userId: string, offer: Offer, email: string | undefined): Promise<CheckoutResult> {
  const { ErrorCode, PurchasesError } = await import('@revenuecat/purchases-js');
  try {
    const purchases = await purchasesFor(userId);
    const { customerInfo } = await purchases.purchase({ rcPackage: offer.pkg, customerEmail: email || undefined });
    return { kind: 'purchased', proActive: ENTITLEMENT_ID in customerInfo.entitlements.active };
  } catch (e) {
    if (e instanceof PurchasesError && e.errorCode === ErrorCode.UserCancelledError) return { kind: 'cancelled' };
    return { kind: 'failed', message: e instanceof Error ? e.message : 'Something went wrong.' };
  }
}

/**
 * After a purchase, the row turns Pro once RevenueCat's webhook lands, which
 * usually takes a few seconds. Polls for up to `timeoutMs`; the answer, or
 * null if it didn't arrive in time.
 */
export async function waitForPro(timeoutMs = 30_000, everyMs = 2_000): Promise<AccountPro | null> {
  const end = Date.now() + timeoutMs;
  while (Date.now() < end) {
    const pro = await readAccountPro();
    if (pro?.isPro) return pro;
    await new Promise((r) => setTimeout(r, everyMs));
  }
  return null;
}
