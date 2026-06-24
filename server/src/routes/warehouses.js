import express from 'express';
import { supabaseAdmin } from '../supabase.js';
import { authRequired, requireRole } from '../auth.js';

export const warehousesRouter = express.Router();

// Builds the per-warehouse stock summary (total qty, product/color counts),
// sorted by quantity desc. Shared by GET /warehouses/stock-summary and the
// aggregated GET /dashboard endpoint. Throws on a DB error.
export async function buildWarehouseStockSummary() {
  const warehousesRes = await supabaseAdmin
    .from('warehouses')
    .select('id,name,location,is_active')
    .eq('is_active', true)
    .order('name', { ascending: true });
  if (warehousesRes.error) throw new Error(warehousesRes.error.message);

  const stocksRes = await supabaseAdmin
    .from('warehouse_product_stocks')
    .select('warehouse_id,product_id,color_name,quantity')
    .gt('quantity', 0)
    .limit(10000);
  if (stocksRes.error) throw new Error(stocksRes.error.message);

  const summaryByWarehouse = new Map();
  for (const w of warehousesRes.data || []) {
    summaryByWarehouse.set(String(w.id), {
      warehouse_id: String(w.id),
      warehouse_name: String(w.name || 'Warehouse'),
      location: w.location || null,
      total_quantity: 0,
      product_ids: new Set(),
      color_keys: new Set(),
    });
  }

  for (const row of stocksRes.data || []) {
    const wid = String(row?.warehouse_id || '').trim();
    if (!summaryByWarehouse.has(wid)) continue;
    const entry = summaryByWarehouse.get(wid);
    const qty = Number(row?.quantity ?? 0);
    const safeQty = Number.isFinite(qty) ? Math.max(0, Math.trunc(qty)) : 0;
    entry.total_quantity += safeQty;
    const productId = String(row?.product_id || '').trim();
    if (productId) entry.product_ids.add(productId);
    const colorKey = `${productId}:${String(row?.color_name || '').trim().toLowerCase()}`;
    entry.color_keys.add(colorKey);
  }

  return [...summaryByWarehouse.values()]
    .map((entry) => ({
      warehouse_id: entry.warehouse_id,
      warehouse_name: entry.warehouse_name,
      location: entry.location,
      total_quantity: entry.total_quantity,
      product_count: entry.product_ids.size,
      color_count: entry.color_keys.size,
    }))
    .sort((a, b) => Number(b.total_quantity) - Number(a.total_quantity));
}

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
  const colorNameRaw = String(req.query?.color_name || '').trim();
  const hasColorFilter = colorNameRaw.length > 0;
  const colorName = colorNameRaw.toLowerCase();
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

  const byWarehouseQty = new Map();
  for (const row of rowsRes.data || []) {
    const rowColor = String(row?.color_name || '').trim().toLowerCase();
    if (hasColorFilter && rowColor !== colorName) continue;
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

warehousesRouter.get('/stock-summary', authRequired, async (_req, res) => {
  try {
    const data = await buildWarehouseStockSummary();
    return res.json({ data });
  } catch (e) {
    return res.status(400).json({ error: e.message });
  }
});

warehousesRouter.get('/:id/products', authRequired, async (req, res) => {
  const warehouseId = String(req.params.id || '').trim();
  if (!warehouseId) {
    return res.status(400).json({ error: 'warehouse id is required' });
  }

  const warehouseRes = await supabaseAdmin
    .from('warehouses')
    .select('id,name,is_active')
    .eq('id', warehouseId)
    .maybeSingle();
  if (warehouseRes.error) {
    return res.status(400).json({ error: warehouseRes.error.message });
  }
  if (!warehouseRes.data || warehouseRes.data.is_active !== true) {
    return res.status(404).json({ error: 'Warehouse not found or inactive' });
  }

  const stocksRes = await supabaseAdmin
    .from('warehouse_product_stocks')
    .select('product_id,quantity')
    .eq('warehouse_id', warehouseId)
    .gt('quantity', 0)
    .limit(10000);
  if (stocksRes.error) {
    return res.status(400).json({ error: stocksRes.error.message });
  }

  const qtyByProduct = new Map();
  for (const row of stocksRes.data || []) {
    const pid = String(row?.product_id || '').trim();
    if (!pid) continue;
    const qty = Number(row?.quantity ?? 0);
    const safeQty = Number.isFinite(qty) ? Math.max(0, Math.trunc(qty)) : 0;
    qtyByProduct.set(pid, (qtyByProduct.get(pid) || 0) + safeQty);
  }

  const data = [...qtyByProduct.entries()].map(([productId, quantity]) => ({
    product_id: productId,
    available_quantity: quantity,
  }));
  return res.json({ data });
});

warehousesRouter.get('/:id/colors', authRequired, async (req, res) => {
  const warehouseId = String(req.params.id || '').trim();
  const productId = String(req.query?.product_id || '').trim();
  if (!warehouseId) {
    return res.status(400).json({ error: 'warehouse id is required' });
  }
  if (!productId) {
    return res.status(400).json({ error: 'product_id is required' });
  }

  const rowsRes = await supabaseAdmin
    .from('warehouse_product_stocks')
    .select('color_name,quantity')
    .eq('warehouse_id', warehouseId)
    .eq('product_id', productId)
    .gt('quantity', 0)
    .limit(2000);
  if (rowsRes.error) {
    return res.status(400).json({ error: rowsRes.error.message });
  }

  const byColor = new Map();
  for (const row of rowsRes.data || []) {
    const rawColor = String(row?.color_name || '').trim();
    if (!rawColor) continue;
    const key = rawColor.toLowerCase();
    const qty = Number(row?.quantity ?? 0);
    const safeQty = Number.isFinite(qty) ? Math.max(0, Math.trunc(qty)) : 0;
    const prev = byColor.get(key);
    if (!prev) {
      byColor.set(key, { color_name: rawColor, available_quantity: safeQty });
    } else {
      prev.available_quantity += safeQty;
    }
  }

  const data = [...byColor.values()].sort((a, b) =>
    String(a.color_name).localeCompare(String(b.color_name)),
  );
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
    const locationUrl = String(payload.location_url || '').trim();

    if (!name) {
      return res.status(400).json({ error: 'name is required' });
    }

    const { data, error } = await supabaseAdmin
      .from('warehouses')
      .insert({
        name,
        code: code === '' ? null : code,
        location: location === '' ? null : location,
        location_url: locationUrl === '' ? null : locationUrl,
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
    if (typeof payload.location_url === 'string') {
      const locationUrl = payload.location_url.trim();
      updateRow.location_url = locationUrl === '' ? null : locationUrl;
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
