-- ============================================================================
-- Stock -- standalone patch
--
-- This is section 1a plus section 2b of supabase/schema.sql, on its own.
--
-- Use it when the rest of the schema is already applied and you only
-- need stock. The full schema is still the source of truth, and it
-- contains these statements too -- running this first and the schema
-- afterwards is safe, because every statement here is idempotent.
--
-- ORDER MATTERS. Nothing in the backfill at the end works until the
-- column exists, so run the DDL first and the UPDATE last. Running
-- them in the wrong order gives:
--
--   ERROR: 42703: column "stock" of relation "public.products" does not exist
--
-- Both are safe to re-run.


-- ---------------------------------------------------------------------------
-- 1. THE COLUMN
-- ---------------------------------------------------------------------------

alter table public.products
  add column if not exists stock integer not null default 0;

alter table public.products
  drop constraint if exists products_stock_non_negative;

alter table public.products
  add constraint products_stock_non_negative check (stock >= 0);

comment on column public.products.stock is
  'Units on hand. Admin sets it; place_order() is the only thing that lowers it, and never below zero.';


-- ---------------------------------------------------------------------------
-- 2. PLACE AN ORDER AND TAKE THE STOCK
--
-- Replaces inserting straight into `orders` from the app.
--
-- The "is there enough?" test sits in the WHERE clause of the statement
-- that takes the stock, so it is one atomic step. Two customers buying
-- the last unit cannot both win: the second UPDATE blocks on the row
-- lock, then re-reads the committed value and matches nothing. A short
-- line raises, which rolls the whole function back, so a rejected order
-- never leaves stock taken for an order that does not exist.
--
-- SECURITY DEFINER is required -- customers may read products but not
-- update them. That makes the GRANT at the bottom load bearing: without
-- it anyone, signed in or not, could drain the catalog.
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
  -- SECURITY DEFINER bypasses the orders policy, so the caller check
  -- has to happen here instead.
  if auth.uid() is null then
    raise exception 'You must be signed in to place an order.'
      using errcode = '42501';
  end if;

  if p_items is null or jsonb_array_length(p_items) = 0 then
    raise exception 'Cannot place an order with no items.'
      using errcode = '22023';
  end if;

  -- Reject totals that do not add up. Prices come from the cart snapshot
  -- (so they are not re-derived from products.price here), but the sums
  -- must at least be internally consistent.
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

  -- Take the stock off first, in a fixed order (by product id) so two
  -- concurrent orders holding the same products cannot lock them in
  -- different sequences and deadlock.
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

    -- Named for the message, since the row is gone by the time the error
    -- surfaces.
    v_label := coalesce(v_entry ->> 'name', v_product_id::text);

    update public.products
       set stock = stock - v_quantity,
           updated_at = now()
     where id = v_product_id
       and stock >= v_quantity;

    if not found then
      -- Distinguish a deleted product from a short one; "some remain" is
      -- a lie when the row is simply gone.
      if not exists (select 1 from public.products where id = v_product_id) then
        raise exception 'The product "%" is no longer available.', v_label
          using errcode = 'P0001';
      end if;

      raise exception 'Not enough stock for "%" (wanted %).',
        v_label, v_quantity
        using errcode = 'P0001';
    end if;
  end loop;

  -- Then write the order.
  --
  -- customer_email is read from auth.users rather than passed in, so
  -- it cannot be forged and this function's signature never changes.
  -- See the orders table in the authoritative schema.
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
    'Completed'
  )
  returning id into v_order_id;

  return v_order_id;
end;
$$;

-- REVOKE ... FROM public does NOT remove anon's grant (Supabase's ALTER
-- DEFAULT PRIVILEGES grants EXECUTE to anon directly). Revoke from anon
-- too so the permission layer matches the intent; the in-function caller
-- check is what actually stops a signed-out visitor.
revoke all on function public.place_order(
  text, text, text, numeric, numeric, numeric, integer, jsonb, text
) from public, anon;

grant execute on function public.place_order(
  text, text, text, numeric, numeric, numeric, integer, jsonb, text
) to authenticated;


-- ---------------------------------------------------------------------------
-- 3. CHECK IT LANDED
--
-- Expect the column here. If this returns nothing, section 1 above did
-- not run, and sections 3 and 4 of this file cannot work either.
-- ---------------------------------------------------------------------------

select column_name, data_type, column_default
from information_schema.columns
where table_name = 'products' and column_name = 'stock';

-- Expect one row with the exact signature the app calls.
select p.proname, pg_get_function_arguments(p.oid) as arguments
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'place_order';


-- ---------------------------------------------------------------------------
-- 4. BACKFILL  --  RUN THIS LAST
--
-- Only valid once the column exists. Everything defaults to 0, which is
-- truthful but leaves the whole catalog reading as sold out.
--
--   update public.products set stock = 25 where stock = 0;
--
-- Left commented out on purpose: running it straight after pasting this
-- file, statement 3 above is what tells you the column is there.
-- ---------------------------------------------------------------------------