import express from 'express';
import { supabaseAdmin } from '../supabase.js';
import { authRequired, requireRole } from '../auth.js';
import { sendStockTransactionPush } from '../notifications/push_service.js';

export const transactionsRouter = express.Router();

transactionsRouter.get('/', authRequired, async (req, res) => {
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
  requireRole(['admin', 'manager', 'worker']),
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
    return res.json({ data: insertResult.data });
  }
);

transactionsRouter.patch(
  '/:id',
  authRequired,
  requireRole(['admin', 'manager']),
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

    // Check if the transaction is older than 12 hours
    const createdAtTime = new Date(oldTx.created_at).getTime();
    const isOlderThan12Hours = (Date.now() - createdAtTime) > 12 * 60 * 60 * 1000;

    if (isOlderThan12Hours) {
      // Validate that locked fields have not changed.
      const payloadCartons = payload.cartons !== undefined && payload.cartons !== null ? (payload.cartons === '' ? null : Number(payload.cartons)) : null;
      const oldCartons = oldTx.cartons ?? null;

      const payloadPcs = payload.pcs_per_carton !== undefined && payload.pcs_per_carton !== null ? (payload.pcs_per_carton === '' ? null : Number(payload.pcs_per_carton)) : null;
      const oldPcs = oldTx.pcs_per_carton ?? null;

      if (
        type !== String(oldTx.type || '') ||
        quantity !== Number(oldTx.quantity || 0) ||
        workerName !== String(oldTx.worker_name || '') ||
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

    const productId = String(oldTx.product_id || '').trim();
    const warehouseId = String(oldTx.warehouse_id || '').trim();
    const colorName = String(oldTx.color_name || 'Default').trim() || 'Default';
    if (!productId || !warehouseId) {
      return res.status(400).json({ error: 'Existing transaction is missing product/warehouse' });
    }

    const oldQty = Number(oldTx.quantity || 0);
    const oldSigned = String(oldTx.type) === 'stock_in' ? oldQty : -oldQty;
    const newSigned = type === 'stock_in' ? quantity : -quantity;
    const delta = newSigned - oldSigned;

    const productRes = await supabaseAdmin
      .from('products')
      .select('id,quantity,color_stocks')
      .eq('id', productId)
      .maybeSingle();
    if (productRes.error) return res.status(400).json({ error: productRes.error.message });
    if (!productRes.data) return res.status(400).json({ error: 'Product not found for transaction' });

    const currentProductQty = Number(productRes.data.quantity || 0);
    const nextProductQty = currentProductQty + delta;
    if (!Number.isFinite(nextProductQty) || nextProductQty < 0) {
      return res.status(400).json({ error: 'Edit would make product stock negative.' });
    }

    const colorStocks = Array.isArray(productRes.data.color_stocks)
      ? productRes.data.color_stocks.map((x) => ({ ...x }))
      : [];
    const normalizedTargetColor = colorName.toLowerCase();
    let colorIdx = colorStocks.findIndex((entry) =>
      String(entry?.color || '').trim().toLowerCase() === normalizedTargetColor,
    );
    if (colorIdx === -1 && normalizedTargetColor !== 'default') {
      colorStocks.push({ color: colorName, quantity: 0 });
      colorIdx = colorStocks.length - 1;
    }
    if (colorIdx !== -1) {
      const currentColorQty = Number(colorStocks[colorIdx]?.quantity || 0);
      const nextColorQty = currentColorQty + delta;
      if (!Number.isFinite(nextColorQty) || nextColorQty < 0) {
        return res.status(400).json({ error: `Edit would make color stock negative for ${colorName}.` });
      }
      colorStocks[colorIdx].quantity = Math.trunc(nextColorQty);
    }

    const warehouseStockRes = await supabaseAdmin
      .from('warehouse_product_stocks')
      .select('quantity')
      .eq('warehouse_id', warehouseId)
      .eq('product_id', productId)
      .eq('color_name', colorName)
      .maybeSingle();
    if (warehouseStockRes.error) return res.status(400).json({ error: warehouseStockRes.error.message });
    if (!warehouseStockRes.data) {
      return res.status(400).json({ error: `No stock row found in warehouse for color ${colorName}.` });
    }
    const currentWarehouseQty = Number(warehouseStockRes.data.quantity || 0);
    const nextWarehouseQty = currentWarehouseQty + delta;
    if (!Number.isFinite(nextWarehouseQty) || nextWarehouseQty < 0) {
      return res.status(400).json({ error: `Edit would make warehouse stock negative for ${colorName}.` });
    }

    const updatedProductRes = await supabaseAdmin
      .from('products')
      .update({
        quantity: Math.trunc(nextProductQty),
        color_stocks: colorStocks,
      })
      .eq('id', productId)
      .select('id')
      .maybeSingle();
    if (updatedProductRes.error) return res.status(400).json({ error: updatedProductRes.error.message });

    const updatedWarehouseRes = await supabaseAdmin
      .from('warehouse_product_stocks')
      .update({ quantity: Math.trunc(nextWarehouseQty), updated_at: new Date().toISOString() })
      .eq('warehouse_id', warehouseId)
      .eq('product_id', productId)
      .eq('color_name', colorName)
      .select('warehouse_id')
      .maybeSingle();
    if (updatedWarehouseRes.error) return res.status(400).json({ error: updatedWarehouseRes.error.message });

    const updatedTxRes = await supabaseAdmin
      .from('transactions')
      .update({
        type,
        quantity,
        notes,
        worker_name: workerName,
        cartons: payload.cartons ? Number(payload.cartons) : null,
        pcs_per_carton: payload.pcs_per_carton ? Number(payload.pcs_per_carton) : oldTx.pcs_per_carton ?? null,
      })
      .eq('id', txId)
      .select('*')
      .maybeSingle();
    if (updatedTxRes.error) return res.status(400).json({ error: updatedTxRes.error.message });

    return res.json({ data: updatedTxRes.data });
  },
);

transactionsRouter.post(
  '/:id/reverse',
  authRequired,
  requireRole(['admin', 'manager', 'worker']),
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
    return res.json({ data: insertResult.data });
  },
);
