import express from 'express';
import { supabaseAdmin } from '../supabase.js';
import { authRequired, requirePermission } from '../auth.js';
import { logActivity } from '../activity_logger.js';

export const usersRouter = express.Router();

function normalizePhone(phoneRaw) {
  const raw = String(phoneRaw || '').trim();
  if (!raw) return '';
  const keepPlus = raw.startsWith('+');
  const digits = raw.replace(/\D/g, '');
  return keepPlus ? `+${digits}` : digits;
}

// Fetch activity logs for the User Management dashboard
usersRouter.get('/activities', authRequired, requirePermission('perm_users'), async (req, res) => {
  const limit = parseInt(req.query.limit) || 100;
  const { data, error } = await supabaseAdmin
    .from('activity_logs')
    .select('*')
    .order('created_at', { ascending: false })
    .limit(limit);

  if (error) return res.status(500).json({ error: error.message });
  return res.json({ data });
});

// Fetch login history for the User Management dashboard
usersRouter.get('/logins', authRequired, requirePermission('perm_users'), async (req, res) => {
  const limit = parseInt(req.query.limit) || 100;
  const { data, error } = await supabaseAdmin
    .from('login_history')
    .select('*')
    .order('created_at', { ascending: false })
    .limit(limit);

  if (error) return res.status(500).json({ error: error.message });
  return res.json({ data });
});

