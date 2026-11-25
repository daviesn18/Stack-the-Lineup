import { useLocalSearchParams } from 'expo-router';

import { JoinPage } from '@/workbench/JoinPage';

/** An assistant coach's invite link (app.stackthelineup.com/join/<token>), signed in or out. */
export default function Join() {
  const { token, resume } = useLocalSearchParams<{ token: string; resume?: string }>();
  return <JoinPage token={token} resume={resume === '1'} />;
}
