// Game date input. Native (Android, later): a plain YYYY-MM-DD field.
// Web uses DateField.web.tsx, a real <input type="date">.

import { fromYMD, toYMD } from './dateText';
import { Field } from './kit';

export function DateField({ label, value, onChange }: { label: string; value: Date; onChange(d: Date): void }) {
  const text = toYMD(value);
  return (
    <Field label={label} defaultValue={text} placeholder="YYYY-MM-DD" onEndEditing={(e) => {
      const d = fromYMD(e.nativeEvent.text, value);
      if (d) onChange(d);
    }} />
  );
}
