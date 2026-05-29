'use client';

import NextImage from 'next/image';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useParams, useRouter } from 'next/navigation';
import { serverGet, serverPut, serverUploadImage, ServerApiError } from '../../../../lib/server_api';
import { useRequireAuth } from '../../../../lib/use_require_auth';

type StockStatus = 'in_stock' | 'low_stock' | 'out_of_stock';

interface ImageAsset {
  url: string;
  publicId: string;
}

interface Product {
  id: string;
  name: string;
  code: string;
  category: string;
  quantity: number;
  threshold: number;
  price: number;
  image_url?: string;
  images?: Array<ImageAsset | string>;
  description?: string;
  color_stocks?: Array<{ color: string; quantity: number }>;
}

interface ColorStockDraft {
  id: string;
  color: string;
  quantity: number;
}

interface ProductsResponse {
  data?: Product[];
}

const EMPTY_FORM = {
  name: '',
  code: '',
  category: '',
  quantity: 0,
  threshold: 50,
  price: 0,
  description: '',
};

function deriveStatus(qty: number, threshold: number): StockStatus {
  if (qty <= 0) return 'out_of_stock';
  if (qty <= threshold) return 'low_stock';
  return 'in_stock';
}

function makeDraftId() {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
    return crypto.randomUUID();
  }
  return `${Date.now()}-${Math.random().toString(36).slice(2, 10)}`;
}

function normalizeImages(product: Product): ImageAsset[] {
  const urls = new Set<string>();
  if (product.image_url && product.image_url.trim()) urls.add(product.image_url.trim());
  for (const item of product.images ?? []) {
    if (typeof item === 'string') {
      const value = item.trim();
      if (value) urls.add(value);
      continue;
    }
    const value = item?.url?.trim();
    if (value) urls.add(value);
  }
  return Array.from(urls).map((url) => ({ url, publicId: '' }));
}

function convertToJpeg(file: File): Promise<File> {
  return new Promise((resolve, reject) => {
    const img = new Image();
    const objectUrl = URL.createObjectURL(file);
    const maxEdge = 1920;
    const quality = 0.85;
    const isPng = file.type.toLowerCase() === 'image/png' || file.name.toLowerCase().endsWith('.png');

    img.onload = () => {
      const scale = Math.min(1, maxEdge / Math.max(img.naturalWidth, img.naturalHeight));
      const targetWidth = Math.max(1, Math.round(img.naturalWidth * scale));
      const targetHeight = Math.max(1, Math.round(img.naturalHeight * scale));
      const canvas = document.createElement('canvas');
      canvas.width = targetWidth;
      canvas.height = targetHeight;
      const ctx = canvas.getContext('2d');
      if (!ctx) {
        reject(new Error('Canvas not supported'));
        return;
      }
      if (isPng) {
        ctx.fillStyle = '#ffffff';
        ctx.fillRect(0, 0, targetWidth, targetHeight);
      }
      ctx.drawImage(img, 0, 0, targetWidth, targetHeight);
      canvas.toBlob(
        (blob) => {
          URL.revokeObjectURL(objectUrl);
          if (!blob) {
            reject(new Error('Canvas conversion failed'));
            return;
          }
          const baseName = file.name.replace(/\.[^.]+$/, '');
          resolve(new File([blob], `${baseName}.jpg`, { type: 'image/jpeg' }));
        },
        'image/jpeg',
        quality
      );
    };

    img.onerror = () => {
      URL.revokeObjectURL(objectUrl);
      reject(new Error(`Cannot decode image: ${file.name}`));
    };

    img.src = objectUrl;
  });
}

