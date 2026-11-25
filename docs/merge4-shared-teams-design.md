# Merge 4: Shared Teams on Supabase (design draft)

Decided with Nick 2026-11-23. Shared Teams drive Pro, so this aims at the rock-solid bar and the longest TestFlight in the plan (Dec 7 – Feb 5). The five decisions are listed at the end.

## What iOS does today (CloudKit)

- The owner (head coach) needs Pro to share (`ProGate(source: "shared_teams")`).
- One invite link per team, sent from the share sheet. Everyone who joins gets the **link's** permission: **Can edit** (the default) or **View only**. Changing it changes it for every coach who already joined. That's a CloudKit limit, not a product choice.
- The owner sees each coach, can remove one, or can stop sharing for everyone.
- The copy says *"Finalizing the lineup stays with you"*, but nothing enforces it: any coach who can edit sees Finalize (`finalizeLineup()` has no owner check).
- Finalizing pushes a notification to the other coaches (the Cloudflare push worker reads CloudKit device tokens).
- Received teams are tracked by the durable received-share ledger, and a lost share shows `ShareRevocationNotice`.

The Asana note says participants are read-only. They aren't today: Can edit is the default. This design keeps both roles.

## Scope

In the cutover release:
- Owner invites by link. The coach who receives it signs in (required to join) and the team appears on all their devices and on the web.
- Two roles, editor and viewer. Remove a coach, leave a team, stop sharing.
- Sharing screens on iOS and the web. A `/join` link that opens the app if it's installed, else the web.
- The owner-only "Move to my account" for a CloudKit shared team.
- Push on finalize for account teams (Merge 5, which needs the membership table from here).

Not in it: transferring ownership, more than one owner, parents or fans as a third role, live (realtime) editing.

## Database

Two tables. Everything else keeps going through the two access functions.

```sql
create table public.team_members (
  team_id    uuid not null references public.teams on delete cascade,
  user_id    uuid not null references auth.users on delete cascade,
  role       text not null check (role in ('editor','viewer')),
  name       text not null default '',          -- the coach's name when they joined; shown to the owner
  invite_id  uuid,                              -- which link they joined from
  joined_at  timestamptz not null default now(),
  primary key (team_id, user_id)
);

create table public.team_invites (
  id          uuid primary key default gen_random_uuid(),
  team_id     uuid not null references public.teams on delete cascade,
  token       text not null unique,             -- readable only through team_invite_link(), by the owner
  role        text not null check (role in ('editor','viewer')),
  created_by  uuid not null references auth.users on delete cascade,
  created_at  timestamptz not null default now(),
  revoked_at  timestamptz
);
-- At most one live link per team (matches today, and "stop sharing" is one revoke).
create unique index one_live_invite on public.team_invites (team_id) where revoked_at is null;
```

Access becomes:

```sql
can_read_team(t) = owner, or any team_members row for auth.uid()
can_edit_team(t) = (owner, or a member with role 'editor') and the team isn't deleted
```

The team row itself (name, color, fair-play and pitching rules, inning count, schedule URL) is **owner-only to change** (decision 1). The `team_update` policy already checks `owner_id = auth.uid()`, so it needs no change. On both platforms, an editor sees Team settings read-only, with "Only Sam can change team settings."

Members can read `team_members` for their own teams, so every coach sees who's on the team. All writes go through functions; the tables get no insert, update or delete grants.

### Functions (security definer, `search_path = ''`, PUBLIC execute revoked, probed as anon)

| Function | Who | What |
|---|---|---|
| `create_team_invite(team, role)` → token | owner, **with Pro** | Revokes any live link and makes a new one. |
| `team_invite_link(team)` → token, role | owner | The live link, to send it again. |
| `set_invite_role(team, role)` | owner | Changes the link's role and every member's role (today's behavior, decision 2). |
| `team_invite_preview(token)` → team name, owner's name, role | any signed-in user | So the join screen can say "Sam invited you to coach the Cubs" before joining. |
| `accept_team_invite(token)` → team_id | any signed-in user | Adds them with the link's role. Joining again is a no-op. The owner can't join their own team. |
| `remove_team_member(team, user)` | owner | |
| `leave_team(team)` | member | |
| `stop_sharing(team)` | owner | Revokes the link and removes every member. |

The token is 64 hex characters (two random UUIDs, about 244 bits), generated on the server. It's stored, not hashed, so the owner can send the same link again (today's "Share Link"); the table has no grants and only `team_invite_link(team)` returns it, to the owner. The link is `https://app.stackthelineup.com/join/<token>`. A rate limit on `accept_team_invite` (per user, per minute) keeps tokens from being guessed. 256 bits makes guessing hopeless anyway, but it's cheap.

**One role for everyone (decision 2).** CloudKit forced one link permission for everyone; Postgres doesn't, but the cutover keeps today's model: one link, and its role applies to every coach. It's the same mental model coaches have now and less UI to test. Per-coach roles can come later if coaches ask; `team_members.role` is already per row, so that's a UI change, not a migration.

## Pro

