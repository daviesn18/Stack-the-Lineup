// Merge 4: Shared Teams on the account, for the web. The calls to the sharing
// functions in 20261124000000_shared_teams, and how a coach's role on a team is
// read from the fetched team. The server decides everything; this mirrors
// iOS TeamAccess.swift and LineupStore+Sharing.swift.

import { supabase } from './supabase';

/** As data/teams upperId (not imported: teams imports this file). */
const upperId = (id: string) => id.toUpperCase();

export type TeamRole = 'owner' | 'editor' | 'viewer';

export interface TeamCoach {
  userId: string;
  role: Exclude<TeamRole, 'owner'>;
  name: string;
  joinedAt: Date | null;
}

export interface TeamAccess {
  role: TeamRole;
  ownerId: string;
  ownerName: string;
  /** Everyone but the owner, oldest first. */
  coaches: TeamCoach[];
}

/** A team_members row as the nested fetch returns it. */
export interface MemberRow {
  user_id: string;
  role: string;
  name: string | null;
  joined_at: string | null;
}

export const isOwner = (a: TeamAccess) => a.role === 'owner';
export const isShared = (a: TeamAccess) => a.coaches.length > 0;
/** Team settings (name, color, rules, game length) are the owner's (decision 1). */
export const canChangeSettings = (a: TeamAccess) => a.role === 'owner';
export const canEdit = (a: TeamAccess) => a.role !== 'viewer';
export const ownerDisplayName = (a: TeamAccess) => a.ownerName.trim() || 'the head coach';
export const coachDisplayName = (c: TeamCoach) => c.name.trim() || 'Coach';

/** What the role lets a coach do, in the iOS sharing screen's words. */
export const ROLE_TEXT: Record<Exclude<TeamRole, 'owner'>, { title: string; explanation: string; participant: string }> = {
  editor: {
    title: 'Can make changes',
    explanation: 'Coaches can build lineups, edit the roster and archive games. Only you can change team settings or finalize a lineup.',
    participant: 'You can build lineups, edit the roster and archive games. The head coach finalizes lineups and changes team settings.',
  },
  viewer: {
    title: 'View only',
    explanation: 'Coaches can see the roster, lineups and game history, and print, but not change anything.',
    participant: 'You can see the roster, lineups and game history, and print. Only the head coach can make changes.',
  },
};

/**
 * This coach's access to a team, from its owner and members. Null when `me`
 * isn't on it (a stale fetch). A member row with a role this build doesn't
 * know is skipped, so a future role never locks anyone out of the list.
 */
export function resolveAccess(ownerId: string, ownerName: string, members: MemberRow[], me: string | null): TeamAccess | null {
  const coaches: TeamCoach[] = members
    .filter((m) => m.role === 'editor' || m.role === 'viewer')
    .map((m) => ({
      userId: upperId(m.user_id), role: m.role as TeamCoach['role'], name: m.name ?? '',
      joinedAt: m.joined_at ? new Date(m.joined_at) : null,
    }))
    .sort((a, b) => (a.joinedAt?.getTime() ?? 0) - (b.joinedAt?.getTime() ?? 0));
  const owner = upperId(ownerId);
  const self = me ? upperId(me) : null;
  if (!self) return null;
  if (self === owner) return { role: 'owner', ownerId: owner, ownerName, coaches };
  const mine = coaches.find((c) => c.userId === self);
  return mine ? { role: mine.role, ownerId: owner, ownerName, coaches } : null;
}

// MARK: - Invite links

export const INVITE_HOST = 'app.stackthelineup.com';
const TOKEN = /^[0-9a-f]{64}$/;

/** The link the head coach sends. Opens the app on an iPhone that has it, else this site's /join page. */
export const inviteUrl = (token: string) => `https://${INVITE_HOST}/join/${token}`;

/** The token from a /join route parameter, or null when it isn't one. */
export function inviteToken(raw: string | string[] | undefined): string | null {
  const s = (Array.isArray(raw) ? raw[0] : raw)?.trim().toLowerCase() ?? '';
  return TOKEN.test(s) ? s : null;
}

// MARK: - Server calls

export type SharingFailure = 'proRequired' | 'rateLimited' | 'notOwner' | 'offline' | 'other';

export class SharingError extends Error {
  constructor(readonly kind: SharingFailure) {
    super({
      proRequired: 'Sharing a team needs Stack the Lineup Pro.',
      rateLimited: 'Too many tries. Wait a few minutes and try again.',
      notOwner: 'Only the head coach can do that.',
      offline: "You're offline. Try again when you're connected.",
      other: 'Something went wrong. Try again in a moment.',
    }[kind]);
  }
}

interface PgError { message: string; code?: string; hint?: string | null }

/** Turns the server's refusals into what a coach can act on. */
export function failureOf(e: PgError): SharingFailure {
  if (e.hint === 'pro_required') return 'proRequired';
  if (e.hint === 'rate_limited') return 'rateLimited';
  if (e.code === '42501') return 'notOwner';
  if (/fetch|network/i.test(e.message)) return 'offline';
  return 'other';
}

async function rpc<T>(fn: string, args: Record<string, unknown>): Promise<T> {
  let res: { data: unknown; error: PgError | null };
  try {
    res = await supabase.rpc(fn, args);
  } catch {
    throw new SharingError('offline');
  }
  if (res.error) throw new SharingError(failureOf(res.error));
  return res.data as T;
}

const db = (id: string) => id.toLowerCase();

export interface LiveLink { token: string; role: Exclude<TeamRole, 'owner'> }

/** Makes the team's link, replacing any live one. */
export async function createInvite(teamId: string, role: LiveLink['role'] = 'editor'): Promise<LiveLink> {
  const token = await rpc<string>('create_team_invite', { p_team: db(teamId), p_role: role });
  return { token, role };
}

/** The live link, to send it again. Null when the team has none. */
export async function liveLink(teamId: string): Promise<LiveLink | null> {
  const rows = await rpc<{ token: string; role: LiveLink['role'] }[]>('team_invite_link', { p_team: db(teamId) });
  return rows?.[0] ? { token: rows[0].token, role: rows[0].role } : null;
}

export const setInviteRole = (teamId: string, role: LiveLink['role']) =>
  rpc<null>('set_invite_role', { p_team: db(teamId), p_role: role });

export const removeCoach = (teamId: string, userId: string) =>
  rpc<null>('remove_team_member', { p_team: db(teamId), p_user: db(userId) });

export const stopSharing = (teamId: string) => rpc<null>('stop_sharing', { p_team: db(teamId) });

export const leaveTeam = (teamId: string) => rpc<null>('leave_team', { p_team: db(teamId) });

export interface InvitePreview {
  teamId: string;
  teamName: string;
  colorHex: string;
  ownerName: string;
  role: LiveLink['role'];
  isMember: boolean;
}

/** Null for a link that's unknown, revoked, or for a deleted team. */
export async function previewInvite(token: string): Promise<InvitePreview | null> {
  const rows = await rpc<{ team_id: string; team_name: string; color_hex: string; owner_name: string; role: LiveLink['role']; is_member: boolean }[]>(
    'team_invite_preview', { p_token: token });
  const r = rows?.[0];
  return r ? {
    teamId: upperId(r.team_id), teamName: r.team_name, colorHex: r.color_hex, ownerName: r.owner_name,
    role: r.role, isMember: r.is_member,
  } : null;
}

/** Joins and returns the team id; null when the link no longer works. */
export async function acceptInvite(token: string, name: string): Promise<string | null> {
  const id = await rpc<string | null>('accept_team_invite', { p_token: token, p_name: name });
  return id ? upperId(id) : null;
}
