// The pitch count list shared by New game (archiving today's game) and
// History (adding or fixing counts on an archived game): one row per pitcher
// with a count, a remove button, and an Add pitcher menu.

import { HAIR, NumInput } from './controls';
import { Icon } from './Icon';
import { SUB } from './Shell';
import { C } from './theme';

/** The schema's limit (pitch_counts.pitches). */
export const MAX_PITCHES = 200;

export type Counts = Record<string, number | ''>;

export interface Pitcher {
  id: string;
  name: string;
  /** Shown under the name in orange (e.g. no league age, so rest can't be tracked). */
  warning?: string;
}

/** Pitchers whose count is over the limit. */
export const overLimit = (ids: string[], counts: Counts) => ids.filter((id) => Number(counts[id] || 0) > MAX_PITCHES);

/** The counts to save: every listed pitcher, blank as 0. */
export const countsToSave = (ids: string[], counts: Counts) => Object.fromEntries(ids.map((id) => [id, Number(counts[id] || 0)]));

export function PitchCountList({ pitchers, addable, counts, onCounts, onRemove, onAdd, empty }: {
  pitchers: Pitcher[];
  addable: Pitcher[];
  counts: Counts;
  onCounts(c: Counts): void;
  onRemove(id: string): void;
  onAdd(id: string): void;
  empty: string;
}) {
  const over = overLimit(pitchers.map((p) => p.id), counts);
  return (
    <div style={{ marginTop: 10, display: 'flex', flexDirection: 'column' }}>
      {pitchers.length === 0 && <div style={{ fontSize: 13, color: SUB, padding: '6px 0' }}>{empty}</div>}
      {pitchers.map((p) => (
        <div key={p.id} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '8px 0', borderTop: HAIR }}>
          <span style={{ flex: 1, minWidth: 0 }}>
            <span className="ellipsis" style={{ display: 'block', fontSize: 14 }}>{p.name}</span>
            {over.includes(p.id) ? <span style={{ display: 'block', fontSize: 12, color: C.red }}>Up to {MAX_PITCHES} pitches</span>
              : p.warning && <span style={{ display: 'block', fontSize: 12, color: C.orange }}>{p.warning}</span>}
          </span>
          <NumInput value={counts[p.id] ?? ''} onChange={(v) => onCounts({ ...counts, [p.id]: v })} label={`${p.name} pitches`} placeholder="0" width={72} />
          <button type="button" className="h-remove" title="Remove pitcher" aria-label={`Remove ${p.name}`}
            onClick={() => onRemove(p.id)} style={{ display: 'grid', placeItems: 'center' }}>
            <Icon name="minus.circle.fill" size={18} color={C.red} />
          </button>
        </div>
      ))}
      {addable.length > 0 && (
        <label className="h-link" style={{ position: 'relative', display: 'flex', alignItems: 'center', gap: 8, paddingTop: 8, borderTop: HAIR, fontSize: 14, fontWeight: 500, color: C.blue, cursor: 'pointer' }}>
          <Icon name="plus.circle.fill" size={18} color={C.blue} />Add pitcher
          <select aria-label="Add pitcher" value="" onChange={(e) => e.target.value && onAdd(e.target.value)}
            style={{ position: 'absolute', inset: 0, opacity: 0, cursor: 'pointer' }}>
            <option value="">Add pitcher</option>
            {addable.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
          </select>
        </label>
      )}
    </div>
  );
}
