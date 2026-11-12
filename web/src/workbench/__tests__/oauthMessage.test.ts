import { oauthMessage } from '../oauthMessage';

describe('Apple / Google sign-in errors', () => {
  it('says nothing when there was no error', () => {
    expect(oauthMessage(null)).toBeNull();
  });

  it('explains sign-ups being off in coach terms', () => {
    const byCode = oauthMessage({ code: 'signup_disabled', description: 'Signups not allowed for this instance' });
    expect(byCode).toMatch(/isn't linked to a Stack the Lineup account/);
    expect(byCode).toMatch(/invite-only/);
    // Older servers send only the description.
    expect(oauthMessage({ code: 'server_error', description: 'Signups not allowed for this instance' })).toBe(byCode);
  });

  it('stays quiet when the coach backed out', () => {
    expect(oauthMessage({ code: 'access_denied', description: 'The user canceled the sign-in' })).toBeNull();
  });

  it('passes anything else through', () => {
    expect(oauthMessage({ code: 'server_error', description: 'Unable to exchange external code' }))
      .toBe("Sign-in didn't finish: Unable to exchange external code");
    expect(oauthMessage({ code: 'server_error', description: '' })).toBe("Sign-in didn't finish. Try again.");
  });
});