export default function EditProductPage() {
  useRequireAuth();
  const router = useRouter();
  const params = useParams<{ productId: string }>();
  const productId = String(params?.productId ?? '');

  const [form, setForm] = useState(EMPTY_FORM);
  const [images, setImages] = useState<ImageAsset[]>([]);
  const [colorStocks, setColorStocks] = useState<ColorStockDraft[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [uploading, setUploading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [uploadError, setUploadError] = useState<string | null>(null);
  const [syncQuantityFromColors, setSyncQuantityFromColors] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const res = (await serverGet('/products')) as ProductsResponse;
      const product = (res.data ?? []).find((item) => item.id === productId);
      if (!product) {
        setError('Product not found.');
        return;
      }
      setForm({
        name: product.name,
        code: product.code,
        category: product.category,
        quantity: product.quantity,
        threshold: product.threshold,
        price: product.price,
        description: product.description ?? '',
      });
      setImages(normalizeImages(product));
      setColorStocks(
        (product.color_stocks ?? [])
          .map((entry) => ({
            id: makeDraftId(),
            color: String(entry.color ?? '').trim(),
            quantity: Number(entry.quantity ?? 0),
          }))
          .filter((entry) => entry.color.length > 0)
      );
      setSyncQuantityFromColors((product.color_stocks ?? []).length > 0);
    } catch (e) {
      if (e instanceof ServerApiError && e.status === 401) {
        router.push('/login');
        return;
      }
      setError(e instanceof Error ? e.message : 'Failed to load product.');
    } finally {
      setLoading(false);
    }
  }, [productId, router]);

  useEffect(() => {
    const timer = window.setTimeout(() => {
      void load();
    }, 0);
    return () => window.clearTimeout(timer);
  }, [load]);

  const setMainImage = (index: number) => {
    setImages((prev) => {
      if (index <= 0 || index >= prev.length) return prev;
      const next = [...prev];
      const [selected] = next.splice(index, 1);
      next.unshift(selected);
      return next;
    });
  };

  const removeImage = (index: number) => {
    setImages((prev) => prev.filter((_, i) => i !== index));
  };

  const addColorStock = () => {
    setColorStocks((prev) => [...prev, { id: makeDraftId(), color: '', quantity: 0 }]);
  };

  const updateColorStock = (
    index: number,
    patch: Partial<{ color: string; quantity: number }>
  ) => {
    setColorStocks((prev) =>
      prev.map((entry, idx) =>
        idx === index
          ? {
              ...entry,
              color: patch.color ?? entry.color,
              quantity: patch.quantity ?? entry.quantity,
            }
          : entry
      )
    );
  };

  const removeColorStock = (index: number) => {
    setColorStocks((prev) => prev.filter((_, idx) => idx !== index));
  };

  const colorTotalQuantity = useMemo(
    () =>
      colorStocks.reduce((sum, entry) => {
        const qty = Number.isFinite(entry.quantity) ? Math.max(0, Math.trunc(entry.quantity)) : 0;
        return sum + qty;
      }, 0),
    [colorStocks]
  );
  const manualQuantity = Number.isFinite(Number(form.quantity))
    ? Math.max(0, Math.trunc(Number(form.quantity)))
    : 0;
  const hasColorMismatch =
    !syncQuantityFromColors && colorStocks.length > 0 && manualQuantity !== colorTotalQuantity;

  const handleFileChange = async (event: React.ChangeEvent<HTMLInputElement>) => {
    const files = Array.from(event.target.files ?? []);
    if (files.length === 0) return;
    if (fileInputRef.current) fileInputRef.current.value = '';
    setUploadError(null);
    setUploading(true);
    try {
      for (const rawFile of files) {
        let fileToUpload: File;
        try {
          fileToUpload = await convertToJpeg(rawFile);
        } catch {
          fileToUpload = rawFile;
        }
        const asset = await serverUploadImage(fileToUpload);
        setImages((prev) => [...prev, { url: asset.url, publicId: asset.publicId ?? '' }]);
      }
    } catch (e) {
      setUploadError(e instanceof Error ? e.message : 'Upload failed.');
    } finally {
      setUploading(false);
    }
  };

  const handleSave = async (event: React.FormEvent) => {
    event.preventDefault();
    if (saving || uploading) return;
    setSaving(true);
    setError(null);
    try {
      const finalQuantity = syncQuantityFromColors
        ? colorTotalQuantity
        : Number(form.quantity);
      const stockStatus = deriveStatus(finalQuantity, Number(form.threshold));
      const finalImages = [...images];
      const finalColorStocks = colorStocks
        .map((entry) => ({
          color: entry.color.trim(),
          quantity: Number.isFinite(entry.quantity) ? Math.max(0, Math.trunc(entry.quantity)) : 0,
        }))
        .filter((entry) => entry.color.length > 0);
      const payload = {
        name: form.name.trim(),
        code: form.code.trim(),
        category: form.category.trim(),
        quantity: finalQuantity,
        threshold: Number(form.threshold),
        price: Number(form.price),
        description: form.description.trim(),
        images: finalImages,
        image_url: finalImages.length > 0 ? finalImages[0].url : null,
        color_stocks: finalColorStocks,
        stock_status: stockStatus,
        updated_at: new Date().toISOString(),
      };
      await serverPut(`/products/${productId}`, payload);
      router.push(`/products/${encodeURIComponent(productId)}`);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to save product.');
    } finally {
      setSaving(false);
    }
  };

  const goBackToFolder = () => {
    const category = form.category.trim();
    if (category) {
      router.push(`/products/folder?name=${encodeURIComponent(category)}`);
      return;
    }
    router.push('/products/folder');
  };

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between gap-3">
        <div>
          <h1 className="text-2xl font-bold">Edit Product</h1>
          <p className="mt-1 text-sm text-slate-400 dark:text-gray-500">Editing stays in product details flow</p>
        </div>
        <button
          type="button"
          onClick={goBackToFolder}
          className="rounded-xl border border-slate-200 dark:border-white/10 px-4 py-2 text-sm text-slate-700 dark:text-gray-200 hover:bg-slate-100 dark:hover:bg-white/5"
        >
          Back to Folder
        </button>
      </div>

      <div className="card max-w-4xl p-6 md:p-8">
        {loading ? (
          <div className="p-8 text-center text-sm text-slate-400 dark:text-gray-500">Loading product...</div>
        ) : (
          <form onSubmit={handleSave} className="space-y-6">
            <div>
              <label className="mb-2 block text-xs font-semibold uppercase tracking-wider text-slate-500 dark:text-gray-400">Product Gallery</label>
              <div className="mb-3 grid grid-cols-3 gap-3 sm:grid-cols-5">
                {images.map((image, idx) => (
                  <div key={`${image.url}-${idx}`} className="group relative aspect-square overflow-hidden rounded-lg border border-slate-200 dark:border-white/10">
                    <NextImage src={image.url} alt={`Product image ${idx + 1}`} fill className="object-cover" sizes="120px" />
                    {idx === 0 ? (
                      <span className="absolute left-1 top-1 rounded bg-indigo-600 px-1 text-[8px] font-bold uppercase text-white">Main</span>
                    ) : (
                      <button
                        type="button"
                        onClick={() => setMainImage(idx)}
                        className="absolute left-1 top-1 rounded bg-indigo-600/85 px-1.5 py-0.5 text-[10px] font-semibold text-white"
                      >
                        Set Main
                      </button>
                    )}
                    <button
                      type="button"
                      onClick={() => removeImage(idx)}
                      className="absolute bottom-1 right-1 rounded bg-red-500/85 px-2 py-1 text-[10px] font-semibold text-white opacity-0 transition-opacity group-hover:opacity-100"
                    >
                      Remove
                    </button>
                  </div>
                ))}
                <button
                  type="button"
                  onClick={() => fileInputRef.current?.click()}
                  className="aspect-square rounded-lg border-2 border-dashed border-slate-200 dark:border-white/10 text-slate-400 dark:text-gray-500 transition hover:border-indigo-500/40 hover:text-indigo-300"
                >
                  <div className="flex h-full flex-col items-center justify-center gap-1">
                    <span className="text-xl">+</span>
                    <span className="text-[10px] uppercase">Add</span>
                  </div>
                </button>
              </div>
              <input ref={fileInputRef} type="file" multiple accept="image/*" className="hidden" onChange={handleFileChange} />
              {uploading && <p className="text-xs text-indigo-300">Uploading image(s)...</p>}
              {uploadError && <p className="text-xs text-red-300">{uploadError}</p>}
            </div>

            <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
              <label className="block">
                <span className="mb-1.5 block text-xs font-semibold uppercase tracking-wider text-slate-500 dark:text-gray-400">Product Name *</span>
                <input
                  type="text"
                  required
                  value={form.name}
                  onChange={(e) => setForm((prev) => ({ ...prev, name: e.target.value }))}
                  className="w-full rounded-lg border border-slate-200 dark:border-white/10 bg-slate-100 dark:bg-white/5 px-3 py-2.5 text-sm text-white focus:border-indigo-500 focus:outline-none"
                />
              </label>
              <label className="block">
                <span className="mb-1.5 block text-xs font-semibold uppercase tracking-wider text-slate-500 dark:text-gray-400">Product Code *</span>
                <input
                  type="text"
                  required
                  value={form.code}
                  onChange={(e) => setForm((prev) => ({ ...prev, code: e.target.value }))}
                  className="w-full rounded-lg border border-slate-200 dark:border-white/10 bg-slate-100 dark:bg-white/5 px-3 py-2.5 text-sm text-white focus:border-indigo-500 focus:outline-none"
                />
              </label>
              <label className="block">
                <span className="mb-1.5 block text-xs font-semibold uppercase tracking-wider text-slate-500 dark:text-gray-400">Category *</span>
                <input
                  type="text"
                  required
                  value={form.category}
                  onChange={(e) => setForm((prev) => ({ ...prev, category: e.target.value }))}
                  className="w-full rounded-lg border border-slate-200 dark:border-white/10 bg-slate-100 dark:bg-white/5 px-3 py-2.5 text-sm text-white focus:border-indigo-500 focus:outline-none"
                />
              </label>
              <label className="block">
                <span className="mb-1.5 block text-xs font-semibold uppercase tracking-wider text-slate-500 dark:text-gray-400">Price (Rs) *</span>
                <input
                  type="number"
                  required
                  min="0"
                  value={form.price}
                  onChange={(e) => setForm((prev) => ({ ...prev, price: Number(e.target.value) }))}
                  className="w-full rounded-lg border border-slate-200 dark:border-white/10 bg-slate-100 dark:bg-white/5 px-3 py-2.5 text-sm text-white focus:border-indigo-500 focus:outline-none"
                />
              </label>
              <label className="block">
                <span className="mb-1.5 block text-xs font-semibold uppercase tracking-wider text-slate-500 dark:text-gray-400">Stock Quantity *</span>
                <input
                  type="number"
                  required
                  min="0"
                  value={syncQuantityFromColors ? colorTotalQuantity : form.quantity}
                  disabled={syncQuantityFromColors}
                  onChange={(e) => setForm((prev) => ({ ...prev, quantity: Number(e.target.value) }))}
                  className="w-full rounded-lg border border-slate-200 dark:border-white/10 bg-slate-100 dark:bg-white/5 px-3 py-2.5 text-sm text-white focus:border-indigo-500 focus:outline-none"
                />
                {hasColorMismatch && (
                  <p className="mt-1 text-xs text-amber-300">
                    Manual quantity ({manualQuantity}) and color total ({colorTotalQuantity}) do not match.
                  </p>
                )}
              </label>
              <label className="block">
                <span className="mb-1.5 block text-xs font-semibold uppercase tracking-wider text-slate-500 dark:text-gray-400">MOQ / Threshold *</span>
                <input
                  type="number"
                  required
                  min="1"
                  value={form.threshold}
                  onChange={(e) => setForm((prev) => ({ ...prev, threshold: Number(e.target.value) }))}
                  className="w-full rounded-lg border border-slate-200 dark:border-white/10 bg-slate-100 dark:bg-white/5 px-3 py-2.5 text-sm text-white focus:border-indigo-500 focus:outline-none"
                />
              </label>
            </div>

            <div className="space-y-3 rounded-xl border border-slate-200 dark:border-white/10 bg-slate-50 dark:bg-white/[0.02] p-4">
              <div className="flex items-center justify-between">
                <label className="block text-xs font-semibold uppercase tracking-wider text-slate-500 dark:text-gray-400">
                  Color Stocks
                </label>
                <button
                  type="button"
                  onClick={addColorStock}
                  className="rounded-lg border border-indigo-200 dark:border-indigo-500/30 bg-indigo-50 dark:bg-indigo-600/20 px-3 py-1 text-xs font-semibold text-indigo-600 dark:text-indigo-200 hover:bg-indigo-100 dark:hover:bg-indigo-600/30 transition-all"
                >
                  + Add Color
                </button>
              </div>
              {colorStocks.length === 0 ? (
                <p className="text-xs text-slate-400 dark:text-gray-500">No colors added. Use Add Color to create color-wise quantities.</p>
              ) : (
                <div className="space-y-2">
                  {colorStocks.map((entry, index) => (
                    <div key={entry.id || `color-row-${index}`} className="grid grid-cols-[1fr_130px_80px] gap-2">
                      <input
                        type="text"
                        value={entry.color}
                        onChange={(e) => updateColorStock(index, { color: e.target.value })}
                        placeholder="Color name"
                        className="rounded-lg border border-slate-200 dark:border-white/10 bg-slate-100 dark:bg-white/5 px-3 py-2 text-sm text-white focus:border-indigo-500 focus:outline-none"
                      />
                      <input
                        type="number"
                        min="0"
                        value={entry.quantity}
                        onChange={(e) =>
                          updateColorStock(index, {
                            quantity: Number(e.target.value),
                          })
                        }
                        className="rounded-lg border border-slate-200 dark:border-white/10 bg-slate-100 dark:bg-white/5 px-3 py-2 text-sm text-white focus:border-indigo-500 focus:outline-none"
                      />
                      <button
                        type="button"
                        onClick={() => removeColorStock(index)}
                        className="rounded-lg border border-red-200 dark:border-red-500/40 bg-red-50 dark:bg-red-500/20 px-3 py-2 text-xs font-semibold text-red-600 dark:text-red-200 hover:bg-red-100 dark:hover:bg-red-500/30 transition-all"
                      >
                        Remove
                      </button>
                    </div>
                  ))}
                </div>
              )}
              <label className="mt-2 flex items-center gap-2 text-xs text-slate-600 dark:text-gray-300">
                <input
                  type="checkbox"
                  checked={syncQuantityFromColors}
                  onChange={(e) => setSyncQuantityFromColors(e.target.checked)}
                />
                Auto-sync total quantity from color stocks ({colorTotalQuantity} pcs)
              </label>
            </div>

            <label className="block">
              <span className="mb-1.5 block text-xs font-semibold uppercase tracking-wider text-slate-500 dark:text-gray-400">Description</span>
              <textarea
                rows={3}
                value={form.description}
                onChange={(e) => setForm((prev) => ({ ...prev, description: e.target.value }))}
                className="w-full resize-none rounded-lg border border-slate-200 dark:border-white/10 bg-slate-100 dark:bg-white/5 px-3 py-2.5 text-sm text-white focus:border-indigo-500 focus:outline-none"
              />
            </label>

            {error && <div className="rounded-xl border border-red-500/20 bg-red-500/10 px-4 py-2 text-sm text-red-300">{error}</div>}

            <div className="flex gap-3">
              <button
                type="submit"
                disabled={saving || uploading}
                className="rounded-xl bg-indigo-600 px-5 py-2.5 text-sm font-semibold text-white hover:bg-indigo-500 disabled:opacity-60"
              >
                {saving ? 'Saving...' : 'Save Changes'}
              </button>
              <button
                type="button"
                onClick={() => router.push(`/products/${encodeURIComponent(productId)}`)}
                className="rounded-xl border border-slate-200 dark:border-white/10 px-5 py-2.5 text-sm text-slate-700 dark:text-gray-200 hover:bg-slate-100 dark:hover:bg-white/5"
              >
                Back to Details
              </button>
            </div>
          </form>
        )}
      </div>
    </div>
  );
}
