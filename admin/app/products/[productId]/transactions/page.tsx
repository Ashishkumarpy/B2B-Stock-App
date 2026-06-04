'use client';

import Link from 'next/link';
import { useCallback, useEffect, useMemo, useState } from 'react';
import { useParams, useRouter } from 'next/navigation';
import { serverGet, ServerApiError } from '../../../../lib/server_api';
import { useRequireAuth } from '../../../../lib/use_require_auth';
import { Product } from '../../../../components/ProductFormModal';

type TransactionType = 'stock_in' | 'stock_out';

interface Transaction {
  id: string;
  product_id: string;
  product_name: string;
  product_code?: string;
  type: TransactionType;
  quantity: number;
  cartons?: number | null;
  pcs_per_carton?: number | null;
  color_name?: string | null;
  warehouse_name?: string | null;
  worker_name?: string | null;
  notes?: string | null;
  created_at: string;
}

function safeDate(value?: string | null): Date | null {
  if (!value) return null;
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function formatDateTime(value?: string | null) {
  const date = safeDate(value);
  if (!date) return '-';
  return new Intl.DateTimeFormat('en-IN', {
    day: '2-digit',
    month: 'short',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  }).format(date);
}

function parseCartonFromNotes(notes?: string | null): { cartons: number; pcsPerCarton: number } | null {
  if (!notes) return null;
  const regex = /(\d+)\s*(?:ctn|carton|cartons)\s*(?:[x*]|\(|pcs\/ctn|pcs)?\s*(\d+)/i;
  const match = notes.match(regex);
  if (!match) return null;
  const cartons = parseInt(match[1], 10);
  const pcsPerCarton = parseInt(match[2], 10);
  if (Number.isNaN(cartons) || Number.isNaN(pcsPerCarton) || pcsPerCarton <= 0) return null;
  return { cartons, pcsPerCarton };
}

function cartonLabel(txn: Transaction) {
  if (txn.cartons !== undefined && txn.cartons !== null && txn.cartons > 0) {
    return `${txn.cartons} ctn (${txn.quantity} pcs)`;
  }
  const parsed = parseCartonFromNotes(txn.notes);
  if (parsed) return `${parsed.cartons} ctn (${txn.quantity} pcs)`;
  return `${txn.quantity} pcs`;
}

function cleanNotes(notes?: string | null) {
  if (!notes) return '';
  return notes
    .replace(/^Customer:\s*[^|]+(\|)?/i, '')
    .replace(/^\|\s*/, '')
    .trim();
}

function customerName(notes?: string | null) {
  if (!notes) return '';
  return notes.match(/Customer:\s*([^|]+)/i)?.[1]?.trim() ?? '';
}

export default function AdminProductTransactionsPage() {
  useRequireAuth();
  const router = useRouter();
  const params = useParams<{ productId: string }>();
  const productId = String(params?.productId ?? '');

  const [products, setProducts] = useState<Product[]>([]);
  const [transactions, setTransactions] = useState<Transaction[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const [productsRes, txRes] = await Promise.all([
        serverGet('/products'),
        serverGet(`/transactions?product_id=${encodeURIComponent(productId)}`),
      ]);
      setProducts(((productsRes as { data?: Product[] }).data ?? []) as Product[]);
      setTransactions(((txRes as { data?: Transaction[] }).data ?? []) as Transaction[]);
    } catch (e) {
      if (e instanceof ServerApiError && e.status === 401) {
        router.push('/login');
        return;
      }
      setError(e instanceof Error ? e.message : 'Failed to load product transactions.');
    } finally {
      setLoading(false);
    }
  }, [productId, router]);

  useEffect(() => {
    const timer = window.setTimeout(() => {
      load();
    }, 0);
    return () => window.clearTimeout(timer);
  }, [load]);

  const product = useMemo(
    () => products.find((item) => item.id === productId) ?? null,
    [productId, products]
  );

  const productTransactions = useMemo(
    () =>
      transactions
        .filter((txn) => txn.product_id === productId)
        .sort((left, right) => {
          const l = safeDate(left.created_at)?.getTime() ?? 0;
          const r = safeDate(right.created_at)?.getTime() ?? 0;
          return r - l;
        }),
    [productId, transactions]
  );

  return (
    <main className="min-h-screen bg-slate-50 p-6 text-slate-950 dark:bg-[#050816] dark:text-white">
      <div className="mx-auto max-w-5xl space-y-6">
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div>
            <Link
              href={`/products/${encodeURIComponent(productId)}`}
              className="text-sm font-bold text-indigo-600 hover:text-indigo-500 dark:text-indigo-300"
            >
              Back to product
            </Link>
            <h1 className="mt-3 text-3xl font-black">Product Transactions</h1>
            <p className="mt-1 text-sm text-slate-500 dark:text-gray-400">
              {product ? `${product.code || 'No code'} - ${product.name}` : productId}
            </p>
          </div>
          <button
            type="button"
            onClick={load}
            className="rounded-xl border border-slate-200 bg-white px-4 py-2 text-sm font-bold text-slate-700 shadow-sm transition hover:border-indigo-300 hover:text-indigo-600 dark:border-white/10 dark:bg-white/5 dark:text-gray-200"
          >
            Refresh
          </button>
        </div>

        <section className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm dark:border-white/10 dark:bg-white/[0.03]">
          <div className="mb-4 flex items-center justify-between">
            <h2 className="text-lg font-semibold">All History</h2>
            <span className="text-xs font-bold text-slate-500 dark:text-gray-400">
              {productTransactions.length} entries
            </span>
          </div>

          {loading ? (
            <p className="p-8 text-center text-sm text-slate-500 dark:text-gray-400">Loading transactions...</p>
          ) : error ? (
            <div className="rounded-xl border border-rose-200 bg-rose-50 p-4 text-sm text-rose-700 dark:border-rose-500/30 dark:bg-rose-500/10 dark:text-rose-200">
              {error}
            </div>
          ) : productTransactions.length === 0 ? (
            <p className="p-8 text-center text-sm text-slate-500 dark:text-gray-400">No history found.</p>
          ) : (
            <div className="space-y-2">
              {productTransactions.map((txn) => {
                const isIn = txn.type === 'stock_in';
                const cleanedNotes = cleanNotes(txn.notes);
                const customer = customerName(txn.notes);

                return (
                  <div
                    key={txn.id}
                    className="rounded-xl border border-slate-200 bg-slate-50 p-4 dark:border-white/10 dark:bg-white/5"
                  >
                    <div className="flex items-start justify-between gap-4">
                      <div className="min-w-0 flex-1">
                        <div className="mb-2 flex flex-wrap items-center gap-2">
                          <span className={`badge ${isIn ? 'badge-green' : 'badge-red'} text-[9px] uppercase`}>
                            {isIn ? 'IN' : 'OUT'}
                          </span>
                          <span className="text-sm font-black text-slate-900 dark:text-white">
                            {txn.product_code || product?.code || 'No Code'}
                          </span>
                          <span className="text-xs font-bold text-slate-500 dark:text-gray-400">
                            {txn.color_name || 'Standard'}
                          </span>
                        </div>
                        <div className="grid gap-1 text-xs text-slate-500 dark:text-gray-400 sm:grid-cols-2">
                          <p>By {txn.worker_name || 'Admin'}</p>
                          <p>{formatDateTime(txn.created_at)}</p>
                          <p>{txn.warehouse_name || 'Main Warehouse'}</p>
                          {customer && <p>Customer: {customer}</p>}
                        </div>
                        {cleanedNotes && (
                          <p className="mt-2 inline-block max-w-full rounded-lg bg-slate-100 px-2 py-1 text-xs text-slate-600 dark:bg-white/5 dark:text-gray-300">
                            {cleanedNotes}
                          </p>
                        )}
                      </div>
                      <div className="text-right">
                        <p className={`text-2xl font-black leading-none ${isIn ? 'text-emerald-500' : 'text-rose-500'}`}>
                          {isIn ? '+' : '-'}{txn.quantity}
                        </p>
                        <p className="mt-1 whitespace-nowrap text-xs font-bold text-slate-500 dark:text-gray-400">
                          {cartonLabel(txn)}
                        </p>
                      </div>
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </section>
      </div>
    </main>
  );
}
