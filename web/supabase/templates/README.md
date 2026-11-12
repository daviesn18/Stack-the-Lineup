# Auth email templates

The emails Supabase Auth sends, branded, with links on our own domain
(`{{ .SiteURL }}/auth/confirm?token_hash=…&type=…`, finished by the web app's
`/auth/confirm` page; see `src/data/confirmLink.ts`).

Hosted projects don't read these files. Paste each one into
**Authentication → Emails → Templates** in BOTH projects (staging
`juzecenqlehzdlobvptd`, prod `vxfuoqfjcrzfvbdgxnyo`), with these subjects:

| Template in the dashboard | File | Subject |
|---|---|---|
| Invite user | `invite.html` | You're invited to Stack the Lineup |
| Reset password | `recovery.html` | Reset your Stack the Lineup password |
| Confirm signup | `confirmation.html` | Confirm your email for Stack the Lineup |
| Change email address | `email_change.html` | Confirm your new email for Stack the Lineup |

Magic link isn't used (the apps sign in with a password, Apple or Google).

`{{ .SiteURL }}` is each project's Site URL, so the links follow it: today
both are `https://app.stackthelineup.com`. When staging's Site URL moves to
`http://localhost:8082`, staging emails link to local development.

The local CLI stack (`supabase start`) reads them through `config.toml`.
