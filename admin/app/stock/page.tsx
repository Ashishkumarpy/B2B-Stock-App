'use client';

import { useState, useEffect, useRef, useCallback } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import { serverGet, serverPost, ServerApiError } from '../../lib/server_api';
import { useRequireAuth } from '../../lib/use_require_auth';
import { supabase } from '../../lib/supabase';

type TransactionType = 'stock_in' | 'stock_out';

interface Transaction {
  id: string;
  product_id: string;
  product_name: string;
  product_code: string;
  color_name?: string;
  warehouse_name?: string;
  type: TransactionType;
  quantity: number;
  worker_name: string;
  notes?: string;
  created_at: string;
}

interface Product {
  id: string;
  name: string;
  code: string;
  category?: string;
  quantity: number;
  threshold: number;
  color_stocks?: Array<{ color: string; quantity: number }>;
}

interface Warehouse {
  id: string;
  name: string;
  location?: string | null;
  is_active: boolean;
}

const EMPTY_FORM = {
  product_id: '',
  type: 'stock_in' as TransactionType,
  cartons: '' as string | number,
  pcsPerCarton: '' as string | number,
  quantity: 0,
  color_name: 'Default',
  warehouse_id: '',
  worker_id: '',
  worker_name: '',
  notes: '',
};

export default function StockPage() {
  useRequireAuth();
  const router = useRouter();
  const searchParams = useSearchParams();
  const [transactions, setTransactions] = useState<Transaction[]>([]);
  const [products, setProducts] = useState<Product[]>([]);
  const [warehouses, setWarehouses] = useState<Warehouse[]>([]);
  const [workers, setWorkers] = useState<{ id: string; name: string }[]>([]);
  const [loading, setLoading] = useState(true);
  const [showModal, setShowModal] = useState(false);
  const [form, setForm] = useState(EMPTY_FORM);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [showProductPicker, setShowProductPicker] = useState(false);
  const [pickerSearch, setPickerSearch] = useState('');
  const [pickerCategory, setPickerCategory] = useState<string | null>(null);
  const prefetchedQueryRef = useRef<string | null>(null);

  const [realtimeStatus, setRealtimeStatus] = useState<'connecting' | 'connected' | 'error'>('connecting');

  const fetchTransactions = useCallback(async () => {
    try {
      const res = await serverGet('/transactions');
      setTransactions(((res as any).data ?? []) as Transaction[]);
      setError('');
    } catch (e) {
      if (e instanceof ServerApiError && e.status === 401) {
        router.push('/login');
        return;
      }
      console.error(e);
      setError('Failed to fetch transactions');
    }
    setLoading(false);
  }, [router]);

  const fetchFormData = useCallback(async () => {
    try {
      const [pRes, uRes, wRes] = await Promise.all([
        serverGet('/products'),
        serverGet('/workers'),
        serverGet('/warehouses'),
      ]);
      const pData = ((pRes as any).data ?? []) as Product[];
      const uData = ((uRes as any).data ?? []) as Array<{ id: string; name: string; role: string; is_active?: boolean }>;
      const wData = ((wRes as any).data ?? []) as Warehouse[];
      setProducts(pData);
      setWarehouses(wData.filter((w) => w.is_active));
      setWorkers(uData.filter((u) => u.is_active !== false).map((u) => ({ id: u.id, name: u.name })));
    } catch (e) {
      if (e instanceof ServerApiError && e.status === 401) {
        router.push('/login');
        return;
      }
      if (e instanceof ServerApiError && e.status === 404) {
        setWarehouses([]);
      }
      console.error('Failed to fetch form data:', e);
    }
  }, [router]);

  useEffect(() => {
    fetchTransactions();
    fetchFormData();

    // Set up real-time listener for both transactions and products
    const channel = supabase
      .channel('stock-all-changes')
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'transactions' },
        () => {
          fetchTransactions();
        }
      )
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'products' },
        () => {
          fetchFormData();
        }
      )
      .subscribe((status) => {
        if (status === 'SUBSCRIBED') setRealtimeStatus('connected');
        if (status === 'CHANNEL_ERROR') setRealtimeStatus('error');
      });

    return () => {
      supabase.removeChannel(channel);
    };
  }, [fetchTransactions, fetchFormData]);


  useEffect(() => {
    if (!form.warehouse_id && warehouses.length > 0) {
      setForm((prev) => ({ ...prev, warehouse_id: warehouses[0].id }));
    }
  }, [form.warehouse_id, warehouses]);

  useEffect(() => {
    if (!form.worker_id && workers.length > 0) {
      const first = workers[0];
      setForm((prev) => ({ ...prev, worker_id: first.id, worker_name: first.name }));
    }
  }, [form.worker_id, workers]);

  useEffect(() => {
    if (!form.product_id) return;
    const product = products.find((p) => p.id === form.product_id);
    if (!product) return;
    const firstColor = product.color_stocks?.[0]?.color || 'Default';
    setForm((prev) => ({ 
      ...prev, 
      color_name: prev.color_name || firstColor,
      pcsPerCarton: product.pcs_per_carton || prev.pcsPerCarton || 1
    }));
  }, [form.product_id, products]);

  useEffect(() => {
    const productId = (searchParams.get('productId') ?? '').trim();
    const typeParam = (searchParams.get('type') ?? '').trim();
    const queryKey = `${productId}|${typeParam}`;
    if (!productId) {
      prefetchedQueryRef.current = null;
      return;
    }
    if (prefetchedQueryRef.current === queryKey) return;
    if (!productId || products.length === 0) return;
    const exists = products.some((p) => p.id === productId);
    if (!exists) return;
    const safeType: TransactionType =
      typeParam === 'stock_out' ? 'stock_out' : 'stock_in';
    const defaultWarehouse = warehouses[0]?.id ?? '';
    const nextProduct = products.find((p) => p.id === productId);
    const firstColor = nextProduct?.color_stocks?.[0]?.color || 'Default';
    const timer = window.setTimeout(() => {
      setForm((prev) => ({
        ...prev,
        product_id: productId,
        type: safeType,
        color_name: firstColor,
        warehouse_id: prev.warehouse_id || defaultWarehouse,
      }));
      setShowModal(true);
      prefetchedQueryRef.current = queryKey;
    }, 0);
    return () => window.clearTimeout(timer);
  }, [products, searchParams, warehouses]);

  const selectedProduct = products.find((p) => p.id === form.product_id);
  const availableColors = selectedProduct?.color_stocks ?? [];
  const selectedColorQty = (() => {
    if (!selectedProduct) return 0;
    const normalized = form.color_name.trim().toLowerCase();
    if (!normalized || normalized === 'default') return selectedProduct.quantity;
    const colorRow = selectedProduct.color_stocks?.find(
      (c) => c.color.trim().toLowerCase() === normalized
    );
    return colorRow?.quantity ?? 0;
  })();

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');
    if (!form.product_id) { setError('Please select a product.'); return; }
    if (form.quantity <= 0) { setError('Quantity must be greater than 0.'); return; }
    if (!form.color_name.trim()) { setError('Color is required.'); return; }
    if (warehouses.length > 0 && !form.warehouse_id) { setError('Please select a warehouse.'); return; }
    if (!form.worker_name.trim()) { setError('Worker name is required.'); return; }

    setSaving(true);
    try {
      // Get product
      const product = products.find((p) => p.id === form.product_id);
      if (!product) { setError('Product not found.'); setSaving(false); return; }

      if (form.type === 'stock_out' && form.quantity > product.quantity) {
        setError(`Only ${product.quantity} units available. Cannot dispatch more than available stock.`);
        setSaving(false);
        return;
      }
      if (form.type === 'stock_out' && form.quantity > selectedColorQty) {
        setError(`Only ${selectedColorQty} units available for color "${form.color_name}".`);
        setSaving(false);
        return;
      }

      // Write transaction
      await serverPost('/transactions', {
        product_id: product.id,
        product_name: product.name,
        color_name: form.color_name.trim(),
        warehouse_id: form.warehouse_id || undefined,
        type: form.type,
        quantity: form.quantity,
        cartons: form.cartons ? Number(form.cartons) : null,
        pcs_per_carton: form.pcsPerCarton ? Number(form.pcsPerCarton) : null,
        worker_id: form.worker_id || undefined,
        worker_name: form.worker_name.trim(),
        notes: form.notes.trim() || null,
      });

      setForm({
        ...EMPTY_FORM,
        warehouse_id: warehouses[0]?.id ?? '',
      });
      setShowModal(false);
    } catch (err) {
      setError('Failed to save. Please try again.');
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="space-y-6">
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <div className="flex items-center gap-3 mb-1">
            <h1 className="text-2xl font-bold">Stock Entries</h1>
            <div className={`flex items-center gap-1.5 px-2 py-0.5 rounded-full text-[10px] font-bold border ${realtimeStatus === 'connected'
                ? 'bg-emerald-500/10 text-emerald-400 border-emerald-500/20'
                : realtimeStatus === 'error'
                  ? 'bg-red-500/10 text-red-400 border-red-500/20'
                  : 'bg-amber-500/10 text-amber-400 border-amber-500/20'
              }`}>
              <div className={`w-1.5 h-1.5 rounded-full ${realtimeStatus === 'connected' ? 'bg-emerald-500 animate-pulse' : realtimeStatus === 'error' ? 'bg-red-500' : 'bg-amber-500'
                }`} />
              {realtimeStatus === 'connected' ? 'LIVE' : realtimeStatus === 'error' ? 'OFFLINE' : 'CONNECTING'}
            </div>
          </div>
          <p className="text-gray-500 text-sm">{transactions.length} transactions recorded</p>
        </div>
        <button
          onClick={() => { setForm(EMPTY_FORM); setError(''); setShowModal(true); }}
          className="bg-indigo-600 hover:bg-indigo-500 text-white text-sm font-semibold px-5 py-2.5 rounded-xl transition shadow-lg shadow-indigo-500/20 active:scale-95"
        >
          + Record Stock
        </button>
      </div>

      {/* Table */}
      <div className="card overflow-hidden">
        {loading ? (
          <div className="p-12 text-center text-gray-500 text-sm">Loading transactions…</div>
        ) : transactions.length === 0 ? (
          <div className="p-12 text-center text-gray-500 text-sm">No stock entries yet. Click "+ Record Stock" to log the first transaction.</div>
        ) : (
          <table className="data-table w-full text-sm">
            <thead>
              <tr>
                <th className="text-left">Worker</th>
                <th className="text-left">Type</th>
                <th className="text-left">Code</th>
                <th className="text-left">Color</th>
                <th className="text-left">Warehouse</th>
                <th className="text-right">Qty</th>
                <th className="text-left">Notes</th>
                <th className="text-left">Date / Time</th>
              </tr>
            </thead>
            <tbody>
              {transactions.map((t) => (
                <tr key={t.id}>
                  <td className="text-white font-medium">{t.worker_name}</td>
                  <td>
                    <span className={`badge ${t.type === 'stock_in' ? 'badge-green' : 'badge-red'}`}>
                      {t.type === 'stock_in' ? 'Stock In' : 'Stock Out'}
                    </span>
                  </td>
                  <td className="py-2">
                    <div className="flex flex-col">
                      <button
                        type="button"
                        onClick={() => router.push(`/products/${encodeURIComponent(t.product_id)}`)}
                        className="font-mono text-sm font-bold text-indigo-400 hover:underline text-left"
                      >
                        {t.product_code}
                      </button>
                      <span className="text-[10px] text-gray-500 max-w-[200px] truncate leading-tight mt-0.5">
                        {t.product_name}
                      </span>
                    </div>
                  </td>
                  <td className="text-gray-300">{t.color_name || 'Default'}</td>
                  <td className="text-gray-300 max-w-[180px] truncate">{t.warehouse_name || 'Main Warehouse'}</td>
                  <td className={`text-right font-mono font-semibold ${t.type === 'stock_in' ? 'text-emerald-400' : 'text-red-400'}`}>
                    {t.type === 'stock_in' ? '+' : '-'}{t.quantity}
                  </td>
                  <td className="text-gray-500 text-xs max-w-[140px] truncate">{t.notes || '—'}</td>
                  <td className="text-gray-500 text-xs">{new Date(t.created_at).toLocaleString('en-IN', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' })}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      {/* Record Stock Modal */}
      {showModal && (
        <div className="fixed inset-0 bg-black/70 backdrop-blur-sm z-50 flex items-center justify-center p-4">
          <div className="bg-[#0f1117] border border-white/10 rounded-2xl p-8 w-full max-w-lg">
            <div className="flex items-center justify-between mb-6">
              <h2 className="text-xl font-bold">Record Stock Movement</h2>
              <button onClick={() => setShowModal(false)} className="text-gray-400 hover:text-white text-2xl leading-none">×</button>
            </div>

            <form onSubmit={handleSubmit} className="space-y-5">
              {/* Type Toggle */}
              <div>
                <label className="block text-xs text-gray-400 mb-2 uppercase tracking-wider">Movement Type</label>
                <div className="flex gap-3">
                  {(['stock_in', 'stock_out'] as TransactionType[]).map((t) => (
                    <button
                      key={t}
                      type="button"
                      onClick={() => setForm({ ...form, type: t })}
                      className={`flex-1 py-2.5 rounded-xl text-sm font-semibold border transition ${form.type === t
                          ? t === 'stock_in'
                            ? 'bg-emerald-600/20 border-emerald-500 text-emerald-300'
                            : 'bg-red-600/20 border-red-500 text-red-300'
                          : 'border-white/10 text-gray-500 hover:bg-white/5'
                        }`}
                    >
                      {t === 'stock_in' ? '↑ Stock In' : '↓ Stock Out'}
                    </button>
                  ))}
                </div>
              </div>

              {/* Product */}
              <div>
                <label className="block text-xs text-gray-400 mb-1.5 uppercase tracking-wider">Product *</label>
                <button
                  type="button"
                  onClick={() => setShowProductPicker(true)}
                  className="w-full bg-white/5 border border-white/10 rounded-lg px-3 py-2.5 text-sm text-left text-white focus:outline-none focus:border-indigo-500 flex justify-between items-center"
                >
                  {form.product_id ? (
                    <div className="flex flex-col">
                      <span className="font-mono font-bold text-indigo-500 text-sm">
                        {products.find(p => p.id === form.product_id)?.code}
                      </span>
                      <span className="text-[10px] text-gray-400 leading-tight">
                        {products.find(p => p.id === form.product_id)?.name}
                      </span>
                    </div>
                  ) : (
                    <span className="text-gray-400">Choose product from folders...</span>
                  )}
                  <div className="flex items-center gap-3">
                    {selectedProduct && (
                      <span className="bg-indigo-500/20 text-indigo-300 text-[10px] px-2 py-1 rounded-md font-bold uppercase tracking-wider">
                        Available: {selectedProduct.quantity}
                      </span>
                    )}
                    <span className="text-gray-400 text-xs">▼</span>
                  </div>
                </button>
              </div>

              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-xs text-gray-400 mb-1.5 uppercase tracking-wider">Warehouse</label>
                  <select
                    value={form.warehouse_id}
                    onChange={(e) => setForm({ ...form, warehouse_id: e.target.value })}
                    className="w-full bg-white/5 border border-white/10 rounded-lg px-3 py-2.5 text-sm text-white focus:outline-none focus:border-indigo-500"
                  >
                    {warehouses.length === 0 ? (
                      <option value="" className="bg-[#0f1117]">Main Warehouse (fallback)</option>
                    ) : (
                      warehouses.map((w) => (
                        <option key={w.id} value={w.id} className="bg-[#0f1117]">
                          {w.location ? `${w.name} — ${w.location}` : w.name}
                        </option>
                      ))
                    )}
                  </select>
                </div>
                <div>
                  <label className="block text-xs text-gray-400 mb-1.5 uppercase tracking-wider">Color *</label>
                  <div className="relative">
                    <input
                      required
                      type="text"
                      value={form.color_name}
                      onChange={(e) => setForm({ ...form, color_name: e.target.value })}
                      className="w-full bg-white/5 border border-white/10 rounded-lg px-3 py-2.5 text-sm text-white focus:outline-none focus:border-indigo-500"
                      placeholder="e.g. Black"
                    />
                    {form.product_id && (
                      <span className="absolute right-3 top-1/2 -translate-y-1/2 text-[10px] font-bold text-emerald-400 bg-emerald-400/10 px-1.5 py-0.5 rounded">
                        Stock: {selectedColorQty}
                      </span>
                    )}
                  </div>
                  {availableColors.length > 0 && (
                    <p className="mt-1 text-[11px] text-gray-500">
                      Available: {availableColors.map((c) => `${c.color} (${c.quantity})`).join(', ')}
                    </p>
                  )}
                </div>
              </div>

              {/* Quantity + Worker */}
              <div className="grid gap-4">
                <div className="grid grid-cols-3 gap-4">
                  <div>
                    <label className="block text-xs text-gray-400 mb-1.5 uppercase tracking-wider">Cartons</label>
                    <input
                      type="number" min="0"
                      value={form.cartons}
                      onChange={(e) => {
                        const c = Number(e.target.value);
                        const p = Number(form.pcsPerCarton) || 0;
                        setForm({ ...form, cartons: e.target.value, quantity: c * p || 0 });
                      }}
                      className="w-full bg-white/5 border border-white/10 rounded-lg px-3 py-2.5 text-sm text-white focus:outline-none focus:border-indigo-500"
                      placeholder="e.g. 5"
                    />
                  </div>
                  <div>
                    <label className="block text-xs text-gray-400 mb-1.5 uppercase tracking-wider">Pcs / Carton</label>
                    <input
                      type="number" min="0"
                      value={form.pcsPerCarton}
                      onChange={(e) => {
                        const p = Number(e.target.value);
                        const c = Number(form.cartons) || 0;
                        setForm({ ...form, pcsPerCarton: e.target.value, quantity: c * p || 0 });
                      }}
                      className="w-full bg-white/5 border border-white/10 rounded-lg px-3 py-2.5 text-sm text-white focus:outline-none focus:border-indigo-500"
                      placeholder="e.g. 20"
                    />
                  </div>
                  <div>
                    <label className="block text-xs text-gray-400 mb-1.5 uppercase tracking-wider">Total Quantity *</label>
                    <input
                      type="number" required min="1"
                      value={form.quantity || ''}
                      onChange={(e) => setForm({ ...form, quantity: Number(e.target.value) })}
                      className="w-full bg-white/5 border border-white/10 rounded-lg px-3 py-2.5 text-sm text-white focus:outline-none focus:border-indigo-500"
                      placeholder="e.g. 100"
                    />
                  </div>
                </div>
                <div>
                  <label className="block text-xs text-gray-400 mb-1.5 uppercase tracking-wider">Recorded By *</label>
                  <select
                    required
                    value={form.worker_id}
                    onChange={(e) => {
                      const w = workers.find(w => w.id === e.target.value);
                      setForm({ ...form, worker_id: e.target.value, worker_name: w?.name || '' });
                    }}
                    className="w-full bg-white/5 border border-white/10 rounded-lg px-3 py-2.5 text-sm text-white focus:outline-none focus:border-indigo-500"
                  >
                    <option value="" disabled className="bg-[#0f1117]">Select Worker...</option>
                    {workers.map((w) => (
                      <option key={w.id} value={w.id} className="bg-[#0f1117]">
                        {w.name}
                      </option>
                    ))}
                  </select>
                </div>
              </div>

              {/* Notes */}
              <div>
                <label className="block text-xs text-gray-400 mb-1.5 uppercase tracking-wider">Notes (optional)</label>
                <input
                  type="text"
                  value={form.notes}
                  onChange={(e) => setForm({ ...form, notes: e.target.value })}
                  className="w-full bg-white/5 border border-white/10 rounded-lg px-3 py-2.5 text-sm text-white focus:outline-none focus:border-indigo-500"
                  placeholder="Reason, batch number, etc."
                />
              </div>

              {error && (
                <p className="text-sm text-red-400 bg-red-400/10 rounded-lg px-3 py-2">{error}</p>
              )}

              <div className="flex gap-3 pt-2">
                <button
                  type="submit"
                  disabled={saving}
                  className={`flex-1 font-semibold py-3 rounded-xl transition text-white disabled:opacity-50 ${form.type === 'stock_in' ? 'bg-emerald-600 hover:bg-emerald-500' : 'bg-red-600 hover:bg-red-500'
                    }`}
                >
                  {saving ? 'Saving…' : form.type === 'stock_in' ? '↑ Record Stock In' : '↓ Record Stock Out'}
                </button>
                <button
                  type="button"
                  onClick={() => setShowModal(false)}
                  className="px-6 py-3 border border-white/10 rounded-xl text-sm text-gray-300 hover:bg-white/5 transition"
                >
                  Cancel
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* Product Picker Modal */}
      {showProductPicker && (
        <div className="fixed inset-0 bg-[#0f1117] z-[60] flex flex-col p-4 md:p-8 overflow-hidden">
          <div className="flex items-center gap-4 mb-6">
            <button
              type="button"
              onClick={() => {
                if (pickerCategory) setPickerCategory(null);
                else {
                  setShowProductPicker(false);
                  setPickerSearch('');
                }
              }}
              className="p-2 rounded-lg bg-white/5 hover:bg-white/10 text-white flex items-center justify-center min-w-[40px]"
            >
              ←
            </button>
            <input
              type="text"
              autoFocus
              value={pickerSearch}
              onChange={(e) => setPickerSearch(e.target.value)}
              placeholder="Search products by name or code..."
              className="flex-1 bg-white/5 border border-white/10 rounded-xl px-4 py-3 text-white placeholder-gray-500 focus:outline-none focus:border-indigo-500"
            />
          </div>

          <div className="flex-1 overflow-y-auto">
            {pickerSearch ? (
              <div className="grid gap-3 sm:grid-cols-2 md:grid-cols-3">
                {products
                  .filter((p) => p.name.toLowerCase().includes(pickerSearch.toLowerCase()) || p.code.toLowerCase().includes(pickerSearch.toLowerCase()))
                  .sort((a, b) => a.code.localeCompare(b.code))
                  .map((p) => (
                    <button
                      key={p.id}
                      type="button"
                      onClick={() => {
                        setForm({ ...form, product_id: p.id, color_name: p.color_stocks?.[0]?.color || 'Default' });
                        setShowProductPicker(false);
                        setPickerSearch('');
                        setPickerCategory(null);
                      }}
                      className="text-left bg-white/5 border border-white/10 p-4 rounded-xl hover:border-indigo-500/50 hover:bg-indigo-500/10 transition"
                    >
                      <p className="font-mono font-bold text-indigo-400 text-sm">{p.code}</p>
                      <p className="text-[10px] text-gray-500 truncate mt-0.5">{p.name}</p>
                      <p className="text-xs text-indigo-400 mt-2">{p.quantity} in stock</p>
                    </button>
                  ))}
              </div>
            ) : pickerCategory ? (
              <div className="grid gap-3 sm:grid-cols-2 md:grid-cols-3">
                {products
                  .filter((p) => (p.category || 'Uncategorized') === pickerCategory)
                  .sort((a, b) => a.code.localeCompare(b.code))
                  .map((p) => (
                    <button
                      key={p.id}
                      type="button"
                      onClick={() => {
                        setForm({ ...form, product_id: p.id, color_name: p.color_stocks?.[0]?.color || 'Default' });
                        setShowProductPicker(false);
                        setPickerSearch('');
                        setPickerCategory(null);
                      }}
                      className="text-left bg-white/5 border border-white/10 p-4 rounded-xl hover:border-indigo-500/50 hover:bg-indigo-500/10 transition"
                    >
                      <p className="font-mono font-bold text-indigo-400 text-sm">{p.code}</p>
                      <p className="text-[10px] text-gray-500 truncate mt-0.5">{p.name}</p>
                      <p className="text-[10px] font-bold text-indigo-300 mt-2 uppercase tracking-tight bg-indigo-500/10 px-2 py-0.5 rounded inline-block">
                        Qty: {p.quantity}
                      </p>
                    </button>
                  ))}
              </div>
            ) : (
              <div className="grid gap-4 grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5">
                {Object.entries(
                  products.reduce((acc, p) => {
                    const cat = p.category || 'Uncategorized';
                    if (!acc[cat]) acc[cat] = 0;
                    acc[cat]++;
                    return acc;
                  }, {} as Record<string, number>)
                ).sort((a, b) => a[0].localeCompare(b[0])).map(([name, count]) => (
                  <button
                    key={name}
                    type="button"
                    onClick={() => setPickerCategory(name)}
                    className="aspect-square bg-[#121826] border border-white/10 rounded-2xl flex flex-col items-center justify-center p-4 hover:border-indigo-500/40 hover:bg-indigo-500/5 transition relative overflow-hidden group"
                  >
                    <div className="absolute inset-0 bg-gradient-to-br from-indigo-500/10 to-transparent opacity-0 group-hover:opacity-100 transition" />
                    <span className="text-4xl mb-2 opacity-80">📁</span>
                    <p className="text-sm font-semibold text-white text-center line-clamp-2">{name}</p>
                    <span className="mt-2 text-[10px] uppercase tracking-wider text-gray-500 bg-black/40 px-2 py-0.5 rounded-full">{count} items</span>
                  </button>
                ))}
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
}
