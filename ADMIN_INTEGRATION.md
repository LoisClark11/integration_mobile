# TouchSkin — project guide

This file is the map of the repo. Read it before changing Flutter, SQL, or the admin dashboard.

The admin dashboard is now a **separate deployable**: it moved out of this
repo to `../touchskin-admin/` (its own git repo, deployed on GitHub Pages,
zero-cost plan). Every `Admin_Dashboard` path below should be read as that
location. Its deployment instructions live in `../touchskin-admin/README.md`.

Truth for tables and policies: `supabase/schema.sql` (idempotent; safe to re-run).
Truth for storefront queries: `lib/app_repository.dart`.
Truth for admin UI behavior: `../touchskin-admin/app.js`.

---

## Contents

1. [What this project is](#1-what-this-project-is)
2. [Where to look](#2-where-to-look)
3. [Invariants — do not break these](#3-invariants--do-not-break-these)
4. [Data contract](#4-data-contract)
5. [Storefront behavior](#5-storefront-behavior)
6. [One-time Supabase setup](#6-one-time-supabase-setup)
7. [Admin: products and images](#7-admin-products-and-images)
8. [Admin: featured slides](#8-admin-featured-slides)
9. [Admin: stock and `place_order`](#9-admin-stock-and-place_order)
10. [Admin: who can write, who can read orders](#10-admin-who-can-write-who-can-read-orders)
11. [Realtime](#11-realtime)
12. [Firebase → Supabase field map](#12-firebase--supabase-field-map)
13. [Common errors](#13-common-errors)
14. [Checklist](#14-checklist)

---

## 1. What this project is

Two clients, one Supabase backend.

| Client | Path | Role |
|---|---|---|
| Storefront | this Flutter app (`lib/`) | **Receive-only** for catalog and banners. Writes cart, orders (via RPC), and the signed-in user's profile. |
| Admin | `../touchskin-admin/` (static HTML/JS) | Creates/edits products and featured slides. Reads all orders. Sets stock. Never decrements stock itself. |

App display name: **TouchSkin** (skincare e-commerce storefront; soft blush & cream design direction). Package name: `integration_mobile`. Entry: `lib/main.dart` → `ProductInventoryApp` → `DashboardScreen` (product grid).

Auth is Supabase Auth (email). Passwords are not stored in `profiles`. A `handle_new_user` trigger creates the `profiles` row on signup.

---

## 2. Where to look

### Storefront (`lib/`)

Do not add new `.from('…')` calls in screens. Route data through `AppRepository`.

| File | Responsibility |
|---|---|
| `lib/main.dart` | `main()`, `ProductInventoryApp`, password-recovery listener, `DashboardScreen` (grid + banner + search + tabs) |
| `lib/supabase_service.dart` | `Supabase.initialize`, `projectUrl`, `publishableKey`, `deepLinkRedirect` |
| `lib/session.dart` | `AppSession` — `isLoggedIn`, `userId`, `username`, `email` from the live client (no cache) |
| `lib/app_repository.dart` | **All** table streams and writes: products, slides, cart, orders, profile |
| `lib/featured_slide.dart` | `FeaturedSlide.fromRow` — banner/name/price fallback rules (unit-tested) |
| `lib/featured_slides_carousel.dart` | Full-width banner strip on the products page |
| `lib/stock_label.dart` | `readStock`, `StockTone`, `kLowStockThreshold = 5` |
| `lib/product_image.dart` | `Image.network` with `assets/images/product_placeholder.png` fallback |
| `lib/product_thumbnail.dart` | Grid/list thumbnail |
| `lib/product_detail_screen.dart` | Product page + “Other Products” + Add to cart / Buy now |
| `lib/cart_screen.dart` | Cart lines; quantity capped at live stock |
| `lib/checkout_screen.dart` | Checkout; delivery fee **50**; calls `AppRepository.createOrder` |
| `lib/order_detail_screen.dart` | One order; cancel / delete |
| `lib/user_profile_screen.dart` | Profile, avatar upload (`avatars` bucket), My Orders, sign out |
| `lib/login_screen.dart` | Sign in |
| `lib/create_account_screen.dart` | Sign up |
| `lib/forgot_password_screen.dart` | Sends reset email using `deepLinkRedirect` |
| `lib/reset_password_screen.dart` | New password after recovery deep link |
| `lib/change_password_screen.dart` | Signed-in password change |
| `lib/gradient_header.dart` / `lib/app_footer.dart` | Shared chrome |

### Tests (`test/`)

| File | Covers |
|---|---|
| `test/featured_slide_test.dart` | Banner/name/price fallbacks, skip-if-unrenderable |
| `test/featured_slides_carousel_test.dart` | Carousel widget |
| `test/stock_label_test.dart` | Stock wording/colors |
| `test/user_profile_signed_out_test.dart` | Signed-out profile UI |

### Backend and admin

| Path | Role |
|---|---|
| `supabase/schema.sql` | Tables, replica identity, RLS, `is_admin()`, `place_order()`, profile trigger, realtime publication |
| `supabase/stock.sql` | Stock column + `place_order` only (use if you do not want a full schema re-run) |
| `../touchskin-admin/index.html` | Admin UI shell |
| `../touchskin-admin/app.js` | Admin flows (upload, save, slides, orders, XSS-safe order cells) |
| `../touchskin-admin/supabase-config.js` | Admin URL + anon/publishable key |
| `android/app/src/main/AndroidManifest.xml` | Deep-link intent-filter; must match `SupabaseService.deepLinkRedirect` |

### Navigation (storefront)

```
DashboardScreen (home; unknown routes also land here)
  ├─ FeaturedSlidesCarousel  → ProductDetailScreen
  ├─ product grid            → ProductDetailScreen
  │     ├─ add to cart
  │     └─ buy now           → CheckoutScreen (purchase_type: "Buy Now")
  ├─ Cart tab                → CartScreen → CheckoutScreen (purchase_type: "Cart")
  ├─ Profile tab             → UserProfileScreen
  │     ├─ My Orders         → OrderDetailScreen
  │     ├─ Change password
  │     └─ Log In            → LoginScreen
  │           ├─ CreateAccountScreen
  │           └─ ForgotPasswordScreen
  └─ AuthRecoveryListener (above Navigator)
        └─ ResetPasswordScreen on passwordRecovery event
```

Deep link scheme: `integrationmobile://reset-password`. Must be allow-listed in Supabase Auth → URL Configuration.

---

## 3. Invariants — do not break these

An AI changing this repo should treat these as hard constraints.

1. **Catalog writes are admin-only.** Storefront never inserts/updates/deletes `products` or `featured_slides`. RLS (`is_admin()`) enforces this because the publishable key ships in the customer app.
2. **Never put the `service_role` / secret key** in Flutter or the admin dashboard.
3. **Orders go through `rpc('place_order')`**, not `from('orders').insert`. Stock decrement and order insert are one Postgres transaction. App-side `stock - n` races two buyers on the last unit.
4. **`place_order` JSON items must use camelCase `productId` and `quantity`.** Postgres reads `v_entry ->> 'productId'`.
5. **Do not build Supabase `.stream()` inside `Widget.build`.** Create the stream once in `initState` and keep it in a field. A new call opens a new realtime subscription.
6. **Featured stream order is `display_order` ascending.** Default stream sort is newest-first and would reverse the carousel.
7. **`featured_slides.product_id` is required.** Create the product first, then attach a slide. Deleting the slide unfeatures the product. Deleting the product cascades the slide.
8. **A slide uploads one picture: `banner_url`.** Product photo is reused as fallback and as the detail-page image. Folder: `product-images` / `featured/banner/`.
9. **Skip slides with no drawable image.** `FeaturedSlide.isRenderable` is `bannerUrl != null` after fallback to `products.image_url`.
10. **`item_name` / `item_price` are legacy overrides.** Admin no longer writes them. App still honours them if present, else uses the linked product.
11. **Cart lines snapshot `name`, `price`, `image_url`.** Unique `(user_id, product_id)`. Quantity `+` is capped at live `products.stock`.
12. **Delivery fee is 50** (`CheckoutScreen._deliveryFee` and `orders.delivery_fee` default).
13. **Order `status` is `'Completed' | 'Cancelled'`.** Customers can cancel/delete **their own** orders. Admins have **SELECT all orders**, no UPDATE.
14. **`customer_email` is filled inside `place_order` from `auth.users`**, not from the app. Do not add it as an RPC argument.
15. **`profiles` RLS is own-row only.** Admins cannot join orders → profiles. That is why email is snapshotted on the order.
16. **Replica identity FULL** on `cart_items`, `orders`, `featured_slides`. Without it, filtered DELETE events never reach the device (row stays on screen).
17. **Storage `bucket_id` is text** (the bucket id string) on current projects. `bucket_id = 'avatars'` works directly; the storage policies are installed by schema section 2d with owner checks.
18. **Session is in-memory.** `persistSession: false` and `autoRefreshToken: false`. Cold start is signed out. Password reset still works via deep link + in-memory session for that process.
19. **Signed-out users can still read products and active slides** (public SELECT). Cart/checkout/orders require auth.
20. **Low-stock threshold is 5** in both `lib/stock_label.dart` and `../touchskin-admin/app.js` (`LOW_STOCK`). Keep them equal.
21. **Order panel must not use `innerHTML` for customer fields.** `customer_name` and `address` are free text (stored XSS). Dashboard uses `textContent` / `escapeHtml`.
22. **Column names the storefront reads are a contract.** Renaming them without updating both `schema.sql` and `AppRepository` / widgets breaks the app. See section 4.

---

## 4. Data contract

### Tables the storefront reads/writes

| Table | Storefront | Columns the app uses |
|---|---|---|
| `products` | read + realtime | `id`, `name`, `price`, `description`, `image_url`, `stock`, `category`, `created_at` |
| `featured_slides` | read + realtime, `is_active = true` | `id`, `product_id`, `title`, `subtitle`, `banner_url`, `item_name`, `item_price`, `button_label`, `display_order`, `is_active` |
| `cart_items` | CRUD own rows | `id`, `user_id`, `product_id`, `quantity`, `name`, `price`, `image_url` |
| `orders` | create via RPC; read/cancel/delete own | `id`, `customer_name`, `customer_email`, `address`, `payment_method`, `subtotal_amount`, `delivery_fee`, `total_amount`, `item_count`, `items`, `status`, `created_at`, `purchase_type`, `cancelled_at` |
| `profiles` | read/update own | `id`, `username`, `profile_image`, `role` (admin app only) |

Fallbacks: blank `description` → `"No description available"`. Missing/failed `image_url` → bundled placeholder. Missing `stock` column → hide badge (`readStock` returns null), do not show “Out of stock”.

### `place_order` RPC

```
place_order(
  p_customer_name text,
  p_address text,
  p_payment_method text,
  p_subtotal numeric,
  p_delivery_fee numeric,
  p_total numeric,
  p_item_count integer,
  p_items jsonb,
  p_purchase_type text
) returns uuid
```

`p_items` example:

```json
[{ "productId": "<uuid>", "name": "Laptop", "price": 30000, "quantity": 2, "subtotal": 60000 }]
```

`p_purchase_type`: `"Cart"` or `"Buy Now"`. Granted to `authenticated` only.

### Storage

| Bucket | Public | Used for | Paths |
|---|---|---|---|
| `product-images` | yes | product photos, banners | `products/<ts>.<ext>`, `featured/banner/<ts>.<ext>` |
| `avatars` | yes | profile pictures | uploaded by storefront profile screen |

Public URL shape:

`https://<ref>.supabase.co/storage/v1/object/public/<bucket>/<path>`

That string is stored in `image_url` / `banner_url` / `profile_image`. The storefront renders it with `Image.network`.

### RLS summary

| Caller | products / featured_slides | cart / own orders | all orders |
|---|---|---|---|
| Signed out | SELECT | none | none |
| Customer | SELECT | own rows | no |
| Admin (`profiles.role = 'admin'`) | SELECT + INSERT/UPDATE/DELETE | own rows | SELECT only |

`role` defaults to `'customer'`. Until at least one profile is promoted, every admin save fails with `new row violates row-level security policy`. Re-running the schema does **not** promote anyone.

---

## 5. Storefront behavior

- **Browse without login.** Grid and banners are public. Add to cart / checkout / orders require a session.
- **Featured carousel:** `watchFeaturedSlides()` filters `is_active` in PostgREST. Resolve each row with `FeaturedSlide.fromRow(row, productsById)`. Tap / Order Now → `ProductDetailScreen` for `productId`. No product id or no image → no button / skip slide.
- **Stock copy:** `0` → “Out of stock” (red); `1..5` → “Only N left” (amber); `6+` → “N in stock” (green).
- **Checkout refusal:** `PostgrestException` from `place_order` is shown as-is. Expected when another buyer took the last units after the cart was filled. Not a bug.
- **Password reset:** Android may deliver the link as `/?code=...`. `onUnknownRoute` still shows `DashboardScreen`. `AuthRecoveryListener` waits for `passwordRecovery` so a session exists before `updateUser`.
- **Config:** `lib/supabase_service.dart` — `projectUrl`, `publishableKey`, `deepLinkRedirect`. Restart after edits.

---

## 6. One-time Supabase setup

Do this once in the dashboard.

### 6a. Keys

Project Settings → API:

| Value | Where |
|---|---|
| Project URL | `lib/supabase_service.dart` → `projectUrl` and `../touchskin-admin/supabase-config.js` |
| Publishable key (`sb_publish_…`) | same two files |

### 6b. Schema

SQL Editor → paste all of `supabase/schema.sql` → Run.

Stock-only follow-up: `supabase/stock.sql` (column, function, grants, verification **before** any backfill).

### 6c. Buckets

Storage → New bucket, twice: `product-images` (public), `avatars` (public).

### 6d. Storage policies

**Installed by `supabase/schema.sql` section 2d** — you do not need to paste anything by hand. That section creates both buckets (`product-images`, `avatars`, both public) and the read/write policies with owner checks:

- **read** — open to everyone (the app renders photos before login);
- **`product-images` write** — admin only, via `public.is_admin()`;
- **`avatars` write** — a customer may write only under their own id (`avatars/<user_id>.<ext>`), so one signed-in user cannot overwrite another's picture.

If you are on an older project and only want to verify or re-apply just the storage half, run section 2d on its own — every statement there is idempotent.

Note on `bucket_id`: on current Supabase projects it is a **text** column holding the bucket id, so `bucket_id = 'product-images'` works directly. (Some older docs claim it is uuid and you must subquery `storage.buckets.name`; that is no longer the case, but the subquery form also still works if you prefer it.)

Verify the buckets exist:

```sql
select id, name, public from storage.buckets order by name;
```

### 6e. Email confirmation

Authentication → Providers → Email. For local testing, Confirm email **OFF**. With it ON, signup shows “Check your email” and does not sign in.

### 6f. Promote an admin

Sign up the admin account first (so `profiles` exists), then:

```sql
update public.profiles
set role = 'admin'
where username = 'your-admin-username';

select username, role from public.profiles order by username;
```

### 6g. Replica identity (live deletes)

Confirm `relreplident` is `f` (FULL) for `cart_items`, `orders`, `featured_slides`. Schema section 1c sets this. Symptom if missing: inserts/updates live, deletes stay on screen.

---

## 7. Admin: products and images

Init the same project (admin is already JS; Flutter admin would use `supabase_flutter` + `image_picker`).

Flow: **upload file first**, then insert the row with the public URL (never bytes).

```dart
final path = 'products/${DateTime.now().millisecondsSinceEpoch}.$extension';

await Supabase.instance.client.storage
    .from('product-images')
    .uploadBinary(path, bytes, fileOptions: const FileOptions(
      contentType: 'image/jpeg',
      upsert: false,
    ));

final imageUrl = Supabase.instance.client.storage
    .from('product-images')
    .getPublicUrl(path);

await Supabase.instance.client.from('products').insert({
  'name': name,
  'price': price,          // numeric, not a string
  'description': description,
  'image_url': imageUrl,   // not `image`
  'stock': stock,          // integer; 0 = sold out
});
```

Update: `.update({…}).eq('id', productId)`. No need to set `updated_at` by hand — the `products_set_updated_at` trigger in `supabase/schema.sql` stamps it on every UPDATE.

Delete: remove storage object, then delete the row. `cart_items.product_id` is `on delete cascade`.

Set MIME from the picker extension (`png` → `image/png`, etc.). Wrong `contentType` makes phones refuse to render the file.

---

## 8. Admin: featured slides

One picture per slide (`banner_url`). Overlay: `title`, `subtitle`, `item_name`/`item_price` (or product fallback), `button_label` (default `Order Now`).

```
1. Create product            → public.products
2. Feature it                → public.featured_slides
                               product_id = that product
                               banner_url = wide picture
3. Unfeature                 → DELETE the featured_slides row
                               (product stays in the catalog)
```

`display_order`: lowest first. `is_active: false` hides without deleting.

Upload path: `featured/banner/<timestamp>.<ext>` in `product-images`. No extra bucket or policy.

Insert after upload; require `productId` **before** uploading so a cancel does not leave an orphan file.

Replace banner: upload new → update row → then delete old file (never the reverse).

Delete slide: parse path from public URL (`…/object/public/product-images/` + rest), `storage.remove`, then delete row. Ignore URLs that are not in this bucket.

Admin list stream:

```dart
.from('featured_slides').stream(primaryKey: ['id'])
  .order('display_order', ascending: true)
```

Working implementation: `../touchskin-admin/app.js` (slide upload, reorder, delete).

---

## 9. Admin: stock and `place_order`

`products.stock` is the only inventory number. Admin sets it. **Only `place_order()` lowers it.** Realtime updates both UIs.

Blank/zero stock = sold out. Dashboard colours: green, amber at ≤5, red at 0.

Inside the function, decrement is:

```sql
update public.products
   set stock = stock - v_quantity
 where id = v_product_id
   and stock >= v_quantity;
```

If `not found`, it raises `Not enough stock for "…"`. The whole function rolls back, so a refused order never leaves stock taken.

Default for new/migrated rows is `0`. Backfill **only after** the column exists:

```sql
update public.products set stock = 25 where stock = 0;
```

Prefer `supabase/stock.sql` over guessing order.

Storefront call site: `AppRepository.createOrder` → `rpc('place_order', params: { p_customer_name, p_address, p_payment_method, p_subtotal, p_delivery_fee, p_total, p_item_count, p_items, p_purchase_type })`.

---

## 10. Admin: who can write, who can read orders

UI `isAdmin()` (read `profiles.role`) only hides buttons. RLS is what refuses the write.

```sql
-- already in schema.sql
create policy "admins can read all orders"
  on public.orders for select
  to authenticated
  using (public.is_admin());
```

Permissive policies **OR**. Customers still only match `auth.uid() = user_id`. After adding admin-read, **verify a customer still sees only their own orders**.

Backfill email on old orders (touches `auth.users`; not auto-run by schema):

```sql
update public.orders o
set customer_email = u.email
from auth.users u
where u.id = o.user_id and o.customer_email is null;
```

A read-only staff role is **not** implemented. `is_admin()` currently implies catalog writes. Sketch for later: `can_view_orders()` checking `role in ('admin','staff')` on the orders SELECT policy only.

To restore “any signed-in user may edit catalog”, commented statements live in `supabase/schema.sql` (permissive section). That reopens the catalog to every signup.

---

## 11. Realtime

Publication includes `products`, `cart_items`, `orders`, `profiles`, `featured_slides`. New tables:

```sql
alter publication supabase_realtime add table public.your_table;
```

Admin products list:

```dart
.from('products').stream(primaryKey: ['id']).order('created_at')
```

---

## 12. Firebase → Supabase field map

| Firebase (old) | Supabase (new) |
|---|---|
| `products/<id>` | `products.id` (uuid) |
| `products/<id>/price` (string) | `products.price` (numeric) |
| `products/<id>/image` | `products.image_url` |
| `users/<username>/password` | gone — Supabase Auth |
| `users/<username>/profileImage` | `profiles.profile_image` |
| `carts/<username>/<productId>` | `cart_items` keyed by `user_id` (auth uuid), not username |
| `transactions/<id>` | `orders.id` |
| `transactions/<id>/customerName` | `orders.customer_name` |
| `transactions/<id>/totalAmount` | `orders.total_amount` |
| `transactions/<id>/items` | `orders.items` (jsonb) |

---

## 13. Common errors

| Error / symptom | Cause | Fix |
|---|---|---|
| `Invalid API key` | wrong publishable key | recopy Project Settings → API |
| RLS on `products` / `featured_slides` insert | no admin role | `update profiles set role = 'admin' …` |
| RLS on storage upload | missing storage insert policy, or bucket not public | schema section 2d |
| `Bucket not found` | typo / wrong project | names must be `product-images`, `avatars` |
| `fetch failed` | offline or paused project | dashboard |
| Image never appears | empty URL or private bucket | public bucket + URL string |
| Signup ok, login rejected | email confirmation on | §6e |
| Products load once then freeze | table not in realtime publication | schema realtime section |
| Deletes persist on screen; `+`/`-` works | replica identity not FULL | schema 1c |
| `Not enough stock for "…"` | race at checkout | expected; lower qty or restock |
| Every product “Out of stock” | `stock` default 0 | set stock or backfill |
| `column products.stock does not exist` | schema not updated | re-run schema or `stock.sql` |
| `permission denied for function place_order` | GRANT missing | re-run schema |
| `column products.image does not exist` | old Firebase name | use `image_url` |
| `relation "featured_slides" does not exist` | schema not re-run | re-run `schema.sql` |
| Banner missing | no active slides, or no banner and no product photo | `select id, is_active, banner_url from featured_slides;` |
| Slides in wrong order | stream default sort | `order('display_order', ascending: true)` |
| Cart/checkout RLS | signed out or wrong user | own-row policies |

---

## 14. Checklist

- [ ] Ran `supabase/schema.sql`
- [ ] `relreplident` is FULL (`f`) on `cart_items`, `orders`, `featured_slides`
- [ ] Public buckets `product-images` and `avatars` + four storage policies (subquery form)
- [ ] Email confirmation off for local testing
- [ ] URL + publishable key in `lib/supabase_service.dart` and `../touchskin-admin/supabase-config.js`
- [ ] Deep link `integrationmobile://reset-password` in AndroidManifest **and** Supabase redirect URLs
- [ ] Promoted admin: `update public.profiles set role = 'admin'`
- [ ] Full app restart (not hot reload)
- [ ] Admin saves one product with image + stock → appears on storefront grid and “Other Products”
- [ ] Customer cannot save a product or slide
- [ ] Add to cart, quantity caps at stock, checkout via `place_order`
- [ ] Order in Profile → My Orders; cancel works
- [ ] Featured slide with banner opens the linked product
- [ ] Buy last units; stock drops on both clients; oversell is refused
- [ ] Admin Orders tab sees every order; customer still sees only their own
- [ ] `customer_email` backfilled on old orders if needed
