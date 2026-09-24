import { useFocusEffect, useRouter } from 'expo-router';
import { useCallback, useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';

import { useAuth, useIsPro } from '@/data/auth';
import { supabase } from '@/data/supabase';
import { listTeams, type TeamSummary } from '@/data/teams';
import { Body, Button, Card, Notice, Page, Title, usePalette } from '@/ui/kit';

export default function Teams() {
  const router = useRouter();
  const c = usePalette();
  const { session } = useAuth();
  const isPro = useIsPro();
  const [teams, setTeams] = useState<TeamSummary[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  useFocusEffect(useCallback(() => {
    listTeams().then(setTeams, (e: Error) => setError(e.message));
  }, []));

  return (
    <Page>
      <View style={styles.header}>
        <Title>Your teams</Title>
        <View style={styles.headerRight}>
          {isPro && <Text style={[styles.pro, { color: c.accent, borderColor: c.accent }]}>PRO</Text>}
          <Text style={{ color: c.muted }}>{session?.user.email}</Text>
          <Button title="Sign out" kind="secondary" onPress={() => supabase.auth.signOut()} />
        </View>
      </View>

      {error && <Notice kind="error">Couldn&apos;t load your teams: {error}</Notice>}

      {teams?.length === 0 && (
        <Card>
          <Body>No teams yet. Bring one over from the iPhone app:</Body>
          <Body muted>In Stack the Lineup on iPhone, open the team, choose Export Team, and save the .stlteam file somewhere this computer can reach (AirDrop, Files, or email it to yourself).</Body>
        </Card>
      )}

      {teams?.map((t) => (
        <Pressable key={t.id} accessibilityRole="link" onPress={() => router.push({ pathname: '/team/[id]', params: { id: t.id } })}>
        <Card>
          <View style={styles.teamRow}>
            <View style={[styles.swatch, { backgroundColor: `#${t.colorHex}` }]} />
            <View style={{ flex: 1 }}>
              <Text style={[styles.teamName, { color: c.ink }]}>{t.name || 'Untitled team'}</Text>
              <Text style={{ color: c.muted }}>{t.playerCount} {t.playerCount === 1 ? 'player' : 'players'}</Text>
            </View>
          </View>
        </Card>
        </Pressable>
      ))}

      <Button title="Import a team from iPhone" kind={teams?.length ? 'secondary' : 'primary'} onPress={() => router.push('/import')} />
    </Page>
  );
}

const styles = StyleSheet.create({
  header: { flexDirection: 'row', flexWrap: 'wrap', alignItems: 'center', justifyContent: 'space-between', gap: 12 },
  headerRight: { flexDirection: 'row', flexWrap: 'wrap', alignItems: 'center', gap: 12 },
  pro: { fontSize: 12, fontWeight: '700', letterSpacing: 1, borderWidth: 1, borderRadius: 4, paddingHorizontal: 6, paddingVertical: 2 },
  teamRow: { flexDirection: 'row', alignItems: 'center', gap: 12 },
  swatch: { width: 14, height: 40, borderRadius: 3 },
  teamName: { fontSize: 18, fontWeight: '600' },
});
