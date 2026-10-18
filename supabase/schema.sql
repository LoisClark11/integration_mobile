-- ============================================================================
-- TouchSkin (skincare e-commerce) - Supabase schema
--
-- Run this once in the Supabase SQL Editor:
--   Dashboard -> SQL Editor -> New query -> paste -> Run
--
-- It is safe to re-run: every statement is idempotent.
-- ============================================================================


-- ============================================================================
-- 1. TABLES
-- ============================================================================

-- Products sold in the storefront.
-- The admin side inserts and updates rows here.
create table if not exists public.products (
  id           uuid primary key default gen_random_uuid(),
  name         text        not null,
  price        numeric(12, 2) not null default 0 check (price >= 0),
  description  text,
  -- Public URL of the image in the "product-images" storage bucket.
  image_url    text,
  -- Units the admin has declared, and units still on hand. The app
  -- shows this and the Order Now path takes from it; see place_order()
  -- in section 3.
  stock        integer     not null default 0 check (stock >= 0),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

-- Storefront filter category. The six values are the store's whole
-- taxonomy; NULL means unassigned, and such a product only shows up
-- under the storefront's "All Products" chip. The same list lives in
-- lib/product_categories.dart and the admin dashboard's CATEGORIES --
-- keep all three in step.
alter table public.products
  add column if not exists category text
  constraint products_category_check
  check (
    category is null
    or category in (
      'Cleansers', 'Moisturizers', 'Sunscreens',
      'Serums & Treatments', 'Toners', 'Masks & Exfoliators'
    )
  );

comment on column public.products.image_url is
  'Public URL from Supabase Storage, e.g. https://<project>.supabase.co/storage/v1/object/public/product-images/laptop.png';

comment on column public.products.stock is
  'Units on hand. Admin sets it; place_order() is the only thing that lowers it, and never below zero.';


-- ---------------------------------------------------------------------------
-- 1a. STOCK ON AN ALREADY-CREATED TABLE
--
-- A products table from an earlier run has no stock column. The ALTER
-- below covers that. It defaults to 0, which is truthful -- "nothing
-- has been declared" -- but it also means every existing product reads
-- as out of stock until the admin sets a number.
--
-- Nothing decrements a stock of 0, so leaving it at 0 is safe: those
-- products simply cannot be ordered.
--
-- The UPDATE below needs the column to already exist. Run the ALTERs
-- first and only then the backfill, or it fails with:
--
--   ERROR: 42703: column "stock" of relation "public.products" does not exist
--
-- `supabase/stock.sql` has this section on its own, with a verification
-- query between the DDL and the backfill.
-- ---------------------------------------------------------------------------

alter table public.products
  add column if not exists stock integer not null default 0;

alter table public.products
  drop constraint if exists products_stock_non_negative;

alter table public.products
  add constraint products_stock_non_negative check (stock >= 0);


-- ---------------------------------------------------------------------------
-- 1a-2. updated_at ON EVERY PRODUCT EDIT
--
-- products.updated_at was written only by place_order() and
-- restock_on_cancel(), i.e. only when stock changed. Renaming or
-- repricing from the dashboard left it stale, so the column really
-- meant "last stock movement" despite its name (and despite what
-- ADMIN_INTEGRATION.md §"Update" claims clients do). This trigger
-- stamps every UPDATE, so the column means what it says no matter
-- which writer touched the row -- dashboard, app or SQL editor.
--
-- The explicit `updated_at = now()` inside place_order() and
-- restock_on_cancel() becomes redundant but harmless: it is the same
-- value this trigger writes. Safe to re-run.
-- ---------------------------------------------------------------------------

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists products_set_updated_at on public.products;
create trigger products_set_updated_at
  before update on public.products
  for each row
  execute function public.set_updated_at();


-- Per-user profile data.
-- `id` matches auth.users.id so Supabase Auth owns the login.
create table if not exists public.profiles (
  id             uuid primary key references auth.users (id) on delete cascade,
  username       text unique not null,
  -- Public URL of the profile picture in the "avatars" storage bucket.
  profile_image  text,
  created_at     timestamptz not null default now()
);


-- Cart lines. One row per product per user, quantity held on the row.
-- The unique constraint is what stops duplicate rows appearing.
create table if not exists public.cart_items (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users (id) on delete cascade,
  product_id  uuid not null references public.products (id) on delete cascade,
  quantity    integer not null default 1 check (quantity > 0),
  created_at  timestamptz not null default now(),

  unique (user_id, product_id)
);

create index if not exists cart_items_user_id_idx
  on public.cart_items (user_id);

-- The cart reads a product snapshot alongside each line so the cart can
-- show the current name and price. Supabase can only embed this related
-- row automatically when it knows the relationship, which is what the
-- foreign key above declares.


-- ============================================================================
-- 1b. PRICE SNAPSHOT ON CART LINES
--
-- A cart line keeps its own copy of the name and price. If the admin
-- later renames or reprices a product, carts already in progress keep
-- charging what the customer was originally shown.
-- ============================================================================

alter table public.cart_items
  add column if not exists name text;
alter table public.cart_items
  add column if not exists price numeric(12, 2);
alter table public.cart_items
  add column if not exists image_url text;


-- Completed and cancelled orders.
create table if not exists public.orders (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references auth.users (id) on delete cascade,

  customer_name    text          not null,
  address          text          not null,
  payment_method   text          not null,

  -- The buyer's address, written by place_order() from their own auth
  -- session rather than sent by the app, so it cannot be spoofed.
  --
  -- Snapshotted instead of joined so the dashboard can say who placed
  -- an order without needing to read `profiles` -- the profiles policy
  -- only lets a user see their own row, so an admin joining to it would
  -- get nothing back. It also survives the account later changing its
  -- email or being deleted.
  customer_email   text,

  subtotal_amount  numeric(12, 2) not null default 0,
  delivery_fee     numeric(12, 2) not null default 50,
  total_amount     numeric(12, 2) not null default 0,
  item_count       integer       not null default 0,

  -- Snapshot of what was bought, so history stays correct even if a
  -- product is later renamed, repriced, or deleted.
  items            jsonb         not null default '[]'::jsonb,

  -- 'Completed' | 'Cancelled'
  status           text          not null default 'Completed'
                     check (status in ('Completed', 'Cancelled')),

  -- 'Cart' | 'Buy Now'
  purchase_type    text,

  created_at       timestamptz   not null default now(),
  cancelled_at     timestamptz
);

create index if not exists orders_user_id_idx
  on public.orders (user_id);

create index if not exists orders_status_idx
  on public.orders (status);

-- The dashboard lists newest first and filters on status, so it needs
-- its own path. The customer's own list already sorts on created_at.
create index if not exists orders_created_at_idx
  on public.orders (created_at desc);

-- Columns added after the first release. `create table if not exists`
-- above is a no-op on a database that already has the table, so without
-- these guards an older database keeps missing them: cancelOrder() fails
-- with PGRST204 ("column cancelled_at not found in the schema cache")
-- and place_order() fails with 42703. Safe to re-run.
alter table public.orders
  add column if not exists customer_email text;
alter table public.orders
  add column if not exists purchase_type text;
alter table public.orders
  add column if not exists cancelled_at timestamptz;


-- ---------------------------------------------------------------------------
-- 1b. CUSTOMER EMAIL ON ORDERS PLACED BEFORE THE COLUMN EXISTED
--
-- Orders written before customer_email existed have it null, which makes
-- them show up in the dashboard with no account attached. Run this once
-- in the SQL editor to attach them:
--
--   update public.orders o
--   set customer_email = u.email
--   from auth.users u
--   where u.id = o.user_id and o.customer_email is null;
--
-- Not run automatically on purpose: it reaches into auth.users, which
-- is a schema this project does not own.
-- ---------------------------------------------------------------------------


-- ============================================================================
-- 1c. REPLICA IDENTITY  (required for live delete events)
--
-- The Flutter app subscribes with a `user_id` filter, which Supabase
-- pushes down to the realtime server. For a DELETE, Postgres only puts
-- the primary key into `old_record` -- the rest of the row is already
-- gone. The server then cannot evaluate `user_id = <id>` against that
-- payload, so it silently drops the event.
--
-- The symptom is confusing: inserts and updates arrive fine (their
-- payload is the full new row), but removing a cart line or deleting
-- an order leaves the row on screen even though it was really deleted.
--
-- Sending the whole old row fixes it. This is safe at this scale; it
-- only makes Postgres write a slightly larger replication record.
-- ============================================================================

alter table public.cart_items replica identity full;
alter table public.orders    replica identity full;


-- ============================================================================
-- 1d. FEATURED SLIDES
--
-- The banners that slide across the top of the products page.
--
-- Each slide carries two uploaded pictures:
--   banner_url     the wide "featured picture" that fills the slide
--   item_image_url the "item itself" shot shown on top of the banner
--
-- Both live in the existing public "product-images" bucket under the
-- `featured/` prefix. The bucket and its read/write policies are created
-- in section 2d below -- a public bucket grants READ but not WRITE, so
-- the storage policies there are what actually allow the admin to upload
-- a banner. See ADMIN_INTEGRATION.md section 6d.
--
-- A slide is independent of the catalog so the admin owns the wording
-- and the order of the carousel without editing product rows.
-- `product_id` is optional: set it and tapping the slide opens that
-- product, and any item_* column left blank falls back to the linked
-- product's own name, price and image.
-- ============================================================================

create table if not exists public.featured_slides (
  id             uuid primary key default gen_random_uuid(),

  -- Copy drawn over the banner.
  title          text,
  subtitle       text,
  button_label   text        not null default 'Order Now',

  -- The one picture a slide uploads: the wide featured picture that
-- fills the slide from left to right. The item it advertises is a real
-- product with its own photo, so there is no second upload.
  banner_url     text,

  -- Legacy. The admin form no longer offers these, so nothing writes
  -- them any more. They are read rather than dropped so that slides
  -- saved before the boxes were removed keep whatever they stored.
  item_image_url text,
  item_name      text,
  item_price     numeric(12, 2) check (item_price >= 0),

  -- Legacy blurb the dashboard used to collect. Stored but never drawn.
  description    text,

  -- The product this banner advertises.
  --
  -- Required, not optional. A slide exists to send a customer to a
  -- product, and the Order Now button is the only way out of it, so a
  -- row with no product behind it renders a dead end: the banner
  -- slides, the copy reads, and there is no button and nowhere to go.
  -- Requiring it makes that state impossible to save.
  --
  -- ON DELETE CASCADE because the slide belongs to the product. Delete
  -- the slide to take a product *out* of the carousel while keeping the
  -- product; delete the product and its banner goes with it.
  product_id     uuid not null references public.products (id) on delete cascade,

  -- Position in the carousel, lowest first.
  display_order  integer      not null default 0,

  -- Inactive slides stay in the table but the app never shows them.
  is_active      boolean      not null default true,

  created_at     timestamptz  not null default now(),
  updated_at     timestamptz  not null default now()
);

comment on column public.featured_slides.banner_url is
  'Public URL of the wide featured picture in the product-images bucket, e.g. https://<project>.supabase.co/storage/v1/object/public/product-images/featured/banner/1.png';

comment on column public.featured_slides.item_image_url is
  'Public URL of the item picture in the product-images bucket under featured/item/.';

create index if not exists featured_slides_order_idx
  on public.featured_slides (is_active, display_order);

-- Same reason as section 1c. The app subscribes with an `is_active`
-- filter, and Postgres only puts the primary key in `old_record` for a
-- DELETE, so deactivating or deleting a slide without this line leaves
-- it on screen until the app is restarted.
alter table public.featured_slides replica identity full;

-- The admin dashboard writes every column on this table, so a column
-- added there but not here fails every slide save with:
--   Could not find the 'description' column of 'featured_slides' in the
--   schema cache
-- This covers a table created by an earlier run of this file.
alter table public.featured_slides
  add column if not exists description text;

-- PostgREST caches the table shape, so a column that was just added is
-- rejected until it is told to reload. Without this the same "could not
-- find the column" error persists for a minute or two even after the
-- column really exists. Safe to re-run.
notify pgrst, 'reload schema';


-- ---------------------------------------------------------------------------
-- 1d-2. MOVE TO "EVERY SLIDE HAS A PRODUCT"
--
-- A slide is created by taking an existing product and turning it into
-- a banner, so product_id is now required. Two steps, and the first one
-- has to be done by hand on purpose.
--
-- STEP 1 -- look at what is about to be discarded:
--
--   select id, title, banner_url from public.featured_slides
--   where product_id is null;
--
-- Prefer fixing those rows over deleting them. Linking one to a product
-- keeps the two pictures already uploaded:
--
--   update public.featured_slides
--   set product_id = '<paste a products.id here>'
--   where id = '<paste the slide id here>';
--
-- Or remove them, which leaves the products untouched and simply takes
-- them out of the carousel:
--
--   delete from public.featured_slides where product_id is null;
--
-- STEP 2 -- once that returns zero rows, enforce the rule:
--
--   alter table public.featured_slides
--     alter column product_id set not null;
--
--   alter table public.featured_slides
--     drop constraint if exists featured_slides_product_id_fkey;
--
--   alter table public.featured_slides
--     add constraint featured_slides_product_id_fkey
--     foreign key (product_id)
--     references public.products (id) on delete cascade;
--
-- Not run automatically on purpose. `set not null` fails outright if a
-- standalone row is still there, and silently deleting somebody's
-- uploaded banner to get past it is not something a schema file should
-- decide for you. Both statements are safe to re-run on their own.


-- ============================================================================
-- 1e. ADMIN ROLE
--
-- The storefront app is receive only for the catalog and for the banner
-- slides: it reads `products` and `featured_slides`, and writes only to
-- its own cart, orders and profile. The admin app is the only thing
-- that creates or edits catalog and slide rows.
--
-- That split is enforced here rather than by convention, because the
-- publishable key ships inside the customer app and is designed to be
-- public. Row level security is the only thing standing between that
-- key and your data, so "the code never calls insert" is not enough on
-- its own.
--
-- After running this schema, mark at least one account as an admin or
-- the admin app will be refused every write:
--
--   update public.profiles set role = 'admin' where username = 'yourname';
--
-- Section 5 has the promotion query. Section 6 explains how to undo this
-- if you need the old permissive behaviour back.
-- ============================================================================

alter table public.profiles
  add column if not exists role text
    not null default 'customer';

comment on column public.profiles.role is
  'customer | admin. Only admins may write to products and featured_slides.';

-- Returns true when the caller is an admin.
--
-- SECURITY DEFINER matters here. `profiles` has a row level policy that
-- lets a user read only their own row, and a plain function would be
-- subject to that policy. Running it as the table owner steps around
-- it, so the check always sees the caller's real role.
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin'
  );
