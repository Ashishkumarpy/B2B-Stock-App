'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';

import { getServerBaseUrl } from '../../lib/server_api';

function normalizeUrl(input: string) {
  const trimmed = input.trim();
  if (!trimmed) return '';
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) return trimmed;
  return `http://${trimmed}`;
}

export default function ServerPage() {
  const initial = useMemo(() => getServerBaseUrl(), []);
  const [value, setValue] = useState(initial);
  const [status, setStatus] = useState<'idle' | 'testing' | 'ok' | 'error'>('idle');
  const [message, setMessage] = useState<string>('');

  useEffect(() => {
    setValue(initial);
  }, [initial]);

  const testConnection = useCallback(async (url: string) => {
    const u = normalizeUrl(url);
    if (!u) {
      setStatus('error');
      setMessage('Please enter a server URL.');
      return false;
    }

    setStatus('testing');
    setMessage('');
    try {
      const res = await fetch(`${u}/health`, { credentials: 'include' });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      setStatus('ok');
      setMessage('Connected successfully.');
      return true;
    } catch (e) {
      const m = e instanceof Error ? e.message : String(e);
      setStatus('error');
      setMessage(`Cannot reach server: ${m}`);
      return false;
    }
  }, []);

  const onSave = useCallback(async () => {
    const u = normalizeUrl(value);
    const ok = await testConnection(u);
    if (!ok) return;
    window.localStorage.setItem('server_base_url', u);
    setMessage('Saved. You can go back to Products.');
  }, [testConnection, value]);

  return (
    <div className="mx-auto max-w-2xl px-4 py-8">
      <h1 className="text-2xl font-bold">Server</h1>
      <p className="mt-1 text-sm text-slate-400 dark:text-gray-500">
        Set your PC IP + port 8080. Example: <span className="font-mono">http://192.168.0.6:8080</span>
      </p>

      <div className="mt-6 rounded-2xl border border-slate-200 dark:border-white/10 bg-slate-100 dark:bg-white/5 p-4">
        <label className="text-sm font-medium text-slate-700 dark:text-gray-200">Server URL</label>
        <div className="mt-2 flex flex-col gap-3 sm:flex-row">
          <input
            value={value}
            onChange={(e) => setValue(e.target.value)}
            placeholder="http://192.168.0.6:8080"
            className="w-full rounded-xl border border-slate-200 dark:border-white/10 bg-slate-100 dark:bg-black/20 px-3 py-2 text-sm text-white outline-none focus:border-indigo-500/50"
          />
          <button
            onClick={() => testConnection(value)}
            disabled={status === 'testing'}
            className="rounded-xl border border-slate-200 dark:border-white/10 bg-slate-100 dark:bg-white/5 px-4 py-2 text-sm font-medium text-white hover:bg-slate-200 dark:hover:bg-white/10 disabled:opacity-60"
          >
            {status === 'testing' ? 'Testing…' : 'Test'}
          </button>
          <button
            onClick={onSave}
            disabled={status === 'testing'}
            className="rounded-xl bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-500 disabled:opacity-60"
          >
            Save
          </button>
        </div>

        {message ? (
          <div
            className={`mt-3 rounded-xl px-3 py-2 text-sm ${
              status === 'ok'
                ? 'bg-emerald-500/10 text-emerald-300'
                : status === 'error'
                  ? 'bg-rose-500/10 text-rose-300'
                  : 'bg-slate-100 dark:bg-white/5 text-slate-600 dark:text-gray-300'
            }`}
          >
            {message}
          </div>
        ) : null}
      </div>
    </div>
  );
}

