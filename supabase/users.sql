-- ============================================================================
-- ADMIN USERS LIST
--
-- Run this ONCE in the Supabase SQL Editor against an existing project.
-- It is idempotent: every statement is safe to re-run.
--
-- Installs public.admin_list_users(), the read-only RPC behind the dashboard's
-- Users tab.
--
-- Why a function instead of a plain SELECT:
--   * email and last_sign_in_at live in auth.users, which the publishable key
--     cannot read;
--   * `profiles` RLS stays own-row only, so an admin still cannot browse other
--     people's profile rows directly;
--   * the function is SECURITY DEFINER and refuses every signed-in caller
--     whose profiles.role is not 'admin'.
--
-- The function also aggregates orders so the Users tab can show order count,
-- delivered spend and the last order date without downloading every order a
-- second time.
--
-- Fresh installs get the same function from supabase/schema.sql. This file
-- exists only to upgrade a database that is already live.
-- ============================================================================

begin;

create or replace function public.admin_list_users()
returns table (
  id              uuid,
  username        text,
  email           text,
  role            text,
  profile_image   text,
  joined_at       timestamptz,
  last_sign_in_at timestamptz,
  order_count     bigint,
  total_spent     numeric,
  last_order_at   timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  -- The SQL editor has no JWT, so auth.uid() is null there. That is the
  -- trusted path used to verify the function; an API caller always carries a
  -- JWT and is therefore checked. This mirrors guard_profile_role().
  if auth.uid() is not null and not public.is_admin() then
    raise exception 'Only an admin can list users.'
      using errcode = '42501';
  end if;

  return query
  select
    u.id,
    coalesce(p.username, split_part(u.email, '@', 1)) as username,
    u.email,
    coalesce(p.role, 'customer') as role,
    p.profile_image,
    u.created_at as joined_at,
    u.last_sign_in_at,
    count(o.id) as order_count,
    -- Only delivered orders count as money spent; pending and cancelled
    -- orders are not revenue yet.
    coalesce(sum(o.total_amount) filter (where o.status = 'Delivered'), 0) as total_spent,
    max(o.created_at) as last_order_at
  from auth.users u
  left join public.profiles p on p.id = u.id
  left join public.orders o on o.user_id = u.id
  group by u.id, u.email, u.created_at, u.last_sign_in_at,
           p.username, p.role, p.profile_image
  order by u.created_at desc;
end;
$$;

-- Same grant shape as is_admin(): revoke the Supabase default grants from
-- every role, then allow authenticated. The in-function role check is what
-- actually decides who sees rows.
revoke all on function public.admin_list_users() from public, anon, authenticated, service_role;
grant execute on function public.admin_list_users() to authenticated;

commit;

-- PostgREST caches the function list. Without this the dashboard keeps
-- getting "Could not find the public.admin_list_users function" for a minute
-- or two even though the function now exists.
notify pgrst, 'reload schema';


-- ---------------------------------------------------------------------------
-- Verification
-- ---------------------------------------------------------------------------

-- 1. As the SQL editor (trusted, no JWT), this returns one row per signup:
--    select * from public.admin_list_users();
--
-- 2. Signed in as an admin, the dashboard Users tab loads the same rows.
--
-- 3. Signed in as a customer, the RPC fails with:
--    ERROR: Only an admin can list users.
--
-- 4. The function exists and is executable by authenticated:
--    select proname, proacl from pg_proc where proname = 'admin_list_users';
