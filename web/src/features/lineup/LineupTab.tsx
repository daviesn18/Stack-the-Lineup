import { useEffect, useMemo, useRef, useState } from 'react';
import {
  Platform, Pressable, ScrollView, StyleSheet, Text, TextInput, View, useColorScheme, useWindowDimensions,
} from 'react-native';

import { runAutoFill, type AutoFillOutcome } from '@/core/autofillCoordinator';
import { activeFieldPositions, fairPlayFindings, openPositions } from '@/core/fairPlay';
import {
  assign, clearPositions, displayPlayers, finalize, moveBatter, reopen, shortName, toggleAbsent, unassign,
} from '@/core/lineupOps';
import type { FieldPosition, GameLog, Lineup, Player } from '@/core/model';
import { blocksAssignment, status as pitchStatus } from '@/core/pitching';
import { useIsPro } from '@/data/auth';
import { useTeam, type TeamInfo } from '@/data/teamStore';
import { battingOrderPdf, coachesGuidePdf, pdfFilename } from '@/print/lineupPdf';
import { openPdfTab } from '@/print/openPdf';
import { DateField } from '@/ui/DateField';
import { Body, Button, Card, Field, Notice, usePalette } from '@/ui/kit';

import { positionColors, SHORT_CODES, TYPED_CODES } from './positions';

type Sel = { row: number; inning: number } | null;