$$;

-- EXECUTE is granted to `authenticated` only. Every policy that calls
-- is_admin() is `to authenticated`, so anon has no use for it.
--
-- A revoke from public alone does NOT remove Supabase's default
-- grants: ALTER DEFAULT PRIVILEGES grants EXECUTE to anon,
-- authenticated and service_role directly, not via PUBLIC. Naming all
-- four roles and then granting to authenticated makes the end state
-- identical on a fresh database and on one where the old grants
-- linger (and makes re-runs converge).
revoke all on function public.is_admin() from public, anon, authenticated, service_role;
grant execute on function public.is_admin() to authenticated;


-- ============================================================================
-- 2. ROW LEVEL SECURITY
--
-- The storefront app is receive only for catalog content:
--   - anyone may read products and featured slides, signed in or not
--   - only admins may create, edit or remove them
--   - users may only touch their own cart, orders and profile
-- ============================================================================

alter table public.products    enable row level security;
alter table public.profiles    enable row level security;
alter table public.cart_items  enable row level security;
alter table public.orders      enable row level security;

alter table public.featured_slides enable row level security;


-- ---------------------------------------------------------------------------
-- 2-0. WIPE EVERY EXISTING POLICY ON THE FIVE TABLES
--
-- Permissive policies are OR'd together, so ONE leftover permissive
-- policy defeats every restrictive one created below. This database
-- already carried live examples: the Supabase linter found the six
-- "signed in users can ..." policies from section 6 still attached to
-- products and featured_slides, all with USING / WITH CHECK (true).
-- The result was that ANY signed-in account -- every storefront
-- customer -- could rewrite the catalog, no matter what section 2
-- says. Re-running this file never cleaned them up because it only
-- dropped policies it knew by name.
--
-- So drop everything that exists on these five tables, then recreate
-- only the approved set below. Idempotent: on a clean database the
-- loop finds nothing and does nothing.
--
-- storage.objects is deliberately NOT wiped here -- a blanket wipe
-- would destroy policies for unrelated buckets. Section 2d drops the
-- known legacy storage policies by name instead.
-- ---------------------------------------------------------------------------
do $$
declare
  v_table  text;
  v_policy text;
