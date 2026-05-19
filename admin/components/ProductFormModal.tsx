'use client';

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import NextImage from 'next/image';
import { serverDelete, serverPost, serverPut, serverUploadImage } from '../lib/server_api';

export type StockStatus = 'in_stock' | 'low_stock' | 'out_of_stock';

export interface ImageAsset {
  url: string;
  publicId: string;
}

export interface ColorStock {
  color: string;
  quantity: number;
}

export interface Product {
  id: string;
  name: string;
  code: string;
  category: string;
  quantity: number;
  threshold: number;
  price: number;
  pcs_per_carton?: number;
  image_url?: string;
  images?: ImageAsset[];
  description?: string;
  stock_status: StockStatus;
  color_stocks?: ColorStock[];
  created_at?: string;
  updated_at?: string;
}

interface PendingUpload {
  id: string;
  name: string;
  progress: number;
  status: 'uploading' | 'failed';
}

interface ProductFormModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSuccess: (product: Product) => void;
  editingProduct?: Product | null;
  initialCategory?: string;
  allCategories?: string[];
  existingProducts?: Product[];
}

const EMPTY_FORM = {
  name: '',
  code: '',
  category: '',
  quantity: 0,
  threshold: 50,
  price: 0,
  pcs_per_carton: 1,
  description: '',
};

function deriveStatus(qty: number, threshold: number): StockStatus {
  if (qty <= 0) return 'out_of_stock';
  if (qty <= threshold) return 'low_stock';
  return 'in_stock';
}

function makeDraftId() {
  return `${Date.now()}-${Math.random().toString(36).slice(2, 10)}`;
}

