// Small shared UI kit for the web pilot's simple pages (sign-in, team list,
// import): iOS system colors, a centered page, text, buttons, fields and
// notices. Plain React Native components so the same code runs on Android later.

import type { ReactNode } from 'react';
import {
  ActivityIndicator, Pressable, ScrollView, StyleSheet, Text, TextInput, View, useColorScheme,
  type TextInputProps,
} from 'react-native';

const light = {
  ground: '#F2F2F7', surface: '#FFFFFF', ink: '#000000', muted: 'rgba(60,60,67,0.6)', line: '#E5E5EA',
  accent: '#007AFF', accentInk: '#FFFFFF', accentSoft: 'rgba(0,122,255,0.12)',
  warn: '#C93400', warnSoft: 'rgba(255,149,0,0.12)', danger: '#FF3B30', dangerSoft: 'rgba(255,59,48,0.09)',
};
const dark: typeof light = {
  ground: '#000000', surface: '#1C1C1E', ink: '#FFFFFF', muted: 'rgba(235,235,245,0.6)', line: '#38383A',
  accent: '#0A84FF', accentInk: '#FFFFFF', accentSoft: 'rgba(10,132,255,0.18)',
  warn: '#FF9F0A', warnSoft: 'rgba(255,159,10,0.16)', danger: '#FF453A', dangerSoft: 'rgba(255,69,58,0.16)',
};
export type Palette = typeof light;
export const usePalette = (): Palette => (useColorScheme() === 'dark' ? dark : light);

export function Page({ children, width = 720 }: { children: ReactNode; width?: number }) {
  const c = usePalette();
  return (
    <ScrollView style={{ flex: 1, backgroundColor: c.ground }} contentContainerStyle={styles.pageOuter}>
      <View style={[styles.pageInner, { maxWidth: width }]}>{children}</View>
    </ScrollView>
  );
}

export function Loading() {
  const c = usePalette();
  return (
    <View style={[styles.center, { backgroundColor: c.ground }]}>
      <ActivityIndicator color={c.accent} />
    </View>
  );
}

export function Title({ children }: { children: ReactNode }) {
  const c = usePalette();
  return <Text accessibilityRole="header" style={[styles.title, { color: c.ink }]}>{children}</Text>;
}

export function Body({ children, muted, style }: { children: ReactNode; muted?: boolean; style?: object }) {
  const c = usePalette();
  return <Text style={[styles.body, { color: muted ? c.muted : c.ink }, style]}>{children}</Text>;
}

export function Card({ children }: { children: ReactNode }) {
  const c = usePalette();
  return <View style={[styles.card, { backgroundColor: c.surface, borderColor: c.line }]}>{children}</View>;
}

export function Button({
  title, onPress, kind = 'primary', busy, disabled,
}: { title: string; onPress: () => void; kind?: 'primary' | 'secondary' | 'danger'; busy?: boolean; disabled?: boolean }) {
  const c = usePalette();
  const bg = kind === 'primary' ? c.accent : kind === 'danger' ? c.danger : 'transparent';
  const fg = kind === 'secondary' ? c.accent : c.accentInk;
  const off = disabled || busy;
  return (
    <Pressable
      accessibilityRole="button"
      onPress={off ? undefined : onPress}
      style={({ pressed, hovered }: { pressed: boolean; hovered?: boolean }) => [
        styles.button,
        { backgroundColor: bg, borderColor: kind === 'secondary' ? c.line : bg, opacity: off ? 0.5 : pressed ? 0.8 : hovered ? 0.92 : 1 },
      ]}
    >
      {busy ? <ActivityIndicator color={fg} /> : <Text style={[styles.buttonText, { color: fg }]}>{title}</Text>}
    </Pressable>
  );
}

export function Field({ label, ...input }: { label: string } & TextInputProps) {
  const c = usePalette();
  return (
    <View style={styles.field}>
      <Text style={[styles.label, { color: c.muted }]}>{label}</Text>
      <TextInput
        placeholderTextColor={c.muted}
        {...input}
        style={[styles.input, { color: c.ink, backgroundColor: c.surface, borderColor: c.line }]}
      />
    </View>
  );
}

export function Notice({ kind = 'info', children }: { kind?: 'info' | 'warn' | 'error'; children: ReactNode }) {
  const c = usePalette();
  const [bg, fg] = kind === 'error' ? [c.dangerSoft, c.danger] : kind === 'warn' ? [c.warnSoft, c.warn] : [c.accentSoft, c.accent];
  return (
    <View accessibilityRole={kind === 'error' ? 'alert' : undefined} style={[styles.notice, { backgroundColor: bg, borderLeftColor: fg }]}>
      <Text style={[styles.body, { color: c.ink }]}>{children}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  pageOuter: { flexGrow: 1, paddingHorizontal: 16, paddingVertical: 32, alignItems: 'center' },
  pageInner: { width: '100%', gap: 16 },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  title: { fontSize: 28, fontWeight: '700', letterSpacing: -0.3 },
  body: { fontSize: 16, lineHeight: 23 },
  card: { borderWidth: 1, borderRadius: 10, padding: 16, gap: 12 },
  button: { minHeight: 44, borderRadius: 8, borderWidth: 1, paddingHorizontal: 18, alignItems: 'center', justifyContent: 'center' },
  buttonText: { fontSize: 16, fontWeight: '600' },
  field: { gap: 6 },
  label: { fontSize: 13, fontWeight: '600', letterSpacing: 0.4, textTransform: 'uppercase' },
  input: { minHeight: 44, borderWidth: 1, borderRadius: 8, paddingHorizontal: 12, fontSize: 16 },
  notice: { borderLeftWidth: 4, borderRadius: 6, padding: 12 },
});
