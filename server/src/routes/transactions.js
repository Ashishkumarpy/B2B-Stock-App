import express from 'express';
import { supabaseAdmin } from '../supabase.js';
import { authRequired, requirePermission } from '../auth.js';
import { sendStockTransactionPush } from '../notifications/push_service.js';
import { logActivity } from '../activity_logger.js';

export const transactionsRouter = express.Router();

function parseOptionalIntegerField(value, fieldName, { min = 0 } = {}) {
  if (value === undefined) return undefined;
  if (value === null || value === '') return null;
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < min) {
    const minText = min > 0 ? `a positive integer` : `a non-negative integer`;
    const err = new Error(`${fieldName} must be ${minText}`);
    err.status = 400;
    throw err;
  }
  return Math.trunc(parsed);
}

transactionsRouter.get('/', authRequired, requirePermission('perm_inventory'), async (req, res) => {
  const limit = parseInt(req.query.limit) || 1000;
  const page = parseInt(req.query.page) || 1;
  const offset = (page - 1) * limit;

  let query = supabaseAdmin
    .from('transactions')
    .select('*')
    .order('created_at', { ascending: false })
    .range(offset, offset + limit - 1);

  if (req.query.product_id) {
    query = query.eq('product_id', req.query.product_id);
  }

  const { data, error } = await query;
  if (error) return res.status(500).json({ error: error.message });
  return res.json({ data });
});