// Fetch all users (from public.users) and phone-only workers (from public.workers) merged
usersRouter.get('/', authRequired, requirePermission('perm_users'), async (req, res) => {
  try {
    const sessionRole = String(req.session?.role || '').trim();
    const sessionUserId = String(req.session?.sub || '').trim();

    // 1. Fetch users from public.users with their warehouse assignments
    const { data: usersData, error: usersError } = await supabaseAdmin
      .from('users')
      .select('*, user_warehouses(warehouse_id)')
      .order('created_at', { ascending: false });

    if (usersError) return res.status(500).json({ error: usersError.message });

    // 2. Fetch workers from public.workers to map phones and append phone-only profiles
    const { data: workersData, error: workersError } = await supabaseAdmin
      .from('workers')
      .select('*');

    if (workersError) return res.status(500).json({ error: workersError.message });

    // 2.5 Fetch all warehouse mappings from user_warehouses to assign to phone-only workers
    const { data: allWarehouseMappings, error: mappingsError } = await supabaseAdmin
      .from('user_warehouses')
      .select('*');

    if (mappingsError) return res.status(500).json({ error: mappingsError.message });

    // Map of worker_id to warehouse_ids
    const workerWarehouseMap = new Map();
    (allWarehouseMappings ?? []).forEach(m => {
      if (m.worker_id) {
        if (!workerWarehouseMap.has(m.worker_id)) {
          workerWarehouseMap.set(m.worker_id, []);
        }
        workerWarehouseMap.get(m.worker_id).push(m.warehouse_id);
      }
    });

    // Map of user_id to worker properties (phone, active status, email)
    const workerInfoMap = new Map();
    const linkedUserIds = new Set();

    (workersData ?? []).forEach(w => {
      if (w.user_id) {
        workerInfoMap.set(w.user_id, {
          phone: w.phone,
          email: w.email,
          is_active: w.is_active
        });
        linkedUserIds.add(w.user_id);
      }
    });

    // Format profiles from public.users
    const formattedUsers = (usersData ?? []).map(user => {
      const workerInfo = workerInfoMap.get(user.id);
      return {
        id: user.id,
        name: user.name,
        email: user.email,
        phone: workerInfo?.phone || null,
        role: user.role,
        is_active: user.is_active ?? true,
        created_at: user.created_at,
        is_phone_only: false,
        permissions: {
          perm_products: user.perm_products ?? false,
          perm_inventory: user.perm_inventory ?? false,
          perm_orders: user.perm_orders ?? false,
          perm_reports: user.perm_reports ?? false,
          perm_users: user.perm_users ?? false,
          perm_settings: user.perm_settings ?? false
        },
        warehouses: user.user_warehouses ? user.user_warehouses.map(uw => uw.warehouse_id) : []
      };
    });

    // Synthesize phone-only workers that are NOT linked to any users account
    const phoneOnlyUsers = (workersData ?? [])
      .filter(w => !w.user_id)
      .map(w => {
        const isManager = w.role === 'manager';
        return {
          id: w.id, // worker.id
          name: w.name,
          email: w.email || null,
          phone: w.phone || null,
          role: w.role || 'worker',
          is_active: w.is_active ?? true,
          created_at: w.created_at,
          is_phone_only: true,
          permissions: {
            perm_products: false,
            perm_inventory: true,
            perm_orders: isManager,
            perm_reports: isManager,
            perm_users: isManager,
            perm_settings: false
          },
          warehouses: workerWarehouseMap.get(w.id) || []
        };
      });

    // Combine users & phone-only profiles
    let mergedList = [...formattedUsers, ...phoneOnlyUsers];

    // Apply warehouse scoping if the logged-in user is a MANAGER
    if (sessionRole === 'manager') {
      // Find warehouses assigned to this manager (either as user_id or worker_id)
      const managerWarehouses = (allWarehouseMappings ?? [])
        .filter(m => m.user_id === sessionUserId || m.worker_id === sessionUserId)
        .map(m => m.warehouse_id);

      if (managerWarehouses.length === 0) {
        // If manager has no warehouses assigned, they can only see their own profile
        mergedList = mergedList.filter(u => u.id === sessionUserId);
      } else {
        // Keep users/workers who share at least one warehouse with this manager OR are the manager themselves
        mergedList = mergedList.filter(u => {
          if (u.id === sessionUserId) return true;
          return u.warehouses.some(wId => managerWarehouses.includes(wId));
        });
      }
    }

    mergedList.sort((a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime());

    return res.json({ data: mergedList });
  } catch (err) {
    console.error('Error fetching users/workers directory:', err);
    return res.status(500).json({ error: 'Internal server error' });
  }
});

// Create a new user in Supabase Auth & Profile (creating both users & worker records)
usersRouter.post('/', authRequired, requirePermission('perm_users'), async (req, res) => {
  const { email, password, name, role, is_active, warehouses, permissions, phone } = req.body || {};
  if (!email || !password || !name) {
    return res.status(400).json({ error: 'Email, password, and name are required' });
  }

  try {
    // 1. Create the user in Supabase Auth
    const { data: authData, error: authError } = await supabaseAdmin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: { name }
    });

    if (authError) return res.status(400).json({ error: authError.message });
    const authUser = authData.user;

    // 2. Set profile permissions and active status
    const payload = {
      name,
      role: role || 'worker',
      is_active: is_active !== false,
      perm_products: !!permissions?.perm_products,
      perm_inventory: !!permissions?.perm_inventory,
      perm_orders: !!permissions?.perm_orders,
      perm_reports: !!permissions?.perm_reports,
      perm_users: !!permissions?.perm_users,
      perm_settings: !!permissions?.perm_settings,
    };

    const { data: profile, error: profileError } = await supabaseAdmin
      .from('users')
      .update(payload)
      .eq('id', authUser.id)
      .select('*')
      .single();

    if (profileError) return res.status(400).json({ error: profileError.message });

    // 3. Assign warehouses
    if (Array.isArray(warehouses) && warehouses.length > 0) {
      const insertRows = warehouses.map(wId => ({
        user_id: authUser.id,
        warehouse_id: wId
      }));
      await supabaseAdmin.from('user_warehouses').insert(insertRows);
    }

    // 4. Update corresponding worker phone number if provided
    if (phone) {
      await supabaseAdmin
        .from('workers')
        .update({ phone: normalizePhone(phone) })
        .eq('user_id', authUser.id);
    }

    // 5. Log the activity
    await logActivity({
      actorId: req.session.sub,
      actorName: req.session.name,
      actionType: 'user_create',
      description: `Created user ${name} (${email}) with role ${role || 'worker'}`,
      metadata: { created_user_id: authUser.id, role }
    });

    return res.json({
      data: {
        id: profile.id,
        name: profile.name,
        email: profile.email,
        phone: phone || null,
        role: profile.role,
        is_active: profile.is_active,
        created_at: profile.created_at,
        permissions: {
          perm_products: profile.perm_products,
          perm_inventory: profile.perm_inventory,
          perm_orders: profile.perm_orders,
          perm_reports: profile.perm_reports,
          perm_users: profile.perm_users,
          perm_settings: profile.perm_settings
        },
        warehouses: warehouses || []
      }
    });
  } catch (e) {
    console.error('Error creating user:', e);
    return res.status(500).json({ error: 'Internal server error' });
  }
});

