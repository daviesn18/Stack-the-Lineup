-- Signed-out callers must not be able to run any of our functions.
--
-- Postgres grants EXECUTE on every new function to PUBLIC (which includes
-- anon). The initial migration revoked it from the functions that existed at
-- that point, and its per-schema ALTER DEFAULT PRIVILEGES could not remove the
-- PUBLIC default (a per-schema default can only add to the global one), so the
-- functions created in 20260924000100 were callable while signed out. They
-- still failed on table permissions inside, so nothing was exposed, but the
-- function itself should be the first thing to refuse.
--
-- Found on staging 2026-09-24: an anon POST /rpc/save_innings reached
-- "permission denied for table lineups" instead of "... for function".

-- Future functions created by this role: no implicit PUBLIC execute.
alter default privileges revoke execute on functions from public;

-- Existing functions: take it back from PUBLIC and anon.
revoke execute on all functions in schema public from public, anon;

-- Re-state what signed-in coaches may call (explicit grants were not affected,
-- but this keeps the full list in one place).
grant execute on function
  public.can_read_team(uuid),
  public.can_edit_team(uuid),
  public.require_editable_lineup(uuid),
  public.revert_to_draft(uuid),
  public.save_innings(uuid, jsonb),
  public.archive_game(uuid, int, text, jsonb, uuid),
  public.replace_pitch_counts(uuid, jsonb),
  public.import_team(jsonb, boolean)
  to authenticated;
