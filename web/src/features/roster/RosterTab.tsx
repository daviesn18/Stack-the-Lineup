import { useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';

import { activeFieldPositions } from '@/core/fairPlay';
import type { FieldPosition, Player, PositionPreferenceTier } from '@/core/model';
import { useTeam } from '@/data/teamStore';
import { Body, Button, Card, Field, Notice, usePalette } from '@/ui/kit';

const TIERS: (PositionPreferenceTier | null)[] = [null, 'Strength', 'Capable', 'Emergency', 'Never'];
const TIER_LABEL: Record<string, string> = { null: '—', Strength: 'Strength', Capable: 'Capable', Emergency: 'Emergency', Never: 'Never' };

type Draft = { firstName: string; lastName: string; number: string; leagueAge: string; prefs: Player['positionPreferences'] };
const blank: Draft = { firstName: '', lastName: '', number: '', leagueAge: '', prefs: {} };
const fromPlayer = (p: Player): Draft => ({
  firstName: p.firstName, lastName: p.lastName, number: p.number,
  leagueAge: p.leagueAge === undefined ? '' : String(p.leagueAge), prefs: { ...p.positionPreferences },
});

export function RosterTab() {
  const { data, addPlayer, updatePlayer, deletePlayer } = useTeam();
  const c = usePalette();
  const [editing, setEditing] = useState<string | 'new' | null>(null);
  const [confirmDelete, setConfirmDelete] = useState<string | null>(null);
  const { players, team } = data!;
  const positions = activeFieldPositions(team.fairPlayConfig);

  const save = (id: string | 'new', d: Draft) => {
    const age = d.leagueAge.trim() === '' ? undefined : Number(d.leagueAge);
    const fields: Omit<Player, 'id'> = {
      firstName: d.firstName.trim(), lastName: d.lastName.trim(), number: d.number.trim(),
      positionPreferences: d.prefs, ...(age !== undefined && Number.isInteger(age) ? { leagueAge: age } : {}),
    };
    if (id === 'new') addPlayer(fields);
    else {
      const existing = players.find((p) => p.id === id)!;
      updatePlayer({ ...fields, id, ...(existing.hittingArchetype ? { hittingArchetype: existing.hittingArchetype } : {}) });
    }
    setEditing(null);
  };

  return (
    <View style={{ gap: 16 }}>
      {editing === 'new'
        ? <PlayerEditor title="Add player" initial={blank} positions={positions} onSave={(d) => save('new', d)} onCancel={() => setEditing(null)} />
        : <View style={{ alignSelf: 'flex-start' }}><Button title="Add player" onPress={() => setEditing('new')} /></View>}

      {team.pitchingConfig.rulesEnabled && players.some((p) => p.leagueAge === undefined) && (
        <Notice kind="warn">Pitch count rules are on. Players without a league age can&apos;t be checked, so Auto-Fill won&apos;t put them on the mound.</Notice>
      )}

      <Card>
        {players.length === 0 && <Body muted>No players yet.</Body>}
        {players.map((p) =>
          editing === p.id ? (
            <PlayerEditor key={p.id} title={`Edit ${p.firstName}`} initial={fromPlayer(p)} positions={positions}
              onSave={(d) => save(p.id, d)} onCancel={() => setEditing(null)} />
          ) : (
            <View key={p.id} style={[styles.row, { borderColor: c.line }]}>
              <Text style={[styles.num, { color: c.muted }]}>{p.number ? `#${p.number}` : ''}</Text>
              <View style={{ flex: 1, minWidth: 160 }}>
                <Text style={{ color: c.ink, fontSize: 16, fontWeight: '600' }}>{p.firstName} {p.lastName}</Text>
                <Text style={{ color: c.muted }}>
                  {p.leagueAge !== undefined ? `Age ${p.leagueAge}` : 'No league age'}
                  {summary(p) ? ` · ${summary(p)}` : ''}
                </Text>
              </View>
              {confirmDelete === p.id ? (
                <>
                  <Body muted>Remove {p.firstName} from the team?</Body>
                  <Button title="Remove" kind="danger" onPress={() => { setConfirmDelete(null); deletePlayer(p.id); }} />
                  <Button title="Keep" kind="secondary" onPress={() => setConfirmDelete(null)} />
                </>
              ) : (
                <>
                  <Button title="Edit" kind="secondary" onPress={() => setEditing(p.id)} />
                  <Button title="Remove" kind="secondary" onPress={() => setConfirmDelete(p.id)} />
                </>
              )}
            </View>
          ),
        )}
      </Card>
    </View>
  );
}

function summary(p: Player): string {
  const by = (t: PositionPreferenceTier) =>
    Object.entries(p.positionPreferences).filter(([, v]) => v === t).map(([k]) => k);
  const parts = [];
  if (by('Strength').length) parts.push(`Strong: ${by('Strength').join(', ')}`);
  if (by('Never').length) parts.push(`Never: ${by('Never').join(', ')}`);
  return parts.join(' · ');
}

function PlayerEditor({
  title, initial, positions, onSave, onCancel,
}: { title: string; initial: Draft; positions: FieldPosition[]; onSave(d: Draft): void; onCancel(): void }) {
  const c = usePalette();
  const [d, setD] = useState<Draft>(initial);
  const ageOk = d.leagueAge.trim() === '' || /^\d{1,2}$/.test(d.leagueAge.trim());
  const valid = d.firstName.trim().length > 0 && ageOk;
  const setTier = (pos: FieldPosition, tier: PositionPreferenceTier | null) => {
    const prefs = { ...d.prefs };
    if (tier) prefs[pos] = tier; else delete prefs[pos];
    setD({ ...d, prefs });
  };
  return (
    <View style={[styles.editor, { borderColor: c.accent, backgroundColor: c.surface }]}>
      <Text style={{ color: c.ink, fontSize: 17, fontWeight: '700' }}>{title}</Text>
      <View style={styles.fields}>
        <View style={{ flex: 2, minWidth: 140 }}><Field label="First name" value={d.firstName} onChangeText={(v) => setD({ ...d, firstName: v })} /></View>
        <View style={{ flex: 2, minWidth: 140 }}><Field label="Last name" value={d.lastName} onChangeText={(v) => setD({ ...d, lastName: v })} /></View>
        <View style={{ flex: 1, minWidth: 80 }}><Field label="Number" value={d.number} onChangeText={(v) => setD({ ...d, number: v })} /></View>
        <View style={{ flex: 1, minWidth: 90 }}><Field label="League age" value={d.leagueAge} keyboardType="number-pad" onChangeText={(v) => setD({ ...d, leagueAge: v })} /></View>
      </View>
      {!ageOk && <Notice kind="error">League age should be a number, like 10.</Notice>}
      {ageOk && d.leagueAge.trim() !== '' && Number(d.leagueAge) > 16 && (
        <Notice kind="warn">Pitch count brackets go up to 16, so rules won&apos;t limit this player.</Notice>
      )}
      <Text style={[styles.label, { color: c.muted }]}>Positions</Text>
      <View style={{ gap: 6 }}>
        {positions.map((pos) => (
          <View key={pos} style={styles.prefRow}>
            <Text style={{ color: c.ink, width: 40, fontWeight: '700' }}>{pos}</Text>
            {TIERS.map((t) => {
              const on = (d.prefs[pos] ?? null) === t;
              return (
                <Pressable key={String(t)} accessibilityRole="radio" accessibilityState={{ checked: on }} onPress={() => setTier(pos, t)}
                  style={[styles.tier, { borderColor: on ? c.accent : c.line, backgroundColor: on ? c.accentSoft : 'transparent' }]}>
                  <Text style={{ color: on ? c.ink : c.muted, fontSize: 13 }}>{TIER_LABEL[String(t)]}</Text>
                </Pressable>
              );
            })}
          </View>
        ))}
      </View>
      <View style={styles.fields}>
        <Button title="Save" onPress={() => onSave(d)} disabled={!valid} />
        <Button title="Cancel" kind="secondary" onPress={onCancel} />
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  row: { flexDirection: 'row', flexWrap: 'wrap', alignItems: 'center', gap: 10, paddingVertical: 10, borderBottomWidth: 1 },
  num: { width: 40, fontVariant: ['tabular-nums'] },
  editor: { borderWidth: 2, borderRadius: 10, padding: 14, gap: 12 },
  fields: { flexDirection: 'row', flexWrap: 'wrap', gap: 10 },
  label: { fontSize: 13, fontWeight: '600', letterSpacing: 0.4, textTransform: 'uppercase' },
  prefRow: { flexDirection: 'row', flexWrap: 'wrap', alignItems: 'center', gap: 6 },
  tier: { borderWidth: 1, borderRadius: 6, paddingHorizontal: 10, minHeight: 32, justifyContent: 'center' },
});
