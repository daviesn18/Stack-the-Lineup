// Roster CSV import: port of the CSV path in RosterImporter.swift (GameChanger
// Stats exports and any roster CSV with first/last or name columns, plus an
// optional jersey column). Pure: text in, players or an error out.
//
// Handles RFC 4180 quoting, a group row above the real headers (GameChanger
// puts "Batting/Pitching/Fielding" there), mixed line endings and a trailing
// "Totals" row. The .stlroster JSON path isn't ported.

export interface ImportedPlayer {
  firstName: string;
  lastName: string;
  number: string;
}

export type RosterCsvError = 'emptyFile' | 'malformedHeader' | 'noValidPlayersFound';

export const ROSTER_CSV_ERRORS: Record<RosterCsvError, string> = {
  emptyFile: 'The file is empty.',
  malformedHeader: "Couldn't find a column for player names. The file may be in an unexpected format.",
  noValidPlayersFound: 'No players were found in this file. Check that it has player names.',
};

export type RosterCsvResult = { ok: true; players: ImportedPlayer[] } | { ok: false; error: RosterCsvError };

export function splitCSV(text: string): string[][] {
  const rows: string[][] = [];
  let row: string[] = [];
  let cell = '';
  let quoted = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (quoted) {
      if (c === '"') {
        if (text[i + 1] === '"') { cell += '"'; i++; } else quoted = false;
      } else cell += c;
      continue;
    }
    if (c === '"') quoted = true;
    else if (c === ',') { row.push(cell); cell = ''; }
    else if (c === '\n' || c === '\r') {
      row.push(cell); cell = '';
      rows.push(row); row = [];
      if (c === '\r' && text[i + 1] === '\n') i++;
    } else cell += c;
  }
  if (cell || row.length) { row.push(cell); rows.push(row); }
  return rows;
}

const normalize = (s: string) => s.trim().toLowerCase().split(/\s+/).filter(Boolean).join(' ');

const FIRST = new Set(['first', 'firstname', 'first name']);
const LAST = new Set(['last', 'lastname', 'last name', 'surname']);
const NAME = new Set(['name', 'player', 'player name', 'full name']);
const JERSEY = new Set(['number', '#', 'jersey', 'jersey number', 'jersey#']);
const HEADER_WORDS = new Set([...FIRST, ...LAST, ...NAME, ...JERSEY]);

/** "Mary Ann Smith" → first "Mary Ann", last "Smith". */
export function splitFullName(full: string): { first: string; last: string } {
  const parts = full.trim().split(/\s+/).filter(Boolean);
  if (parts.length <= 1) return { first: full.trim(), last: '' };
  return { first: parts.slice(0, -1).join(' '), last: parts[parts.length - 1] };
}

export function parseRosterCsv(text: string): RosterCsvResult {
  if (!text.trim()) return { ok: false, error: 'emptyFile' };
  const rows = splitCSV(text);
  const headerAt = rows.findIndex((r) => r.slice(0, 5).some((c) => HEADER_WORDS.has(normalize(c))));
  if (headerAt < 0) return { ok: false, error: 'malformedHeader' };

  const header = rows[headerAt].map(normalize);
  const find = (set: Set<string>) => { const i = header.findIndex((c) => set.has(c)); return i < 0 ? undefined : i; };
  const first = find(FIRST);
  const last = find(LAST);
  const name = find(NAME);
  const jersey = find(JERSEY);
  const split = first !== undefined && last !== undefined;
  if (!split && name === undefined) return { ok: false, error: 'malformedHeader' };

  const at = (r: string[], i: number | undefined) => (i === undefined ? '' : (r[i] ?? '').trim());
  const players: ImportedPlayer[] = [];
  for (const r of rows.slice(headerAt + 1)) {
    if (r.every((c) => !c.trim())) continue;
    const lead = (r[0] ?? '').trim().toLowerCase();
    if (lead === 'totals' || lead === 'total') continue;
    const n = split ? { first: at(r, first), last: at(r, last) } : splitFullName(at(r, name));
    if (!n.first && !n.last) continue;
    players.push({ firstName: n.first, lastName: n.last, number: at(r, jersey) });
  }
  return players.length ? { ok: true, players } : { ok: false, error: 'noValidPlayersFound' };
}

/** Lowercased full name, for spotting players already on the roster. */
export const matchKey = (p: { firstName: string; lastName: string }) => `${p.firstName} ${p.lastName}`.trim().toLowerCase();
