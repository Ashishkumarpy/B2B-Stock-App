import express from 'express';
import { supabaseAdmin } from '../supabase.js';
import { authRequired, requirePermission } from '../auth.js';
import { logActivity } from '../activity_logger.js';

export const productsRouter = express.Router();

productsRouter.get('/', authRequired, async (req, res) => {
  const limit = parseInt(req.query.limit) || 1000;
  const page = parseInt(req.query.page) || 1;
  const offset = (page - 1) * limit;

  const { data, error } = await supabaseAdmin
    .from('products')
    .select('*')
    .order('name', { ascending: true })
    .range(offset, offset + limit - 1);

  if (error) return res.status(500).json({ error: error.message });
  return res.json({ data });
});

productsRouter.get('/:id/stock-distribution', authRequired, async (req, res) => {
  const productId = req.params.id;
  if (!productId) {
    return res.status(400).json({ error: 'id parameter is required' });
  }
  
  const [warehousesRes, stocksRes] = await Promise.all([
    supabaseAdmin
      .from('warehouses')
      .select('id,name,location')
      .eq('is_active', true),
    supabaseAdmin
      .from('warehouse_product_stocks')
      .select('warehouse_id,color_name,quantity')
      .eq('product_id', productId)
      .gt('quantity', 0)
      .limit(10000)
  ]);

  if (warehousesRes.error) {
    return res.status(400).json({ error: warehousesRes.error.message });
  }
  if (stocksRes.error) {
    return res.status(400).json({ error: stocksRes.error.message });
  }

  const warehouseMap = new Map(
    (warehousesRes.data || []).map((w) => [String(w.id), w])
  );

  const distribution = (stocksRes.data || [])
    .filter((row) => warehouseMap.has(String(row.warehouse_id)))
    .map((row) => {
      const w = warehouseMap.get(String(row.warehouse_id));
      return {
        warehouse_id: row.warehouse_id,
        warehouse_name: w.name,
        location: w.location || null,
        color_name: row.color_name,
        quantity: row.quantity
      };
    });

  return res.json({ data: distribution });
});


productsRouter.post('/', authRequired, requirePermission('perm_products'), async (req, res) => {
  const payload = req.body || {};
  const { data, error } = await supabaseAdmin.from('products').insert(payload).select('*').single();
  if (error) return res.status(400).json({ error: error.message });

  await logActivity({
    actorId: req.session.sub,
    actorName: req.session.name,
    actionType: 'product_create',
    description: `Created product ${data.name} (Code: ${data.code})`,
    metadata: { product_id: data.id, product_name: data.name, price: data.price }
  });

  return res.json({ data });
});

