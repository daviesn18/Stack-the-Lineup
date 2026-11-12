import { gate, PAYWALL_GROUPS, type ProFeature } from '../proGate';

const ALL: ProFeature[] = ['autofill', 'player_preferences', 'lineup_template', 'pdf_export', 'shared_teams', 'game_history', 'pitch_tracking'];

describe('Pro gate (matches iOS)', () => {
  it('opens everything for Pro', () => {
    for (const f of ALL) expect(gate(f, 'pro', { templateCount: 5 })).toBe('open');
  });

  it('locks every Pro feature for a free coach', () => {
    for (const f of ALL) expect(gate(f, 'free', { templateCount: 1 })).toBe('locked');
  });

  it('shows neither state while the entitlement loads', () => {
    for (const f of ALL) expect(gate(f, 'loading', { templateCount: 1 })).toBe('pending');
  });

  it('keeps the first template free', () => {
    expect(gate('lineup_template', 'free', { templateCount: 0 })).toBe('open');
    expect(gate('lineup_template', 'free')).toBe('open');
    expect(gate('lineup_template', 'loading', { templateCount: 0 })).toBe('open');
    expect(gate('lineup_template', 'free', { templateCount: 1 })).toBe('locked');
  });

  it('lets a read-only coach on a received team print the Coaches Guide', () => {
    expect(gate('pdf_export', 'free', { receivedReadOnly: true })).toBe('open');
    expect(gate('pdf_export', 'free', { receivedReadOnly: false })).toBe('locked');
    // Only the PDF: a received team doesn't unlock the coach's other Pro features.
    expect(gate('autofill', 'free', { receivedReadOnly: true })).toBe('locked');
  });

  it('lists every gated feature on the paywall, plus nothing unknown', () => {
    const ids = PAYWALL_GROUPS.flatMap((g) => g.features.map((f) => f.id));
    for (const f of ALL) expect(ids).toContain(f);
    expect(ids).toHaveLength(ALL.length);
  });
});
