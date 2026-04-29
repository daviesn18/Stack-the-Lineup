import { useState, useEffect, useRef } from "react";

const COLUMNS = ["Up Next", "In Development", "Done"];
const EFFORT_LABELS = { 1: "Small", 2: "Medium", 3: "Large", 4: "X-Large" };

const PHASE_COLORS = {
  "v2.2.1":  { bg: "#fce7f3", color: "#9d174d" },
  "v2.3":    { bg: "#dbeafe", color: "#1e40af" },
  "v2.4":    { bg: "#dcfce7", color: "#166534" },
  "v2.5":    { bg: "#fef3c7", color: "#92400e" },
  "v3.0":    { bg: "#ede9fe", color: "#5b21b6" },
  "Backlog": { bg: "#f1f5f9", color: "#475569" },
};

const EFFORT_COLORS = {
  1: { bg: "#dcfce7", color: "#166534" },
  2: { bg: "#dbeafe", color: "#1e40af" },
  3: { bg: "#fef3c7", color: "#92400e" },
  4: { bg: "#fee2e2", color: "#991b1b" },
};

const COL_META = {
  "Up Next":        { dot: "#94a3b8", label: "#64748b" },
  "In Development": { dot: "#f59e0b", label: "#d97706" },
  "Done":           { dot: "#22c55e", label: "#16a34a" },
};

