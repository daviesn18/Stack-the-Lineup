import { useLocalSearchParams, useRouter } from 'expo-router';

import { TeamProvider, useTeam } from '@/data/teamStore';
import { Button, Loading, Notice, Page } from '@/ui/kit';
import { Workbench } from '@/workbench/Workbench';

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
  const { data, loadError } = useTeam();
  if (loadError) {
    return (
      <Page>
        <Notice kind="error">Couldn&apos;t open this team: {loadError}</Notice>
        <Button title="Back to teams" kind="secondary" onPress={() => router.replace('/')} />
      </Page>
    );
  }
  if (!data) return <Loading />;
  return <Workbench />;
}
