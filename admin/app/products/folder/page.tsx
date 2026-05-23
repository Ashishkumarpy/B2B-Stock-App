'use client';

import NextImage from 'next/image';
import { useMemo, useState, useEffect } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import { serverGet, ServerApiError } from '../../../lib/server_api';
import { useRequireAuth } from '../../../lib/use_require_auth';
import ProductFormModal from '../../../components/ProductFormModal';

type StockStatus = 'in_stock' | 'low_stock' | 'out_of_stock';

interface Product {
  id: string;
  name: string;
  code: string;
  category: string;
  quantity: number;
  threshold: number;
  price: number;
  pcs_per_carton?: number;
  image_url?: string;
  images?: any[];
  description?: string;
  stock_status: StockStatus;
  color_stocks?: any[];
  created_at?: string;
  updated_at?: string;
}

const statusMap: Record<StockStatus, { label: string; cls: string }> = {
  in_stock: { label: 'In Stock', cls: 'badge-green' },
  low_stock: { label: 'Low Stock', cls: 'badge-yellow' },
  out_of_stock: { label: 'Out of Stock', cls: 'badge-red' },
};

function splitCategoryPath(value: string): string[] {
  return value
    .split(/\s*(?:\/|>|\\)\s*/g)
    .map((segment) => segment.trim())
    .filter(Boolean);
}

function isPrefix(prefix: string[], full: string[]): boolean {
  if (prefix.length > full.length) return false;
  for (let index = 0; index < prefix.length; index += 1) {
    if (prefix[index].toLowerCase() !== full[index].toLowerCase()) return false;
  }
  return true;
}

function sortProductsByCode(left: Product, right: Product): number {
  const codeCompare = left.code.localeCompare(right.code, undefined, {
    sensitivity: 'base',
    numeric: true,
  });
  if (codeCompare !== 0) return codeCompare;
  return left.name.localeCompare(right.name, undefined, { sensitivity: 'base' });
}

