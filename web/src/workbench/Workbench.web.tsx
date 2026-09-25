// The web app from the game-prep handoff, for laptop browsers: a sidebar,
// Home, a game page prepared in four steps, Roster and Season stats. Plain DOM
// so hover, drag and drop, right-click and the keyboard work as on a desktop
// app. Android will get its own screens.

import { useEffect } from 'react';

import { useTeam } from '@/data/teamStore';

import { GameScreen } from './GameScreen';
import { HistoryScreen } from './HistoryScreen';
import { HomeScreen } from './HomeScreen';
import { Overlays } from './Overlays';
import { PlayerPanel, RosterScreen } from './RosterScreen';
import { LeaveDialog, SettingsScreen } from './SettingsScreen';
import { Sidebar } from './Shell';
import { useWorkbench, WorkbenchProvider } from './state';
import { C, CSS } from './theme';

export function Workbench({ demo }: { demo?: boolean }) {
  return (
    <WorkbenchProvider>
      <style>{CSS}</style>
      <Frame demo={demo} />
    </WorkbenchProvider>
  );
}

function Frame({ demo }: { demo?: boolean }) {
  const w = useWorkbench();
  const { saveError, dismissSaveError, saving } = useTeam();
  useKeyboard();
  return (
    // Below 1024px wide (not designed yet) the frame keeps its width and the page scrolls sideways.
    <div className="stl" style={{ position: 'fixed', inset: 0, overflow: 'auto', background: C.grouped }}>
      <div style={{ minWidth: 1024, height: '100%', minHeight: 600, display: 'flex' }}>
        <Sidebar demo={demo} />
        <main style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column' }}>
          {saveError && (
            <div role="alert" style={{ background: 'rgba(255,59,48,0.09)', color: C.red, fontSize: 14, padding: '8px 20px', display: 'flex', gap: 12, borderBottom: C.hair }}>
              <span style={{ flex: 1 }}>{saveError}</span>
              <button className="h-link" onClick={dismissSaveError} style={{ color: C.blue }}>Dismiss</button>
            </div>
          )}
          <div style={{ flex: 1, display: 'flex', minHeight: 0 }}>
            {w.screen === 'home' && <HomeScreen />}
            {w.screen === 'game' && <GameScreen />}
            {w.screen === 'roster' && <RosterScreen />}
            {w.screen === 'stats' && <HistoryScreen />}
            {w.screen === 'settings' && <SettingsScreen />}
          </div>
        </main>
      </div>
      <Overlays />
      {w.playerModal && <PlayerPanel key={w.playerModal.id} />}
      {w.pendingLeave && <LeaveDialog />}
      {saving && <span aria-live="polite" style={{ position: 'fixed', right: 14, bottom: 10, fontSize: 12, color: C.label3 }}>Saving…</span>}
    </div>
  );
}

/** Esc closes overlays; on the Field view, 1-9 and the arrows switch innings; B benches from the menu. */
function useKeyboard() {
  const w = useWorkbench();
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const tag = (e.target as HTMLElement | null)?.tagName;
      const typing = tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT';
      if (e.key === 'Escape') { w.closeOverlays(); return; }
      if (typing || e.metaKey || e.ctrlKey || e.altKey || w.playerModal || w.pendingLeave) return;
      if (w.menu && e.key.toLowerCase() === 'b') { e.preventDefault(); w.place(w.menu.pid, w.menu.inning, 'Bench'); return; }
      if (w.screen === 'game' && w.step === 3 && w.defView === 'field' && !w.picker && !w.menu) {
        if (/^[1-9]$/.test(e.key) && Number(e.key) <= w.lineup.innings.length) w.setInning(Number(e.key) - 1);
        else if (e.key === 'ArrowRight') { e.preventDefault(); w.setInning(w.inning + 1); }
        else if (e.key === 'ArrowLeft') { e.preventDefault(); w.setInning(w.inning - 1); }
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  });
}
