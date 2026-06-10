import express from 'express';
import { supabaseAdmin } from '../supabase.js';
import { authRequired, requirePermission } from '../auth.js';
import { logActivity } from '../activity_logger.js';

export const productsRouter = express.Router();

function normalizeColorName(value, fallback = 'Default') {
  const normalized = String(value || '').trim();
  return normalized || fallback;
}

function colorNamesFromStocks(colorStocks) {
  return Array.isArray(colorStocks)
    ? colorStocks
        .map((entry) => normalizeColorName(entry?.color, ''))
        .filter(Boolean)
    : [];
}

function buildColorRenameMap(previousColorStocks, nextColorStocks) {
  const previousColors = colorNamesFromStocks(previousColorStocks);
  const nextColors = colorNamesFromStocks(nextColorStocks);
  const nextByLower = new Map(nextColors.map((name) => [name.toLowerCase(), name]));
  const renameMap = new Map();

  for (const previousColor of previousColors) {
    const previousKey = previousColor.toLowerCase();
    const exactNext = nextByLower.get(previousKey);
    if (exactNext && exactNext !== previousColor) {
      renameMap.set(previousKey, exactNext);
    }
  }

  const commonLength = Math.min(previousColors.length, nextColors.length);
  for (let idx = 0; idx < commonLength; idx += 1) {
    const previousColor = previousColors[idx];
    const nextColor = nextColors[idx];
    if (
      previousColor &&
      nextColor &&
      previousColor.toLowerCase() !== nextColor.toLowerCase()
    ) {
      renameMap.set(previousColor.toLowerCase(), nextColor);
    }
  }

  const removedColors = previousColors.filter(
    (color) => !nextByLower.has(color.toLowerCase()),
  );
  const previousByLower = new Map(
    previousColors.map((name) => [name.toLowerCase(), name]),
  );
  const addedColors = nextColors.filter(
    (color) => !previousByLower.has(color.toLowerCase()),
  );
  if (removedColors.length === 1 && addedColors.length === 1) {
    renameMap.set(removedColors[0].toLowerCase(), addedColors[0]);
  }

  return renameMap;
}

function makeColorResolver(previousColorStocks, nextColorStocks) {
  const nextColors = colorNamesFromStocks(nextColorStocks);
  const nextByLower = new Map(nextColors.map((name) => [name.toLowerCase(), name]));
  const renameMap = buildColorRenameMap(previousColorStocks, nextColorStocks);

  return (rawColor) => {
    const current = normalizeColorName(rawColor);
    const currentLc = current.toLowerCase();
    if (renameMap.has(currentLc)) {
      return renameMap.get(currentLc);
    }
    if (nextByLower.has(currentLc)) {
      return nextByLower.get(currentLc);
    }
    if (nextColors.length === 1) {
      return nextColors[0];
    }
    if (current.length === 1) {
      const matches = nextColors.filter((color) =>
        color.toLowerCase().startsWith(currentLc),
      );
      if (matches.length === 1) {
        return matches[0];
      }
    }
    return current;
  };
}

function aggregateWarehouseStockRows(rows, resolveColor) {
  const aggregated = new Map();
  for (const row of rows) {
    const warehouseId = String(row?.warehouse_id || '').trim();
    const productId = String(row?.product_id || '').trim();
    if (!warehouseId || !productId) continue;

    const colorName = resolveColor(row?.color_name);
    const key = `${warehouseId}::${productId}::${colorName.toLowerCase()}`;
    const qty = Number(row?.quantity ?? 0);
    const safeQty = Number.isFinite(qty) ? Math.max(0, Math.trunc(qty)) : 0;
    const existing = aggregated.get(key);
    aggregated.set(key, {
      warehouse_id: warehouseId,
      product_id: productId,
      color_name: existing?.color_name || colorName,
      quantity: (existing?.quantity || 0) + safeQty,
      updated_at: new Date().toISOString(),
    });
  }
  return [...aggregated.values()];
}

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

  let existingProduct = null;
  if (hasColorStocksUpdate) {
    const existingRes = await supabaseAdmin
      .from('products')
      .select('id,color_stocks')
      .eq('id', id)
      .maybeSingle();
    if (existingRes.error) return res.status(400).json({ error: existingRes.error.message });
    if (!existingRes.data) return res.status(404).json({ error: 'Product not found' });
    existingProduct = existingRes.data;
  }

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
    const resolveCanonicalColor = makeColorResolver(
      existingProduct?.color_stocks,
      data?.color_stocks,
    );

    const existingWarehouseRows = await supabaseAdmin
      .from('warehouse_product_stocks')
      .select('id,warehouse_id,product_id,color_name,quantity')
      .eq('product_id', id)
      .limit(10000);
    if (existingWarehouseRows.error) {
      return res.status(400).json({ error: existingWarehouseRows.error.message });
    }

    if (Array.isArray(existingWarehouseRows.data)) {
      const upsertRows = aggregateWarehouseStockRows(
        existingWarehouseRows.data,
        resolveCanonicalColor,
      );

      const deleteRes = await supabaseAdmin
        .from('warehouse_product_stocks')
        .delete()
        .eq('product_id', id);
      if (deleteRes.error) return res.status(400).json({ error: deleteRes.error.message });

      if (upsertRows.length > 0) {
        const upsertRes = await supabaseAdmin
          .from('warehouse_product_stocks')
          .upsert(upsertRows, { onConflict: 'warehouse_id,product_id,color_name' });
        if (upsertRes.error) return res.status(400).json({ error: upsertRes.error.message });
      }
    }

    // Keep product transaction history labels aligned with renamed colors.
    const txRes = await supabaseAdmin
      .from('transactions')
      .select('id,color_name')
      .eq('product_id', id)
      .limit(10000);
    if (txRes.error) return res.status(400).json({ error: txRes.error.message });

    if (Array.isArray(txRes.data) && txRes.data.length > 0) {
      const txUpdates = txRes.data
        .map((tx) => {
          const nextColor = resolveCanonicalColor(tx?.color_name);
          const currentColor = normalizeColorName(tx?.color_name);
          if (nextColor === currentColor) {
            return null;
          }
          return { id: tx.id, color_name: nextColor };
        })
        .filter(Boolean);
      for (const txUpdate of txUpdates) {
        const updateTxRes = await supabaseAdmin
          .from('transactions')
          .update({ color_name: txUpdate.color_name })
          .eq('id', txUpdate.id);
        if (updateTxRes.error) {
          return res.status(400).json({ error: updateTxRes.error.message });
        }
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
