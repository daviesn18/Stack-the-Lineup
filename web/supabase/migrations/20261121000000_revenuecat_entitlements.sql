-- Pro from RevenueCat: App Store (iOS) and Stripe (web) purchases both reach
-- public.entitlements through the revenuecat-webhook Edge Function, so a coach
-- who pays on one platform is Pro on both.
--
-- New columns (readable by the coach, like the rest of their row):
--   store            where the active Pro was bought, so each app can say
--                    "manage it on your iPhone" instead of offering checkout
--   product_id       the RevenueCat product behind the entitlement
--   management_url   RevenueCat's manage link (App Store or Stripe portal)
--   revenuecat_as_of RevenueCat's clock for the read that was written; an
--                    older read arriving late is ignored

alter table public.entitlements
  add column store text check (store in ('app_store','play_store','stripe','promotional','other')),
  add column product_id text,
  add column management_url text,
  add column revenuecat_as_of timestamptz;

-- The only writer of RevenueCat state. Returns what it did, for the logs:
--   'pro' / 'free'  the row now says that
--   'kept_manual'   a hand-granted Pro (source 'manual') stays as it is; the
--                   purchase details are still recorded alongside it
--   'stale'         an older read than the one already stored; nothing changed
--   'no_account'    no such user (deleted, or not this project's)
create function public.apply_revenuecat_entitlement(
  p_user_id uuid,
  p_is_pro boolean,
  p_expires_at timestamptz,
  p_store text,
  p_product_id text,
  p_management_url text,
  p_as_of timestamptz
) returns text
language plpgsql security definer set search_path = '' as $$
declare
  cur public.entitlements%rowtype;
begin
  select * into cur from public.entitlements where user_id = p_user_id for update;
  if not found then
    return 'no_account';
  end if;
  if cur.revenuecat_as_of is not null and p_as_of < cur.revenuecat_as_of then
    return 'stale';
  end if;

  if cur.source = 'manual' and cur.is_pro then
    update public.entitlements
       set store = p_store, product_id = p_product_id,
           management_url = p_management_url, revenuecat_as_of = p_as_of
     where user_id = p_user_id;
    return 'kept_manual';
  end if;

  update public.entitlements
     set is_pro = p_is_pro, source = 'revenuecat', expires_at = p_expires_at,
         store = p_store, product_id = p_product_id,
         management_url = p_management_url, revenuecat_as_of = p_as_of
   where user_id = p_user_id;
  return case when p_is_pro then 'pro' else 'free' end;
end $$;

-- Server only: coaches must not be able to grant themselves Pro.
revoke execute on function public.apply_revenuecat_entitlement(uuid, boolean, timestamptz, text, text, text, timestamptz)
  from public, anon, authenticated;
grant execute on function public.apply_revenuecat_entitlement(uuid, boolean, timestamptz, text, text, text, timestamptz)
  to service_role;
