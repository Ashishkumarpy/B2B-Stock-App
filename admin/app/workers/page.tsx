'use client';

import { useState, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { serverDelete, serverGet, serverPost, ServerApiError } from '../../lib/server_api';
import { useRequireAuth } from '../../lib/use_require_auth';

interface Transaction {
  id: string;
  type: 'stock_in' | 'stock_out';
  quantity: number;
  worker_name: string;
  created_at: string;
}

interface Worker {
  id: string;
  name: string;
  email?: string;
  phone?: string;
  created_at: string;
}

interface WorkerSummary {
  id: string;
  name: string;
  transactions: number;
  stockIn: number;
  stockOut: number;
  lastActive: string;
}

export default function WorkersPage() {
  useRequireAuth();
  const router = useRouter();
  const [workers, setWorkers] = useState<Worker[]>([]);
  const [transactions, setTransactions] = useState<Transaction[]>([]);
  const [loading, setLoading] = useState(true);
  const [showModal, setShowModal] = useState(false);
  const [newWorker, setNewWorker] = useState({ name: '', phone: '', email: '' });

  useEffect(() => {
    const fetchWorkersAndTx = async () => {
      try {
        const [wRes, tRes] = await Promise.all([
          serverGet('/workers'),
          serverGet('/transactions'),
        ]);
        setWorkers(((wRes as any).data ?? []) as Worker[]);
        setTransactions(((tRes as any).data ?? []) as Transaction[]);
      } catch (e) {
        if (e instanceof ServerApiError && e.status === 401) {
          router.push('/login');
          return;
        }
        console.error(e);
      }
      setLoading(false);
    };
    fetchWorkersAndTx();
  }, [router]);

  const handleAddWorker = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!newWorker.name.trim()) return;
    try {
      await serverPost('/workers', { ...newWorker });
      setNewWorker({ name: '', phone: '', email: '' });
      setShowModal(false);
    } catch (error) {
      alert('Failed to add worker');
    }
  };

  const handleDeleteWorker = async (id: string) => {
    if (!confirm('Remove this worker?')) return;
    await serverDelete(`/workers/${id}`);
  };

  // Aggregate per worker
  const workerSummaries: WorkerSummary[] = workers.map(worker => {
    const workerTx = transactions.filter(t => t.worker_name === worker.name);
    return {
      id: worker.id,
      name: worker.name,
      transactions: workerTx.length,
      stockIn: workerTx.filter(t => t.type === 'stock_in').reduce((acc, t) => acc + t.quantity, 0),
      stockOut: workerTx.filter(t => t.type === 'stock_out').reduce((acc, t) => acc + t.quantity, 0),
      lastActive: workerTx.length > 0 ? workerTx.sort((a, b) => b.created_at.localeCompare(a.created_at))[0].created_at : worker.created_at
    };
  }).sort((a, b) => b.transactions - a.transactions);

  return (
    <div className="space-y-8">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold">Worker Activity</h1>
          <p className="text-gray-500 text-sm mt-1">Management and real-time operations</p>
        </div>
        <button 
          onClick={() => setShowModal(true)}
          className="bg-indigo-600 hover:bg-indigo-500 text-white text-sm font-semibold px-4 py-2.5 rounded-xl transition"
        >
          + Add Worker
        </button>
      </div>

      {loading ? (
        <div className="text-center text-gray-500 text-sm py-12">Loading activity…</div>
      ) : workerSummaries.length === 0 ? (
        <div className="card p-10 text-center text-gray-500 text-sm">
          No workers added yet.
        </div>
      ) : (
        <div className="grid sm:grid-cols-2 lg:grid-cols-4 gap-4">
          {workerSummaries.map((w) => (
            <div key={w.id} className="card p-5 space-y-4 group relative">
              <button 
                onClick={() => handleDeleteWorker(w.id)}
                className="absolute top-4 right-4 text-gray-600 hover:text-red-400 opacity-0 group-hover:opacity-100 transition-opacity"
              >
                ✕
              </button>
              <div className="flex items-center gap-3">
                <div className="w-10 h-10 rounded-full bg-indigo-600/30 flex items-center justify-center text-sm font-bold text-indigo-300 flex-shrink-0">
                  {w.name.charAt(0).toUpperCase()}
                </div>
                <div className="min-w-0">
                  <p className="text-sm font-semibold text-white truncate">{w.name}</p>
                  <p className="text-xs text-gray-500">{w.transactions} transaction{w.transactions !== 1 ? 's' : ''}</p>
                </div>
              </div>

              <div className="space-y-2">
                <div>
                  <div className="flex justify-between text-xs mb-1">
                    <span className="text-gray-500">Stock In</span>
                    <span className="text-emerald-400 font-mono">+{w.stockIn}</span>
                  </div>
                  <div className="h-1.5 bg-white/5 rounded-full overflow-hidden">
                    <div
                      className="h-full bg-emerald-500 rounded-full"
                      style={{ width: `${Math.min(100, (w.stockIn / Math.max(w.stockIn + w.stockOut, 1)) * 100)}%` }}
                    />
                  </div>
                </div>
                <div>
                  <div className="flex justify-between text-xs mb-1">
                    <span className="text-gray-500">Stock Out</span>
                    <span className="text-red-400 font-mono">-{w.stockOut}</span>
                  </div>
                  <div className="h-1.5 bg-white/5 rounded-full overflow-hidden">
                    <div
                      className="h-full bg-red-500 rounded-full"
                      style={{ width: `${Math.min(100, (w.stockOut / Math.max(w.stockIn + w.stockOut, 1)) * 100)}%` }}
                    />
                  </div>
                </div>
              </div>

              <p className="text-[10px] text-gray-600 uppercase tracking-widest">
                Last: {new Date(w.lastActive).toLocaleString('en-IN', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' })}
              </p>
            </div>
          ))}
        </div>
      )}

      {/* Add Worker Modal */}
      {showModal && (
        <div className="fixed inset-0 bg-black/70 backdrop-blur-sm z-50 flex items-center justify-center p-4">
          <div className="bg-[#0f1117] border border-white/10 rounded-2xl p-8 w-full max-w-md">
            <div className="flex items-center justify-between mb-6">
              <h2 className="text-xl font-bold">Add New Worker</h2>
              <button onClick={() => setShowModal(false)} className="text-gray-400 hover:text-white text-2xl leading-none">×</button>
            </div>
            <form onSubmit={handleAddWorker} className="space-y-4">
              <div>
                <label className="block text-xs text-gray-400 mb-1.5 uppercase tracking-wider">Full Name *</label>
                <input
                  type="text" required
                  value={newWorker.name}
                  onChange={(e) => setNewWorker({ ...newWorker, name: e.target.value })}
                  className="w-full bg-white/5 border border-white/10 rounded-lg px-3 py-2.5 text-sm text-white focus:outline-none focus:border-indigo-500"
                  placeholder="e.g. Rahul Singh"
                />
              </div>
              <div>
                <label className="block text-xs text-gray-400 mb-1.5 uppercase tracking-wider">Phone (Optional)</label>
                <input
                  type="tel"
                  value={newWorker.phone}
                  onChange={(e) => setNewWorker({ ...newWorker, phone: e.target.value })}
                  className="w-full bg-white/5 border border-white/10 rounded-lg px-3 py-2.5 text-sm text-white focus:outline-none focus:border-indigo-500"
                />
              </div>
              <div className="flex gap-3 pt-4">
                <button
                  type="submit"
                  className="flex-1 bg-indigo-600 hover:bg-indigo-500 text-white font-semibold py-3 rounded-xl transition"
                >
                  Add Worker
                </button>
                <button
                  type="button"
                  onClick={() => setShowModal(false)}
                  className="px-6 py-3 border border-white/10 rounded-xl text-sm text-gray-300 hover:bg-white/5 transition"
                >
                  Cancel
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
