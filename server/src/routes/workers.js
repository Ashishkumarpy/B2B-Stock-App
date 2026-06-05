import express from 'express';
import { supabaseAdmin } from '../supabase.js';
import { authRequired, requirePermission } from '../auth.js';
import { logActivity } from '../activity_logger.js';

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

const PERMISSION_KEYS = [
  'perm_products',
  'perm_inventory',
  'perm_orders',
  'perm_reports',
  'perm_users',
  'perm_settings'
];

function defaultPermissionsForRole(role) {
  if (role === 'manager') {
    return {
      perm_products: false,
      perm_inventory: true,
      perm_orders: true,
      perm_reports: true,
      perm_users: true,
      perm_settings: false
    };
  }
  return {
    perm_products: false,
    perm_inventory: true,
    perm_orders: false,
    perm_reports: false,
    perm_users: false,
    perm_settings: false
  };
}

function buildPermissionUpdate(permissions, role, { useDefaults = false } = {}) {
  const source = permissions && typeof permissions === 'object'
    ? permissions
    : useDefaults
      ? defaultPermissionsForRole(role)
      : {};
  const update = {};
  for (const key of PERMISSION_KEYS) {
    if (source[key] !== undefined) {
      update[key] = !!source[key];
    }
  }
  return update;
}

async function attachLinkedUserPermissions(workers) {
  const rows = workers ?? [];
  const userIds = [...new Set(rows.map(row => row.user_id).filter(Boolean))];
  if (userIds.length === 0) return rows;

  const { data: linkedUsers, error } = await supabaseAdmin
    .from('users')
    .select(`id,${PERMISSION_KEYS.join(',')}`)
    .in('id', userIds);

  if (error) throw error;

  const usersById = new Map((linkedUsers ?? []).map(user => [user.id, user]));
  return rows.map(row => {
    const linkedUser = usersById.get(row.user_id);
    if (!linkedUser) return row;

    const merged = { ...row };
    for (const key of PERMISSION_KEYS) {
      if (linkedUser[key] !== undefined && linkedUser[key] !== null) {
        merged[key] = linkedUser[key];
      }
    }
    return merged;
  });
}

// Get all workers (filtered by warehouse scope for managers)
workersRouter.get('/', authRequired, requirePermission('perm_users'), async (req, res) => {
  const sessionRole = String(req.session?.role || '').trim();
  const sessionUserId = String(req.session?.sub || '').trim();

  if (sessionRole === 'admin') {
    const { data, error } = await supabaseAdmin
      .from('workers')
      .select('*')
      .in('role', ['worker', 'manager'])
      .order('created_at', { ascending: false });
    if (error) return res.status(500).json({ error: error.message });
    try {
      return res.json({ data: await attachLinkedUserPermissions(data) });
    } catch (e) {
      return res.status(500).json({ error: e.message });
    }
  }

  if (sessionRole === 'manager') {
    if (!sessionUserId) return res.status(401).json({ error: 'Unauthorized' });

    // 1. Fetch warehouses assigned to this manager (either via user_id or worker_id)
    const { data: managerWarehouses, error: mwError } = await supabaseAdmin
      .from('user_warehouses')
      .select('warehouse_id')
      .or(`user_id.eq.${sessionUserId},worker_id.eq.${sessionUserId}`);

    if (mwError) return res.status(500).json({ error: mwError.message });
    const warehouseIds = (managerWarehouses ?? []).map(mw => mw.warehouse_id);

    if (warehouseIds.length === 0) {
      return res.json({ data: [] });
    }

    // 2. Fetch all user/worker assignments for these warehouses
    const { data: assignments, error: uaError } = await supabaseAdmin
      .from('user_warehouses')
      .select('user_id, worker_id')
      .in('warehouse_id', warehouseIds);

    if (uaError) return res.status(500).json({ error: uaError.message });
    
    const workerUserIds = [...new Set((assignments ?? []).map(ua => ua.user_id).filter(Boolean))];
    const workerIds = [...new Set((assignments ?? []).map(ua => ua.worker_id).filter(Boolean))];

    if (workerUserIds.length === 0 && workerIds.length === 0) {
      return res.json({ data: [] });
    }

    // 3. Fetch workers belonging to these user accounts or matching the worker IDs directly
    let query = supabaseAdmin
      .from('workers')
      .select('*')
      .in('role', ['worker', 'manager']);
    
    const orConditions = [];
    if (workerUserIds.length > 0) {
      orConditions.push(`user_id.in.(${workerUserIds.join(',')})`);
    }
    if (workerIds.length > 0) {
      orConditions.push(`id.in.(${workerIds.join(',')})`);
    }

    if (orConditions.length > 0) {
      query = query.or(orConditions.join(','));
    }

    const { data, error } = await query.order('created_at', { ascending: false });

    if (error) return res.status(500).json({ error: error.message });
    try {
      return res.json({ data: await attachLinkedUserPermissions(data) });
    } catch (e) {
      return res.status(500).json({ error: e.message });
    }
  }

  // Workers cannot manage users
  return res.status(403).json({ error: 'Forbidden' });
});

