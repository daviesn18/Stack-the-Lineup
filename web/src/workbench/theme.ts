// Design tokens from the web handoff (iOS system colors), and the one global
// stylesheet the web workbench uses for things inline styles can't do: hover
// states (mouse only), focus rings and the toast animation.

import { isInfield, isOutfield, type FieldPosition, type PositionPreferenceTier } from '@/core/model';

export const C = {
  blue: '#007AFF', green: '#34C759', orange: '#FF9500', red: '#FF3B30', yellow: '#FFCC00', teal: '#30B0C7',
  label: '#000', label2: 'rgba(60,60,67,0.6)', label3: 'rgba(60,60,67,0.3)',
  grouped: '#F2F2F7', cell: '#FFFFFF',
  gray1: '#8E8E93', gray2: '#AEAEB2', gray3: '#C7C7CC', gray4: '#D1D1D6', gray5: '#E5E5EA', gray6: '#F2F2F7',
  sep: 'rgba(60,60,67,0.36)',
  hair: '0.5px solid rgba(60,60,67,0.36)',
  infieldTint: 'rgba(0,122,255,0.12)', outfieldTint: 'rgba(52,199,89,0.15)',
  destructiveBg: 'rgb(252,235,235)', destructiveFg: 'rgb(227,74,74)', destructiveBorder: 'rgb(240,148,148)',
};

export const FONT = '-apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", system-ui, sans-serif';

export const TIER_STYLE: Record<PositionPreferenceTier, { bg: string; fg: string; letter: string }> = {
  Strength: { bg: 'rgb(235,242,222)', fg: 'rgb(59,110,18)', letter: 'S' },
  Capable: { bg: 'rgb(230,242,250)', fg: 'rgb(23,94,166)', letter: 'C' },
  Emergency: { bg: 'rgb(250,237,217)', fg: 'rgb(133,79,10)', letter: 'E' },
  Never: { bg: 'rgb(253,235,235)', fg: 'rgb(163,46,46)', letter: 'N' },
};
export const TIER_RANK: Record<PositionPreferenceTier | 'none', number> = { Strength: 0, Capable: 1, none: 2, Emergency: 3, Never: 4 };

/** Solid badge color: infield blue, outfield green, bench gray. */
export const badgeColor = (p: FieldPosition | undefined | null) =>
  !p ? C.gray3 : isInfield(p) ? C.blue : isOutfield(p) ? C.green : C.gray1;
/** Soft cell tint for a position. */
export const tint = (p: FieldPosition | undefined | null) =>
  !p ? C.gray5 : isInfield(p) ? C.infieldTint : isOutfield(p) ? C.outfieldTint : C.gray5;

const TIERS_BY_RANK: PositionPreferenceTier[] = ['Strength', 'Capable', 'Emergency', 'Never'];

/** Initials avatar tinted by the player's average preference tier (Capable when none are set). */
export function playerAvatar(p: { positionPreferences: Partial<Record<FieldPosition, PositionPreferenceTier>> }) {
  const ranks = Object.values(p.positionPreferences).filter(Boolean).map((t) => TIERS_BY_RANK.indexOf(t!));
  const avg = ranks.length ? Math.round(ranks.reduce((a, b) => a + b, 0) / ranks.length) : 1;
  return TIER_STYLE[TIERS_BY_RANK[avg]];
}

/** A stable pastel for a player's initials avatar. */
export function avatarStyle(id: string) {
  const tiers: PositionPreferenceTier[] = ['Strength', 'Capable', 'Emergency', 'Never'];
  let h = 0;
  for (const ch of id) h = (h * 31 + ch.charCodeAt(0)) >>> 0;
  return TIER_STYLE[tiers[h % tiers.length]];
}