begin
  foreach v_table in array array[
    'products', 'featured_slides', 'profiles', 'cart_items', 'orders'
  ]
  loop
    for v_policy in
      select policyname
        from pg_policies
       where schemaname = 'public' and tablename = v_table
    loop
      execute format('drop policy %I on public.%I', v_policy, v_table);
    end loop;
  end loop;
end $$;


-- ---------- products ----------
--
-- Reads stay open to everyone, signed in or not. Customers browse the
-- catalog before they have an account, and the storefront app holds
-- only the publishable key.
--
-- Writes are admin only. Without this the publishable key that ships
-- inside the customer app would let any signed-in user rewrite the
-- catalog, which is not what the storefront is for.

drop policy if exists "products are readable by everyone" on public.products;
create policy "products are readable by everyone"
  on public.products for select
  using (true);

drop policy if exists "admins can insert products" on public.products;
create policy "admins can insert products"
  on public.products for insert
  to authenticated
  with check (public.is_admin());

drop policy if exists "admins can update products" on public.products;
create policy "admins can update products"
  on public.products for update
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

drop policy if exists "admins can delete products" on public.products;
create policy "admins can delete products"
  on public.products for delete
  to authenticated
  using (public.is_admin());


-- ---------- featured_slides ----------
--
-- The same split as the four product policies above: open to read,
-- admin only to write.
--
-- The read policy is `using (true)` rather than `using (is_active)`
-- because the admin app lists drafts too, and it reads this table with
-- the same role. Hiding inactive slides is the app's job: the
-- storefront query filters on `is_active` itself, which PostgREST
-- applies before any row is sent over the wire, so a draft never
-- reaches a customer's device.

