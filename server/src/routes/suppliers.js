import express from 'express';
import { supabaseAdmin } from '../supabase.js';
import { authRequired, requireRole } from '../auth.js';

export const suppliersRouter = express.Router();

suppliersRouter.get('/', authRequired, async (_req, res) => {
  const { data, error } = await supabaseAdmin
    .from('suppliers')
    .select('*')
    .order('name', { ascending: true });
  if (error) return res.status(500).json({ error: error.message });
  return res.json({ data });
});

suppliersRouter.post('/', authRequired, requireRole(['admin']), async (req, res) => {
  const payload = req.body || {};
  const { data, error } = await supabaseAdmin
    .from('suppliers')
    .insert(payload)
    .select('*')
    .single();
  if (error) return res.status(400).json({ error: error.message });
  return res.json({ data });
});

suppliersRouter.put('/:id', authRequired, requireRole(['admin']), async (req, res) => {
  const id = req.params.id;
  const payload = req.body || {};
  const { data, error } = await supabaseAdmin
    .from('suppliers')
    .update(payload)
    .eq('id', id)
    .select('*')
    .single();
  if (error) return res.status(400).json({ error: error.message });
  return res.json({ data });
});

suppliersRouter.delete('/:id', authRequired, requireRole(['admin']), async (req, res) => {
  const id = req.params.id;
  const { error } = await supabaseAdmin.from('suppliers').delete().eq('id', id);
  if (error) return res.status(400).json({ error: error.message });
  return res.json({ ok: true });
});

