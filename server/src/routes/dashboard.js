import express from 'express';
import { supabaseAdmin } from '../supabase.js';
import { authRequired } from '../auth.js';
import { buildWarehouseStockSummary } from './warehouses.js';

export const dashboardRouter = express.Router();

// Aggregates everything the mobile dashboard needs into a single round trip:
// products, recent transactions and the warehouse stock summary. Replaces the
// 3-4 separate calls the dashboard used to fan out on every load/refresh, which
// is especially costly against a cold-starting backend.
//
// Transactions are gated by perm_inventory (mirroring GET /transactions) so a
// user without inventory access doesn't receive them — the rest of the
// dashboard (products, warehouses) still loads.
dashboardRouter.get('/', authRequired, async (req, res) => {
  const productLimit = Math.min(parseInt(req.query.productLimit, 10) || 1000, 5000);
  const txLimit = Math.min(parseInt(req.query.txLimit, 10) || 5000, 10000);

  const session = req.session || {};
  const perms = session.permissions || {};
  const canInventory = session.role === 'admin' || perms.perm_inventory === true;

  try {
    const [productsRes, txRes, warehouses] = await Promise.all([
      supabaseAdmin
        .from('products')
        .select('*')
        .order('name', { ascending: true })
        .range(0, productLimit - 1),
      canInventory
        ? supabaseAdmin
            .from('transactions')
            .select('*')
            .order('created_at', { ascending: false })
            .range(0, txLimit - 1)
        : Promise.resolve({ data: [], error: null }),
      buildWarehouseStockSummary(),
    ]);

    if (productsRes.error) {
      return res.status(500).json({ error: productsRes.error.message });
    }
    if (txRes.error) {
      return res.status(500).json({ error: txRes.error.message });
    }

    return res.json({
      products: productsRes.data || [],
      transactions: txRes.data || [],
      warehouses: warehouses || [],
    });
  } catch (e) {
    return res
      .status(500)
      .json({ error: e?.message || 'Failed to load dashboard' });
  }
});