drop policy if exists "featured slides are readable by everyone" on public.featured_slides;
create policy "featured slides are readable by everyone"
  on public.featured_slides for select
  using (true);

drop policy if exists "admins can insert featured slides" on public.featured_slides;
create policy "admins can insert featured slides"
  on public.featured_slides for insert
  to authenticated
  with check (public.is_admin());

drop policy if exists "admins can update featured slides" on public.featured_slides;
create policy "admins can update featured slides"
  on public.featured_slides for update
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

drop policy if exists "admins can delete featured slides" on public.featured_slides;
create policy "admins can delete featured slides"
  on public.featured_slides for delete
  to authenticated
  using (public.is_admin());


-- ---------- profiles ----------

drop policy if exists "users can read own profile" on public.profiles;
create policy "users can read own profile"
  on public.profiles for select
  to authenticated
  using (auth.uid() = id);

drop policy if exists "users can insert own profile" on public.profiles;
create policy "users can insert own profile"
  on public.profiles for insert
  to authenticated
  -- A user may only create their own row, and only as a customer.
  -- Allowing role to be set here would let a signup mint itself admin.
  with check (auth.uid() = id and (role = 'customer' or public.is_admin()));

drop policy if exists "users can update own profile" on public.profiles;
create policy "users can update own profile"
  on public.profiles for update
  to authenticated
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- RLS above lets a user write their own row, and PostgREST exposes every
-- column, so without this a signed-in customer could run
--   update profiles set role = 'admin' where id = auth.uid()
-- and gain catalog write access plus SELECT on every order. This trigger
-- makes `role` immutable to anyone who is not already an admin.
--
-- It runs on UPDATE only. The signup path is covered by the insert
-- policy's `role = 'customer'` check above, and handle_new_user() runs
-- as the table owner so it is not subject to RLS or to this guard.
create or replace function public.guard_profile_role()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Only enforce for a real signed-in caller. The SQL editor and the
  -- service role carry no JWT (auth.uid() is null); those are the
  -- trusted paths used to promote an admin (section 5), so they pass
  -- through. An API request always has auth.uid() set, and that is the
  -- escalation this guard exists to stop.
  if auth.uid() is not null
     and new.role is distinct from old.role
     and not public.is_admin() then
    raise exception 'Only an admin can change the account role.'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

