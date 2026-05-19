-- 1. Add pcs_per_carton to products
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS pcs_per_carton INTEGER DEFAULT 1;

-- 2. Add cartons and pcs_per_carton to transactions
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS cartons INTEGER;
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS pcs_per_carton INTEGER;

-- 3. Update existing products to have at least 1 pc per carton (avoid division by zero)
UPDATE public.products SET pcs_per_carton = 1 WHERE pcs_per_carton IS NULL OR pcs_per_carton < 1;
