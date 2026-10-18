/// The storefront's category filter list.
///
/// "All Products" is the default chip and clears the filter; the six
/// skincare categories below narrow the grid. These strings must stay
/// in step with two other copies of the same list:
///
///   - the `products_category_check` constraint in supabase/schema.sql
///   - `CATEGORIES` in the admin dashboard's app.js
///
/// A product with a NULL category shows only under "All Products".
const String kAllProductsCategory = 'All Products';

const List<String> kProductCategories = [
  kAllProductsCategory,
  'Cleansers',
  'Moisturizers',
  'Sunscreens',
  'Serums & Treatments',
  'Toners',
  'Masks & Exfoliators',
];
