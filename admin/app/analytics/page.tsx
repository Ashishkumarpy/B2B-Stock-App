'use client';

import { useState, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { serverGet, ServerApiError } from '../../lib/server_api';
import { useRequireAuth } from '../../lib/use_require_auth';
import { supabase } from '../../lib/supabase';

interface Transaction {
  id: string;
  product_id?: string;
  type: 'stock_in' | 'stock_out';
  quantity: number;
  created_at: string;
}

interface Product {
  id: string;
  category: string;
  quantity: number;
  price: number;
  cost_price?: number;
  threshold?: number;
}

export default function AnalyticsPage() {
  useRequireAuth();
  const router = useRouter();
  const [transactions, setTransactions] = useState<Transaction[]>([]);
  const [products, setProducts] = useState<Product[]>([]);
  const [loading, setLoading] = useState(true);

  const fetchAnalytics = async () => {
    try {
      const [tRes, pRes] = await Promise.all([
        serverGet('/transactions'),
        serverGet('/products'),
      ]);
      setTransactions(((tRes as any).data ?? []) as Transaction[]);
      setProducts(((pRes as any).data ?? []) as Product[]);
    } catch (e) {
      if (e instanceof ServerApiError && e.status === 401) {
        router.push('/login');
        return;
      }
      console.error(e);
    }
    setLoading(false);
  };

  useEffect(() => {
    fetchAnalytics();

    const transactionsChannel = supabase
      .channel('analytics_transactions')
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'transactions' },
        () => fetchAnalytics()
      )
      .subscribe();

    const productsChannel = supabase
      .channel('analytics_products')
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'products' },
        () => fetchAnalytics()
      )
      .subscribe();

    return () => {
      supabase.removeChannel(transactionsChannel);
      supabase.removeChannel(productsChannel);
    };
  }, [router]);

  // 1. Category Breakdown
  const catMap: Record<string, number> = {};
  products.forEach(p => {
    catMap[p.category] = (catMap[p.category] || 0) + p.quantity;
  });
  const totalStock = products.reduce((acc, p) => acc + p.quantity, 0);
  const categoryData = Object.entries(catMap).map(([name, value], idx) => ({
    name,
    percentage: totalStock > 0 ? Math.round((value / totalStock) * 100) : 0,
    color: [`#6366f1`, `#8b5cf6`, `#38bdf8`, `#34d399`, `#fb923c`][idx % 5]
  })).sort((a, b) => b.percentage - a.percentage);

  // 2. Financial Value Metrics Calculations
  const totalPriceValue = products.reduce((acc, p) => acc + (Number(p.price) || 0) * (Number(p.quantity) || 0), 0);
  const inStockValue = products.reduce((acc, p) => p.quantity > 0 ? acc + (Number(p.price) || 0) * (Number(p.quantity) || 0) : acc, 0);
  const outStockValue = products.reduce((acc, p) => p.quantity === 0 ? acc + (Number(p.price) || 0) * (Number(p.threshold) || 10) : acc, 0);

  let estimatedRevenue = 0;
  transactions.forEach(t => {
    if (t.type === 'stock_out') {
      const prod = products.find(p => p.id === t.product_id);
      if (prod) {
        estimatedRevenue += t.quantity * prod.price;
      }
    }
  });

  // 3. Monthly Trends (Last 6 Months)
  const monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  const now = new Date();
  const monthlyTrend = Array.from({ length: 6 }).map((_, i) => {
    const d = new Date(now.getFullYear(), now.getMonth() - (5 - i), 1);
    return {
      month: monthNames[d.getMonth()],
      monthIdx: d.getMonth(),
      year: d.getFullYear(),
      in: 0,
      out: 0
    };
  });

  transactions.forEach(t => {
    const td = new Date(t.created_at);
    const mIdx = monthlyTrend.findIndex(m => m.monthIdx === td.getMonth() && m.year === td.getFullYear());
    if (mIdx !== -1) {
      if (t.type === 'stock_in') monthlyTrend[mIdx].in += t.quantity;
      else monthlyTrend[mIdx].out += t.quantity;
    }
  });

  const maxTrend = Math.max(...monthlyTrend.flatMap((m) => [m.in, m.out]), 1);

  // 4. Current Month Stats
  const currentMonth = monthlyTrend[5];

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-2xl font-bold">Analytics</h1>
        <p className="text-gray-500 text-sm mt-1">Live stock trends and category distribution</p>
      </div>

      {loading ? (
        <div className="p-12 text-center text-gray-500 text-sm">Loading analytics…</div>
      ) : (
        <>
          {/* Financial & Inventory Value Cards */}
          <div className="grid sm:grid-cols-2 lg:grid-cols-4 gap-4">
            {[
              { label: 'Total Price Value', value: `₹${totalPriceValue.toLocaleString('en-IN')}`, sub: 'Current retail inventory value', icon: '💰', border: 'stat-indigo' },
              { label: 'Estimated Revenue', value: `₹${estimatedRevenue.toLocaleString('en-IN')}`, sub: 'Revenue from stock dispatches', icon: '📈', border: 'stat-violet' },
              { label: 'In Stock Value', value: `₹${inStockValue.toLocaleString('en-IN')}`, sub: 'Active inventory value', icon: '🟢', border: 'stat-emerald' },
              { label: 'Out of Stock Value', value: `₹${outStockValue.toLocaleString('en-IN')}`, sub: 'Replenishment value (to threshold)', icon: '🔴', border: 'stat-sky' },
            ].map((s) => (
              <div key={s.label} className={`card p-5 hover:scale-[1.02] transition-transform duration-200 ${s.border}`}>
                <div className="flex justify-between items-start">
                  <div>
                    <p className="text-[10px] uppercase tracking-widest text-gray-500 font-semibold">{s.label}</p>
                    <p className="text-xl font-bold text-white mt-1">{s.value}</p>
                    <p className="text-[10px] text-gray-400 mt-2">{s.sub}</p>
                  </div>
                  <span className="text-2xl p-2 bg-white/5 rounded-xl">{s.icon}</span>
                </div>
              </div>
            ))}
          </div>

          <div className="grid lg:grid-cols-2 gap-6">
            {/* Monthly trend bar chart */}
            <div className="card p-6">
              <h2 className="font-semibold mb-6 text-sm text-gray-300">Monthly Stock Flow</h2>
              <div className="flex items-end gap-3 h-40">
                {monthlyTrend.map((m) => (
                  <div key={`${m.month}-${m.year}`} className="flex-1 flex flex-col items-center gap-1">
                    <div className="w-full flex gap-0.5 items-end" style={{ height: '120px' }}>
                      <div
                        className="flex-1 rounded-t bg-indigo-500/70 transition-all"
                        style={{ height: `${(m.in / maxTrend) * 100}%` }}
                        title={`In: ${m.in}`}
                      />
                      <div
                        className="flex-1 rounded-t bg-purple-500/40 transition-all"
                        style={{ height: `${(m.out / maxTrend) * 100}%` }}
                        title={`Out: ${m.out}`}
                      />
                    </div>
                    <span className="text-[10px] text-gray-500">{m.month}</span>
                  </div>
                ))}
              </div>
              <div className="flex gap-4 mt-4 text-xs text-gray-500">
                <span className="flex items-center gap-1"><span className="w-2 h-2 rounded-full bg-indigo-500 inline-block"/>Stock In</span>
                <span className="flex items-center gap-1"><span className="w-2 h-2 rounded-full bg-purple-500/60 inline-block"/>Stock Out</span>
              </div>
            </div>

            {/* Category breakdown */}
            <div className="card p-6">
              <h2 className="font-semibold mb-6 text-sm text-gray-300">Stock by Category (%)</h2>
              <div className="space-y-4">
                {categoryData.length === 0 ? (
                  <div className="text-gray-500 text-xs py-8 text-center">No categories found</div>
                ) : categoryData.map((c) => (
                  <div key={c.name}>
                    <div className="flex justify-between text-sm mb-1.5">
                      <span className="text-gray-300">{c.name}</span>
                      <span className="text-gray-500 font-mono text-xs">{c.percentage}%</span>
                    </div>
                    <div className="h-2 rounded-full bg-white/5 overflow-hidden">
                      <div
                        className="h-full rounded-full transition-all duration-500"
                        style={{ width: `${c.percentage}%`, background: c.color }}
                      />
                    </div>
                  </div>
                ))}
              </div>
            </div>
          </div>

          {/* Summary metrics */}
          <div className="grid sm:grid-cols-3 gap-4">
            {[
              { label: `Total Stock In (${currentMonth.month})`, value: `${currentMonth.in.toLocaleString()} units`, icon: '📈' },
              { label: `Total Stock Out (${currentMonth.month})`, value: `${currentMonth.out.toLocaleString()} units`, icon: '📉' },
              { label: 'Net Flow (Monthly)', value: `${(currentMonth.in - currentMonth.out) >= 0 ? '+' : ''}${(currentMonth.in - currentMonth.out).toLocaleString()} units`, icon: '🔄' },
            ].map((s) => (
              <div key={s.label} className="card p-5 text-center">
                <p className="text-3xl mb-2">{s.icon}</p>
                <p className="text-xl font-bold text-white">{s.value}</p>
                <p className="text-[10px] uppercase tracking-widest text-gray-500 mt-2">{s.label}</p>
              </div>
            ))}
          </div>
        </>
      )}
    </div>
  );
}
