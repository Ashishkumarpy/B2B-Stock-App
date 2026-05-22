-- Color Name Sync / Repair Script (fixed)
-- Run in Supabase SQL Editor
-- Safe to run multiple times.

BEGIN;

-- 1) Build mapping for warehouse_product_stocks rows -> canonical target color.
DROP TABLE IF EXISTS tmp_wps_mapped;
CREATE TEMP TABLE tmp_wps_mapped AS
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
  SELECT product_id, COUNT(*)::int AS color_count
  FROM product_colors
  GROUP BY product_id
)
SELECT
  wps.id,
  wps.warehouse_id,
  wps.product_id,
  wps.quantity,
  wps.color_name AS old_color_name,
  COALESCE(
    -- exact case-insensitive match
    (
      SELECT pc.canonical_color
      FROM product_colors pc
      WHERE pc.product_id = wps.product_id
        AND pc.canonical_color_lc = lower(COALESCE(NULLIF(btrim(wps.color_name), ''), 'Default'))
      LIMIT 1
    ),
    -- single-letter shorthand match (B -> Black) when unique
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
    -- product defines exactly one color
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
FROM warehouse_product_stocks wps;

-- 2) Aggregate canonical warehouse color rows.
DROP TABLE IF EXISTS tmp_wps_aggregated;
CREATE TEMP TABLE tmp_wps_aggregated AS
SELECT
  warehouse_id,
  product_id,
  target_color_name AS color_name,
  SUM(quantity)::int AS quantity
FROM tmp_wps_mapped
GROUP BY warehouse_id, product_id, target_color_name;

-- 3) Replace warehouse_product_stocks with canonical merged rows.
DELETE FROM warehouse_product_stocks wps
USING tmp_wps_mapped m
WHERE wps.id = m.id;

INSERT INTO warehouse_product_stocks (warehouse_id, product_id, color_name, quantity, updated_at)
SELECT
  a.warehouse_id,
  a.product_id,
  a.color_name,
  GREATEST(0, a.quantity),
  NOW()
FROM tmp_wps_aggregated a
ON CONFLICT (warehouse_id, product_id, color_name)
DO UPDATE
SET quantity = EXCLUDED.quantity,
    updated_at = NOW();

-- 4) Canonicalize transactions.color_name for consistent history labels.
DROP TABLE IF EXISTS tmp_tx_color_map;
CREATE TEMP TABLE tmp_tx_color_map AS
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
)
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
FROM transactions t;

UPDATE transactions t
SET color_name = m.target_color_name
FROM tmp_tx_color_map m
WHERE t.id = m.id
  AND COALESCE(NULLIF(btrim(t.color_name), ''), 'Default') <> m.target_color_name;

COMMIT;
