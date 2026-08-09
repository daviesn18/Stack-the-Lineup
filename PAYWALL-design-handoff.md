# Paywall Redesign — Handoff to Design

> **Shipped.** The one thing still outstanding is the on-device dark mode and Dynamic Type calibration under "Still on Design" — tracked as [`BACKLOG.md`](BACKLOG.md) item 4.3. Otherwise this stands as the reference for the paywall's content rules and source → hero mapping.

**Owner split:** Content, copy, and code are handled outside this doc (see "Content decisions already made"). This handoff covers what Design owns: layout, hierarchy, density, and motion.

**File:** `Lineup Builder/PaywallView.swift`
**Component:** `ProFeatureRow` (icon + title + description, `HStack` with 36pt icon column)

---

## What this screen is

A sheet shown to free users the moment they tap something Pro-gated. It is not a marketing page they browsed to — it is an interruption. The coach was mid-task, usually minutes before a game.

It is presented from **10 distinct places** in the app:

| Source string | What the coach just tapped |
|---|---|
| `autofill` | The bolt icon on the Positions tab |
| `player_preferences` | Position preference tags in a player's edit screen |
| `lineup_template` | Save as Template / apply a template (3 call sites) |
| `pdf_export` | Coaches Guide PDF on the Lineup tab |
| `game_history` | The History tab |
| `team_export` | Export Team File |
| `team_import` | Opening a `.stlteam` file |
| `settings` | The upgrade row in Settings |

Today all 10 render identically. That is the main thing to solve.

---

## The problems to design against

**1. The buy button is below the fold — often two screens down.**
Nine feature rows sit in a plain `ScrollView` with no pinned footer. A coach who doesn't scroll never sees the price or the CTA. This is the highest-priority fix.

**2. No acknowledgment of what the coach was doing.**
Someone who tapped Auto-Fill sees a generic nine-item list. The thing they wanted is row one, but nothing connects it to the tap that got them here.

**3. Uniform weight across nine rows.**
Every row has identical icon size, title weight, and description length. Nothing is primary. Scanning it costs the same as reading it.

**4. The free tier is invisible.**
The list implies the app does nothing without Pro. In reality batting order, position assignment, fair play warnings, roster import, schedule import, and the Batting Order PDF are all free. Coaches who think the app is a paid-only tool bounce.

---

## Content Design is laying out

Eight feature rows in three groups. Copy is final; treat lengths as fixed.

**Group 1 — Build lineups faster**
- Auto-Fill Positions — "Fill an inning or the whole game in one tap, fair play rules included."
- Position Preferences — "Tag what each player can handle. Auto-Fill places them accordingly."
- Lineup Templates — "Save a lineup and rebuild it next week in one tap."

**Group 2 — Share it with your coaches and parents**
- Coaches Guide PDF — "The full inning-by-inning grid, printed for the dugout."
- Shared Teams — "Invite an assistant coach to build positions with you."

**Group 3 — Track the whole season**
- Game History — "Archive every game and keep a season record."
- AI Coaching Insights — "Spot bench-time and playing-time patterns across the season."
- Pitch Count Tracking — "Weekly limits and rest days by age, checked as you assign."

Plus a free-tier line, placement at Design's discretion:
"Batting order, positions, fair play warnings, and roster import are always free."

---

## What Design needs to solve

**A contextual hero.** When the source is a known feature, that feature should lead — named, and visibly connected to what the coach just tapped. The other seven become secondary. Design decides the mechanism: promoted card, callout above the list, reordering, a "you just tried" framing. Note the `settings` and `preview` sources have no context, so the layout needs a graceful generic state.

**A visible CTA.** Pinned footer, sticky bar, or a compact enough layout that it clears the fold on a 6.1" screen. Price and button must be reachable without scrolling intent.

**Three tiers of density**, roughly: hero feature > the rest > the free-tier line. Today everything is tier two.

**Group treatment.** Headers, dividers, cards, or none — as long as eight rows stop reading as one undifferentiated wall.

---

## Hard constraints

- **Restore Purchase must stay visible.** Apple requirement, not a design preference. It cannot be hidden behind a menu or a scroll.
- **A price/terms disclosure slot must exist below the buy button.** Today it holds one line. It needs room for four or five lines without a redesign — see below.
- **The error message slot** (`purchaseManager.purchaseError`) must have a home. It appears on failed purchase, failed restore, and failed product load.
- **The loading state** replaces the button label with a `ProgressView`. Don't design a button whose width collapses when the label is gone.
- **Dark mode.** Every current color is a literal (`.blue`, `.green`, `.purple`, `.orange`) with no dark variants specified.
- **Dynamic Type.** Coaches skew older; large accessibility sizes are realistic here. The current fixed 36pt icon column and `.callout` descriptions have not been tested at AX sizes.

