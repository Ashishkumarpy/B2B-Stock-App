'use client';

import { useEffect, useState } from 'react';

interface TopBarProps {
  name: string;
  email: string;
  role: string;
  initials: string;
  onSignOut: () => void | Promise<void>;
}

export default function TopBar({ name, email, role, initials, onSignOut }: TopBarProps) {
  const [theme, setTheme] = useState<'light' | 'dark'>('dark');

  useEffect(() => {
    if (typeof window !== 'undefined') {
      const isDark = document.documentElement.classList.contains('dark');
      setTheme(isDark ? 'dark' : 'light');
    }
  }, []);

  const toggleTheme = () => {
    const isDark = document.documentElement.classList.contains('dark');
    if (isDark) {
      document.documentElement.classList.remove('dark');
      localStorage.setItem('theme', 'light');
      setTheme('light');
    } else {
      document.documentElement.classList.add('dark');
      localStorage.setItem('theme', 'dark');
      setTheme('dark');
    }
  };

  return (
    <header className="sticky top-0 z-40 flex items-center justify-between px-6 h-14 border-b border-slate-200 dark:border-white/5 bg-white/80 dark:bg-[#0a0a0f]/80 backdrop-blur-md text-slate-800 dark:text-white">
      <p className="text-sm text-slate-500 dark:text-gray-400">
        {new Date().toLocaleDateString('en-IN', {
          weekday: 'long',
          year: 'numeric',
          month: 'long',
          day: 'numeric',
        })}
      </p>
      <div className="flex items-center gap-3">
        <div className="hidden text-right md:block">
          <p className="text-sm font-semibold text-slate-800 dark:text-gray-200">{name}</p>
          <p className="text-[11px] uppercase tracking-wider text-slate-400 dark:text-gray-500">
            {role}
            {email ? ` · ${email}` : ''}
          </p>
        </div>
        <div className="w-8 h-8 rounded-full bg-indigo-600 flex items-center justify-center text-xs font-bold text-white shadow-sm">
          {initials}
        </div>
        <button
          type="button"
          onClick={toggleTheme}
          className="rounded-lg border border-slate-200 dark:border-white/10 p-1.5 text-xs font-medium text-slate-600 dark:text-gray-300 hover:bg-slate-100 dark:hover:bg-white/5 hover:text-slate-900 dark:hover:text-white transition flex items-center justify-center"
          title="Toggle Theme"
        >
          {theme === 'dark' ? '☀️' : '🌙'}
        </button>
        <button
          type="button"
          onClick={onSignOut}
          className="rounded-lg border border-slate-200 dark:border-white/10 px-3 py-1.5 text-xs font-medium text-slate-600 dark:text-gray-300 transition hover:bg-slate-100 dark:hover:bg-white/5 hover:text-slate-950 dark:hover:text-white"
        >
          Sign Out
        </button>
      </div>
    </header>
  );
}