drop trigger if exists guard_profile_role on public.profiles;
create trigger guard_profile_role
  before update on public.profiles
  for each row execute function public.guard_profile_role();


-- ---------- cart_items ----------

drop policy if exists "users can read own cart" on public.cart_items;
create policy "users can read own cart"
  on public.cart_items for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists "users can insert own cart items" on public.cart_items;
create policy "users can insert own cart items"
  on public.cart_items for insert
  to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "users can update own cart items" on public.cart_items;
create policy "users can update own cart items"
  on public.cart_items for update
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists "users can delete own cart items" on public.cart_items;
create policy "users can delete own cart items"
  on public.cart_items for delete
  to authenticated
  using (auth.uid() = user_id);


-- ---------- orders ----------
--
-- Postgres ORs permissive policies together rather than replacing them,
-- so this second SELECT policy is purely additive. A customer still
-- matches only "users can read own orders"; an admin matches this one
-- and therefore sees every order. Adding it does not widen anybody
-- else's access.
--
-- Reuses is_admin() on purpose, which also means anyone who can edit
-- the catalog can read every customer's name and address. That is the
-- trade for not having to manage a second role. See ADMIN_INTEGRATION.md
-- section 6a.
--
-- SELECT only. Admins can read the order log but cannot edit it, so a
-- mistake in the dashboard cannot rewrite someone's history.

drop policy if exists "users can read own orders" on public.orders;
create policy "users can read own orders"
  on public.orders for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists "admins can read all orders" on public.orders;
create policy "admins can read all orders"
  on public.orders for select
  to authenticated
  using (public.is_admin());

drop policy if exists "users can create own orders" on public.orders;
-- Intentionally NOT recreated. Orders are written only by place_order(),
-- which runs SECURITY DEFINER and is not subject to this policy. The old
-- direct INSERT policy here let a client insert an order row straight
-- into the table, bypassing place_order() entirely -- which meant an
-- order could be recorded without any stock being taken. Removing it
-- restores the invariant that place_order() is the only writer.

drop policy if exists "users can cancel own orders" on public.orders;
create policy "users can cancel own orders"
  on public.orders for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- The UPDATE policy above pins the row to its owner but still lets the
-- owner rewrite any column on it -- total_amount, items, customer_email,
-- even status back to 'Completed'. This trigger narrows that down to
-- what the app actually does: a customer may move their own order to
-- 'Cancelled' and stamp cancelled_at, and change nothing else.
--
-- SECURITY DEFINER so the guard can read the stored row's full contents
-- regardless of the caller's row-level read access.
create or replace function public.guard_order_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status is distinct from old.status
     or new.cancelled_at is distinct from old.cancelled_at then
    if new.status <> 'Cancelled' then
      raise exception 'An order can only be cancelled, not set to "%" or edited.',
        new.status using errcode = '42501';
    end if;

    -- Once cancelled, an order is frozen.
    if old.status = 'Cancelled' then
      return old;
    end if;
  end if;

  -- Everything else on the row is history and must not be rewritten.
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
    raise exception 'An order cannot be edited after it is placed. Only its status may change to Cancelled.'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

drop trigger if exists guard_order_update on public.orders;
create trigger guard_order_update
  before update on public.orders
  for each row execute function public.guard_order_update();

-- Cancelling an order used to retire its stock forever: place_order()
-- took the units, but nothing ever gave them back, so a cancelled order
-- permanently shrank inventory. This puts them back exactly once, on the
-- transition into 'Cancelled'.
--
-- `old.status <> 'Cancelled'` is what makes it once-only: re-saving an
-- already-cancelled order does not restock a second time. SECURITY
-- DEFINER because the customer cancelling cannot UPDATE products under
-- their own policies.
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
  if new.status = 'Cancelled' and old.status <> 'Cancelled' then
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

drop policy if exists "users can delete own orders" on public.orders;
create policy "users can delete own orders"
  on public.orders for delete
  to authenticated
  using (auth.uid() = user_id);