// Update a user/worker (supporting both users and phone-only workers, with upgrade support)
usersRouter.patch('/:id', authRequired, requirePermission('perm_users'), async (req, res) => {
  const id = req.params.id;
  const { name, role, is_active, warehouses, permissions, email, password, phone } = req.body || {};

  try {
    // 1. Check if user exists in public.users table
    const { data: existingUser, error: fetchErr } = await supabaseAdmin
      .from('users')
      .select('*')
      .eq('id', id)
      .maybeSingle();

    if (fetchErr) return res.status(500).json({ error: fetchErr.message });

    // A. User exists in public.users table
    if (existingUser) {
      const profileUpdate = {};
      if (name !== undefined) profileUpdate.name = name;
      if (role !== undefined) profileUpdate.role = role;
      if (is_active !== undefined) profileUpdate.is_active = is_active;

      if (permissions) {
        if (permissions.perm_products !== undefined) profileUpdate.perm_products = permissions.perm_products;
        if (permissions.perm_inventory !== undefined) profileUpdate.perm_inventory = permissions.perm_inventory;
        if (permissions.perm_orders !== undefined) profileUpdate.perm_orders = permissions.perm_orders;
        if (permissions.perm_reports !== undefined) profileUpdate.perm_reports = permissions.perm_reports;
        if (permissions.perm_users !== undefined) profileUpdate.perm_users = permissions.perm_users;
        if (permissions.perm_settings !== undefined) profileUpdate.perm_settings = permissions.perm_settings;
      }

      if (email && email !== existingUser.email) {
        const { error: authError } = await supabaseAdmin.auth.admin.updateUserById(id, { email });
        if (authError) return res.status(400).json({ error: authError.message });
        profileUpdate.email = email;
      }

      // Update User Profile
      const { data: updatedProfile, error: updateErr } = await supabaseAdmin
        .from('users')
        .update(profileUpdate)
        .eq('id', id)
        .select('*')
        .single();

      if (updateErr) return res.status(400).json({ error: updateErr.message });

      // Update phone in workers table if provided
      if (phone !== undefined) {
        await supabaseAdmin
          .from('workers')
          .update({ phone: normalizePhone(phone) })
          .eq('user_id', id);
      }

      // Update warehouse mappings
      if (warehouses !== undefined && Array.isArray(warehouses)) {
        await supabaseAdmin.from('user_warehouses').delete().eq('user_id', id);
        if (warehouses.length > 0) {
          const insertRows = warehouses.map(wId => ({
            user_id: id,
            warehouse_id: wId
          }));
          await supabaseAdmin.from('user_warehouses').insert(insertRows);
        }
      }

      // Track differences and log activity
      const changes = [];
      if (role !== undefined && role !== existingUser.role) changes.push(`role: ${existingUser.role} -> ${role}`);
      if (is_active !== undefined && is_active !== existingUser.is_active) {
        changes.push(is_active ? 'enabled' : 'disabled');
      }

      const permChanges = [];
      if (permissions) {
        Object.keys(permissions).forEach(k => {
          if (permissions[k] !== existingUser[k]) {
            permChanges.push(`${k}: ${existingUser[k]} -> ${permissions[k]}`);
          }
        });
      }

      const description = `Updated user ${updatedProfile.name}. ` +
        (changes.length > 0 ? `Changes: ${changes.join(', ')}. ` : '') +
        (permChanges.length > 0 ? `Permission changes: ${permChanges.join(', ')}` : '');

      await logActivity({
        actorId: req.session.sub,
        actorName: req.session.name,
        actionType: 'user_edit',
        description,
        metadata: {
          edited_user_id: id,
          role_changed: role !== undefined && role !== existingUser.role,
          disabled_changed: is_active !== undefined && is_active !== existingUser.is_active,
          permission_changes: permChanges
        }
      });

      return res.json({
        data: {
          id: updatedProfile.id,
          name: updatedProfile.name,
          email: updatedProfile.email,
          phone: phone !== undefined ? phone : null,
          role: updatedProfile.role,
          is_active: updatedProfile.is_active,
          created_at: updatedProfile.created_at,
          is_phone_only: false,
          permissions: {
            perm_products: updatedProfile.perm_products,
            perm_inventory: updatedProfile.perm_inventory,
            perm_orders: updatedProfile.perm_orders,
            perm_reports: updatedProfile.perm_reports,
            perm_users: updatedProfile.perm_users,
            perm_settings: updatedProfile.perm_settings
          },
          warehouses: warehouses !== undefined ? warehouses : []
        }
      });
    }

    // B. User does NOT exist in public.users, check if it's in public.workers (phone-only profile)
    const { data: existingWorker, error: workerFetchErr } = await supabaseAdmin
      .from('workers')
      .select('*')
      .eq('id', id)
      .maybeSingle();

    if (workerFetchErr || !existingWorker) {
      return res.status(404).json({ error: 'User or Worker profile not found' });
    }

    // If email and password are provided, "upgrade" the phone-only worker to a full auth users account!
    if (email && password) {
      // 1. Register in Supabase Auth
      const { data: authData, error: authError } = await supabaseAdmin.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
        user_metadata: { name: name || existingWorker.name }
      });

      if (authError) return res.status(400).json({ error: authError.message });
      const authUser = authData.user;

      // 2. Set profile properties
      const payload = {
        name: name || existingWorker.name,
        role: role || existingWorker.role || 'worker',
        is_active: is_active !== undefined ? is_active : existingWorker.is_active ?? true,
        perm_products: !!permissions?.perm_products,
        perm_inventory: !!permissions?.perm_inventory,
        perm_orders: !!permissions?.perm_orders,
        perm_reports: !!permissions?.perm_reports,
        perm_users: !!permissions?.perm_users,
        perm_settings: !!permissions?.perm_settings,
      };

      const { data: profile, error: profileError } = await supabaseAdmin
        .from('users')
        .update(payload)
        .eq('id', authUser.id)
        .select('*')
        .single();

      if (profileError) return res.status(400).json({ error: profileError.message });

      // 3. Link existing workers table row to authUser
      await supabaseAdmin
        .from('workers')
        .update({
          user_id: authUser.id,
          phone: phone !== undefined ? normalizePhone(phone) : existingWorker.phone,
          is_active: is_active !== undefined ? is_active : existingWorker.is_active ?? true
        })
        .eq('id', id);

      // 4. Assign warehouses (moving from worker_id mappings to user_id mappings)
      await supabaseAdmin.from('user_warehouses').delete().eq('worker_id', id);
      if (Array.isArray(warehouses) && warehouses.length > 0) {
        const insertRows = warehouses.map(wId => ({
          user_id: authUser.id,
          warehouse_id: wId
        }));
        await supabaseAdmin.from('user_warehouses').insert(insertRows);
      }

      await logActivity({
        actorId: req.session.sub,
        actorName: req.session.name,
        actionType: 'user_edit',
        description: `Upgraded phone-only worker ${existingWorker.name} to email account ${email}`,
        metadata: { worker_id: id, user_id: authUser.id }
      });

      return res.json({
        data: {
          id: profile.id,
          name: profile.name,
          email: profile.email,
          phone: phone !== undefined ? phone : existingWorker.phone,
          role: profile.role,
          is_active: profile.is_active,
          created_at: profile.created_at,
          is_phone_only: false,
          permissions: {
            perm_products: profile.perm_products,
            perm_inventory: profile.perm_inventory,
            perm_orders: profile.perm_orders,
            perm_reports: profile.perm_reports,
            perm_users: profile.perm_users,
            perm_settings: profile.perm_settings
          },
          warehouses: warehouses || []
        }
      });
    }

    // Otherwise, just update properties inside workers table directly
    const workerUpdate = {};
    if (name !== undefined) workerUpdate.name = name;
    if (phone !== undefined) workerUpdate.phone = normalizePhone(phone);
    if (role !== undefined) workerUpdate.role = role;
    if (is_active !== undefined) workerUpdate.is_active = is_active;
    if (email !== undefined) workerUpdate.email = email;

    const { data: updatedWorker, error: updateErr } = await supabaseAdmin
      .from('workers')
      .update(workerUpdate)
      .eq('id', id)
      .select('*')
      .single();

    if (updateErr) return res.status(400).json({ error: updateErr.message });

    // Update warehouse assignments for phone-only workers
    if (warehouses !== undefined && Array.isArray(warehouses)) {
      await supabaseAdmin.from('user_warehouses').delete().eq('worker_id', id);
      if (warehouses.length > 0) {
        const insertRows = warehouses.map(wId => ({
          worker_id: id,
          warehouse_id: wId
        }));
        await supabaseAdmin.from('user_warehouses').insert(insertRows);
      }
    }

    await logActivity({
      actorId: req.session.sub,
      actorName: req.session.name,
      actionType: 'worker_edit',
      description: `Updated phone-only worker profile ${updatedWorker.name}`,
      metadata: { worker_id: id }
    });

    const isManager = updatedWorker.role === 'manager';
    return res.json({
      data: {
        id: updatedWorker.id,
        name: updatedWorker.name,
        email: updatedWorker.email,
        phone: updatedWorker.phone,
        role: updatedWorker.role,
        is_active: updatedWorker.is_active,
        created_at: updatedWorker.created_at,
        is_phone_only: true,
        permissions: {
          perm_products: false,
          perm_inventory: true,
          perm_orders: isManager,
          perm_reports: isManager,
          perm_users: isManager,
          perm_settings: false
        },
        warehouses: warehouses !== undefined ? warehouses : []
      }
    });
  } catch (e) {
    console.error('Error updating user/worker:', e);
    return res.status(500).json({ error: 'Internal server error' });
  }
});