const INITIAL_CARDS = [
  // ── v2.2.1 — Internal Cleanup (no user-facing changes) ────────────────────
  {
    id: "v221-1", title: "Centralize back-to-back bench detection", phase: "v2.2.1", pro: false, effort: 1, column: "Up Next",
    notes: "Add hasBackToBackBench(player:) and playersWithBackToBackBench(players:) to Lineup.\n\nReplaces the duplicated (0..<6).contains scan currently in:\n• DefensiveGridView.gameWideIssueCount\n• DefensiveGridView.WarningsView.computeInningWarnings\n• PositionSummaryView.fairPlaySection\n• iPadDashboardView.FairPlayWarningsSheet\n\nWhy now: the bench rule becomes configurable in v2.4. One method = one place to add config check. Touching 4 files for that change is exactly how regressions happen.\n\nNo behavioral change. Pure refactor.",
  },
  {
    id: "v221-2", title: "Lineup.isPastAndFinalized helper", phase: "v2.2.1", pro: false, effort: 1, column: "Up Next",
    notes: "Add nonisolated computed var isPastAndFinalized: Bool to Lineup.\n\nCollapses identical 4-line check currently duplicated in:\n• ContentView.hasPastFinalizedGame (archive nudge)\n• GameLogsView.readyToArchiveLineup (history empty state)\n\nLogic: status == .finalized && startOfDay(gameDate) < startOfDay(today)\n\nGood warm-up before the bigger v2.2.1 refactors. No behavioral change.",
  },
  {
    id: "v221-3", title: "Inning count constants", phase: "v2.2.1", pro: false, effort: 1, column: "Up Next",
    notes: "Replace hardcoded 7 / 6 / 0..<7 / 0..<6 across 12+ sites with Lineup.inningCount and Lineup.lastInningIndex.\n\nFiles affected: DefensiveGridView, PositionSummaryView, iPadDashboardView, GameLogDetailView, PDFGenerator, DebugDataSeeder, Models.\n\nWhy now: configurable rules in v2.4 will likely include inning count per league (rec leagues vary 6 vs 7). Establishing the constant now means v2.4 can support variable counts without a follow-up sweep.\n\nNo behavioral change. Pure refactor.",
  },
  {
    id: "v221-4", title: "FieldPosition.solidBadgeColor", phase: "v2.2.1", pro: false, effort: 1, column: "Up Next",
    notes: "Move position color mapping onto FieldPosition itself.\n\nReplaces 3 near-identical helpers:\n• DefensiveGridView.PlayerInningRow.positionColor(_:)\n• DefensiveGridView.PositionPickerView.badgeColor(_:)\n• GameLogDetailView.positionColor(_:)\n\nWhy now: v2.5 adds pitcher-specific UI on the Positions tab. Consolidating before adding pitcher styling means new badges follow one pattern, not three.\n\nLeave PositionSummaryView.cellColor alone — that one uses opacity tints, different use case.\n\nNo behavioral change. Pure refactor.",
  },
  {
    id: "v221-5", title: "Centralize displayPlayers computed var", phase: "v2.2.1", pro: false, effort: 1, column: "Up Next",
    notes: "Add displayPlayers(from:) method on Lineup. Returns ordered batting lineup, falling back to active players if no batting order set.\n\nCollapses identical 4-line computed var in:\n• DefensiveGridView.displayPlayers\n• PositionSummaryView.displayPlayers\n\nWhy now: v2.5 pitching availability flags will affect which players show up where. One helper to update is much safer than two.\n\nNo behavioral change. Pure refactor.",
  },
  {
    id: "v221-6", title: "Collapse styledCurrentPosition / styledCurrentPlayer", phase: "v2.2.1", pro: false, effort: 1, column: "Up Next",
    notes: "PositionSummaryView has two private functions that are byte-for-byte identical except for parameter name. Both produce strikethrough/italic/secondary AttributedString.\n\nReplace with one styledStrikethrough(_:) method. Saves ~15 lines.\n\nLowest priority of the v2.2.1 batch — purely cosmetic. Keep grouped here so the cleanup release is comprehensive.\n\nNo behavioral change. Pure refactor.",
  },
  {
    id: "v221-7", title: "Clean up AutoFillEngine unused-warning", phase: "v2.2.1", pro: false, effort: 1, column: "Up Next",
    notes: "AutoFillEngine.swift line 227 has `_ = assigned // suppress unused warning`. The `var assigned` reassignments later in that block are no-ops since the variable isn't read after the final check.\n\nEither remove trailing assignments + the suppression, or restructure as early returns. Cosmetic — doesn't change algorithm output.\n\nLowest priority. Touch when next editing AutoFill.\n\nNo behavioral change. Pure refactor.",
  },

  // ── v2.3 — Setup & Scheduling ─────────────────────────────────────────────
  {
    id: "v23-1", title: "iCal schedule import", phase: "v2.3", pro: false, effort: 2, column: "Up Next",
    notes: "Parse a .ics file from GameChanger, LeagueApps, or any calendar app. Extract game date, time, and opponent from each VEVENT.\n\nIn LineupView, show 'Pick from schedule' to pre-fill date + opponent when starting a new lineup. Store as [ScheduledGame] on Team. Handle duplicate imports gracefully.",
  },
  {
    id: "v23-2", title: "Team roster import", phase: "v2.3", pro: false, effort: 2, column: "Up Next",
    notes: "Import player names and jersey numbers from CSV or .stlroster file.\n\nAfter import, prompt coach to complete each player: league age and position preferences. Do NOT auto-populate batting order or positions.\n\nShow a post-import checklist of players needing completion. Needs UX thought around what formats coaches actually have (GameChanger export? League spreadsheet?).",
  },

  // ── v2.4 — Configurable Fair Play ─────────────────────────────────────────
  {
    id: "v24-1", title: "Configure Fair Play Rules", phase: "v2.4", pro: false, effort: 4, column: "Up Next",
    notes: "Per-team rules engine. All config scoped to activeTeam — a coach with a rec team and travel team gets different rules for each.\n\nAll 9 rules ship in v2.4:\n\nSimple toggles / configurable values (map to existing data):\n• No Pitcher — toggle removes Pitcher from valid positions entirely\n• No Catcher — same pattern as No Pitcher\n• No Consecutive Bench Innings — already hardcoded, becomes a toggle\n• Minimum innings per player — already hardcoded at 4, becomes configurable Int\n• Equal Bench Time — don't sit someone twice before everyone has sat once\n• Minimum IF / OF innings — already hardcoded as 1 each, becomes configurable (complete by inning X)\n\nNew engine logic (require per-game inning-role tracking):\n• No consecutive position innings — same position back-to-back not allowed; new AutoFill + validation logic\n• Catcher→Pitcher restriction — caught N+ innings this game = can't pitch (real Little League rule)\n• Pitcher→Catcher restriction — pitched N+ innings this game = can't catch\n\nNote: the per-game inning-role counter built for the last 3 rules is reused by v2.5 pitch eligibility engine — building it here gives v2.5 a foundation.\n\nLeague ruleset selection per team (Little League, Cal Ripken, Babe Ruth) — prerequisite for v2.5 pitch limits.\n\nData: FairPlayConfig struct on Team. Validation engine and AutoFill both read activeTeam.fairPlayConfig.\n\nUI: Team edit flow in PlayersView, not global SettingsView. Clearly scoped to active team.",
  },

  // ── v2.5 — Pitching ───────────────────────────────────────────────────────
  {
    id: "v25-1", title: "Pitch count capture at archive", phase: "v2.5", pro: true, effort: 2, column: "Up Next",
    notes: "Prompt coach to enter pitch counts after archiving a game. Auto-detect who pitched from the positions grid and show those players in the prompt. Allow manual entry per pitcher.\n\nStore pitch counts on GameLog. If a player's league age is missing, prompt for it — required for rest day calculation.\n\nThis is the data capture layer. Eligibility computation is a separate card.",
  },
  {
    id: "v25-2", title: "Pitch eligibility & rest days", phase: "v2.5", pro: true, effort: 4, column: "Up Next",
    notes: "Rules engine computing eligibility from stored pitch counts:\n• Little League rest day chart (age-based thresholds: 7-8, 9-10, 11-12, 13-16)\n• Weekly pitch total vs. league limit\n• Required rest days based on count + age bracket\n• Eligibility status: eligible / limited (N innings) / must rest until [date]\n\nSurfaces warnings in positions view when assigning an ineligible pitcher.\n\nRuleset driven by league config set in v2.4. Requires: pitch count capture (v2.5-1) + Fair Play config (v2.4).",
  },
  {
    id: "v25-3", title: "Pitching note field", phase: "v2.5", pro: false, effort: 1, column: "Up Next",
    notes: "Optional freeform String on Player for short-term context (e.g. 'arm sore this week'). Shown as a subtitle in the positions view when assigning pitcher slot.\n\nFits naturally in the v2.5 pitching release alongside eligibility.",
  },
  {
    id: "v25-4", title: "GameChanger CSV import (pitch counts)", phase: "v2.5", pro: true, effort: 3, column: "Up Next",
    notes: "Parse GC game export CSV to populate pitch counts on GameLog instead of manual entry.\n\nFuzzy player name matching with confirmation UI for mismatches. File-based only — no API dependency. GC format may change; fail gracefully with a clear error.\n\nRequires: Pitch count capture at archive (v2.5-1).",
  },

  // ── v3.0 — Collaboration ──────────────────────────────────────────────────
  {
    id: "v30-1", title: "Draft / Finalize lineup states", phase: "v3.0", pro: false, effort: 2, column: "Up Next",
    notes: "Add to Lineup model:\n• lineupStatus: LineupStatus (.draft, .finalized)\n• lastEditedBy: String\n• lastEditedAt: Date\n\nSave Draft is explicit. Finalize locks lineup and is required before Archive. Finalized lineups show a lock indicator. Only head coach (owner) can finalize in shared context.\n\nPrerequisite for CloudKit sharing.",
  },
  {
    id: "v30-2", title: "CloudKit shared team", phase: "v3.0", pro: true, effort: 4, column: "Up Next",
    notes: "Migrate Team persistence from NSUbiquitousKeyValueStore blob to CKRecord + CKShare.\n\nHead coach owns the record, invites assistant coaches via CKShare link.\n\nRequires: CloudKit entitlement in Apple Developer portal (manual step), CKShare handling in scene delegate, two physical devices on different Apple IDs for testing, Draft/Finalize states in model.\n\nConflict resolution: last-write-wins per field — acceptable tradeoff.",
  },
  {
    id: "v30-3", title: "Shared game history", phase: "v3.0", pro: true, effort: 2, column: "Up Next",
    notes: "GameLog records shared automatically as part of Team CKRecord.\n\nAdd archivedBy: String to GameLog. History tab reflects full shared history regardless of which coach archived.\n\nRequires: CloudKit shared team (v3.0).",
  },
  {
    id: "v30-4", title: "Team file export / import", phase: "v3.0", pro: true, effort: 2, column: "Up Next",
    notes: "Export full Team struct as .stlteam JSON via iOS share sheet. Import to merge or replace.\n\nUseful as pre-CloudKit workaround and as backup/restore even after CloudKit exists. Post-import: prompt coach to review any incomplete fields.",
  },
];