-- ============================================================================
-- 2b. PLACE AN ORDER AND TAKE THE STOCK
--
-- This replaces inserting straight into `orders` from the app. It is the
-- only function that lowers `products.stock`, so stock can never drift
-- away from the orders that caused it.
--
-- WHY NOT DO IT IN THE APP
--
-- The obvious version reads the stock, works out the new number and
-- writes it back. Two customers buying the last unit at the same moment
-- both read 1, both write 0, and both succeed: the shop sells something
-- it does not have.
--
-- Doing the same UPDATE twice here does not have that problem. The
-- "is there enough?" test lives in the WHERE clause of the very
-- statement that takes the stock, so Postgres takes a row lock, and the
-- second transaction re-reads the committed value before deciding it
-- matches nothing. Exactly one of them wins, and the other is told why.
--
-- If any line runs short, the exception rolls the whole function back,
-- so a failed order never leaves stock taken for an order that does not
-- exist.
--
-- SECURITY DEFINER is required: customers may read products but not
-- update them, so without it this function would be refused for every
-- ordinary shopper. That also means the GRANT at the bottom matters --
-- without it anyone, signed in or not, could drain the catalog.
-- ============================================================================

create or replace function public.place_order(
  p_customer_name    text,
  p_address          text,
  p_payment_method   text,
  -- Plain `numeric`, not `numeric(12,2)`. The GRANT and REVOKE at the
  -- bottom of this function have to name this signature exactly, and
  -- there is no reason to depend on Postgres stripping a typmod before
  -- matching it. The insert below casts into the real column.
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

  -- The client sends the totals it showed the customer, but the server
  -- does not trust them: total must equal subtotal plus the delivery
  -- fee, and item_count must match the items actually listed. A tampered
  -- request that understates the total is rejected here rather than
  -- recorded as a real order.
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

  -- 1. Take the stock off first.
  --
  -- Iterating in a fixed order (by product id) matters: two concurrent
  -- orders holding the same products in different array orders would
  -- otherwise lock them in different sequences and deadlock. Postgres
  -- would kill one with 40P01, which the app would surface as a raw
  -- error instead of the friendly stock message.
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

    -- Named for the message, since the row is gone by the time the
    -- error surfaces.
    v_label := coalesce(v_entry ->> 'name', v_product_id::text);

    update public.products
       set stock = stock - v_quantity,
           updated_at = now()
     where id = v_product_id
       and stock >= v_quantity;

    if not found then
      -- Two very different causes reach here: the product row is gone
      -- (deleted mid-checkout) or there simply is not enough of it left.
      -- Saying "some remain" for a missing product is a lie, so name
      -- which one happened.
      if not exists (select 1 from public.products where id = v_product_id) then
        raise exception 'The product "%" is no longer available.', v_label
          using errcode = 'P0001';
      end if;

      raise exception 'Not enough stock for "%" (wanted %).',
        v_label, v_quantity
        using errcode = 'P0001';
    end if;
  end loop;

  -- 2. Then write the order. Any failure above has already unwound
  --    this far, so stock and orders can never disagree.
  --
  -- customer_email is read from auth.users rather than passed in.
  -- SECURITY DEFINER lets this function see that table, and taking the
  -- address from the caller's own session means it cannot be forged.
  -- It also leaves the signature alone, so there is no second overload
  -- to clean up and no app change to make.
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

-- REVOKE ... FROM public does NOT remove anon's grant. Supabase's
-- ALTER DEFAULT PRIVILEGES grants EXECUTE to anon, authenticated and
-- service_role directly (not via PUBLIC), so a signed-out visitor keeps
-- a working EXECUTE even after the PUBLIC grant is revoked. The caller
-- check inside the function is what actually stops abuse, but revoke
-- from anon too so the permission layer agrees with the intent.
revoke all on function public.place_order(
  text, text, text, numeric, numeric, numeric, integer, jsonb, text
) from public, anon;

grant execute on function public.place_order(
  text, text, text, numeric, numeric, numeric, integer, jsonb, text
) to authenticated;


-- ============================================================================
-- 2c. EXPLICIT TABLE GRANTS
--
-- The policies above decide WHICH rows each role may touch. Grants decide
-- whether the role may reach the table at all -- PostgREST checks the
-- table privilege first, and only then applies RLS. Without an explicit
-- grant here the schema leans entirely on Supabase's legacy default
-- privileges, which newer projects no longer install, and every query
-- would fail with "permission denied for table ..." before RLS even ran.
--
-- These are the minimum each client needs. The admin app's writes to
-- products and featured_slides are still gated by the is_admin() policies
-- in section 2; a grant only opens the door, RLS still decides the rows.
-- ============================================================================

grant select on table public.products         to anon, authenticated;
grant select on table public.featured_slides  to anon, authenticated;

grant select, insert, update, delete on table public.cart_items to authenticated;

-- No INSERT here on purpose: orders are written only by place_order(),
-- which runs SECURITY DEFINER. Granting INSERT would reopen the direct
-- path that bypasses stock.
grant select, update, delete on table public.orders to authenticated;

-- No DELETE here on purpose: a profile row is owned by the account and
-- removed with it via the auth.users cascade, not by the client.
grant select, insert, update on table public.profiles to authenticated;


-- ============================================================================
-- 2d. STORAGE  (product images, featured banners, profile pictures)
--
-- Two public buckets, created here so a fresh project has them:
--
--   product-images  admin-written catalog art and featured banners
--   avatars         customer-written profile pictures
--
-- A public bucket grants READ to anyone who can reach the URL, but it
-- says nothing about WRITE. Uploads insert rows into storage.objects, so
-- without the policies below every upload is rejected with 42501 even
-- while signed in. (This is the same trap as Firebase Storage.)
--
-- Ownership is checked, so the two write paths are separated:
--   product-images  only an admin may write
--   avatars         a customer may write only under their own id
--
-- On current Supabase projects storage.objects.bucket_id is text, so a
-- direct `bucket_id = 'product-images'` comparison works. The bucket rows
-- are inserted first so the ids are known to be these exact strings.
-- ============================================================================

insert into storage.buckets (id, name, public)
values
  ('product-images', 'product-images', true),
  ('avatars', 'avatars', true)
on conflict (id) do update set public = excluded.public;

-- The four BROAD policies earlier instructions had admins paste by
-- hand. "authenticated upload/update/delete" let any signed-in
-- account write to either bucket with no owner check, so a customer
-- could replace product photos. They are not always-true, which is
-- why the linter never flagged them, but they are OR'd with the
-- policies below and must go. No-ops when they were never applied.
drop policy if exists "public read"           on storage.objects;
drop policy if exists "authenticated upload"  on storage.objects;
drop policy if exists "authenticated update"  on storage.objects;
drop policy if exists "authenticated delete"  on storage.objects;

-- Anyone, signed in or not, may read the two public buckets. The app
-- renders product photos and avatars before login, so this stays open.
drop policy if exists "public read of catalog images" on storage.objects;
create policy "public read of catalog images"
  on storage.objects for select
  using (bucket_id in ('product-images', 'avatars'));

-- Only an admin may write catalog art and featured banners. A customer
-- with the publishable key must not be able to replace product photos.
drop policy if exists "admins write product images" on storage.objects;
create policy "admins write product images"
  on storage.objects for insert
  to authenticated
  with check (bucket_id = 'product-images' and public.is_admin());

drop policy if exists "admins update product images" on storage.objects;
create policy "admins update product images"
  on storage.objects for update
  to authenticated
  using (bucket_id = 'product-images' and public.is_admin());

drop policy if exists "admins delete product images" on storage.objects;
create policy "admins delete product images"
  on storage.objects for delete
  to authenticated
  using (bucket_id = 'product-images' and public.is_admin());

-- Avatars are stored in the `avatars` bucket at the path
-- `avatars/<user_id>.<ext>` (see lib/user_profile_screen.dart). So the
-- object's filename is "<user_id>.<ext>", and ownership is checked
-- against that filename, not the folder. These three policies let a
-- customer manage their own picture and nobody else's -- the filename
-- check is what stops one signed-in user overwriting another's avatar.
drop policy if exists "users upload own avatar" on storage.objects;
create policy "users upload own avatar"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = 'avatars'
    and storage.filename(name) like (auth.uid()::text || '.%')
  );

