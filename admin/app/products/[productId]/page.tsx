'use client';

import NextImage from 'next/image';
import { useCallback, useEffect, useMemo, useState } from 'react';
import { useParams, useRouter } from 'next/navigation';
import { serverDelete, serverGet, ServerApiError } from '../../../lib/server_api';
import { useRequireAuth } from '../../../lib/use_require_auth';
import ProductFormModal, { Product } from '../../../components/ProductFormModal';

type StockStatus = 'in_stock' | 'low_stock' | 'out_of_stock';
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

export function parseCartonFromNotes(notes?: string | null): { cartons: number; pcsPerCarton: number } | null {
  if (!notes) return null;
  const regex = /(\d+)\s*(?:ctn|carton|cartons)\s*(?:[x*]|\(|pcs\/ctn|pcs)?\s*(\d+)/i;
  const match = notes.match(regex);
  if (match) {
    const cartons = parseInt(match[1], 10);
    const pcsPerCarton = parseInt(match[2], 10);
    if (!isNaN(cartons) && !isNaN(pcsPerCarton) && pcsPerCarton > 0) {
      return { cartons, pcsPerCarton };
    }
  }
  return null;
}

const statusMap: Record<StockStatus, { label: string; cls: string }> = {
  in_stock: { label: 'In Stock', cls: 'badge-green' },
  low_stock: { label: 'Low Stock', cls: 'badge-yellow' },
  out_of_stock: { label: 'Out of Stock', cls: 'badge-red' },
};

function safeDate(value?: string | null): Date | null {
  if (!value) return null;
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function formatDateTime(value?: string | null) {
  const date = safeDate(value);
  if (!date) return '—';
  return new Intl.DateTimeFormat('en-IN', {
    day: '2-digit',
    month: 'short',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  }).format(date);
}

function formatMoney(value: number) {
  return new Intl.NumberFormat('en-IN', { maximumFractionDigits: 0 }).format(value);
}

function productImageUrls(product: Product | null): string[] {
  if (!product) return [];
  const urls = new Set<string>();
  if (product.image_url && product.image_url.trim()) urls.add(product.image_url.trim());
  for (const image of product.images ?? []) {
    if (image?.url) urls.add(image.url);
  }
  return Array.from(urls);
}

function sevenDayNetSeries(transactions: Transaction[]) {
  const now = new Date();
  const points = Array.from({ length: 7 }).map((_, index) => {
    const date = new Date(now.getFullYear(), now.getMonth(), now.getDate() - (6 - index));
    return {
      key: date.toISOString().slice(0, 10),
      label: new Intl.DateTimeFormat('en-IN', { day: '2-digit', month: 'short' }).format(date),
      value: 0,
    };
  });
  const pointMap = new Map(points.map((p) => [p.key, p]));

  for (const txn of transactions) {
    const date = safeDate(txn.created_at);
    if (!date) continue;
    const key = new Date(date.getFullYear(), date.getMonth(), date.getDate()).toISOString().slice(0, 10);
    const point = pointMap.get(key);
    if (!point) continue;
    point.value += txn.type === 'stock_in' ? txn.quantity : -txn.quantity;
  }
  return points;
}

export default function ProductDetailAdminPage() {
  useRequireAuth();
  const router = useRouter();
  const params = useParams<{ productId: string }>();
  const productId = String(params?.productId ?? '');

  const [products, setProducts] = useState<Product[]>([]);
  const [transactions, setTransactions] = useState<Transaction[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [selectedImageIndex, setSelectedImageIndex] = useState(0);
  const [deleting, setDeleting] = useState(false);
  const [showEditModal, setShowEditModal] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const [productsRes, txRes] = await Promise.all([
        serverGet('/products'),
        serverGet(`/transactions?product_id=${encodeURIComponent(productId)}`)
      ]);
      setProducts(((productsRes as { data?: Product[] }).data ?? []) as Product[]);
      setTransactions(((txRes as { data?: Transaction[] }).data ?? []) as Transaction[]);
    } catch (e) {
      if (e instanceof ServerApiError && e.status === 401) {
        router.push('/login');
        return;
      }
      setError(e instanceof Error ? e.message : 'Failed to load product details.');
    } finally {
      setLoading(false);
    }
  }, [productId, router]);

  useEffect(() => {
    load();
    setSelectedImageIndex(0);
  }, [load, productId]);

  const product = useMemo(
    () => products.find((item) => item.id === productId) ?? null,
    [productId, products]
  );

  const sortedProducts = useMemo(() => {
    return [...products].sort((left, right) => {
      const catCompare = (left.category || '').localeCompare(right.category || '', undefined, { sensitivity: 'base' });
      if (catCompare !== 0) return catCompare;
      const codeCompare = left.code.localeCompare(right.code, undefined, {
        sensitivity: 'base',
        numeric: true,
      });
      if (codeCompare !== 0) return codeCompare;
      return left.name.localeCompare(right.name, undefined, { sensitivity: 'base' });
    });
  }, [products]);

  const currentIndex = useMemo(() => {
    return sortedProducts.findIndex((item) => item.id === productId);
  }, [sortedProducts, productId]);

  const prevProduct = useMemo(() => {
    return currentIndex > 0 ? sortedProducts[currentIndex - 1] : null;
  }, [sortedProducts, currentIndex]);

  const nextProduct = useMemo(() => {
    return currentIndex >= 0 && currentIndex < sortedProducts.length - 1
      ? sortedProducts[currentIndex + 1]
      : null;
  }, [sortedProducts, currentIndex]);

  const images = useMemo(() => productImageUrls(product), [product]);
  const activeImageIndex = Math.max(0, Math.min(selectedImageIndex, Math.max(images.length - 1, 0)));
  const currentImage = images[activeImageIndex] ?? images[0] ?? null;

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

  const stockInThirtyDays = useMemo(() => {
    const thirtyDaysAgo = new Date();
    thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);
    return productTransactions
      .filter((txn) => txn.type === 'stock_in' && (safeDate(txn.created_at)?.getTime() ?? 0) >= thirtyDaysAgo.getTime())
      .reduce((sum, txn) => sum + txn.quantity, 0);
  }, [productTransactions]);

  const stockOutThirtyDays = useMemo(() => {
    const thirtyDaysAgo = new Date();
    thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);
    return productTransactions
      .filter((txn) => txn.type === 'stock_out' && (safeDate(txn.created_at)?.getTime() ?? 0) >= thirtyDaysAgo.getTime())
      .reduce((sum, txn) => sum + txn.quantity, 0);
  }, [productTransactions]);

  const netSevenDays = useMemo(() => sevenDayNetSeries(productTransactions), [productTransactions]);
  const maxY = Math.max(0, ...netSevenDays.map((point) => point.value));
  const minY = Math.min(0, ...netSevenDays.map((point) => point.value));
  const ySpan = Math.max(1, maxY - minY);
  const chartPoints = netSevenDays
    .map((point, index) => {
      const x = (index / Math.max(netSevenDays.length - 1, 1)) * 100;
      const y = ((maxY - point.value) / ySpan) * 100;
      return `${x},${y}`;
    })
    .join(' ');

  const handleDelete = async () => {
    if (!product || deleting) return;
    if (!confirm('Delete this product? This action cannot be undone.')) return;
    setDeleting(true);
    try {
      await serverDelete(`/products/${product.id}`);
      router.push('/products');
    } catch (e) {
      alert(e instanceof Error ? e.message : 'Failed to delete product.');
    } finally {
      setDeleting(false);
    }
  };

  const goBackToFolder = () => {
    const category = product?.category?.trim();
    if (category) {
      router.push(`/products/folder?name=${encodeURIComponent(category)}`);
      return;
    }
    router.push('/products/folder');
  };

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-2xl font-bold">Product Details</h1>
          <p className="mt-1 text-sm text-gray-500">History and stock movement</p>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          {prevProduct && (
            <button
              type="button"
              onClick={() => router.push(`/products/${encodeURIComponent(prevProduct.id)}`)}
              className="rounded-xl border border-slate-200 dark:border-white/10 bg-slate-50 dark:bg-transparent px-3.5 py-2 text-sm text-slate-700 dark:text-gray-200 hover:bg-slate-100 dark:hover:bg-white/5 transition-all flex items-center gap-1.5"
              title={`Previous: ${prevProduct.name}`}
            >
              <span className="text-xs">←</span> <span>Prev</span>
            </button>
          )}
          {nextProduct && (
            <button
              type="button"
              onClick={() => router.push(`/products/${encodeURIComponent(nextProduct.id)}`)}
              className="rounded-xl border border-slate-200 dark:border-white/10 bg-slate-50 dark:bg-transparent px-3.5 py-2 text-sm text-slate-700 dark:text-gray-200 hover:bg-slate-100 dark:hover:bg-white/5 transition-all flex items-center gap-1.5"
              title={`Next: ${nextProduct.name}`}
            >
              <span>Next</span> <span className="text-xs">→</span>
            </button>
          )}
          {(prevProduct || nextProduct) && (
            <div className="h-6 w-px bg-slate-200 dark:bg-white/10 mx-1" />
          )}
          <button type="button" onClick={goBackToFolder} className="rounded-xl border border-slate-200 dark:border-white/10 bg-slate-50 dark:bg-transparent px-4 py-2 text-sm text-slate-700 dark:text-gray-200 hover:bg-slate-100 dark:hover:bg-white/5 transition-all">Back to Folder</button>
          {product && (
            <>
              <button type="button" onClick={() => setShowEditModal(true)} className="rounded-xl border border-indigo-200 dark:border-indigo-500/30 bg-indigo-50 dark:bg-indigo-600/20 px-4 py-2 text-sm font-semibold text-indigo-600 dark:text-indigo-200 hover:bg-indigo-100 dark:hover:bg-indigo-600/30 transition-all">Edit</button>
              <button type="button" onClick={handleDelete} disabled={deleting} className="rounded-xl border border-red-200 dark:border-red-500/40 bg-red-50 dark:bg-red-500/20 px-4 py-2 text-sm font-semibold text-red-600 dark:text-red-200 hover:bg-red-100 dark:hover:bg-red-500/30 disabled:opacity-60 transition-all">{deleting ? 'Deleting...' : 'Delete'}</button>
            </>
          )}
        </div>
      </div>

      {loading ? (
        <div className="card p-12 text-center text-sm text-gray-500">Loading details...</div>
      ) : error ? (
        <div className="card border border-red-500/20 bg-red-500/10 p-6 text-sm text-red-300">{error}</div>
      ) : !product ? (
        <div className="card p-12 text-center text-sm text-gray-500">Product not found.</div>
      ) : (
        <>
          <div className="grid gap-6 lg:grid-cols-[1.15fr_1fr]">
            <div className="card p-4">
              <div className="relative aspect-square overflow-hidden rounded-2xl border border-white/10 bg-white/5">
                {currentImage ? (
                  <NextImage src={currentImage} alt={product.name} fill className="object-contain" sizes="(max-width: 1024px) 100vw, 60vw" priority />
                ) : (
                  <div className="flex h-full items-center justify-center text-gray-500">No image</div>
                )}
              </div>
              {images.length > 1 && (
                <div className="mt-3 grid grid-cols-6 gap-2">
                  {images.map((url, index) => (
                    <button key={`${url}-${index}`} type="button" onClick={() => setSelectedImageIndex(index)} className={`relative aspect-square overflow-hidden rounded-lg border ${activeImageIndex === index ? 'border-indigo-500 ring-1 ring-indigo-500/50' : 'border-white/10'}`}>
                      <NextImage src={url} alt="Thumbnail" fill className="object-cover" sizes="96px" />
                    </button>
                  ))}
                </div>
              )}
            </div>

            <div className="space-y-4">
              <div className="card p-5">
                <div className="mb-3 flex items-start justify-between gap-3">
                  <div className="min-w-0">
                    <p className="truncate font-mono text-2xl font-black text-indigo-600 dark:text-indigo-200">{product.code}</p>
                    <p className="mt-1 truncate text-sm font-semibold text-slate-800 dark:text-white/90">{product.name}</p>
                  </div>
                  <span className={`inline-flex badge ${statusMap[product.stock_status]?.cls ?? 'badge-gray'}`}>
                    {statusMap[product.stock_status]?.label ?? 'Unknown'}
                  </span>
                </div>
                <div className="grid grid-cols-2 gap-3 text-sm">
                  <div className="rounded-xl border border-white/10 bg-white/5 p-3">
                    <p className="text-xs text-gray-500">Category</p>
                    <p className="mt-1 font-semibold text-white">{product.category || 'Uncategorized'}</p>
                  </div>
                  <div className="rounded-xl border border-white/10 bg-white/5 p-3">
                    <p className="text-xs text-gray-500">Price</p>
                    <p className="mt-1 font-semibold text-white">Rs {formatMoney(product.price)}</p>
                  </div>
                  <div className="rounded-xl border border-white/10 bg-white/5 p-3">
                    <p className="text-xs text-gray-500">Pcs per Carton</p>
                    <p className="mt-1 font-semibold text-white">{product.pcs_per_carton || 1} pcs/ctn</p>
                  </div>
                  <div className="rounded-xl border border-white/10 bg-white/5 p-3">
                    <p className="text-xs text-gray-500">MOQ / Threshold</p>
                    <p className="mt-1 font-semibold text-white">{product.threshold || 50} pcs</p>
                  </div>
                  <div className="rounded-xl border border-white/10 bg-white/5 p-3">
                    <p className="text-xs text-gray-500">Created</p>
                    <p className="mt-1 text-[10px] text-gray-300">{formatDateTime(product.created_at)}</p>
                  </div>
                  <div className="rounded-xl border border-white/10 bg-white/5 p-3">
                    <p className="text-xs text-gray-500">Updated</p>
                    <p className="mt-1 text-[10px] text-gray-300">{formatDateTime(product.updated_at)}</p>
                  </div>
                </div>
                {product.description && (
                  <div className="mt-4 rounded-xl border border-white/10 bg-white/5 p-3 text-sm text-gray-300 leading-relaxed">{product.description}</div>
                )}
              </div>

              <div className="grid grid-cols-2 gap-3">
                <div className="card border border-emerald-500/30 bg-emerald-500/10 p-4">
                  <p className="text-[10px] uppercase font-bold text-emerald-300">Stock</p>
                  <p className="mt-1 text-lg font-black text-emerald-100 truncate">{(() => {
                    const size = product.pcs_per_carton || 1;
                    if (size <= 1) return `${product.quantity} pcs`;
                    const cartons = Math.floor(product.quantity / size);
                    const pcs = product.quantity % size;
                    if (cartons === 0) return `${pcs} pcs`;
                    if (pcs === 0) return `${cartons} ctn`;
                    return `${cartons} ctn, ${pcs} pcs`;
                  })()}</p>
                  <p className="text-[10px] text-emerald-400">({product.quantity} total pcs)</p>
                </div>
                <div className="card border border-amber-500/30 bg-amber-500/10 p-4">
                  <p className="text-[10px] uppercase font-bold text-amber-300">Threshold</p>
                  <p className="mt-1 text-2xl font-black text-amber-100">{product.threshold}</p>
                </div>
                <div className="card border border-indigo-500/30 bg-indigo-500/10 p-4">
                  <p className="text-[10px] uppercase font-bold text-indigo-300">In (30d)</p>
                  <p className="mt-1 text-2xl font-black text-indigo-100">+{stockInThirtyDays}</p>
                </div>
                <div className="card border border-rose-500/30 bg-rose-500/10 p-4">
                  <p className="text-[10px] uppercase font-bold text-rose-300">Out (30d)</p>
                  <p className="mt-1 text-2xl font-black text-rose-100">-{stockOutThirtyDays}</p>
                </div>
              </div>

              <div className="grid grid-cols-2 gap-3">
                <button type="button" onClick={() => router.push(`/stock?productId=${encodeURIComponent(product.id)}&type=stock_in`)} className="rounded-xl bg-emerald-600/20 py-3 text-sm font-bold text-emerald-300 hover:bg-emerald-600/30">+ Stock In</button>
                <button type="button" onClick={() => router.push(`/stock?productId=${encodeURIComponent(product.id)}&type=stock_out`)} className="rounded-xl bg-rose-600/20 py-3 text-sm font-bold text-rose-300 hover:bg-rose-600/30">- Stock Out</button>
              </div>
            </div>
          </div>

          <div className="card p-5">
            <h2 className="mb-4 text-lg font-semibold text-white">Color Stock</h2>
            {product.color_stocks && product.color_stocks.length > 0 ? (
              <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
                {product.color_stocks.map((entry, index) => (
                  <div key={`${entry.color}-${index}`} className="flex items-center justify-between rounded-xl border border-white/10 bg-white/5 px-4 py-3">
                    <span className="text-sm font-semibold text-white">{entry.color}</span>
                    <div className="text-right">
                      <span className="text-sm font-black text-indigo-300">{(() => {
                        const size = product.pcs_per_carton || 1;
                        if (size <= 1) return `${entry.quantity} pcs`;
                        const cartons = Math.floor(entry.quantity / size);
                        const pcs = entry.quantity % size;
                        if (cartons === 0) return `${pcs} pcs`;
                        if (pcs === 0) return `${cartons} ctn`;
                        return `${cartons} ctn, ${pcs} pcs`;
                      })()}</span>
                      {product.pcs_per_carton && product.pcs_per_carton > 1 && (
                        <p className="text-[9px] text-gray-500">({entry.quantity} pcs)</p>
                      )}
                    </div>
                  </div>
                ))}
              </div>
            ) : (
              <p className="text-sm text-gray-500">No color-wise stock added.</p>
            )}
          </div>

          <div className="card p-5">
            <div className="mb-4 flex items-center justify-between">
              <h2 className="text-lg font-semibold text-white">7-Day Activity</h2>
            </div>
            <div className="rounded-2xl border border-white/10 bg-white/5 p-6">
              <svg viewBox="0 0 100 100" className="h-48 w-full overflow-visible">
                <line x1="0" y1="50" x2="100" y2="50" stroke="rgba(255,255,255,0.1)" strokeDasharray="4 2" />
                <polyline fill="none" stroke="#6366f1" strokeWidth="2" points={chartPoints} />
              </svg>
              <div className="mt-4 grid grid-cols-7 gap-2 text-center text-[10px] text-gray-500">
                {netSevenDays.map(p => <div key={p.key}><p>{p.label}</p><p className={p.value >= 0 ? 'text-emerald-400' : 'text-rose-400'}>{p.value > 0 ? `+${p.value}` : p.value}</p></div>)}
              </div>
            </div>
          </div>

          <div className="card p-5">
            <div className="mb-4 flex items-center justify-between">
              <h2 className="text-lg font-semibold text-white">Transactions</h2>
              <span className="text-xs text-gray-500">{productTransactions.length} entries</span>
            </div>
            <div className="space-y-2">
              {productTransactions.slice(0, 20).map((txn) => {
                const isIn = txn.type === 'stock_in';
                return (
                  <div key={txn.id} className="rounded-xl border border-white/10 bg-white/5 p-4 flex items-center justify-between gap-4">
                    <div className="min-w-0 flex-1">
                      <div className="flex items-center gap-2 mb-1">
                        <span className={`badge ${isIn ? 'badge-green' : 'badge-red'} text-[9px] uppercase`}>{isIn ? 'IN' : 'OUT'}</span>
                        <span className="text-xs font-bold text-white truncate">{txn.color_name || 'Standard'}</span>
                      </div>
                      <p className="text-[10px] text-gray-500 truncate">By {txn.worker_name || 'Admin'} • {formatDateTime(txn.created_at)}</p>
                      {txn.notes && (
                        <div className="mt-1">
                          <span className="text-[9px] text-gray-400 truncate bg-white/5 px-1.5 py-0.5 rounded inline-block max-w-full">
                            {txn.notes}
                          </span>
                        </div>
                      )}
                    </div>
                    <div className="flex flex-col items-end justify-center">
                      <span className={`text-lg font-black leading-none ${isIn ? 'text-emerald-400' : 'text-rose-400'}`}>
                        {isIn ? '+' : '-'}{txn.quantity}
                      </span>
                      {(() => {
                        if (txn.cartons !== undefined && txn.cartons !== null) {
                          return (
                            <span className="text-[10px] text-gray-400 leading-tight mt-1 whitespace-nowrap">
                              {txn.cartons} ctn × {txn.pcs_per_carton || 1}
                            </span>
                          );
                        }
                        const parsed = parseCartonFromNotes(txn.notes);
                        if (parsed) {
                          return (
                            <span className="text-[10px] text-gray-400 leading-tight mt-1 whitespace-nowrap">
                              {parsed.cartons} ctn × {parsed.pcsPerCarton}
                            </span>
                          );
                        }
                        return null;
                      })()}
                    </div>
                  </div>
                );
              })}
              {productTransactions.length === 0 && <p className="p-8 text-center text-sm text-gray-500">No history found.</p>}
            </div>
          </div>
        </>
      )}

      <ProductFormModal
        isOpen={showEditModal}
        onClose={() => setShowEditModal(false)}
        onSuccess={() => load()}
        editingProduct={product}
        existingProducts={products}
      />
    </div>
  );
}
