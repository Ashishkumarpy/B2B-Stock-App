import express from 'express';
import { supabaseAdmin } from '../supabase.js';
import { authRequired, requirePermission } from '../auth.js';
import { logActivity } from '../activity_logger.js';

export const ordersRouter = express.Router();

ordersRouter.get('/', authRequired, requirePermission('perm_orders'), async (_req, res) => {
  const { data, error } = await supabaseAdmin
    .from('orders')
    .select('*')
    .order('created_at', { ascending: false });
  if (error) return res.status(500).json({ error: error.message });
  return res.json({ data });
});

ordersRouter.patch('/:id', authRequired, requirePermission('perm_orders'), async (req, res) => {
  const id = req.params.id;
  const payload = req.body || {};
  const { data, error } = await supabaseAdmin
    .from('orders')
    .update(payload)
    .eq('id', id)
    .select('*')
    .single();
  if (error) return res.status(400).json({ error: error.message });

  if (payload.status) {
    const isDispatched = payload.status === 'shipped';
    await logActivity({
      actorId: req.session.sub,
      actorName: req.session.name,
      actionType: isDispatched ? 'order_dispatch' : 'order_status_update',
      description: isDispatched
        ? `Dispatched order for ${data.customer_name} (Total: $${data.total})`
        : `Updated order status for ${data.customer_name} to ${payload.status}`,
      metadata: {
        order_id: id,
        status: payload.status,
        customer: data.customer_name
      }
    });
  }

  return res.json({ data });
});
