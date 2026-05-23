'use client';

import { useEffect, useState, useMemo } from 'react';
import { useRouter } from 'next/navigation';
import { serverGet, ServerApiError } from '../lib/server_api';
import { useRequireAuth } from '../lib/use_require_auth';
import { supabase } from '../lib/supabase';

interface Transaction {
  id: string;
  product_id?: string;
  product_code?: string;
  product_name: string;
  color_name?: string;
  warehouse_name?: string;
  type: 'stock_in' | 'stock_out';
  quantity: number;
  worker_name: string;
  created_at: string;
}

interface Product {
  id: string;
  name: string;
  code: string;
  category?: string;
  quantity: number;
  threshold: number;
  stock_status: string;
  created_at: string;
}

interface WarehouseSummary {
  warehouse_id: string;
  warehouse_name: string;
  location?: string;
  total_quantity: number;
  product_count: number;
  color_count: number;
}

export default function DashboardPage() {
  useRequireAuth();
  const router = useRouter();

  const [adminName, setAdminName] = useState('Admin');
  const [products, setProducts] = useState<Product[]>([]);
  const [transactions, setTransactions] = useState<Transaction[]>([]);
  const [warehouseSummary, setWarehouseSummary] = useState<WarehouseSummary[]>([]);
  const [loadingProducts, setLoadingProducts] = useState(true);
  const [loadingTx, setLoadingTx] = useState(true);
  const [loadingWarehouse, setLoadingWarehouse] = useState(true);

  // UI state
  const [showNotifications, setShowNotifications] = useState(false);
  const [drawerTab, setDrawerTab] = useState<'alerts' | 'activity'>('alerts');
  const [warehouseTab, setWarehouseTab] = useState<'top' | 'all'>('top');

  // Greeting
  const greeting = useMemo(() => {
    const hour = new Date().getHours();
    if (hour < 12) return 'Morning';
    if (hour < 17) return 'Afternoon';
    return 'Evening';
  }, []);

  // Fetch admin profile for greeting
  useEffect(() => {
    serverGet('/auth/me')
      .then((res: any) => {
        if (res?.user?.name) {
          setAdminName(res.user.name);
        } else if (res?.user?.email) {
          setAdminName(res.user.email.split('@')[0]);
        }
      })
      .catch((err) => console.error('Failed to fetch auth me:', err));
  }, []);

  // Fetch functions
  const fetchProducts = async () => {
    try {
      const res = await serverGet('/products');
      setProducts(((res as any).data ?? []) as Product[]);
    } catch (e) {
      if (e instanceof ServerApiError && e.status === 401) {
        router.push('/login');
        return;
      }
      console.error('Failed to fetch products:', e);
    }
    setLoadingProducts(false);
  };

  const fetchTransactions = async () => {
    try {
      const res = await serverGet('/transactions');
      setTransactions(((res as any).data ?? []) as Transaction[]);
    } catch (e) {
      if (e instanceof ServerApiError && e.status === 401) {
        router.push('/login');
        return;
      }
      console.error('Failed to fetch transactions:', e);
    }
    setLoadingTx(false);
  };

  const fetchWarehouseSummary = async () => {
    try {
      const res = await serverGet('/warehouses/stock-summary');
      setWarehouseSummary(((res as any).data ?? []) as WarehouseSummary[]);
    } catch (e) {
      console.error('Failed to fetch warehouse stock summary:', e);
    }
    setLoadingWarehouse(false);
  };

  // Setup real-time updates and initial fetch
  useEffect(() => {
    fetchProducts();
    fetchTransactions();
    fetchWarehouseSummary();

    const channel = supabase
      .channel('dashboard_updates')
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'products' },
        () => {
          fetchProducts();
          fetchWarehouseSummary();
        }
      )
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'transactions' },
        () => {
          fetchTransactions();
          fetchWarehouseSummary();
        }
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [router]);

  // Calculations
  const isToday = (dateString: string) => {
    const date = new Date(dateString);
    const today = new Date();
    return (
      date.getDate() === today.getDate() &&
      date.getMonth() === today.getMonth() &&
      date.getFullYear() === today.getFullYear()
    );
  };

  const totalProducts = products.length;
  
  const availableStock = useMemo(() => {
    return products.reduce((sum, p) => sum + (p.quantity || 0), 0);
  }, [products]);

  const stockInToday = useMemo(() => {
    return transactions
      .filter((t) => t.type === 'stock_in' && isToday(t.created_at))
      .reduce((sum, t) => sum + (t.quantity || 0), 0);
  }, [transactions]);

  const stockOutToday = useMemo(() => {
    return transactions
      .filter((t) => t.type === 'stock_out' && isToday(t.created_at))
      .reduce((sum, t) => sum + (t.quantity || 0), 0);
  }, [transactions]);

  const lowStockProducts = useMemo(() => {
    return products.filter((p) => p.stock_status === 'low_stock' || p.stock_status === 'out_of_stock');
  }, [products]);

  const lowStockCount = lowStockProducts.length;

  const categories = useMemo(() => {
    const cats = products.map((p) => p.category?.trim()).filter(Boolean) as string[];
    const unique = Array.from(new Set(cats));
    unique.sort();
    return unique;
  }, [products]);

  const getCategoryCount = (catName: string) => {
    return products.filter((p) => p.category === catName).length;
  };

  // SVGs Chart Data Generation (Last 7 Days)
  const netSevenDays = useMemo(() => {
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
      const txDate = new Date(txn.created_at);
      if (isNaN(txDate.getTime())) continue;
      const key = new Date(txDate.getFullYear(), txDate.getMonth(), txDate.getDate()).toISOString().slice(0, 10);
      const point = pointMap.get(key);
      if (!point) continue;
      point.value += txn.type === 'stock_in' ? txn.quantity : -txn.quantity;
    }
    return points;
  }, [transactions]);

  const maxY = Math.max(10, ...netSevenDays.map((point) => Math.abs(point.value)));
  const ySpan = maxY * 2; // symmetric span around zero

  const chartPoints = useMemo(() => {
    return netSevenDays
      .map((point, index) => {
        const x = (index / Math.max(netSevenDays.length - 1, 1)) * 100;
        // zero line is at Y = 50. values mapped proportionally
        const y = 50 - (point.value / maxY) * 40; // max height is 90, min is 10
        return { x, y, value: point.value, label: point.label };
      });
  }, [netSevenDays, maxY]);

  const polylinePointsStr = useMemo(() => {
    return chartPoints.map((p) => `${p.x},${p.y}`).join(' ');
  }, [chartPoints]);

  const sortedWarehouses = useMemo(() => {
    const list = [...warehouseSummary];
    if (warehouseTab === 'top') {
      return list.sort((a, b) => b.total_quantity - a.total_quantity).slice(0, 5);
    }
    return list.sort((a, b) => a.warehouse_name.localeCompare(b.warehouse_name));
  }, [warehouseSummary, warehouseTab]);

  return (
    <div className="space-y-8 pb-12">
      {/* Dynamic greeting header & notification center */}
      <div className="flex items-center justify-between">
        <div>
          <p className="text-xs font-semibold text-slate-500 dark:text-gray-400 uppercase tracking-wide">
            Good {greeting},
          </p>
          <h1 className="text-2xl font-extrabold text-slate-800 dark:text-white mt-0.5">
            {adminName}
          </h1>
        </div>

        {/* Notification Bell Icon */}
        <div className="relative">
          <button
            onClick={() => {
              setDrawerTab(lowStockCount > 0 ? 'alerts' : 'activity');
              setShowNotifications(true);
            }}
            className="p-2.5 rounded-xl border border-slate-200 dark:border-white/5 bg-white dark:bg-white/[0.03] text-slate-700 dark:text-gray-300 hover:bg-slate-100 dark:hover:bg-white/5 hover:text-slate-900 dark:hover:text-white transition shadow-sm"
          >
            🔔
          </button>
          {lowStockCount > 0 && (
            <span className="absolute -top-1.5 -right-1.5 flex h-5 w-5 items-center justify-center rounded-full bg-red-500 text-[10px] font-bold text-white ring-2 ring-slate-50 dark:ring-[#0a0a0f] animate-pulse">
              {lowStockCount}
            </span>
          )}
        </div>
      </div>

      {/* Stats Grid (Aligned with Mobile App Colors and Icons) */}
      <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        {[
          {
            label: 'Total Products',
            value: loadingProducts ? '...' : String(totalProducts),
            colorRgb: '--color-primary-rgb',
            colorHex: 'var(--color-primary)',
            icon: '📦',
            href: '/products?view=all',
          },
          {
            label: 'Available Stock',
            value: loadingProducts ? '...' : String(availableStock),
            colorRgb: '--color-success-rgb',
            colorHex: 'var(--color-success)',
            icon: '🥞',
            href: '/products?view=all',
          },
          {
            label: 'Stock In (Today)',
            value: loadingTx ? '...' : `+${stockInToday}`,
            colorRgb: '--color-success-rgb',
            colorHex: 'var(--color-success)',
            icon: '📥',
            href: '/stock',
          },
          {
            label: 'Stock Out (Today)',
            value: loadingTx ? '...' : `-${stockOutToday}`,
            colorRgb: '--color-danger-rgb',
            colorHex: 'var(--color-danger)',
            icon: '📤',
            href: '/stock',
          },
        ].map((stat, i) => (
          <div
            key={i}
            onClick={() => router.push(stat.href)}
            style={{
              backgroundColor: `rgba(var(${stat.colorRgb}), 0.08)`,
              borderColor: `rgba(var(${stat.colorRgb}), 0.15)`,
            }}
            className="flex items-center gap-3 p-4 rounded-2xl border cursor-pointer hover:scale-[1.02] active:scale-95 transition-all shadow-sm group"
          >
            <div
              style={{
                backgroundColor: `rgba(var(${stat.colorRgb}), 0.15)`,
                color: stat.colorHex,
              }}
              className="w-10 h-10 rounded-xl flex items-center justify-center text-lg font-bold transition group-hover:rotate-6"
            >
              {stat.icon}
            </div>
            <div className="min-w-0">
              <p
                style={{ color: stat.colorHex }}
                className="text-lg lg:text-xl font-extrabold truncate"
              >
                {stat.value}
              </p>
              <p className="text-[11px] font-semibold text-slate-500 dark:text-gray-400 uppercase tracking-wider truncate">
                {stat.label}
              </p>
            </div>
          </div>
        ))}
      </div>

      {/* Quick Actions (Dashboard navigation & modal entry) */}
      <div className="space-y-3">
        <h2 className="text-sm font-bold text-slate-800 dark:text-white uppercase tracking-wider">
          Quick Actions
        </h2>
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
          {[
            {
              label: 'Stock In',
              icon: '➕',
              color: 'var(--color-success)',
              href: '/stock?action=record&type=stock_in',
            },
            {
              label: 'Stock Out',
              icon: '➖',
              color: 'var(--color-danger)',
              href: '/stock?action=record&type=stock_out',
            },
            {
              label: 'Products',
              icon: '📦',
              color: 'var(--color-primary)',
              href: '/products',
            },
            {
              label: 'Analytics',
              icon: '📊',
              color: 'var(--color-purple)',
              href: '/analytics',
            },
          ].map((act, i) => (
            <button
              key={i}
              onClick={() => router.push(act.href)}
              className="card flex flex-col items-center justify-center py-4 px-3 text-center transition hover:border-slate-300 dark:hover:border-indigo-500/30 hover:scale-[1.03] active:scale-95 cursor-pointer"
            >
              <span
                style={{ color: act.color }}
                className="text-xl mb-1.5 filter drop-shadow-sm"
              >
                {act.icon}
              </span>
              <span
                style={{ color: act.color }}
                className="text-xs font-bold uppercase tracking-wider"
              >
                {act.label}
              </span>
            </button>
          ))}
        </div>
      </div>

      {/* Main Grid: Split Layout on Desktop, Column Layout on Mobile */}
      <div className="grid gap-6 lg:grid-cols-12">
        {/* Left Columns (8 grid slots on desktop) */}
        <div className="space-y-6 lg:col-span-7">
          
          {/* Warehouse Stock summary section */}
          <div className="card overflow-hidden flex flex-col">
            <div className="p-4 border-b border-slate-200 dark:border-white/5 flex items-center justify-between">
              <h2 className="text-sm font-bold text-slate-800 dark:text-white uppercase tracking-wider">
                Warehouse Stock
              </h2>
              {/* Tab Selector */}
              <div className="flex rounded-lg bg-slate-100 dark:bg-white/5 p-1 text-[11px] font-bold">
                <button
                  onClick={() => setWarehouseTab('top')}
                  className={`px-2.5 py-1 rounded-md transition ${
                    warehouseTab === 'top'
                      ? 'bg-white dark:bg-white/10 text-slate-800 dark:text-white shadow-sm'
                      : 'text-slate-500 dark:text-gray-400 hover:text-slate-800 dark:hover:text-white'
                  }`}
                >
                  Top 5
                </button>
                <button
                  onClick={() => setWarehouseTab('all')}
                  className={`px-2.5 py-1 rounded-md transition ${
                    warehouseTab === 'all'
                      ? 'bg-white dark:bg-white/10 text-slate-800 dark:text-white shadow-sm'
                      : 'text-slate-500 dark:text-gray-400 hover:text-slate-800 dark:hover:text-white'
                  }`}
                >
                  All
                </button>
              </div>
            </div>

            {loadingWarehouse ? (
              <div className="p-8 text-center text-xs text-slate-500 dark:text-gray-400">
                Loading warehouses stock...
              </div>
            ) : sortedWarehouses.length === 0 ? (
              <div className="p-8 text-center text-xs text-slate-500 dark:text-gray-400">
                No warehouse stock logs found.
              </div>
            ) : (
              <div className="p-3 space-y-2 max-h-[300px] overflow-y-auto">
                {sortedWarehouses.map((wh) => (
                  <div
                    key={wh.warehouse_id}
                    onClick={() => router.push(`/warehouses`)}
                    className="flex items-center justify-between p-3 rounded-xl bg-slate-50 dark:bg-white/[0.02] hover:bg-slate-100 dark:hover:bg-white/[0.05] transition-all cursor-pointer border border-slate-100 dark:border-transparent"
                  >
                    <div className="min-w-0">
                      <p className="text-xs font-bold text-slate-800 dark:text-white truncate">
                        {wh.warehouse_name} {wh.location ? `• ${wh.location}` : ''}
                      </p>
                      <p className="text-[10px] text-slate-400 dark:text-gray-500 mt-0.5">
                        Products: {wh.product_count} · Colors: {wh.color_count}
                      </p>
                    </div>
                    <div className="text-right">
                      <span className="text-xs font-extrabold text-emerald-500 dark:text-emerald-400 bg-emerald-500/10 px-2 py-0.5 rounded-md">
                        Qty: {wh.total_quantity}
                      </span>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>

          {/* Stock Movement SVG Line Chart */}
          <div className="card p-5 space-y-4">
            <div className="flex items-center justify-between">
              <h2 className="text-sm font-bold text-slate-800 dark:text-white uppercase tracking-wider">
                Stock Movement (7d)
              </h2>
              <button
                onClick={() => router.push('/stock')}
                className="text-[11px] font-bold text-indigo-600 dark:text-indigo-400 hover:underline"
              >
                View Log →
              </button>
            </div>
            
            <div className="relative rounded-xl bg-slate-50 dark:bg-white/[0.02] border border-slate-100 dark:border-transparent p-4 flex flex-col items-center">
              {loadingTx ? (
                <div className="h-40 flex items-center justify-center text-xs text-slate-500">
                  Loading movements...
                </div>
              ) : transactions.length === 0 ? (
                <div className="h-40 flex items-center justify-center text-xs text-slate-500">
                  Record stock transactions to draw charts.
                </div>
              ) : (
                <>
                  <svg
                    viewBox="0 0 100 100"
                    className="h-44 w-full overflow-visible"
                    preserveAspectRatio="none"
                  >
                    {/* Zero baseline */}
                    <line
                      x1="0"
                      y1="50"
                      x2="100"
                      y2="50"
                      stroke="currentColor"
                      className="text-slate-200 dark:text-white/10"
                      strokeWidth="0.5"
                      strokeDasharray="3 3"
                    />
                    {/* Graph line */}
                    <polyline
                      fill="none"
                      stroke="var(--color-primary)"
                      strokeWidth="2"
                      strokeLinecap="round"
                      strokeLinejoin="round"
                      points={polylinePointsStr}
                    />
                    {/* Point dots */}
                    {chartPoints.map((pt, i) => (
                      <circle
                        key={i}
                        cx={pt.x}
                        cy={pt.y}
                        r="2.5"
                        style={{
                          fill: 'var(--color-primary)',
                          stroke: 'var(--bg-surface)',
                        }}
                        strokeWidth="1.5"
                      />
                    ))}
                  </svg>
                  
                  {/* Chart X axis */}
                  <div className="mt-4 w-full grid grid-cols-7 gap-1 text-center text-[9px] font-semibold text-slate-400 dark:text-gray-500">
                    {netSevenDays.map((p, i) => (
                      <div key={i} className="flex flex-col items-center">
                        <p>{p.label}</p>
                        <p
                          className={
                            p.value > 0
                              ? 'text-emerald-500'
                              : p.value < 0
                              ? 'text-red-500'
                              : 'text-slate-400'
                          }
                        >
                          {p.value > 0 ? `+${p.value}` : p.value}
                        </p>
                      </div>
                    ))}
                  </div>
                </>
              )}
            </div>
          </div>
        </div>

        {/* Right Columns (5 grid slots on desktop) */}
        <div className="space-y-6 lg:col-span-5">
          
          {/* Folders (Horizontal Scrolling Categories list) */}
          <div className="space-y-2.5">
            <div className="flex items-center justify-between">
              <h2 className="text-sm font-bold text-slate-800 dark:text-white uppercase tracking-wider">
                Category Folders
              </h2>
              <button
                onClick={() => router.push('/products')}
                className="text-[11px] font-bold text-indigo-600 dark:text-indigo-400 hover:underline"
              >
                See All
              </button>
            </div>
            
            {loadingProducts ? (
              <div className="text-xs text-slate-500">Loading categories...</div>
            ) : categories.length === 0 ? (
              <div className="text-xs text-slate-500">No categories found yet.</div>
            ) : (
              <div className="flex gap-3 overflow-x-auto pb-2 scrollbar-thin">
                {categories.map((cat) => (
                  <div
                    key={cat}
                    onClick={() =>
                      router.push(`/products/folder?name=${encodeURIComponent(cat)}`)
                    }
                    className="flex-shrink-0 w-28 p-3 rounded-2xl border border-indigo-500/20 bg-indigo-500/5 hover:bg-indigo-500/10 cursor-pointer transition active:scale-95 flex flex-col justify-between h-24"
                  >
                    <span className="text-xl">📁</span>
                    <div>
                      <p className="text-xs font-bold text-slate-800 dark:text-white truncate max-w-full leading-tight">
                        {cat}
                      </p>
                      <p className="text-[10px] text-slate-400 dark:text-gray-500 mt-0.5">
                        {getCategoryCount(cat)} items
                      </p>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>

          {/* Recent Activity List (styled exactly like mobile screen) */}
          <div className="space-y-3">
            <div className="flex items-center justify-between">
              <h2 className="text-sm font-bold text-slate-800 dark:text-white uppercase tracking-wider">
                Recent Activity
              </h2>
              <button
                onClick={() => router.push('/stock')}
                className="text-[11px] font-bold text-indigo-600 dark:text-indigo-400 hover:underline"
              >
                View All
              </button>
            </div>

            {loadingTx ? (
              <div className="text-xs text-slate-500">Loading activity...</div>
            ) : transactions.length === 0 ? (
              <div className="card p-8 text-center text-xs text-slate-500">
                No activity logged yet.
              </div>
            ) : (
              <div className="space-y-2">
                {transactions.slice(0, 5).map((txn) => {
                  const isIn = txn.type === 'stock_in';
                  return (
                    <div
                      key={txn.id}
                      onClick={() =>
                        txn.product_id &&
                        router.push(`/products/${encodeURIComponent(txn.product_id)}`)
                      }
                      className="card p-3 flex items-center justify-between gap-3 hover:border-slate-300 dark:hover:border-white/10 hover:scale-[1.01] transition-all cursor-pointer shadow-sm"
                    >
                      <div className="flex items-center gap-3 min-w-0">
                        {/* Icon */}
                        <div
                          className={`w-9 h-9 rounded-xl flex items-center justify-center font-bold text-xs ${
                            isIn
                              ? 'bg-emerald-500/10 text-emerald-500'
                              : 'bg-red-500/10 text-red-500'
                          }`}
                        >
                          {isIn ? '📥' : '📤'}
                        </div>
                        <div className="min-w-0">
                          <p className="text-xs font-bold text-slate-800 dark:text-white truncate">
                            {txn.product_name}
                          </p>
                          <p className="text-[10px] text-slate-400 dark:text-gray-500 mt-0.5 truncate">
                            By {txn.worker_name}
                          </p>
                        </div>
                      </div>
                      <div className="text-right flex-shrink-0">
                        <span
                          className={`text-sm font-extrabold ${
                            isIn ? 'text-emerald-500' : 'text-red-500'
                          }`}
                        >
                          {isIn ? '+' : '-'}
                          {txn.quantity}
                        </span>
                        <p className="text-[9px] text-slate-400 dark:text-gray-500 mt-0.5 font-mono">
                          {new Date(txn.created_at).toLocaleTimeString('en-IN', {
                            hour: '2-digit',
                            minute: '2-digit',
                          })}
                        </p>
                      </div>
                    </div>
                  );
                })}
              </div>
            )}
          </div>

        </div>
      </div>

      {/* Notification drawer overlay (Right slide drawer) */}
      {showNotifications && (
        <div className="fixed inset-0 z-50 flex justify-end">
          {/* Backdrop */}
          <div
            className="absolute inset-0 bg-black/40 backdrop-blur-sm transition-opacity"
            onClick={() => setShowNotifications(false)}
          />
          {/* Drawer Body */}
          <div className="relative w-full max-w-md h-full bg-white dark:bg-[#111119] border-l border-slate-200 dark:border-white/5 shadow-2xl flex flex-col z-10 transition-transform duration-300">
            {/* Header */}
            <div className="flex items-center justify-between p-4 border-b border-slate-200 dark:border-white/5">
              <h2 className="text-base font-extrabold text-slate-800 dark:text-white uppercase tracking-wider">
                Notifications & Alerts
              </h2>
              <button
                onClick={() => setShowNotifications(false)}
                className="text-slate-400 hover:text-slate-800 dark:hover:text-white text-2xl font-bold leading-none p-1"
              >
                ×
              </button>
            </div>

            {/* Tabs */}
            <div className="flex border-b border-slate-200 dark:border-white/5 p-2 gap-2 text-xs font-bold">
              <button
                onClick={() => setDrawerTab('alerts')}
                className={`flex-1 py-2 text-center rounded-lg transition flex items-center justify-center gap-1.5 ${
                  drawerTab === 'alerts'
                    ? 'bg-slate-100 dark:bg-white/5 text-slate-800 dark:text-white shadow-sm border border-slate-200 dark:border-transparent'
                    : 'text-slate-500 dark:text-gray-400 hover:bg-slate-50 dark:hover:bg-white/[0.01]'
                }`}
              >
                🚨 Critical Alerts
                {lowStockCount > 0 && (
                  <span className="bg-red-500 text-white text-[9px] px-1.5 py-0.5 rounded-full font-bold">
                    {lowStockCount}
                  </span>
                )}
              </button>
              <button
                onClick={() => setDrawerTab('activity')}
                className={`flex-1 py-2 text-center rounded-lg transition flex items-center justify-center gap-1.5 ${
                  drawerTab === 'activity'
                    ? 'bg-slate-100 dark:bg-white/5 text-slate-800 dark:text-white shadow-sm border border-slate-200 dark:border-transparent'
                    : 'text-slate-500 dark:text-gray-400 hover:bg-slate-50 dark:hover:bg-white/[0.01]'
                }`}
              >
                📝 Activity Log
              </button>
            </div>

            {/* List */}
            <div className="flex-1 overflow-y-auto p-4 space-y-3">
              {drawerTab === 'alerts' ? (
                lowStockProducts.length === 0 ? (
                  <div className="h-full flex flex-col items-center justify-center text-center p-6 space-y-2">
                    <span className="text-3xl">✅</span>
                    <p className="text-xs font-bold text-slate-800 dark:text-white">
                      All Systems Healthy
                    </p>
                    <p className="text-[11px] text-slate-400 dark:text-gray-500">
                      No items are currently below their stock threshold.
                    </p>
                  </div>
                ) : (
                  lowStockProducts.map((prod) => (
                    <div
                      key={prod.id}
                      onClick={() => {
                        setShowNotifications(false);
                        router.push(`/products/${encodeURIComponent(prod.id)}`);
                      }}
                      className="p-3 rounded-xl border border-red-500/20 bg-red-500/5 hover:bg-red-500/10 cursor-pointer transition flex items-center gap-3"
                    >
                      <span className="text-xl">⚠️</span>
                      <div className="min-w-0 flex-1">
                        <p className="text-xs font-mono font-bold text-red-600 dark:text-red-400">
                          {prod.code}
                        </p>
                        <p className="text-xs font-semibold text-slate-700 dark:text-gray-300 truncate mt-0.5">
                          {prod.name}
                        </p>
                        <p className="text-[10px] text-slate-400 dark:text-gray-500 mt-1">
                          Stock: <span className="font-bold text-red-500">{prod.quantity}</span> · Threshold: {prod.threshold}
                        </p>
                      </div>
                    </div>
                  ))
                )
              ) : transactions.length === 0 ? (
                <div className="h-full flex flex-col items-center justify-center text-center p-6">
                  <p className="text-xs text-slate-500">No transaction logs available.</p>
                </div>
              ) : (
                transactions.slice(0, 15).map((txn) => {
                  const isIn = txn.type === 'stock_in';
                  return (
                    <div
                      key={txn.id}
                      onClick={() => {
                        if (txn.product_id) {
                          setShowNotifications(false);
                          router.push(`/products/${encodeURIComponent(txn.product_id)}`);
                        }
                      }}
                      className="p-3 rounded-xl border border-slate-200 dark:border-white/5 bg-slate-50 dark:bg-white/[0.01] hover:bg-slate-100 dark:hover:bg-white/[0.03] cursor-pointer transition flex items-center gap-3"
                    >
                      <div
                        className={`w-8 h-8 rounded-lg flex items-center justify-center text-xs font-bold ${
                          isIn
                            ? 'bg-emerald-500/10 text-emerald-500'
                            : 'bg-red-500/10 text-red-500'
                        }`}
                      >
                        {isIn ? '📥' : '📤'}
                      </div>
                      <div className="min-w-0 flex-1">
                        <p className="text-xs font-bold text-slate-800 dark:text-white truncate">
                          {txn.product_name}
                        </p>
                        <p className="text-[10px] text-slate-400 dark:text-gray-500 mt-0.5">
                          {isIn ? 'Stock In' : 'Stock Out'} of {txn.quantity} · By {txn.worker_name}
                        </p>
                      </div>
                      <div className="text-right text-[9px] text-slate-400 dark:text-gray-500 flex-shrink-0">
                        {new Date(txn.created_at).toLocaleDateString('en-IN', {
                          day: '2-digit',
                          month: 'short',
                        })}
                      </div>
                    </div>
                  );
                })
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