const S = {
  label: { display: "block", fontSize: "11px", fontWeight: 600, color: "var(--color-text-secondary)", textTransform: "uppercase", letterSpacing: "0.05em", marginBottom: "5px" },
  input: { width: "100%", padding: "8px 10px", borderRadius: "8px", border: "1px solid var(--color-border-tertiary)", background: "var(--color-background-primary)", color: "var(--color-text-primary)", fontSize: "13px", outline: "none", boxSizing: "border-box", marginBottom: "12px", fontFamily: "var(--font-sans)" },
  saveBtn: { padding: "8px 20px", borderRadius: "8px", border: "none", background: "#3b82f6", color: "#fff", fontSize: "13px", fontWeight: 600, cursor: "pointer" },
  cancelBtn: { padding: "8px 20px", borderRadius: "8px", border: "1px solid var(--color-border-tertiary)", background: "transparent", color: "var(--color-text-secondary)", fontSize: "13px", cursor: "pointer" },
};

function Pill({ bg, color, children }) {
  return (
    <span style={{ fontSize: "10px", fontWeight: 600, padding: "2px 7px", borderRadius: "20px", background: bg, color, whiteSpace: "nowrap" }}>
      {children}
    </span>
  );
}

function Modal({ title, initial, saveLabel, onSave, onClose }) {
  const [form, setForm] = useState({ ...initial });
  const set = (k, v) => setForm(f => ({ ...f, [k]: v }));

  return (
    <div
      style={{ position: "fixed", top: 0, left: 0, right: 0, bottom: 0, zIndex: 9999, background: "rgba(0,0,0,0.6)", display: "flex", alignItems: "center", justifyContent: "center", padding: "20px", boxSizing: "border-box" }}
      onMouseDown={e => { if (e.target === e.currentTarget) onClose(); }}
    >
      <div
        style={{ background: "#ffffff", borderRadius: "16px", padding: "24px", width: "100%", maxWidth: "460px", boxShadow: "0 32px 80px rgba(0,0,0,0.35)", border: "1px solid #e2e8f0", maxHeight: "85vh", overflowY: "auto", boxSizing: "border-box" }}
        onMouseDown={e => e.stopPropagation()}
      >
        <h2 style={{ fontSize: "15px", fontWeight: 600, color: "#0f172a", margin: "0 0 18px" }}>{title}</h2>

        <label style={{ ...S.label, color: "#64748b" }}>Title</label>
        <input value={form.title} onChange={e => set("title", e.target.value)}
          style={{ ...S.input, background: "#f8fafc", color: "#0f172a", border: "1px solid #cbd5e1" }}
          placeholder="Feature name..." />

        <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "12px" }}>
          <div>
            <label style={{ ...S.label, color: "#64748b" }}>Release</label>
            <select value={form.phase} onChange={e => set("phase", e.target.value)}
              style={{ ...S.input, background: "#f8fafc", color: "#0f172a", border: "1px solid #cbd5e1" }}>
              {Object.keys(PHASE_COLORS).map(p => <option key={p}>{p}</option>)}
            </select>
          </div>
          <div>
            <label style={{ ...S.label, color: "#64748b" }}>Effort</label>
            <select value={form.effort} onChange={e => set("effort", Number(e.target.value))}
              style={{ ...S.input, background: "#f8fafc", color: "#0f172a", border: "1px solid #cbd5e1" }}>
              {Object.entries(EFFORT_LABELS).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
            </select>
          </div>
        </div>

        <label style={{ ...S.label, color: "#64748b" }}>Status</label>
        <select value={form.column} onChange={e => set("column", e.target.value)}
          style={{ ...S.input, background: "#f8fafc", color: "#0f172a", border: "1px solid #cbd5e1" }}>
          {COLUMNS.map(c => <option key={c}>{c}</option>)}
        </select>

        <div style={{ display: "flex", alignItems: "center", gap: "8px", marginBottom: "14px" }}>
          <input type="checkbox" id="pro-chk" checked={form.pro}
            onChange={e => set("pro", e.target.checked)}
            style={{ width: "15px", height: "15px", accentColor: "#3b82f6", cursor: "pointer" }} />
          <label htmlFor="pro-chk" style={{ fontSize: "13px", color: "#64748b", cursor: "pointer" }}>Pro feature</label>
        </div>

        <label style={{ ...S.label, color: "#64748b" }}>Requirements / Notes</label>
        <textarea
          value={form.notes}
          onChange={e => set("notes", e.target.value)}
          rows={6}
          style={{ ...S.input, resize: "vertical", lineHeight: 1.65, background: "#f8fafc", color: "#0f172a", border: "1px solid #cbd5e1" }}
          placeholder="Add requirements or notes..."
        />

        <div style={{ display: "flex", gap: "8px", justifyContent: "flex-end", marginTop: "8px" }}>
          <button onClick={onClose} style={{ ...S.cancelBtn, border: "1px solid #cbd5e1", color: "#64748b" }}>Cancel</button>
          <button onClick={() => { if (form.title.trim()) { onSave(form); onClose(); } }} style={S.saveBtn}>{saveLabel}</button>
        </div>
      </div>
    </div>
  );
}