productsRouter.put('/:id', authRequired, requirePermission('perm_products'), async (req, res) => {
  const id = req.params.id;
  const payload = req.body || {};
  const hasColorStocksUpdate = Object.prototype.hasOwnProperty.call(payload, 'color_stocks');
  const { data, error } = await supabaseAdmin
    .from('products')
    .update(payload)
    .eq('id', id)
    .select('*')
    .single();
    
  if (error) return res.status(400).json({ error: error.message });

  await logActivity({
    actorId: req.session.sub,
    actorName: req.session.name,
    actionType: 'product_edit',
    description: `Edited product ${data.name} (Code: ${data.code})`,
    metadata: { product_id: id, product_name: data.name, updated_fields: Object.keys(payload) }
  });

  // Auto-sync renamed colors across warehouse rows + transactions.
  if (hasColorStocksUpdate) {
    const canonicalColors = Array.isArray(data?.color_stocks)
      ? data.color_stocks
          .map((entry) => String(entry?.color || '').trim())
          .filter(Boolean)
      : [];
    const canonicalByLower = new Map(
      canonicalColors.map((name) => [name.toLowerCase(), name]),
    );

    const resolveCanonicalColor = (rawColor) => {
      const current = String(rawColor || '').trim() || 'Default';
      const currentLc = current.toLowerCase();
      if (canonicalByLower.has(currentLc)) {
        return canonicalByLower.get(currentLc);
      }
      if (canonicalColors.length === 1) {
        return canonicalColors[0];
      }
      if (current.length === 1) {
        const shortLc = currentLc;
        const matches = canonicalColors.filter(
          (c) => c.toLowerCase().startsWith(shortLc),
        );
        if (matches.length === 1) {
          return matches[0];
        }
      }
      return current;
    };

    const existingWarehouseRows = await supabaseAdmin
      .from('warehouse_product_stocks')
      .select('id,warehouse_id,product_id,color_name,quantity')
      .eq('product_id', id)
      .limit(10000);
    if (!existingWarehouseRows.error && Array.isArray(existingWarehouseRows.data)) {
      const aggregated = new Map();
      for (const row of existingWarehouseRows.data) {
        const warehouseId = String(row?.warehouse_id || '').trim();
        const productId = String(row?.product_id || '').trim();
        if (!warehouseId || !productId) continue;
        const canonicalColor = resolveCanonicalColor(row?.color_name);
        const key = `${warehouseId}::${productId}::${canonicalColor}`;
        const qty = Number(row?.quantity ?? 0);
        const safeQty = Number.isFinite(qty) ? Math.max(0, Math.trunc(qty)) : 0;
        aggregated.set(key, (aggregated.get(key) || 0) + safeQty);
      }

      // Replace per-product warehouse rows with canonical merged rows.
      await supabaseAdmin
        .from('warehouse_product_stocks')
        .delete()
        .eq('product_id', id);

      const upsertRows = [...aggregated.entries()].map(([key, quantity]) => {
        const [warehouse_id, product_id, color_name] = key.split('::');
        return {
          warehouse_id,
          product_id,
          color_name,
          quantity,
          updated_at: new Date().toISOString(),
        };
      });

      if (upsertRows.length > 0) {
        await supabaseAdmin
          .from('warehouse_product_stocks')
          .upsert(upsertRows, { onConflict: 'warehouse_id,product_id,color_name' });
      }
    }

    // Best-effort color canonicalization for product transaction history.
    const txRes = await supabaseAdmin
      .from('transactions')
      .select('id,color_name')
      .eq('product_id', id)
      .limit(10000);
    if (!txRes.error && Array.isArray(txRes.data) && txRes.data.length > 0) {
      const updates = txRes.data
        .map((tx) => {
          const nextColor = resolveCanonicalColor(tx?.color_name);
          const currentColor = String(tx?.color_name || '').trim() || 'Default';
          if (nextColor === currentColor) return null;
          return { id: tx.id, color_name: nextColor };
        })
        .filter(Boolean);
      if (updates.length > 0) {
        await supabaseAdmin.from('transactions').upsert(updates, { onConflict: 'id' });
      }
    }
  }

  // Cascade name/code changes to transactions history if they were updated
  if (payload.name !== undefined || payload.code !== undefined) {
    const transactionUpdates = {};
    if (payload.name !== undefined) {
      transactionUpdates.product_name = payload.name;
    }
    if (payload.code !== undefined) {
      transactionUpdates.product_code = payload.code;
    }

    // Best-effort update, ignore errors so product edit doesn't fail
    await supabaseAdmin
      .from('transactions')
      .update(transactionUpdates)
      .eq('product_id', id);
  }

  return res.json({ data });
});

productsRouter.delete('/:id', authRequired, requirePermission('perm_products'), async (req, res) => {
  const id = req.params.id;

  try {
    // 1. Fetch product to get image public IDs before deleting
    const { data: product, error: fetchError } = await supabaseAdmin
      .from('products')
      .select('name, code, images')
      .eq('id', id)
      .single();

    if (product && !fetchError) {
      const publicIds = (product.images || [])
        .map((img) => img.publicId)
        .filter(Boolean);

      if (publicIds.length > 0) {
        const { deleteImage } = await import('../cloudinary.js');
        // Delete images in parallel
        await Promise.allSettled(publicIds.map((pid) => deleteImage(pid)));
      }
    }

    // 2. Delete from DB
    const { error } = await supabaseAdmin.from('products').delete().eq('id', id);
    if (error) return res.status(400).json({ error: error.message });

    await logActivity({
      actorId: req.session.sub,
      actorName: req.session.name,
      actionType: 'product_delete',
      description: `Deleted product ${product?.name || 'Unknown'} (Code: ${product?.code || 'Unknown'})`,
      metadata: { product_id: id, product_name: product?.name }
    });

    return res.json({ ok: true });
  } catch (err) {
    console.error('Product deletion error:', err);
    return res.status(500).json({ error: 'Internal server error during deletion' });
  }
});