drop policy if exists "users update own avatar" on storage.objects;
create policy "users update own avatar"
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = 'avatars'
    and storage.filename(name) like (auth.uid()::text || '.%')
  );

drop policy if exists "users delete own avatar" on storage.objects;
create policy "users delete own avatar"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = 'avatars'
    and storage.filename(name) like (auth.uid()::text || '.%')
  );


-- ============================================================================
-- 2e. FUNCTION EXECUTE, NARROWED TO WHAT CLIENTS ACTUALLY CALL
--
-- The Supabase linter flagged every SECURITY DEFINER function as
-- callable over PostgREST (/rest/v1/rpc/<name>) by anon and
-- authenticated. For trigger-only functions that is pure attack
-- surface: calling guard_profile_role() or handle_new_user() outside
-- a trigger context cannot do anything useful, so there is no reason
-- to expose them.
--
-- Revoking is safe for triggers: PostgreSQL checks EXECUTE on a
-- trigger function only at CREATE TRIGGER time, never when the
-- trigger fires (confirmed in the docs and on pgsql-workers). The
-- owner (postgres) keeps its rights implicitly, so the triggers keep
-- working for every caller.
--
-- Each revoke names anon, authenticated and service_role explicitly
-- because Supabase's ALTER DEFAULT PRIVILEGES grants EXECUTE to them
-- directly, not via PUBLIC -- revoking PUBLIC alone changes nothing.
--
-- place_order() is NOT revoked: it is the storefront's checkout RPC
-- and must stay callable by authenticated. That linter warning is
-- accepted on purpose (section 2b).
--
-- handle_new_user() is also revoked, but it lives in section 3 --
-- revoking a function that does not exist yet aborts a fresh run, so
-- the statement sits right after its definition there.
-- ============================================================================

revoke all on function public.guard_profile_role() from public, anon, authenticated, service_role;
revoke all on function public.guard_order_update() from public, anon, authenticated, service_role;
revoke all on function public.restock_on_cancel()  from public, anon, authenticated, service_role;


-- ============================================================================
-- 3. AUTO-CREATE PROFILE ON SIGNUP
--
-- Keeps the username in sync with the account the moment it is created,
-- so the app never has to create the row itself.
-- ============================================================================

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  v_username text;
  v_base     text;
  v_suffix   integer := 0;
