// Development-only preview of the Lineup and Roster tabs on a made-up team,
// held in memory (nothing is read from or written to Supabase). Renders nothing
// in production builds.

import { useMemo, useState } from 'react';
import { Pressable, Text, View } from 'react-native';

import { TeamProvider } from '@/data/teamStore';
import { demoTeam } from '@/dev/demoTeam';
import { LineupTab } from '@/features/lineup/LineupTab';
import { RosterTab } from '@/features/roster/RosterTab';
import { Notice, Page, usePalette } from '@/ui/kit';

export default function DevGrid() {
  const c = usePalette();
  const demo = useMemo(() => demoTeam(), []);
  const [tab, setTab] = useState<'lineup' | 'roster'>('lineup');
  if (!__DEV__) return null;
  return (
    <TeamProvider teamId="DEMO" demo={demo}>
      <Page width={1280}>
        <Notice kind="warn">Development preview: made-up team, nothing is saved.</Notice>
        <View style={{ flexDirection: 'row', gap: 16 }}>
          {(['lineup', 'roster'] as const).map((t) => (
            <Pressable key={t} onPress={() => setTab(t)}>
              <Text style={{ color: tab === t ? c.accent : c.muted, fontWeight: '700', fontSize: 16 }}>{t}</Text>
            </Pressable>
          ))}
        </View>
        {tab === 'lineup' ? <LineupTab /> : <RosterTab />}
      </Page>
    </TeamProvider>
  );
}
