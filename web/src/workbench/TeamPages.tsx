// Native (Android, later): the team list and .stlteam import on the shared
// React Native kit. The web uses TeamPages.web.tsx.

import * as DocumentPicker from 'expo-document-picker';
import { useFocusEffect, useRouter } from 'expo-router';
import { useCallback, useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';

import { useAuth, useIsPro } from '@/data/auth';
import { supabase } from '@/data/supabase';
import { importTeam, listTeams, previewImport, type ImportPreview, type TeamSummary } from '@/data/teams';
import { Body, Button, Card, Notice, Page, Title, usePalette } from '@/ui/kit';

export function TeamsPage() {
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
          <Button title="Sign out" kind="secondary" onPress={() => supabase.auth.signOut({ scope: 'local' })} />
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

type Conflict = 'alreadyYours' | 'ownedElsewhere' | null;

export function ImportPage() {
  const router = useRouter();
  const [preview, setPreview] = useState<ImportPreview | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [conflict, setConflict] = useState<Conflict>(null);
  const [busy, setBusy] = useState(false);

  async function pick() {
    setError(null); setConflict(null); setPreview(null);
    const result = await DocumentPicker.getDocumentAsync({ type: '*/*', copyToCacheDirectory: true, multiple: false });
    if (result.canceled) return;
    const asset = result.assets[0];
    if (!asset.name.toLowerCase().endsWith('.stlteam')) {
      setError(`"${asset.name}" isn't a team file. Pick the .stlteam file you exported from the iPhone app.`);
      return;
    }
    try {
      const text = asset.file ? await asset.file.text() : await (await fetch(asset.uri)).text();
      setPreview(previewImport(text));
    } catch (e) {
      setError((e as Error).message);
    }
  }

  async function run(mode: 'new' | 'replace' | 'copy') {
    if (!preview) return;
    setBusy(true); setError(null);
    const outcome = await importTeam(preview.payload, mode);
    setBusy(false);
    if (outcome.ok) router.replace({ pathname: '/team/[id]', params: { id: outcome.teamId } });
    else if (outcome.reason === 'error') setError(outcome.message);
    else setConflict(outcome.reason);
  }

  const t = preview?.team;
  return (
    <Page width={560}>
      <Title>Import a team</Title>
      <Body muted>
        Choose a .stlteam file exported from Stack the Lineup on iPhone. You get the roster, rules, schedule,
        templates, game history and saved lineups. The web pilot keeps its own copy: later changes on your
        iPhone don&apos;t sync here.
      </Body>

      <Button title={preview ? 'Choose a different file' : 'Choose .stlteam file'} kind={preview ? 'secondary' : 'primary'} onPress={pick} />
      {error && <Notice kind="error">{error}</Notice>}

      {t && preview && (
        <Card>
          <Body style={{ fontSize: 20, fontWeight: '700' }}>{t.name || 'Untitled team'}</Body>
          <Body muted>
            Exported {preview.exportedAt.toLocaleDateString()} from app version {preview.appVersion}
          </Body>
          <Body>
            {t.players.length} players · {t.gameInningCount}-inning games · {t.scheduledGames.length} scheduled games ·{' '}
            {preview.savedLineups} saved {preview.savedLineups === 1 ? 'lineup' : 'lineups'} · {t.gameLogs.length} archived
            {t.gameLogs.length === 1 ? ' game' : ' games'} · {t.lineupTemplates.length}{' '}
            {t.lineupTemplates.length === 1 ? 'template' : 'templates'}
          </Body>
          {preview.notes.map((n) => <Notice key={n} kind="warn">{n}</Notice>)}

          {conflict === 'alreadyYours' && (
            <Notice kind="warn">You already have this team here. Replacing it discards the web copy, including any changes made on the web.</Notice>
          )}
          {conflict === 'ownedElsewhere' && (
            <Notice kind="warn">
              Another coach has already imported this team (it&apos;s probably a shared team on iPhone). You can import your
              own separate copy; the two won&apos;t be linked.
            </Notice>
          )}

          <View style={{ gap: 8 }}>
            {conflict === null && <Button title="Import team" onPress={() => run('new')} busy={busy} />}
            {conflict === 'alreadyYours' && <Button title="Replace my web copy" kind="danger" onPress={() => run('replace')} busy={busy} />}
            {conflict === 'ownedElsewhere' && <Button title="Import as a separate copy" onPress={() => run('copy')} busy={busy} />}
          </View>
        </Card>
      )}

      <Button title="Back to teams" kind="secondary" onPress={() => router.replace('/')} />
    </Page>
  );
}
