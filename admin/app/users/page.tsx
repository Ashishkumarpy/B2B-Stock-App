'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { serverDelete, serverGet, serverPatch, ServerApiError } from '../../lib/server_api';
import { useRequireAuth } from '../../lib/use_require_auth';

interface User {
  id: string;
  name: string;
  email: string;
  role: string;
  created_at: string;
}

const ROLES = ['admin', 'manager', 'worker', 'customer'] as const;
type Role = (typeof ROLES)[number];

const roleCls: Record<string, string> = {
  admin: 'badge-red',
  manager: 'badge-blue',
  worker: 'badge-gray',
  customer: 'badge-emerald',
};

export default function UsersPage() {
  useRequireAuth();
  const router = useRouter();
  const [users, setUsers] = useState<User[]>([]);
  const [loading, setLoading] = useState(true);

  // Edit Role modal state
  const [editingUser, setEditingUser] = useState<User | null>(null);
  const [selectedRole, setSelectedRole] = useState<Role>('worker');
  const [saving, setSaving] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);

  // Remove confirmation state
  const [removingUser, setRemovingUser] = useState<User | null>(null);
  const [removing, setRemoving] = useState(false);

  useEffect(() => {
    const fetchUsers = async () => {
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
      setLoading(false);
    };

    fetchUsers();
  }, [router]);

  const openEditModal = (user: User) => {
    setEditingUser(user);
    setSelectedRole(user.role as Role);
    setSaveError(null);
  };

  const handleSaveRole = async () => {
    if (!editingUser) return;
    setSaving(true);
    setSaveError(null);

    try {
      await serverPatch(`/users/${editingUser.id}`, { role: selectedRole });
      setUsers((prev) =>
        prev.map((u) => (u.id === editingUser.id ? { ...u, role: selectedRole } : u))
      );
      setEditingUser(null);
    } catch (e: any) {
      setSaveError(String(e?.message || e));
    }
    setSaving(false);
  };

  const handleRemoveUser = async () => {
    if (!removingUser) return;
    setRemoving(true);
    try {
      await serverDelete(`/users/${removingUser.id}`);
      setUsers((prev) => prev.filter((u) => u.id !== removingUser.id));
      setRemovingUser(null);
    } catch {
      // ignore, modal stays open
    }
    setRemoving(false);
  };

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold">Users</h1>
          <p className="mt-1 text-sm text-gray-500">
            {loading ? 'Loading...' : `${users.length} registered users`}
          </p>
        </div>
        <button className="rounded-xl bg-indigo-600 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-indigo-500">
          + Invite User
        </button>
      </div>

      <div className="card overflow-hidden">
        {loading ? (
          <div className="p-10 text-center text-sm text-gray-500">Loading users...</div>
        ) : users.length === 0 ? (
          <div className="p-10 text-center text-sm text-gray-500">No users found.</div>
        ) : (
          <table className="data-table w-full text-sm">
            <thead>
              <tr>
                <th className="text-left">Name</th>
                <th className="text-left">Email</th>
                <th className="text-left">Role</th>
                <th className="text-left">Joined</th>
                <th className="text-left">Actions</th>
              </tr>
            </thead>
            <tbody>
              {users.map((u) => (
                <tr key={u.id}>
                  <td className="font-medium text-white">{u.name}</td>
                  <td className="text-xs text-gray-400">{u.email}</td>
                  <td>
                    <span className={`badge ${roleCls[u.role] || 'badge-gray'}`}>{u.role}</span>
                  </td>
                  <td className="text-xs text-gray-500">
                    {new Date(u.created_at).toLocaleDateString('en-US', {
                      year: 'numeric',
                      month: 'short',
                      day: 'numeric',
                    })}
                  </td>
                  <td>
                    <div className="flex gap-3 text-xs">
                      <button
                        onClick={() => openEditModal(u)}
                        className="font-medium text-indigo-400 transition hover:text-indigo-300"
                      >
                        Edit Role
                      </button>
                      <button
                        onClick={() => setRemovingUser(u)}
                        className="font-medium text-red-400 transition hover:text-red-300"
                      >
                        Remove
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      {/* ── Edit Role Modal ── */}
      {editingUser && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-6 backdrop-blur-sm">
          <div className="w-full max-w-sm rounded-3xl border border-white/10 bg-[#11131a] p-7 shadow-2xl">
            <h2 className="text-lg font-semibold text-white">Edit Role</h2>
            <p className="mt-1 text-sm text-gray-400">
              Changing role for{' '}
              <span className="font-medium text-white">{editingUser.name}</span>
            </p>

            <div className="mt-5">
              <label className="mb-2 block text-xs font-semibold uppercase tracking-wider text-gray-400">
                New Role
              </label>
              <select
                value={selectedRole}
                onChange={(e) => setSelectedRole(e.target.value as Role)}
                className="w-full rounded-2xl border border-white/10 bg-white/5 px-4 py-3 text-sm text-white outline-none transition focus:border-indigo-500"
              >
                {ROLES.map((r) => (
                  <option key={r} value={r} className="bg-[#11131a]">
                    {r.charAt(0).toUpperCase() + r.slice(1)}
                  </option>
                ))}
              </select>
            </div>

            {saveError && (
              <p className="mt-3 rounded-xl border border-red-500/20 bg-red-500/10 px-4 py-2 text-xs text-red-300">
                {saveError}
              </p>
            )}

            <div className="mt-6 flex gap-3">
              <button
                onClick={() => setEditingUser(null)}
                className="flex-1 rounded-xl border border-white/10 py-2.5 text-sm text-gray-300 transition hover:bg-white/5"
              >
                Cancel
              </button>
              <button
                onClick={handleSaveRole}
                disabled={saving}
                className="flex-1 rounded-xl bg-indigo-600 py-2.5 text-sm font-semibold text-white transition hover:bg-indigo-500 disabled:opacity-60"
              >
                {saving ? 'Saving...' : 'Save Role'}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* ── Remove Confirmation Modal ── */}
      {removingUser && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-6 backdrop-blur-sm">
          <div className="w-full max-w-sm rounded-3xl border border-red-500/20 bg-[#11131a] p-7 shadow-2xl">
            <h2 className="text-lg font-semibold text-white">Remove User?</h2>
            <p className="mt-2 text-sm text-gray-400">
              This will remove{' '}
              <span className="font-medium text-white">{removingUser.name}</span> from the
              platform. This action cannot be undone.
            </p>

            <div className="mt-6 flex gap-3">
              <button
                onClick={() => setRemovingUser(null)}
                className="flex-1 rounded-xl border border-white/10 py-2.5 text-sm text-gray-300 transition hover:bg-white/5"
              >
                Cancel
              </button>
              <button
                onClick={handleRemoveUser}
                disabled={removing}
                className="flex-1 rounded-xl bg-red-600 py-2.5 text-sm font-semibold text-white transition hover:bg-red-500 disabled:opacity-60"
              >
                {removing ? 'Removing...' : 'Yes, Remove'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
