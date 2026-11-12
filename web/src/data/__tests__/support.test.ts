import { buildLabel, supportMailto } from '../support';

describe('support email', () => {
  it('labels CI and local builds', () => {
    expect(buildLabel('abc1234')).toBe('Web build abc1234');
    expect(buildLabel('')).toBe('Web development build');
  });

  it('addresses support with the build, host and browser in the body', () => {
    const url = supportMailto({ commit: 'abc1234', userAgent: 'Mozilla/5.0 & co', host: 'app.stackthelineup.com' });
    expect(url.startsWith('mailto:support@stackthelineup.com?subject=')).toBe(true);
    const body = decodeURIComponent(url.split('&body=')[1]);
    expect(body).toContain('Web build abc1234');
    expect(body).toContain('Site: app.stackthelineup.com');
    expect(body).toContain('Browser: Mozilla/5.0 & co');
    // The ampersand in the user agent is encoded, so it can't split the query.
    expect(url.split('&')).toHaveLength(2);
  });
});