// Delete a user or phone-only worker
usersRouter.delete('/:id', authRequired, requirePermission('perm_users'), async (req, res) => {
  const id = req.params.id;

  try {
    // 1. Try to fetch from users
    const { data: user } = await supabaseAdmin.from('users').select('name, email').eq('id', id).maybeSingle();

    if (user) {
      const name = `${user.name} (${user.email})`;
      const { error } = await supabaseAdmin.auth.admin.deleteUser(id);
      if (error) return res.status(400).json({ error: error.message });

      await logActivity({
        actorId: req.session.sub,
        actorName: req.session.name,
        actionType: 'user_delete',
        description: `Deleted user ${name}`,
        metadata: { deleted_user_id: id }
      });
      return res.json({ ok: true });
    }

    // 2. If not found in users, check in workers table
    const { data: worker } = await supabaseAdmin.from('workers').select('name, phone').eq('id', id).maybeSingle();
    if (!worker) {
      return res.status(404).json({ error: 'User or Worker profile not found' });
    }

    // Unlink transactions to preserve audit history
    await supabaseAdmin
      .from('transactions')
      .update({ worker_id: null })
      .eq('worker_id', id);

    const { error: deleteErr } = await supabaseAdmin.from('workers').delete().eq('id', id);
    if (deleteErr) return res.status(400).json({ error: deleteErr.message });

    await logActivity({
      actorId: req.session.sub,
      actorName: req.session.name,
      actionType: 'worker_delete',
      description: `Deleted phone-only worker ${worker.name}`,
      metadata: { deleted_worker_id: id }
    });

    return res.json({ ok: true });
  } catch (e) {
    console.error('Error deleting user/worker:', e);
    return res.status(500).json({ error: 'Internal server error' });
  }
});
