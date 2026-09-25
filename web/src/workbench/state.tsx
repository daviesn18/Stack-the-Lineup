// Screen state for the web workbench (the design handoff's sidebar layout):
// which screen and view is showing, the open overlay (picker or right-click
// menu), drag and drop, the undo toast, and the lineup edits every screen
// shares. Team data and saving stay in teamStore; this only adds the UI layer.

import {
  createContext, useCallback, useContext, useMemo, useRef, useState, type DragEvent, type ReactNode,
} from 'react';

import { runAutoFill, type AutoFillOutcome } from '@/core/autofillCoordinator';
import { activeFieldPositions, activePlayers, openPositions } from '@/core/fairPlay';
import { displayPlayers, gridNames, moveBatter, place, unbench } from '@/core/lineupOps';
import type { FieldPosition, Lineup, Player } from '@/core/model';
import { useTeam, type TeamData } from '@/data/teamStore';

import { fairPlayIssues, type FairPlayIssue } from './fairPlayIssues';

export type Screen = 'home' | 'game' | 'roster' | 'stats' | 'settings';
/** Game prep: 1 Attendance, 2 Batting order, 3 Defense, 4 Review. */
export type Step = 1 | 2 | 3 | 4;
export type DefView = 'field' | 'grid' | 'pitching';
export type HistView = 'players' | 'games' | 'team';

export interface PickerState { inning: number; pos: FieldPosition; x: number; y: number }
export interface MenuState { pid: string; inning: number; x: number; y: number }
export interface ToastState { id: number; text: string; before: Lineup | null }
type DragSource = { pid: string; from: 'cell' | 'order' };
/** Player editor: an existing player's id, or 'new'. */
export type PlayerModal = { id: string } | { id: 'new' } | null;

export interface Workbench extends TeamData {
  /** Active players in batting order. */
  active: Player[];
  byId: Map<string, Player>;
  /** The name the grid shows: first name, disambiguated when two players share it. */
  nameOf(p: Player): string;
  positions: FieldPosition[];
  issues: FairPlayIssue[];
  /** Who holds a field spot in an inning. */
  holder(inning: number, pos: FieldPosition): Player | undefined;
  posOf(pid: string, inning: number): FieldPosition | undefined;

  screen: Screen; go(screen: Screen): void;
  step: Step; goStep(step: Step): void;
  defView: DefView; setDefView(v: DefView): void;
  histView: HistView; setHistView(v: HistView): void;
  inning: number; setInning(i: number): void;
  /** Game › Defense › Field at `inning`. */
  showInning(inning: number): void;

  /** Optional Auto-Fill instructions (one per line). */
  prompt: string; setPrompt(p: string): void;
  /** Fills every open spot in every inning; toasts with Undo. */
  autoFill(): void;
  /** The last Auto-Fill's notes (couldn't fill, or instructions it skipped). */
  fillNotes: AutoFillOutcome | null; clearFillNotes(): void;

  picker: PickerState | null;
  openPicker(anchor: Element, inning: number, pos: FieldPosition): void;
  menu: MenuState | null;
  openMenu(e: { clientX: number; clientY: number; preventDefault(): void }, pid: string | undefined, inning: number): void;
  closeOverlays(): void;

  playerModal: PlayerModal;
  setPlayerModal(m: PlayerModal): void;
  /** The New game dialog (archive this game, set up the next). */
  newGameOpen: boolean;
  setNewGameOpen(open: boolean): void;
  /** Team settings reports unsaved changes here, so leaving the page can ask first. */
  setSettingsDirty(dirty: boolean): void;
  /** Runs `fn` now, or after the coach agrees to drop unsaved team settings. */
  leave(fn: () => void): void;
  /** A leave waiting on "Discard unsaved changes?". */
  pendingLeave: (() => void) | null;
  resolveLeave(discard: boolean): void;

  /** Assign with swap (see lineupOps.place); closes overlays. */
  place(pid: string, inning: number, pos: FieldPosition | null): void;
  /** Any lineup edit; with `toast`, shows it with Undo. */
  edit(fn: (l: Lineup) => Lineup, toast?: string): void;
  toast: ToastState | null;
  showToast(text: string, before?: Lineup | null): void;
  undo(): void;

