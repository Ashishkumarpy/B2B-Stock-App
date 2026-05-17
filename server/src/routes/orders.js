import express from 'express';
import { supabaseAdmin } from '../supabase.js';
import { authRequired, requireRole } from '../auth.js';

export const ordersRouter = express.Router();

ordersRouter.get('/', authRequired, requireRole(['admin']), async (_req, res) => {
  const { data, error } = await supabaseAdmin
    .from('orders')
    .select('*')
    .order('created_at', { ascending: false });
  if (error) return res.status(500).json({ error: error.message });
  return res.json({ data });
});

ordersRouter.patch('/:id', authRequired, requireRole(['admin']), async (req, res) => {
  const id = req.params.id;
  const payload = req.body || {};
  const { data, error } = await supabaseAdmin
    .from('orders')
    .update(payload)
    .eq('id', id)
    .select('*')
    .single();
  if (error) return res.status(400).json({ error: error.message });
  return res.json({ data });
});

