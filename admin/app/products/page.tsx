'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import NextImage from 'next/image';
import { serverDelete, serverGet, ServerApiError } from '../../lib/server_api';
import { useRouter, useSearchParams } from 'next/navigation';
import { useRequireAuth } from '../../lib/use_require_auth';
import ProductFormModal, { Product } from '../../components/ProductFormModal';
import { supabase } from '../../lib/supabase';

interface ProductsResponse {
  data?: Product[];
}

function productImageUrls(product: Product): string[] {
  const urls = new Set<string>();
  if (product.image_url) urls.add(product.image_url);
  for (const image of product.images ?? []) {
    if (image?.url) urls.add(image.url);
  }
  return Array.from(urls);
}

function sortProductsByCode(left: Product, right: Product): number {
  const codeCompare = left.code.localeCompare(right.code, undefined, {
    sensitivity: 'base',
    numeric: true,
  });
  if (codeCompare !== 0) return codeCompare;
  return left.name.localeCompare(right.name, undefined, { sensitivity: 'base' });
}

export default function ProductsPage() {
  useRequireAuth();
  const router = useRouter();
  const searchParams = useSearchParams();
  
  const [products, setProducts] = useState<Product[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [selectedCategory, setSelectedCategory] = useState<string | null>(null);
  const [customCategories, setCustomCategories] = useState<string[]>([]);
  const [showCategoryModal, setShowCategoryModal] = useState(false);
  const [newCategory, setNewCategory] = useState('');
  
  const [showModal, setShowModal] = useState(false);
  const [editingProduct, setEditingProduct] = useState<Product | null>(null);
  const [initialCategory, setInitialCategory] = useState('');
  
  const [highlightedProductId, setHighlightedProductId] = useState<string | null>(null);
  const [viewerImages, setViewerImages] = useState<string[]>([]);
  const [viewerIndex, setViewerIndex] = useState(0);
  const handledProductIdRef = useRef<string | null>(null);
  const handledAddRef = useRef(false);
  const returnToRef = useRef<string | null>(null);

  const fetchProducts = useCallback(async () => {
    try {
      const res = (await serverGet('/products')) as ProductsResponse;
      setProducts(res.data ?? []);
    } catch (e) {
      if (e instanceof ServerApiError && e.status === 401) {
        router.push('/login');
        return;
      }
      console.error('Failed to fetch products:', e);
    } finally {
      setLoading(false);
    }
  }, [router]);

  const [realtimeStatus, setRealtimeStatus] = useState<'connecting' | 'connected' | 'error'>('connecting');

  useEffect(() => {
    fetchProducts();

    const channel = supabase
      .channel('products-changes')
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'products' },
        () => {
          fetchProducts();
        }
      )
      .subscribe((status) => {
        if (status === 'SUBSCRIBED') setRealtimeStatus('connected');
        if (status === 'CHANNEL_ERROR') setRealtimeStatus('error');
      });

    return () => {
      supabase.removeChannel(channel);
    };
  }, [fetchProducts]);

  useEffect(() => {
    try {
      const raw = window.localStorage.getItem('product_categories');
      if (raw) {
        const parsed = JSON.parse(raw);
        if (Array.isArray(parsed)) setCustomCategories(parsed.map(String).filter(Boolean));
      }
    } catch {}
  }, []);

  const saveCustomCategories = useCallback((cats: string[]) => {
    setCustomCategories(cats);
    try { window.localStorage.setItem('product_categories', JSON.stringify(cats)); } catch {}
  }, []);

  const allCategories = Array.from(
    new Set([
      ...products.map((p) => p.category).filter(Boolean),
      ...customCategories.filter(Boolean),
    ])
  ).sort((a, b) => a.localeCompare(b));

  const openAdd = useCallback((category?: string) => {
    setEditingProduct(null);
    setInitialCategory(category || '');
    setShowModal(true);
  }, []);

  const openEdit = useCallback((product: Product) => {
    setEditingProduct(product);
    setShowModal(true);
  }, []);

  useEffect(() => {
    const queryProductId = searchParams.get('productId');
    if (!queryProductId || products.length === 0) return;
    if (handledProductIdRef.current === queryProductId) return;
    const match = products.find((p) => p.id === queryProductId);
    if (!match) return;

    handledProductIdRef.current = queryProductId;
    setHighlightedProductId(queryProductId);
    openEdit(match);
    setTimeout(() => setHighlightedProductId(null), 5000);
  }, [openEdit, products, searchParams]);

  useEffect(() => {
    if (handledAddRef.current) return;
    if (searchParams.get('openAdd') === 'true') {
      handledAddRef.current = true;
      const cat = searchParams.get('category') || '';
      returnToRef.current = searchParams.get('returnTo');
      openAdd(cat);
      
      const newUrl = new URL(window.location.href);
      newUrl.searchParams.delete('openAdd');
      newUrl.searchParams.delete('category');
      newUrl.searchParams.delete('returnTo');
      window.history.replaceState({}, '', newUrl.toString());
    }
  }, [searchParams, openAdd]);

  const onModalSuccess = async () => {
    const returnTo = returnToRef.current;
    returnToRef.current = null;
    if (returnTo) {
      router.push(returnTo);
    } else {
      await fetchProducts();
    }
  };

  const openCreateCategory = () => {
    setNewCategory('');
    setShowCategoryModal(true);
  };

  const handleCreateCategory = () => {
    const value = newCategory.trim();
    if (!value) return;
    const exists = allCategories.some((c) => c.toLowerCase() === value.toLowerCase());
    const next = exists ? customCategories : [...customCategories, value];
    saveCustomCategories(next);
    setSelectedCategory(value);
    setShowCategoryModal(false);
  };

  const handleDelete = async (product: Product) => {
    if (!confirm('Delete this product? This cannot be undone.')) return;
    try {
      await serverDelete(`/products/${product.id}`);
      await fetchProducts();
    } catch (e) {
      console.error('Failed to delete product:', e);
    }
  };

  const query = search.trim().toLowerCase();
  const folderSummaries = allCategories.map((category) => {
    const categoryProducts = products.filter((p) => p.category === category);
    const sampleImage = categoryProducts.find((p) => p.image_url)?.image_url ?? null;
    const totalQty = categoryProducts.reduce((sum, p) => sum + p.quantity, 0);
    const lowStockCount = categoryProducts.filter(p => p.stock_status !== 'in_stock').length;
    return { name: category, count: categoryProducts.length, totalQty, lowStockCount, sampleImage, products: categoryProducts };
  });

  const visibleFolders = folderSummaries.filter((f) => {
    if (!query) return true;
    if (f.name.toLowerCase().includes(query)) return true;
    return f.products.some(p => p.name.toLowerCase().includes(query) || p.code.toLowerCase().includes(query));
  });

  const searchedProducts = query ? products.filter(p => p.name.toLowerCase().includes(query) || p.code.toLowerCase().includes(query)).sort(sortProductsByCode) : [];

  const renderProductCard = (product: Product, index: number) => {
    const status = (product.stock_status === 'in_stock') ? { label: 'In Stock', cls: 'badge-green' } :
                   (product.stock_status === 'low_stock') ? { label: 'Low Stock', cls: 'badge-yellow' } :
                   { label: 'Out of Stock', cls: 'badge-red' };
    return (
      <div
        key={product.id}
        onClick={() => router.push(`/products/${encodeURIComponent(product.id)}`)}
        className={`group relative aspect-square overflow-hidden rounded-3xl border border-white/10 bg-white/5 ${highlightedProductId === product.id ? 'ring-2 ring-indigo-500/30' : ''} cursor-pointer`}
      >
        <div className="absolute inset-0">
          {product.image_url ? (
                    <NextImage src={product.image_url} alt={product.name} fill className="object-cover transition duration-500 group-hover:scale-110" sizes="300px" priority={index < 3} />
          ) : (
            <div className="flex h-full w-full items-center justify-center text-4xl font-black text-indigo-300/75">DIR</div>
          )}
        </div>
        <div className="absolute inset-0 bg-gradient-to-t from-black/90 via-black/30 to-transparent" />
        <div className="absolute inset-x-3 bottom-3 rounded-2xl border border-white/20 bg-black/40 p-3 backdrop-blur-md">
          <p className="truncate text-sm font-semibold text-white">{product.name}</p>
          <p className="font-mono text-[11px] text-gray-200">{product.code}</p>
          <div className="mt-2 flex items-center justify-between text-[11px] text-gray-200">
            <span>Qty: {product.quantity}</span>
            <span>Rs {product.price.toLocaleString()}</span>
          </div>
          <div className="mt-2 flex items-center justify-between gap-2">
            <span className={`inline-flex badge ${status.cls}`}>{status.label}</span>
            <div className="flex gap-2">
              <button onClick={(e) => { e.stopPropagation(); setViewerImages(productImageUrls(product)); setViewerIndex(0); }} className="rounded-lg border border-sky-500/40 bg-sky-600/20 px-2.5 py-1 text-[11px] font-semibold text-sky-200 hover:bg-sky-600/30">Photos</button>
              <button onClick={(e) => { e.stopPropagation(); openEdit(product); }} className="rounded-lg border border-indigo-500/40 bg-indigo-600/20 px-2.5 py-1 text-[11px] font-semibold text-indigo-200 hover:bg-indigo-600/30">Edit</button>
            </div>
          </div>
        </div>
      </div>
    );
  };

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold">Products</h1>
          <p className="mt-1 text-sm text-gray-500">{products.length} products total</p>
        </div>
        <div className="flex items-center gap-2">
          <button onClick={() => router.push('/products/folder')} className="rounded-xl border border-white/10 px-4 py-2.5 text-sm font-semibold text-gray-200 hover:bg-white/5">Open Explorer</button>
          <button onClick={() => openAdd()} className="rounded-xl bg-indigo-600 px-4 py-2.5 text-sm font-semibold text-white hover:bg-indigo-500 transition-all">+ Add Product</button>
        </div>
      </div>

      <div className="flex flex-col gap-3 md:flex-row md:items-center md:justify-between">
        <input
          type="text"
          placeholder="Search folders or products..."
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          className="w-full max-w-sm rounded-xl border border-white/10 bg-white/5 px-4 py-2.5 text-sm text-white placeholder-gray-500 focus:border-indigo-500 focus:outline-none"
        />
        <button onClick={openCreateCategory} className="rounded-xl bg-indigo-600 px-4 py-2 text-xs font-semibold text-white hover:bg-indigo-500">+ Create Folder</button>
      </div>

      {query ? (
        <div className="card p-4 md:p-6">
          <h2 className="text-sm font-semibold text-white mb-4">Search Results ({searchedProducts.length})</h2>
          {loading ? <div className="p-12 text-center text-sm text-gray-500">Loading...</div> : searchedProducts.length === 0 ? <div className="p-12 text-center text-sm text-gray-500">No matches found.</div> : (
            <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">{searchedProducts.map((p, i) => renderProductCard(p, i))}</div>
          )}
        </div>
      ) : (
        <div className="card p-4 md:p-6">
          <h2 className="text-sm font-semibold text-white mb-4">Folders ({visibleFolders.length})</h2>
          {loading ? <div className="p-12 text-center text-sm text-gray-500">Loading...</div> : visibleFolders.length === 0 ? <div className="p-12 text-center text-sm text-gray-500">No products yet.</div> : (
            <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
              {visibleFolders.map((folder, index) => (
                <button
                  key={folder.name}
                  type="button"
                  onClick={() => router.push(`/products/folder?name=${encodeURIComponent(folder.name)}`)}
                  className="group relative aspect-square overflow-hidden rounded-3xl border border-white/10 bg-white/5 hover:border-indigo-500/40 transition-all"
                >
                  <div className="relative h-full w-full bg-[#121826]">
                    {folder.sampleImage ? (
                      <NextImage src={folder.sampleImage} alt={folder.name} fill className="object-cover transition duration-500 group-hover:scale-110" sizes="300px" priority={index < 3} />
                    ) : (
                      <div className="flex h-full w-full items-center justify-center text-4xl font-black text-indigo-300/75">DIR</div>
                    )}
                    <div className="absolute inset-0 bg-gradient-to-t from-black/85 via-black/20 to-transparent" />
                    <div className="absolute inset-x-3 bottom-3 rounded-2xl border border-white/20 bg-black/35 p-3 backdrop-blur-md">
                      <div className="mb-2 flex items-center justify-between">
                        <p className="truncate text-sm font-semibold text-white">{folder.name}</p>
                        <span className="rounded-full bg-black/50 px-2 py-0.5 text-[11px] text-white">{folder.count}</span>
                      </div>
                      <div className="grid grid-cols-2 gap-2 text-[11px] text-gray-200">
                        <div className="rounded-lg border border-white/20 bg-white/10 px-2 py-1">Qty: <span className="font-semibold text-white">{folder.totalQty}</span></div>
                        <div className="rounded-lg border border-white/20 bg-white/10 px-2 py-1">Alerts: <span className="font-semibold text-white">{folder.lowStockCount}</span></div>
                      </div>
                    </div>
                  </div>
                </button>
              ))}
            </div>
          )}
        </div>
      )}

      <ProductFormModal
        isOpen={showModal}
        onClose={() => setShowModal(false)}
        onSuccess={onModalSuccess}
        editingProduct={editingProduct}
        initialCategory={initialCategory}
        allCategories={allCategories}
        existingProducts={products}
      />

      {viewerImages.length > 0 && (
        <div className="fixed inset-0 z-[60] flex items-center justify-center bg-black/85 p-4 backdrop-blur-md">
          <div className="w-full max-w-5xl rounded-3xl border border-white/10 bg-[#0f1117] p-4 shadow-2xl">
            <div className="mb-3 flex items-center justify-between">
              <div className="text-sm text-gray-300">Photo {viewerIndex + 1} / {viewerImages.length}</div>
              <div className="flex items-center gap-2">
                <button onClick={() => { setViewerImages([]); setViewerIndex(0); }} className="rounded-xl border border-white/10 bg-white/5 px-4 py-2 text-xs font-semibold text-white hover:bg-white/10 uppercase tracking-widest transition-all">Close</button>
              </div>
            </div>
            <div className="relative h-[70vh] overflow-hidden rounded-2xl bg-black/40">
              <NextImage src={viewerImages[viewerIndex]} alt="Full size" fill className="object-contain" sizes="90vw" />
              {viewerImages.length > 1 && (
                <>
                  <button onClick={() => setViewerIndex(prev => (prev - 1 + viewerImages.length) % viewerImages.length)} className="absolute left-4 top-1/2 -translate-y-1/2 rounded-full bg-black/50 p-3 text-white hover:bg-black/80 transition-all text-2xl">‹</button>
                  <button onClick={() => setViewerIndex(prev => (prev + 1) % viewerImages.length)} className="absolute right-4 top-1/2 -translate-y-1/2 rounded-full bg-black/50 p-3 text-white hover:bg-black/80 transition-all text-2xl">›</button>
                </>
              )}
            </div>
          </div>
        </div>
      )}

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
    </div>
  );
}