// Create a worker profile
workersRouter.post('/', authRequired, requirePermission('perm_users'), async (req, res) => {
  const payload = req.body || {};
  const name = String(payload.name || '').trim();
  const phone = normalizePhone(payload.phone);
  const role = String(payload.role || 'worker').trim();
  const canAccessStock =
    payload.can_access_stock === undefined ? true : Boolean(payload.can_access_stock);
  const permissionUpdate = buildPermissionUpdate(payload.permissions, role, {
    useDefaults: true
  });

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
    is_active: payload.is_active === undefined ? true : Boolean(payload.is_active),
    email: payload.email ? String(payload.email).trim() : null,
    ...permissionUpdate,
    can_access_stock: permissionUpdate.perm_inventory ?? canAccessStock
  };

  const { data, error } = await supabaseAdmin
    .from('workers')
    .insert(sanitized)
    .select('*')
    .single();

  if (error) {
    return res.status(400).json({ error: badRequestFromDbError(error, 'Failed to create worker') });
  }

  // Log activity
  await logActivity({
    actorId: req.session.sub,
    actorName: req.session.name,
    actionType: 'worker_create',
    description: `Created worker profile for ${name} (${phone})`,
    metadata: { worker_id: data.id, role: data.role }
  });

  return res.json({ data });
});

// Update a worker profile (restricted by warehouse scope for managers)
workersRouter.put('/:id', authRequired, requirePermission('perm_users'), async (req, res) => {
  const id = req.params.id;
  const sessionRole = String(req.session?.role || '').trim();
  const sessionUserId = String(req.session?.sub || '').trim();

  // Load existing worker profile
  const { data: existingWorker, error: loadError } = await supabaseAdmin
    .from('workers')
    .select('*')
    .eq('id', id)
    .maybeSingle();

  if (loadError || !existingWorker) {
    return res.status(404).json({ error: 'Worker not found' });
  }
  if (existingWorker.role === 'admin') {
    return res.status(403).json({ error: 'Admin accounts cannot be edited from Manage Workers.' });
  }

  // Warehouse check for managers
  if (sessionRole === 'manager') {
    const { data: shares } = await supabaseAdmin.rpc('share_warehouse', {
      user_a: sessionUserId,
      user_b: existingWorker.user_id || existingWorker.id
    });
    if (!shares) {
      return res.status(403).json({ error: 'Forbidden: Worker does not belong to your assigned warehouses.' });
    }
  }

  const payload = req.body || {};
  const name = String(payload.name || '').trim();
  const phone = normalizePhone(payload.phone);
  const role = String(payload.role || 'worker').trim();
  const canAccessStock =
    payload.can_access_stock === undefined
      ? existingWorker.can_access_stock ?? true
      : Boolean(payload.can_access_stock);
  const permissionUpdate = buildPermissionUpdate(payload.permissions, role);

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
    is_active: payload.is_active === undefined ? true : Boolean(payload.is_active),
    email: payload.email ? String(payload.email).trim() : null,
    ...permissionUpdate,
    can_access_stock: permissionUpdate.perm_inventory ?? canAccessStock
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

  if (existingWorker.user_id) {
    const linkedUserUpdate = {
      name,
      role,
      is_active: sanitized.is_active
    };

    const { error: userProfileError } = await supabaseAdmin
      .from('users')
      .update(linkedUserUpdate)
      .eq('id', existingWorker.user_id);
    if (userProfileError) {
      return res.status(400).json({ error: userProfileError.message });
    }

    if (Object.keys(permissionUpdate).length > 0) {
      const { error: userPermissionError } = await supabaseAdmin
        .from('users')
        .update(permissionUpdate)
        .eq('id', existingWorker.user_id);
      if (userPermissionError) {
        return res.status(400).json({ error: userPermissionError.message });
      }
    }
  }

  // Log activity
  await logActivity({
    actorId: req.session.sub,
    actorName: req.session.name,
    actionType: 'worker_edit',
    description: `Updated worker profile for ${name}`,
    metadata: { worker_id: id }
  });

  return res.json({ data });
});

// Delete a worker profile (restricted by warehouse scope for managers)
workersRouter.delete('/:id', authRequired, requirePermission('perm_users'), async (req, res) => {
  const id = req.params.id;
  const sessionRole = String(req.session?.role || '').trim();
  const sessionUserId = String(req.session?.sub || '').trim();

  // Load existing worker profile
  const { data: existingWorker, error: loadError } = await supabaseAdmin
    .from('workers')
    .select('*')
    .eq('id', id)
    .maybeSingle();

  if (loadError || !existingWorker) {
    return res.status(404).json({ error: 'Worker not found' });
  }
  if (existingWorker.role === 'admin') {
    return res.status(403).json({ error: 'Admin accounts cannot be removed from Manage Workers.' });
  }

  // Warehouse check for managers
  if (sessionRole === 'manager') {
    const { data: shares } = await supabaseAdmin.rpc('share_warehouse', {
      user_a: sessionUserId,
      user_b: existingWorker.user_id || existingWorker.id
    });
    if (!shares) {
      return res.status(403).json({ error: 'Forbidden: Worker does not belong to your assigned warehouses.' });
    }
  }

  // Unlink transactions to prevent them from being deleted (preserve history)
  await supabaseAdmin
    .from('transactions')
    .update({ worker_id: null })
    .eq('worker_id', id);

  const { error } = await supabaseAdmin.from('workers').delete().eq('id', id);
  if (error) return res.status(400).json({ error: error.message });

  // Log activity
  await logActivity({
    actorId: req.session.sub,
    actorName: req.session.name,
    actionType: 'worker_delete',
    description: `Deleted worker profile ${existingWorker.name}`,
    metadata: { worker_id: id, name: existingWorker.name }
  });

  return res.json({ ok: true });
});