function Card({ card, onEdit, onMove, onDelete }) {
  const pc = PHASE_COLORS[card.phase] || { bg: "#f1f5f9", color: "#475569" };
  const ec = EFFORT_COLORS[card.effort] || EFFORT_COLORS[1];
  return (
    <div
      onClick={() => onEdit(card)}
      style={{ background: "var(--color-background-primary)", border: "1px solid var(--color-border-tertiary)", borderRadius: "10px", padding: "13px", cursor: "pointer", transition: "box-shadow 0.15s, transform 0.12s" }}
      onMouseEnter={e => { e.currentTarget.style.boxShadow = "0 4px 14px rgba(0,0,0,0.1)"; e.currentTarget.style.transform = "translateY(-1px)"; }}
      onMouseLeave={e => { e.currentTarget.style.boxShadow = "none"; e.currentTarget.style.transform = "none"; }}
    >
      <div style={{ fontSize: "13px", fontWeight: 600, color: "var(--color-text-primary)", lineHeight: 1.4, marginBottom: "9px" }}>{card.title}</div>
      <div style={{ display: "flex", flexWrap: "wrap", gap: "4px", marginBottom: card.notes ? "9px" : 0 }}>
        <Pill bg={pc.bg} color={pc.color}>{card.phase}</Pill>
        {card.pro && <Pill bg="#dbeafe" color="#1e40af">PRO</Pill>}
        <Pill bg={ec.bg} color={ec.color}>{EFFORT_LABELS[card.effort]}</Pill>
      </div>
      {card.notes && (
        <div style={{ fontSize: "11px", color: "var(--color-text-secondary)", lineHeight: 1.55, borderTop: "1px solid var(--color-border-tertiary)", paddingTop: "8px", whiteSpace: "pre-line" }}>
          {card.notes.length > 150 ? card.notes.slice(0, 150) + "…" : card.notes}
        </div>
      )}
      <div style={{ display: "flex", gap: "5px", marginTop: "10px", justifyContent: "flex-end" }} onClick={e => e.stopPropagation()}>
        {COLUMNS.filter(c => c !== card.column).map(col => (
          <button key={col} onClick={() => onMove(card.id, col)} style={{ fontSize: "10px", padding: "3px 7px", borderRadius: "5px", border: "1px solid var(--color-border-tertiary)", background: "transparent", color: "var(--color-text-secondary)", cursor: "pointer", whiteSpace: "nowrap" }}>→ {col}</button>
        ))}
        <button onClick={() => onDelete(card.id)} style={{ fontSize: "10px", padding: "3px 7px", borderRadius: "5px", border: "1px solid #fecaca", background: "transparent", color: "#dc2626", cursor: "pointer" }}>✕</button>
      </div>
    </div>
  );
}