/** Convert any browser-renderable image to a JPEG File. */
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
      if (!ctx) { reject(new Error('Canvas not supported')); return; }
      if (isPng) {
        ctx.fillStyle = '#ffffff';
        ctx.fillRect(0, 0, targetWidth, targetHeight);
      }
      ctx.drawImage(img, 0, 0, targetWidth, targetHeight);
      canvas.toBlob(
        (blob) => {
          URL.revokeObjectURL(objectUrl);
          if (!blob) { reject(new Error('Canvas conversion failed')); return; }
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

export default function ProductFormModal({
  isOpen,
  onClose,
  onSuccess,
  editingProduct,
  initialCategory,
  allCategories = [],
  existingProducts = [],
}: ProductFormModalProps) {
  const [form, setForm] = useState(EMPTY_FORM);
  const [images, setImages] = useState<ImageAsset[]>([]);
  const [colorStocks, setColorStocks] = useState<Array<ColorStock & { id: string }>>([]);
  const [syncQuantityFromColors, setSyncQuantityFromColors] = useState(false);
  const [saving, setSaving] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);
  const [uploading, setUploading] = useState(false);
  const [uploadProgress, setUploadProgress] = useState(0);
  const [uploadError, setUploadError] = useState<string | null>(null);
  const [pendingUploads, setPendingUploads] = useState<PendingUpload[]>([]);
  const fileInputRef = useRef<HTMLInputElement>(null);

  // Initialize form when editingProduct or initialCategory changes
  useEffect(() => {
    if (editingProduct) {
      setForm({
        name: editingProduct.name,
        code: editingProduct.code,
        category: editingProduct.category,
        quantity: editingProduct.quantity,
        threshold: editingProduct.threshold,
        price: editingProduct.price,
        pcs_per_carton: editingProduct.pcs_per_carton || 1,
        description: editingProduct.description || '',
      });
      setImages(editingProduct.images ?? (editingProduct.image_url ? [{ url: editingProduct.image_url, publicId: '' }] : []));
      const colors = (editingProduct.color_stocks ?? []).map(c => ({ ...c, id: makeDraftId() }));
      setColorStocks(colors);
      setSyncQuantityFromColors(colors.length > 0);
    } else {
      setForm({ ...EMPTY_FORM, category: initialCategory || '' });
      setImages([]);
      setColorStocks([]);
      setSyncQuantityFromColors(false);
    }
    setSaveError(null);
    setUploadError(null);
    setPendingUploads([]);
  }, [editingProduct, initialCategory, isOpen]);

  const colorTotalQuantity = useMemo(
    () => colorStocks.reduce((sum, entry) => sum + Math.max(0, entry.quantity), 0),
    [colorStocks]
  );

  const handleFileChange = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const files = Array.from(e.target.files || []);
    if (files.length === 0) return;
    if (fileInputRef.current) fileInputRef.current.value = '';

    setUploading(true);
    setUploadError(null);

    const uploadIds = files.map((file, index) => `${Date.now()}-${index}-${file.name}`);
    setPendingUploads((prev) => [
      ...prev,
      ...files.map((file, index) => ({
        id: uploadIds[index],
        name: file.name,
        progress: 0,
        status: 'uploading' as const,
      })),
    ]);

    try {
      for (let i = 0; i < files.length; i++) {
        const rawFile = files[i];
        const uploadId = uploadIds[i];

        let fileToUpload: File;
        try {
          fileToUpload = await convertToJpeg(rawFile);
        } catch {
          fileToUpload = rawFile;
        }

        const asset = await serverUploadImage(fileToUpload);

        setPendingUploads((prev) =>
          prev.map((upload) => (upload.id === uploadId ? { ...upload, progress: 100 } : upload))
        );
        setUploadProgress(Math.round(((i + 1) / files.length) * 100));

        setImages((prev) => [...prev, { url: asset.url, publicId: asset.publicId ?? '' }]);
        setPendingUploads((prev) => prev.filter((upload) => upload.id !== uploadId));
      }
      setUploadProgress(100);
    } catch (err) {
      console.error(err);
      setUploadError(err instanceof Error ? err.message : 'Image upload failed.');
      setPendingUploads((prev) =>
        prev.map((upload) =>
          upload.status === 'uploading' ? { ...upload, status: 'failed', progress: 0 } : upload
        )
      );
    } finally {
      setUploading(false);
      setTimeout(() => setUploadProgress(0), 400);
    }
  };

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    setSaving(true);
    setSaveError(null);

    try {
      // Validate duplicate product code
      const enteredCode = form.code.trim().toLowerCase();
      const isDuplicate = existingProducts.some(p => 
        p.code.trim().toLowerCase() === enteredCode && 
        p.id !== editingProduct?.id
      );
      if (isDuplicate) {
        setSaveError("This Product Code is already taken.");
        setSaving(false);
        return;
      }

      const finalQuantity = syncQuantityFromColors ? colorTotalQuantity : Number(form.quantity);
      const stockStatus = deriveStatus(finalQuantity, Number(form.threshold));
      const finalImages = [...images];
      const finalColorStocks = colorStocks
        .map(({ color, quantity }) => ({ color: color.trim(), quantity: Math.max(0, quantity) }))
        .filter(c => c.color.length > 0);

      const payload = {
        name: form.name.trim(),
        code: form.code.trim(),
        category: form.category.trim(),
        quantity: finalQuantity,
        threshold: Number(form.threshold),
        price: Number(form.price),
        pcs_per_carton: Number(form.pcs_per_carton) || 1,
        description: form.description.trim(),
        images: finalImages,
        image_url: finalImages.length > 0 ? finalImages[0].url : null,
        color_stocks: finalColorStocks,
        stock_status: stockStatus,
        updated_at: new Date().toISOString(),
      };

      let result: Product;
      if (editingProduct) {
        // Cleanup removed images from Cloudinary
        const oldIds = (editingProduct.images || []).map(img => img.publicId).filter(Boolean);
        const newIds = finalImages.map(img => img.publicId).filter(Boolean);
        const removed = oldIds.filter(id => !newIds.includes(id));
        for (const pid of removed) {
          try { await serverDelete(`/uploads/${encodeURIComponent(pid)}`); } catch (e) { console.error(e); }
        }
        result = await serverPut(`/products/${editingProduct.id}`, payload) as Product;
      } else {
        result = await serverPost('/products', { ...payload, supplier_id: null }) as Product;
      }

      onSuccess(result);
      onClose();
    } catch (err) {
      console.error(err);
      setSaveError(err instanceof Error ? err.message : 'Failed to save product.');
    } finally {
      setSaving(false);
    }
  };

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 p-4 backdrop-blur-sm">
      <div className="flex max-h-[90vh] w-full max-w-4xl flex-col overflow-hidden rounded-3xl border border-white/10 bg-[#0f1117] shadow-2xl">
        <div className="flex items-center justify-between border-b border-white/10 p-6">
          <div>
            <h2 className="text-xl font-bold">{editingProduct ? 'Edit Product' : 'Add New Product'}</h2>
            <p className="text-xs text-gray-400">Fill in the details below to {editingProduct ? 'update' : 'create'} the product.</p>
          </div>
          <button onClick={onClose} className="text-2xl text-gray-400 hover:text-white">&times;</button>
        </div>

        <form onSubmit={handleSave} className="flex-1 overflow-y-auto p-6 scrollbar-hide">
          <div className="grid grid-cols-1 gap-8 lg:grid-cols-2">
            {/* Left Column: Images */}
            <div className="space-y-4">
              <label className="block text-xs font-semibold uppercase tracking-wider text-gray-400">Product Gallery</label>
              <div className="grid grid-cols-3 gap-3 sm:grid-cols-4">
                {images.map((img, idx) => (
                  <div key={`${img.publicId || img.url}-${idx}`} className="group relative aspect-square overflow-hidden rounded-xl border border-white/10 bg-white/5">
                    <NextImage src={img.url} alt="Product" fill className="object-cover" sizes="150px" />
                    {idx === 0 && <span className="absolute left-1 top-1 rounded bg-indigo-600 px-1 text-[8px] font-bold text-white uppercase">Main</span>}
                    <button
                      type="button"
                      onClick={() => setImages(prev => prev.filter((_, i) => i !== idx))}
                      className="absolute bottom-1 right-1 rounded bg-red-500/80 px-2 py-1 text-[10px] font-semibold text-white opacity-0 group-hover:opacity-100"
                    >
                      Remove
                    </button>
                    {idx > 0 && (
                      <button
                        type="button"
                        onClick={() => {
                          const next = [...images];
                          const [selected] = next.splice(idx, 1);
                          next.unshift(selected);
                          setImages(next);
                        }}
                        className="absolute left-1 top-1 rounded bg-indigo-600/80 px-1.5 py-0.5 text-[10px] font-semibold text-white"
                      >
                        Set Main
                      </button>
                    )}
                  </div>
                ))}
                {pendingUploads.map(up => (
                  <div key={up.id} className="relative aspect-square rounded-xl border border-orange-500/20 bg-orange-500/5 flex flex-col items-center justify-center p-2 text-center text-[9px] text-orange-400">
                    <span className="truncate w-full">{up.name}</span>
                    <span>{up.status === 'failed' ? 'Failed' : `${up.progress}%`}</span>
                    <button type="button" onClick={() => setPendingUploads(p => p.filter(x => x.id !== up.id))} className="absolute inset-0 bg-red-500/80 text-white opacity-0 hover:opacity-100 flex items-center justify-center font-bold">Cancel</button>
                  </div>
                ))}
                <button
                  type="button"
                  onClick={() => fileInputRef.current?.click()}
                  className="aspect-square rounded-xl border-2 border-dashed border-white/10 flex flex-col items-center justify-center text-gray-500 hover:border-indigo-500/40 hover:text-indigo-300 transition-colors"
                >
                  <span className="text-2xl">+</span>
                  <span className="text-[10px] uppercase font-bold">Add Photo</span>
                </button>
              </div>
              <input ref={fileInputRef} type="file" multiple accept="image/*" className="hidden" onChange={handleFileChange} />

              {uploading && (
                <div className="h-1.5 w-full bg-white/5 rounded-full overflow-hidden">
                  <div className="h-full bg-indigo-500 transition-all duration-300" style={{ width: `${uploadProgress}%` }} />
                </div>
              )}
              {uploadError && <p className="text-xs text-red-400">{uploadError}</p>}

              <div className="space-y-3 rounded-2xl border border-white/10 bg-white/[0.02] p-4">
                <div className="flex items-center justify-between">
                  <label className="text-xs font-semibold uppercase tracking-wider text-gray-400">Color Stocks</label>
                  <button
                    type="button"
                    onClick={() => setColorStocks(prev => [...prev, { id: makeDraftId(), color: '', quantity: 0 }])}
                    className="rounded-lg bg-indigo-600/20 px-3 py-1 text-[10px] font-bold text-indigo-300 hover:bg-indigo-600/30 uppercase tracking-widest"
                  >
                    + Add Color
                  </button>
                </div>
                <div className="max-h-[200px] space-y-2 overflow-y-auto scrollbar-hide">
                  {colorStocks.map((entry, idx) => (
                    <div key={entry.id} className="grid grid-cols-[1fr_80px_40px] gap-2">
                      <input
                        type="text"
                        placeholder="Color"
                        value={entry.color}
                        onChange={e => setColorStocks(prev => prev.map((x, i) => i === idx ? { ...x, color: e.target.value } : x))}
                        className="rounded-lg border border-white/10 bg-white/5 px-3 py-2 text-sm text-white focus:border-indigo-500 focus:outline-none"
                      />
                      <input
                        type="number"
                        min="0"
                        value={entry.quantity}
                        onChange={e => setColorStocks(prev => prev.map((x, i) => i === idx ? { ...x, quantity: Number(e.target.value) } : x))}
                        className="rounded-lg border border-white/10 bg-white/5 px-3 py-2 text-sm text-white focus:border-indigo-500 focus:outline-none"
                      />
                      <button
                        type="button"
                        onClick={() => setColorStocks(prev => prev.filter((_, i) => i !== idx))}
                        className="flex items-center justify-center rounded-lg bg-red-500/10 text-red-400 hover:bg-red-500/20"
                      >
                        &times;
                      </button>
                    </div>
                  ))}
                </div>
                {colorStocks.length > 0 && (
                  <label className="flex items-center gap-2 text-[11px] text-gray-400 mt-2">
                    <input type="checkbox" checked={syncQuantityFromColors} onChange={e => setSyncQuantityFromColors(e.target.checked)} />
                    Auto-sync total quantity ({colorTotalQuantity} pcs)
                  </label>
                )}
              </div>
            </div>

            {/* Right Column: Fields */}
            <div className="space-y-5">
              <div className="grid grid-cols-2 gap-4">
                <label className="block">
                  <span className="mb-1.5 block text-xs font-semibold uppercase tracking-wider text-gray-400">Product Name *</span>
                  <input type="text" required value={form.name} onChange={e => setForm({ ...form, name: e.target.value })} className="w-full rounded-lg border border-white/10 bg-white/5 px-3 py-2.5 text-sm text-white focus:border-indigo-500 focus:outline-none" />
                </label>
                <label className="block">
                  <span className="mb-1.5 block text-xs font-semibold uppercase tracking-wider text-gray-400">Product Code *</span>
                  <input type="text" required value={form.code} onChange={e => setForm({ ...form, code: e.target.value })} className="w-full rounded-lg border border-white/10 bg-white/5 px-3 py-2.5 text-sm text-white focus:border-indigo-500 focus:outline-none" />
                </label>
              </div>

              <div className="grid grid-cols-2 gap-4">
                <label className="block">
                  <span className="mb-1.5 block text-xs font-semibold uppercase tracking-wider text-gray-400">
                    Category * <span className="text-[10px] text-indigo-400 font-normal lowercase">(type to create new folder)</span>
                  </span>
                  <input type="text" required list="modal-categories" value={form.category} onChange={e => setForm({ ...form, category: e.target.value })} className="w-full rounded-lg border border-white/10 bg-white/5 px-3 py-2.5 text-sm text-white focus:border-indigo-500 focus:outline-none" />
                  <datalist id="modal-categories">
                    {allCategories.map(c => <option key={c} value={c} />)}
                  </datalist>
                </label>
                <label className="block">
                  <span className="mb-1.5 block text-xs font-semibold uppercase tracking-wider text-gray-400">Price (Rs) *</span>
                  <input type="number" required min="0" value={form.price} onChange={e => setForm({ ...form, price: Number(e.target.value) })} className="w-full rounded-lg border border-white/10 bg-white/5 px-3 py-2.5 text-sm text-white focus:border-indigo-500 focus:outline-none" />
                </label>
              </div>

              <div className="grid grid-cols-2 gap-4">
                <label className="block">
                  <span className="mb-1.5 block text-xs font-semibold uppercase tracking-wider text-gray-400">Pcs per Carton *</span>
                  <input type="number" required min="1" value={form.pcs_per_carton} onChange={e => setForm({ ...form, pcs_per_carton: Number(e.target.value) })} className="w-full rounded-lg border border-white/10 bg-white/5 px-3 py-2.5 text-sm text-white focus:border-indigo-500 focus:outline-none" />
                </label>
                <label className="block">
                  <span className="mb-1.5 block text-xs font-semibold uppercase tracking-wider text-gray-400">MOQ / Threshold *</span>
                  <input type="number" required min="1" value={form.threshold} onChange={e => setForm({ ...form, threshold: Number(e.target.value) })} className="w-full rounded-lg border border-white/10 bg-white/5 px-3 py-2.5 text-sm text-white focus:border-indigo-500 focus:outline-none" />
                </label>
              </div>

              <div className="grid grid-cols-1 gap-4">
                <label className="block">
                  <span className="mb-1.5 block text-xs font-semibold uppercase tracking-wider text-gray-400">Stock Quantity *</span>
                  <input
                    type="number"
                    required
                    min="0"
                    disabled={syncQuantityFromColors}
                    value={syncQuantityFromColors ? colorTotalQuantity : form.quantity}
                    onChange={e => setForm({ ...form, quantity: Number(e.target.value) })}
                    className="w-full rounded-lg border border-white/10 bg-white/5 px-3 py-2.5 text-sm text-white focus:border-indigo-500 focus:outline-none disabled:opacity-50"
                  />
                </label>
                <label className="block">
                  <span className="mb-1.5 block text-xs font-semibold uppercase tracking-wider text-gray-400">MOQ / Threshold *</span>
                  <input type="number" required min="1" value={form.threshold} onChange={e => setForm({ ...form, threshold: Number(e.target.value) })} className="w-full rounded-lg border border-white/10 bg-white/5 px-3 py-2.5 text-sm text-white focus:border-indigo-500 focus:outline-none" />
                </label>
              </div>

              <label className="block">
                <span className="mb-1.5 block text-xs font-semibold uppercase tracking-wider text-gray-400">Description</span>
                <textarea
                  rows={4}
                  value={form.description}
                  onChange={e => setForm({ ...form, description: e.target.value })}
                  className="w-full resize-none rounded-lg border border-white/10 bg-white/5 px-3 py-2.5 text-sm text-white focus:border-indigo-500 focus:outline-none"
                />
              </label>

              {saveError && <div className="rounded-xl border border-red-500/20 bg-red-500/10 px-4 py-3 text-xs text-red-300">{saveError}</div>}
            </div>
          </div>

          <div className="mt-8 flex gap-3 border-t border-white/10 pt-6">
            <button
              type="submit"
              disabled={saving || uploading}
              className="flex-1 rounded-2xl bg-indigo-600 py-3.5 font-bold text-white hover:bg-indigo-500 disabled:opacity-50 shadow-lg shadow-indigo-500/20 transition-all active:scale-95"
            >
              {saving ? 'Saving...' : editingProduct ? 'Update Product' : 'Create Product'}
            </button>
            <button
              type="button"
              onClick={onClose}
              className="rounded-2xl border border-white/10 px-8 py-3.5 text-sm font-semibold text-gray-300 hover:bg-white/5 transition-all"
            >
              Cancel
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
