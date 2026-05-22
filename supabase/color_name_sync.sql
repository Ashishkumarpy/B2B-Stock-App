-- Color Name Sync / Repair Script
-- Purpose:
-- 1) Canonicalize warehouse_product_stocks.color_name to current product color names
-- 2) Merge duplicate rows created by old/short color codes (e.g. "B") vs new names (e.g. "Black")
-- 3) Canonicalize transactions.color_name for consistency
--
-- Safe to run multiple times.

BEGIN;

-- Build product color catalog from products.color_stocks JSON.
WITH product_colors AS (
  SELECT
    p.id AS product_id,
    COALESCE(NULLIF(btrim(cs.value->>'color'), ''), 'Default') AS canonical_color,
    lower(COALESCE(NULLIF(btrim(cs.value->>'color'), ''), 'Default')) AS canonical_color_lc
  FROM products p
  CROSS JOIN LATERAL jsonb_array_elements(
    CASE
      WHEN jsonb_typeof(p.color_stocks) = 'array' THEN p.color_stocks
      ELSE '[]'::jsonb
    END
  ) AS cs(value)
),
product_color_counts AS (
  SELECT
    product_id,
    COUNT(*)::int AS color_count
  FROM product_colors
  GROUP BY product_id
),
-- For each warehouse stock row, choose a canonical target color:
-- Priority:
-- 1) exact case-insensitive match
-- 2) single-letter short code where exactly one product color starts with that letter (e.g. B -> Black)
-- 3) product has exactly one color -> map everything to that color
-- 4) otherwise keep current color_name
row_mapping AS (
  SELECT
    wps.id,
    wps.warehouse_id,
    wps.product_id,
    wps.quantity,
    wps.color_name AS old_color_name,
    lower(COALESCE(NULLIF(btrim(wps.color_name), ''), 'Default')) AS old_color_lc,
    COALESCE(
      -- exact match
      (
        SELECT pc.canonical_color
        FROM product_colors pc
        WHERE pc.product_id = wps.product_id
          AND pc.canonical_color_lc = lower(COALESCE(NULLIF(btrim(wps.color_name), ''), 'Default'))
        LIMIT 1
      ),
      -- one-letter short code match
      (
        SELECT x.canonical_color
        FROM (
          SELECT pc.canonical_color
          FROM product_colors pc
          WHERE pc.product_id = wps.product_id
            AND length(COALESCE(NULLIF(btrim(wps.color_name), ''), 'Default')) = 1
            AND left(pc.canonical_color_lc, 1) = lower(COALESCE(NULLIF(btrim(wps.color_name), ''), 'Default'))
          GROUP BY pc.canonical_color
        ) x
        -- only when unique candidate exists
        WHERE (
          SELECT COUNT(*)
          FROM (
            SELECT pc2.canonical_color
            FROM product_colors pc2
            WHERE pc2.product_id = wps.product_id
              AND length(COALESCE(NULLIF(btrim(wps.color_name), ''), 'Default')) = 1
              AND left(pc2.canonical_color_lc, 1) = lower(COALESCE(NULLIF(btrim(wps.color_name), ''), 'Default'))
            GROUP BY pc2.canonical_color
          ) q
        ) = 1
        LIMIT 1
      ),
      -- only one product color defined
      (
        SELECT pc.canonical_color
        FROM product_colors pc
        JOIN product_color_counts pcc ON pcc.product_id = pc.product_id
        WHERE pc.product_id = wps.product_id
          AND pcc.color_count = 1
        LIMIT 1
      ),
      COALESCE(NULLIF(btrim(wps.color_name), ''), 'Default')
    ) AS target_color_name
  FROM warehouse_product_stocks wps
),
aggregated AS (
  SELECT
    warehouse_id,
    product_id,
    target_color_name AS color_name,
    SUM(quantity)::int AS quantity
  FROM row_mapping
  GROUP BY warehouse_id, product_id, target_color_name
)
-- Remove old rows, then reinsert canonical merged rows.
DELETE FROM warehouse_product_stocks wps
USING row_mapping rm
WHERE wps.id = rm.id;

INSERT INTO warehouse_product_stocks (warehouse_id, product_id, color_name, quantity, updated_at)
SELECT
  a.warehouse_id,
  a.product_id,
  a.color_name,
  GREATEST(0, a.quantity),
  NOW()
FROM aggregated a
ON CONFLICT (warehouse_id, product_id, color_name)
DO UPDATE SET
  quantity = EXCLUDED.quantity,
  updated_at = NOW();

-- Canonicalize transactions color_name as well (for display/history consistency).
WITH product_colors AS (
  SELECT
    p.id AS product_id,
    COALESCE(NULLIF(btrim(cs.value->>'color'), ''), 'Default') AS canonical_color,
    lower(COALESCE(NULLIF(btrim(cs.value->>'color'), ''), 'Default')) AS canonical_color_lc
  FROM products p
  CROSS JOIN LATERAL jsonb_array_elements(
    CASE
      WHEN jsonb_typeof(p.color_stocks) = 'array' THEN p.color_stocks
      ELSE '[]'::jsonb
    END
  ) AS cs(value)
),
tx_map AS (
  SELECT
    t.id,
    COALESCE(
      (
        SELECT pc.canonical_color
        FROM product_colors pc
        WHERE pc.product_id = t.product_id
          AND pc.canonical_color_lc = lower(COALESCE(NULLIF(btrim(t.color_name), ''), 'Default'))
        LIMIT 1
      ),
      COALESCE(NULLIF(btrim(t.color_name), ''), 'Default')
    ) AS target_color_name
  FROM transactions t
)
UPDATE transactions t
SET color_name = tx.target_color_name
FROM tx_map tx
WHERE t.id = tx.id
  AND COALESCE(NULLIF(btrim(t.color_name), ''), 'Default') <> tx.target_color_name;

COMMIT;

-- Optional verification queries:
-- 1) Check old short codes still present:
-- SELECT warehouse_id, product_id, color_name, quantity
-- FROM warehouse_product_stocks
-- WHERE length(btrim(color_name)) = 1
-- ORDER BY updated_at DESC;
--
-- 2) Check per product color rows:
-- SELECT product_id, color_name, SUM(quantity) AS qty
-- FROM warehouse_product_stocks
-- GROUP BY product_id, color_name
-- ORDER BY product_id, color_name;