- Creating or re-creating a link needs the owner to have Pro. The check is on the server, in `create_team_invite`, reading `entitlements`, not only in the app.
- Joining never needs Pro. That's how sharing sells Pro today: the assistant coach is free.
- **The owner's Pro lapses (decision 3):** coaches keep their access, and only new or replacement links are blocked until Pro is back. This matches CloudKit today, where the share keeps working after a lapse. Cutting assistant coaches off mid-season would cost trust and wouldn't win renewals. The owner's sharing screen says why the invite button is locked.

## Finalize

**Only the owner finalizes (decision 4).** The copy already promises it; now it's enforced on both platforms. Only the owner sees Finalize, and editors see "Waiting for Sam to finalize". On the server, a trigger on `lineups` refuses setting `status = 'finalized'` (or `last_finalized_*`) from anyone but the owner. An editor's edit to a finalized lineup still reverts it to draft, as today. CloudKit teams keep today's behavior; this applies to account teams only.

## iOS

- **Pulling member teams needs almost nothing new.** The account sync's team query goes through RLS, so a joined team just appears. A viewer's pushes are refused, and the sync already turns a refused team read-only (`outcome.refusedTeamIDs`). To avoid a refused push the first time, the pull also reads the coach's role and marks viewer teams read-only up front.
- **New `AccountSharingView`** for account teams: invite link (with Can edit / View only), coaches list, remove, stop sharing, and Leave Team for a member. The CloudKit `TeamSharingView` stays for CloudKit teams. Merge 1 already hides CloudKit sharing on account teams.
- **Joining:** a universal link (`/join/<token>`) opens the app. A signed-out coach is asked to sign in first, then sees the preview and joins. This needs an `apple-app-site-association` file on app.stackthelineup.com (served by the `stack-the-lineup-web` Worker with `_headers` for `application/json`) and the Associated Domains entitlement. Without the app installed, the same link opens the web join page.
- **Removed or the team was deleted:** the next pull no longer sees the team. Reuse the Merge 1 removal path, and show the existing revocation notice instead of silently dropping it.
- **"Shared with you" and attribution:** "Shared by Sam" comes from the team's owner name. Merge 3 already names the coach who archived a game.

## Web

- Sharing panel in Team settings (the same actions as iOS).
- A `/join/:token` route: sign in or sign up, preview, join, then open the team.
- The team switcher shows joined teams with a "Shared by Sam" label. A viewer gets the read-only UI the web already has for locked states.

## Moving a CloudKit shared team (owner only)

The Merge 1 move is blocked for shared teams ("Shared teams can move once co-coaching comes to accounts"). After Merge 4:
1. The owner moves the team. It's uploaded, read back and backed up as today.
2. The app creates the new invite link with the same role the CloudKit share had and opens the share sheet: "Send your coaches the new link."
3. The CloudKit share is **stopped** at that point. Participants' devices show the existing "moved" marker, and its copy says to ask the head coach for the new link.

**The CloudKit share stops right away (decision 5).** There's one source of truth, and coaches re-join once. Two live copies of a shared team is the failure mode this whole migration exists to end.

## Push (Merge 5, for reference)

The worker sends "Sam finalized the lineup vs Tigers" to every member and the owner except the one who finalized, using Supabase device tokens and `team_members`. Without Merge 5, account-team coaches get no push. So Merge 5 is also needed before the sharing TestFlight, not after.

## Deleting an account

- Deleting a member account removes its `team_members` rows (cascade).
- Deleting an owner account deletes the team (it already cascades), and the members lose it on their next pull with the revocation notice.

## Tests

- **test:db:** every function as owner, editor, viewer, stranger and anon; RLS on every child table for each role; an editor can't update the team row; Pro check on `create_team_invite`; a revoked token can't be accepted; the finalize trigger; account deletion both ways.
- **Unit tests (iOS + web):** role → read-only mapping, the join flow states, the removal notice.
- **Staging, by hand:** two accounts on two simulators plus the web. Invite, join from a link with the app installed and not installed, edit both ways, viewer can't edit, remove, leave, stop sharing, cold launch on both, move a CloudKit shared team.
- **TestFlight:** real multi-coach teams from the start (Dec 7). That's the gate item "Shared team: invite, accept, edit both ways, remove a coach, cold launch on both devices".

## Size and order

About 6–8 days:
1. Migration + test:db (1.5 days).
2. iOS sharing screen + join flow + universal link (2.5 days).
3. Web panel + `/join` (1.5 days).
4. Moving a shared team (1 day).
5. Staging pass (1 day).

Merge 5 (the push worker) follows right after and is needed before sharing goes to TestFlight.

## Decisions (Nick, 2026-11-23)

1. Editors **can't** change team settings (name, color, rules, inning count, schedule). Only the owner can.
2. One role for every coach, set by the link, as today.
3. If the owner's Pro lapses, coaches keep access and only new links are blocked.
4. Only the owner finalizes, enforced in the apps and on the server, for account teams.
5. Moving a CloudKit shared team stops its CloudKit share right away.
