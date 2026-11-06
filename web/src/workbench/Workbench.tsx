// Native (Android, later): the workbench is web only for now.

import { Body, Page } from '@/ui/kit';

export function Workbench(_: { demo?: boolean }) {
  return (
    <Page>
      <Body>This screen is built for a laptop browser. Open Stack the Lineup on the web to plan lineups.</Body>
    </Page>
  );
}
