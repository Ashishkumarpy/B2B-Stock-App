-- 📊 Zentory User Management Patch: Support Phone-Only Workers in Warehouses & Audits
-- Run this in the Supabase SQL Editor.

-- 1. Modify public.user_warehouses to support worker_id
-- Drop the original primary key constraint (which was on user_id, warehouse_id)
ALTER TABLE public.user_warehouses DROP CONSTRAINT IF EXISTS user_warehouses_pkey;

-- Add worker_id column referencing workers(id)
ALTER TABLE public.user_warehouses ADD COLUMN IF NOT EXISTS worker_id UUID REFERENCES public.workers(id) ON DELETE CASCADE;

ALTER TABLE public.workers ADD COLUMN IF NOT EXISTS perm_products BOOLEAN;
ALTER TABLE public.workers ADD COLUMN IF NOT EXISTS perm_inventory BOOLEAN;
ALTER TABLE public.workers ADD COLUMN IF NOT EXISTS perm_orders BOOLEAN;
ALTER TABLE public.workers ADD COLUMN IF NOT EXISTS perm_reports BOOLEAN;
ALTER TABLE public.workers ADD COLUMN IF NOT EXISTS perm_users BOOLEAN;
ALTER TABLE public.workers ADD COLUMN IF NOT EXISTS perm_settings BOOLEAN;

UPDATE public.workers
SET
  perm_products = COALESCE(perm_products, false),
  perm_inventory = COALESCE(perm_inventory, true),
  perm_orders = COALESCE(perm_orders, (role = 'manager')),
  perm_reports = COALESCE(perm_reports, (role = 'manager')),
  perm_users = COALESCE(perm_users, (role = 'manager')),
  perm_settings = COALESCE(perm_settings, false);

ALTER TABLE public.workers
  ALTER COLUMN perm_products SET DEFAULT false,
  ALTER COLUMN perm_inventory SET DEFAULT true,
  ALTER COLUMN perm_orders SET DEFAULT false,
  ALTER COLUMN perm_reports SET DEFAULT false,
  ALTER COLUMN perm_users SET DEFAULT false,
  ALTER COLUMN perm_settings SET DEFAULT false;

-- Make user_id nullable (since phone-only workers don't have user_id)
ALTER TABLE public.user_warehouses ALTER COLUMN user_id DROP NOT NULL;

-- Add unique constraint on (user_id, warehouse_id)
ALTER TABLE public.user_warehouses DROP CONSTRAINT IF EXISTS user_warehouses_user_unique;
ALTER TABLE public.user_warehouses ADD CONSTRAINT user_warehouses_user_unique UNIQUE (user_id, warehouse_id);

-- Add unique constraint on (worker_id, warehouse_id)
ALTER TABLE public.user_warehouses DROP CONSTRAINT IF EXISTS user_warehouses_worker_unique;
ALTER TABLE public.user_warehouses ADD CONSTRAINT user_warehouses_worker_unique UNIQUE (worker_id, warehouse_id);


-- 2. Modify public.login_history to support worker_id
ALTER TABLE public.login_history ADD COLUMN IF NOT EXISTS worker_id UUID REFERENCES public.workers(id) ON DELETE CASCADE;


-- 3. Modify public.activity_logs to support worker_id
ALTER TABLE public.activity_logs ADD COLUMN IF NOT EXISTS worker_actor_id UUID REFERENCES public.workers(id) ON DELETE SET NULL;


-- 4. Update share_warehouse helper function to support workers
CREATE OR REPLACE FUNCTION public.share_warehouse(user_a UUID, user_b UUID)
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 
    FROM public.user_warehouses uw1
    JOIN public.user_warehouses uw2 ON uw1.warehouse_id = uw2.warehouse_id
    WHERE (uw1.user_id = user_a OR uw1.worker_id = user_a)
      AND (uw2.user_id = user_b OR uw2.worker_id = user_b)
  );
$$ LANGUAGE sql SECURITY DEFINER;


-- 5. Update RLS Policies on user_warehouses for worker_id support
DROP POLICY IF EXISTS "Users can view own warehouse assignments." ON public.user_warehouses;
CREATE POLICY "Users can view own warehouse assignments." ON public.user_warehouses
  FOR SELECT USING (
    user_id = auth.uid() OR 
    worker_id = auth.uid() OR
    public.is_real_admin() OR
    (public.has_permission('perm_users') AND public.share_warehouse(auth.uid(), COALESCE(user_id, worker_id)))
  );

DROP POLICY IF EXISTS "Admins and managers can manage warehouse assignments." ON public.user_warehouses;
CREATE POLICY "Admins and managers can manage warehouse assignments." ON public.user_warehouses
  FOR ALL USING (
    public.is_real_admin() OR
    (public.has_permission('perm_users') AND public.share_warehouse(auth.uid(), COALESCE(user_id, worker_id)))
  )
  WITH CHECK (
    public.is_real_admin() OR
    (public.has_permission('perm_users') AND public.share_warehouse(auth.uid(), COALESCE(user_id, worker_id)))
  );


-- 6. Update Login History Policies for worker_id support
DROP POLICY IF EXISTS "Admins and managers can view login history." ON public.login_history;
CREATE POLICY "Admins and managers can view login history." ON public.login_history
  FOR SELECT USING (
    public.is_real_admin() OR
    (public.has_permission('perm_users') AND public.share_warehouse(auth.uid(), COALESCE(user_id, worker_id)))
  );
