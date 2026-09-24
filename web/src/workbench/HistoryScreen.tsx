// History: season stats from archived games only (Team coverage and bench
// innings, the games list, per-player totals).

import { useMemo } from 'react';

import { shortName } from '@/core/lineupOps';
import { isInfield, isOutfield, type FieldPosition, type GameLog, type Player } from '@/core/model';

import { Icon } from './Icon';
import { useWorkbench } from './state';
import { C, TIER_STYLE } from './theme';
import { card, Segmented, Title } from './ui';

/** The innings actually played in an archived game. */
const playedInnings = (g: GameLog) => g.innings.slice(0, g.inningsPlayed || g.innings.length);

export function seasonTotals(players: Player[], logs: GameLog[]) {
  const out = new Map<string, { infield: number; outfield: number; bench: number; played: Set<FieldPosition> }>();
  for (const p of players) out.set(p.id, { infield: 0, outfield: 0, bench: 0, played: new Set() });
  for (const g of logs) {
    for (const inn of playedInnings(g)) {
      for (const [pid, pos] of Object.entries(inn.assignments)) {
        const t = out.get(pid);
        if (!t) continue;
        if (isInfield(pos)) t.infield++;
        else if (isOutfield(pos)) t.outfield++;
        else if (pos === 'Bench') t.bench++;
        t.played.add(pos);
      }
    }
  }
  return out;
}

export function HistoryScreen() {
  const w = useWorkbench();
  const totals = useMemo(() => seasonTotals(w.players, w.gameLogs), [w.players, w.gameLogs]);
  const empty = w.gameLogs.length === 0;
  return (
    <div style={{ flex: 1, overflowY: 'auto' }}>
      <div style={{ maxWidth: 900, margin: '0 auto', padding: '22px 28px 36px' }}>
        <Title>History</Title>
        <Segmented value={w.histView} onChange={w.setHistView} options={[['players', 'Players'], ['games', 'Games'], ['team', 'Team']]} />
        {empty ? (
          <div style={{ ...card, marginTop: 20, padding: '18px 16px', fontSize: 15, color: C.label2, lineHeight: '21px' }}>
            No archived games yet. After a game, archive it and season stats start adding up here.
          </div>
        ) : (
          <div style={{ marginTop: 20 }}>
            {w.histView === 'team' && <TeamView totals={totals} />}
            {w.histView === 'games' && <GamesView />}
            {w.histView === 'players' && <PlayersView totals={totals} />}
          </div>
        )}
      </div>
    </div>
  );
}

type Totals = ReturnType<typeof seasonTotals>;

function Heading({ children }: { children: string }) {
  return <div style={{ fontSize: 20, fontWeight: 600, color: C.label2, margin: '4px 4px 10px' }}>{children}</div>;
}

function TeamView({ totals }: { totals: Totals }) {
  const w = useWorkbench();
  const bench = w.players.map((p) => ({ p, n: totals.get(p.id)!.bench })).sort((a, b) => b.n - a.n);
  const max = Math.max(1, ...bench.map((b) => b.n));
  const cols = `110px repeat(${w.positions.length}, 1fr)`;
  return (
    <>
      <Heading>Position coverage</Heading>
      <div style={{ ...card, padding: '14px 16px' }}>
        <div style={{ display: 'flex', gap: 18, fontSize: 13, color: C.label2, marginBottom: 12 }}>
          <Dot kind="played">Played</Dot><Dot kind="yet">Yet to play</Dot><Dot kind="na">N/A (Never)</Dot>
        </div>
        <div style={{ display: 'grid', gridTemplateColumns: cols, fontSize: 13, color: C.label2, height: 24, alignItems: 'center' }}>
          <span />{w.positions.map((pos) => <span key={pos} style={{ textAlign: 'center' }}>{pos}</span>)}
        </div>
        {w.players.map((p) => (
          <div key={p.id} className="h-cov" style={{ display: 'grid', gridTemplateColumns: cols, height: 30, alignItems: 'center', borderRadius: 6 }}>
            <span className="ellipsis" style={{ fontSize: 14, color: C.label2, paddingLeft: 4 }}>{shortName(p)}</span>
            {w.positions.map((pos) => {
              const kind = p.positionPreferences[pos] === 'Never' ? 'na' : totals.get(p.id)!.played.has(pos) ? 'played' : 'yet';
              return <span key={pos} style={{ display: 'grid', placeItems: 'center' }} title={`${p.firstName} at ${pos}: ${kind === 'na' ? 'N/A' : kind === 'played' ? 'played' : 'yet to play'}`}><Dot kind={kind} /></span>;
            })}
          </div>
        ))}
      </div>

      <div style={{ marginTop: 26 }}><Heading>Bench innings this season</Heading></div>
      <div style={{ ...card, padding: '4px 16px' }}>
        {bench.map(({ p, n }, i) => (
          <div key={p.id} style={{ display: 'grid', gridTemplateColumns: '110px 1fr 32px', gap: 12, alignItems: 'center', height: 42, borderTop: i ? C.hair : 'none' }}>
            <span className="ellipsis" style={{ fontSize: 15, color: C.label2 }}>{shortName(p)}</span>
            <span style={{ height: 8, borderRadius: 4, background: C.gray5, overflow: 'hidden' }}>
              <span style={{ display: 'block', height: '100%', width: `${(n / max) * 100}%`, background: C.red, opacity: 0.75, borderRadius: 4 }} />
            </span>
            <span className="num" style={{ fontSize: 15, textAlign: 'right', color: C.label2 }}>{n}</span>
          </div>
        ))}
      </div>
    </>
  );
}