// Allow both admin and worker to insert stock transactions
transactionsRouter.post(
  '/',
  authRequired,
  requirePermission('perm_inventory'),
  async (req, res) => {
    const payload = req.body || {};
    const productId = String(payload.product_id || '').trim();
    const type = String(payload.type || '').trim();
    const quantity = Number(payload.quantity);
    const colorNameInput = String(payload.color_name || '').trim();
    let colorName = colorNameInput || 'Default';
    const warehouseIdInput = String(payload.warehouse_id || '').trim();
    const createdAtRaw = payload.created_at;
    const notes =
      typeof payload.notes === 'string' && payload.notes.trim().length > 0
        ? payload.notes.trim()
        : null;

    if (!productId) {
      return res.status(400).json({ error: 'product_id is required' });
    }
    if (!['stock_in', 'stock_out'].includes(type)) {
      return res
        .status(400)
        .json({ error: 'type must be stock_in or stock_out' });
    }
    if (!Number.isInteger(quantity) || quantity <= 0) {
      return res.status(400).json({ error: 'quantity must be a positive integer' });
    }

    let createdAt = null;
    if (typeof createdAtRaw === 'string' && createdAtRaw.trim().length > 0) {
      const parsed = new Date(createdAtRaw);
      if (Number.isNaN(parsed.getTime())) {
        return res.status(400).json({ error: 'created_at must be a valid ISO datetime' });
      }
      createdAt = parsed.toISOString();
    }

    const session = req.session || {};
    const userId = String(session.sub || '').trim();
    const sessionRole = String(session.role || '').trim();
    const userName = String(session.name || 'Mobile User').trim();
    const userEmail = String(session.email || '').trim();

    // Run all initial entity lookups in a single parallel batch
    const warehouseIdToQuery = (warehouseIdInput && warehouseIdInput.toLowerCase() !== 'default' && warehouseIdInput.trim() !== '') ? warehouseIdInput : null;
    const workerIdInput = String(payload.worker_id || '').trim();

    const [
      productRes,
      warehousesRes,
      stocksRes,
      explicitWorkerRes,
      workerByUserIdRes,
      workerByEmailRes
    ] = await Promise.all([
      // 1. Fetch Product
      supabaseAdmin.from('products').select('id,name,code,color_stocks,pcs_per_carton').eq('id', productId).maybeSingle(),
      // 2. Fetch Active Warehouses
      supabaseAdmin.from('warehouses').select('id,name,is_active').eq('is_active', true).order('created_at', { ascending: true }),
      // 3. Fetch Stocks for Product
      supabaseAdmin.from('warehouse_product_stocks').select('warehouse_id,color_name,quantity').eq('product_id', productId).limit(1000),
      // 4. Fetch Explicit Worker
      workerIdInput ? supabaseAdmin.from('workers').select('id,name').eq('id', workerIdInput).maybeSingle() : Promise.resolve({ data: null, error: null }),
      // 5. Fetch Worker by session user identifier
      (!workerIdInput && userId) ? supabaseAdmin.from('workers').select('id,name,user_id').or(`id.eq.${userId},user_id.eq.${userId}`).maybeSingle() : Promise.resolve({ data: null, error: null }),
      // 6. Fetch Worker by session email
      (!workerIdInput && userId && userEmail) ? supabaseAdmin.from('workers').select('id,name,user_id,email').eq('email', userEmail).maybeSingle() : Promise.resolve({ data: null, error: null })
    ]);

    if (productRes.error) return res.status(400).json({ error: productRes.error.message });
    const product = productRes.data;
    if (!product) return res.status(400).json({ error: 'Invalid product_id' });

    const parsedProductPcs = Number(product?.pcs_per_carton);
    const defaultPcsPerCarton =
      Number.isFinite(parsedProductPcs) && parsedProductPcs > 0
        ? Math.trunc(parsedProductPcs)
        : 1;
    const parsedPayloadPcs = Number(payload.pcs_per_carton);
    const resolvedPcsPerCarton =
      Number.isFinite(parsedPayloadPcs) && parsedPayloadPcs > 0
        ? Math.trunc(parsedPayloadPcs)
        : defaultPcsPerCarton;

    const colorStocksRaw = Array.isArray(product.color_stocks) ? product.color_stocks : [];
    const matchingColor = colorStocksRaw.find((entry) => {
      const entryColor = String(entry?.color || '').trim();
      return entryColor.toLowerCase() === colorName.toLowerCase();
    });
    if (matchingColor) {
      colorName = String(matchingColor.color || colorName).trim() || colorName;
    } else if (colorName.toLowerCase() === 'default') {
      colorName = 'Default';
    }
    const matchingColorQty = Number(matchingColor?.quantity ?? 0);
    if (type === 'stock_out' && colorName.toLowerCase() !== 'default') {
      if (!matchingColor) {
        return res.status(400).json({
          error: 'Selected color is not available for this product. Please use an existing color.',
        });
      }
      if (!Number.isFinite(matchingColorQty) || matchingColorQty < quantity) {
        return res.status(400).json({
          error: `Insufficient ${colorName} stock. Available: ${Math.max(0, Math.trunc(matchingColorQty))}`,
        });
      }
    }

    if (warehousesRes.error) return res.status(400).json({ error: warehousesRes.error.message });
    const activeWarehouses = warehousesRes.data || [];
    const activeById = new Map(activeWarehouses.map((w) => [String(w.id), String(w.name || 'Warehouse')]));

    let warehouseId = warehouseIdToQuery;
    let warehouseName = null;

    if (warehouseId) {
      if (!activeById.has(warehouseId)) {
        return res.status(400).json({ error: 'Selected warehouse is invalid or inactive.' });
      }
      warehouseName = activeById.get(warehouseId);
    } else {
      if (type === 'stock_out') {
        const sameColorRows = (stocksRes.data || []).filter((row) => {
          const rowColor = String(row?.color_name || '').trim().toLowerCase();
          const qty = Number(row?.quantity ?? 0);
          return rowColor === colorName.trim().toLowerCase() && Number.isFinite(qty) && qty >= quantity;
        });

        const candidateWarehouseIds = [...new Set(sameColorRows.map((row) => String(row?.warehouse_id || '').trim()).filter(Boolean))];
        const viableWarehouseIds = candidateWarehouseIds.filter((wid) => activeById.has(wid));

        if (viableWarehouseIds.length === 1) {
          warehouseId = viableWarehouseIds[0];
          warehouseName = activeById.get(viableWarehouseIds[0]);
          const canonical = sameColorRows.find((row) => String(row?.warehouse_id || '').trim() === viableWarehouseIds[0]);
          if (canonical?.color_name) {
            colorName = String(canonical.color_name).trim() || colorName;
          }
        } else if (viableWarehouseIds.length > 1) {
          const options = viableWarehouseIds.map((wid) => activeById.get(wid) || wid).join(', ');
          return res.status(400).json({
            error: `Stock for ${colorName} is available in multiple warehouses (${options}). Please choose a warehouse explicitly.`,
          });
        }
      }

      if (!warehouseId) {
        if (activeWarehouses.length === 0) {
          return res.status(400).json({ error: 'No active warehouse configured. Please add a warehouse first.' });
        }
        warehouseId = String(activeWarehouses[0].id);
        warehouseName = String(activeWarehouses[0].name || 'Warehouse');
      }
    }

    if (type === 'stock_out') {
      const sameWarehouseRows = (stocksRes.data || []).filter((row) => String(row.warehouse_id) === warehouseId);
      if (sameWarehouseRows.length > 0) {
        const sameColorMatches = sameWarehouseRows.filter((row) => {
          const rowColor = String(row?.color_name || '').trim().toLowerCase();
          return rowColor === colorName.trim().toLowerCase();
        });

        if (sameColorMatches.length > 0) {
          const stockMatch = sameColorMatches.reduce((best, row) => {
            const bestQty = Number(best?.quantity ?? 0);
            const rowQty = Number(row?.quantity ?? 0);
            return rowQty > bestQty ? row : best;
          }, sameColorMatches[0]);

          const matchedColorName = String(stockMatch?.color_name || '').trim();
          if (matchedColorName) {
            colorName = matchedColorName;
          }
          const available = Number(stockMatch?.quantity ?? 0);
          if (!Number.isFinite(available) || available < quantity) {
            return res.status(400).json({
              error: `Insufficient stock in ${warehouseName} for ${colorName}. Available: ${Math.max(0, Math.trunc(available))}`,
            });
          }
        } else {
          return res.status(400).json({
            error: `No stock found in warehouse ${warehouseName} for color ${colorName}.`,
          });
        }
      } else {
        return res.status(400).json({
          error: `No stock found in selected warehouse for ${colorName}.`,
        });
      }
    }

    let workerId = workerIdInput || null;
    let workerName = userName;

    if (workerId) {
      const explicitWorker = explicitWorkerRes.data;
      if (explicitWorker) {
        workerName = explicitWorker.name;
      } else {
        workerId = null;
      }
    }

    if (!workerId && userId) {
      if (sessionRole === 'worker' || (sessionRole === 'manager' && !userEmail)) {
        const byWorkerId = workerByUserIdRes.data;
        if (!byWorkerId) {
          return res.status(400).json({
            error: 'Worker session is invalid. Please log in again.',
          });
        }
        workerId = byWorkerId.id;
        workerName = String(byWorkerId.name || userName || 'Worker');
      } else {
        let worker = workerByUserIdRes.data;
        let hasWorkerUserIdColumn = true;

        if (workerByUserIdRes.error && String(workerByUserIdRes.error.message || '').toLowerCase().includes("could not find the 'user_id' column")) {
          hasWorkerUserIdColumn = false;
        }

        if (!worker && userEmail) {
          const byEmail = workerByEmailRes.data;
          if (byEmail) {
            worker = byEmail;
            if (hasWorkerUserIdColumn && !worker.user_id) {
              await supabaseAdmin
                .from('workers')
                .update({ user_id: userId, name: userName })
                .eq('id', worker.id);
            }
          }
        }

        if (!worker) {
          const insertPayload = hasWorkerUserIdColumn
            ? {
                user_id: userId,
                name: userName || 'Admin User',
                email: userEmail || null
              }
            : {
                name: userName || 'Admin User',
                email: userEmail || null
              };
          const inserted = await supabaseAdmin
            .from('workers')
            .insert(insertPayload)
            .select('id,name')
            .single();
          if (inserted.error) {
            return res.status(400).json({ error: inserted.error.message });
          }
          worker = inserted.data;
        }

        workerId = worker.id;
        workerName = String(worker.name || userName || 'Admin User');
      }
    }

    const insertRow = {
      product_id: productId,
      product_name: String(product.name || 'Product'),
      product_code: String(product.code || ''),
      color_name: colorName,
      warehouse_id: warehouseId,
      warehouse_name: warehouseName,
      type,
      quantity,
      cartons: payload.cartons ? Number(payload.cartons) : null,
      pcs_per_carton: resolvedPcsPerCarton,
      worker_id: workerId,
      worker_name: workerName,
      actor_user_id:
        sessionRole === 'admin' || (sessionRole === 'manager' && userEmail) ? userId || null : null,
      actor_role: sessionRole || null,
      notes
    };
    if (createdAt) {
      insertRow.created_at = createdAt;
    }

    let insertResult = await supabaseAdmin
      .from('transactions')
      .insert(insertRow)
      .select('*')
      .single();

    if (
      insertResult.error &&
      String(insertResult.error.message || '')
        .toLowerCase()
        .includes("could not find the 'color_name' column")
    ) {
      const { color_name: _ignored, warehouse_id: _warehouseIdIgnored, warehouse_name: _warehouseNameIgnored, cartons: _c, pcs_per_carton: _pc, ...legacyRow } = insertRow;
      insertResult = await supabaseAdmin
        .from('transactions')
        .insert(legacyRow)
        .select('*')
        .single();
    } else if (
      insertResult.error &&
      String(insertResult.error.message || '')
        .toLowerCase()
        .includes("could not find the 'cartons' column")
    ) {
      const { cartons: _c, pcs_per_carton: _pc, ...legacyRow } = insertRow;
      insertResult = await supabaseAdmin
        .from('transactions')
        .insert(legacyRow)
        .select('*')
        .single();
    }

    if (insertResult.error) {
      return res.status(400).json({ error: insertResult.error.message });
    }

    if (
      Number.isFinite(parsedPayloadPcs) &&
      parsedPayloadPcs > 0 &&
      Math.trunc(parsedPayloadPcs) !== defaultPcsPerCarton
    ) {
      await supabaseAdmin
        .from('products')
        .update({ pcs_per_carton: Math.trunc(parsedPayloadPcs) })
        .eq('id', productId);
    }

    // Fire-and-forget push notifications for stock activity.
    sendStockTransactionPush(insertResult.data).catch(() => {});

    // Log stock transaction activity
    await logActivity({
      actorId: session.sub || workerId,
      actorName: workerName || userName,
      actionType: 'stock_transaction',
      description: `${insertResult.data.type === 'stock_in' ? 'Stocked in' : 'Stocked out'} ${insertResult.data.quantity} units of ${insertResult.data.product_name} (${insertResult.data.color_name}) at ${insertResult.data.warehouse_name}`,
      metadata: {
        transaction_id: insertResult.data.id,
        product_id: insertResult.data.product_id,
        warehouse_id: insertResult.data.warehouse_id,
        type: insertResult.data.type,
        quantity: insertResult.data.quantity
      }
    });

    return res.json({ data: insertResult.data });
  }
);

