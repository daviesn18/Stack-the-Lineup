import * as DocumentPicker from 'expo-document-picker';
import { useRouter } from 'expo-router';
import { useState } from 'react';
import { View } from 'react-native';

import { importTeam, previewImport, type ImportPreview } from '@/data/teams';
import { Body, Button, Card, Notice, Page, Title } from '@/ui/kit';

type Conflict = 'alreadyYours' | 'ownedElsewhere' | null;

export default function Import() {
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