function ReleaseSummary({ cards }) {
  return (
    <div style={{ display: "flex", gap: "8px", marginBottom: "16px", flexWrap: "wrap" }}>
      {Object.entries(PHASE_COLORS).filter(([r]) => r !== "Backlog").map(([r, pc]) => {
        const rc = cards.filter(c => c.phase === r);
        const done = rc.filter(c => c.column === "Done").length;
        const total = rc.reduce((s, c) => s + c.effort, 0);
        const load = total <= 3 ? "Light" : total <= 6 ? "Medium" : total <= 10 ? "Heavy" : "Very Heavy";
        return (
          <div key={r} style={{ background: "var(--color-background-secondary)", border: "1px solid var(--color-border-tertiary)", borderRadius: "10px", padding: "10px 14px" }}>
            <div style={{ fontSize: "12px", fontWeight: 700, color: pc.color, background: pc.bg, padding: "1px 8px", borderRadius: "20px", display: "inline-block", marginBottom: "5px" }}>{r}</div>
            <div style={{ fontSize: "11px", color: "var(--color-text-secondary)" }}>{rc.length} features · {done}/{rc.length} done</div>
            <div style={{ fontSize: "11px", color: "var(--color-text-secondary)" }}>Load: {load}</div>
          </div>
        );
      })}
    </div>
  );
}

