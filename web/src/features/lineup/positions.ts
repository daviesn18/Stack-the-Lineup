// Position colors and keyboard codes for the grid.

import { isInfield, type FieldPosition } from '@/core/model';
import type { Palette } from '@/ui/kit';

/** iOS badgeColor: infield blue, outfield green, bench gray, absent light gray. */
export function positionColors(pos: FieldPosition | undefined, c: Palette, dark: boolean) {
  if (!pos) return { bg: 'transparent', fg: c.muted };
  if (pos === 'ABS') return { bg: dark ? '#2A3036' : '#ECEEEF', fg: c.muted };
  if (pos === 'Bench') return { bg: dark ? '#2B3238' : '#E3E6E8', fg: dark ? '#C3CAD0' : '#4B555E' };
  if (isInfield(pos)) return { bg: dark ? '#1C3350' : '#DCE8F7', fg: dark ? '#9CC3F2' : '#1D4E89' };
  return { bg: dark ? '#173424' : '#DDF1E4', fg: dark ? '#8BD6A8' : '#1D6B47' };
}

/** What the coach types in a selected cell. Exact codes apply at once; short ones after a pause. */
export const TYPED_CODES: Record<string, FieldPosition> = {
  p: 'P', c: 'C', '1b': '1B', '2b': '2B', '3b': '3B', ss: 'SS', lf: 'LF', cf: 'CF', rf: 'RF',
  lcf: 'LCF', rcf: 'RCF', b: 'Bench', bench: 'Bench',
};
export const SHORT_CODES: Record<string, FieldPosition> = { '1': '1B', '2': '2B', '3': '3B', s: 'SS', l: 'LF', r: 'RF' };
