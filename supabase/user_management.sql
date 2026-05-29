-- 📊 Zentory User Management, Permissions, and Activity Tracking Schema Update
-- Run this in the Supabase SQL Editor.

-- 1. Extend public.users with is_active and Individual Permissions
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT true;

-- Individual permission columns
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS perm_products BOOLEAN DEFAULT false;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS perm_inventory BOOLEAN DEFAULT false;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS perm_orders BOOLEAN DEFAULT false;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS perm_reports BOOLEAN DEFAULT false;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS perm_users BOOLEAN DEFAULT false;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS perm_settings BOOLEAN DEFAULT false;

-- Initialize existing users' permissions based on their current roles so they do not lose access
UPDATE public.users
SET 
  is_active = COALESCE(is_active, true),
  perm_products = COALESCE(perm_products, (role = 'admin')),
  perm_inventory = COALESCE(perm_inventory, (role IN ('admin', 'manager', 'worker'))),
  perm_orders = COALESCE(perm_orders, (role IN ('admin', 'manager'))),
  perm_reports = COALESCE(perm_reports, (role IN ('admin', 'manager'))),
  perm_users = COALESCE(perm_users, (role IN ('admin', 'manager'))),
  perm_settings = COALESCE(perm_settings, (role = 'admin'));


-- 2. Create user_warehouses Table (User-to-Warehouse Mapping)
CREATE TABLE IF NOT EXISTS public.user_warehouses (
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
  warehouse_id UUID REFERENCES public.warehouses(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (user_id, warehouse_id)
);

-- 3. Create login_history Table
CREATE TABLE IF NOT EXISTS public.login_history (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
  email TEXT,
  ip_address TEXT,
  user_agent TEXT,
  status TEXT DEFAULT 'success', -- 'success' or 'failed'
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4. Create activity_logs Table
CREATE TABLE IF NOT EXISTS public.activity_logs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  actor_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
  actor_name TEXT NOT NULL,
  action_type TEXT NOT NULL, -- 'stock_transaction', 'product_edit', 'order_dispatch', 'login', 'permission_change', 'user_edit', 'user_create', 'user_delete', 'user_disable'
  description TEXT NOT NULL,
  metadata JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 5. Helper Functions for Permissions and Warehouse Sharing

-- Check if a user has a specific permission (or is an Admin)
CREATE OR REPLACE FUNCTION public.has_permission(perm_name TEXT)
RETURNS BOOLEAN AS $$
DECLARE
  has_perm BOOLEAN;
  u_role public.user_role;
BEGIN
  -- Fetch user role, active status and check permission
  SELECT 
    role,
    is_active AND (
      (role = 'admin') OR
      (perm_name = 'perm_products' AND perm_products) OR
      (perm_name = 'perm_inventory' AND perm_inventory) OR
      (perm_name = 'perm_orders' AND perm_orders) OR
      (perm_name = 'perm_reports' AND perm_reports) OR
      (perm_name = 'perm_users' AND perm_users) OR
      (perm_name = 'perm_settings' AND perm_settings)
    )
  INTO u_role, has_perm
  FROM public.users
  WHERE id = auth.uid();

  -- If not active, deny
  IF NOT FOUND THEN
    RETURN FALSE;
  END IF;

  RETURN COALESCE(has_perm, FALSE);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Check if two users share at least one warehouse
CREATE OR REPLACE FUNCTION public.share_warehouse(user_a UUID, user_b UUID)
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 
    FROM public.user_warehouses uw1
    JOIN public.user_warehouses uw2 ON uw1.warehouse_id = uw2.warehouse_id
    WHERE uw1.user_id = user_a AND uw2.user_id = user_b
  );
$$ LANGUAGE sql SECURITY DEFINER;

-- Check if user is Admin
CREATE OR REPLACE FUNCTION public.is_real_admin()
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.users 
    WHERE id = auth.uid() AND role = 'admin' AND is_active = true
  );
$$ LANGUAGE sql SECURITY DEFINER;

-- Check if user is Manager
CREATE OR REPLACE FUNCTION public.is_manager()
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.users 
    WHERE id = auth.uid() AND role = 'manager' AND is_active = true
  );
$$ LANGUAGE sql SECURITY DEFINER;

-- 6. Trigger to auto-assign default permissions based on role
CREATE OR REPLACE FUNCTION public.assign_default_permissions()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.role = 'admin' THEN
    NEW.perm_products := true;
    NEW.perm_inventory := true;
    NEW.perm_orders := true;
    NEW.perm_reports := true;
    NEW.perm_users := true;
    NEW.perm_settings := true;
  ELSIF NEW.role = 'manager' THEN
    NEW.perm_products := false; -- Managers cannot manage products (unless custom permitted)
    NEW.perm_inventory := true;
    NEW.perm_orders := true;
    NEW.perm_reports := true;
    NEW.perm_users := true;     -- Managers can manage workers
    NEW.perm_settings := false;
  ELSIF NEW.role = 'worker' THEN
    NEW.perm_products := false;
    NEW.perm_inventory := true;
    NEW.perm_orders := false;
    NEW.perm_reports := false;
    NEW.perm_users := false;
    NEW.perm_settings := false;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trigger_assign_default_permissions ON public.users;
