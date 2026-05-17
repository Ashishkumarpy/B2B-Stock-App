// lib/productService.ts — client-side Supabase helpers
import { supabase } from './supabase';

export interface Product {
  id: string;
  name: string;
  code: string;
  category: string;
  quantity: number;
  threshold: number;   // used as MOQ on client
  supplierId: string;
  price: number;
  costPrice?: number;
  imageUrl?: string;
  imagePath?: string;
  images?: Array<{ url: string; path: string }>;
  unit?: string;
  stockStatus: 'in_stock' | 'low_stock' | 'out_of_stock';
  updatedAt: string;
  createdAt: string;
  description?: string;
}

const TABLE = 'products';

type RawProduct = {
  id: string;
  name: string;
  code: string;
  category: string;
  quantity: number | string | null;
  threshold: number | string | null;
  supplier_id: string | null;
  price: number | string;
  cost_price: number | string | null;
  image_url: string | null;
  image_path?: string | null;
  images: unknown;
  unit: string | null;
  stock_status: 'in_stock' | 'low_stock' | 'out_of_stock' | null;
  updated_at: string | null;
  created_at: string | null;
  description: string | null;
};

function toNumber(value: unknown): number {
  if (typeof value === 'number') return value;
  if (typeof value === 'string') {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : 0;
  }
  return 0;
}

function normalizeImages(images: unknown): Array<{ url: string; path: string }> | undefined {
  // `images` comes from a JSONB column; it may be `null`, `[]`, or an array of objects.
  if (!Array.isArray(images)) return undefined;
  const normalized = images
    .map((img) => {
      if (!img || typeof img !== 'object') return null;
      const record = img as Record<string, unknown>;
      const url = typeof record.url === 'string' ? record.url : undefined;
      const publicId = typeof record.publicId === 'string' ? record.publicId : undefined;
      const path = typeof record.path === 'string' ? record.path : publicId;
      if (!url) return null;
      return { url, path: path ?? '' };
    })
    .filter(Boolean) as Array<{ url: string; path: string }>;

  return normalized.length > 0 ? normalized : undefined;
}

function normalizeProduct(raw: RawProduct): Product {
  // Supabase returns snake_case column names; the client UI expects camelCase.
  return {
    id: raw.id,
    name: raw.name,
    code: raw.code,
    category: raw.category,
    quantity: toNumber(raw.quantity),
    threshold: toNumber(raw.threshold),
    supplierId: raw.supplier_id ?? '',
    price: toNumber(raw.price),
    costPrice: raw.cost_price == null ? undefined : toNumber(raw.cost_price),
    imageUrl: raw.image_url ?? undefined,
    imagePath: (raw as { image_path?: string | null }).image_path ?? undefined,
    images: normalizeImages(raw.images),
    unit: raw.unit ?? undefined,
    stockStatus: raw.stock_status ?? 'out_of_stock',
    updatedAt: raw.updated_at ?? '',
    createdAt: raw.created_at ?? '',
    description: raw.description ?? undefined,
  };
}

function buildCategoryCandidates(input: string): string[] {
  const trimmed = input.trim();
  if (!trimmed) return [];

  const unslugified = trimmed.replace(/[-_]+/g, ' ').replace(/\s+/g, ' ').trim();

  const titleCased = unslugified
    .split(' ')
    .filter(Boolean)
    .map((w) => w.charAt(0).toUpperCase() + w.slice(1))
    .join(' ');

  return Array.from(new Set([trimmed, trimmed.toLowerCase(), unslugified, titleCased]));
}

/** Fetch all products once */
export async function getProducts(): Promise<Product[]> {
  const { data, error } = await supabase
    .from(TABLE)
    .select('*')
    .order('created_at', { ascending: false });
  
  if (error) {
    console.error('Error fetching products:', error);
    return [];
  }
  return (data as RawProduct[]).map(normalizeProduct);
}

/** Fetch a single product by ID */
export async function getProduct(id: string): Promise<Product | null> {
  const { data, error } = await supabase
    .from(TABLE)
    .select('*')
    .eq('id', id)
    .single();
    
  if (error || !data) return null;
  return normalizeProduct(data as RawProduct);
}

/** Fetch products filtered by category (once) */
export async function getProductsByCategory(category: string): Promise<Product[]> {
  const candidates = buildCategoryCandidates(category);
  if (candidates.length === 0) return [];

  // Try exact matches first (fast, index-friendly).
  for (const candidate of candidates) {
    const { data, error } = await supabase
      .from(TABLE)
      .select('*')
      .eq('category', candidate)
      .order('created_at', { ascending: false });

    if (error) {
      console.error('Error fetching products by category:', error);
      return [];
    }
    if (data && data.length > 0) return (data as RawProduct[]).map(normalizeProduct);
  }

  // Fallback: case-insensitive exact match.
  for (const candidate of candidates) {
    const { data, error } = await supabase
      .from(TABLE)
      .select('*')
      .ilike('category', candidate)
      .order('created_at', { ascending: false });

    if (error) {
      console.error('Error fetching products by category:', error);
      return [];
    }
    if (data && data.length > 0) return (data as RawProduct[]).map(normalizeProduct);
  }

  return [];
}

/** Real-time listener for all products */
export function subscribeToProducts(callback: (products: Product[]) => void): () => void {
  // Initial fetch
  getProducts().then(callback);

  // IMPORTANT:
  // Supabase Realtime channels are keyed by name; reusing the same name across multiple
  // React mounts (or StrictMode double-mount in dev) can cause:
  // "cannot add `postgres_changes` callbacks ... after `subscribe()`"
  // because the SDK may return an already-subscribed channel instance.
  const channelName = `products:${Date.now()}:${Math.random().toString(16).slice(2)}`;
  const channel = supabase
    .channel(channelName)
    .on('postgres_changes', { event: '*', schema: 'public', table: TABLE }, () => {
      // Re-fetch all products on any change
      getProducts().then(callback);
    })
    .subscribe();

  return () => {
    // Prefer direct unsubscribe; fallback to removeChannel for older SDK behavior.
    // eslint-disable-next-line @typescript-eslint/no-floating-promises
    channel.unsubscribe?.();
    // eslint-disable-next-line @typescript-eslint/no-floating-promises
    supabase.removeChannel(channel);
  };
}
