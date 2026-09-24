// Date <-> YYYY-MM-DD text for the game-date field. Shared by DateField.tsx and
// DateField.web.tsx (kept separate: on web, './DateField' resolves to the .web file).

/** Local calendar date as YYYY-MM-DD. */
export const toYMD = (d: Date) =>
  `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;

/** Keeps the time of day from `keepTimeOf` (game time) and changes only the date. */
export function fromYMD(s: string, keepTimeOf: Date): Date | null {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(s.trim());
  if (!m) return null;
  const d = new Date(keepTimeOf);
  d.setFullYear(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
  return Number.isNaN(d.getTime()) ? null : d;
}
