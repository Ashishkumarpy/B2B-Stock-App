'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { serverGet, serverPost, serverPut, ServerApiError } from '../../lib/server_api';
import { useRequireAuth } from '../../lib/use_require_auth';

interface Warehouse {
  id: string;
  name: string;
  code?: string | null;
  location?: string | null;
  location_url?: string | null;
  is_active: boolean;
  created_at: string;
}

const EMPTY_FORM = {
  name: '',
  code: '',
  location: '',
  location_url: '',
  is_active: true,
};

export default function WarehousesPage() {
  useRequireAuth();
  const router = useRouter();
  const [warehouses, setWarehouses] = useState<Warehouse[]>([]);
  const [loading, setLoading] = useState(true);
  const [showModal, setShowModal] = useState(false);
  const [editing, setEditing] = useState<Warehouse | null>(null);
  const [form, setForm] = useState(EMPTY_FORM);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  const fetchWarehouses = async () => {
    try {
      const res = await serverGet('/warehouses?include_inactive=true');
      setWarehouses(((res as any).data ?? []) as Warehouse[]);
    } catch (e) {
      if (e instanceof ServerApiError && e.status === 401) {
        router.push('/login');
        return;
      }
      if (e instanceof ServerApiError && e.status === 404) {
        setError('Server not updated yet for warehouses endpoint. Please restart backend.');
        return;
      }
      setError('Failed to load warehouses.');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchWarehouses();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const openCreate = () => {
    setEditing(null);
    setForm(EMPTY_FORM);
    setError('');
    setShowModal(true);
  };

  const openEdit = (warehouse: Warehouse) => {
    setEditing(warehouse);
    setForm({
      name: warehouse.name ?? '',
      code: warehouse.code ?? '',
      location: warehouse.location ?? '',
      location_url: warehouse.location_url ?? '',
      is_active: warehouse.is_active,
    });
    setError('');
    setShowModal(true);
  };

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    setSaving(true);
    setError('');
    try {
      if (!form.name.trim()) {
        setError('Warehouse name is required.');
        setSaving(false);
        return;
      }
      if (editing) {
        await serverPut(`/warehouses/${editing.id}`, {
          name: form.name.trim(),
          code: form.code.trim(),
          location: form.location.trim(),
          location_url: form.location_url.trim(),
          is_active: form.is_active,
        });
      } else {
        await serverPost('/warehouses', {
          name: form.name.trim(),
          code: form.code.trim(),
          location: form.location.trim(),
          location_url: form.location_url.trim(),
        });
      }
      setShowModal(false);
      setEditing(null);
      setForm(EMPTY_FORM);
      await fetchWarehouses();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to save warehouse.');
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold">Warehouses</h1>
          <p className="mt-1 text-sm text-slate-400 dark:text-gray-500">Manage stock locations and map URLs</p>
        </div>
        <button
          onClick={openCreate}
          className="rounded-xl bg-indigo-600 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-indigo-500"
        >
          + Add Warehouse
        </button>
      </div>

      {error && !showModal && (
        <div className="rounded-xl border border-red-500/20 bg-red-500/10 px-4 py-3 text-sm text-red-300">
          {error}
        </div>
      )}

      <div className="card overflow-hidden">
        {loading ? (
          <div className="p-12 text-center text-sm text-slate-400 dark:text-gray-500">Loading warehouses...</div>
        ) : warehouses.length === 0 ? (
          <div className="p-12 text-center text-sm text-slate-400 dark:text-gray-500">No warehouses yet.</div>
        ) : (
          <table className="data-table w-full text-sm">
            <thead>
              <tr>
                <th className="text-left">Name</th>
                <th className="text-left">Code</th>
                <th className="text-left">Location</th>
                <th className="text-left">Location URL</th>
                <th className="text-left">Status</th>
                <th className="text-left">Actions</th>
              </tr>
            </thead>
            <tbody>
              {warehouses.map((warehouse) => (
                <tr key={warehouse.id}>
                  <td className="font-medium text-white">{warehouse.name}</td>
                  <td className="font-mono text-xs text-indigo-300">{warehouse.code || '—'}</td>
                  <td className="max-w-[220px] truncate text-slate-600 dark:text-gray-300">{warehouse.location || '—'}</td>
                  <td className="max-w-[300px] truncate">
                    {warehouse.location_url ? (
                      <a
                        href={warehouse.location_url}
                        target="_blank"
                        rel="noreferrer"
                        className="text-indigo-300 hover:underline"
                      >
                        {warehouse.location_url}
                      </a>
                    ) : (
                      <span className="text-slate-400 dark:text-gray-500">—</span>
                    )}
                  </td>
                  <td>
                    <span className={`badge ${warehouse.is_active ? 'badge-green' : 'badge-red'}`}>
                      {warehouse.is_active ? 'Active' : 'Inactive'}
                    </span>
                  </td>
                  <td>
                    <button
                      onClick={() => openEdit(warehouse)}
                      className="rounded-lg border border-slate-200 dark:border-white/10 px-3 py-1.5 text-xs text-slate-700 dark:text-gray-200 hover:bg-slate-100 dark:hover:bg-white/5"
                    >
                      Edit
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      {showModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 dark:bg-black/70 p-4 backdrop-blur-sm">
          <div className="w-full max-w-xl rounded-2xl border border-slate-200 dark:border-white/10 bg-white dark:bg-[#0f1117] p-8">
            <div className="mb-6 flex items-center justify-between">
              <h2 className="text-xl font-bold">
                {editing ? 'Edit Warehouse' : 'Add Warehouse'}
              </h2>
              <button
                onClick={() => setShowModal(false)}
                className="text-2xl leading-none text-slate-500 dark:text-gray-400 hover:text-white"
              >
                ×
              </button>
            </div>

            <form onSubmit={handleSave} className="space-y-4">
              <div>
                <label className="mb-1.5 block text-xs uppercase tracking-wider text-slate-500 dark:text-gray-400">Warehouse Name *</label>
                <input
                  required
                  value={form.name}
                  onChange={(e) => setForm((prev) => ({ ...prev, name: e.target.value }))}
                  className="w-full rounded-lg border border-slate-200 dark:border-white/10 bg-slate-100 dark:bg-white/5 px-3 py-2.5 text-sm text-white focus:border-indigo-500 focus:outline-none"
                  placeholder="e.g. Hyderabad Central"
                />
              </div>
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="mb-1.5 block text-xs uppercase tracking-wider text-slate-500 dark:text-gray-400">Code</label>
                  <input
                    value={form.code}
                    onChange={(e) => setForm((prev) => ({ ...prev, code: e.target.value }))}
                    className="w-full rounded-lg border border-slate-200 dark:border-white/10 bg-slate-100 dark:bg-white/5 px-3 py-2.5 text-sm text-white focus:border-indigo-500 focus:outline-none"
                    placeholder="e.g. HYD-C"
                  />
                </div>
                <div>
                  <label className="mb-1.5 block text-xs uppercase tracking-wider text-slate-500 dark:text-gray-400">Status</label>
                  <select
                    value={form.is_active ? 'active' : 'inactive'}
                    onChange={(e) =>
                      setForm((prev) => ({ ...prev, is_active: e.target.value === 'active' }))
                    }
                    className="w-full rounded-lg border border-slate-200 dark:border-white/10 bg-slate-100 dark:bg-white/5 px-3 py-2.5 text-sm text-white focus:border-indigo-500 focus:outline-none"
                  >
                    <option value="active" className="bg-white dark:bg-[#0f1117]">Active</option>
                    <option value="inactive" className="bg-white dark:bg-[#0f1117]">Inactive</option>
                  </select>
                </div>
              </div>
              <div>
                <label className="mb-1.5 block text-xs uppercase tracking-wider text-slate-500 dark:text-gray-400">Location</label>
                <input
                  value={form.location}
                  onChange={(e) => setForm((prev) => ({ ...prev, location: e.target.value }))}
                  className="w-full rounded-lg border border-slate-200 dark:border-white/10 bg-slate-100 dark:bg-white/5 px-3 py-2.5 text-sm text-white focus:border-indigo-500 focus:outline-none"
                  placeholder="City, area, floor details..."
                />
              </div>
              <div>
                <label className="mb-1.5 block text-xs uppercase tracking-wider text-slate-500 dark:text-gray-400">Location URL</label>
                <input
                  type="url"
                  value={form.location_url}
                  onChange={(e) => setForm((prev) => ({ ...prev, location_url: e.target.value }))}
                  className="w-full rounded-lg border border-slate-200 dark:border-white/10 bg-slate-100 dark:bg-white/5 px-3 py-2.5 text-sm text-white focus:border-indigo-500 focus:outline-none"
                  placeholder="https://maps.google.com/..."
                />
              </div>

              {error && (
                <p className="rounded-lg bg-red-400/10 px-3 py-2 text-sm text-red-400">{error}</p>
              )}

              <div className="flex gap-3 pt-2">
                <button
                  type="submit"
                  disabled={saving}
                  className="flex-1 rounded-xl bg-indigo-600 py-3 font-semibold text-white transition hover:bg-indigo-500 disabled:opacity-60"
                >
                  {saving ? 'Saving...' : editing ? 'Save Changes' : 'Create Warehouse'}
                </button>
                <button
                  type="button"
                  onClick={() => setShowModal(false)}
                  className="rounded-xl border border-slate-200 dark:border-white/10 px-6 py-3 text-sm text-slate-600 dark:text-gray-300 transition hover:bg-slate-100 dark:hover:bg-white/5"
                >
                  Cancel
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
