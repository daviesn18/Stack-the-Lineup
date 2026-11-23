import { billingFor, periodWords, proFromRow, readAccountPro, subscriptionWords } from '../billing';

jest.mock('../supabase', () => ({ supabase: {} }));

const NOW = new Date('2026-11-22T12:00:00Z');

describe('proFromRow', () => {
  it('is free with no row', () => {
    expect(proFromRow(null, NOW)).toEqual({ isPro: false, expiresAt: null, store: null, managementUrl: null, source: null });
  });
  it('is Pro until it expires', () => {
    expect(proFromRow({ is_pro: true, expires_at: '2027-11-22T00:00:00Z', store: 'stripe' }, NOW).isPro).toBe(true);
    expect(proFromRow({ is_pro: true, expires_at: '2026-11-01T00:00:00Z', store: 'stripe' }, NOW).isPro).toBe(false);
  });
  it('treats no expiry as lifetime', () => {
    expect(proFromRow({ is_pro: true, expires_at: null, store: 'app_store' }, NOW).isPro).toBe(true);
  });
  it('drops a store it does not know', () => {
    expect(proFromRow({ is_pro: true, store: 'amazon' }, NOW).store).toBeNull();
  });
});

describe('billingFor', () => {
  const pro = (over: Partial<ReturnType<typeof proFromRow>>) => ({ ...proFromRow({ is_pro: true }, NOW), ...over });
  it('is free when not Pro, whatever the store', () => {
    expect(billingFor(proFromRow({ is_pro: false, store: 'stripe' }, NOW))).toEqual({ kind: 'free' });
  });
  it('sends a web subscriber to the Stripe portal', () => {
    expect(billingFor(pro({ store: 'stripe', expiresAt: '2027-11-22T00:00:00Z', managementUrl: 'https://billing.example/p' })))
      .toEqual({ kind: 'web', renewsOrEnds: '2027-11-22T00:00:00Z', manageUrl: 'https://billing.example/p' });
  });
  it('keeps an App Store subscriber on their iPhone', () => {
    expect(billingFor(pro({ store: 'app_store', expiresAt: '2027-01-01T00:00:00Z', managementUrl: 'https://apps.apple.com/account/subscriptions' })))
      .toMatchObject({ kind: 'app_store', lifetime: false });
  });
  it('knows the lifetime purchase', () => {
    expect(billingFor(pro({ store: 'app_store', expiresAt: null }))).toMatchObject({ kind: 'app_store', lifetime: true });
  });
  it('lets a hand grant win over the store RevenueCat reported', () => {
    expect(billingFor(pro({ source: 'manual', store: 'promotional' }))).toEqual({ kind: 'granted' });
    expect(billingFor(pro({ source: 'manual', store: 'stripe' }))).toEqual({ kind: 'granted' });
  });
  it('treats a promotional grant as granted', () => {
    expect(billingFor(pro({ source: 'revenuecat', store: 'promotional' }))).toEqual({ kind: 'granted' });
  });
});

describe('subscriptionWords', () => {
  it('dates a web subscription', () => {
    expect(subscriptionWords({ kind: 'web', renewsOrEnds: '2027-11-22T12:00:00Z', manageUrl: null }, 'en-US').label)
      .toBe('Pro through November 22, 2027');
  });
  it('never sends an App Store subscriber to Stripe', () => {
    expect(subscriptionWords({ kind: 'app_store', lifetime: false, manageUrl: null }).help).toMatch(/iPhone or iPad/);
    expect(subscriptionWords({ kind: 'app_store', lifetime: true, manageUrl: null }).label).toBe('Pro for life');
  });
});

describe('periodWords', () => {
  it('reads the durations RevenueCat sends', () => {
    expect(periodWords('P1Y')).toEqual({ per: 'year', days: null });
    expect(periodWords('P1M')).toEqual({ per: 'month', days: null });
    expect(periodWords('P7D')).toEqual({ per: '7 days', days: 7 });
    expect(periodWords('P1W')).toEqual({ per: 'week', days: 7 });
    expect(periodWords(null)).toEqual({ per: null, days: null });
    expect(periodWords('nonsense')).toEqual({ per: null, days: null });
  });
});

describe('readAccountPro', () => {
  const { supabase } = jest.requireMock('../supabase') as { supabase: { from: jest.Mock } };
  const query = (result: unknown) => ({ select: jest.fn(() => ({ maybeSingle: jest.fn(async () => result) })) });

  it('reads the RevenueCat columns', async () => {
    supabase.from = jest.fn(() => query({ data: { is_pro: true, store: 'stripe', management_url: 'https://p' }, error: null }));
    expect(await readAccountPro()).toMatchObject({ isPro: true, store: 'stripe', managementUrl: 'https://p' });
  });

  it('falls back to the base columns on a database without them', async () => {
    supabase.from = jest.fn()
      .mockReturnValueOnce(query({ data: null, error: { code: '42703', message: 'column entitlements.store does not exist' } }))
      .mockReturnValueOnce(query({ data: { is_pro: true, expires_at: null, source: 'manual' }, error: null }));
    expect(await readAccountPro()).toMatchObject({ isPro: true, store: null, source: 'manual' });
  });

  it('returns null on any other error, so the last answer stands', async () => {
    supabase.from = jest.fn(() => query({ data: null, error: { code: 'PGRST301', message: 'JWT expired' } }));
    expect(await readAccountPro()).toBeNull();
    expect(supabase.from).toHaveBeenCalledTimes(1);
  });
});
