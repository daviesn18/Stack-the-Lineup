// Native (Android, later): invite links open the web page or the iPhone app
// for now. The web uses JoinPage.web.tsx.

import { Body, Page, Title } from '@/ui/kit';

export function JoinPage(_: { token: string | undefined; resume?: boolean }) {
  return (
    <Page width={440}>
      <Title>Open this link on the web</Title>
      <Body muted>Team invites open at app.stackthelineup.com, or in Stack the Lineup on iPhone and iPad.</Body>
    </Page>
  );
}
