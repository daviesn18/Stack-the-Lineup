// Small shared UI kit for the web pilot: colors, a centered page, text, buttons,
// fields and notices. Plain React Native components so the same code runs on
// Android later.

import type { ReactNode } from 'react';
import {
  ActivityIndicator, Pressable, ScrollView, StyleSheet, Text, TextInput, View, useColorScheme,
  type TextInputProps,
} from 'react-native';

const light = {
  ground: '#F4F6F5', surface: '#FFFFFF', ink: '#14202B', muted: '#5A6672', line: '#DCE2DF',
  accent: '#1D6B47', accentInk: '#FFFFFF', accentSoft: '#E2EFE8',
  warn: '#8A5A0F', warnSoft: '#FBF0DC', danger: '#A3322A', dangerSoft: '#FBE7E5',
};
const dark: typeof light = {
  ground: '#0F1519', surface: '#172027', ink: '#E5ECE9', muted: '#9AA7A1', line: '#28343B',
  accent: '#5CC08F', accentInk: '#0B1A12', accentSoft: '#173024',
  warn: '#E4AE55', warnSoft: '#2F2513', danger: '#EF8A80', dangerSoft: '#3A1D1A',
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
