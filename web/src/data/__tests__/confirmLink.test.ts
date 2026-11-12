import { needsPassword, parseConfirmLink } from '../confirmLink';

describe('auth confirm links', () => {
  it('reads the token and kind on /auth/confirm', () => {
    expect(parseConfirmLink('/auth/confirm', '?token_hash=abc123&type=invite')).toEqual({ tokenHash: 'abc123', type: 'invite' });
    expect(parseConfirmLink('/auth/confirm/', 'token_hash=abc&type=recovery')).toEqual({ tokenHash: 'abc', type: 'recovery' });
    expect(parseConfirmLink('/auth/confirm', '?type=email&token_hash=x')).toEqual({ tokenHash: 'x', type: 'email' });
    expect(parseConfirmLink('/auth/confirm', '?token_hash=x&type=email_change')?.type).toBe('email_change');
  });

  it('ignores other pages, missing tokens and unknown kinds', () => {
    expect(parseConfirmLink('/', '?token_hash=abc&type=invite')).toBeNull();
    expect(parseConfirmLink('/auth/confirm', '?type=invite')).toBeNull();
    expect(parseConfirmLink('/auth/confirm', '?token_hash=%20&type=invite')).toBeNull();
    expect(parseConfirmLink('/auth/confirm', '?token_hash=abc&type=magiclink')).toBeNull();
    expect(parseConfirmLink('/auth/confirm', '')).toBeNull();
  });

  it('sends invites and resets to Choose a password', () => {
    expect(needsPassword('invite')).toBe(true);
    expect(needsPassword('recovery')).toBe(true);
    expect(needsPassword('email')).toBe(false);
    expect(needsPassword('email_change')).toBe(false);
  });
});
