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
    const colorName = colorNameInput || 'Default';
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

    let productQuery = await supabaseAdmin
      .from('products')
      .select('id,name,code,color_stocks')
      .eq('id', productId)
      .maybeSingle();
    if (
      productQuery.error &&
      String(productQuery.error.message || '')
        .toLowerCase()
        .includes("could not find the 'color_stocks' column")
    ) {
      productQuery = await supabaseAdmin
        .from('products')
        .select('id,name,code')
        .eq('id', productId)
        .maybeSingle();
    }
    const product = productQuery.data;
    const productError = productQuery.error;
    if (productError) return res.status(400).json({ error: productError.message });
    if (!product) return res.status(400).json({ error: 'Invalid product_id' });

    const colorStocksRaw = Array.isArray(product.color_stocks)
      ? product.color_stocks
      : [];
    const matchingColor = colorStocksRaw.find((entry) => {
      const entryColor = String(entry?.color || '').trim();
      return entryColor.toLowerCase() === colorName.toLowerCase();
    });
    const matchingColorQty = Number(matchingColor?.quantity ?? 0);
    if (type === 'stock_out' && colorName.toLowerCase() !== 'default') {
      if (!matchingColor) {
        return res.status(400).json({
          error:
            'Selected color is not available for this product. Please use an existing color.',
        });
      }
      if (!Number.isFinite(matchingColorQty) || matchingColorQty < quantity) {
        return res.status(400).json({
          error: `Insufficient ${colorName} stock. Available: ${Math.max(
            0,
            Math.trunc(matchingColorQty),
          )}`,
        });
      }
    }

    let warehouseId = warehouseIdInput;
    if (warehouseId && (warehouseId.toLowerCase() === 'default' || warehouseId.trim() === '')) {
      warehouseId = null;
    }
    let warehouseName = null;
    if (warehouseId) {
      const byId = await supabaseAdmin
        .from('warehouses')
        .select('id,name,is_active')
        .eq('id', warehouseId)
        .maybeSingle();
      if (byId.error) {
        return res.status(400).json({ error: byId.error.message });
      }
      if (!byId.data || byId.data.is_active !== true) {
        return res.status(400).json({ error: 'Selected warehouse is invalid or inactive.' });
      }
      warehouseName = String(byId.data.name || 'Warehouse');
    } else {
      const firstWarehouse = await supabaseAdmin
        .from('warehouses')
        .select('id,name')
        .eq('is_active', true)
        .order('created_at', { ascending: true })
        .limit(1)
        .maybeSingle();
      if (firstWarehouse.error) {
        return res.status(400).json({ error: firstWarehouse.error.message });
      }
      if (!firstWarehouse.data) {
        return res.status(400).json({ error: 'No warehouse configured. Please add a warehouse first.' });
      }
      warehouseId = String(firstWarehouse.data.id);
      warehouseName = String(firstWarehouse.data.name || 'Warehouse');
    }

    if (type === 'stock_out') {
      const stockRow = await supabaseAdmin
        .from('warehouse_product_stocks')
        .select('quantity')
        .eq('warehouse_id', warehouseId)
        .eq('product_id', productId)
        .eq('color_name', colorName)
        .maybeSingle();
      if (!stockRow.error && stockRow.data) {
        const available = Number(stockRow.data.quantity ?? 0);
        if (!Number.isFinite(available) || available < quantity) {
          return res.status(400).json({
            error: `Insufficient stock in ${warehouseName} for ${colorName}. Available: ${Math.max(
              0,
              Math.trunc(available),
            )}`,
          });
        }
      }
    }

    let workerId = String(payload.worker_id || '').trim() || null;
    let workerName = userName;

    if (workerId) {
      const { data: explicitWorker, error: workerErr } = await supabaseAdmin
        .from('workers')
        .select('id,name')
        .eq('id', workerId)
        .maybeSingle();
      
      if (explicitWorker) {
        workerName = explicitWorker.name;
      } else {
        // Fallback to current user if worker_id is invalid
        workerId = null;
      }
    }

    if (!workerId && userId) {
      // Worker OTP sessions use workers.id as session.sub (not users.id).
      if (sessionRole === 'worker' || (sessionRole === 'manager' && !userEmail)) {
        const byWorkerId = await supabaseAdmin
          .from('workers')
          .select('id,name')
          .eq('id', userId)
          .maybeSingle();
        if (byWorkerId.error || !byWorkerId.data) {
          return res.status(400).json({
            error: 'Worker session is invalid. Please log in again.',
          });
        }
        workerId = byWorkerId.data.id;
        workerName = String(byWorkerId.data.name || userName || 'Worker');
      } else {
        // Admin sessions use users.id as session.sub.
        let worker = null;
        let hasWorkerUserIdColumn = true;

        const byUser = await supabaseAdmin
          .from('workers')
          .select('id,name')
          .eq('user_id', userId)
          .maybeSingle();
        if (!byUser.error && byUser.data) {
          worker = byUser.data;
        } else if (
          byUser.error &&
          String(byUser.error.message || '')
            .toLowerCase()
            .includes("could not find the 'user_id' column")
        ) {
          hasWorkerUserIdColumn = false;
        }

        if (!worker && userEmail) {
          const byEmail = await supabaseAdmin
            .from('workers')
            .select(hasWorkerUserIdColumn ? 'id,name,user_id' : 'id,name')
            .eq('email', userEmail)
            .maybeSingle();
          if (!byEmail.error && byEmail.data) {
            worker = byEmail.data;
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
      const { color_name: _ignored, warehouse_id: _warehouseIdIgnored, warehouse_name: _warehouseNameIgnored, ...legacyRow } = insertRow;
      insertResult = await supabaseAdmin
        .from('transactions')
        .insert(legacyRow)
        .select('*')
        .single();
    }

    if (insertResult.error) {
      return res.status(400).json({ error: insertResult.error.message });
    }

    // Fire-and-forget push notifications for stock activity.
    sendStockTransactionPush(insertResult.data).catch(() => {});
    return res.json({ data: insertResult.data });
  }
);
