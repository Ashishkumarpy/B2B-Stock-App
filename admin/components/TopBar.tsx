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
  const [theme, setTheme] = useState<'light' | 'dark' | 'system'>(() => {
    if (typeof window === 'undefined') return 'system';
    const savedTheme = localStorage.getItem('theme');
    return savedTheme === 'light' || savedTheme === 'dark' || savedTheme === 'system'
      ? savedTheme
      : 'system';
  });

  useEffect(() => {
    if (typeof window !== 'undefined') {
      const mediaQuery = window.matchMedia('(prefers-color-scheme: dark)');
      const handleChange = () => {
        const activeTheme = localStorage.getItem('theme') || 'system';
        if (activeTheme === 'system') {
          if (mediaQuery.matches) {
            document.documentElement.classList.add('dark');
          } else {
            document.documentElement.classList.remove('dark');
          }
        }
      };

      mediaQuery.addEventListener('change', handleChange);
      return () => {
        mediaQuery.removeEventListener('change', handleChange);
      };
    }
  }, []);

  const toggleTheme = () => {
    let nextTheme: 'light' | 'dark' | 'system';
    if (theme === 'system') {
      nextTheme = 'light';
    } else if (theme === 'light') {
      nextTheme = 'dark';
    } else {
      nextTheme = 'system';
    }

    setTheme(nextTheme);
    localStorage.setItem('theme', nextTheme);

    if (nextTheme === 'system') {
      const mediaQuery = window.matchMedia('(prefers-color-scheme: dark)');
      if (mediaQuery.matches) {
        document.documentElement.classList.add('dark');
      } else {
        document.documentElement.classList.remove('dark');
      }
    } else if (nextTheme === 'dark') {
      document.documentElement.classList.add('dark');
    } else {
      document.documentElement.classList.remove('dark');
    }
  };

  return (
    <header className="sticky top-0 z-40 flex min-w-0 items-center justify-between gap-3 border-b border-slate-200 bg-white/80 px-3 h-14 text-slate-800 backdrop-blur-md dark:border-white/5 dark:bg-[#0a0a0f]/80 dark:text-white sm:px-4 xl:px-6">
      <p className="hidden truncate text-sm text-slate-500 dark:text-gray-400 lg:block">
        {new Date().toLocaleDateString('en-IN', {
          weekday: 'long',
          year: 'numeric',
          month: 'long',
          day: 'numeric',
        })}
      </p>
      <div className="flex min-w-0 flex-1 items-center justify-end gap-2 xl:gap-3">
        <div className="hidden min-w-0 text-right xl:block">
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
          className="flex min-h-9 items-center gap-1.5 rounded-lg border border-slate-200 px-2.5 py-1.5 text-xs font-medium text-slate-600 transition hover:bg-slate-100 hover:text-slate-900 dark:border-white/10 dark:text-gray-300 dark:hover:bg-white/5 dark:hover:text-white"
          title="Toggle Theme"
        >
          {theme === 'light' && (
            <>
              <span>☀️</span>
              <span>Light</span>
            </>
          )}
          {theme === 'dark' && (
            <>
              <span>🌙</span>
              <span>Dark</span>
            </>
          )}
          {theme === 'system' && (
            <>
              <span>🖥️</span>
              <span>Auto</span>
            </>
          )}
        </button>
        <button
          type="button"
          onClick={onSignOut}
          className="min-h-9 rounded-lg border border-slate-200 px-3 py-1.5 text-xs font-medium text-slate-600 transition hover:bg-slate-100 hover:text-slate-900 dark:border-white/10 dark:text-gray-300 dark:hover:bg-white/5 dark:hover:text-white"
        >
          Sign Out
        </button>
      </div>
    </header>
  );
}
