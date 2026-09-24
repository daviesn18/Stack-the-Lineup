// The web workbench: the design handoff's sidebar layout (option 1b) for
// laptop browsers. Plain DOM so hover, drag and drop, right-click and the
// keyboard work as on a desktop app. Android will get its own screens.

import { useEffect } from 'react';

import { useTeam } from '@/data/teamStore';

import { HistoryScreen } from './HistoryScreen';
import { LineupScreen } from './LineupScreen';
import { Overlays } from './Overlays';
import { PlayerModal, PlayersScreen } from './PlayersScreen';
import { PositionsScreen } from './PositionsScreen';
import { SettingsModal } from './SettingsModal';
import { FairPlayPanel, Sidebar, TopBar } from './Shell';
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
  const { saveError, dismissSaveError } = useTeam();
  useKeyboard();
  return (
    // Below 1024px wide (not designed yet) the frame keeps its width and the page scrolls sideways.
    <div className="stl" style={{ position: 'fixed', inset: 0, overflow: 'auto', background: C.grouped }}>
      <div style={{ minWidth: 1024, height: '100%', minHeight: 600, display: 'flex', flexDirection: 'column' }}>
        <TopBar demo={demo} />
        {saveError && (
          <div role="alert" style={{ background: 'rgba(255,59,48,0.09)', color: C.red, fontSize: 14, padding: '8px 20px', display: 'flex', gap: 12, borderBottom: C.hair }}>
            <span style={{ flex: 1 }}>{saveError}</span>
            <button className="h-link" onClick={dismissSaveError} style={{ color: C.blue }}>Dismiss</button>
          </div>
        )}
        <div style={{ flex: 1, display: 'flex', minHeight: 0 }}>
          <Sidebar />
          <main style={{ flex: 1, minWidth: 0, display: 'flex', background: C.grouped }}>
            {w.screen === 'positions' && <PositionsScreen />}
            {w.screen === 'players' && <PlayersScreen demo={demo} />}
            {w.screen === 'lineup' && <LineupScreen />}
            {w.screen === 'history' && <HistoryScreen />}
          </main>
          <FairPlayPanel />
        </div>
      </div>
      <Overlays />
      {w.playerModal && <PlayerModal key={w.playerModal.id} />}
      {w.settingsOpen && <SettingsModal onClose={() => w.setSettingsOpen(false)} />}
    </div>
  );
}

/** Esc closes overlays; in By Inning, 1-9 and the arrows switch innings; B benches from the menu. */
function useKeyboard() {
  const w = useWorkbench();
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const tag = (e.target as HTMLElement | null)?.tagName;
      const typing = tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT';
      if (e.key === 'Escape') { w.closeOverlays(); return; }
      if (typing || e.metaKey || e.ctrlKey || e.altKey || w.playerModal || w.settingsOpen) return;
      if (w.menu && e.key.toLowerCase() === 'b') { e.preventDefault(); w.place(w.menu.pid, w.menu.inning, 'Bench'); return; }
      if (w.screen === 'positions' && w.posView === 'inning' && !w.picker && !w.menu) {
        if (/^[1-9]$/.test(e.key) && Number(e.key) <= w.lineup.innings.length) w.setInning(Number(e.key) - 1);
        else if (e.key === 'ArrowRight') { e.preventDefault(); w.setInning(w.inning + 1); }
        else if (e.key === 'ArrowLeft') { e.preventDefault(); w.setInning(w.inning - 1); }
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  });
}
