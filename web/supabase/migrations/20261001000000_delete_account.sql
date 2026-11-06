-- delete_account: a signed-in coach erases their own account and everything
-- it owns, from the Account dialog.
--
-- SECURITY DEFINER because coaches have no rights on auth.users. It can only
-- ever delete the caller: the id comes from the request's JWT, never from an
-- argument. Deleting the auth user cascades to profiles, entitlements and
-- teams, and each team cascades to its players, lineups, cells, templates,
-- schedule, game logs and pitch counts. Nothing is kept.

create function public.delete_account() returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := (select auth.uid());
begin
  if v_user is null then
    raise exception 'Not signed in' using errcode = '28000';
  end if;
  delete from auth.users where id = v_user;
end $$;

-- New functions are callable by PUBLIC (so anon) unless revoked; see
-- 20260924000200_revoke_public_execute.sql.
revoke execute on function public.delete_account() from public, anon;
grant execute on function public.delete_account() to authenticated;
