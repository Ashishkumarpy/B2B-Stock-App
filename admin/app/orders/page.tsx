'use client';

import { useState, useEffect } from 'react';
import Image from 'next/image';
import { useRouter } from 'next/navigation';
import { serverGet, serverPatch, ServerApiError } from '../../lib/server_api';
import { useRequireAuth } from '../../lib/use_require_auth';
import { supabase } from '../../lib/supabase';

interface Order {
  id: string;
  customer_name: string;
  company_name: string;
  email: string;
  phone: string;
  total: number;
  status: 'pending' | 'confirmed' | 'shipped' | 'delivered' | 'cancelled';
  created_at: string;
  items: Array<{
    name: string;
    quantity: number;
    price: number;
  }>;
  branding?: {
    logoUrl?: string;
    notes?: string;
  };
}

const statusCls: Record<string, string> = {
  pending:   'badge-yellow',
  confirmed: 'badge-blue',
  shipped:   'badge-blue',
  delivered: 'badge-green',
  cancelled: 'badge-red',
};

export default function OrdersPage() {
  useRequireAuth();
  const router = useRouter();
  const [orders, setOrders] = useState<Order[]>([]);
  const [loading, setLoading] = useState(true);
  const [selectedOrder, setSelectedOrder] = useState<Order | null>(null);

  const fetchOrders = async () => {
    try {
      const res = await serverGet('/orders');
      setOrders(((res as any).data ?? []) as Order[]);
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
    fetchOrders();

    const channel = supabase
      .channel('public:orders')
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'orders' },
        () => {
          fetchOrders();
        }
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [router]);

  const updateStatus = async (orderId: string, newStatus: string) => {
    try {
      await serverPatch(`/orders/${orderId}`, { status: newStatus });
      if (selectedOrder?.id === orderId) {
        setSelectedOrder({ ...selectedOrder, status: newStatus as any });
      }
    } catch (error) {
      alert('Failed to update status');
    }
  };

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold">Orders</h1>
          <p className="text-slate-400 dark:text-gray-500 text-sm mt-1">{orders.length} orders total</p>
        </div>
      </div>

      <div className="card overflow-hidden">
        {loading ? (
          <div className="p-12 text-center text-slate-400 dark:text-gray-500 text-sm">Loading orders…</div>
        ) : orders.length === 0 ? (
          <div className="p-12 text-center text-slate-400 dark:text-gray-500 text-sm">No orders received yet.</div>
        ) : (
          <table className="data-table w-full text-sm">
            <thead>
              <tr>
                <th className="text-left">Order ID</th>
                <th className="text-left">Customer</th>
                <th className="text-right">Items</th>
                <th className="text-right">Total</th>
                <th className="text-left">Status</th>
                <th className="text-left">Date</th>
                <th className="text-left">Actions</th>
              </tr>
            </thead>
            <tbody>
              {orders.map((o) => (
                <tr key={o.id}>
                  <td className="font-mono text-xs text-indigo-400">#{o.id.slice(-6).toUpperCase()}</td>
                  <td>
                    <div className="text-white font-medium">{o.customer_name}</div>
                    <div className="text-xs text-slate-400 dark:text-gray-500">{o.company_name}</div>
                  </td>
                  <td className="text-right font-mono">{o.items.length}</td>
                  <td className="text-right font-semibold">₹{o.total.toLocaleString()}</td>
                  <td>
                    <select 
                      value={o.status} 
                      onChange={(e) => updateStatus(o.id, e.target.value)}
                      className={`bg-transparent border-none text-xs focus:ring-0 cursor-pointer ${statusCls[o.status]}`}
                    >
                      <option value="pending" className="bg-white dark:bg-[#0f1117] text-white">Pending</option>
                      <option value="confirmed" className="bg-white dark:bg-[#0f1117] text-white">Confirmed</option>
                      <option value="shipped" className="bg-white dark:bg-[#0f1117] text-white">Shipped</option>
                      <option value="delivered" className="bg-white dark:bg-[#0f1117] text-white">Delivered</option>
                      <option value="cancelled" className="bg-white dark:bg-[#0f1117] text-white">Cancelled</option>
                    </select>
                  </td>
                  <td className="text-slate-400 dark:text-gray-500 text-xs">
                    {new Date(o.created_at).toLocaleDateString('en-IN', { day: '2-digit', month: 'short' })}
                  </td>
                  <td>
                    <button 
                      onClick={() => setSelectedOrder(o)}
                      className="text-indigo-400 hover:text-indigo-300 font-medium text-xs"
                    >
                      View Details
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      {/* Order Details Modal */}
      {selectedOrder && (
        <div className="fixed inset-0 bg-black/40 dark:bg-black/70 backdrop-blur-sm z-50 flex items-center justify-center p-4">
          <div className="bg-white dark:bg-[#0f1117] border border-slate-200 dark:border-white/10 rounded-2xl p-8 w-full max-w-3xl max-h-[90vh] overflow-y-auto">
            <div className="flex items-center justify-between mb-8 pb-4 border-b border-slate-200 dark:border-white/10">
              <div>
                <h2 className="text-xl font-bold">Order Details</h2>
                <p className="text-xs font-mono text-indigo-400 mt-1">ID: #{selectedOrder.id.toUpperCase()}</p>
              </div>
              <button onClick={() => setSelectedOrder(null)} className="text-slate-500 dark:text-gray-400 hover:text-white text-2xl leading-none">×</button>
            </div>

            <div className="grid md:grid-cols-3 gap-8 mb-8">
              <div className="md:col-span-1">
                <h3 className="text-[10px] text-slate-400 dark:text-gray-500 uppercase tracking-widest mb-3">Customer</h3>
                <p className="text-sm font-semibold text-white">{selectedOrder.customer_name}</p>
                <p className="text-xs text-slate-500 dark:text-gray-400 mt-1">{selectedOrder.company_name}</p>
                <p className="text-xs text-slate-500 dark:text-gray-400 mt-1">{selectedOrder.email}</p>
                <p className="text-xs text-slate-500 dark:text-gray-400 mt-1">{selectedOrder.phone}</p>
              </div>

              <div className="md:col-span-1">
                <h3 className="text-[10px] text-slate-400 dark:text-gray-500 uppercase tracking-widest mb-3">Branding</h3>
                {selectedOrder.branding?.logoUrl ? (
                  <div className="w-24 h-24 bg-slate-100 dark:bg-white/5 border border-slate-200 dark:border-white/10 rounded p-2 flex items-center justify-center mb-2">
                    <Image
                      src={selectedOrder.branding.logoUrl}
                      alt="Customer Logo"
                      width={80}
                      height={80}
                      className="max-w-full max-h-full object-contain"
                      sizes="80px"
                    />
                  </div>
                ) : (
                  <p className="text-xs text-slate-400 dark:text-gray-500 italic mb-2">No logo provided</p>
                )}
                {selectedOrder.branding?.notes && (
                  <div className="p-3 bg-slate-100 dark:bg-white/5 rounded border border-slate-200 dark:border-white/5">
                    <p className="text-[10px] text-slate-500 dark:text-gray-400 italic">"{selectedOrder.branding.notes}"</p>
                  </div>
                )}
              </div>

              <div className="md:col-span-1">
                <h3 className="text-[10px] text-slate-400 dark:text-gray-500 uppercase tracking-widest mb-3">Summary</h3>
                <div className="space-y-2">
                  <div className="flex justify-between text-xs">
                    <span className="text-slate-400 dark:text-gray-500">Status</span>
                    <span className={`badge ${statusCls[selectedOrder.status]}`}>{selectedOrder.status}</span>
                  </div>
                  <div className="flex justify-between text-xs">
                    <span className="text-slate-400 dark:text-gray-500">Date</span>
                    <span className="text-white">{new Date(selectedOrder.created_at).toLocaleString()}</span>
                  </div>
                  <div className="flex justify-between text-sm font-bold pt-2 border-t border-slate-200 dark:border-white/10">
                    <span className="text-slate-500 dark:text-gray-400">Total</span>
                    <span className="text-indigo-400">₹{selectedOrder.total.toLocaleString()}</span>
                  </div>
                </div>
              </div>
            </div>

            <h3 className="text-[10px] text-slate-400 dark:text-gray-500 uppercase tracking-widest mb-4">Order Items</h3>
            <div className="space-y-2 mb-8">
              {selectedOrder.items.map((item, idx) => (
                <div key={idx} className="flex items-center justify-between p-4 bg-white/3 border border-slate-200 dark:border-white/5 rounded-xl">
                  <div>
                    <div className="text-sm font-medium text-white">{item.name}</div>
                    <div className="text-xs text-slate-400 dark:text-gray-500 mt-0.5">₹{item.price.toLocaleString()} x {item.quantity}</div>
                  </div>
                  <div className="text-sm font-mono text-indigo-400">
                    ₹{(item.price * item.quantity).toLocaleString()}
                  </div>
                </div>
              ))}
            </div>

            <div className="flex gap-4">
              <button
                onClick={() => setSelectedOrder(null)}
                className="flex-1 px-6 py-3 border border-slate-200 dark:border-white/10 rounded-xl text-sm text-slate-600 dark:text-gray-300 hover:bg-slate-100 dark:hover:bg-white/5 transition"
              >
                Close Details
              </button>
              <a
                href={`mailto:${selectedOrder.email}?subject=Order Update - #${selectedOrder.id.slice(-6).toUpperCase()}`}
                className="flex-1 px-6 py-3 bg-indigo-600 hover:bg-indigo-500 text-white text-center rounded-xl text-sm font-semibold transition"
              >
                Email Customer
              </a>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