export function LineupTab() {
  const { data, editLineup } = useTeam();
  const c = usePalette();
  const dark = useColorScheme() === 'dark';
  const isPro = useIsPro();
  const { width } = useWindowDimensions();
  const wide = width >= 1060;
  const [sel, setSel] = useState<Sel>(null);
  const [prompt, setPrompt] = useState('');
  const [fillResult, setFillResult] = useState<{ outcome: AutoFillOutcome; before: Lineup } | null>(null);
  const [confirmClear, setConfirmClear] = useState(false);
  const [printError, setPrintError] = useState<string | null>(null);

  const { team, players, lineup, gameLogs } = data!;
  const config = team.fairPlayConfig;
  const rows = useMemo(() => displayPlayers(lineup, players), [lineup, players]);
  const absent = players.filter((p) => lineup.absentPlayerIDs.includes(p.id));
  const positions = activeFieldPositions(config);
  const innings = lineup.innings.map((_, i) => i);
  const selPlayer = sel ? rows[sel.row] : undefined;

  const setCell = (player: Player, inning: number, pos: FieldPosition | null) => {
    setFillResult(null);
    editLineup((l) => (pos ? assign(l, player.id, [inning], pos) : unassign(l, player.id, [inning])));
  };
  const advance = () => setSel((s) => (s ? { row: Math.min(s.row + 1, rows.length - 1), inning: s.inning } : s));

  // Keyboard entry (web): arrows move, type a position code, Delete clears, Esc deselects.
  const buffer = useRef('');
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  useEffect(() => {
    if (Platform.OS !== 'web' || !sel || !selPlayer) return;
    const apply = (code: string) => {
      const pos = TYPED_CODES[code] ?? SHORT_CODES[code];
      buffer.current = '';
      if (pos && (pos === 'Bench' || positions.includes(pos))) { setCell(selPlayer, sel.inning, pos); advance(); }
    };
    const onKey = (e: KeyboardEvent) => {
      const tag = (document.activeElement?.tagName ?? '').toLowerCase();
      if (tag === 'input' || tag === 'textarea' || e.metaKey || e.ctrlKey || e.altKey) return;
      const move = { ArrowUp: [-1, 0], ArrowDown: [1, 0], ArrowLeft: [0, -1], ArrowRight: [0, 1] }[e.key];
      if (move) {
        e.preventDefault();
        setSel({ row: clamp(sel.row + move[0], 0, rows.length - 1), inning: clamp(sel.inning + move[1], 0, innings.length - 1) });
        return;
      }
      if (e.key === 'Escape') { setSel(null); return; }
      if (e.key === 'Backspace' || e.key === 'Delete') { e.preventDefault(); setCell(selPlayer, sel.inning, null); return; }
      if (e.key === 'Enter') { advance(); return; }
      if (!/^[a-z0-9]$/i.test(e.key)) return;
      e.preventDefault();
      buffer.current += e.key.toLowerCase();
      if (timer.current) clearTimeout(timer.current);
      const b = buffer.current;
      const longer = [...Object.keys(TYPED_CODES), ...Object.keys(SHORT_CODES)].some((k) => k.length > b.length && k.startsWith(b));
      if (TYPED_CODES[b] && !longer) apply(b);
      else timer.current = setTimeout(() => apply(b), 600);
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  });

  const fill = (scope: 'game' | 'inning') => {
    const before = lineup;
    const outcome = runAutoFill({
      scope: scope === 'game' ? { kind: 'through', inning: innings.length - 1 } : { kind: 'inning', inning: sel?.inning ?? 0 },
      prompt, lineup, players, config, pitchingConfig: team.pitchingConfig, gameLogs,
    });
    if (outcome.filledCount > 0) editLineup(() => outcome.lineup);
    setFillResult({ outcome, before });
  };

  const print = (kind: 'battingOrder' | 'coachesGuide') => {
    setPrintError(null);
    const show = openPdfTab();   // must happen in the click, before any await
    const input = {
      lineup, players, gameLogs, teamName: team.name, teamColorHex: team.colorHex, pitchingConfig: team.pitchingConfig,
    };
    (kind === 'battingOrder' ? battingOrderPdf(input) : coachesGuidePdf(input))
      .then((bytes) => show(bytes, pdfFilename(kind, lineup.gameDate)))
      .catch((e: Error) => setPrintError(`Couldn't make the printout: ${e.message}`));
  };

  const warnings = useMemo(() => buildWarnings(lineup, players, team, gameLogs), [lineup, players, team, gameLogs]);

  const grid = (
    <Card>
      <ScrollView horizontal>
        <View>
          <View style={[styles.row, styles.headRow, { borderColor: c.line }]}>
            <Text style={[styles.orderCell, styles.head, { color: c.muted }]}>#</Text>
            <Text style={[styles.nameCell, styles.head, { color: c.muted }]}>Player</Text>
            {innings.map((i) => (
              <Text key={i} style={[styles.cell, styles.head, { color: sel?.inning === i ? c.accent : c.muted }]}>{i + 1}</Text>
            ))}
          </View>
          {rows.map((p, r) => (
            <View key={p.id} style={[styles.row, { borderColor: c.line }]}>
              <Text style={[styles.orderCell, { color: c.muted }]}>{r + 1}</Text>
              <Text numberOfLines={1} style={[styles.nameCell, { color: c.ink }]}>
                {p.number ? <Text style={{ color: c.muted }}>#{p.number} </Text> : null}{shortName(p)}
              </Text>
              {innings.map((i) => {
                const pos = lineup.innings[i].assignments[p.id];
                const col = positionColors(pos, c, dark);
                const selected = sel?.row === r && sel.inning === i;
                return (
                  <Pressable key={i} accessibilityRole="button" accessibilityLabel={`${p.firstName}, inning ${i + 1}: ${pos ?? 'open'}`}
                    onPress={() => setSel(selected ? null : { row: r, inning: i })}
                    style={[styles.cell, styles.cellBox, { backgroundColor: col.bg, borderColor: selected ? c.accent : 'transparent' }]}>
                    <Text style={[styles.cellText, { color: pos ? col.fg : c.line }]}>{pos === 'Bench' ? 'BN' : pos ?? '·'}</Text>
                  </Pressable>
                );
              })}
            </View>
          ))}
          <View style={[styles.row, { borderColor: 'transparent' }]}>
            <Text style={[styles.orderCell]} />
            <Text style={[styles.nameCell, styles.head, { color: c.muted }]}>Open</Text>
            {innings.map((i) => {
              const open = openPositions(lineup, i, players, config);
              return (
                <Text key={i} accessibilityLabel={open.length ? `Inning ${i + 1} open: ${open.join(', ')}` : `Inning ${i + 1} full`}
                  style={[styles.cell, styles.openText, { color: open.length ? c.warn : c.muted }]}>
                  {open.length === 0 ? '✓' : open.length <= 2 ? open.join(' ') : `${open.length} open`}
                </Text>
              );
            })}
          </View>
        </View>
      </ScrollView>

      {sel && selPlayer && (
        <View style={[styles.picker, { borderColor: c.line }]}>
          <Text style={{ color: c.ink, fontWeight: '600' }}>{shortName(selPlayer)} · inning {sel.inning + 1}</Text>
          <View style={styles.pickerButtons}>
            {[...positions, 'Bench' as const].map((pos) => {
              const holder = pos === 'Bench' ? undefined
                : rows.find((x) => x.id !== selPlayer.id && lineup.innings[sel.inning].assignments[x.id] === pos);
              const col = positionColors(pos, c, dark);
              const current = lineup.innings[sel.inning].assignments[selPlayer.id] === pos;
              return (
                <Pressable key={pos} accessibilityRole="button" onPress={() => { setCell(selPlayer, sel.inning, pos); advance(); }}
                  style={[styles.pickButton, { backgroundColor: col.bg, borderColor: current ? c.accent : 'transparent' }]}>
                  <Text style={{ color: col.fg, fontWeight: '700' }}>{pos}</Text>
                  {holder && <Text style={{ color: c.muted, fontSize: 11 }}>{holder.firstName}</Text>}
                </Pressable>
              );
            })}
            <Button title="Clear" kind="secondary" onPress={() => { setCell(selPlayer, sel.inning, null); advance(); }} />
          </View>
          {Platform.OS === 'web' && (
            <Text style={{ color: c.muted, fontSize: 13 }}>
              Keyboard: arrows move · type p, c, 1b, ss, lf, cf… or b for bench · Delete clears · Esc closes
            </Text>
          )}
        </View>
      )}
    </Card>
  );

  const autoFill = (
    <Card>
      <Text style={[styles.cardTitle, { color: c.ink }]}>Auto-Fill</Text>
      {isPro === false ? (
        <Body muted>Auto-Fill is a Pro feature. Subscribe in the iPhone app and it unlocks here too.</Body>
      ) : (
        <>
          <TextInput multiline value={prompt} onChangeText={setPrompt} placeholderTextColor={c.muted}
            placeholder={'Optional instructions, one per line:\nJake pitches innings 1 to 2\nkeep Nate off pitcher'}
            style={[styles.prompt, { color: c.ink, borderColor: c.line, backgroundColor: c.surface }]} />
          <View style={styles.buttonRow}>
            <Button title="Fill whole game" onPress={() => fill('game')} />
            <Button title={`Fill inning ${(sel?.inning ?? 0) + 1}`} kind="secondary" onPress={() => fill('inning')} />
            {!confirmClear
              ? <Button title="Clear all positions" kind="secondary" onPress={() => setConfirmClear(true)} />
              : <Button title="Yes, clear every inning" kind="danger" onPress={() => {
                  setConfirmClear(false); setFillResult(null); editLineup((l) => clearPositions(l));
                }} />}
          </View>
          <Body muted>Fills open cells only; anything you&apos;ve set stays put.</Body>
        </>
      )}
      {fillResult && (
        <View style={{ gap: 8 }}>
          <View style={styles.buttonRow}>
            <Body>{fillResult.outcome.filledCount ? fillResult.outcome.undoMessage : 'Nothing to fill: every open cell in that range is already set.'}</Body>
            {fillResult.outcome.filledCount > 0 && (
              <Button title="Undo" kind="secondary" onPress={() => { const b = fillResult.before; setFillResult(null); editLineup(() => b); }} />
            )}
          </View>
          {fillResult.outcome.incompleteMessage && <Notice kind="warn">{fillResult.outcome.incompleteMessage}</Notice>}
          {fillResult.outcome.noticeMessage && <Notice>{fillResult.outcome.noticeMessage}</Notice>}
        </View>
      )}
    </Card>
  );

  const warningCard = warnings.length > 0 && (
    <Card>
      <Text style={[styles.cardTitle, { color: c.ink }]}>Check before you print</Text>
      {warnings.map((w) => <Notice key={w} kind="warn">{w}</Notice>)}
    </Card>
  );

  const side = (
    <View style={{ gap: 16, width: wide ? 340 : '100%' }}>
      <Card>
        <OpponentField value={lineup.opponent} onCommit={(v) => editLineup((l) => ({ ...l, opponent: v }))} />
        <DateField label="Game date" value={lineup.gameDate} onChange={(d) => editLineup((l) => ({ ...l, gameDate: d }))} />
        <View style={styles.buttonRow}>
          <Text style={[styles.status, { color: lineup.status === 'finalized' ? c.accent : c.muted, borderColor: lineup.status === 'finalized' ? c.accent : c.line }]}>
            {lineup.status === 'finalized' ? 'FINALIZED' : 'DRAFT'}
          </Text>
          {lineup.status === 'finalized'
            ? <Button title="Reopen" kind="secondary" onPress={() => editLineup((l) => reopen(l))} />
            : <Button title="Finalize lineup" onPress={() => editLineup((l) => finalize(l, team.coachName))} />}
        </View>
        {lineup.status === 'finalized' && lineup.lastFinalizedAt && (
          <Body muted>Finalized{lineup.lastFinalizedBy ? ` by ${lineup.lastFinalizedBy}` : ''} {lineup.lastFinalizedAt.toLocaleString()}. Any change sets it back to draft.</Body>
        )}
      </Card>

      <Card>
        <Text style={[styles.cardTitle, { color: c.ink }]}>Print</Text>
        <View style={styles.buttonRow}>
          <Button title="Batting order" onPress={() => print('battingOrder')} />
          <Button title="Coaches guide" onPress={() => print('coachesGuide')} />
        </View>
        <Body muted>Opens a PDF (US Letter) in a new tab, ready to print or save.</Body>
        {openCount(lineup, players, config) > 0 && (
          <Notice kind="warn">{openCount(lineup, players, config)} field {openCount(lineup, players, config) === 1 ? 'spot is' : 'spots are'} still open. They print as blanks.</Notice>
        )}
        {printError && <Notice kind="error">{printError}</Notice>}
      </Card>

      <Card>
        <Text style={[styles.cardTitle, { color: c.ink }]}>Batting order</Text>
        {rows.map((p, i) => (
          <View key={p.id} style={styles.batter}>
            <Text style={[styles.batterNo, { color: c.muted }]}>{i + 1}</Text>
            <Text numberOfLines={1} style={{ color: c.ink, flex: 1 }}>{p.firstName} {p.lastName}</Text>
            <SmallButton label="▲" disabled={i === 0} onPress={() => editLineup((l) => moveBatter(l, p.id, i - 1))} />
            <SmallButton label="▼" disabled={i === rows.length - 1} onPress={() => editLineup((l) => moveBatter(l, p.id, i + 1))} />
            <SmallButton label="Out" onPress={() => { setSel(null); editLineup((l) => toggleAbsent(l, p.id)); }} />
          </View>
        ))}
        {absent.length > 0 && <Text style={[styles.subhead, { color: c.muted }]}>Not here today</Text>}
        {absent.map((p) => (
          <View key={p.id} style={styles.batter}>
            <Text numberOfLines={1} style={{ color: c.muted, flex: 1 }}>{p.firstName} {p.lastName}</Text>
            <SmallButton label="Back in" onPress={() => editLineup((l) => toggleAbsent(l, p.id))} />
          </View>
        ))}
        {players.length === 0 && <Body muted>Add players on the Roster tab.</Body>}
      </Card>
    </View>
  );

  return (
    <View style={[styles.layout, { flexDirection: wide ? 'row' : 'column' }]}>
      <View style={{ flex: 1, gap: 16, minWidth: 0 }}>
        {grid}
        {autoFill}
        {warningCard}
      </View>
      {side}
    </View>
  );
}

function OpponentField({ value, onCommit }: { value: string; onCommit(v: string): void }) {
  const [text, setText] = useState(value);
  const [seen, setSeen] = useState(value);
  if (value !== seen) { setSeen(value); setText(value); }   // lineup reloaded or changed elsewhere
  const commit = () => { const v = text.trim(); if (v !== value) onCommit(v); };
  return <Field label="Opponent" value={text} onChangeText={setText} onBlur={commit} onSubmitEditing={commit} placeholder="Who you're playing" />;
}

function SmallButton({ label, onPress, disabled }: { label: string; onPress: () => void; disabled?: boolean }) {
  const c = usePalette();
  return (
    <Pressable accessibilityRole="button" onPress={disabled ? undefined : onPress}
      style={[styles.small, { borderColor: c.line, opacity: disabled ? 0.35 : 1 }]}>
      <Text style={{ color: c.ink, fontSize: 13 }}>{label}</Text>
    </Pressable>
  );
}

const clamp = (n: number, lo: number, hi: number) => Math.max(lo, Math.min(hi, n));

/** Open field spots across all innings. */
const openCount = (lineup: Lineup, players: Player[], config: TeamInfo['fairPlayConfig']) =>
  lineup.innings.reduce((n, _, i) => n + openPositions(lineup, i, players, config).length, 0);

/** The grid's warnings: fair-play rules, plus pitchers who must rest on game day. */
function buildWarnings(lineup: Lineup, players: Player[], team: TeamInfo, gameLogs: GameLog[]): string[] {
  const out: string[] = [];
  const names = (ps: Player[]) => ps.map(shortName).join(', ');
  const f = fairPlayFindings(lineup, players, team.fairPlayConfig);
  const active = players.filter((p) => !lineup.absentPlayerIDs.includes(p.id));
  const complete = active.length > 0 && lineup.innings.every((inn) => active.every((p) => p.id in inn.assignments));

  if (f.withoutInfield.length) out.push(`No infield inning yet: ${names(f.withoutInfield)}.`);
  if (f.withoutOutfield.length) out.push(`No outfield inning yet: ${names(f.withoutOutfield)}.`);
  if (complete && f.underFieldingMinimum.length) {
    out.push(`Under ${f.minimumFieldingInnings} fielding innings: ${names(f.underFieldingMinimum)}.`);
  }
  for (const p of f.backToBackBench) {
    const pairs: string[] = [];
    for (let i = 0; i < lineup.innings.length - 1; i++) {
      if (lineup.innings[i].assignments[p.id] === 'Bench' && lineup.innings[i + 1].assignments[p.id] === 'Bench') pairs.push(`${i + 1}–${i + 2}`);
    }
    out.push(`${shortName(p)} sits back to back (innings ${pairs.join(', ')}).`);
  }
  if (f.catcherThenPitcher.length) out.push(`Caught, then pitched (league battery rule): ${names(f.catcherThenPitcher)}.`);
  if (f.pitcherThenCatcher.length) out.push(`Pitched, then caught (league battery rule): ${names(f.pitcherThenCatcher)}.`);

  if (team.pitchingConfig.rulesEnabled) {
    for (const p of active) {
      if (!lineup.innings.some((inn) => inn.assignments[p.id] === 'P')) continue;
      const s = pitchStatus(p, gameLogs, team.pitchingConfig, lineup.gameDate);
      if (!blocksAssignment(s)) continue;
      out.push(s.kind === 'mustRest'
        ? `${shortName(p)} is pitching but must rest until ${s.until.toLocaleDateString(undefined, { weekday: 'short', month: 'numeric', day: 'numeric' })} under your pitch count rules.`
        : `${shortName(p)} is pitching but has no league age set, so pitch count rules can't be checked. Add it on the Roster tab.`);
    }
  }
  return out;
}

const styles = StyleSheet.create({
  layout: { gap: 16, alignItems: 'flex-start' },
  row: { flexDirection: 'row', alignItems: 'center', borderBottomWidth: 1, minHeight: 40 },
  headRow: { minHeight: 32 },
  head: { fontSize: 12, fontWeight: '700', letterSpacing: 0.6, textTransform: 'uppercase' },
  orderCell: { width: 28, textAlign: 'right', paddingRight: 8, fontVariant: ['tabular-nums'] },
  nameCell: { width: 150, paddingRight: 8, fontSize: 15 },
  cell: { width: 52, textAlign: 'center' },
  cellBox: { height: 32, marginHorizontal: 2, borderRadius: 6, borderWidth: 2, alignItems: 'center', justifyContent: 'center' },
  cellText: { fontSize: 14, fontWeight: '700' },
  openText: { fontSize: 11, lineHeight: 14, paddingTop: 6 },
  picker: { borderTopWidth: 1, paddingTop: 12, gap: 10 },
  pickerButtons: { flexDirection: 'row', flexWrap: 'wrap', gap: 6, alignItems: 'center' },
  pickButton: { minWidth: 52, minHeight: 44, borderRadius: 8, borderWidth: 2, alignItems: 'center', justifyContent: 'center', paddingHorizontal: 8 },
  cardTitle: { fontSize: 17, fontWeight: '700' },
  prompt: { minHeight: 76, borderWidth: 1, borderRadius: 8, padding: 10, fontSize: 15, textAlignVertical: 'top' },
  buttonRow: { flexDirection: 'row', flexWrap: 'wrap', gap: 8, alignItems: 'center' },
  status: { fontSize: 12, fontWeight: '700', letterSpacing: 1, borderWidth: 1, borderRadius: 4, paddingHorizontal: 8, paddingVertical: 3 },
  batter: { flexDirection: 'row', alignItems: 'center', gap: 6, minHeight: 36 },
  batterNo: { width: 22, textAlign: 'right', fontVariant: ['tabular-nums'] },
  subhead: { fontSize: 12, fontWeight: '700', letterSpacing: 0.6, textTransform: 'uppercase', marginTop: 8 },
  small: { borderWidth: 1, borderRadius: 6, paddingHorizontal: 8, minHeight: 30, justifyContent: 'center' },
});