transactionsRouter.post(
  '/shift',
  authRequired,
  requirePermission('perm_inventory'),
  async (req, res) => {
    const payload = req.body || {};
    const productId = String(payload.product_id || '').trim();
    const fromWarehouseId = String(payload.from_warehouse_id || '').trim();
    const toWarehouseId = String(payload.to_warehouse_id || '').trim();
    const quantity = Number(payload.quantity);
    const requestedColorName = String(payload.color_name || 'Default').trim() || 'Default';
    const notes =
      typeof payload.notes === 'string' && payload.notes.trim().length > 0
        ? payload.notes.trim()
        : null;

    if (!productId) {
      return res.status(400).json({ error: 'product_id is required' });
    }
    if (!fromWarehouseId) {
      return res.status(400).json({ error: 'from_warehouse_id is required' });
    }
    if (!toWarehouseId) {
      return res.status(400).json({ error: 'to_warehouse_id is required' });
    }
    if (fromWarehouseId === toWarehouseId) {
      return res.status(400).json({ error: 'Source and destination warehouses must be different.' });
    }
    if (!Number.isInteger(quantity) || quantity <= 0) {
      return res.status(400).json({ error: 'quantity must be a positive integer' });
    }

    const [productRes, warehousesRes, stockRowsRes] = await Promise.all([
      supabaseAdmin
        .from('products')
        .select('id,name,code')
        .eq('id', productId)
        .maybeSingle(),
      supabaseAdmin
        .from('warehouses')
        .select('id,name,is_active')
        .in('id', [fromWarehouseId, toWarehouseId]),
      supabaseAdmin
        .from('warehouse_product_stocks')
        .select('warehouse_id,product_id,color_name,quantity')
        .eq('product_id', productId)
        .in('warehouse_id', [fromWarehouseId, toWarehouseId])
        .limit(100),
    ]);

    if (productRes.error) return res.status(400).json({ error: productRes.error.message });
    if (warehousesRes.error) return res.status(400).json({ error: warehousesRes.error.message });
    if (stockRowsRes.error) return res.status(400).json({ error: stockRowsRes.error.message });
    if (!productRes.data) return res.status(400).json({ error: 'Invalid product_id' });

    const warehouseById = new Map(
      (warehousesRes.data || []).map((warehouse) => [String(warehouse.id), warehouse]),
    );
    const fromWarehouse = warehouseById.get(fromWarehouseId);
    const toWarehouse = warehouseById.get(toWarehouseId);
    if (!fromWarehouse || fromWarehouse.is_active !== true) {
      return res.status(400).json({ error: 'Source warehouse is invalid or inactive.' });
    }
    if (!toWarehouse || toWarehouse.is_active !== true) {
      return res.status(400).json({ error: 'Destination warehouse is invalid or inactive.' });
    }

    const colorLc = requestedColorName.toLowerCase();
    const stockRows = stockRowsRes.data || [];
    const sourceRow = stockRows.find((row) =>
      String(row.warehouse_id) === fromWarehouseId &&
      String(row.color_name || 'Default').trim().toLowerCase() === colorLc,
    );
    const available = Number(sourceRow?.quantity ?? 0);
    if (!sourceRow || !Number.isFinite(available) || available < quantity) {
      return res.status(400).json({
        error: `Insufficient stock in ${fromWarehouse.name} for ${requestedColorName}. Available: ${Math.max(0, Math.trunc(available || 0))}`,
      });
    }

    const canonicalColorName = String(sourceRow.color_name || requestedColorName).trim() || requestedColorName;
    const targetRow = stockRows.find((row) =>
      String(row.warehouse_id) === toWarehouseId &&
      String(row.color_name || 'Default').trim().toLowerCase() === canonicalColorName.toLowerCase(),
    );
    const targetColorName = String(targetRow?.color_name || canonicalColorName).trim() || canonicalColorName;
    const nextSourceQty = Math.trunc(available) - quantity;
    const targetQty = Number(targetRow?.quantity ?? 0);
    const nextTargetQty = (Number.isFinite(targetQty) ? Math.max(0, Math.trunc(targetQty)) : 0) + quantity;
    const nowIso = new Date().toISOString();

    const sourceUpdate = await supabaseAdmin
      .from('warehouse_product_stocks')
      .update({ quantity: nextSourceQty, updated_at: nowIso })
      .eq('warehouse_id', fromWarehouseId)
      .eq('product_id', productId)
      .eq('color_name', canonicalColorName);
    if (sourceUpdate.error) return res.status(400).json({ error: sourceUpdate.error.message });

    const targetUpsert = await supabaseAdmin
      .from('warehouse_product_stocks')
      .upsert(
        [{
          warehouse_id: toWarehouseId,
          product_id: productId,
          color_name: targetColorName,
          quantity: nextTargetQty,
          updated_at: nowIso,
        }],
        { onConflict: 'warehouse_id,product_id,color_name' },
      );
    if (targetUpsert.error) return res.status(400).json({ error: targetUpsert.error.message });

    const session = req.session || {};
    const actorName = String(session.name || payload.worker_name || 'Stock User').trim();
    const result = {
      product_id: productId,
      product_name: String(productRes.data.name || 'Product'),
      product_code: String(productRes.data.code || ''),
      color_name: canonicalColorName,
      quantity,
      from_warehouse_id: fromWarehouseId,
      from_warehouse_name: String(fromWarehouse.name || 'Warehouse'),
      to_warehouse_id: toWarehouseId,
      to_warehouse_name: String(toWarehouse.name || 'Warehouse'),
      notes,
      shifted_by: actorName,
      created_at: nowIso,
    };

    await logActivity({
      actorId: session.sub,
      actorName,
      actionType: 'stock_shift',
      description: `Shifted ${quantity} units of ${result.product_name} (${canonicalColorName}) from ${result.from_warehouse_name} to ${result.to_warehouse_name}`,
      metadata: result,
    });

    return res.json({ data: result });
  },
);