export const CSS = `
.stl { font-family: ${FONT}; color: #000; -webkit-font-smoothing: antialiased; font-size: 15px; line-height: 1.3; }
.stl *, .stl *::before, .stl *::after { box-sizing: border-box; }
.stl button { font: inherit; color: inherit; border: none; background: none; padding: 0; margin: 0; cursor: pointer; text-align: inherit; }
.stl button:disabled { cursor: default; }
.stl input, .stl textarea, .stl select { font: inherit; color: inherit; }
.stl :focus-visible { outline: 2px solid ${C.blue}; outline-offset: 2px; }
.stl .num { font-variant-numeric: tabular-nums; }
.stl .field:focus { border-color: ${C.blue} !important; box-shadow: 0 0 0 3px rgba(0,122,255,0.15); }
.stl .num-field:focus { box-shadow: 0 0 0 2px ${C.blue}; }
.stl .num-field::placeholder { color: rgba(60,60,67,0.3); font-weight: 500; }
.stl .h-remove { opacity: 0.35; transition: opacity .15s; }
/* Hairlines between the rows of a card (not above the first). */
.stl .sep-rows > * + * { box-shadow: inset 0 0.5px 0 ${C.sep}; }
.stl .settings-group > * + * { box-shadow: inset 0 0.5px 0 rgba(60,60,67,0.29); }
.stl .ellipsis { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.stl [draggable="true"] { cursor: grab; }
.stl .field-cell, .stl .field-chip, .stl .h-card, .stl .h-ring, .stl .issue, .stl .inn-status { transition: box-shadow .12s, background-color .2s, color .2s; }
.stl .strip { transition: background-color .2s ease-in-out, color .2s ease-in-out; }
.stl .pt-bar { transition: width .2s; }
.stl .switch-knob { transition: transform .2s; }
.stl .switch { transition: background-color .2s; }
@media (hover: hover) {
  .stl .h-gray:hover:not(:disabled) { background: ${C.gray6}; }
  .stl .h-row:hover { background: rgba(0,0,0,0.035); }
  .stl .h-row2:hover { background: rgba(0,0,0,0.025); }
  .stl .h-nav:hover { background: rgba(0,0,0,0.04); }
  .stl .h-bright:hover:not(:disabled) { filter: brightness(0.93); }
  .stl .h-dim:hover { filter: brightness(0.97); }
  .stl .h-link:hover:not(:disabled) { opacity: 0.7; }
  .stl .h-tint:hover { background: rgba(0,122,255,0.05); }
  .stl .h-side:hover { background: rgba(60,60,67,0.08); }
  .stl .h-row3:hover { background: #F7F7FA; }
  .stl .h-bluetext:hover { color: ${C.blue}; }
  .stl .menu-row:hover { background: rgba(0,122,255,0.08); }
  .stl .h-sec:hover:not(:disabled) { background: #F7F7FA !important; }
  .stl .h-step:hover { background: rgba(60,60,67,0.05); }
  .stl .h-card:hover { box-shadow: inset 0 0 0 1.5px rgba(0,122,255,0.55) !important; }
  .stl .h-ring:hover { box-shadow: 0 0 0 2px ${C.blue}; }
  .stl .field-cell:hover { box-shadow: inset 0 0 0 1.5px rgba(0,122,255,0.55); }
  .stl .field-chip:hover { background: rgba(0,122,255,0.07); }
  .stl .inn-head:hover { color: ${C.blue}; background: rgba(0,0,0,0.04); }
  .stl .pick-row:hover { background: rgba(0,122,255,0.08) !important; }
  .stl .menu-item:hover { background: ${C.blue}; color: #fff; }
  .stl .menu-item.danger:hover { background: ${C.red}; color: #fff; }
  .stl .menu-tile:hover { filter: brightness(0.95); }
  .stl .h-cov:hover { background: ${C.gray6}; }
  .stl .h-rail:hover { background: rgba(60,60,67,0.06); }
  .stl .h-reset:hover { background: rgba(255,59,48,0.05) !important; }
  .stl .h-save:hover:not(:disabled) { background: #0066d6 !important; }
  .stl .h-remove:hover { opacity: 1; }
}
@keyframes stl-toast-in { from { transform: translate(-50%, 24px); opacity: 0; } to { transform: translate(-50%, 0); opacity: 1; } }
@keyframes stl-pop-in { from { transform: scale(0.97); opacity: 0; } to { transform: scale(1); opacity: 1; } }
.stl .toast { animation: stl-toast-in .35s cubic-bezier(.2,.9,.3,1.15); }
.stl .pop { animation: stl-pop-in .12s ease-out; }
@keyframes stl-slide-in { from { transform: translateX(24px); opacity: 0; } to { transform: none; opacity: 1; } }
.stl .slide-in { animation: stl-slide-in .18s ease-out; }
`;
