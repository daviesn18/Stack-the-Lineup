import { useLocalSearchParams } from 'expo-router';

import { JoinPage } from '@/workbench/JoinPage';

/** An assistant coach's invite link (app.stackthelineup.com/join/<token>), signed in or out. */
export default function Join() {
  const { token } = useLocalSearchParams<{ token: string }>();
  return <JoinPage token={token} />;
}