transactionsRouter.patch(
  '/:id',
  authRequired,
  requirePermission('perm_inventory'),
  async (req, res) => {
    const txId = String(req.params.id || '').trim();
    if (!txId) return res.status(400).json({ error: 'transaction id is required' });

    const payload = req.body || {};
    const type = String(payload.type || '').trim();
    const quantity = Number(payload.quantity);
    const notes =
      typeof payload.notes === 'string' && payload.notes.trim().length > 0
        ? payload.notes.trim()
        : null;
    const workerName = String(payload.worker_name || '').trim();
    let requestedCartons;
    let requestedPcsPerCarton;

    try {
      requestedCartons = parseOptionalIntegerField(payload.cartons, 'cartons', { min: 0 });
      requestedPcsPerCarton = parseOptionalIntegerField(payload.pcs_per_carton, 'pcs_per_carton', { min: 1 });
    } catch (err) {
      return res.status(err.status || 400).json({ error: err.message || 'Invalid carton fields' });
    }

    if (!['stock_in', 'stock_out'].includes(type)) {
      return res.status(400).json({ error: 'type must be stock_in or stock_out' });
    }
    if (!Number.isInteger(quantity) || quantity <= 0) {
      return res.status(400).json({ error: 'quantity must be a positive integer' });
    }
    if (!workerName) {
      return res.status(400).json({ error: 'worker_name is required' });
    }

    const oldRes = await supabaseAdmin
      .from('transactions')
      .select('*')
      .eq('id', txId)
      .maybeSingle();
    if (oldRes.error) return res.status(400).json({ error: oldRes.error.message });
    if (!oldRes.data) return res.status(404).json({ error: 'Transaction not found' });
    const oldTx = oldRes.data;
    const requestedProductId = String(payload.product_id ?? oldTx.product_id ?? '').trim();
    const requestedWarehouseId = String(payload.warehouse_id ?? oldTx.warehouse_id ?? '').trim();
    let requestedColorName = String(payload.color_name ?? oldTx.color_name ?? 'Default').trim() || 'Default';

    // Check if the transaction is older than 12 hours
    const createdAtTime = new Date(oldTx.created_at).getTime();
    const isOlderThan12Hours = (Date.now() - createdAtTime) > 12 * 60 * 60 * 1000;

    if (isOlderThan12Hours) {
      // Validate that locked fields have not changed.
      const oldCartons = oldTx.cartons ?? null;
      const oldPcs = oldTx.pcs_per_carton ?? null;
      const payloadCartons = requestedCartons === undefined ? oldCartons : requestedCartons;
      const payloadPcs = requestedPcsPerCarton === undefined ? oldPcs : requestedPcsPerCarton;
      const oldProductId = String(oldTx.product_id || '').trim();
      const oldWarehouseId = String(oldTx.warehouse_id || '').trim();
      const oldColorName = String(oldTx.color_name || 'Default').trim() || 'Default';

      if (
        requestedProductId !== oldProductId ||
        type !== String(oldTx.type || '') ||
        quantity !== Number(oldTx.quantity || 0) ||
        workerName !== String(oldTx.worker_name || '') ||
        requestedWarehouseId !== oldWarehouseId ||
        requestedColorName.toLowerCase() !== oldColorName.toLowerCase() ||
        payloadCartons !== oldCartons ||
        payloadPcs !== oldPcs
      ) {
        return res.status(400).json({
          error: 'This transaction was recorded more than 12 hours ago. Only customer name and notes can be edited.',
        });
      }

      // Update only notes in the transactions table
      const updatedTxRes = await supabaseAdmin
        .from('transactions')
        .update({
          notes,
        })
        .eq('id', txId)
        .select('*')
        .maybeSingle();

      if (updatedTxRes.error) return res.status(400).json({ error: updatedTxRes.error.message });
      return res.json({ data: updatedTxRes.data });
    }

    const oldProductId = String(oldTx.product_id || '').trim();
    const newProductId = requestedProductId || oldProductId;
    const oldWarehouseId = String(oldTx.warehouse_id || '').trim();
    const oldColorName = String(oldTx.color_name || 'Default').trim() || 'Default';
    if (!oldProductId || !oldWarehouseId) {
      return res.status(400).json({ error: 'Existing transaction is missing product/warehouse' });
    }
    if (!newProductId) {
      return res.status(400).json({ error: 'product_id is required' });
    }
    if (!requestedWarehouseId) {
      return res.status(400).json({ error: 'warehouse_id is required' });
    }

    const oldQty = Number(oldTx.quantity || 0);
    const oldSigned = String(oldTx.type) === 'stock_in' ? oldQty : -oldQty;
    const newSigned = type === 'stock_in' ? quantity : -quantity;

    const productIds = [...new Set([oldProductId, newProductId])];
    const [productsRes, warehousesRes, stockRowsRes] = await Promise.all([
      supabaseAdmin
        .from('products')
        .select('id,name,code,category,quantity,color_stocks')
        .in('id', productIds),
      supabaseAdmin
        .from('warehouses')
        .select('id,name,is_active')
        .eq('is_active', true),
      supabaseAdmin
        .from('warehouse_product_stocks')
        .select('warehouse_id,product_id,color_name,quantity')
        .in('product_id', productIds)
        .limit(10000),
    ]);
    if (productsRes.error) return res.status(400).json({ error: productsRes.error.message });
    if (warehousesRes.error) return res.status(400).json({ error: warehousesRes.error.message });
    if (stockRowsRes.error) return res.status(400).json({ error: stockRowsRes.error.message });

    const productsById = new Map((productsRes.data || []).map((product) => [String(product.id), product]));
    const oldProduct = productsById.get(oldProductId);
    const newProduct = productsById.get(newProductId);
    if (!oldProduct) return res.status(400).json({ error: 'Original product not found for transaction' });
    if (!newProduct) return res.status(400).json({ error: 'Selected product not found' });

    const oldCategory = String(oldProduct.category || 'Uncategorized').trim() || 'Uncategorized';
    const newCategory = String(newProduct.category || 'Uncategorized').trim() || 'Uncategorized';
    if (oldCategory.toLowerCase() !== newCategory.toLowerCase()) {
      return res.status(400).json({
        error: 'Product correction is only allowed within the same category.',
      });
    }

    const activeWarehouse = (warehousesRes.data || []).find(
      (w) => String(w.id) === requestedWarehouseId,
    );
    if (!activeWarehouse) {
      return res.status(400).json({ error: 'Selected warehouse is invalid or inactive.' });
    }
    const requestedWarehouseName = String(activeWarehouse.name || 'Warehouse');

    const newProductColorStocks = Array.isArray(newProduct.color_stocks)
      ? newProduct.color_stocks.map((x) => ({ ...x }))
      : [];

    const matchingProductColor = newProductColorStocks.find((entry) =>
      String(entry?.color || '').trim().toLowerCase() === requestedColorName.toLowerCase(),
    );
    if (matchingProductColor?.color) {
      requestedColorName = String(matchingProductColor.color).trim() || requestedColorName;
    }

    const productDeltas = new Map();
    const addProductDelta = (productId, amount) => {
      productDeltas.set(productId, (productDeltas.get(productId) || 0) + amount);
    };
    addProductDelta(oldProductId, -oldSigned);
    addProductDelta(newProductId, newSigned);

    const productUpdates = [];
    for (const [productId, productDelta] of productDeltas.entries()) {
      const product = productsById.get(productId);
      const currentProductQty = Number(product?.quantity || 0);
      const nextProductQty = currentProductQty + productDelta;
      if (!Number.isFinite(nextProductQty) || nextProductQty < 0) {
        return res.status(400).json({ error: `Edit would make product stock negative for ${product?.code || productId}.` });
      }
      productUpdates.push({
        id: productId,
        quantity: Math.trunc(nextProductQty),
      });
    }

    const colorDeltas = new Map();
    const addColorDelta = (productId, color, amount) => {
      const normalized = String(color || 'Default').trim() || 'Default';
      if (normalized.toLowerCase() === 'default') return;
      const key = `${productId}::${normalized.toLowerCase()}`;
      colorDeltas.set(key, {
        product_id: productId,
        color: normalized,
        delta: (colorDeltas.get(key)?.delta || 0) + amount,
      });
    };
    addColorDelta(oldProductId, oldColorName, -oldSigned);
    addColorDelta(newProductId, requestedColorName, newSigned);

    const colorStockUpdates = new Map();
    for (const entry of colorDeltas.values()) {
      const product = productsById.get(entry.product_id);
      const colorStocks = Array.isArray(product?.color_stocks)
        ? product.color_stocks.map((stock) => ({ ...stock }))
        : [];
      let colorIdx = colorStocks.findIndex((stock) =>
        String(stock?.color || '').trim().toLowerCase() === entry.color.toLowerCase(),
      );
      if (colorIdx === -1) {
        colorStocks.push({ color: entry.color, quantity: 0 });
        colorIdx = colorStocks.length - 1;
      }
      const currentColorQty = Number(colorStocks[colorIdx]?.quantity || 0);
      const nextColorQty = currentColorQty + entry.delta;
      if (!Number.isFinite(nextColorQty) || nextColorQty < 0) {
        return res.status(400).json({ error: `Edit would make color stock negative for ${entry.color}.` });
      }
      colorStocks[colorIdx].quantity = Math.trunc(nextColorQty);
      colorStockUpdates.set(entry.product_id, colorStocks);
    }

    const warehouseRowsByKey = new Map();
    for (const row of stockRowsRes.data || []) {
      const key = `${String(row.product_id)}::${String(row.warehouse_id)}::${String(row.color_name || 'Default').trim().toLowerCase()}`;
      warehouseRowsByKey.set(key, row);
    }

    const warehouseDeltas = new Map();
    const addWarehouseDelta = (productId, warehouseId, color, amount) => {
      const colorName = String(color || 'Default').trim() || 'Default';
      const key = `${productId}::${warehouseId}::${colorName.toLowerCase()}`;
      warehouseDeltas.set(key, {
        warehouse_id: warehouseId,
        product_id: productId,
        color_name: colorName,
        delta: (warehouseDeltas.get(key)?.delta || 0) + amount,
      });
    };
    addWarehouseDelta(oldProductId, oldWarehouseId, oldColorName, -oldSigned);
    addWarehouseDelta(newProductId, requestedWarehouseId, requestedColorName, newSigned);

    const warehouseUpserts = [];
    for (const entry of warehouseDeltas.values()) {
      const key = `${entry.product_id}::${entry.warehouse_id}::${entry.color_name.toLowerCase()}`;
      const currentWarehouseQty = Number(warehouseRowsByKey.get(key)?.quantity || 0);
      const nextWarehouseQty = currentWarehouseQty + entry.delta;
      if (!Number.isFinite(nextWarehouseQty) || nextWarehouseQty < 0) {
        return res.status(400).json({
          error: `Edit would make warehouse stock negative for ${entry.color_name}.`,
        });
      }
      warehouseUpserts.push({
        warehouse_id: entry.warehouse_id,
        product_id: entry.product_id,
        color_name: entry.color_name,
        quantity: Math.trunc(nextWarehouseQty),
        updated_at: new Date().toISOString(),
      });
    }

    for (const productUpdate of productUpdates) {
      const updatePayload = { quantity: productUpdate.quantity };
      if (colorStockUpdates.has(productUpdate.id)) {
        updatePayload.color_stocks = colorStockUpdates.get(productUpdate.id);
      }
      const updatedProductRes = await supabaseAdmin
        .from('products')
        .update(updatePayload)
        .eq('id', productUpdate.id)
        .select('id')
        .maybeSingle();
      if (updatedProductRes.error) return res.status(400).json({ error: updatedProductRes.error.message });
    }

    if (warehouseUpserts.length > 0) {
      const updatedWarehouseRes = await supabaseAdmin
        .from('warehouse_product_stocks')
        .upsert(warehouseUpserts, { onConflict: 'warehouse_id,product_id,color_name' });
      if (updatedWarehouseRes.error) return res.status(400).json({ error: updatedWarehouseRes.error.message });
    }

    const updatedTxRes = await supabaseAdmin
      .from('transactions')
      .update({
        product_id: newProductId,
        product_name: String(newProduct.name || oldTx.product_name || 'Product'),
        product_code: String(newProduct.code || oldTx.product_code || ''),
        type,
        color_name: requestedColorName,
        warehouse_id: requestedWarehouseId,
        warehouse_name: requestedWarehouseName,
        quantity,
        notes,
        worker_name: workerName,
        cartons: requestedCartons === undefined ? (oldTx.cartons ?? null) : requestedCartons,
        pcs_per_carton: requestedPcsPerCarton === undefined ? (oldTx.pcs_per_carton ?? null) : requestedPcsPerCarton,
      })
      .eq('id', txId)
      .select('*')
      .maybeSingle();
    if (updatedTxRes.error) return res.status(400).json({ error: updatedTxRes.error.message });

    await logActivity({
      actorId: req.session.sub,
      actorName: req.session.name,
      actionType: 'stock_transaction_edit',
      description: `Edited stock transaction ${txId} for ${newProduct.name || oldTx.product_name} (New quantity: ${quantity})`,
      metadata: {
        transaction_id: txId,
        old_product_id: oldProductId,
        new_product_id: newProductId,
        old_product_code: oldProduct.code || oldTx.product_code || null,
        new_product_code: newProduct.code || null,
        old_warehouse_id: oldWarehouseId,
        new_warehouse_id: requestedWarehouseId,
        old_color_name: oldColorName,
        new_color_name: requestedColorName,
        old_qty: oldQty,
        new_qty: quantity
      }
    });

    return res.json({ data: updatedTxRes.data });
  },
);

