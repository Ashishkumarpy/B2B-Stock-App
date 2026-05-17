import express from 'express';
import { supabaseAdmin } from '../supabase.js';
import { authRequired, requireRole } from '../auth.js';

export const workersRouter = express.Router();

function normalizePhone(phoneRaw) {
  const raw = String(phoneRaw || '').trim();
  if (!raw) return '';
  const keepPlus = raw.startsWith('+');
  const digits = raw.replace(/\D/g, '');
  return keepPlus ? `+${digits}` : digits;
}

function badRequestFromDbError(error, fallback = 'Request failed') {
  const message = String(error?.message || fallback);
  const code = String(error?.code || '');
  if (code === '23505' && message.toLowerCase().includes('phone')) {
    return 'This phone number is already registered.';
  }
  return message;
}

workersRouter.get('/', authRequired, async (req, res) => {
  const role = String(req.session?.role || '').trim();
  const subjectId = String(req.session?.sub || '').trim();

  if (role === 'admin') {
    const { data, error } = await supabaseAdmin
      .from('workers')
      .select('*')
      .order('created_at', { ascending: false });
    if (error) return res.status(500).json({ error: error.message });
    return res.json({ data });
  }

  if (role === 'worker' || role === 'manager') {
    if (!subjectId) return res.status(401).json({ error: 'Unauthorized' });
    const { data, error } = await supabaseAdmin
      .from('workers')
      .select('*')
      .eq('id', subjectId)
      .maybeSingle();
    if (error) return res.status(500).json({ error: error.message });
    if (!data) return res.status(404).json({ error: 'Worker profile not found' });
    return res.json({ data: [data] });
  }

  return res.status(403).json({ error: 'Forbidden' });
});

workersRouter.post('/', authRequired, requireRole(['admin']), async (req, res) => {
  const payload = req.body || {};
  const name = String(payload.name || '').trim();
  const phone = normalizePhone(payload.phone);
  const role = String(payload.role || 'worker').trim();
  const canAccessStock =
    payload.can_access_stock === undefined ? true : Boolean(payload.can_access_stock);

  if (!name) return res.status(400).json({ error: 'name is required' });
  if (!phone) return res.status(400).json({ error: 'phone is required' });
  if (phone.replace(/\D/g, '').length < 10) {
    return res.status(400).json({ error: 'phone must be at least 10 digits' });
  }
  if (!['worker', 'manager'].includes(role)) {
    return res.status(400).json({ error: 'role must be worker or manager' });
  }

  const sanitized = {
    name,
    phone,
    role,
    can_access_stock: canAccessStock,
    is_active: payload.is_active === undefined ? true : Boolean(payload.is_active),
    email: payload.email ? String(payload.email).trim() : null
  };

  const { data, error } = await supabaseAdmin
    .from('workers')
    .insert(sanitized)
    .select('*')
    .single();
  if (error) {
    return res.status(400).json({ error: badRequestFromDbError(error, 'Failed to create worker') });
  }
  return res.json({ data });
});

workersRouter.put('/:id', authRequired, requireRole(['admin']), async (req, res) => {
  const id = req.params.id;
  const payload = req.body || {};
  const name = String(payload.name || '').trim();
  const phone = normalizePhone(payload.phone);
  const role = String(payload.role || 'worker').trim();
  const canAccessStock =
    payload.can_access_stock === undefined ? true : Boolean(payload.can_access_stock);

  if (!name) return res.status(400).json({ error: 'name is required' });
  if (!phone) return res.status(400).json({ error: 'phone is required' });
  if (phone.replace(/\D/g, '').length < 10) {
    return res.status(400).json({ error: 'phone must be at least 10 digits' });
  }
  if (!['worker', 'manager'].includes(role)) {
    return res.status(400).json({ error: 'role must be worker or manager' });
  }

  const sanitized = {
    name,
    phone,
    role,
    can_access_stock: canAccessStock,
    is_active: payload.is_active === undefined ? true : Boolean(payload.is_active),
    email: payload.email ? String(payload.email).trim() : null
  };

  const { data, error } = await supabaseAdmin
    .from('workers')
    .update(sanitized)
    .eq('id', id)
    .select('*')
    .single();
  if (error) {
    return res.status(400).json({ error: badRequestFromDbError(error, 'Failed to update worker') });
  }
  return res.json({ data });
});

workersRouter.delete('/:id', authRequired, requireRole(['admin']), async (req, res) => {
  const id = req.params.id;

  // Unlink transactions to prevent them from being deleted (preserve history)
  await supabaseAdmin
    .from('transactions')
    .update({ worker_id: null })
    .eq('worker_id', id);

  const { error } = await supabaseAdmin.from('workers').delete().eq('id', id);
  if (error) return res.status(400).json({ error: error.message });
  return res.json({ ok: true });
});