CREATE TRIGGER trigger_assign_default_permissions
  BEFORE INSERT OR UPDATE OF role ON public.users
  FOR EACH ROW
  EXECUTE FUNCTION public.assign_default_permissions();

-- 7. SECURITY DEFINER Triggers for Stock Operations (So workers can insert transactions without direct product write access)
ALTER FUNCTION public.update_product_quantity_from_transaction() SECURITY DEFINER;

-- 8. Enable RLS on new tables
ALTER TABLE public.user_warehouses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.login_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.activity_logs ENABLE ROW LEVEL SECURITY;

-- 9. Setup RLS Policies

-- Users Policies
DROP POLICY IF EXISTS "Users can read own profile." ON public.users;
CREATE POLICY "Users can read own profile." ON public.users
  FOR SELECT USING (id = auth.uid());

DROP POLICY IF EXISTS "Users can manage profiles based on permission." ON public.users;
CREATE POLICY "Users can manage profiles based on permission." ON public.users
  FOR ALL
  USING (
    public.is_real_admin() OR 
    (public.has_permission('perm_users') AND public.share_warehouse(auth.uid(), id))
  )
  WITH CHECK (
    public.is_real_admin() OR 
    (public.has_permission('perm_users') AND public.share_warehouse(auth.uid(), id))
  );

-- User Warehouses Policies
DROP POLICY IF EXISTS "Users can view own warehouse assignments." ON public.user_warehouses;
CREATE POLICY "Users can view own warehouse assignments." ON public.user_warehouses
  FOR SELECT USING (
    user_id = auth.uid() OR 
    public.is_real_admin() OR
    (public.has_permission('perm_users') AND public.share_warehouse(auth.uid(), user_id))
  );

DROP POLICY IF EXISTS "Admins and managers can manage warehouse assignments." ON public.user_warehouses;
CREATE POLICY "Admins and managers can manage warehouse assignments." ON public.user_warehouses
  FOR ALL USING (
    public.is_real_admin() OR
    (public.has_permission('perm_users') AND public.share_warehouse(auth.uid(), user_id))
  )
  WITH CHECK (
    public.is_real_admin() OR
    (public.has_permission('perm_users') AND public.share_warehouse(auth.uid(), user_id))
  );

-- Login History Policies
DROP POLICY IF EXISTS "Admins and managers can view login history." ON public.login_history;
CREATE POLICY "Admins and managers can view login history." ON public.login_history
  FOR SELECT USING (
    public.is_real_admin() OR
    (public.has_permission('perm_users') AND public.share_warehouse(auth.uid(), user_id))
  );

DROP POLICY IF EXISTS "System can insert login history." ON public.login_history;
CREATE POLICY "System can insert login history." ON public.login_history
  FOR INSERT WITH CHECK (true);

-- Activity Logs Policies
DROP POLICY IF EXISTS "Admins and managers can view activity logs." ON public.activity_logs;
CREATE POLICY "Admins and managers can view activity logs." ON public.activity_logs
  FOR SELECT USING (
    public.is_real_admin() OR
    public.has_permission('perm_users')
  );

DROP POLICY IF EXISTS "System can insert activity logs." ON public.activity_logs;
CREATE POLICY "System can insert activity logs." ON public.activity_logs
  FOR INSERT WITH CHECK (true);

-- Update Products Policies to use has_permission
DROP POLICY IF EXISTS "Admins can insert products." ON public.products;
CREATE POLICY "Admins can insert products." ON public.products
  FOR INSERT WITH CHECK (public.has_permission('perm_products'));

DROP POLICY IF EXISTS "Admins can update products." ON public.products;
CREATE POLICY "Admins can update products." ON public.products
  FOR UPDATE USING (public.has_permission('perm_products')) WITH CHECK (public.has_permission('perm_products'));

DROP POLICY IF EXISTS "Admins can delete products." ON public.products;
CREATE POLICY "Admins can delete products." ON public.products
  FOR DELETE USING (public.has_permission('perm_products'));

-- Update Orders Policies to use has_permission
DROP POLICY IF EXISTS "Users can view own orders or admins all." ON public.orders;
CREATE POLICY "Users can view own orders or admins all." ON public.orders
  FOR SELECT USING (customer_id = auth.uid() OR public.has_permission('perm_orders'));

DROP POLICY IF EXISTS "Admins can update orders." ON public.orders;
CREATE POLICY "Admins can update orders." ON public.orders
  FOR UPDATE USING (public.has_permission('perm_orders')) WITH CHECK (public.has_permission('perm_orders'));

-- Update Transactions Policies to use has_permission
DROP POLICY IF EXISTS "Admins can manage transactions." ON public.transactions;
CREATE POLICY "Admins can manage transactions." ON public.transactions
  FOR ALL USING (public.has_permission('perm_inventory')) WITH CHECK (public.has_permission('perm_inventory'));

-- Grant access on new tables
GRANT ALL PRIVILEGES ON TABLE public.user_warehouses TO service_role, authenticated;
GRANT ALL PRIVILEGES ON TABLE public.login_history TO service_role, authenticated;
GRANT ALL PRIVILEGES ON TABLE public.activity_logs TO service_role, authenticated;
