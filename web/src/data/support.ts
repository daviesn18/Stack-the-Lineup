// Support contact for the web (iOS Settings › Support). The build id comes
// from the commit Cloudflare Workers Builds deployed (metro.config.js copies
// WORKERS_CI_COMMIT_SHA into EXPO_PUBLIC_BUILD_COMMIT); local builds have none.
//
// The email body carries only what helps debug: the build, the browser and
// the host. No team or player data, since rosters are about minors.

export const SUPPORT_EMAIL = 'support@stackthelineup.com';

/** Short commit of this build, or '' when it wasn't built by Cloudflare. */
export const BUILD_COMMIT = (process.env.EXPO_PUBLIC_BUILD_COMMIT ?? '').slice(0, 7);

/** "Web build abc1234", or "Web development build" off CI. */
export function buildLabel(commit: string = BUILD_COMMIT): string {
  return commit ? `Web build ${commit}` : 'Web development build';
}

export function supportMailto({ commit = BUILD_COMMIT, userAgent, host }: { commit?: string; userAgent: string; host: string }): string {
  const body = [
    '',
    '',
    '— Please keep this so we can help —',
    buildLabel(commit),
    `Site: ${host}`,
    `Browser: ${userAgent}`,
  ].join('\n');
  const q = `subject=${encodeURIComponent('Stack the Lineup web support')}&body=${encodeURIComponent(body)}`;
  return `mailto:${SUPPORT_EMAIL}?${q}`;
}
