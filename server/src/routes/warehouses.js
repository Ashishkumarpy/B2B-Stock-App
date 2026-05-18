import express from 'express';
import { supabaseAdmin } from '../supabase.js';
import { authRequired, requireRole } from '../auth.js';

export const warehousesRouter = express.Router();

warehousesRouter.get('/', authRequired, async (_req, res) => {
  const includeInactive =
    String(_req.query?.include_inactive || '').trim().toLowerCase() === 'true';
  let query = supabaseAdmin
    .from('warehouses')
    .select('*')
    .order('name', { ascending: true });
  if (!includeInactive) {
    query = query.eq('is_active', true);
  }
  const { data, error } = await query;
  if (error) return res.status(500).json({ error: error.message });
  return res.json({ data });
});

warehousesRouter.post(
  '/',
  authRequired,
  requireRole(['admin', 'manager']),
  async (req, res) => {
    const payload = req.body || {};
    const name = String(payload.name || '').trim();
    const code = String(payload.code || '').trim();
    const location = String(payload.location || '').trim();

    if (!name) {
      return res.status(400).json({ error: 'name is required' });
    }

    const { data, error } = await supabaseAdmin
      .from('warehouses')
      .insert({
        name,
        code: code === '' ? null : code,
        location: location === '' ? null : location,
        is_active: true
      })
      .select('*')
      .single();

    if (error) return res.status(400).json({ error: error.message });
    return res.json({ data });
  }
);

warehousesRouter.put(
  '/:id',
  authRequired,
  requireRole(['admin', 'manager']),
  async (req, res) => {
    const id = req.params.id;
    const payload = req.body || {};
    const updateRow = {};

    if (typeof payload.name === 'string') {
      updateRow.name = payload.name.trim();
    }
    if (typeof payload.code === 'string') {
      const code = payload.code.trim();
      updateRow.code = code === '' ? null : code;
    }
    if (typeof payload.location === 'string') {
      const location = payload.location.trim();
      updateRow.location = location === '' ? null : location;
    }
    if (typeof payload.is_active === 'boolean') {
      updateRow.is_active = payload.is_active;
    }

    const { data, error } = await supabaseAdmin
      .from('warehouses')
      .update(updateRow)
      .eq('id', id)
      .select('*')
      .single();

    if (error) return res.status(400).json({ error: error.message });
    return res.json({ data });
  }
);