export default function FolderExplorerPage() {
  useRequireAuth();
  const router = useRouter();
  const searchParams = useSearchParams();
  const [products, setProducts] = useState<Product[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  
  const [customCategories, setCustomCategories] = useState<string[]>([]);
  const [showCategoryModal, setShowCategoryModal] = useState(false);
  const [newCategory, setNewCategory] = useState('');

  const [editingProduct, setEditingProduct] = useState<Product | null>(null);
  const [showEditModal, setShowEditModal] = useState(false);

  useEffect(() => {
    try {
      const raw = window.localStorage.getItem('product_categories');
      if (raw) {
        const parsed = JSON.parse(raw);
        if (Array.isArray(parsed)) setCustomCategories(parsed.map(String).filter(Boolean));
      }
    } catch {}
  }, []);

  const saveCustomCategories = (cats: string[]) => {
    setCustomCategories(cats);
    try { window.localStorage.setItem('product_categories', JSON.stringify(cats)); } catch {}
  };

  const allCategories = useMemo(() => {
    return Array.from(
      new Set([
        ...products.map((p) => p.category).filter(Boolean),
        ...customCategories.filter(Boolean),
      ])
    ).sort((a, b) => a.localeCompare(b));
  }, [products, customCategories]);

  const handleCreateCategory = () => {
    const value = newCategory.trim();
    if (!value) return;
    const exists = allCategories.some((c) => c.toLowerCase() === value.toLowerCase());
    const next = exists ? customCategories : [...customCategories, value];
    saveCustomCategories(next);
    setShowCategoryModal(false);
    router.push(`/products/folder?name=${encodeURIComponent(value)}`);
  };

  const openEdit = (product: Product) => {
    setEditingProduct(product);
    setShowEditModal(true);
  };

  const handleDeleteProduct = async (product: Product) => {
    if (!confirm(`Delete product "${product.name}"? This cannot be undone.`)) return;
    setLoading(true);
    try {
      const { serverDelete } = await import('../../../lib/server_api');
      await serverDelete(`/products/${product.id}`);
      await fetchProducts();
    } catch (e) {
      console.error('Failed to delete product:', e);
      alert('Failed to delete product.');
    } finally {
      setLoading(false);
    }
  };

  const rawPath = (searchParams.get('name') ?? '').trim();
  const currentSegments = useMemo(() => splitCategoryPath(rawPath), [rawPath]);
  const currentLabel = currentSegments.length > 0 ? currentSegments[currentSegments.length - 1] : 'Root';

  const fetchProducts = async () => {
    try {
      const res = await serverGet('/products');
      const data = (res as { data?: Product[] }).data ?? [];
      setProducts(data);
    } catch (error) {
      if (error instanceof ServerApiError && error.status === 401) {
        router.push('/login');
        return;
      }
      console.error(error);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchProducts();
  }, [router]);

  const productsInFolder = useMemo(() => {
    const items: Product[] = [];

    for (const product of products) {
      const segments = splitCategoryPath(product.category);
      if (!isPrefix(currentSegments, segments)) continue;
      items.push(product);
    }

    return items.sort(sortProductsByCode);
  }, [currentSegments, products]);

  const query = search.trim().toLowerCase();
  const visibleProducts = productsInFolder.filter(
    (product) =>
      !query ||
      product.name.toLowerCase().includes(query) ||
      product.code.toLowerCase().includes(query)
  );

  const gridClass = 'grid gap-4 sm:grid-cols-2 xl:grid-cols-3';
  const cardRoundClass = 'rounded-3xl';
  const overlayPadClass = 'inset-x-3 bottom-3 p-3';

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between gap-3">
        <div>
          <h1 className="text-2xl font-bold">Folder Explorer</h1>
          <p className="mt-1 text-sm text-gray-500">Windows-style navigation for product folders</p>
        </div>
        <div className="flex items-center gap-2">
          <button
            type="button"
            onClick={() => router.push('/products')}
            className="rounded-xl border border-white/10 px-4 py-2 text-sm text-gray-200 hover:bg-white/5"
          >
            Back to Products
          </button>
          <button
            type="button"
            onClick={() => {
              setNewCategory('');
              setShowCategoryModal(true);
            }}
            className="rounded-xl border border-indigo-500/40 bg-indigo-600/10 px-4 py-2 text-sm font-semibold text-indigo-300 transition hover:bg-indigo-600/20"
          >
            + Create Folder
          </button>
          <button
            type="button"
            onClick={() => {
              const currentPath = window.location.pathname + window.location.search;
              router.push(`/products?openAdd=true&category=${encodeURIComponent(currentSegments.join(' / '))}&returnTo=${encodeURIComponent(currentPath)}`);
            }}
            className="rounded-xl bg-indigo-600 px-4 py-2 text-sm font-semibold text-white transition hover:bg-indigo-500"
          >
            + Add Product
          </button>
        </div>
      </div>

      <div className="card p-4 md:p-5">
        <div className="mb-3 flex flex-wrap items-center gap-2">
          <button
            type="button"
            onClick={() => router.push('/products/folder')}
            className={`rounded-lg px-3 py-1.5 text-xs ${currentSegments.length === 0 ? 'bg-indigo-600 text-white' : 'border border-white/10 text-gray-300'
              }`}
          >
            Root
          </button>
          {currentSegments.map((segment, index) => {
            const path = currentSegments.slice(0, index + 1).join(' / ');
            const active = index === currentSegments.length - 1;
            return (
              <button
                key={`${path}-${index}`}
                type="button"
                onClick={() => router.push(`/products/folder?name=${encodeURIComponent(path)}`)}
                className={`rounded-lg px-3 py-1.5 text-xs ${active ? 'bg-indigo-600 text-white' : 'border border-white/10 text-gray-300'
                  }`}
              >
                {segment}
              </button>
            );
          })}
        </div>
        <input
          type="text"
          value={search}
          onChange={(event) => setSearch(event.target.value)}
          placeholder={`Search in ${currentLabel}...`}
          className="w-full rounded-xl border border-white/10 bg-white/5 px-4 py-2.5 text-sm text-white placeholder-gray-500 focus:border-indigo-500 focus:outline-none"
        />
      </div>

      <div className="card p-4 md:p-6">
        <h2 className="mb-4 text-sm font-semibold text-white">Products in {currentLabel}</h2>
        {loading ? (
          <div className="p-8 text-center text-sm text-gray-500">Loading products...</div>
        ) : visibleProducts.length === 0 ? (
          <div className="rounded-xl border border-white/10 bg-white/5 p-6 text-center text-sm text-gray-500">
            No products in this folder.
          </div>
        ) : (
          <div className={gridClass}>
            {visibleProducts.map((product, index) => {
              const status = statusMap[product.stock_status] || statusMap.out_of_stock;
              return (
                <div
                  key={product.id}
                  onClick={() => router.push(`/products/${encodeURIComponent(product.id)}`)}
                  className={`group relative aspect-square cursor-pointer overflow-hidden border border-white/10 bg-white/5 ${cardRoundClass}`}
                >
                  {product.image_url ? (
                      <NextImage
                        src={product.image_url}
                        alt={product.name}
                        fill
                        className="object-cover transition duration-500 group-hover:scale-110"
                        sizes="(max-width: 768px) 100vw, 33vw"
                        priority={index < 4}
                      />
                  ) : (
                    <div className="flex h-full w-full items-center justify-center text-4xl font-black tracking-widest text-indigo-300/75">
                      DIR
                    </div>
                  )}
                  <div className="absolute inset-0 bg-gradient-to-t from-black/90 via-black/30 to-transparent" />
                  <div className={`absolute rounded-2xl border border-white/20 bg-black/40 backdrop-blur-md ${overlayPadClass}`}>
                    <p className="font-mono text-sm font-semibold text-gray-100">{product.code}</p>
                    <p className="truncate text-xs font-medium text-gray-100">{product.name}</p>
                    <div className="mt-2 flex items-center justify-between text-[11px] text-gray-200">
                      <span>Qty: {(() => {
                        const size = product.pcs_per_carton || 1;
                        if (size <= 1) return `${product.quantity} pcs`;
                        const cartons = Math.floor(product.quantity / size);
                        const pcs = product.quantity % size;
                        if (cartons === 0) return `${pcs} pcs`;
                        if (pcs === 0) return `${cartons} ctn`;
                        return `${cartons} ctn, ${pcs} pcs`;
                      })()}</span>
                      <span>Rs {product.price.toLocaleString()}</span>
                    </div>
                    <div className="mt-2 flex items-center justify-between gap-1.5">
                      <span className={`inline-flex badge ${status.cls}`}>{status.label}</span>
                      <div className="flex gap-1">
                        <button
                          type="button"
                          onClick={(event) => {
                            event.stopPropagation();
                            router.push(`/products/${encodeURIComponent(product.id)}`);
                          }}
                          className="rounded-lg border border-white/10 bg-white/5 px-2 py-1 text-[10px] font-semibold text-gray-300 hover:bg-white/10"
                        >
                          Details
                        </button>
                        <button
                          type="button"
                          onClick={(event) => {
                            event.stopPropagation();
                            openEdit(product);
                          }}
                          className="rounded-lg border border-indigo-200 dark:border-indigo-500/40 bg-indigo-50 dark:bg-indigo-600/20 px-2 py-1 text-[10px] font-semibold text-indigo-600 dark:text-indigo-200 hover:bg-indigo-100 dark:hover:bg-indigo-600/30 transition-all"
                        >
                          Edit
                        </button>
                        <button
                          type="button"
                          onClick={(event) => {
                            event.stopPropagation();
                            handleDeleteProduct(product);
                          }}
                          className="rounded-lg border border-red-200 dark:border-red-500/40 bg-red-50 dark:bg-red-600/20 px-2 py-1 text-[10px] font-semibold text-red-600 dark:text-red-200 hover:bg-red-100 dark:hover:bg-red-600/30 transition-all"
                        >
                          Delete
                        </button>
                      </div>
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </div>

      {showCategoryModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 p-4 backdrop-blur-sm">
          <div className="w-full max-w-md rounded-3xl border border-white/10 bg-[#0f1117] p-8 shadow-2xl">
            <h3 className="text-xl font-bold mb-2">Create Folder</h3>
            <p className="text-xs text-gray-400 mb-6 uppercase tracking-widest">New category for your products</p>
            <input value={newCategory} onChange={e => setNewCategory(e.target.value)} placeholder="Folder Name" className="w-full rounded-xl border border-white/10 bg-white/5 px-4 py-3 text-sm text-white focus:border-indigo-500 focus:outline-none mb-6" />
            <div className="flex gap-3">
              <button onClick={handleCreateCategory} className="flex-1 rounded-xl bg-indigo-600 py-3 font-bold text-white hover:bg-indigo-500 transition-all">Create</button>
              <button onClick={() => setShowCategoryModal(false)} className="rounded-xl border border-white/10 px-6 py-3 text-sm font-semibold text-gray-300 hover:bg-white/5 transition-all">Cancel</button>
            </div>
          </div>
        </div>
      )}

      {showEditModal && (
        <ProductFormModal
          isOpen={showEditModal}
          onClose={() => {
            setShowEditModal(false);
            setEditingProduct(null);
          }}
          onSuccess={() => {
            setShowEditModal(false);
            setEditingProduct(null);
            fetchProducts();
          }}
          editingProduct={editingProduct}
          allCategories={allCategories}
          existingProducts={products}
        />
      )}
    </div>
  );
}