function Dot({ kind, children }: { kind: 'played' | 'yet' | 'na'; children?: string }) {
  const s = kind === 'played' ? { width: 10, height: 10, background: C.blue }
    : kind === 'na' ? { width: 10, height: 10, background: C.gray4 }
      : { width: 9, height: 9, border: `1.5px solid ${C.orange}` };
  const dot = <span style={{ display: 'inline-block', borderRadius: 5, flexShrink: 0, ...s }} />;
  return children ? <span style={{ display: 'flex', alignItems: 'center', gap: 6 }}>{dot}{children}</span> : dot;
}

function GamesView() {
  const w = useWorkbench();
  return (
    <>
      <div style={{ ...card, overflow: 'hidden' }}>
        {w.gameLogs.map((g, i) => (
          <div key={g.id} style={{ display: 'flex', alignItems: 'center', gap: 14, padding: '12px 16px', borderTop: i ? C.hair : 'none' }}>
            <Icon name="archivebox" size={22} color={C.teal} />
            <span style={{ flex: 1 }}>
              <span style={{ display: 'block', fontSize: 17 }}>{g.opponent ? `vs ${g.opponent}` : 'Game'}</span>
              <span style={{ display: 'block', fontSize: 13, color: C.label2 }}>
                {g.gameDate.toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' })} · {g.inningsPlayed} innings
              </span>
            </span>
          </div>
        ))}
      </div>
      <p style={{ fontSize: 13, color: C.label2, margin: '10px 16px' }}>Season stats only count archived games.</p>
    </>
  );
}

function PlayersView({ totals }: { totals: Totals }) {
  const w = useWorkbench();
  const cols = '1fr 100px 100px 100px';
  const head = { fontSize: 12, fontWeight: 500, letterSpacing: 0.6, color: C.label2, textAlign: 'right' as const };
  return (
    <div style={{ ...card, overflow: 'hidden' }}>
      <div style={{ display: 'grid', gridTemplateColumns: cols, padding: '10px 18px', boxShadow: `inset 0 -0.5px 0 ${C.sep}` }}>
        <span style={{ ...head, textAlign: 'left' }}>PLAYER</span><span style={head}>INFIELD</span><span style={head}>OUTFIELD</span><span style={head}>BENCH</span>
      </div>
      {w.players.map((p, i) => {
        const t = totals.get(p.id)!;
        return (
          <div key={p.id} className="num" style={{ display: 'grid', gridTemplateColumns: cols, padding: '11px 18px', fontSize: 17, borderTop: i ? C.hair : 'none' }}>
            <span className="ellipsis">{p.firstName} {p.lastName}</span>
            <span style={{ textAlign: 'right', color: TIER_STYLE.Capable.fg, fontWeight: 600 }}>{t.infield}</span>
            <span style={{ textAlign: 'right', color: TIER_STYLE.Strength.fg, fontWeight: 600 }}>{t.outfield}</span>
            <span style={{ textAlign: 'right', color: C.label2 }}>{t.bench}</span>
          </div>
        );
      })}
    </div>
  );
}
