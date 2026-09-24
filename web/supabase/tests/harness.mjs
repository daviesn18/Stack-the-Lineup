// Test harness: runs the real migrations in PGlite (Postgres 17 compiled to
// WASM, in-process) behind a minimal stand-in for the parts of Supabase the
// schema relies on: the auth schema, auth.uid(), and the anon/authenticated
// roles. No Docker, no network, fresh database per test file.
//
// asUser(id, fn) runs fn as the `authenticated` role with that user's JWT
// subject, exactly how PostgREST runs a signed-in coach's request, so row-level
// security is exercised for real.

import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { randomUUID } from 'node:crypto';
import { PGlite } from '@electric-sql/pglite';

const MIGRATIONS = join(import.meta.dirname, '..', 'migrations');

const SUPABASE_STUB = `
  create role anon nologin;
  create role authenticated nologin;
  create role service_role nologin bypassrls;

  create schema auth;
  create table auth.users (
    id uuid primary key,
    email text,
    raw_user_meta_data jsonb not null default '{}'
  );
  -- Same source Supabase uses: the request's JWT subject.
  create function auth.uid() returns uuid language sql stable as $$
    select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
  $$;
  grant usage on schema auth to anon, authenticated, service_role;
  grant execute on function auth.uid() to anon, authenticated, service_role;

  -- Supabase grants these by default; the migration must revoke what it doesn't want.
  grant usage on schema public to anon, authenticated, service_role;
  alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
  alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
`;

export async function freshDb() {
  const db = new PGlite();
  await db.exec(SUPABASE_STUB);
  for (const f of readdirSync(MIGRATIONS).filter((f) => f.endsWith('.sql')).sort()) {
    await db.exec(readFileSync(join(MIGRATIONS, f), 'utf8'));
  }
  return db;
}

/** Creates an auth user (as Supabase Auth would) and returns its id. */
export async function createUser(db, email = `${randomUUID()}@example.com`) {
  const id = randomUUID();
  await db.query('insert into auth.users (id, email) values ($1, $2)', [id, email]);
  return id;
}

/** Runs fn(db) as a signed-in coach, then returns to the superuser session. */
export async function asUser(db, userId, fn) {
  await db.exec(`set role authenticated`);
  await db.query(`select set_config('request.jwt.claim.sub', $1, false)`, [userId]);
  try {
    return await fn(db);
  } finally {
    await db.exec(`reset role`);
    await db.query(`select set_config('request.jwt.claim.sub', '', false)`);
  }
}

/** Runs fn(db) as the public (signed-out) role. */
export async function asAnon(db, fn) {
  await db.exec(`set role anon`);
  try {
    return await fn(db);
  } finally {
    await db.exec(`reset role`);
  }
}

export const uuid = () => randomUUID();