export default function RoadmapBoard() {
  const [cards, setCards] = useState(INITIAL_CARDS);
  const [modal, setModal] = useState(null);
  const [loaded, setLoaded] = useState(false);
  const [saveStatus, setSaveStatus] = useState("");
  const [filterRelease, setFilterRelease] = useState("All");
  const saveTimer = useRef(null);

  useEffect(() => {
    (async () => {
      try {
        const r = await window.storage.get("stl_roadmap_v5");
        if (r?.value) setCards(JSON.parse(r.value));
      } catch {}
      setLoaded(true);
    })();
  }, []);

  async function persist(next) {
    setCards(next);
    clearTimeout(saveTimer.current);
    saveTimer.current = setTimeout(async () => {
      try {
        await window.storage.set("stl_roadmap_v5", JSON.stringify(next));
        setSaveStatus("Saved");
        setTimeout(() => setSaveStatus(""), 2000);
      } catch { setSaveStatus("Save failed"); }
    }, 500);
  }

  const releases = ["All", ...Object.keys(PHASE_COLORS)];
  const visible = filterRelease === "All" ? cards : cards.filter(c => c.phase === filterRelease);

  if (!loaded) return <div style={{ padding: "32px", color: "var(--color-text-secondary)", fontSize: "13px" }}>Loading…</div>;

  return (
    <div style={{ fontFamily: "var(--font-sans)", padding: "20px 16px", position: "relative" }}>

      <div style={{ display: "flex", alignItems: "flex-start", justifyContent: "space-between", marginBottom: "16px" }}>
        <div>
          <h1 style={{ fontSize: "17px", fontWeight: 600, color: "var(--color-text-primary)", margin: 0 }}>Stack the Lineup — Roadmap</h1>
          <p style={{ fontSize: "12px", color: "var(--color-text-secondary)", margin: "3px 0 0" }}>Click any card to edit. Use → buttons to move columns.</p>
        </div>
        {saveStatus && <span style={{ fontSize: "11px", fontWeight: 500, color: saveStatus === "Saved" ? "#22c55e" : "#ef4444" }}>{saveStatus}</span>}
      </div>

      <ReleaseSummary cards={cards} />

      <div style={{ display: "flex", gap: "6px", marginBottom: "16px", flexWrap: "wrap" }}>
        {releases.map(r => {
          const active = filterRelease === r;
          const pc = PHASE_COLORS[r];
          return (
            <button key={r} onClick={() => setFilterRelease(r)} style={{ fontSize: "11px", fontWeight: 600, padding: "4px 12px", borderRadius: "20px", border: active ? "none" : "1px solid var(--color-border-tertiary)", background: active ? (pc?.bg || "#e2e8f0") : "transparent", color: active ? (pc?.color || "#1e293b") : "var(--color-text-secondary)", cursor: "pointer" }}>{r}</button>
          );
        })}
      </div>

      <div style={{ display: "grid", gridTemplateColumns: "repeat(3, 1fr)", gap: "12px", alignItems: "start" }}>
        {COLUMNS.map(col => {
          const meta = COL_META[col];
          const colCards = visible.filter(c => c.column === col);
          return (
            <div key={col} style={{ background: "var(--color-background-secondary)", borderRadius: "12px", padding: "12px", border: "1px solid var(--color-border-tertiary)" }}>
              <div style={{ display: "flex", alignItems: "center", gap: "7px", marginBottom: "11px" }}>
                <span style={{ width: "7px", height: "7px", borderRadius: "50%", background: meta.dot, flexShrink: 0 }} />
                <span style={{ fontSize: "11px", fontWeight: 600, color: meta.label, textTransform: "uppercase", letterSpacing: "0.07em" }}>{col}</span>
                <span style={{ marginLeft: "auto", fontSize: "10px", color: "var(--color-text-secondary)", background: "var(--color-background-primary)", border: "1px solid var(--color-border-tertiary)", borderRadius: "20px", padding: "1px 7px" }}>{colCards.length}</span>
              </div>
              <div style={{ display: "flex", flexDirection: "column", gap: "7px" }}>
                {colCards.map(card => (
                  <Card key={card.id} card={card}
                    onEdit={c => setModal({ mode: "edit", data: c })}
                    onMove={(id, c) => persist(cards.map(x => x.id === id ? { ...x, column: c } : x))}
                    onDelete={id => persist(cards.filter(x => x.id !== id))}
                  />
                ))}
              </div>
              <button
                onClick={() => setModal({ mode: "add", data: { title: "", phase: "v2.2.1", pro: false, effort: 1, column: col, notes: "" } })}
                style={{ width: "100%", marginTop: "9px", padding: "8px", borderRadius: "8px", border: "1.5px dashed var(--color-border-tertiary)", background: "transparent", color: "var(--color-text-secondary)", fontSize: "12px", cursor: "pointer", display: "flex", alignItems: "center", justifyContent: "center", gap: "5px" }}
              >
                <span style={{ fontSize: "15px", lineHeight: 1 }}>+</span> Add feature
              </button>
            </div>
          );
        })}
      </div>

      {modal && (
        <Modal
          title={modal.mode === "edit" ? "Edit feature" : "Add feature"}
          initial={modal.data}
          saveLabel={modal.mode === "edit" ? "Save" : "Add feature"}
          onSave={form => {
            if (modal.mode === "edit") {
              persist(cards.map(c => c.id === form.id ? form : c));
            } else {
              persist([...cards, { ...form, id: `custom-${Date.now()}` }]);
            }
          }}
          onClose={() => setModal(null)}
        />
      )}
    </div>
  );
}
