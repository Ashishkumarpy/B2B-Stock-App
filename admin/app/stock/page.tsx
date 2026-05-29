'use client';

import { useState, useEffect, useRef, useCallback, useMemo } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import { serverGet, serverPost, serverPatch, ServerApiError } from '../../lib/server_api';
import { useRequireAuth } from '../../lib/use_require_auth';
import { supabase } from '../../lib/supabase';

type TransactionType = 'stock_in' | 'stock_out';

interface Transaction {
  id: string;
  product_id: string;
  product_name: string;
  product_code: string;
  color_name?: string;
  warehouse_id?: string;
  warehouse_name?: string;
  type: TransactionType;
  quantity: number;
  worker_name: string;
  notes?: string;
  created_at: string;
  cartons?: number | null;
  pcs_per_carton?: number | null;
  worker_id?: string;
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

export function getCleanNotes(notes?: string | null): string {
  if (!notes) return '';
  let clean = notes.trim();
  
  // 1. Strip customer prefix: "Customer: <any chars till | or end>"
  const customerRegex = /^Customer:\s*[^|]+(\|)?/i;
  clean = clean.replace(customerRegex, '').trim();

  // 2. Strip cartons prefix: "\d+ ctn × \d+ pcs" or similar, case insensitively
  const cartonRegex = /^\d+\s*(?:ctn|carton|cartons)\s*(?:[x*]|\(|pcs\/ctn|pcs)?\s*\d+\s*(?:pcs)?\s*(\|)?/i;
  clean = clean.replace(cartonRegex, '').trim();

  return clean;
}

interface Product {
  id: string;
  name: string;
  code: string;
  category?: string;
  image_url?: string | null;
  images?: Array<{ url?: string | null } | string>;
  quantity: number;
  threshold: number;
  color_stocks?: Array<{ color: string; quantity: number }>;
  pcs_per_carton?: number;
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
  customer_name: '',
};

const STOCK_PREFS_STORAGE_KEY = 'stock_entry_prefs_v1';

type StockEntryPref = {
  warehouse_id?: string;
  color_name?: string;
  updated_at: number;
};

type StockEntryPrefMap = Record<string, StockEntryPref>;

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
  const [editingTransactionId, setEditingTransactionId] = useState<string | null>(null);
  
  const editingTransaction = useMemo(() => {
    if (!editingTransactionId) return null;
    return transactions.find((t) => t.id === editingTransactionId) || null;
  }, [editingTransactionId, transactions]);

  const isEditingOlderThan12Hours = useMemo(() => {
    if (!editingTransaction) return false;
    const createdAtTime = new Date(editingTransaction.created_at).getTime();
    return (Date.now() - createdAtTime) > 12 * 60 * 60 * 1000;
  }, [editingTransaction]);

  const [form, setForm] = useState(EMPTY_FORM);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [showProductPicker, setShowProductPicker] = useState(false);
  const [pickerSearch, setPickerSearch] = useState('');
  const [pickerCategory, setPickerCategory] = useState<string | null>(null);
  const prefetchedQueryRef = useRef<string | null>(null);
  const [stockPrefs, setStockPrefs] = useState<StockEntryPrefMap>({});
  const [productStockDistribution, setProductStockDistribution] = useState<any[]>([]);
  const [isLoadingStockDistribution, setIsLoadingStockDistribution] = useState(false);

  const [realtimeStatus, setRealtimeStatus] = useState<'connecting' | 'connected' | 'error'>('connecting');
  const [typeFilter, setTypeFilter] = useState<'both' | 'stock_in' | 'stock_out'>('both');
  const [dateFilter, setDateFilter] = useState<'today' | 'all' | 'custom'>('all');
  const [customDate, setCustomDate] = useState<string>(() => {
    const local = new Date();
    const offset = local.getTimezoneOffset();
    const adjusted = new Date(local.getTime() - (offset * 60 * 1000));
    return adjusted.toISOString().slice(0, 10);
  });

  const filteredTransactions = useMemo(() => {
    let result = transactions;

    // Apply Date Filter
    if (dateFilter === 'today') {
      const local = new Date();
      const offset = local.getTimezoneOffset();
      const adjusted = new Date(local.getTime() - (offset * 60 * 1000));
      const todayLocalStr = adjusted.toISOString().slice(0, 10);
      
      result = result.filter((t) => {
        const dateObj = new Date(t.created_at);
        const localTx = new Date(dateObj.getTime() - (dateObj.getTimezoneOffset() * 60 * 1000));
        const datePart = localTx.toISOString().slice(0, 10);
        return datePart === todayLocalStr;
      });
    } else if (dateFilter === 'custom') {
      result = result.filter((t) => {
        const dateObj = new Date(t.created_at);
        const localTx = new Date(dateObj.getTime() - (dateObj.getTimezoneOffset() * 60 * 1000));
        const datePart = localTx.toISOString().slice(0, 10);
        return datePart === customDate;
      });
    }

    // Apply Type Filter
    if (typeFilter === 'stock_in') {
      result = result.filter((t) => t.type === 'stock_in');
    } else if (typeFilter === 'stock_out') {
      result = result.filter((t) => t.type === 'stock_out');
    }

    return result;
  }, [transactions, dateFilter, customDate, typeFilter]);

  const [showExportModal, setShowExportModal] = useState(false);
  const [exportDate, setExportDate] = useState(() => {
    const local = new Date();
    const offset = local.getTimezoneOffset();
    const adjusted = new Date(local.getTime() - (offset * 60 * 1000));
    return adjusted.toISOString().slice(0, 10);
  });

  const exportStats = useMemo(() => {
    const targetDateStr = exportDate;
    const dayTxns = transactions.filter((t) => {
      const dateObj = new Date(t.created_at);
      const local = new Date(dateObj.getTime() - (dateObj.getTimezoneOffset() * 60 * 1000));
      return local.toISOString().slice(0, 10) === targetDateStr;
    });

    const stockInTxns = dayTxns.filter((t) => t.type === 'stock_in');
    const stockOutTxns = dayTxns.filter((t) => t.type === 'stock_out');

    const totalStockInQty = stockInTxns.reduce((sum, t) => sum + t.quantity, 0);
    const totalStockOutQty = stockOutTxns.reduce((sum, t) => sum + t.quantity, 0);

    return {
      totalInCount: stockInTxns.length,
      totalInQty: totalStockInQty,
      totalOutCount: stockOutTxns.length,
      totalOutQty: totalStockOutQty,
      totalCount: dayTxns.length,
    };
  }, [exportDate, transactions]);

  const handleExportExcel = () => {
    try {
      const targetDateStr = exportDate; // YYYY-MM-DD
      
      // Filter transactions that occurred on targetDate (local time zone)
      const dayTransactions = transactions.filter((t) => {
        const dateObj = new Date(t.created_at);
        const local = new Date(dateObj.getTime() - (dateObj.getTimezoneOffset() * 60 * 1000));
        return local.toISOString().slice(0, 10) === targetDateStr;
      });

      // Prepare In Stock (Incoming Stock In) data - only include active transactions
      const stockInAOA = products
        .map((p) => {
          const productTxns = dayTransactions.filter(t => t.product_id === p.id && t.type === 'stock_in');
          const totalQty = productTxns.reduce((sum, t) => sum + t.quantity, 0);
          const colors = Array.from(new Set(productTxns.map(t => t.color_name || 'Default'))).join(', ');
          const workers = Array.from(new Set(productTxns.map(t => t.worker_name))).join(', ');
          const notes = productTxns.map(t => t.notes).filter(Boolean).join('; ');

          return {
            code: p.code,
            name: p.name,
            category: p.category || 'Uncategorized',
            qty: totalQty,
            colors: colors || '—',
            workers: workers || '—',
            notes: notes || '—'
          };
        })
        .filter(row => row.qty > 0) // Only show products with actual stock-in movements
        .sort((a, b) => b.qty - a.qty)
        .map(row => [
          row.code,
          row.name,
          row.category,
          row.qty,
          row.colors,
          row.workers,
          row.notes
        ]);

      // Prepare Stock Out (Outgoing Stock Out) data - only include active transactions
      const stockOutAOA = products
        .map((p) => {
          const productTxns = dayTransactions.filter(t => t.product_id === p.id && t.type === 'stock_out');
          const totalQty = productTxns.reduce((sum, t) => sum + t.quantity, 0);
          const colors = Array.from(new Set(productTxns.map(t => t.color_name || 'Default'))).join(', ');
          const workers = Array.from(new Set(productTxns.map(t => t.worker_name))).join(', ');
          const notes = productTxns.map(t => t.notes).filter(Boolean).join('; ');

          return {
            code: p.code,
            name: p.name,
            category: p.category || 'Uncategorized',
            qty: totalQty,
            colors: colors || '—',
            workers: workers || '—',
            notes: notes || '—'
          };
        })
        .filter(row => row.qty > 0) // Only show products with actual stock-out movements
        .sort((a, b) => b.qty - a.qty)
        .map(row => [
          row.code,
          row.name,
          row.category,
          row.qty,
          row.colors,
          row.workers,
          row.notes
        ]);

      import('xlsx').then((XLSX) => {
        const wb = XLSX.utils.book_new();
        const wsIn = XLSX.utils.json_to_sheet([]);
        const wsOut = XLSX.utils.json_to_sheet([]);

        // Format metadata headers inside the sheet itself for professional look
        XLSX.utils.sheet_add_aoa(wsIn, [
          ["ZENTORY B2B STOCK REPORT - STOCK IN (INCOMING)"],
          [`Report Date: ${targetDateStr}`],
          [`Generated on: ${new Date().toLocaleString('en-IN')}`],
          [`Total Quantity In: ${exportStats.totalInQty} pcs (${exportStats.totalInCount} transactions)`],
          [],
          ["PRODUCT CODE", "PRODUCT NAME", "CATEGORY", "QTY IN (PCS)", "COLORS", "RECORDED BY", "NOTES"]
        ], { origin: "A1" });

        XLSX.utils.sheet_add_aoa(wsIn, stockInAOA, { origin: "A7" });

        XLSX.utils.sheet_add_aoa(wsOut, [
          ["ZENTORY B2B STOCK REPORT - STOCK OUT (OUTGOING)"],
          [`Report Date: ${targetDateStr}`],
          [`Generated on: ${new Date().toLocaleString('en-IN')}`],
          [`Total Quantity Out: ${exportStats.totalOutQty} pcs (${exportStats.totalOutCount} transactions)`],
          [],
          ["PRODUCT CODE", "PRODUCT NAME", "CATEGORY", "QTY OUT (PCS)", "COLORS", "RECORDED BY", "NOTES"]
        ], { origin: "A1" });

        XLSX.utils.sheet_add_aoa(wsOut, stockOutAOA, { origin: "A7" });

        // Autofit columns helper for AOA data
        const autofitColumns = (ws: any, rows: any[][], headers: string[]) => {
          const colWidths = headers.map(col => ({ wch: col.length }));
          
          rows.forEach(row => {
            row.forEach((val, idx) => {
              const strVal = String(val ?? '');
              if (strVal.length > (colWidths[idx]?.wch ?? 0)) {
                colWidths[idx] = { wch: strVal.length };
              }
            });
          });

          ws['!cols'] = colWidths.map(w => ({ wch: Math.min(Math.max(w.wch + 3, 10), 60) }));
        };

        const sheetHeaders = ["PRODUCT CODE", "PRODUCT NAME", "CATEGORY", "QTY (PCS)", "COLORS", "RECORDED BY", "NOTES"];
        autofitColumns(wsIn, stockInAOA, sheetHeaders);
        autofitColumns(wsOut, stockOutAOA, sheetHeaders);

        XLSX.utils.book_append_sheet(wb, wsIn, 'In stock');
        XLSX.utils.book_append_sheet(wb, wsOut, 'Stock out');

        XLSX.writeFile(wb, `zentory_stock_report_${targetDateStr}.xlsx`);
      });

      setShowExportModal(false);
    } catch (e) {
      console.error('Failed to export excel:', e);
      alert('Failed to generate Excel file.');
    }
  };

  const parseCustomerFromNotes = (notes?: string | null): string => {
    if (!notes) return '';
    const match = notes.match(/Customer:\s*([^|]+)/i);
    return match?.[1]?.trim() ?? '';
  };

  const resolveProductImageUrl = useCallback((product: Product): string | null => {
    if (product.image_url && product.image_url.trim()) return product.image_url.trim();
    for (const image of product.images ?? []) {
      if (typeof image === 'string' && image.trim()) return image.trim();
      if (typeof image === 'object' && image?.url && image.url.trim()) return image.url.trim();
    }
    return null;
  }, []);

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

  const fetchStockDistribution = useCallback(async (productId: string, autoRoute: boolean = false) => {
    setIsLoadingStockDistribution(true);
    try {
      const res = await serverGet(`/products/${encodeURIComponent(productId)}/stock-distribution`);
      const rows = ((res as any)?.data ?? []) as any[];
      setProductStockDistribution(rows);
      
      if (autoRoute && rows.length > 0) {
        const firstStockRow = rows.find((r) => parseInt(r.quantity?.toString() ?? '0', 10) > 0);
        if (firstStockRow) {
          setForm((prev) => ({
            ...prev,
            color_name: firstStockRow.color_name || 'Default',
            warehouse_id: firstStockRow.warehouse_id || prev.warehouse_id || warehouses[0]?.id || '',
          }));
        }
      }
    } catch (e) {
      console.error('Failed to fetch stock distribution:', e);
      setProductStockDistribution([]);
    } finally {
      setIsLoadingStockDistribution(false);
    }
  }, [warehouses]);

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
    if (!form.product_id || form.type !== 'stock_out') {
      setProductStockDistribution([]);
      return;
    }
    const needsRouting = !form.color_name || form.color_name === 'Default' || !form.warehouse_id;
    fetchStockDistribution(form.product_id, needsRouting);
  }, [form.product_id, form.type, fetchStockDistribution]);

  useEffect(() => {
    try {
      const raw = window.localStorage.getItem(STOCK_PREFS_STORAGE_KEY);
      if (!raw) return;
      const parsed = JSON.parse(raw) as StockEntryPrefMap;
      if (parsed && typeof parsed === 'object') {
        setStockPrefs(parsed);
      }
    } catch (e) {
      console.warn('Failed to load stock entry preferences', e);
    }
  }, []);

  useEffect(() => {
    if (products.length === 0) return;
    const urls = products
      .map((p) => resolveProductImageUrl(p))
      .filter((u): u is string => Boolean(u))
      .slice(0, 36);
    urls.forEach((url) => {
      const img = new window.Image();
      img.decoding = 'async';
      img.src = url;
    });
  }, [products, resolveProductImageUrl]);

  const productById = useMemo(() => {
    const map = new Map<string, Product>();
    for (const p of products) map.set(p.id, p);
    return map;
  }, [products]);


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
    const product = productById.get(form.product_id);
    if (!product) return;
    const productPcs = Number(product.pcs_per_carton);
 
    if (form.type === 'stock_out') {
      setForm((prev) => ({
        ...prev,
        pcsPerCarton: Number.isFinite(productPcs) && productPcs > 0 ? productPcs : 1
      }));
      return;
    }

    const firstColor = product.color_stocks?.[0]?.color || 'Default';
    const pref = stockPrefs[form.product_id];
    const preferredColor = pref?.color_name?.trim() ? pref.color_name.trim() : '';
    const preferredWarehouse = pref?.warehouse_id?.trim() ? pref.warehouse_id.trim() : '';
    const hasPreferredWarehouse = preferredWarehouse
      ? warehouses.some((w) => w.id === preferredWarehouse)
      : false;
 
    setForm((prev) => ({ 
      ...prev, 
      color_name:
        preferredColor ||
        prev.color_name ||
        firstColor,
      warehouse_id:
        hasPreferredWarehouse
          ? preferredWarehouse
          : (prev.warehouse_id || warehouses[0]?.id || ''),
      pcsPerCarton: Number.isFinite(productPcs) && productPcs > 0 ? productPcs : 1
    }));
  }, [form.product_id, form.type, productById, stockPrefs, warehouses]);

  useEffect(() => {
    const actionParam = (searchParams.get('action') ?? '').trim();
    const productId = (searchParams.get('productId') ?? '').trim();
    const typeParam = (searchParams.get('type') ?? '').trim();
    const colorParam = (searchParams.get('color') ?? '').trim();
    const warehouseIdParam = (searchParams.get('warehouseId') ?? '').trim();
    const quantityParam = Number(searchParams.get('quantity') ?? '');
    const notesParam = (searchParams.get('notes') ?? '').trim();
    const workerIdParam = (searchParams.get('workerId') ?? '').trim();
    const workerNameParam = (searchParams.get('workerName') ?? '').trim();
    const cartonsParam = Number(searchParams.get('cartons') ?? '');
    const pcsPerCartonParam = Number(searchParams.get('pcsPerCarton') ?? '');
    const customerParam = (searchParams.get('customer') ?? '').trim();
    const transactionIdParam = (searchParams.get('transactionId') ?? '').trim();
    const queryKey = `${actionParam}|${productId}|${typeParam}|${colorParam}|${warehouseIdParam}|${searchParams.get('quantity') ?? ''}|${notesParam}|${workerIdParam}|${workerNameParam}|${searchParams.get('cartons') ?? ''}|${searchParams.get('pcsPerCarton') ?? ''}|${customerParam}|${transactionIdParam}`;
    if (!productId && actionParam !== 'record') {
      prefetchedQueryRef.current = null;
      return;
    }
    if (prefetchedQueryRef.current === queryKey) return;
    if (productId && products.length === 0) return;
    const exists = productId ? products.some((p) => p.id === productId) : false;
    if (productId && !exists) return;
    const safeType: TransactionType =
      typeParam === 'stock_out' ? 'stock_out' : 'stock_in';
    const defaultWarehouse = warehouses[0]?.id ?? '';
    const nextProduct = productId ? products.find((p) => p.id === productId) : null;
    const firstColor = nextProduct?.color_stocks?.[0]?.color || 'Default';
    const safeQuantity = Number.isFinite(quantityParam) && quantityParam > 0 ? quantityParam : 0;
    const safeCartons = Number.isFinite(cartonsParam) && cartonsParam > 0 ? cartonsParam : '';
    const safePcs = Number.isFinite(pcsPerCartonParam) && pcsPerCartonParam > 0 ? pcsPerCartonParam : '';
    const resolvedCustomer = customerParam || parseCustomerFromNotes(notesParam);
    const timer = window.setTimeout(() => {
      setForm((prev) => ({
        ...prev,
        product_id: productId,
        type: safeType,
        color_name: colorParam || (productId ? firstColor : 'Default'),
        warehouse_id: warehouseIdParam || prev.warehouse_id || defaultWarehouse,
        quantity: safeQuantity,
        notes: getCleanNotes(notesParam),
        worker_id: workerIdParam || prev.worker_id,
        worker_name: workerNameParam || prev.worker_name,
        cartons: safeCartons,
        pcsPerCarton: safePcs,
        customer_name: resolvedCustomer,
      }));
      setEditingTransactionId(transactionIdParam || null);
      setShowModal(true);
      prefetchedQueryRef.current = queryKey;
      if (productId && safeType === 'stock_out') {
        fetchStockDistribution(productId, !colorParam && !warehouseIdParam);
      }
    }, 0);
    return () => window.clearTimeout(timer);
  }, [products, searchParams, warehouses, fetchStockDistribution]);

  const selectedProduct = form.product_id ? productById.get(form.product_id) : undefined;
  const availableColors = selectedProduct?.color_stocks ?? [];

  const allWarehouseIdsWithStock = useMemo(() => {
    if (form.type !== 'stock_out' || !form.product_id) return new Set<string>();
    return new Set(
      productStockDistribution
        .map((r) => r.warehouse_id?.toString() ?? '')
        .filter(Boolean)
    );
  }, [productStockDistribution, form.type, form.product_id]);

  const colorRows = useMemo(() => {
    if (form.type !== 'stock_out' || !form.product_id) return [];
    const colorQtyMap = new Map<string, { color_name: string; available_quantity: number }>();
    for (const row of productStockDistribution) {
      const colorName = (row.color_name?.toString() ?? '').trim();
      if (!colorName) continue;
      const key = colorName.toLowerCase();
      const qty = parseInt(row.quantity?.toString() ?? '0', 10);
      if (qty <= 0) continue;
      
      const existing = colorQtyMap.get(key);
      if (existing) {
        existing.available_quantity += qty;
      } else {
        colorQtyMap.set(key, { color_name: colorName, available_quantity: qty });
      }
    }
    return Array.from(colorQtyMap.values()).sort((a, b) =>
      a.color_name.toLowerCase().localeCompare(b.color_name.toLowerCase())
    );
  }, [productStockDistribution, form.type, form.product_id]);

  const colorSuggestions = useMemo(() => {
    if (form.type === 'stock_out' && form.product_id) {
      return colorRows.map((r) => r.color_name);
    }
    const fromProduct = (selectedProduct?.color_stocks ?? [])
      .map((entry) => String(entry?.color || '').trim())
      .filter(Boolean);
    const prefColor = form.product_id ? stockPrefs[form.product_id]?.color_name?.trim() : '';
    const all = prefColor ? [prefColor, ...fromProduct] : fromProduct;
    return [...new Set(all)];
  }, [form.product_id, form.type, colorRows, selectedProduct?.color_stocks, stockPrefs]);

  const selectedColorQty = useMemo(() => {
    if (!selectedProduct) return 0;
    const normalizedColor = form.color_name.trim().toLowerCase();
    if (form.type === 'stock_out' && form.warehouse_id) {
      const match = productStockDistribution.find(
        (r) =>
          r.warehouse_id?.toString() === form.warehouse_id?.toString() &&
          (r.color_name?.toString() ?? '').trim().toLowerCase() === normalizedColor
      );
      return match ? parseInt(match.quantity?.toString() ?? '0', 10) : 0;
    }
    if (!normalizedColor || normalizedColor === 'default') return selectedProduct.quantity;
    const colorRow = selectedProduct.color_stocks?.find(
      (c) => c.color.trim().toLowerCase() === normalizedColor
    );
    return colorRow?.quantity ?? 0;
  }, [selectedProduct, form.color_name, form.type, form.warehouse_id, productStockDistribution]);

  const filteredWarehouseOptions = useMemo(() => {
    if (form.type !== 'stock_out' || !form.product_id || isLoadingStockDistribution) {
      return warehouses;
    }
    return warehouses.filter((w) => allWarehouseIdsWithStock.has(w.id));
  }, [warehouses, allWarehouseIdsWithStock, form.type, form.product_id, isLoadingStockDistribution]);

  const handleWarehouseChange = (warehouseId: string) => {
    setForm((prev) => {
      let newColor = prev.color_name;
      if (prev.type === 'stock_out' && productStockDistribution.length > 0) {
        const colorsInSelectedWarehouse = new Set(
          productStockDistribution
            .filter((r) => r.warehouse_id?.toString() === warehouseId && parseInt(r.quantity?.toString() ?? '0', 10) > 0)
            .map((r) => (r.color_name?.toString() ?? '').trim().toLowerCase())
        );
        const currentColor = prev.color_name.trim().toLowerCase();
        if (!colorsInSelectedWarehouse.has(currentColor) && colorsInSelectedWarehouse.size > 0) {
          const firstStockedColor = productStockDistribution.find(
            (r) => r.warehouse_id?.toString() === warehouseId && parseInt(r.quantity?.toString() ?? '0', 10) > 0
          );
          if (firstStockedColor) {
            newColor = firstStockedColor.color_name || 'Default';
          }
        }
      }
      return { ...prev, warehouse_id: warehouseId, color_name: newColor };
    });
  };

  const handleColorChange = (colorName: string) => {
    setForm((prev) => {
      let newWarehouseId = prev.warehouse_id;
      if (prev.type === 'stock_out' && productStockDistribution.length > 0) {
        const targetColor = colorName.trim().toLowerCase();
        
        const warehousesWithColorStock = productStockDistribution
          .filter((r) => {
            const rowColor = (r.color_name?.toString() ?? '').trim().toLowerCase();
            const qty = parseInt(r.quantity?.toString() ?? '0', 10);
            return rowColor === targetColor && qty > 0;
          })
          .map((r) => r.warehouse_id?.toString() ?? '')
          .filter(Boolean);
        
        if (newWarehouseId && !warehousesWithColorStock.includes(newWarehouseId) && warehousesWithColorStock.length > 0) {
          const sorted = productStockDistribution
            .filter((r) => (r.color_name?.toString() ?? '').trim().toLowerCase() === targetColor && parseInt(r.quantity?.toString() ?? '0', 10) > 0)
            .sort((a, b) => parseInt(b.quantity?.toString() ?? '0', 10) - parseInt(a.quantity?.toString() ?? '0', 10));
          if (sorted.length > 0) {
            newWarehouseId = sorted[0].warehouse_id;
          }
        }
      }
      return { ...prev, color_name: colorName, warehouse_id: newWarehouseId };
    });
  };

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

      if (!isEditingOlderThan12Hours) {
        let virtualColorQty = selectedColorQty;

        if (editingTransaction && editingTransaction.product_id === form.product_id) {
          const oldQty = editingTransaction.quantity;
          const oldColorNormalized = (editingTransaction.color_name || 'Default').trim().toLowerCase();
          const oldWarehouseId = editingTransaction.warehouse_id?.toString() || '';
          const formColorNormalized = form.color_name.trim().toLowerCase();
          const formWarehouseId = form.warehouse_id?.toString() || '';

          if (editingTransaction.type === 'stock_out') {
            if (oldColorNormalized === formColorNormalized && oldWarehouseId === formWarehouseId) {
              virtualColorQty += oldQty;
            }
          } else if (editingTransaction.type === 'stock_in') {
            if (oldColorNormalized === formColorNormalized && oldWarehouseId === formWarehouseId) {
              virtualColorQty -= oldQty;
            }
          }
        }

        if (form.type === 'stock_out' && form.quantity > virtualColorQty) {
          setError(`Only ${virtualColorQty} units available for color "${form.color_name}" in the selected warehouse.`);
          setSaving(false);
          return;
        }
      }

      let finalNotes = form.notes.trim();
      if (form.cartons && form.pcsPerCarton) {
        const cartonNote = `${form.cartons} ctn × ${form.pcsPerCarton} pcs`;
        finalNotes = finalNotes ? `${cartonNote} | ${finalNotes}` : cartonNote;
      }
      if (form.type === 'stock_out' && form.customer_name.trim()) {
        const customer = form.customer_name.trim();
        finalNotes = finalNotes ? `Customer: ${customer} | ${finalNotes}` : `Customer: ${customer}`;
      }

      if (editingTransactionId) {
        await serverPatch(`/transactions/${encodeURIComponent(editingTransactionId)}`, {
          type: form.type,
          quantity: form.quantity,
          cartons: form.cartons ? Number(form.cartons) : null,
          pcs_per_carton: form.pcsPerCarton ? Number(form.pcsPerCarton) : null,
          worker_name: form.worker_name.trim(),
          notes: finalNotes || null,
        });
      } else {
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
          notes: finalNotes || null,
        });

        if (form.type === 'stock_in' && form.product_id) {
          const nextPrefs = {
            ...stockPrefs,
            [form.product_id]: {
              warehouse_id: form.warehouse_id || undefined,
              color_name: form.color_name.trim() || undefined,
              updated_at: Date.now(),
            },
          };
          setStockPrefs(nextPrefs);
          window.localStorage.setItem(STOCK_PREFS_STORAGE_KEY, JSON.stringify(nextPrefs));
        }
      }

      setForm({
        ...EMPTY_FORM,
        warehouse_id: warehouses[0]?.id ?? '',
      });
      setEditingTransactionId(null);
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
                ? 'stock-success-soft border-emerald-500/20'
                : realtimeStatus === 'error'
                  ? 'stock-danger-soft border-red-500/20'
                  : 'stock-warning-soft border-amber-500/20'
              }`}>
              <div className={`w-1.5 h-1.5 rounded-full ${realtimeStatus === 'connected' ? 'bg-emerald-500 animate-pulse' : realtimeStatus === 'error' ? 'bg-red-500' : 'bg-amber-500'
                }`} />
              {realtimeStatus === 'connected' ? 'LIVE' : realtimeStatus === 'error' ? 'OFFLINE' : 'CONNECTING'}
            </div>
          </div>
          <p className="stock-secondary text-sm">{transactions.length} transactions recorded</p>
        </div>
        <div className="flex items-center gap-3">
          <button
            onClick={() => setShowExportModal(true)}
            className="stock-soft-control flex items-center gap-2 rounded-xl border px-5 py-2.5 text-sm font-semibold transition active:scale-95"
          >
            <span>📥</span> Export to Excel
          </button>
          <button
            onClick={() => { setEditingTransactionId(null); setForm(EMPTY_FORM); setError(''); setShowModal(true); }}
            className="bg-indigo-600 hover:bg-indigo-500 text-white text-sm font-semibold px-5 py-2.5 rounded-xl transition shadow-lg shadow-indigo-500/20 active:scale-95"
          >
            + Record Stock
          </button>
        </div>
      </div>

      {/* Table */}
      <div className="card overflow-hidden">
        {loading ? (
          <div className="stock-secondary p-12 text-center text-sm">Loading transactions…</div>
        ) : transactions.length === 0 ? (
          <div className="stock-secondary p-12 text-center text-sm">No stock entries yet. Click "+ Record Stock" to log the first transaction.</div>
        ) : (
          <>
            {/* Filter Toolbar */}
            <div className="stock-toolbar flex flex-col lg:flex-row lg:items-center justify-between gap-4 border-b p-5">
              <div className="flex flex-wrap items-center gap-4 sm:gap-6">
                {/* Date Filter */}
                <div className="flex flex-wrap items-center gap-2">
                  <span className="stock-secondary text-xs font-bold uppercase tracking-wider">Date:</span>
                  <div className="stock-soft-control flex rounded-xl border p-1">
                    <button
                      onClick={() => setDateFilter('all')}
                      className={`rounded-lg px-3 py-1.5 text-xs font-semibold transition active:scale-95 ${dateFilter === 'all' ? 'stock-segment-active-primary shadow-md' : 'stock-segment'}`}
                    >
                      All Time
                    </button>
                    <button
                      onClick={() => setDateFilter('today')}
                      className={`rounded-lg px-3 py-1.5 text-xs font-semibold transition active:scale-95 ${dateFilter === 'today' ? 'stock-segment-active-primary shadow-md' : 'stock-segment'}`}
                    >
                      Today
                    </button>
                    <button
                      onClick={() => setDateFilter('custom')}
                      className={`rounded-lg px-3 py-1.5 text-xs font-semibold transition active:scale-95 ${dateFilter === 'custom' ? 'stock-segment-active-primary shadow-md' : 'stock-segment'}`}
                    >
                      Choose Date
                    </button>
                  </div>

                  {dateFilter === 'custom' && (
                    <input
                      id="stock-custom-date"
                      name="stock-custom-date"
                      type="date"
                      aria-label="Stock custom date"
                      value={customDate}
                      onChange={(e) => setCustomDate(e.target.value)}
                      className="stock-field rounded-lg border px-2 py-1 text-xs focus:outline-none focus:border-indigo-500"
                    />
                  )}
                </div>

                {/* Type Filter */}
                <div className="flex items-center gap-2">
                  <span className="stock-secondary text-xs font-bold uppercase tracking-wider">Type:</span>
                  <div className="stock-soft-control flex rounded-xl border p-1">
                    <button
                      onClick={() => setTypeFilter('both')}
                      className={`rounded-lg px-3 py-1.5 text-xs font-semibold transition active:scale-95 ${typeFilter === 'both' ? 'stock-segment-active-primary shadow-md' : 'stock-segment'}`}
                    >
                      All Types
                    </button>
                    <button
                      onClick={() => setTypeFilter('stock_in')}
                      className={`rounded-lg px-3 py-1.5 text-xs font-semibold transition active:scale-95 ${typeFilter === 'stock_in' ? 'stock-segment-active-success shadow-md' : 'stock-segment'}`}
                    >
                      Stock In
                    </button>
                    <button
                      onClick={() => setTypeFilter('stock_out')}
                      className={`rounded-lg px-3 py-1.5 text-xs font-semibold transition active:scale-95 ${typeFilter === 'stock_out' ? 'stock-segment-active-danger shadow-md' : 'stock-segment'}`}
                    >
                      Stock Out
                    </button>
                  </div>
                </div>
              </div>

              <div className="stock-secondary text-xs font-medium">
                Showing {filteredTransactions.length} of {transactions.length} entries
              </div>
            </div>

            {filteredTransactions.length === 0 ? (
              <div className="stock-secondary p-12 text-center text-sm">
                No entries found for the selected filter criteria.
              </div>
            ) : (
              <table className="data-table w-full text-sm">
                <thead>
                  <tr>
                    <th className="text-left w-12">#</th>
                    <th className="text-left">Worker</th>
                    <th className="text-left">Type</th>
                    <th className="text-left">Code</th>
                    <th className="text-left">Color</th>
                    <th className="text-left">Warehouse</th>
                    <th className="text-right">Qty</th>
                    <th className="text-left">Notes</th>
                    <th className="text-left">Date / Time</th>
                    <th className="text-left">Action</th>
                  </tr>
                </thead>
                <tbody>
                  {filteredTransactions.map((t, idx) => (
                    <tr key={t.id}>
                      <td className="stock-muted font-mono text-xs w-12">{idx + 1}</td>
                      <td className="font-medium">{t.worker_name}</td>
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
                            className="stock-primary-link text-left font-mono text-sm font-bold hover:underline"
                          >
                            {t.product_code}
                          </button>
                          <span className="stock-muted mt-0.5 max-w-[200px] truncate text-[10px] leading-tight">
                            {t.product_name}
                          </span>
                        </div>
                      </td>
                      <td className="stock-secondary">{t.color_name || 'Default'}</td>
                      <td className="stock-secondary max-w-[180px] truncate">{t.warehouse_name || 'Main Warehouse'}</td>
                      <td className="text-right py-2">
                        <div className="flex flex-col items-end justify-center">
                          <span className={`font-mono font-bold text-sm ${t.type === 'stock_in' ? 'stock-success-value' : 'stock-danger-value'}`}>
                            {t.type === 'stock_in' ? '+' : '-'}{t.quantity}
                          </span>
                          {(() => {
                            if (t.cartons && t.pcs_per_carton) {
                              return (
                                <span className="stock-muted mt-0.5 whitespace-nowrap text-[10px] leading-tight">
                                  {t.cartons} ctn × {t.pcs_per_carton}
                                </span>
                              );
                            }
                            const parsed = parseCartonFromNotes(t.notes);
                            if (parsed) {
                              return (
                                <span className="stock-muted mt-0.5 whitespace-nowrap text-[10px] leading-tight">
                                  {parsed.cartons} ctn × {parsed.pcsPerCarton}
                                </span>
                              );
                            }
                            return null;
                          })()}
                        </div>
                      </td>
                      <td className="stock-muted max-w-[140px] truncate text-xs">{t.notes || '—'}</td>
                      <td className="stock-muted text-xs">{new Date(t.created_at).toLocaleString('en-IN', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' })}</td>
                      <td>
                        <button
                          type="button"
                          onClick={() => {
                            const params = new URLSearchParams({
                              transactionId: t.id,
                              productId: t.product_id,
                              type: t.type,
                              color: t.color_name || 'Default',
                              quantity: String(t.quantity),
                              notes: t.notes || '',
                              workerName: t.worker_name || '',
                            });
                            if (t.warehouse_id) {
                              params.set('warehouseId', t.warehouse_id);
                            } else if (t.warehouse_name) {
                              const matchedWarehouse = warehouses.find((w) => w.name === t.warehouse_name);
                              if (matchedWarehouse?.id) params.set('warehouseId', matchedWarehouse.id);
                            }
                            if (t.worker_id) {
                              params.set('workerId', t.worker_id);
                            } else if (t.worker_name) {
                              const matchedWorker = workers.find((w) => w.name === t.worker_name);
                              if (matchedWorker?.id) params.set('workerId', matchedWorker.id);
                            }
                            if (t.cartons != null) params.set('cartons', String(t.cartons));
                            if (t.pcs_per_carton != null) params.set('pcsPerCarton', String(t.pcs_per_carton));
                            const customer = parseCustomerFromNotes(t.notes);
                            if (customer) params.set('customer', customer);
                            router.push(`/stock?${params.toString()}`);
                          }}
                          className="stock-edit-action rounded-md border px-2.5 py-1 text-xs font-semibold"
                        >
                          Edit
                        </button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </>
        )}
      </div>

      {/* Record Stock Modal */}
      {showModal && (
        <div className="stock-modal-overlay fixed inset-0 backdrop-blur-sm z-50 flex items-center justify-center p-4 overflow-y-auto">
          <div className="stock-modal-surface rounded-2xl border p-8 w-full max-w-lg my-auto max-h-[90vh] overflow-y-auto">
            <div className="flex items-center justify-between mb-6">
              <h2 className="text-xl font-bold">{editingTransactionId ? 'Edit Stock Transaction' : 'Record Stock Movement'}</h2>
              <button onClick={() => setShowModal(false)} className="stock-icon-control flex h-8 w-8 items-center justify-center rounded-full text-2xl leading-none">×</button>
            </div>

            <form onSubmit={handleSubmit} className="space-y-5">
              {isEditingOlderThan12Hours && (
                <div className="stock-warning-soft flex items-start gap-2.5 rounded-xl border border-amber-500/20 p-3 text-xs leading-normal">
                  <span className="text-sm">ℹ️</span>
                  <p>This transaction was recorded more than 12 hours ago. Only the customer name and notes can be edited.</p>
                </div>
              )}

              {/* Type Toggle */}
              <div>
                <div className="stock-muted mb-2 text-xs uppercase tracking-wider">Movement Type</div>
                <div className="flex gap-3">
                  {(['stock_in', 'stock_out'] as TransactionType[]).map((t) => (
                    <button
                      key={t}
                      type="button"
                      disabled={isEditingOlderThan12Hours}
                      onClick={() => {
                        setForm((prev) => ({ ...prev, type: t }));
                        if (t === 'stock_out' && form.product_id) {
                          fetchStockDistribution(form.product_id, true);
                        }
                      }}
                      className={`flex-1 py-2.5 rounded-xl text-sm font-semibold border transition ${form.type === t
                          ? t === 'stock_in'
                            ? 'stock-success-soft border-emerald-500/30'
                            : 'stock-danger-soft border-red-500/30'
                          : 'stock-soft-control'
                        } ${isEditingOlderThan12Hours ? 'opacity-50 cursor-not-allowed' : ''}`}
                    >
                      {t === 'stock_in' ? '↑ Stock In' : '↓ Stock Out'}
                    </button>
                  ))}
                </div>
              </div>

              {/* Product */}
              <div>
                <label htmlFor="stock-product-picker" className="stock-muted mb-1.5 block text-xs uppercase tracking-wider">Product *</label>
                <button
                  id="stock-product-picker"
                  type="button"
                  disabled={isEditingOlderThan12Hours}
                  onClick={() => setShowProductPicker(true)}
                  className={`stock-field w-full rounded-lg border px-3 py-2.5 text-sm text-left focus:outline-none focus:border-indigo-500 flex justify-between items-center ${isEditingOlderThan12Hours ? 'opacity-50 cursor-not-allowed' : ''}`}
                >
                  {form.product_id ? (
                    <div className="flex flex-col">
                      <span className="font-mono font-bold text-indigo-500 text-sm">
                        {productById.get(form.product_id)?.code}
                      </span>
                      <span className="stock-muted text-[10px] leading-tight">
                        {productById.get(form.product_id)?.name}
                      </span>
                    </div>
                  ) : (
                    <span className="stock-muted">Choose product from folders...</span>
                  )}
                  <div className="flex items-center gap-3">
                    {selectedProduct && (
                      <span className="stock-primary-badge rounded-md px-2 py-1 text-[10px] font-bold uppercase tracking-wider">
                        Available: {selectedProduct.quantity}
                      </span>
                    )}
                    <span className="stock-muted text-xs">▼</span>
                  </div>
                </button>
              </div>

              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label htmlFor="stock-warehouse" className="stock-muted mb-1.5 block text-xs uppercase tracking-wider">Warehouse</label>
                  <select
                    id="stock-warehouse"
                    name="stock-warehouse"
                    value={form.warehouse_id}
                    disabled={isEditingOlderThan12Hours}
                    onChange={(e) => handleWarehouseChange(e.target.value)}
                    className="stock-field w-full rounded-lg border px-3 py-2.5 text-sm focus:outline-none focus:border-indigo-500 disabled:opacity-50 disabled:cursor-not-allowed"
                  >
                    {filteredWarehouseOptions.length === 0 ? (
                      <option value="" className="bg-white dark:bg-[#0f1117]">No warehouse with stock</option>
                    ) : (
                      filteredWarehouseOptions.map((w) => (
                        <option key={w.id} value={w.id} className="bg-white dark:bg-[#0f1117]">
                          {w.location ? `${w.name} — ${w.location}` : w.name}
                        </option>
                      ))
                    )}
                  </select>
                </div>
                <div>
                  <label htmlFor="stock-color" className="stock-muted mb-1.5 block text-xs uppercase tracking-wider">Color *</label>
                  {form.type === 'stock_out' ? (
                    <div className="relative">
                      <select
                        id="stock-color"
                        name="stock-color"
                        required
                        disabled={isEditingOlderThan12Hours}
                        value={form.color_name}
                        onChange={(e) => handleColorChange(e.target.value)}
                        className="stock-field w-full rounded-lg border px-3 py-2.5 text-sm focus:outline-none focus:border-indigo-500 disabled:opacity-50 disabled:cursor-not-allowed"
                      >
                        {colorSuggestions.length === 0 ? (
                          <option value="" className="bg-white dark:bg-[#0f1117]">No colors in stock</option>
                        ) : (
                          colorSuggestions.map((color) => (
                            <option key={color} value={color} className="bg-white dark:bg-[#0f1117]">
                              {color}
                            </option>
                          ))
                        )}
                      </select>
                      {form.product_id && (
                        <span className="stock-quantity-pill absolute right-8 top-1/2 -translate-y-1/2 rounded px-1.5 py-0.5 text-[10px] font-bold pointer-events-none">
                          Stock: {selectedColorQty}
                        </span>
                      )}
                    </div>
                  ) : (
                    <div className="relative">
                      <input
                        id="stock-color"
                        name="stock-color"
                        required
                        type="text"
                        disabled={isEditingOlderThan12Hours}
                        list="color-suggestions"
                        value={form.color_name}
                        onChange={(e) => handleColorChange(e.target.value)}
                        className="stock-field w-full rounded-lg border px-3 py-2.5 text-sm focus:outline-none focus:border-indigo-500 disabled:opacity-50 disabled:cursor-not-allowed"
                        placeholder="e.g. Black"
                      />
                      <datalist id="color-suggestions">
                        {colorSuggestions.map((color) => (
                          <option key={color} value={color} />
                        ))}
                      </datalist>
                      {form.product_id && (
                        <span className="stock-quantity-pill absolute right-3 top-1/2 -translate-y-1/2 rounded px-1.5 py-0.5 text-[10px] font-bold">
                          Stock: {selectedColorQty}
                        </span>
                      )}
                    </div>
                  )}
                  {availableColors.length > 0 && (
                    <p className="stock-muted mt-1 text-[11px]">
                      Available: {availableColors.map((c) => `${c.color} (${c.quantity})`).join(', ')}
                    </p>
                  )}
                </div>
              </div>

              {/* Quantity + Worker */}
              <div className="grid gap-4">
                <div className="grid grid-cols-3 gap-4">
                  <div>
                    <label htmlFor="stock-cartons" className="stock-muted mb-1.5 block text-xs uppercase tracking-wider">Cartons</label>
                    <input
                      id="stock-cartons"
                      name="stock-cartons"
                      type="number" min="0"
                      disabled={isEditingOlderThan12Hours}
                      value={form.cartons}
                      onChange={(e) => {
                        const c = Number(e.target.value);
                        const p = Number(form.pcsPerCarton) || 0;
                        setForm({ ...form, cartons: e.target.value, quantity: c * p || 0 });
                      }}
                      className="stock-field w-full rounded-lg border px-3 py-2.5 text-sm focus:outline-none focus:border-indigo-500 disabled:opacity-50 disabled:cursor-not-allowed"
                      placeholder="e.g. 5"
                    />
                  </div>
                  <div>
                    <label htmlFor="stock-pcs-per-carton" className="stock-muted mb-1.5 block text-xs uppercase tracking-wider">Pcs / Carton</label>
                    <input
                      id="stock-pcs-per-carton"
                      name="stock-pcs-per-carton"
                      type="number" min="0"
                      disabled={isEditingOlderThan12Hours}
                      value={form.pcsPerCarton}
                      onChange={(e) => {
                        const p = Number(e.target.value);
                        const c = Number(form.cartons) || 0;
                        setForm({ ...form, pcsPerCarton: e.target.value, quantity: c * p || 0 });
                      }}
                      className="stock-field w-full rounded-lg border px-3 py-2.5 text-sm focus:outline-none focus:border-indigo-500 disabled:opacity-50 disabled:cursor-not-allowed"
                      placeholder="e.g. 20"
                    />
                  </div>
                  <div>
                    <label htmlFor="stock-quantity" className="stock-muted mb-1.5 block text-xs uppercase tracking-wider">Total Quantity *</label>
                    <input
                      id="stock-quantity"
                      name="stock-quantity"
                      type="number" required min="1"
                      disabled={isEditingOlderThan12Hours}
                      value={form.quantity || ''}
                      onChange={(e) => setForm({ ...form, quantity: Number(e.target.value) })}
                      className="stock-field w-full rounded-lg border px-3 py-2.5 text-sm focus:outline-none focus:border-indigo-500 disabled:opacity-50 disabled:cursor-not-allowed"
                      placeholder="e.g. 100"
                    />
                  </div>
                </div>
                <div>
                  <label htmlFor="stock-worker" className="stock-muted mb-1.5 block text-xs uppercase tracking-wider">Recorded By *</label>
                  <select
                    id="stock-worker"
                    name="stock-worker"
                    required
                    disabled={isEditingOlderThan12Hours}
                    value={form.worker_id}
                    onChange={(e) => {
                      const w = workers.find(w => w.id === e.target.value);
                      setForm({ ...form, worker_id: e.target.value, worker_name: w?.name || '' });
                    }}
                    className="stock-field w-full rounded-lg border px-3 py-2.5 text-sm focus:outline-none focus:border-indigo-500 disabled:opacity-50 disabled:cursor-not-allowed"
                  >
                    <option value="" disabled className="bg-white dark:bg-[#0f1117]">Select Worker...</option>
                    {workers.map((w) => (
                      <option key={w.id} value={w.id} className="bg-white dark:bg-[#0f1117]">
                        {w.name}
                      </option>
                    ))}
                  </select>
                </div>
              </div>

              {/* Customer Name */}
              {form.type === 'stock_out' && (
                <div>
                  <label htmlFor="stock-customer-name" className="stock-muted mb-1.5 block text-xs uppercase tracking-wider">Customer Name (optional)</label>
                  <input
                    id="stock-customer-name"
                    name="stock-customer-name"
                    type="text"
                    value={form.customer_name}
                    onChange={(e) => setForm({ ...form, customer_name: e.target.value })}
                    className="stock-field w-full rounded-lg border px-3 py-2.5 text-sm focus:outline-none focus:border-indigo-500"
                    placeholder="Enter customer name"
                  />
                </div>
              )}

              {/* Notes */}
              <div>
                <label htmlFor="stock-notes" className="stock-muted mb-1.5 block text-xs uppercase tracking-wider">Notes (optional)</label>
                <input
                  id="stock-notes"
                  name="stock-notes"
                  type="text"
                  value={form.notes}
                  onChange={(e) => setForm({ ...form, notes: e.target.value })}
                  className="stock-field w-full rounded-lg border px-3 py-2.5 text-sm focus:outline-none focus:border-indigo-500"
                  placeholder="Reason, batch number, etc."
                />
              </div>

              {error && (
                <p className="stock-danger-soft rounded-lg px-3 py-2 text-sm">{error}</p>
              )}

              <div className="flex gap-3 pt-2">
                <button
                  type="submit"
                  disabled={saving}
                  className={`flex-1 font-semibold py-3 rounded-xl transition text-white disabled:opacity-50 ${form.type === 'stock_in' ? 'bg-emerald-600 hover:bg-emerald-500' : 'bg-red-600 hover:bg-red-500'
                    }`}
                >
                  {saving ? 'Saving…' : editingTransactionId ? 'Save Changes' : form.type === 'stock_in' ? '↑ Record Stock In' : '↓ Record Stock Out'}
                </button>
                <button
                  type="button"
                  onClick={() => setShowModal(false)}
                  className="stock-soft-control rounded-xl border px-6 py-3 text-sm transition"
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
        <div className="stock-modal-surface fixed inset-0 z-[60] flex flex-col p-4 md:p-8 overflow-hidden">
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
              className="stock-soft-control flex min-w-[40px] items-center justify-center rounded-lg border p-2"
            >
              ←
            </button>
            <input
              id="stock-product-search"
              name="stock-product-search"
              type="text"
              autoFocus
              value={pickerSearch}
              onChange={(e) => setPickerSearch(e.target.value)}
              placeholder="Search products by name or code..."
              className="stock-field flex-1 rounded-xl border px-4 py-3 focus:outline-none focus:border-indigo-500"
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
                        const productPcs = Number(p.pcs_per_carton);
                        setForm((prev) => ({
                          ...prev,
                          product_id: p.id,
                          pcsPerCarton: Number.isFinite(productPcs) && productPcs > 0 ? productPcs : 1,
                          cartons: '',
                          quantity: 0,
                          ...(prev.type !== 'stock_out' ? {
                            color_name: p.color_stocks?.[0]?.color || 'Default',
                          } : {}),
                        }));
                        if (form.type === 'stock_out') {
                          fetchStockDistribution(p.id, true);
                        }
                        setShowProductPicker(false);
                        setPickerSearch('');
                        setPickerCategory(null);
                      }}
                      className="stock-modal-panel text-left rounded-xl border p-4 transition hover:border-indigo-500/50 hover:bg-indigo-500/10"
                    >
                      <p className="font-mono font-bold text-indigo-700 dark:text-indigo-400 text-sm">{p.code}</p>
                      <p className="stock-muted mt-0.5 truncate text-[10px]">{p.name}</p>
                      <p className="mt-2 text-xs text-indigo-700 dark:text-indigo-400">{p.quantity} in stock</p>
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
                        const productPcs = Number(p.pcs_per_carton);
                        setForm((prev) => ({
                          ...prev,
                          product_id: p.id,
                          pcsPerCarton: Number.isFinite(productPcs) && productPcs > 0 ? productPcs : 1,
                          cartons: '',
                          quantity: 0,
                          ...(prev.type !== 'stock_out' ? {
                            color_name: p.color_stocks?.[0]?.color || 'Default',
                          } : {}),
                        }));
                        if (form.type === 'stock_out') {
                          fetchStockDistribution(p.id, true);
                        }
                        setShowProductPicker(false);
                        setPickerSearch('');
                        setPickerCategory(null);
                      }}
                      className="stock-modal-panel text-left rounded-xl border p-4 transition hover:border-indigo-500/50 hover:bg-indigo-500/10"
                    >
                      <p className="font-mono font-bold text-indigo-700 dark:text-indigo-400 text-sm">{p.code}</p>
                      <p className="stock-muted mt-0.5 truncate text-[10px]">{p.name}</p>
                      <p className="text-[10px] font-bold text-indigo-700 dark:text-indigo-300 mt-2 uppercase tracking-tight bg-indigo-50 dark:bg-indigo-500/10 px-2 py-0.5 rounded inline-block">
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
                    className="stock-modal-panel group relative flex aspect-square flex-col items-center justify-center overflow-hidden rounded-2xl border p-4 transition hover:border-indigo-500/40 hover:bg-indigo-500/5"
                  >
                    <div className="absolute inset-0 bg-gradient-to-br from-indigo-500/10 to-transparent opacity-0 group-hover:opacity-100 transition" />
                    <span className="text-4xl mb-2 opacity-80">📁</span>
                    <p className="line-clamp-2 text-center text-sm font-semibold">{name}</p>
                    <span className="stock-soft-control mt-2 rounded-full border-0 px-2 py-0.5 text-[10px] uppercase tracking-wider">{count} items</span>
                  </button>
                ))}
              </div>
            )}
          </div>
        </div>
      )}

      {/* Export Excel Modal */}
      {showExportModal && (
        <div className="stock-modal-overlay fixed inset-0 backdrop-blur-sm z-50 flex items-center justify-center p-4">
          <div className="stock-modal-surface rounded-3xl border w-full max-w-lg shadow-2xl overflow-hidden transition-all duration-300">
            {/* Header */}
            <div className="stock-modal-header px-8 py-6 border-b flex items-center justify-between">
              <div>
                <h2 className="flex items-center gap-2 text-xl font-bold">
                  <span>📥</span> Export Stock Report
                </h2>
                <p className="stock-muted mt-1 text-xs">Download daily transactions by product in Excel format</p>
              </div>
              <button 
                onClick={() => setShowExportModal(false)} 
                className="stock-icon-control flex h-8 w-8 items-center justify-center rounded-full text-2xl leading-none transition-all"
              >
                ×
              </button>
            </div>

            <div className="p-8 space-y-6">
              {/* Date Input & Quick Selectors */}
              <div className="space-y-3">
                <label htmlFor="stock-export-date" className="stock-muted block text-xs font-semibold uppercase tracking-wider">Select Date</label>
                <div className="flex gap-2">
                  <input
                    id="stock-export-date"
                    name="stock-export-date"
                    type="date"
                    required
                    value={exportDate}
                    onChange={(e) => setExportDate(e.target.value)}
                    className="stock-field flex-1 rounded-xl border px-4 py-3 text-sm focus:outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500/30 transition-all font-mono"
                  />
                  <button
                    type="button"
                    onClick={() => {
                      const local = new Date();
                      const offset = local.getTimezoneOffset();
                      const adjusted = new Date(local.getTime() - (offset * 60 * 1000));
                      setExportDate(adjusted.toISOString().slice(0, 10));
                    }}
                    className="stock-soft-control rounded-xl border px-3.5 py-2.5 text-xs font-semibold active:scale-95 transition-all"
                  >
                    Today
                  </button>
                  <button
                    type="button"
                    onClick={() => {
                      const local = new Date();
                      local.setDate(local.getDate() - 1);
                      const offset = local.getTimezoneOffset();
                      const adjusted = new Date(local.getTime() - (offset * 60 * 1000));
                      setExportDate(adjusted.toISOString().slice(0, 10));
                    }}
                    className="stock-soft-control rounded-xl border px-3.5 py-2.5 text-xs font-semibold active:scale-95 transition-all"
                  >
                    Yesterday
                  </button>
                </div>
              </div>

              {/* Live Preview Stats */}
              <div className="space-y-3">
                <div className="stock-muted text-xs font-semibold uppercase tracking-wider">Report Preview</div>
                
                <div className="grid grid-cols-2 gap-4">
                  {/* Stock In Preview Card */}
                  <div className="stock-success-soft flex flex-col justify-between rounded-2xl border border-emerald-500/20 p-4">
                    <div>
                      <span className="stock-success-badge rounded px-2 py-0.5 text-[10px] font-bold uppercase tracking-wider">
                        Sheet 1: In stock
                      </span>
                      <p className="stock-success-value mt-3 text-2xl font-black font-mono">
                        +{exportStats.totalInQty}
                        <span className="stock-muted ml-1 text-xs font-normal">pcs</span>
                      </p>
                    </div>
                    <p className="stock-muted mt-2 text-[10px] font-medium">
                      {exportStats.totalInCount} entries recorded
                    </p>
                  </div>

                  {/* Stock Out Preview Card */}
                  <div className="stock-danger-soft flex flex-col justify-between rounded-2xl border border-rose-500/20 p-4">
                    <div>
                      <span className="stock-danger-badge rounded px-2 py-0.5 text-[10px] font-bold uppercase tracking-wider">
                        Sheet 2: Stock out
                      </span>
                      <p className="stock-danger-value mt-3 text-2xl font-black font-mono">
                        -{exportStats.totalOutQty}
                        <span className="stock-muted ml-1 text-xs font-normal">pcs</span>
                      </p>
                    </div>
                    <p className="stock-muted mt-2 text-[10px] font-medium">
                      {exportStats.totalOutCount} entries recorded
                    </p>
                  </div>
                </div>

                {exportStats.totalCount === 0 && (
                  <div className="stock-warning-soft flex animate-pulse items-start gap-2.5 rounded-xl border border-amber-500/20 p-3 text-xs leading-normal">
                    <span className="text-sm">⚠️</span>
                    <p>No transactions found on this date. The report will generate empty tables for all products.</p>
                  </div>
                )}
              </div>

              {/* Action Buttons */}
              <div className="flex gap-3 pt-2 border-t border-slate-200 dark:border-white/5">
                <button
                  onClick={handleExportExcel}
                  className="flex-1 font-semibold py-3 rounded-xl transition text-white bg-indigo-600 hover:bg-indigo-500 flex items-center justify-center gap-2 shadow-lg shadow-indigo-600/20 active:scale-95 duration-150"
                >
                  📥 Download Excel Report
                </button>
                <button
                  type="button"
                  onClick={() => setShowExportModal(false)}
                  className="stock-soft-control rounded-xl border px-6 py-3 text-sm transition active:scale-95 duration-150"
                >
                  Cancel
                </button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