transactionsRouter.post(
  '/:id/reverse',
  authRequired,
  requirePermission('perm_inventory'),
  async (req, res) => {
    const txId = String(req.params.id || '').trim();
    if (!txId) return res.status(400).json({ error: 'transaction id is required' });

    const txRes = await supabaseAdmin
      .from('transactions')
      .select('*')
      .eq('id', txId)
      .maybeSingle();
    if (txRes.error) return res.status(400).json({ error: txRes.error.message });
    if (!txRes.data) return res.status(404).json({ error: 'Transaction not found' });

    const original = txRes.data;
    const originalType = String(original.type || '').trim();
    if (!['stock_in', 'stock_out'].includes(originalType)) {
      return res.status(400).json({ error: 'Only stock_in/stock_out transactions can be reversed' });
    }

    // Prevent duplicate reverse operations for the same source transaction.
    const marker = `[REVERSED tx:${txId}]`;
    const dupCheck = await supabaseAdmin
      .from('transactions')
      .select('id')
      .like('notes', `%${marker}%`)
      .limit(1)
      .maybeSingle();
    if (!dupCheck.error && dupCheck.data) {
      return res.status(400).json({ error: 'This transaction is already reversed.' });
    }

    const reverseType = originalType === 'stock_in' ? 'stock_out' : 'stock_in';
    const originalNotes = typeof original.notes === 'string' ? original.notes.trim() : '';
    const reverseNotes = originalNotes
      ? `${marker} ${originalNotes}`
      : marker;

    const insertRow = {
      product_id: original.product_id,
      product_name: original.product_name,
      product_code: original.product_code,
      color_name: original.color_name || 'Default',
      warehouse_id: original.warehouse_id || null,
      warehouse_name: original.warehouse_name || 'Warehouse',
      type: reverseType,
      quantity: Number(original.quantity || 0),
      cartons: original.cartons ?? null,
      pcs_per_carton: original.pcs_per_carton ?? null,
      worker_id: original.worker_id || null,
      worker_name: original.worker_name || 'System',
      notes: reverseNotes,
    };

    let insertResult = await supabaseAdmin
      .from('transactions')
      .insert(insertRow)
      .select('*')
      .single();
    if (
      insertResult.error &&
      String(insertResult.error.message || '')
        .toLowerCase()
        .includes("could not find the 'color_name' column")
    ) {
      const { color_name: _c, warehouse_id: _wId, warehouse_name: _wName, cartons: _cartons, pcs_per_carton: _ppc, ...legacyRow } = insertRow;
      insertResult = await supabaseAdmin
        .from('transactions')
        .insert(legacyRow)
        .select('*')
        .single();
    } else if (
      insertResult.error &&
      String(insertResult.error.message || '')
        .toLowerCase()
        .includes("could not find the 'cartons' column")
    ) {
      const { cartons: _cartons, pcs_per_carton: _ppc, ...legacyRow } = insertRow;
      insertResult = await supabaseAdmin
        .from('transactions')
        .insert(legacyRow)
        .select('*')
        .single();
    }
    if (insertResult.error) return res.status(400).json({ error: insertResult.error.message });

    sendStockTransactionPush(insertResult.data).catch(() => {});

    await logActivity({
      actorId: req.session.sub,
      actorName: req.session.name,
      actionType: 'stock_transaction_reverse',
      description: `Reversed stock transaction ${txId} for ${original.product_name}`,
      metadata: {
        original_transaction_id: txId,
        reverse_transaction_id: insertResult.data.id
      }
    });

    return res.json({ data: insertResult.data });
  },
);
