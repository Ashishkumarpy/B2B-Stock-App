import express from 'express';
import { supabaseAdmin } from '../supabase.js';
import { authRequired, requireRole } from '../auth.js';

export const usersRouter = express.Router();

usersRouter.get('/', authRequired, requireRole(['admin']), async (_req, res) => {
  const { data, error } = await supabaseAdmin
    .from('users')
    .select('*')
    .order('created_at', { ascending: false });
  if (error) return res.status(500).json({ error: error.message });
  return res.json({ data });
});

usersRouter.patch('/:id', authRequired, requireRole(['admin']), async (req, res) => {
  const id = req.params.id;
  const payload = req.body || {};
  const { data, error } = await supabaseAdmin
    .from('users')
    .update(payload)
    .eq('id', id)
    .select('*')
    .single();
  if (error) return res.status(400).json({ error: error.message });
  return res.json({ data });
});

usersRouter.delete('/:id', authRequired, requireRole(['admin']), async (req, res) => {
  const id = req.params.id;
  const { error } = await supabaseAdmin.from('users').delete().eq('id', id);
  if (error) return res.status(400).json({ error: error.message });
  return res.json({ ok: true });
});