begin
  -- Preferred name from sign-up metadata; falls back to the part of the
  -- email before "@". A phone or OAuth sign-up can carry a null email,
  -- so coalesce it before splitting -- split_part(NULL, ...) is NULL,
  -- which would abort the whole auth.users insert on the NOT NULL below.
  v_base := coalesce(
    nullif(trim(new.raw_user_meta_data ->> 'username'), ''),
    nullif(split_part(new.email, '@', 1), ''),
    'customer'
  );

  -- `username` is UNIQUE, and this trigger runs inside the auth.users
  -- INSERT -- a unique_violation here rolls the entire sign-up back with
  -- an opaque error. Two accounts that resolve to the same base name
  -- (john+x@ and john+y@, or two OAuth profiles called "john") would do
  -- exactly that. Append a counter until the name is free instead.
  v_username := v_base;

  while exists (select 1 from public.profiles where username = v_username) loop
    v_suffix   := v_suffix + 1;
    v_username := v_base || '_' || v_suffix;
  end loop;

  insert into public.profiles (id, username)
  values (new.id, v_username)
  on conflict (id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Triggers fire without an EXECUTE check (see section 2e), so this
-- revoke closes the /rpc/handle_new_user endpoint without touching
-- sign-ups. Placed here because a revoke before the function exists
-- would abort a fresh run of this file.
revoke all on function public.handle_new_user() from public, anon, authenticated, service_role;


-- ============================================================================
-- 4. REALTIME
--
-- The storefront expects live updates, so these tables must be added to
-- the realtime publication. Without this the grid loads once and never
-- refreshes.
-- ============================================================================

do $$
begin
  begin
    alter publication supabase_realtime add table public.products;
  exception when duplicate_object then null;
  end;

  begin
    alter publication supabase_realtime add table public.cart_items;
  exception when duplicate_object then null;
  end;

  begin
    alter publication supabase_realtime add table public.orders;
  exception when duplicate_object then null;
  end;

  begin
    alter publication supabase_realtime add table public.profiles;
  exception when duplicate_object then null;
  end;

  begin
    alter publication supabase_realtime add table public.featured_slides;
  exception when duplicate_object then null;
  end;
end $$;


-- ============================================================================
-- 5. ADMIN ACCOUNTS
--
-- Section 1e already gates every write to `products` and
-- `featured_slides` behind `public.is_admin()`. That helper reads
-- `profiles.role`, which defaults to 'customer'.
--
-- So right after running this schema for the first time, NOBODY can
-- write to the catalog yet. Promote the accounts that run the admin
-- app, once, in the SQL editor:
--
--   update public.profiles p
--   set role = 'admin'
--   from auth.users u
--   where p.id = u.id and u.email = 'admin@example.com';
--
-- Targeting via auth.users cannot miss. `profiles.username` can be
-- renamed at any time, and sign-up appends _1, _2 when the base name
-- is taken -- so a `where username = 'admin'` update can match zero
-- rows, or worse, a different account, and still report UPDATE 1.
-- Sign up the admin account first, so the row exists.
--
-- Confirm it took:
--
--   select u.email, p.username, p.role
--   from auth.users u
--   join public.profiles p on p.id = u.id
--   order by u.created_at;
--
-- Until an account is promoted, the admin app signs it straight back
-- out ("admin accounts only") and every save from the storefront side
-- fails with:
--
--   new row violates row-level security policy
--
-- That message means "no admin account yet", not "policies missing".
-- See ADMIN_INTEGRATION.md section 6.
-- ============================================================================


-- ============================================================================
-- 6. OPTIONAL: undo the admin gate
--
-- Only needed if you want the earlier permissive behaviour back, where
-- any signed-in user could edit the catalog. Running this makes the
-- storefront key able to write again, which is what section 1e is
-- there to prevent. The read policies are unchanged by it.
--
-- WARNING: these six policies were found LIVE on this database (the
-- linter flagged them), which meant every storefront customer could
-- rewrite the catalog. If you run this section, run the whole schema
-- again afterwards -- section 2-0 wipes them and restores the gate.
-- And note the admin app itself now refuses non-admin sign-ins, so
-- lifting the gate here does not let customers into the dashboard;
-- it only widens what a stolen storefront key can do.
-- ============================================================================

-- drop policy if exists "admins can insert products" on public.products;
-- create policy "signed in users can insert products"
--   on public.products for insert to authenticated
--   with check (true);

-- drop policy if exists "admins can update products" on public.products;
-- create policy "signed in users can update products"
--   on public.products for update to authenticated
--   using (true);

-- drop policy if exists "admins can delete products" on public.products;
-- create policy "signed in users can delete products"
--   on public.products for delete to authenticated
--   using (true);

-- drop policy if exists "admins can insert featured slides" on public.featured_slides;
-- create policy "signed in users can insert featured slides"
--   on public.featured_slides for insert to authenticated
--   with check (true);

-- drop policy if exists "admins can update featured slides" on public.featured_slides;
-- create policy "signed in users can update featured slides"
--   on public.featured_slides for update to authenticated
--   using (true);

-- drop policy if exists "admins can delete featured slides" on public.featured_slides;
-- create policy "signed in users can delete featured slides"
--   on public.featured_slides for delete to authenticated
--   using (true);
