// "Paste a list" on the Players screen: one player per line.

import type { Player } from '@/core/model';

/** One player per line: "Jake Rivera 4", "4 Jake Rivera" or "Jake Rivera #4". */
export function parseRosterList(text: string): Omit<Player, 'id'>[] {
  return text.split(/\r?\n/).map((line) => line.trim()).filter(Boolean).map((line) => {
    let number = '';
    let rest = line.replace(/#\s*(\d{1,3})\b/, (_, n) => { number = n; return ''; }).trim();
    const lead = rest.match(/^(\d{1,3})[\s.,-]+(.*)$/);
    const trail = rest.match(/^(.*?)[\s,]+(\d{1,3})$/);
    if (!number && lead) { number = lead[1]; rest = lead[2]; } else if (!number && trail) { number = trail[2]; rest = trail[1]; }
    const parts = rest.replace(/,/g, ' ').split(/\s+/).filter(Boolean);
    return { firstName: parts[0] ?? '', lastName: parts.slice(1).join(' '), number, positionPreferences: {} };
  }).filter((p) => p.firstName);
}
