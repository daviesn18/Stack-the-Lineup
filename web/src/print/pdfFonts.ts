// The printouts' typefaces: Barlow and Barlow Condensed (SIL OFL, files and
// licenses in public/fonts). iOS bundles the same files (Lineup Builder/Fonts)
// so both platforms print the same glyphs.

export const FACES = {
  regular: 'Barlow-Regular',
  medium: 'Barlow-Medium',
  semibold: 'Barlow-SemiBold',
  bold: 'Barlow-Bold',
  condensed: 'BarlowCondensed-Bold',
} as const;

export type Face = keyof typeof FACES;
export type FontFiles = Record<Face, ArrayBuffer>;

let pending: Promise<FontFiles | null> | null = null;

/**
 * The font files, fetched once and kept. Null when they can't be fetched:
 * the printout then falls back to Helvetica rather than failing, and the
 * next printout tries again.
 */
export function loadFontFiles(): Promise<FontFiles | null> {
  pending ??= Promise.all(
    (Object.keys(FACES) as Face[]).map(async (face) => {
      const res = await fetch(`/fonts/${FACES[face]}.ttf`);
      if (!res.ok) throw new Error(`${FACES[face]}.ttf: HTTP ${res.status}`);
      return [face, await res.arrayBuffer()] as const;
    }),
  ).then(
    (entries) => Object.fromEntries(entries) as FontFiles,
    (error) => {
      console.warn('Printout fonts unavailable; using Helvetica.', error);
      pending = null;
      return null;
    },
  );
  return pending;
}
