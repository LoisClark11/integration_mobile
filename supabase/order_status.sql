-- ============================================================================
-- ORDER STATUS UPGRADE
--
-- Run this ONCE in the Supabase SQL Editor against the existing project.
-- It is idempotent: every statement is safe to re-run.
--
-- Before:  status = 'Completed' | 'Cancelled'
-- After:   status = 'Pending' | 'Processing' | 'Delivered' | 'Cancelled'
--
-- Rules installed here:
--   * a new order starts 'Pending';
--   * only an admin may move an order to Processing or Delivered;
--   * either side may cancel, but only while Pending or Processing;
--   * Delivered is final except for cancellation; Cancelled is final
--     (no reopening);
--   * cancelling a Pending/Processing order puts its stock back exactly
--     once; cancelling a Delivered order does not restock anything;
--   * legacy 'Completed' rows become 'Delivered'.
--
-- Fresh installs get the same rules from supabase/schema.sql -- this file
-- exists only to upgrade a database that is already live.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. New status values
-- ---------------------------------------------------------------------------

-- Drop the guard first: the backfill below changes status, and the old
-- trigger only permits a move to 'Cancelled'.
drop trigger if exists guard_order_update on public.orders;

-- The inline CHECK from the original CREATE TABLE is named
-- orders_status_check by Postgres.
alter table public.orders
  drop constraint if exists orders_status_check;

-- 'Completed' was the old final state, so keep those orders closed.
update public.orders
   set status = 'Delivered'
 where status = 'Completed';

-- Anything unexpected must not block the new constraint. Pending is the
-- safe, admin-triageable value.
update public.orders
   set status = 'Pending'
 where status is null
    or status not in ('Pending', 'Processing', 'Delivered', 'Cancelled');

alter table public.orders
  alter column status set default 'Pending';

alter table public.orders
  add constraint orders_status_check
  check (status in ('Pending', 'Processing', 'Delivered', 'Cancelled'));


-- ---------------------------------------------------------------------------
-- 2. New orders start Pending
-- ---------------------------------------------------------------------------

