import express from 'express';
import { supabaseAdmin } from '../supabase.js';
import { authRequired, requirePermission } from '../auth.js';
import { logActivity } from '../activity_logger.js';

export const usersRouter = express.Router();

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

// Fetch all users with their warehouse assignments
usersRouter.get('/', authRequired, requirePermission('perm_users'), async (_req, res) => {
  const { data, error } = await supabaseAdmin
    .from('users')
    .select('*, user_warehouses(warehouse_id)')
    .order('created_at', { ascending: false });

  if (error) return res.status(500).json({ error: error.message });

  const formatted = (data ?? []).map(user => ({
    id: user.id,
    name: user.name,
    email: user.email,
    role: user.role,
    is_active: user.is_active ?? true,
    created_at: user.created_at,
    permissions: {
      perm_products: user.perm_products ?? false,
      perm_inventory: user.perm_inventory ?? false,
      perm_orders: user.perm_orders ?? false,
      perm_reports: user.perm_reports ?? false,
      perm_users: user.perm_users ?? false,
      perm_settings: user.perm_settings ?? false
    },
    warehouses: user.user_warehouses ? user.user_warehouses.map(uw => uw.warehouse_id) : []
  }));

  return res.json({ data: formatted });
});

// Create a new user in Supabase Auth & Profile
usersRouter.post('/', authRequired, requirePermission('perm_users'), async (req, res) => {
  const { email, password, name, role, is_active, warehouses, permissions } = req.body || {};
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
    // Note: handle_new_user trigger inserts user profile, so we perform an update
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

    // 4. Log the activity
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

// Update a user's details, role, permissions, active status, and warehouse mapping
usersRouter.patch('/:id', authRequired, requirePermission('perm_users'), async (req, res) => {
  const id = req.params.id;
  const { name, role, is_active, warehouses, permissions, email } = req.body || {};

  try {
    // 1. Fetch existing user details for comparison
    const { data: existingUser, error: fetchErr } = await supabaseAdmin
      .from('users')
      .select('*')
      .eq('id', id)
      .maybeSingle();

    if (fetchErr || !existingUser) return res.status(404).json({ error: 'User not found' });

    // 2. Prepare profile updates
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

    // Update email in Auth if modified
    if (email && email !== existingUser.email) {
      const { error: authError } = await supabaseAdmin.auth.admin.updateUserById(id, { email });
      if (authError) return res.status(400).json({ error: authError.message });
      profileUpdate.email = email;
    }

    // 3. Update User Profile
    const { data: updatedProfile, error: updateErr } = await supabaseAdmin
      .from('users')
      .update(profileUpdate)
      .eq('id', id)
      .select('*')
      .single();

    if (updateErr) return res.status(400).json({ error: updateErr.message });

    // 4. Update warehouse mappings
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

    // 5. Track differences and log activity
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
        role: updatedProfile.role,
        is_active: updatedProfile.is_active,
        created_at: updatedProfile.created_at,
        permissions: {
          perm_products: updatedProfile.perm_products,
          perm_inventory: updatedProfile.perm_inventory,
          perm_orders: updatedProfile.perm_orders,
          perm_reports: updatedProfile.perm_reports,
          perm_users: updatedProfile.perm_users,
          perm_settings: updatedProfile.perm_settings
        },
        warehouses: warehouses !== undefined ? warehouses : (existingUser.user_warehouses ? existingUser.user_warehouses.map(uw => uw.warehouse_id) : [])
      }
    });
  } catch (e) {
    console.error('Error updating user:', e);
    return res.status(500).json({ error: 'Internal server error' });
  }
});

// Delete a user (from Auth, which cascades to Profile)
usersRouter.delete('/:id', authRequired, requirePermission('perm_users'), async (req, res) => {
  const id = req.params.id;

  try {
    const { data: user } = await supabaseAdmin.from('users').select('name, email').eq('id', id).maybeSingle();
    const name = user ? `${user.name} (${user.email})` : 'Unknown User';

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
  } catch (e) {
    console.error('Error deleting user:', e);
    return res.status(500).json({ error: 'Internal server error' });
  }
});