---

## Plan for subscriptions

Pricing is moving from a $4.99 one-time purchase to a subscription. Design should not assume a single price string.

**The layout must accommodate, without rework:**
- **Two or more plan options** — likely monthly and annual, with the annual carrying a savings badge. This needs real estate the current design has none of.
- **A longer legal block.** Auto-renewable subscriptions require disclosure of price, period, renewal terms, and links to Terms and Privacy (App Review guideline 3.1.2). Today's single line "One-time purchase. No subscription." becomes roughly four to five lines plus two links.
- **A trial or intro-offer badge**, if one is used at launch.
- **A different button label.** "Unlock Pro — $4.99" becomes something like "Start free trial" or "Subscribe — $X/season."

Design for the subscription shape now even though the current build ships one-time. The code will render whichever applies; the layout should not have to change twice.

**Worth exploring:** youth baseball is seasonal. A season-length term may fit coaches better than monthly, and may be worth showing as the default option.

---

## Resolved (implemented)

Everything below is now built in `PaywallView.swift`. This section records the decisions so the doc stays the source of truth.

- **Pricing: one subscription — 7 days free, then $9.99/year.** No multi-plan picker. All price/CTA/legal strings derive from StoreKit via `PurchaseManager` (`priceText`, `ctaLabel`, `planHeadline`, `legalText`); nothing is hardcoded, and the trial promise only shows when the account is actually eligible.
- **Multiple Teams: cut for good.** The feature is free and ungated; no row.
- **Team file import/export: it was a bug — now free.** The paywall was removed from both call sites. These sources no longer have a hero and fall back to the generic one.
- **Shared Teams stays Pro.** Note the earlier `team_export`/`team_import` → Shared Teams hero mapping in the mock was wrong: those are team *files* (free), a different feature from *Shared Teams* (CloudKit co-editing, Pro). Shared Teams is now gated from its own control with `source: "shared_teams"`.
- **Icons corrected:** Shared Teams uses `person.2.wave.2.fill` (matches the in-app Share Team button, avoids reusing the Players-tab `person.3.fill`); Lineup Templates uses `square.stack.3d.up.fill`; pitch tracking uses `figure.baseball` (the mock's `figure.baseball.pitcher` does not exist and renders blank).
- **Legacy $4.99 buyers are grandfathered into full Pro forever**, enforced in `PurchaseManager.productGrantsPro` and guarded by `PurchaseManagerEntitlementTests`.

### What a shared team's *recipient* pays for — decided 8 Aug 2026

Pro is per-account, never per-team, and stays that way. Three decisions on top of that, all made while reworking sharing. None is derivable from the code, so they are recorded here.

- **A view-only assistant gets the Coaches Guide free.** The case it exists for: a head coach running late asks an assistant to print the guide for the dugout. Charging that assistant for a read-only copy of a lineup they cannot even edit would block a job the head coach has already paid for. Implemented as `LineupPDFExport.canExportCoachesGuide` — `isPro || (isSharedParticipant && isReadOnly)` — and the PRO badge disappears with the gate. Exports carry an `entitlement` analytics parameter (`pro` / `readonly_participant`) so the unlock's real usage is measured rather than assumed.
- **A read-write assistant is a co-coach and pays like a head coach.** They are deliberately *not* included above. Pro being per-account already delivers this: an unpaid read-write assistant gets exactly the free tier any unpaid coach gets. No extra gating was added, and none is wanted.
- **The Assistant Coaches row in Edit Team is not paywalled on a *received* team.** Pro buys the ability to *share*. That row is the only place an invited coach can learn who invited them and what they are allowed to do, and withholding an answer about access they already have behind a purchase is the wrong trade. Owned teams are gated as before.

**Consequence worth being deliberate about:** one Pro head coach can equip any number of *free* read-write assistants with full edit access to the roster and lineup. That is a monetisation choice, not an oversight — flagged 8 Aug and accepted.

**Final source → hero mapping:**

| Source | Hero |
|---|---|
| `autofill` | Auto-Fill Positions |
| `player_preferences` | Position Preferences |
| `lineup_template` | Lineup Templates |
| `pdf_export` | Coaches Guide PDF |
| `game_history` | Game History |
| `shared_teams` | Shared Teams |
| `settings`, `preview`, `team_export`, `team_import` | generic |

## Still on Design

- **Dark mode + Dynamic Type** were implemented with semantic colors and a footer that tolerates large type, but the *visual* calibration (exact dark tints, AX-size footer behavior) is worth a design pass on device.
- The build ships **8 feature rows**. Nine remains the ceiling if a feature is ever added.
