-- Supabase PostgreSQL Schema for B2B Stock Platform

-- 1. Enable UUID extension if not already enabled
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 2. ENUMS
DO $$ BEGIN
    CREATE TYPE user_role AS ENUM ('admin', 'manager', 'worker', 'customer');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE stock_status AS ENUM ('in_stock', 'low_stock', 'out_of_stock');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE order_status AS ENUM ('pending', 'confirmed', 'processing', 'shipped', 'delivered', 'cancelled');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE transaction_type AS ENUM ('stock_in', 'stock_out', 'adjustment');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- 3. TABLES

-- App Users (Profiles) linked to Supabase Auth
CREATE TABLE IF NOT EXISTS users (
  id UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
  name TEXT NOT NULL,
  email TEXT NOT NULL UNIQUE,
  role user_role DEFAULT 'worker',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Suppliers
CREATE TABLE IF NOT EXISTS suppliers (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL,
  contact_email TEXT,
  contact_phone TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Workers (For transaction logging, non-auth)
CREATE TABLE IF NOT EXISTS workers (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID UNIQUE REFERENCES users(id) ON DELETE SET NULL,
  name TEXT NOT NULL,
  email TEXT,
  role user_role DEFAULT 'worker',
  phone TEXT,
  can_access_stock BOOLEAN DEFAULT true,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE workers
  ADD COLUMN IF NOT EXISTS user_id UUID UNIQUE REFERENCES users(id) ON DELETE SET NULL;
ALTER TABLE workers
  ADD COLUMN IF NOT EXISTS role user_role DEFAULT 'worker';
ALTER TABLE workers
  ADD COLUMN IF NOT EXISTS can_access_stock BOOLEAN DEFAULT true;
ALTER TABLE workers
  ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT true;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'workers_role_allowed'
  ) THEN
    ALTER TABLE workers
      ADD CONSTRAINT workers_role_allowed CHECK (role IN ('worker', 'manager'));
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS idx_workers_phone_unique_nonnull
  ON workers (phone)
  WHERE phone IS NOT NULL;

-- OTP challenge records for worker phone login
CREATE TABLE IF NOT EXISTS worker_login_otps (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  worker_id UUID REFERENCES workers(id) ON DELETE CASCADE NOT NULL,
  phone TEXT NOT NULL,
  otp_hash TEXT NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0,
  consumed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_worker_login_otps_phone_created
  ON worker_login_otps (phone, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_worker_login_otps_worker_created
  ON worker_login_otps (worker_id, created_at DESC);

-- Notification device tokens (FCM)
CREATE TABLE IF NOT EXISTS notification_devices (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  token TEXT NOT NULL UNIQUE,
  platform TEXT NOT NULL DEFAULT 'android', -- android | ios | web
  app TEXT NOT NULL DEFAULT 'mobile', -- mobile | admin
  device_name TEXT,
  user_id UUID REFERENCES users(id) ON DELETE SET NULL,
  worker_id UUID REFERENCES workers(id) ON DELETE SET NULL,
  role user_role,
  is_active BOOLEAN NOT NULL DEFAULT true,
  last_seen TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_notification_devices_user_id
  ON notification_devices (user_id);
CREATE INDEX IF NOT EXISTS idx_notification_devices_worker_id
  ON notification_devices (worker_id);
CREATE INDEX IF NOT EXISTS idx_notification_devices_active
  ON notification_devices (is_active, updated_at DESC);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'notification_devices_platform_allowed'
  ) THEN
    ALTER TABLE notification_devices
      ADD CONSTRAINT notification_devices_platform_allowed
      CHECK (platform IN ('android', 'ios', 'web'));
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'notification_devices_app_allowed'
  ) THEN
    ALTER TABLE notification_devices
      ADD CONSTRAINT notification_devices_app_allowed
      CHECK (app IN ('mobile', 'admin'));
  END IF;
END $$;

-- Products
CREATE TABLE IF NOT EXISTS products (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL,
  code TEXT NOT NULL UNIQUE,
  category TEXT NOT NULL,
  quantity INTEGER DEFAULT 0 CHECK (quantity >= 0),
  threshold INTEGER DEFAULT 10,
  supplier_id UUID REFERENCES suppliers(id) ON DELETE SET NULL,
  price NUMERIC(10, 2) NOT NULL,
  cost_price NUMERIC(10, 2),
  image_url TEXT,
  images JSONB DEFAULT '[]'::jsonb, -- Array of { url, publicId }
  color_stocks JSONB DEFAULT '[]'::jsonb, -- Array of { color, quantity }
  unit TEXT,
  description TEXT,
  stock_status stock_status DEFAULT 'out_of_stock',
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Warehouses
CREATE TABLE IF NOT EXISTS warehouses (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL UNIQUE,
  code TEXT UNIQUE,
  location TEXT,
  location_url TEXT,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE warehouses
  ADD COLUMN IF NOT EXISTS location_url TEXT;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'warehouses_location_url_http'
  ) THEN
    ALTER TABLE warehouses
      ADD CONSTRAINT warehouses_location_url_http
      CHECK (
        location_url IS NULL
        OR location_url ~* '^https?://'
      );
  END IF;
END $$;

-- Warehouse-wise product/color stock
CREATE TABLE IF NOT EXISTS warehouse_product_stocks (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  warehouse_id UUID REFERENCES warehouses(id) ON DELETE CASCADE NOT NULL,
  product_id UUID REFERENCES products(id) ON DELETE CASCADE NOT NULL,
  color_name TEXT NOT NULL DEFAULT 'Default',
  quantity INTEGER NOT NULL DEFAULT 0 CHECK (quantity >= 0),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (warehouse_id, product_id, color_name)
);

-- Orders
CREATE TABLE IF NOT EXISTS orders (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  customer_id UUID REFERENCES users(id) ON DELETE SET NULL, -- Can be null for guest checkout
  customer_name TEXT NOT NULL,
  company_name TEXT,
  email TEXT NOT NULL,
  phone TEXT,
  shipping_address JSONB NOT NULL, -- { address1, address2, city, state, postalCode, country }
  items JSONB NOT NULL, -- Array of { id, name, quantity, price, total }
  subtotal NUMERIC(10, 2) NOT NULL,
  tax NUMERIC(10, 2) NOT NULL,
  total NUMERIC(10, 2) NOT NULL,
  total_quantity INTEGER NOT NULL,
  status order_status DEFAULT 'pending',
  payment_method TEXT NOT NULL,
  branding JSONB, -- { logoUrl, notes }
  notes TEXT,
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Transactions (Stock Logs)
CREATE TABLE IF NOT EXISTS transactions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  product_id UUID REFERENCES products(id) ON DELETE CASCADE NOT NULL,
  product_code TEXT,
  product_name TEXT NOT NULL,
  color_name TEXT NOT NULL DEFAULT 'Default',
  warehouse_id UUID REFERENCES warehouses(id) ON DELETE SET NULL,
  warehouse_name TEXT NOT NULL DEFAULT 'Main Warehouse',
  type transaction_type NOT NULL,
  quantity INTEGER NOT NULL CHECK (quantity > 0),
  worker_id UUID REFERENCES workers(id) ON DELETE SET NULL,
  worker_name TEXT NOT NULL,
  actor_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
  actor_role user_role,
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE transactions
  ADD COLUMN IF NOT EXISTS product_code TEXT;
ALTER TABLE transactions
  ADD COLUMN IF NOT EXISTS color_name TEXT DEFAULT 'Default';
ALTER TABLE transactions
  ADD COLUMN IF NOT EXISTS warehouse_id UUID REFERENCES warehouses(id) ON DELETE SET NULL;
ALTER TABLE transactions
  ADD COLUMN IF NOT EXISTS warehouse_name TEXT DEFAULT 'Main Warehouse';
ALTER TABLE transactions
  ADD COLUMN IF NOT EXISTS actor_user_id UUID REFERENCES users(id) ON DELETE SET NULL;
ALTER TABLE transactions
  ADD COLUMN IF NOT EXISTS actor_role user_role;

UPDATE transactions
SET color_name = 'Default'
WHERE color_name IS NULL OR btrim(color_name) = '';
UPDATE transactions
SET warehouse_name = 'Main Warehouse'
WHERE warehouse_name IS NULL OR btrim(warehouse_name) = '';

ALTER TABLE transactions
  ALTER COLUMN color_name SET NOT NULL;
ALTER TABLE transactions
  ALTER COLUMN warehouse_name SET NOT NULL;

ALTER TABLE products
  ADD COLUMN IF NOT EXISTS color_stocks JSONB DEFAULT '[]'::jsonb;

INSERT INTO warehouses (name, code, location, is_active)
SELECT 'Main Warehouse', 'MAIN', 'Primary Location', true
WHERE NOT EXISTS (SELECT 1 FROM warehouses);

UPDATE transactions t
SET warehouse_id = w.id
FROM warehouses w
WHERE (t.warehouse_id IS NULL)
  AND lower(w.name) = 'main warehouse';

WITH main_warehouse AS (
  SELECT id
  FROM warehouses
  WHERE lower(name) = 'main warehouse'
  LIMIT 1
),
color_rows AS (
  SELECT
    p.id AS product_id,
    COALESCE(NULLIF(btrim(cs.value->>'color'), ''), 'Default') AS color_name,
    GREATEST(0, COALESCE((cs.value->>'quantity')::INTEGER, 0)) AS quantity
  FROM products p
  CROSS JOIN LATERAL jsonb_array_elements(
    CASE
      WHEN jsonb_typeof(p.color_stocks) = 'array' THEN p.color_stocks
      ELSE '[]'::jsonb
    END
  ) AS cs(value)
),
fallback_rows AS (
  SELECT
    p.id AS product_id,
    'Default'::TEXT AS color_name,
    GREATEST(0, p.quantity) AS quantity
  FROM products p
  WHERE COALESCE(jsonb_array_length(p.color_stocks), 0) = 0
),
combined AS (
  SELECT product_id, color_name, SUM(quantity)::INTEGER AS quantity
  FROM (
    SELECT * FROM color_rows
    UNION ALL
    SELECT * FROM fallback_rows
  ) s
  GROUP BY product_id, color_name
)
INSERT INTO warehouse_product_stocks (
  warehouse_id,
  product_id,
  color_name,
  quantity,
  updated_at
)
SELECT
  mw.id,
  c.product_id,
  c.color_name,
  c.quantity,
  NOW()
FROM combined c
CROSS JOIN main_warehouse mw
WHERE c.quantity > 0
ON CONFLICT (warehouse_id, product_id, color_name) DO NOTHING;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'transactions_quantity_positive'
  ) THEN
    ALTER TABLE transactions
      ADD CONSTRAINT transactions_quantity_positive CHECK (quantity > 0);
  END IF;
END $$;

-- 4. ROW LEVEL SECURITY (RLS) POLICIES
-- Enable RLS on all tables
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE workers ENABLE ROW LEVEL SECURITY;
ALTER TABLE notification_devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE warehouses ENABLE ROW LEVEL SECURITY;
ALTER TABLE warehouse_product_stocks ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE transactions ENABLE ROW LEVEL SECURITY;

-- Users: signed-in users can read their own profile, admins/managers can manage all
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.users WHERE id = auth.uid() AND role IN ('admin', 'manager')
  );
$$ LANGUAGE sql SECURITY DEFINER;

DROP POLICY IF EXISTS "Users can read own profile." ON users;
CREATE POLICY "Users can read own profile." ON users
FOR SELECT
USING (id = auth.uid());

DROP POLICY IF EXISTS "Admins can read all users." ON users;
CREATE POLICY "Admins can read all users." ON users
FOR SELECT
USING (public.is_admin());

DROP POLICY IF EXISTS "Admins can modify users." ON users;
CREATE POLICY "Admins can modify users." ON users
FOR ALL
USING (public.is_admin())
WITH CHECK (public.is_admin());

-- Suppliers: admins/managers can read and modify
DROP POLICY IF EXISTS "Admins can manage suppliers." ON suppliers;
CREATE POLICY "Admins can manage suppliers." ON suppliers
FOR ALL
USING (public.is_admin())
WITH CHECK (public.is_admin());

-- Workers: admins/managers can read and modify
DROP POLICY IF EXISTS "Admins can manage workers." ON workers;
CREATE POLICY "Admins can manage workers." ON workers
FOR ALL
USING (public.is_admin())
WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "Admins can manage notification devices." ON notification_devices;
CREATE POLICY "Admins can manage notification devices." ON notification_devices
FOR ALL
USING (public.is_admin())
WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "Users can read warehouses." ON warehouses;
CREATE POLICY "Users can read warehouses." ON warehouses
FOR SELECT
USING (true);

DROP POLICY IF EXISTS "Admins can manage warehouses." ON warehouses;
CREATE POLICY "Admins can manage warehouses." ON warehouses
FOR ALL
USING (public.is_admin())
WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "Users can read warehouse stocks." ON warehouse_product_stocks;
CREATE POLICY "Users can read warehouse stocks." ON warehouse_product_stocks
FOR SELECT
USING (true);

DROP POLICY IF EXISTS "Admins can manage warehouse stocks." ON warehouse_product_stocks;
CREATE POLICY "Admins can manage warehouse stocks." ON warehouse_product_stocks
FOR ALL
USING (public.is_admin())
WITH CHECK (public.is_admin());

-- Products: everyone can read, only admin/manager can modify
DROP POLICY IF EXISTS "Public products are viewable by everyone." ON products;
CREATE POLICY "Public products are viewable by everyone." ON products
FOR SELECT
USING (true);

DROP POLICY IF EXISTS "Admins can insert products." ON products;
CREATE POLICY "Admins can insert products." ON products
FOR INSERT
WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "Admins can update products." ON products;
CREATE POLICY "Admins can update products." ON products
FOR UPDATE
USING (public.is_admin())
WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "Admins can delete products." ON products;
CREATE POLICY "Admins can delete products." ON products
FOR DELETE
USING (public.is_admin());

-- Orders: Users can read their own, admins can read all, anyone can insert (checkout)
DROP POLICY IF EXISTS "Anyone can insert orders." ON orders;
CREATE POLICY "Anyone can insert orders." ON orders FOR INSERT WITH CHECK (true);

DROP POLICY IF EXISTS "Users can view own orders or admins all." ON orders;
CREATE POLICY "Users can view own orders or admins all." ON orders FOR SELECT USING (
  customer_id = auth.uid() OR public.is_admin()
);

DROP POLICY IF EXISTS "Admins can update orders." ON orders;
CREATE POLICY "Admins can update orders." ON orders
FOR UPDATE
USING (public.is_admin())
WITH CHECK (public.is_admin());

-- Transactions: admins/managers can read and modify
DROP POLICY IF EXISTS "Admins can manage transactions." ON transactions;
CREATE POLICY "Admins can manage transactions." ON transactions
FOR ALL
USING (public.is_admin())
WITH CHECK (public.is_admin());

-- 5. TRIGGERS
-- Trigger to automatically update stock_status based on quantity & threshold
CREATE OR REPLACE FUNCTION update_product_stock_status()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.quantity <= 0 THEN
    NEW.stock_status = 'out_of_stock'::stock_status;
  ELSIF NEW.quantity <= NEW.threshold THEN
    NEW.stock_status = 'low_stock'::stock_status;
  ELSE
    NEW.stock_status = 'in_stock'::stock_status;
  END IF;
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_update_stock_status ON products;
CREATE TRIGGER trigger_update_stock_status
BEFORE INSERT OR UPDATE OF quantity ON products
FOR EACH ROW
EXECUTE FUNCTION update_product_stock_status();

-- Trigger: When transaction inserted, update product quantity
CREATE OR REPLACE FUNCTION prepare_transaction_defaults()
RETURNS TRIGGER AS $$
DECLARE
  product_row products%ROWTYPE;
  worker_row workers%ROWTYPE;
  user_row users%ROWTYPE;
  warehouse_row warehouses%ROWTYPE;
BEGIN
  IF NEW.quantity IS NULL OR NEW.quantity <= 0 THEN
    RAISE EXCEPTION 'Transaction quantity must be > 0';
  END IF;

  SELECT * INTO product_row
  FROM products
  WHERE id = NEW.product_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Product not found for id %', NEW.product_id;
  END IF;

  NEW.product_name := COALESCE(NULLIF(NEW.product_name, ''), product_row.name);
  NEW.product_code := COALESCE(NULLIF(NEW.product_code, ''), product_row.code);
  NEW.color_name := COALESCE(NULLIF(btrim(NEW.color_name), ''), 'Default');
  NEW.warehouse_name := COALESCE(NULLIF(btrim(NEW.warehouse_name), ''), 'Main Warehouse');

  IF NEW.warehouse_id IS NOT NULL THEN
    SELECT * INTO warehouse_row
    FROM warehouses
    WHERE id = NEW.warehouse_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Warehouse not found for id %', NEW.warehouse_id;
    END IF;

    IF warehouse_row.is_active IS DISTINCT FROM true THEN
      RAISE EXCEPTION 'Warehouse % is inactive', warehouse_row.name;
    END IF;

    NEW.warehouse_name := COALESCE(NULLIF(NEW.warehouse_name, ''), warehouse_row.name);
  ELSE
    SELECT * INTO warehouse_row
    FROM warehouses
    WHERE is_active = true
    ORDER BY created_at ASC
    LIMIT 1;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'No active warehouse found';
    END IF;

    NEW.warehouse_id := warehouse_row.id;
    NEW.warehouse_name := warehouse_row.name;
  END IF;

  IF NEW.actor_user_id IS NOT NULL THEN
    SELECT * INTO user_row
    FROM users
    WHERE id = NEW.actor_user_id;

    IF FOUND THEN
      NEW.actor_role := COALESCE(NEW.actor_role, user_row.role);
      NEW.worker_name := COALESCE(NULLIF(NEW.worker_name, ''), user_row.name);
    END IF;
  END IF;

  IF NEW.worker_id IS NOT NULL THEN
    SELECT * INTO worker_row
    FROM workers
    WHERE id = NEW.worker_id;

    IF FOUND THEN
      NEW.worker_name := COALESCE(NULLIF(NEW.worker_name, ''), worker_row.name);
      IF NEW.actor_user_id IS NULL THEN
        NEW.actor_user_id := worker_row.user_id;
      END IF;
    END IF;
  END IF;

  NEW.worker_name := COALESCE(NULLIF(NEW.worker_name, ''), 'System');

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_prepare_transaction_defaults ON transactions;
CREATE TRIGGER trigger_prepare_transaction_defaults
BEFORE INSERT ON transactions
FOR EACH ROW
EXECUTE FUNCTION prepare_transaction_defaults();

-- Apply stock movement atomically and prevent negative stock at DB level.
CREATE OR REPLACE FUNCTION update_product_quantity_from_transaction()
RETURNS TRIGGER AS $$
DECLARE
  current_qty INTEGER;
  current_color_stocks JSONB;
  current_warehouse_qty INTEGER;
  selected_color TEXT;
  selected_color_normalized TEXT;
  item JSONB;
  item_color TEXT;
  item_color_normalized TEXT;
  item_qty INTEGER;
  updated_color_stocks JSONB := '[]'::jsonb;
  color_found BOOLEAN := FALSE;
BEGIN
  selected_color := COALESCE(NULLIF(btrim(NEW.color_name), ''), 'Default');
  selected_color_normalized := lower(selected_color);

  SELECT quantity, COALESCE(color_stocks, '[]'::jsonb)
  INTO current_qty, current_color_stocks
  FROM products
  WHERE id = NEW.product_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Product not found for id %', NEW.product_id;
  END IF;

  IF NEW.warehouse_id IS NULL THEN
    RAISE EXCEPTION 'Warehouse is required for stock transactions';
  END IF;

  SELECT quantity
  INTO current_warehouse_qty
  FROM warehouse_product_stocks
  WHERE warehouse_id = NEW.warehouse_id
    AND product_id = NEW.product_id
    AND color_name = selected_color
  FOR UPDATE;

  IF NEW.type = 'stock_in' THEN
    FOR item IN SELECT value FROM jsonb_array_elements(current_color_stocks)
    LOOP
      item_color := btrim(COALESCE(item->>'color', ''));
      item_color_normalized := lower(item_color);
      item_qty := GREATEST(0, COALESCE((item->>'quantity')::INTEGER, 0));

      IF item_color_normalized = selected_color_normalized THEN
        item_qty := item_qty + NEW.quantity;
        color_found := TRUE;
      END IF;

      IF item_color <> '' THEN
        updated_color_stocks := updated_color_stocks || jsonb_build_array(
          jsonb_build_object('color', item_color, 'quantity', item_qty)
        );
      END IF;
    END LOOP;

    IF NOT color_found AND selected_color <> 'Default' THEN
      updated_color_stocks := updated_color_stocks || jsonb_build_array(
        jsonb_build_object('color', selected_color, 'quantity', NEW.quantity)
      );
    END IF;

    UPDATE products
    SET quantity = current_qty + NEW.quantity,
        color_stocks = updated_color_stocks
    WHERE id = NEW.product_id;

    INSERT INTO warehouse_product_stocks (
      warehouse_id,
      product_id,
      color_name,
      quantity,
      updated_at
    )
    VALUES (
      NEW.warehouse_id,
      NEW.product_id,
      selected_color,
      NEW.quantity,
      NOW()
    )
    ON CONFLICT (warehouse_id, product_id, color_name)
    DO UPDATE
      SET quantity = warehouse_product_stocks.quantity + EXCLUDED.quantity,
          updated_at = NOW();
  ELSIF NEW.type = 'stock_out' THEN
    IF current_qty < NEW.quantity THEN
      RAISE EXCEPTION 'Insufficient stock for product %, have %, requested %',
        NEW.product_id, current_qty, NEW.quantity;
    END IF;

    FOR item IN SELECT value FROM jsonb_array_elements(current_color_stocks)
    LOOP
      item_color := btrim(COALESCE(item->>'color', ''));
      item_color_normalized := lower(item_color);
      item_qty := GREATEST(0, COALESCE((item->>'quantity')::INTEGER, 0));

      IF item_color_normalized = selected_color_normalized THEN
        IF item_qty < NEW.quantity THEN
          RAISE EXCEPTION 'Insufficient color stock for product %, color %, have %, requested %',
            NEW.product_id, selected_color, item_qty, NEW.quantity;
        END IF;
        item_qty := item_qty - NEW.quantity;
        color_found := TRUE;
      END IF;

      IF item_color <> '' THEN
        updated_color_stocks := updated_color_stocks || jsonb_build_array(
          jsonb_build_object('color', item_color, 'quantity', item_qty)
        );
      END IF;
    END LOOP;

    IF selected_color_normalized <> 'default' AND NOT color_found THEN
      RAISE EXCEPTION 'Color % not found for product %', selected_color, NEW.product_id;
    END IF;

    UPDATE products
    SET quantity = current_qty - NEW.quantity,
        color_stocks = updated_color_stocks
    WHERE id = NEW.product_id;

    IF current_warehouse_qty IS NULL THEN
      RAISE EXCEPTION 'No stock found in warehouse % for product % color %',
        NEW.warehouse_id, NEW.product_id, selected_color;
    END IF;

    IF current_warehouse_qty < NEW.quantity THEN
      RAISE EXCEPTION 'Insufficient warehouse stock for warehouse %, product %, color %, have %, requested %',
        NEW.warehouse_id, NEW.product_id, selected_color, current_warehouse_qty, NEW.quantity;
    END IF;

    UPDATE warehouse_product_stocks
    SET quantity = current_warehouse_qty - NEW.quantity,
        updated_at = NOW()
    WHERE warehouse_id = NEW.warehouse_id
      AND product_id = NEW.product_id
      AND color_name = selected_color;
  ELSIF NEW.type = 'adjustment' THEN
    -- Reserved for future logic. Keep current behavior explicit and safe.
    RAISE EXCEPTION 'Adjustment transactions must be handled by dedicated workflow';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_stock_transaction ON transactions;
CREATE TRIGGER trigger_stock_transaction
AFTER INSERT ON transactions
FOR EACH ROW
EXECUTE FUNCTION update_product_quantity_from_transaction();

CREATE INDEX IF NOT EXISTS idx_transactions_created_at
  ON transactions (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_transactions_product_id_created_at
  ON transactions (product_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_transactions_worker_id_created_at
  ON transactions (worker_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_transactions_product_color_created_at
  ON transactions (product_id, color_name, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_transactions_warehouse_created_at
  ON transactions (warehouse_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_warehouse_product_stocks_lookup
  ON warehouse_product_stocks (warehouse_id, product_id, color_name);
CREATE INDEX IF NOT EXISTS idx_workers_user_id
  ON workers (user_id);

-- Trigger: Automatically create a user profile when a new user signs up in auth.users
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.users (id, name, email, role)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'name', NEW.email, 'User'),
    NEW.email,
    'worker' -- default role
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Keep workers table in sync with app users for stock transaction FK integrity.
CREATE OR REPLACE FUNCTION public.sync_worker_from_user()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE public.workers
  SET name = NEW.name,
      email = NEW.email
  WHERE user_id = NEW.id;

  IF NOT FOUND THEN
    UPDATE public.workers
    SET user_id = NEW.id,
        name = NEW.name
    WHERE email = NEW.email
      AND user_id IS NULL;
  END IF;

  IF NOT FOUND THEN
    INSERT INTO public.workers (user_id, name, email)
    VALUES (NEW.id, NEW.name, NEW.email);
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_user_profile_upsert_worker ON public.users;
CREATE TRIGGER on_user_profile_upsert_worker
  AFTER INSERT OR UPDATE OF name, email ON public.users
  FOR EACH ROW EXECUTE FUNCTION public.sync_worker_from_user();

-- 5.5 Cascade Product Name/Code Changes to Transactions
CREATE OR REPLACE FUNCTION public.cascade_product_changes_to_transactions()
RETURNS TRIGGER AS $$
BEGIN
  IF (OLD.name IS DISTINCT FROM NEW.name OR OLD.code IS DISTINCT FROM NEW.code) THEN
    UPDATE public.transactions
    SET 
      product_name = NEW.name,
      product_code = NEW.code
    WHERE product_id = NEW.id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_cascade_product_changes ON public.products;
CREATE TRIGGER trg_cascade_product_changes
  AFTER UPDATE OF name, code ON public.products
  FOR EACH ROW
  EXECUTE FUNCTION public.cascade_product_changes_to_transactions();

-- 6. PERMISSIONS (GRANTS)
-- Note: RLS still applies for anon/authenticated; service_role bypasses RLS but needs table privileges.
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO service_role;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO service_role;

-- Optional defaults for future tables
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON TABLES TO service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON SEQUENCES TO service_role;