  // Drag and drop (HTML5).
  dropKey: string | null;
  dragging: DragSource | null;
  dragProps(pid: string | undefined, from: 'cell' | 'order'): Record<string, unknown>;
  dropProps(key: string, onDrop: (src: DragSource) => void, accept?: (src: DragSource) => boolean): Record<string, unknown>;
}

const Ctx = createContext<Workbench | null>(null);

export function WorkbenchProvider({ children }: { children: ReactNode }) {
  const { data, editLineup } = useTeam();
  const { team, players, lineup, gameLogs } = data!;

  const [screen, setScreen] = useState<Screen>('home');
  const [step, setStep] = useState<Step>(1);
  const [defView, setDefView] = useState<DefView>('field');
  const [histView, setHistView] = useState<HistView>('team');
  const [prompt, setPrompt] = useState('');
  const [fillNotes, setFillNotes] = useState<AutoFillOutcome | null>(null);
  const [inning, setInningRaw] = useState(0);
  const [picker, setPicker] = useState<PickerState | null>(null);
  const [menu, setMenu] = useState<MenuState | null>(null);
  const [playerModal, setPlayerModal] = useState<PlayerModal>(null);
  const [newGameOpen, setNewGameOpen] = useState(false);
  const [pendingLeave, setPendingLeave] = useState<(() => void) | null>(null);
  const settingsDirty = useRef(false);
  const [toast, setToast] = useState<ToastState | null>(null);
  const [dropKey, setDropKey] = useState<string | null>(null);
  const [dragging, setDragging] = useState<DragSource | null>(null);
  const drag = useRef<DragSource | null>(null);
  const toastTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const inningCount = lineup.innings.length;
  const setInning = useCallback((i: number) => setInningRaw(Math.max(0, Math.min(inningCount - 1, i))), [inningCount]);

  const derived = useMemo(() => {
    const byId = new Map(players.map((p) => [p.id, p]));
    const active = displayPlayers(lineup, players);
    const positions = activeFieldPositions(team.fairPlayConfig);
    const issues = fairPlayIssues({ lineup, players, config: team.fairPlayConfig, pitchingConfig: team.pitchingConfig, gameLogs });
    const holders = lineup.innings.map((inn) => {
      const m = new Map<FieldPosition, Player>();
      for (const [pid, pos] of Object.entries(inn.assignments)) {
        const p = byId.get(pid);
        if (p && !lineup.absentPlayerIDs.includes(pid)) m.set(pos, p);
      }
      return m;
    });
    return { byId, active, positions, issues, holders, names: gridNames(players) };
  }, [lineup, players, team, gameLogs]);

  const closeOverlays = useCallback(() => { setPicker(null); setMenu(null); }, []);

  const showToast = useCallback((text: string, before: Lineup | null = null) => {
    if (toastTimer.current) clearTimeout(toastTimer.current);
    setToast({ id: Date.now(), text, before });
    toastTimer.current = setTimeout(() => setToast(null), 5000);
  }, []);

  const edit = useCallback((fn: (l: Lineup) => Lineup, toastText?: string) => {
    const before = lineup;
    editLineup(fn);
    if (toastText) showToast(toastText, before);
  }, [editLineup, lineup, showToast]);

  const leave = (fn: () => void) => {
    if (screen === 'settings' && settingsDirty.current) setPendingLeave(() => fn);
    else fn();
  };

  const wb: Workbench = {
    ...data!,
    ...derived,
    nameOf: (p) => derived.names.get(p.id) ?? p.firstName,
    holder: (i, pos) => derived.holders[i]?.get(pos),
    posOf: (pid, i) => lineup.innings[i]?.assignments[pid],

    screen, go: (s) => leave(() => { closeOverlays(); setScreen(s); }),
    step, goStep: (n) => leave(() => { closeOverlays(); setScreen('game'); setStep(n); }),
    defView, setDefView: (v) => { closeOverlays(); setDefView(v); },
    histView, setHistView, inning, setInning,
    showInning: (i) => leave(() => { closeOverlays(); setScreen('game'); setStep(3); setDefView('field'); setInning(i); }),

    prompt, setPrompt,
    autoFill: () => {
      closeOverlays();
      // Innings with open spots put their bench back in play, so Auto-Fill can rebalance around an absence.
      const short = lineup.innings.map((_, i) => i).filter((i) => openPositions(lineup, i, players, team.fairPlayConfig).length > 0);
      const outcome = runAutoFill({
        scope: { kind: 'through', inning: lineup.innings.length - 1 }, prompt,
        lineup: unbench(lineup, short), players, config: team.fairPlayConfig, pitchingConfig: team.pitchingConfig, gameLogs,
      });
      setFillNotes(outcome.incompleteMessage || outcome.noticeMessage ? outcome : null);
      if (outcome.filledCount === 0) { showToast('Nothing to fill: every position is covered'); return; }
      const n = activePlayers(lineup, players).length;
      edit(() => outcome.lineup, `Filled ${lineup.innings.length} innings for ${n} players`);
    },
    fillNotes, clearFillNotes: () => setFillNotes(null),

    picker,
    openPicker: (anchor, i, pos) => {
      const r = anchor.getBoundingClientRect();
      const W = window.innerWidth;
      const H = window.innerHeight;
      let x = r.left + r.width / 2 - 160;
      let y = r.bottom + 6;
      if (y + 470 > H) y = Math.max(8, r.top - 476);
      x = Math.max(8, Math.min(x, W - 328));
      setMenu(null);
      setPicker({ inning: i, pos, x, y });
    },
    menu,
    openMenu: (e, pid, i) => {
      e.preventDefault();
      if (!pid) return;
      setPicker(null);
      setMenu({ pid, inning: i, x: Math.max(8, Math.min(e.clientX, window.innerWidth - 246)), y: Math.max(8, Math.min(e.clientY, window.innerHeight - 300)) });
    },
    closeOverlays,

    playerModal, setPlayerModal,
    newGameOpen, setNewGameOpen: (open) => { closeOverlays(); setNewGameOpen(open); },
    setSettingsDirty: (d) => { settingsDirty.current = d; },
    leave, pendingLeave,
    resolveLeave: (discard) => {
      const fn = pendingLeave;
      setPendingLeave(null);
      if (discard && fn) { settingsDirty.current = false; fn(); }
    },

    place: (pid, i, pos) => { closeOverlays(); setDropKey(null); editLineup((l) => place(l, pid, i, pos)); },
    edit,
    toast, showToast,
    undo: () => {
      if (toast?.before) { const b = toast.before; editLineup(() => b); }
      setToast(null);
    },

    dropKey,
    dragging,
    dragProps: (pid, from) => (pid ? {
      draggable: true,
      onDragStart: (e: DragEvent) => {
        drag.current = { pid, from };
        setDragging(drag.current);
        closeOverlays();
        try { e.dataTransfer.effectAllowed = 'move'; e.dataTransfer.setData('text/plain', pid); } catch { /* old browsers */ }
      },
      onDragEnd: () => { drag.current = null; setDragging(null); setDropKey(null); },
    } : { draggable: false }),
    dropProps: (key, onDrop, accept = () => true) => ({
      onDragOver: (e: DragEvent) => {
        if (!drag.current || !accept(drag.current)) return;
        e.preventDefault();
        if (dropKey !== key) setDropKey(key);
      },
      onDragLeave: () => { if (dropKey === key) setDropKey(null); },
      onDrop: (e: DragEvent) => {
        e.preventDefault();
        const src = drag.current;
        drag.current = null;
        setDragging(null);
        setDropKey(null);
        if (src && accept(src)) onDrop(src);
      },
    }),
  };
  return <Ctx.Provider value={wb}>{children}</Ctx.Provider>;
}

export function useWorkbench(): Workbench {
  const w = useContext(Ctx);
  if (!w) throw new Error('useWorkbench outside WorkbenchProvider');
  return w;
}

/** Drop a batting-order row onto another: move it to that row's slot. */
export const reorderTo = (lineup: Lineup, active: Player[], pid: string, targetId: string): Lineup => {
  if (pid === targetId) return lineup;
  const to = active.findIndex((p) => p.id === targetId);
  // Until a batting order is saved, the roster order stands in for it.
  return to < 0 ? lineup : moveBatter({ ...lineup, battingOrder: active.map((p) => p.id) }, pid, to);
};
