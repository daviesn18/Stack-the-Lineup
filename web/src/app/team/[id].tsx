import { useLocalSearchParams, useRouter } from 'expo-router';
import { useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';

import { TeamProvider, useTeam } from '@/data/teamStore';
import { LineupTab } from '@/features/lineup/LineupTab';
import { RosterTab } from '@/features/roster/RosterTab';
import { Button, Loading, Notice, Page, usePalette } from '@/ui/kit';

type Tab = 'lineup' | 'roster';

export default function TeamScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  return (
    <TeamProvider teamId={id}>
      <TeamPage />
    </TeamProvider>
  );
}

function TeamPage() {
  const router = useRouter();
  const c = usePalette();
  const { data, loadError, saveError, saving, dismissSaveError } = useTeam();
  const [tab, setTab] = useState<Tab>('lineup');

  if (loadError) {
    return (
      <Page>
        <Notice kind="error">Couldn&apos;t open this team: {loadError}</Notice>
        <Button title="Back to teams" kind="secondary" onPress={() => router.replace('/')} />
      </Page>
    );
  }
  if (!data) return <Loading />;

  return (
    <Page width={1280}>
      <View style={styles.header}>
        <Pressable accessibilityRole="link" onPress={() => router.replace('/')}>
          <Text style={{ color: c.accent, fontSize: 15 }}>‹ Teams</Text>
        </Pressable>
        <View style={[styles.swatch, { backgroundColor: `#${data.team.colorHex}` }]} />
        <Text accessibilityRole="header" style={[styles.teamName, { color: c.ink }]}>{data.team.name || 'Untitled team'}</Text>
        <Text style={{ color: c.muted, marginLeft: 'auto' }}>{saving ? 'Saving…' : 'All changes saved'}</Text>
      </View>

      <View style={[styles.tabs, { borderColor: c.line }]} accessibilityRole="tablist">
        {(['lineup', 'roster'] as Tab[]).map((t) => (
          <Pressable key={t} accessibilityRole="tab" accessibilityState={{ selected: tab === t }} onPress={() => setTab(t)}
            style={[styles.tab, tab === t && { borderBottomColor: c.accent }]}>
            <Text style={[styles.tabText, { color: tab === t ? c.ink : c.muted }]}>{t === 'lineup' ? 'Lineup' : `Roster (${data.players.length})`}</Text>
          </Pressable>
        ))}
      </View>

      {saveError && (
        <Pressable onPress={dismissSaveError}><Notice kind="error">{saveError} (Click to dismiss.)</Notice></Pressable>
      )}

      {tab === 'lineup' ? <LineupTab /> : <RosterTab />}
    </Page>
  );
}

const styles = StyleSheet.create({
  header: { flexDirection: 'row', alignItems: 'center', gap: 12, flexWrap: 'wrap' },
  swatch: { width: 10, height: 28, borderRadius: 2 },
  teamName: { fontSize: 26, fontWeight: '700', letterSpacing: -0.3 },
  tabs: { flexDirection: 'row', borderBottomWidth: 1, gap: 8 },
  tab: { paddingVertical: 10, paddingHorizontal: 12, borderBottomWidth: 3, borderBottomColor: 'transparent', marginBottom: -1 },
  tabText: { fontSize: 16, fontWeight: '600' },
});
