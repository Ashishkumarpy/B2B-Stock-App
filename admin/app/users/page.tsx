'use client';

import { useEffect, useState, useMemo } from 'react';
import { useRouter } from 'next/navigation';
import { serverGet, serverPost, serverPatch, serverDelete, ServerApiError } from '../../lib/server_api';
import { useRequireAuth } from '../../lib/use_require_auth';

interface User {
  id: string;
  name: string;
  email: string;
  role: 'admin' | 'manager' | 'worker' | 'customer';
  is_active: boolean;
  created_at: string;
  permissions: {
    perm_products: boolean;
    perm_inventory: boolean;
    perm_orders: boolean;
    perm_reports: boolean;
    perm_users: boolean;
    perm_settings: boolean;
  };
  warehouses: string[];
}

interface Warehouse {
  id: string;
  name: string;
  code: string;
  is_active: boolean;
}

interface ActivityLog {
  id: string;
  actor_id: string | null;
  actor_name: string;
  action_type: string;
  description: string;
  metadata: any;
  created_at: string;
}

interface LoginRecord {
  id: string;
  user_id: string | null;
  email: string | null;
  ip_address: string | null;
  user_agent: string | null;
  status: string;
  created_at: string;
}

export default function UsersPage() {
  useRequireAuth();
  const router = useRouter();

  // Tab State
  const [activeTab, setActiveTab] = useState<'directory' | 'activities' | 'logins'>('directory');

  // Core Data State
  const [users, setUsers] = useState<User[]>([]);
  const [warehouses, setWarehouses] = useState<Warehouse[]>([]);
  const [activities, setActivities] = useState<ActivityLog[]>([]);
  const [logins, setLogins] = useState<LoginRecord[]>([]);

  // Loading States
  const [loadingUsers, setLoadingUsers] = useState(true);
  const [loadingWarehouses, setLoadingWarehouses] = useState(true);
  const [loadingActivities, setLoadingActivities] = useState(false);
  const [loadingLogins, setLoadingLogins] = useState(false);

  // Search and Filter State
  const [searchQuery, setSearchQuery] = useState('');
  const [roleFilter, setRoleFilter] = useState<string>('all');
  const [statusFilter, setStatusFilter] = useState<string>('all');
  const [warehouseFilter, setWarehouseFilter] = useState<string>('all');

  // Expanded Log Details
  const [expandedLogId, setExpandedLogId] = useState<string | null>(null);

  // User Profile Detail View
  const [selectedUser, setSelectedUser] = useState<User | null>(null);

  // Edit/Create Modal State
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [editingUser, setEditingUser] = useState<User | null>(null); // Null means creating
  const [formState, setFormState] = useState({
    name: '',
    email: '',
    password: '', // Only for create
    role: 'worker' as User['role'],
    is_active: true,
    permissions: {
      perm_products: false,
      perm_inventory: true,
      perm_orders: false,
      perm_reports: false,
      perm_users: false,
      perm_settings: false,
    },
    warehouses: [] as string[]
  });
  const [saving, setSaving] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);

  // Delete Confirmation Modal State
  const [removingUser, setRemovingUser] = useState<User | null>(null);
  const [removing, setRemoving] = useState(false);

  // Fetch Users & Warehouses
  const fetchUsers = async () => {
    setLoadingUsers(true);
    try {
      const res = await serverGet('/users');
      setUsers(((res as any).data ?? []) as User[]);
    } catch (e) {
      if (e instanceof ServerApiError && e.status === 401) {
        router.push('/login');
        return;
      }
      console.error('Failed to fetch users:', e);
    }
    setLoadingUsers(false);
  };

  const fetchWarehouses = async () => {
    setLoadingWarehouses(true);
    try {
      const res = await serverGet('/warehouses');
      setWarehouses(((res as any).data ?? []) as Warehouse[]);
    } catch (e) {
      console.error('Failed to fetch warehouses:', e);
    }
    setLoadingWarehouses(false);
  };

  const fetchActivities = async () => {
    setLoadingActivities(true);
    try {
      const res = await serverGet('/users/activities');
      setActivities(((res as any).data ?? []) as ActivityLog[]);
    } catch (e) {
      console.error('Failed to fetch activities:', e);
    }
    setLoadingActivities(false);
  };

  const fetchLogins = async () => {
    setLoadingLogins(true);
    try {
      const res = await serverGet('/users/logins');
      setLogins(((res as any).data ?? []) as LoginRecord[]);
    } catch (e) {
      console.error('Failed to fetch logins:', e);
    }
    setLoadingLogins(false);
  };

  useEffect(() => {
    fetchUsers();
    fetchWarehouses();
  }, [router]);

  useEffect(() => {
    if (activeTab === 'activities') {
      fetchActivities();
    } else if (activeTab === 'logins') {
      fetchLogins();
    }
  }, [activeTab]);

  // Statistics Calculations
  const stats = useMemo(() => {
    const total = users.length;
    const admins = users.filter(u => u.role === 'admin' && u.is_active).length;
    const managers = users.filter(u => u.role === 'manager' && u.is_active).length;
    const workers = users.filter(u => u.role === 'worker' && u.is_active).length;
    const disabled = users.filter(u => !u.is_active).length;
    return { total, admins, managers, workers, disabled };
  }, [users]);

  // Filtered Users List
  const filteredUsers = useMemo(() => {
    return users.filter(u => {
      const matchesSearch =
        u.name.toLowerCase().includes(searchQuery.toLowerCase()) ||
        u.email.toLowerCase().includes(searchQuery.toLowerCase());
      
      const matchesRole = roleFilter === 'all' || u.role === roleFilter;
      
      const matchesStatus =
        statusFilter === 'all' ||
        (statusFilter === 'active' && u.is_active) ||
        (statusFilter === 'disabled' && !u.is_active);

      const matchesWarehouse =
        warehouseFilter === 'all' || u.warehouses.includes(warehouseFilter);

      return matchesSearch && matchesRole && matchesStatus && matchesWarehouse;
    });
  }, [users, searchQuery, roleFilter, statusFilter, warehouseFilter]);

  // Auto-assign permissions template based on role
  const handleRoleChange = (role: User['role']) => {
    let permissions = { ...formState.permissions };
    if (role === 'admin') {
      permissions = {
        perm_products: true,
        perm_inventory: true,
        perm_orders: true,
        perm_reports: true,
        perm_users: true,
        perm_settings: true,
      };
    } else if (role === 'manager') {
      permissions = {
        perm_products: false,
        perm_inventory: true,
        perm_orders: true,
        perm_reports: true,
        perm_users: true,
        perm_settings: false,
      };
    } else if (role === 'worker') {
      permissions = {
        perm_products: false,
        perm_inventory: true,
        perm_orders: false,
        perm_reports: false,
        perm_users: false,
        perm_settings: false,
      };
    }
    setFormState(prev => ({ ...prev, role, permissions }));
  };

  // Toggle permission checkbox
  const togglePermission = (key: keyof typeof formState.permissions) => {
    setFormState(prev => ({
      ...prev,
      permissions: {
        ...prev.permissions,
        [key]: !prev.permissions[key]
      }
    }));
  };

  // Toggle warehouse assignment
  const toggleWarehouse = (warehouseId: string) => {
    setFormState(prev => {
      const exists = prev.warehouses.includes(warehouseId);
      const list = exists
        ? prev.warehouses.filter(id => id !== warehouseId)
        : [...prev.warehouses, warehouseId];
      return { ...prev, warehouses: list };
    });
  };

  // Open Create Modal
  const openCreateModal = () => {
    setEditingUser(null);
    setFormState({
      name: '',
      email: '',
      password: '',
      role: 'worker',
      is_active: true,
      permissions: {
        perm_products: false,
        perm_inventory: true,
        perm_orders: false,
        perm_reports: false,
        perm_users: false,
        perm_settings: false,
      },
      warehouses: []
    });
    setSaveError(null);
    setIsModalOpen(true);
  };

  // Open Edit Modal
  const openEditModal = (user: User) => {
    setEditingUser(user);
    setFormState({
      name: user.name,
      email: user.email,
      password: '', // Leave blank (not updating password in patch directly)
      role: user.role,
      is_active: user.is_active,
      permissions: { ...user.permissions },
      warehouses: [...user.warehouses]
    });
    setSaveError(null);
    setIsModalOpen(true);
  };

  // Handle Save
  const handleSaveUser = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!formState.name || !formState.email) {
      setSaveError('Name and Email are required.');
      return;
    }
    if (!editingUser && !formState.password) {
      setSaveError('Password is required for new users.');
      return;
    }

    setSaving(true);
    setSaveError(null);

    try {
      if (editingUser) {
        // Update user
        const payload: any = {
          name: formState.name,
          role: formState.role,
          is_active: formState.is_active,
          permissions: formState.permissions,
          warehouses: formState.warehouses,
          email: formState.email
        };
        const res = await serverPatch(`/users/${editingUser.id}`, payload);
        const updatedUser = (res as any).data as User;

        setUsers(prev => prev.map(u => u.id === editingUser.id ? updatedUser : u));
      } else {
        // Create user
        const res = await serverPost('/users', formState);
        const newUser = (res as any).data as User;

        setUsers(prev => [newUser, ...prev]);
      }

      setIsModalOpen(false);
      // Refresh stats and listing
      fetchUsers();
    } catch (err: any) {
      setSaveError(err.message || 'Failed to save user.');
    } finally {
      setSaving(false);
    }
  };

  // Handle Remove
  const handleRemoveUser = async () => {
    if (!removingUser) return;
    setRemoving(true);
    try {
      await serverDelete(`/users/${removingUser.id}`);
      setUsers(prev => prev.filter(u => u.id !== removingUser.id));
      setRemovingUser(null);
      if (selectedUser?.id === removingUser.id) setSelectedUser(null);
    } catch (e: any) {
      alert(e.message || 'Failed to remove user.');
    } finally {
      setRemoving(false);
    }
  };

  // Format date helper
  const formatDate = (dateStr: string) => {
    return new Date(dateStr).toLocaleString('en-US', {
      month: 'short',
      day: 'numeric',
      year: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
    });
  };

  // Map Warehouse Names
  const getWarehouseNames = (ids: string[]) => {
    if (!ids || ids.length === 0) return 'All Warehouses (Global)';
    return ids
      .map(id => warehouses.find(w => w.id === id)?.name || id)
      .join(', ');
  };

  // Render role badge helper
  const renderRoleBadge = (role: User['role']) => {
    const clsMap = {
      admin: 'badge-red',
      manager: 'badge-blue',
      worker: 'badge-green',
      customer: 'badge-gray',
    };
    return <span className={`badge ${clsMap[role] || 'badge-gray'}`}>{role}</span>;
  };

  return (
    <div className="space-y-6">
      {/* ── Title Area ── */}
      <div className="flex flex-col md:flex-row md:items-center md:justify-between gap-4">
        <div>
          <h1 className="text-3xl font-bold tracking-tight">User Management</h1>
          <p className="mt-1.5 text-sm text-slate-500 dark:text-gray-400">
            Control platform roles, fine-grained access permissions, and audit logs.
          </p>
        </div>
        <div className="flex gap-3">
          <button
            onClick={openCreateModal}
            className="flex items-center gap-2 rounded-xl bg-indigo-600 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-indigo-500 shadow-sm shadow-indigo-600/10 cursor-pointer"
          >
            <svg className="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2.5" d="M12 4v16m8-8H4" />
            </svg>
            Add New User
          </button>
        </div>
      </div>

      {/* ── Tabs Navigation ── */}
      <div className="border-b border-slate-200 dark:border-white/5 flex gap-2">
        <button
          onClick={() => setActiveTab('directory')}
          className={`px-4 py-2.5 text-sm font-medium border-b-2 transition-all -mb-px ${
            activeTab === 'directory'
              ? 'border-indigo-600 text-indigo-600 dark:text-indigo-400 font-semibold'
              : 'border-transparent text-slate-500 dark:text-gray-400 hover:text-slate-900 dark:hover:text-white'
          }`}
        >
          Users Directory
        </button>
        <button
          onClick={() => setActiveTab('activities')}
          className={`px-4 py-2.5 text-sm font-medium border-b-2 transition-all -mb-px ${
            activeTab === 'activities'
              ? 'border-indigo-600 text-indigo-600 dark:text-indigo-400 font-semibold'
              : 'border-transparent text-slate-500 dark:text-gray-400 hover:text-slate-900 dark:hover:text-white'
          }`}
        >
          Activity Audit Logs
        </button>
        <button
          onClick={() => setActiveTab('logins')}
          className={`px-4 py-2.5 text-sm font-medium border-b-2 transition-all -mb-px ${
            activeTab === 'logins'
              ? 'border-indigo-600 text-indigo-600 dark:text-indigo-400 font-semibold'
              : 'border-transparent text-slate-500 dark:text-gray-400 hover:text-slate-900 dark:hover:text-white'
          }`}
        >
          Login Audit History
        </button>
      </div>

      {/* ── Tab Content: Users Directory ── */}
      {activeTab === 'directory' && (
        <div className="space-y-6">
          {/* Statistics Grid */}
          <div className="grid grid-cols-2 md:grid-cols-5 gap-4">
            <div className="card stat-indigo p-4 flex flex-col justify-between">
              <span className="text-xs font-semibold text-slate-500 dark:text-gray-400 uppercase tracking-wider">Total Accounts</span>
              <span className="text-2xl font-bold mt-2">{loadingUsers ? '...' : stats.total}</span>
            </div>
            <div className="card stat-sky p-4 flex flex-col justify-between">
              <span className="text-xs font-semibold text-slate-500 dark:text-gray-400 uppercase tracking-wider">Active Admins</span>
              <span className="text-2xl font-bold text-indigo-600 dark:text-indigo-400 mt-2">{loadingUsers ? '...' : stats.admins}</span>
            </div>
            <div className="card stat-emerald p-4 flex flex-col justify-between">
              <span className="text-xs font-semibold text-slate-500 dark:text-gray-400 uppercase tracking-wider">Active Managers</span>
              <span className="text-2xl font-bold text-emerald-600 dark:text-emerald-400 mt-2">{loadingUsers ? '...' : stats.managers}</span>
            </div>
            <div className="card stat-violet p-4 flex flex-col justify-between">
              <span className="text-xs font-semibold text-slate-500 dark:text-gray-400 uppercase tracking-wider">Active Workers</span>
              <span className="text-2xl font-bold text-purple-600 dark:text-purple-400 mt-2">{loadingUsers ? '...' : stats.workers}</span>
            </div>
            <div className="card stat-gray p-4 flex flex-col justify-between">
              <span className="text-xs font-semibold text-slate-500 dark:text-gray-400 uppercase tracking-wider">Disabled Users</span>
              <span className="text-2xl font-bold text-slate-400 mt-2">{loadingUsers ? '...' : stats.disabled}</span>
            </div>
          </div>

          {/* Search and Filters */}
          <div className="card p-4 flex flex-col md:flex-row gap-4 items-center justify-between">
            <div className="relative w-full md:w-80">
              <span className="absolute inset-y-0 left-0 flex items-center pl-3 text-slate-400 dark:text-gray-500">
                <svg className="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
                </svg>
              </span>
              <input
                type="text"
                placeholder="Search users by name or email..."
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                className="w-full rounded-xl border border-slate-200 dark:border-white/10 bg-slate-100 dark:bg-white/5 pl-9 pr-4 py-2.5 text-sm"
              />
            </div>

            <div className="flex flex-wrap items-center gap-3 w-full md:w-auto">
              {/* Role Filter */}
              <div className="flex flex-col gap-1 w-full sm:w-auto">
                <select
                  value={roleFilter}
                  onChange={(e) => setRoleFilter(e.target.value)}
                  className="rounded-xl border border-slate-200 dark:border-white/10 bg-slate-100 dark:bg-white/5 px-3 py-2.5 text-sm"
                >
                  <option value="all">All Roles</option>
                  <option value="admin">Admin</option>
                  <option value="manager">Manager</option>
                  <option value="worker">Worker</option>
                  <option value="customer">Customer</option>
                </select>
              </div>

              {/* Status Filter */}
              <div className="flex flex-col gap-1 w-full sm:w-auto">
                <select
                  value={statusFilter}
                  onChange={(e) => setStatusFilter(e.target.value)}
                  className="rounded-xl border border-slate-200 dark:border-white/10 bg-slate-100 dark:bg-white/5 px-3 py-2.5 text-sm"
                >
                  <option value="all">All Statuses</option>
                  <option value="active">Active Only</option>
                  <option value="disabled">Disabled Only</option>
                </select>
              </div>

              {/* Warehouse Filter */}
              <div className="flex flex-col gap-1 w-full sm:w-auto">
                <select
                  value={warehouseFilter}
                  onChange={(e) => setWarehouseFilter(e.target.value)}
                  className="rounded-xl border border-slate-200 dark:border-white/10 bg-slate-100 dark:bg-white/5 px-3 py-2.5 text-sm"
                >
                  <option value="all">All Warehouses</option>
                  {warehouses.map(w => (
                    <option key={w.id} value={w.id}>{w.name}</option>
                  ))}
                </select>
              </div>
            </div>
          </div>

          {/* Users Directory Table */}
          <div className="card overflow-hidden">
            {loadingUsers ? (
              <div className="p-16 text-center text-sm text-slate-500 dark:text-gray-400">
                <div className="inline-block animate-spin rounded-full h-6 w-6 border-b-2 border-indigo-600 dark:border-indigo-400 mb-3" />
                <p>Retrieving directory data...</p>
              </div>
            ) : filteredUsers.length === 0 ? (
              <div className="p-16 text-center text-sm text-slate-500 dark:text-gray-400">
                <svg className="h-10 w-10 mx-auto text-slate-300 dark:text-gray-700 mb-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="1.5" d="M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197M13 7a4 4 0 11-8 0 4 4 0 018 0z" />
                </svg>
                <p className="font-semibold text-slate-700 dark:text-gray-200">No users found</p>
                <p className="mt-1 text-xs">Try adjusting your filters or search keywords.</p>
              </div>
            ) : (
              <table className="data-table w-full text-sm">
                <thead>
                  <tr>
                    <th className="text-left">User Name</th>
                    <th className="text-left">Email Address</th>
                    <th className="text-left">Role</th>
                    <th className="text-left">Assigned Warehouses</th>
                    <th className="text-left">Status</th>
                    <th className="text-left">Joined Date</th>
                    <th className="text-left">Actions</th>
                  </tr>
                </thead>
                <tbody>
                  {filteredUsers.map((u) => (
                    <tr key={u.id}>
                      <td className="font-semibold text-slate-900 dark:text-white">
                        <button
                          onClick={() => setSelectedUser(u)}
                          className="hover:underline text-left cursor-pointer"
                        >
                          {u.name}
                        </button>
                      </td>
                      <td className="text-xs text-slate-600 dark:text-gray-400 font-mono">{u.email}</td>
                      <td>{renderRoleBadge(u.role)}</td>
                      <td className="text-xs text-slate-600 dark:text-gray-400 max-w-[200px] truncate">
                        {getWarehouseNames(u.warehouses)}
                      </td>
                      <td>
                        {u.is_active ? (
                          <span className="badge badge-green">Active</span>
                        ) : (
                          <span className="badge badge-red">Disabled</span>
                        )}
                      </td>
                      <td className="text-xs text-slate-500 dark:text-gray-500">
                        {new Date(u.created_at).toLocaleDateString(undefined, {
                          month: 'short',
                          day: 'numeric',
                          year: 'numeric'
                        })}
                      </td>
                      <td>
                        <div className="flex gap-3 text-xs">
                          <button
                            onClick={() => openEditModal(u)}
                            className="font-semibold text-indigo-600 dark:text-indigo-400 transition hover:underline cursor-pointer"
                          >
                            Edit
                          </button>
                          <button
                            onClick={() => setRemovingUser(u)}
                            className="font-semibold text-red-600 dark:text-red-400 transition hover:underline cursor-pointer"
                          >
                            Delete
                          </button>
                        </div>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </div>
        </div>
      )}

      {/* ── Tab Content: Activity Logs ── */}
      {activeTab === 'activities' && (
        <div className="space-y-6">
          <div className="card p-4">
            <h2 className="text-lg font-semibold text-slate-950 dark:text-white">System Activity Audit Trail</h2>
            <p className="text-xs text-slate-500 dark:text-gray-400 mt-1">
              Tracks stock transactions, product modifications, dispatches, and credential edits.
            </p>
          </div>

          <div className="card overflow-hidden">
            {loadingActivities ? (
              <div className="p-16 text-center text-sm text-slate-500 dark:text-gray-400">
                <div className="inline-block animate-spin rounded-full h-6 w-6 border-b-2 border-indigo-600 dark:border-indigo-400 mb-3" />
                <p>Fetching activity logs...</p>
              </div>
            ) : activities.length === 0 ? (
              <div className="p-16 text-center text-sm text-slate-500 dark:text-gray-400">
                <svg className="h-10 w-10 mx-auto text-slate-300 dark:text-gray-700 mb-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="1.5" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
                </svg>
                <p className="font-semibold text-slate-700 dark:text-gray-200">No activity logs recorded</p>
              </div>
            ) : (
              <table className="data-table w-full text-sm">
                <thead>
                  <tr>
                    <th className="w-12">Action</th>
                    <th className="text-left">Description</th>
                    <th className="text-left w-48">Actor</th>
                    <th className="text-left w-52">Date & Time</th>
                    <th className="w-24">Metadata</th>
                  </tr>
                </thead>
                <tbody>
                  {activities.map((log) => {
                    const isExpanded = expandedLogId === log.id;
                    let actionIcon = '📋';
                    if (log.action_type.includes('login')) actionIcon = '🔑';
                    else if (log.action_type.includes('product')) actionIcon = '📦';
                    else if (log.action_type.includes('order')) actionIcon = '🛒';
                    else if (log.action_type.includes('stock') || log.action_type.includes('transaction')) actionIcon = '📥';
                    else if (log.action_type.includes('user')) actionIcon = '👥';

                    return (
                      <tr key={log.id} className="align-top">
                        <td className="text-center text-lg py-3">{actionIcon}</td>
                        <td className="py-3">
                          <p className="text-slate-900 dark:text-slate-200">{log.description}</p>
                          <span className="text-[10px] uppercase font-bold tracking-wider text-slate-400 dark:text-gray-500">
                            {log.action_type}
                          </span>
                        </td>
                        <td className="py-3 font-medium text-slate-800 dark:text-gray-300">{log.actor_name}</td>
                        <td className="py-3 text-xs text-slate-500 dark:text-gray-500 font-mono">{formatDate(log.created_at)}</td>
                        <td className="py-3 text-center">
                          <button
                            onClick={() => setExpandedLogId(isExpanded ? null : log.id)}
                            className="text-xs font-semibold text-indigo-600 dark:text-indigo-400 transition hover:underline cursor-pointer"
                          >
                            {isExpanded ? 'Hide' : 'Inspect'}
                          </button>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            )}
          </div>

          {/* Expanded Metadata Overlay Panel */}
          {expandedLogId && (
            <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-6 backdrop-blur-sm">
              <div className="w-full max-w-lg rounded-3xl border border-white/10 bg-[#11131a] p-7 shadow-2xl">
                <div className="flex items-center justify-between border-b border-white/10 pb-4">
                  <h3 className="text-base font-semibold text-white">Metadata Inspector</h3>
                  <button
                    onClick={() => setExpandedLogId(null)}
                    className="text-gray-400 hover:text-white text-lg font-bold"
                  >
                    ×
                  </button>
                </div>
                <div className="mt-4">
                  <pre className="p-4 bg-black/50 border border-white/5 rounded-2xl text-xs text-indigo-300 font-mono max-h-[300px] overflow-auto">
                    {JSON.stringify(activities.find(a => a.id === expandedLogId)?.metadata, null, 2)}
                  </pre>
                </div>
                <div className="mt-6 flex justify-end">
                  <button
                    onClick={() => setExpandedLogId(null)}
                    className="rounded-xl border border-white/10 px-5 py-2 text-sm text-gray-300 hover:bg-white/5"
                  >
                    Close
                  </button>
                </div>
              </div>
            </div>
          )}
        </div>
      )}

      {/* ── Tab Content: Login Audit History ── */}
      {activeTab === 'logins' && (
        <div className="space-y-6">
          <div className="card p-4">
            <h2 className="text-lg font-semibold text-slate-950 dark:text-white">Credential Login Audit Trails</h2>
            <p className="text-xs text-slate-500 dark:text-gray-400 mt-1">
              Maintains history of all successful logins and security failures.
            </p>
          </div>

          <div className="card overflow-hidden">
            {loadingLogins ? (
              <div className="p-16 text-center text-sm text-slate-500 dark:text-gray-400">
                <div className="inline-block animate-spin rounded-full h-6 w-6 border-b-2 border-indigo-600 dark:border-indigo-400 mb-3" />
                <p>Loading login logs...</p>
              </div>
            ) : logins.length === 0 ? (
              <div className="p-16 text-center text-sm text-slate-500 dark:text-gray-400">
                <svg className="h-10 w-10 mx-auto text-slate-300 dark:text-gray-700 mb-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="1.5" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
                </svg>
                <p className="font-semibold text-slate-700 dark:text-gray-200">No login attempts recorded</p>
              </div>
            ) : (
              <table className="data-table w-full text-sm">
                <thead>
                  <tr>
                    <th className="text-left">Target ID / Phone</th>
                    <th className="text-left">IP Address</th>
                    <th className="text-left">User Agent</th>
                    <th className="text-left w-36">Status</th>
                    <th className="text-left w-52">Date & Time</th>
                  </tr>
                </thead>
                <tbody>
                  {logins.map((record) => (
                    <tr key={record.id}>
                      <td className="font-semibold text-slate-900 dark:text-white font-mono text-xs">{record.email || 'OTP Worker'}</td>
                      <td className="text-xs text-slate-600 dark:text-gray-400 font-mono">{record.ip_address || 'Unknown'}</td>
                      <td className="text-xs text-slate-500 dark:text-gray-500 max-w-[300px] truncate" title={record.user_agent || ''}>
                        {record.user_agent || 'Unknown'}
                      </td>
                      <td>
                        {record.status === 'success' ? (
                          <span className="badge badge-green">Success</span>
                        ) : (
                          <span className="badge badge-red">Failed</span>
                        )}
                      </td>
                      <td className="text-xs text-slate-500 dark:text-gray-500 font-mono">{formatDate(record.created_at)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </div>
        </div>
      )}

      {/* ── User Profile Detail Sidebar / Modal ── */}
      {selectedUser && (
        <div className="fixed inset-0 z-50 flex items-center justify-end bg-black/50 backdrop-blur-sm">
          <div className="w-full max-w-xl h-full bg-[#11131a] border-l border-white/10 p-8 shadow-2xl overflow-y-auto flex flex-col justify-between">
            <div className="space-y-6">
              <div className="flex items-center justify-between border-b border-white/10 pb-4">
                <div>
                  <h2 className="text-xl font-bold text-white">{selectedUser.name}</h2>
                  <p className="text-xs text-slate-400 dark:text-gray-500 mt-1">ID: {selectedUser.id}</p>
                </div>
                <button
                  onClick={() => setSelectedUser(null)}
                  className="rounded-xl border border-white/10 bg-white/5 p-2 text-gray-300 hover:bg-white/10 text-sm font-semibold cursor-pointer"
                >
                  Close
                </button>
              </div>

              {/* Basic Fields */}
              <div className="grid grid-cols-2 gap-4 text-sm bg-white/5 border border-white/5 rounded-2xl p-4">
                <div>
                  <span className="text-xs text-slate-400 dark:text-gray-500 block uppercase font-bold">Email Address</span>
                  <span className="text-white font-medium">{selectedUser.email}</span>
                </div>
                <div>
                  <span className="text-xs text-slate-400 dark:text-gray-500 block uppercase font-bold">Access Role</span>
                  <span className="mt-1 block">{renderRoleBadge(selectedUser.role)}</span>
                </div>
                <div className="mt-2">
                  <span className="text-xs text-slate-400 dark:text-gray-500 block uppercase font-bold">Account Status</span>
                  <span className={`badge inline-block mt-1 ${selectedUser.is_active ? 'badge-green' : 'badge-red'}`}>
                    {selectedUser.is_active ? 'Active' : 'Disabled'}
                  </span>
                </div>
                <div className="mt-2">
                  <span className="text-xs text-slate-400 dark:text-gray-500 block uppercase font-bold">Creation Date</span>
                  <span className="text-slate-300 font-mono text-xs">{formatDate(selectedUser.created_at)}</span>
                </div>
              </div>

              {/* Warehouses Block */}
              <div className="space-y-2">
                <h3 className="text-xs font-bold uppercase tracking-wider text-slate-400 dark:text-gray-400">Assigned Warehouses</h3>
                <div className="bg-white/5 border border-white/5 rounded-2xl p-4 text-sm text-slate-300">
                  {selectedUser.warehouses.length === 0 ? (
                    <p className="text-slate-500 italic">No warehouses assigned (Global access / Storefront Customer)</p>
                  ) : (
                    <div className="flex flex-wrap gap-2">
                      {selectedUser.warehouses.map(wid => {
                        const name = warehouses.find(w => w.id === wid)?.name || wid;
                        return (
                          <span key={wid} className="rounded-lg bg-indigo-500/10 border border-indigo-500/20 text-indigo-400 px-2.5 py-1 text-xs">
                            🏢 {name}
                          </span>
                        );
                      })}
                    </div>
                  )}
                </div>
              </div>

              {/* Permissions Blocks */}
              <div className="space-y-2">
                <h3 className="text-xs font-bold uppercase tracking-wider text-slate-400 dark:text-gray-400">Effective Permissions</h3>
                <div className="bg-white/5 border border-white/5 rounded-2xl p-4 grid grid-cols-2 gap-3 text-xs">
                  {Object.entries(selectedUser.permissions).map(([key, val]) => {
                    const cleanName = key.replace('perm_', '').replace('_', ' ');
                    return (
                      <div key={key} className="flex items-center justify-between border-b border-white/5 pb-2 last:border-b-0">
                        <span className="text-slate-300 capitalize font-medium">{cleanName}</span>
                        {val || selectedUser.role === 'admin' ? (
                          <span className="text-emerald-400 font-semibold">✔ Permitted</span>
                        ) : (
                          <span className="text-red-500">❌ Denied</span>
                        )}
                      </div>
                    );
                  })}
                </div>
              </div>
            </div>

            <div className="border-t border-white/10 pt-4 flex gap-3">
              <button
                onClick={() => {
                  setSelectedUser(null);
                  openEditModal(selectedUser);
                }}
                className="flex-1 rounded-xl bg-indigo-600 py-3 text-sm font-semibold text-white hover:bg-indigo-500 text-center cursor-pointer"
              >
                Edit Profile
              </button>
              <button
                onClick={() => {
                  setRemovingUser(selectedUser);
                }}
                className="flex-1 rounded-xl bg-red-600/20 border border-red-500/20 py-3 text-sm font-semibold text-red-400 hover:bg-red-600/30 text-center cursor-pointer"
              >
                Delete Account
              </button>
            </div>
          </div>
        </div>
      )}

      {/* ── Add / Edit User Drawer / Modal ── */}
      {isModalOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-6 backdrop-blur-sm">
          <div className="w-full max-w-2xl rounded-3xl border border-white/10 bg-[#11131a] p-7 shadow-2xl max-h-[90vh] overflow-y-auto">
            <div className="flex items-center justify-between border-b border-white/10 pb-4 mb-5">
              <h2 className="text-xl font-semibold text-white">
                {editingUser ? 'Edit User Credentials & Access' : 'Create Platform User Account'}
              </h2>
              <button
                onClick={() => setIsModalOpen(false)}
                className="text-gray-400 hover:text-white text-xl font-bold cursor-pointer"
              >
                ×
              </button>
            </div>

            <form onSubmit={handleSaveUser} className="space-y-6">
              {/* Form columns grid */}
              <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                {/* Column Left: Credentials */}
                <div className="space-y-4">
                  <h3 className="text-xs font-bold uppercase tracking-wider text-slate-400 dark:text-gray-400 border-b border-white/5 pb-2">
                    Account Basics
                  </h3>

                  <div>
                    <label className="mb-1.5 block text-xs font-semibold text-slate-300 uppercase tracking-wider">Full Name</label>
                    <input
                      type="text"
                      placeholder="e.g. John Doe"
                      value={formState.name}
                      onChange={(e) => setFormState(prev => ({ ...prev, name: e.target.value }))}
                      className="w-full rounded-2xl border border-white/10 bg-white/5 px-4 py-3 text-sm text-white"
                      required
                    />
                  </div>

                  <div>
                    <label className="mb-1.5 block text-xs font-semibold text-slate-300 uppercase tracking-wider">Email Address</label>
                    <input
                      type="email"
                      placeholder="e.g. user@zentory.com"
                      value={formState.email}
                      onChange={(e) => setFormState(prev => ({ ...prev, email: e.target.value }))}
                      className="w-full rounded-2xl border border-white/10 bg-white/5 px-4 py-3 text-sm text-white"
                      required
                    />
                  </div>

                  {!editingUser && (
                    <div>
                      <label className="mb-1.5 block text-xs font-semibold text-slate-300 uppercase tracking-wider">Password</label>
                      <input
                        type="password"
                        placeholder="Secure password (min 6 chars)"
                        value={formState.password}
                        onChange={(e) => setFormState(prev => ({ ...prev, password: e.target.value }))}
                        className="w-full rounded-2xl border border-white/10 bg-white/5 px-4 py-3 text-sm text-white"
                        minLength={6}
                        required
                      />
                    </div>
                  )}

                  <div>
                    <label className="mb-1.5 block text-xs font-semibold text-slate-300 uppercase tracking-wider">Primary System Role</label>
                    <select
                      value={formState.role}
                      onChange={(e) => handleRoleChange(e.target.value as User['role'])}
                      className="w-full rounded-2xl border border-white/10 bg-[#11131a] px-4 py-3 text-sm text-white"
                    >
                      <option value="worker">Worker</option>
                      <option value="manager">Manager</option>
                      <option value="admin">Administrator</option>
                      <option value="customer">Customer</option>
                    </select>
                  </div>

                  <div className="flex items-center gap-3 pt-3">
                    <input
                      type="checkbox"
                      id="form-is-active"
                      checked={formState.is_active}
                      onChange={(e) => setFormState(prev => ({ ...prev, is_active: e.target.checked }))}
                      className="h-4.5 w-4.5 rounded border-white/10 bg-white/5"
                    />
                    <label htmlFor="form-is-active" className="text-sm text-white font-medium">
                      Account status is Active (allows login)
                    </label>
                  </div>
                </div>

                {/* Column Right: Warehouses & Permissions */}
                <div className="space-y-6">
                  {/* Warehouse Assignment */}
                  <div className="space-y-2">
                    <h3 className="text-xs font-bold uppercase tracking-wider text-slate-400 dark:text-gray-400 border-b border-white/5 pb-2">
                      Warehouse Assignments
                    </h3>
                    <div className="grid grid-cols-1 gap-2 max-h-[140px] overflow-y-auto bg-white/5 border border-white/5 rounded-2xl p-3">
                      {warehouses.length === 0 ? (
                        <p className="text-xs text-slate-500 italic">No warehouses available</p>
                      ) : (
                        warehouses.map(w => (
                          <div key={w.id} className="flex items-center gap-2">
                            <input
                              type="checkbox"
                              id={`w-${w.id}`}
                              checked={formState.warehouses.includes(w.id)}
                              onChange={() => toggleWarehouse(w.id)}
                              className="h-4 w-4 rounded border-white/10"
                            />
                            <label htmlFor={`w-${w.id}`} className="text-xs text-slate-300 truncate">
                              {w.name}
                            </label>
                          </div>
                        ))
                      )}
                    </div>
                  </div>

                  {/* Individual Permissions */}
                  <div className="space-y-2">
                    <h3 className="text-xs font-bold uppercase tracking-wider text-slate-400 dark:text-gray-400 border-b border-white/5 pb-2">
                      Access Permissions
                    </h3>
                    <p className="text-[10px] text-indigo-400 italic">
                      Changing roles resets permissions to system defaults. Toggle boxes to customize.
                    </p>
                    <div className="space-y-3 bg-white/5 border border-white/5 rounded-2xl p-4 max-h-[220px] overflow-y-auto">
                      {Object.keys(formState.permissions).map((k) => {
                        const key = k as keyof typeof formState.permissions;
                        const labelText = key.replace('perm_', '').replace('_', ' ');
                        return (
                          <div key={key} className="flex items-start gap-2.5">
                            <input
                              type="checkbox"
                              id={`perm-${key}`}
                              checked={formState.permissions[key] || formState.role === 'admin'}
                              disabled={formState.role === 'admin'} // Admin role enforces true
                              onChange={() => togglePermission(key)}
                              className="h-4.5 w-4.5 rounded border-white/10 mt-0.5"
                            />
                            <div className="text-left">
                              <label htmlFor={`perm-${key}`} className="text-xs text-white capitalize font-semibold block">
                                {labelText}
                              </label>
                              <span className="text-[10px] text-slate-400 dark:text-gray-500">
                                {key === 'perm_products' && 'Create, edit prices, delete product catalog.'}
                                {key === 'perm_inventory' && 'Stock In, Stock Out, Barcode scan, view logs.'}
                                {key === 'perm_orders' && 'Process orders, dispatch items, update status.'}
                                {key === 'perm_reports' && 'Export stock list, view analytics dashboards.'}
                                {key === 'perm_users' && 'Manage other worker accounts and warehouses.'}
                                {key === 'perm_settings' && 'Configure active warehouses and settings.'}
                              </span>
                            </div>
                          </div>
                        );
                      })}
                    </div>
                  </div>
                </div>
              </div>

              {saveError && (
                <p className="rounded-xl border border-red-500/20 bg-red-500/10 px-4 py-2.5 text-xs text-red-300 text-left">
                  {saveError}
                </p>
              )}

              <div className="border-t border-white/10 pt-5 flex gap-3 justify-end">
                <button
                  type="button"
                  onClick={() => setIsModalOpen(false)}
                  className="rounded-xl border border-white/10 px-5 py-2.5 text-sm text-gray-300 hover:bg-white/5 cursor-pointer"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={saving}
                  className="rounded-xl bg-indigo-600 px-6 py-2.5 text-sm font-semibold text-white hover:bg-indigo-500 disabled:opacity-60 shadow-sm shadow-indigo-600/10 cursor-pointer"
                >
                  {saving ? 'Saving Details...' : editingUser ? 'Update User' : 'Create User'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* ── Remove User Confirmation Dialog ── */}
      {removingUser && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-6 backdrop-blur-sm">
          <div className="w-full max-w-sm rounded-3xl border border-red-500/20 bg-[#11131a] p-7 shadow-2xl text-left">
            <h2 className="text-lg font-semibold text-white">Permanently Remove Account?</h2>
            <p className="mt-2 text-sm text-gray-400">
              Are you sure you want to remove <span className="font-semibold text-white">{removingUser.name}</span>?
              This will completely delete their credentials and revoke all access. This action is permanent and cannot be undone.
            </p>

            <div className="mt-6 flex gap-3">
              <button
                onClick={() => setRemovingUser(null)}
                className="flex-1 rounded-xl border border-white/10 py-2.5 text-sm text-gray-300 transition hover:bg-white/5 cursor-pointer"
              >
                Cancel
              </button>
              <button
                onClick={handleRemoveUser}
                disabled={removing}
                className="flex-1 rounded-xl bg-red-600 py-2.5 text-sm font-semibold text-white transition hover:bg-red-500 disabled:opacity-60 cursor-pointer"
              >
                {removing ? 'Deleting...' : 'Yes, Delete'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
