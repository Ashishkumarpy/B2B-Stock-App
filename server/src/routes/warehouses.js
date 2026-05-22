import express from 'express';
import { supabaseAdmin } from '../supabase.js';
import { authRequired, requireRole } from '../auth.js';

export const warehousesRouter = express.Router();

warehousesRouter.get('/', authRequired, async (_req, res) => {
  const includeInactive =
    String(_req.query?.include_inactive || '').trim().toLowerCase() === 'true';
  let query = supabaseAdmin
    .from('warehouses')
    .select('*')
    .order('name', { ascending: true });
  if (!includeInactive) {
    query = query.eq('is_active', true);
  }
  const { data, error } = await query;
  if (error) return res.status(500).json({ error: error.message });
  return res.json({ data });
});

warehousesRouter.get('/stock-options', authRequired, async (req, res) => {
  const productId = String(req.query?.product_id || '').trim();
  const colorName = String(req.query?.color_name || '').trim() || 'Default';
  if (!productId) {
    return res.status(400).json({ error: 'product_id is required' });
  }

  const rowsRes = await supabaseAdmin
    .from('warehouse_product_stocks')
    .select('warehouse_id,color_name,quantity')
    .eq('product_id', productId)
    .limit(2000);
  if (rowsRes.error) {
    return res.status(400).json({ error: rowsRes.error.message });
  }

  const targetColor = colorName.toLowerCase();
  const byWarehouseQty = new Map();
  for (const row of rowsRes.data || []) {
    const rowColor = String(row?.color_name || '').trim().toLowerCase();
    if (rowColor !== targetColor) continue;
    const wid = String(row?.warehouse_id || '').trim();
    if (!wid) continue;
    const qty = Number(row?.quantity ?? 0);
    const safeQty = Number.isFinite(qty) ? Math.max(0, Math.trunc(qty)) : 0;
    byWarehouseQty.set(wid, (byWarehouseQty.get(wid) || 0) + safeQty);
  }

  const warehouseIds = [...byWarehouseQty.keys()];
  if (warehouseIds.length === 0) {
    return res.json({ data: [] });
  }

  const activeWarehousesRes = await supabaseAdmin
    .from('warehouses')
    .select('id,name,location,is_active')
    .in('id', warehouseIds)
    .eq('is_active', true)
    .order('name', { ascending: true });
  if (activeWarehousesRes.error) {
    return res.status(400).json({ error: activeWarehousesRes.error.message });
  }

  const data = (activeWarehousesRes.data || []).map((w) => {
    const id = String(w.id);
    return {
      warehouse_id: id,
      warehouse_name: String(w.name || 'Warehouse'),
      location: w.location || null,
      available_quantity: byWarehouseQty.get(id) || 0,
    };
  }).filter((row) => Number(row.available_quantity) > 0);

  return res.json({ data });
});

warehousesRouter.post(
  '/',
  authRequired,
  requireRole(['admin', 'manager']),
  async (req, res) => {
    const payload = req.body || {};
    const name = String(payload.name || '').trim();
    const code = String(payload.code || '').trim();
    const location = String(payload.location || '').trim();

    if (!name) {
      return res.status(400).json({ error: 'name is required' });
    }

    const { data, error } = await supabaseAdmin
      .from('warehouses')
      .insert({
        name,
        code: code === '' ? null : code,
        location: location === '' ? null : location,
        is_active: true
      })
      .select('*')
      .single();

    if (error) return res.status(400).json({ error: error.message });
    return res.json({ data });
  }
);

warehousesRouter.put(
  '/:id',
  authRequired,
  requireRole(['admin', 'manager']),
  async (req, res) => {
    const id = req.params.id;
    const payload = req.body || {};
    const updateRow = {};

    if (typeof payload.name === 'string') {
      updateRow.name = payload.name.trim();
    }
    if (typeof payload.code === 'string') {
      const code = payload.code.trim();
      updateRow.code = code === '' ? null : code;
    }
    if (typeof payload.location === 'string') {
      const location = payload.location.trim();
      updateRow.location = location === '' ? null : location;
    }
    if (typeof payload.is_active === 'boolean') {
      updateRow.is_active = payload.is_active;
    }

    const { data, error } = await supabaseAdmin
      .from('warehouses')
      .update(updateRow)
      .eq('id', id)
      .select('*')
      .single();

    if (error) return res.status(400).json({ error: error.message });
    return res.json({ data });
  }
);