create or replace function public.place_order(
  p_customer_name    text,
  p_address          text,
  p_payment_method   text,
  p_subtotal         numeric,
  p_delivery_fee     numeric,
  p_total            numeric,
  p_item_count       integer,
  p_items            jsonb,
  p_purchase_type    text
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_entry      jsonb;
  v_product_id uuid;
  v_quantity   integer;
  v_label      text;
  v_order_id   uuid;
  v_sum        numeric;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in to place an order.'
      using errcode = '42501';
  end if;

  if p_items is null or jsonb_array_length(p_items) = 0 then
    raise exception 'Cannot place an order with no items.'
      using errcode = '22023';
  end if;

  if p_subtotal is null or p_total is null or p_delivery_fee is null
     or p_subtotal < 0 or p_delivery_fee < 0 then
    raise exception 'Order totals are missing or negative.'
      using errcode = '22023';
  end if;

  if p_total <> p_subtotal + p_delivery_fee then
    raise exception 'Order total does not match subtotal plus delivery fee.'
      using errcode = '22023';
  end if;

  select coalesce(sum((item ->> 'quantity')::integer), 0) into v_sum
    from jsonb_array_elements(p_items) as item;

  if p_item_count is distinct from v_sum then
    raise exception 'Order item count does not match the items listed.'
      using errcode = '22023';
  end if;

  -- Take the stock off first, in a fixed order to avoid deadlocks.
  for v_entry in
    select item from jsonb_array_elements(p_items) as item
    order by nullif(item ->> 'productId', '')::uuid
  loop
    v_product_id := nullif(v_entry ->> 'productId', '')::uuid;
    v_quantity   := nullif(v_entry ->> 'quantity', '')::integer;

    if v_product_id is null or v_quantity is null or v_quantity <= 0 then
      raise exception 'An item on this order has no product or a bad quantity.'
        using errcode = '22023';
    end if;

    v_label := coalesce(v_entry ->> 'name', v_product_id::text);

    update public.products
       set stock = stock - v_quantity,
           updated_at = now()
     where id = v_product_id
       and stock >= v_quantity;

    if not found then
      if not exists (select 1 from public.products where id = v_product_id) then
        raise exception 'The product "%" is no longer available.', v_label
          using errcode = 'P0001';
      end if;

      raise exception 'Not enough stock for "%" (wanted %).',
        v_label, v_quantity
        using errcode = 'P0001';
    end if;
  end loop;

  insert into public.orders (
    user_id,
    customer_name,
    customer_email,
    address,
    payment_method,
    subtotal_amount,
    delivery_fee,
    total_amount,
    item_count,
    items,
    purchase_type,
    status
  )
  values (
    auth.uid(),
    p_customer_name,
    (select email from auth.users where id = auth.uid()),
    p_address,
    p_payment_method,
    p_subtotal,
    p_delivery_fee,
    p_total,
    p_item_count,
    p_items,
    p_purchase_type,
    'Pending'
  )
  returning id into v_order_id;

  return v_order_id;
end;
$$;

revoke all on function public.place_order(
  text, text, text, numeric, numeric, numeric, integer, jsonb, text
) from public, anon;

grant execute on function public.place_order(
  text, text, text, numeric, numeric, numeric, integer, jsonb, text
) to authenticated;


-- ---------------------------------------------------------------------------
-- 3. Admins may update an order
-- ---------------------------------------------------------------------------

-- The admin app already has UPDATE granted at the table level; this policy
-- is what lets an admin match a row they do not own.
drop policy if exists "admins can update all orders" on public.orders;
create policy "admins can update all orders"
  on public.orders for update
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- RLS decides WHICH rows a role may touch; the table grant decides whether
-- it may reach the table at all. Already in schema.sql section 2c; repeated
-- here so an older project that missed that section still works.
grant select, update on table public.orders to authenticated;


-- ---------------------------------------------------------------------------
-- 4. What may change on an order
-- ---------------------------------------------------------------------------

create or replace function public.guard_order_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_is_admin boolean := public.is_admin();
begin
  -- Everything except status / cancelled_at is history.
  if new.id                is distinct from old.id
     or new.user_id        is distinct from old.user_id
     or new.customer_name  is distinct from old.customer_name
     or new.customer_email is distinct from old.customer_email
     or new.address        is distinct from old.address
     or new.payment_method is distinct from old.payment_method
     or new.subtotal_amount is distinct from old.subtotal_amount
     or new.delivery_fee   is distinct from old.delivery_fee
     or new.total_amount   is distinct from old.total_amount
     or new.item_count     is distinct from old.item_count
     or new.items          is distinct from old.items
     or new.purchase_type  is distinct from old.purchase_type
     or new.created_at     is distinct from old.created_at then
    raise exception 'An order cannot be edited after it is placed. Only its status may change.'
      using errcode = '42501';
  end if;

  if new.status is distinct from old.status then
    -- Cancelled is final for everybody.
    if old.status = 'Cancelled' then
      raise exception 'A cancelled order cannot be changed.'
        using errcode = '42501';
    end if;

    if v_is_admin then
      if new.status not in ('Pending', 'Processing', 'Delivered', 'Cancelled') then
        raise exception 'Unknown order status "%".', new.status
          using errcode = '22023';
      end if;

      -- Delivered is final except for cancellation. Reopening it would let
      -- a later cancel restock units that already left the shop.
      if old.status = 'Delivered' and new.status <> 'Cancelled' then
        raise exception 'A delivered order can only be cancelled, not moved back to "%".',
          new.status using errcode = '42501';
      end if;
    else
      if new.status <> 'Cancelled' then
        raise exception 'Only an admin can set the order status to "%".', new.status
          using errcode = '42501';
      end if;

      if old.status not in ('Pending', 'Processing') then
        raise exception 'This order can no longer be cancelled.'
          using errcode = '42501';
      end if;
    end if;
  end if;

  -- Derive the timestamp instead of accepting whatever the client sent.
  if new.status = 'Cancelled' then
    new.cancelled_at := coalesce(old.cancelled_at, now());
  else
    new.cancelled_at := old.cancelled_at;
  end if;

  return new;
end;
$$;

drop trigger if exists guard_order_update on public.orders;
create trigger guard_order_update
  before update on public.orders
  for each row execute function public.guard_order_update();


-- ---------------------------------------------------------------------------
-- 5. Restock only when an unshipped order is cancelled
-- ---------------------------------------------------------------------------

create or replace function public.restock_on_cancel()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item       jsonb;
  v_product_id uuid;
  v_quantity   integer;
begin
  if new.status = 'Cancelled' and old.status in ('Pending', 'Processing') then
    for v_item in select * from jsonb_array_elements(new.items)
    loop
      v_product_id := nullif(v_item ->> 'productId', '')::uuid;
      v_quantity   := nullif(v_item ->> 'quantity', '')::integer;

      if v_product_id is not null and v_quantity is not null and v_quantity > 0 then
        update public.products
           set stock = stock + v_quantity,
               updated_at = now()
         where id = v_product_id;
      end if;
    end loop;
  end if;

  return new;
end;
$$;

drop trigger if exists restock_on_cancel on public.orders;
create trigger restock_on_cancel
  after update on public.orders
  for each row execute function public.restock_on_cancel();

commit;

-- PostgREST caches the table shape. Tell it to reload so the dashboard and
-- the app see the new default immediately.
notify pgrst, 'reload schema';


-- ---------------------------------------------------------------------------
-- Verification
-- ---------------------------------------------------------------------------

-- 1. Every row is on a valid status:
--    select status, count(*) from public.orders group by status order by status;
--
-- 2. The new default is Pending:
--    select column_default from information_schema.columns
--     where table_schema = 'public' and table_name = 'orders' and column_name = 'status';
--
-- 3. The admin update policy exists:
--    select policyname, cmd from pg_policies
--     where schemaname = 'public' and tablename = 'orders' order by policyname;
--
-- 4. The triggers exist:
--    select tgname from pg_trigger
--     where tgrelid = 'public.orders'::regclass and not tgisinternal order by tgname;
