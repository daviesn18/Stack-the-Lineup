import { StyleSheet, Text, View } from 'react-native';

// Placeholder until the sign-in and team screens land (Web 9, Web 10).
export default function Home() {
  return (
    <View style={styles.screen}>
      <Text style={styles.title}>Stack the Lineup</Text>
      <Text style={styles.body}>Web pilot: coming soon.</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, alignItems: 'center', justifyContent: 'center', gap: 8, padding: 24 },
  title: { fontSize: 28, fontWeight: '700' },
  body: { fontSize: 16, opacity: 0.7 },
});
