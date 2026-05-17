'use client';

import { useEffect, useState } from 'react';
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
  stock_status: string;
}

export default function DashboardPage() {
  useRequireAuth();
  const router = useRouter();
  const [transactions, setTransactions] = useState<Transaction[]>([]);
  const [products, setProducts] = useState<Product[]>([]);
  const [pendingOrdersCount, setPendingOrdersCount] = useState<number | '...'>('...');
  const [loadingTx, setLoadingTx] = useState(true);
  const [loadingProducts, setLoadingProducts] = useState(true);

  const fetchTransactions = async () => {
    try {
      const res = await serverGet('/transactions');
      const all = ((res as any).data ?? []) as Transaction[];
      setTransactions(all.slice(0, 10));
    } catch (e) {
      if (e instanceof ServerApiError && e.status === 401) {
        router.push('/login');
        return;
      }
      console.error('Failed to fetch transactions:', e);
    }
    setLoadingTx(false);
  };

  useEffect(() => {
    fetchTransactions();

    const channel = supabase
      .channel('dashboard_transactions')
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'transactions' },
        () => fetchTransactions()
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [router]);

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

  useEffect(() => {
    fetchProducts();

    const channel = supabase
      .channel('dashboard_products')
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'products' },
        () => fetchProducts()
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [router]);

  const fetchOrders = async () => {
    try {
      const res = await serverGet('/orders');
      const all = ((res as any).data ?? []) as Array<{ status: string }>;
      setPendingOrdersCount(all.filter((o) => o.status === 'pending').length);
    } catch (e) {
      if (e instanceof ServerApiError && e.status === 401) {
        router.push('/login');
        return;
      }
      console.error('Failed to fetch pending orders:', e);
    }
  };

  useEffect(() => {
    fetchOrders();

    const channel = supabase
      .channel('dashboard_orders')
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'orders' },
        () => fetchOrders()
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [router]);

  const totalProducts = products.length;
  const lowStockAlerts = products.filter(
    (product) => product.stock_status === 'low_stock' || product.stock_status === 'out_of_stock'
  ).length;

  const activeWorkers = new Set(transactions.map((transaction) => transaction.worker_name)).size;

  const stats = [
    { label: 'Total Products', value: loadingProducts ? '...' : String(totalProducts), accent: 'stat-indigo', icon: '[]' },
    { label: 'Low Stock Alerts', value: loadingProducts ? '...' : String(lowStockAlerts), accent: 'stat-yellow', icon: '!' },
    { label: 'Pending Orders', value: String(pendingOrdersCount), accent: 'stat-sky', icon: 'Cart' },
    { label: 'Active Workers', value: loadingTx ? '...' : String(activeWorkers), accent: 'stat-emerald', icon: 'Team' },
  ];

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-2xl font-bold">Dashboard</h1>
        <p className="mt-1 text-sm text-gray-500">Overview of your B2B Stock platform</p>
      </div>

      <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        {stats.map((stat) => (
          <div key={stat.label} className={`card ${stat.accent} p-5`}>
            <p className="mb-3 text-lg">{stat.icon}</p>
            <p className="text-2xl font-bold text-white">{stat.value}</p>
            <p className="mt-1 text-xs text-gray-500">{stat.label}</p>
          </div>
        ))}
      </div>

      <div className="grid gap-3 sm:grid-cols-3">
        {[
          { label: 'Add Product', href: '/products' },
          { label: 'Record Stock', href: '/stock' },
          { label: 'View Analytics', href: '/analytics' },
        ].map((action) => (
          <a
            key={action.label}
            href={action.href}
            className="card flex items-center gap-3 p-4 transition-all hover:border-indigo-500/30"
          >
            <span className="text-sm font-medium text-gray-300">{action.label}</span>
          </a>
        ))}
      </div>

      <div className="card overflow-hidden">
        <div className="border-b border-white/5 px-6 py-4">
          <h2 className="text-sm font-semibold">Recent Activity</h2>
        </div>

        {loadingTx ? (
          <div className="p-10 text-center text-sm text-gray-500">Loading activity...</div>
        ) : transactions.length === 0 ? (
          <div className="p-10 text-center text-sm text-gray-500">
            No activity yet.{' '}
            <a href="/stock" className="text-indigo-400 hover:underline">
              Record your first stock movement {'->'}
            </a>
          </div>
        ) : (
          <table className="data-table w-full text-sm">
            <thead>
              <tr>
                <th className="text-left">Time</th>
                <th className="text-left">Worker</th>
                <th className="text-left">Action</th>
                <th className="text-left">Product</th>
                <th className="text-right">Qty</th>
              </tr>
            </thead>
            <tbody>
              {transactions.map((transaction) => (
                <tr key={transaction.id}>
                  <td className="text-xs text-gray-500">
                    {new Date(transaction.created_at).toLocaleString('en-IN', {
                      hour: '2-digit',
                      minute: '2-digit',
                      day: '2-digit',
                      month: 'short',
                    })}
                  </td>
                  <td className="font-medium text-white">{transaction.worker_name}</td>
                  <td>
                    <span className={`badge ${transaction.type === 'stock_in' ? 'badge-green' : 'badge-red'}`}>
                      {transaction.type === 'stock_in' ? 'Stock In' : 'Stock Out'}
                    </span>
                  </td>
                  <td className="max-w-[220px]">
                    <button
                      type="button"
                      onClick={() => {
                        if (!transaction.product_id) return;
                        router.push(`/products?productId=${encodeURIComponent(transaction.product_id)}`);
                      }}
                      disabled={!transaction.product_id}
                      className={`max-w-[220px] truncate text-left ${
                        transaction.product_id ? 'text-indigo-300 hover:underline' : 'text-gray-400'
                      }`}
                    >
                      {transaction.product_name}
                    </button>
                    <div className="text-[11px] text-gray-500">
                      {transaction.product_code || '-'}
                      {transaction.color_name ? ` | ${transaction.color_name}` : ''}
                      {transaction.warehouse_name ? ` | ${transaction.warehouse_name}` : ''}
                    </div>
                  </td>
                  <td
                    className={`text-right font-mono font-semibold ${
                      transaction.type === 'stock_in' ? 'text-emerald-400' : 'text-red-400'
                    }`}
                  >
                    {transaction.type === 'stock_in' ? '+' : '-'}
                    {transaction.quantity}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
}
