import { createElement } from 'react';
import { StyleSheet, Text, View } from 'react-native';

import { fromYMD, toYMD } from './dateText';
import { usePalette } from './kit';

/** Web: a native date picker. React Native Web renders to the DOM, so a plain <input> works here. */
export function DateField({ label, value, onChange }: { label: string; value: Date; onChange(d: Date): void }) {
  const c = usePalette();
  return (
    <View style={styles.field}>
      <Text style={[styles.label, { color: c.muted }]}>{label}</Text>
      {createElement('input', {
        type: 'date',
        value: toYMD(value),
        'aria-label': label,
        onChange: (e: { target: { value: string } }) => {
          const d = fromYMD(e.target.value, value);
          if (d) onChange(d);
        },
        style: {
          minHeight: 44, borderWidth: 1, borderStyle: 'solid', borderRadius: 8, paddingLeft: 12, paddingRight: 12,
          fontSize: 16, color: c.ink, backgroundColor: c.surface, borderColor: c.line, fontFamily: 'inherit',
          colorScheme: c.ground === '#0F1519' ? 'dark' : 'light', boxSizing: 'border-box',
        },
      })}
    </View>
  );
}

const styles = StyleSheet.create({
  field: { gap: 6 },
  label: { fontSize: 13, fontWeight: '600', letterSpacing: 0.4, textTransform: 'uppercase' },
});
