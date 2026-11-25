# Merge 5: push notifications for account teams

Status: design, 2026-11-24. Needed before the sharing TestFlight (Dec 7).

## Today

- Pushes exist for one event, `lineup_finalized`, and only for CloudKit-shared teams.
- The app that finalizes POSTs to the Cloudflare Worker `stl-push-worker` (no auth). The Worker reads `DeviceToken` records from the CloudKit public database for that team id and sends APNs to every token but the sender's.
- Account teams get nothing:
  - iOS writes no CloudKit token for them (`DeviceTokenManager.tokenTeams`).
  - Their coaches are in `team_members`, which the Worker can't see.
  - The web never sends anything.

## Proposal

**The database sends the push, not the app.** A trigger on `lineups` fires when a lineup turns `finalized`. It works out who should hear about it, gathers their device tokens, and hands them to the Worker in one call (`pg_net`, asynchronous, so the finalize never waits on it).

Why the database rather than the app:
- It covers every client at once: iOS, web, and Android later. The web has no APNs token to send from, and a finalize from the web must still reach the assistant's iPhone.
- It can't be spoofed. Today anyone who knows a team id can make the Worker push to that team. The new path only runs from a real finalize the server accepted, and decision 4's trigger already guarantees the finalizer is the head coach.
- Recipients come from `team_members`, which only the database knows.

**The Worker stays a thin APNs sender.**
- The new path is a new route, `POST /v2/send`, protected by a shared secret.
- The body carries the tokens, title, body, team id and event type.
- The Worker needs no Supabase credentials, so staging and production both use the same Worker (each with its own secret).
- The CloudKit path (`POST /`) is unchanged, for CloudKit teams and for every shipped app version.

## Database

```sql
create table public.device_tokens (
  token       text primary key,          -- APNs hex (FCM later)
  user_id     uuid not null references auth.users on delete cascade,
  platform    text not null check (platform in ('ios','android')),
  apns_env    text not null check (apns_env in ('production','sandbox')),
  app_version text not null default '',
  updated_at  timestamptz not null default now()
);
```

- **Written only through functions:**
  - `register_device_token(token, platform, apns_env, app_version)`: upserts and moves a token to the caller if another account had it (one phone, new sign-in).
  - `unregister_device_token(token)`: called on sign-out.
  - No direct grants.
- **`apns_env` per token.** Debug builds get sandbox tokens and TestFlight/App Store builds get production ones. The Worker picks the APNs host for each token, so pushes can be tested from Xcode against staging without editing the Worker (today that means flipping its host).
- **Stale tokens:** the app re-registers on every launch, which bumps `updated_at`. A daily `pg_cron` job deletes tokens not seen in 60 days. A 410 from APNs is just logged by the Worker: an uninstalled app's token stops being refreshed and ages out.
- **The trigger:** `after update of status on lineups` when the status becomes `finalized`.
  - It only runs for teams with at least one member.
  - Recipients are every member plus the owner, minus the finalizer's own user.
  - It calls the Worker URL and secret, both kept in Vault.

## iOS

- After sign-in and on every launch with an account, register the APNs token with `register_device_token`. On sign-out, unregister it.
- For account teams, stop POSTing to the Worker on finalize (the server sends it). CloudKit teams keep today's path.
- Tapping a push already opens its team (the `teamID` in the payload). Account-team pushes carry the same fields.

## Web

Nothing to build. Its finalizes trigger the push like any other. Web push notifications (browser) are out of scope.

## Events

| Event | Who hears it | Text |
|---|---|---|
| `lineup_finalized` | every coach on the team except the finalizer | "Cubs: Sam finalized the lineup vs Tigers." (as today) |
| `coach_joined` (proposed) | the head coach | "Cubs: Jo joined as an assistant coach." |

## Tests

- **test:db:**
  - The trigger picks the right recipients (owner finalizes → members; nobody else can finalize).
  - It doesn't fire for unshared teams or for a re-save of an already finalized row.
  - Token functions: register, move between accounts, unregister.
  - Anon is denied.
  - `pg_net` is stubbed in PGlite.
- **Worker:** unit tests for the v2 route (secret check, sandbox vs production host).
- **Staging by hand:** the head coach finalizes on the web, and the assistant's iPhone (debug build, sandbox token) shows the push and opens the team.

## What Nick does

- Set the Worker secret (`wrangler secret put PUSH_SECRET`) and deploy the Worker, or let Claude run `wrangler deploy` if wrangler is signed in on this Mac.
- Put the same secret and the Worker URL into Vault on staging, then production at cutover.
