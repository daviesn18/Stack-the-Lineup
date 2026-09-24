// Development-only preview of the workbench on the design handoff's made-up
// team, held in memory (nothing is read from or written to Supabase). Renders
// nothing in production builds.

import { useMemo } from 'react';

import { TeamProvider } from '@/data/teamStore';
import { demoTeam } from '@/dev/demoTeam';
import { Workbench } from '@/workbench/Workbench';

export default function DevGrid() {
  const demo = useMemo(() => demoTeam(), []);
  if (!__DEV__) return null;
  return (
    <TeamProvider teamId="DEMO" demo={demo}>
      <Workbench demo />
    </TeamProvider>
  );
}
