'use client';
import Link from 'next/link';
import { usePathname } from 'next/navigation';

const nav = [
  { href: '/',               icon: '🏠', label: 'Dashboard' },
  { href: '/products',       icon: '📦', label: 'Products' },
  { href: '/stock',          icon: '📥', label: 'Stock Entries' },
  { href: '/analytics',      icon: '📊', label: 'Analytics' },
  { href: '/orders',         icon: '🛒', label: 'Orders' },
  { href: '/users',          icon: '👥', label: 'Users' },
  { href: '/workers',        icon: '👷', label: 'Worker Activity' },
  { href: '/warehouses',     icon: '🏬', label: 'Warehouses' },
  { href: '/server',         icon: '🔗', label: 'Server' },
];

export default function Sidebar() {
  const pathname = usePathname();

  return (
    <aside className="sidebar hidden md:flex flex-col sticky top-0 h-screen">
      {/* Logo */}
      <div className="border-b border-slate-200 px-3 py-4 text-center dark:border-white/5 xl:px-6 xl:py-5 xl:text-left">
        <span className="text-lg font-bold gradient-text xl:text-xl">
          <span className="xl:hidden">B2B</span>
          <span className="hidden xl:inline">B2B Stock</span>
        </span>
        <p className="mt-0.5 hidden text-xs text-slate-400 dark:text-gray-500 xl:block">Admin Panel</p>
      </div>

      {/* Nav */}
      <nav className="flex-1 px-3 py-4 space-y-1 overflow-y-auto">
        {nav.map((item) => {
          const active = pathname === item.href;
          return (
            <Link
              key={item.href}
              href={item.href}
              title={item.label}
              className={`flex min-h-11 items-center justify-center gap-3 rounded-xl border px-3 py-2.5 text-sm font-medium transition-all xl:justify-start ${
                active
                  ? 'bg-indigo-600/10 dark:bg-indigo-600/20 text-indigo-600 dark:text-indigo-300 border-indigo-500/20'
                  : 'text-slate-600 dark:text-gray-400 hover:text-slate-900 dark:hover:text-white hover:bg-slate-100 dark:hover:bg-white/5 border-transparent'
              }`}
            >
              <span className="text-base leading-none">{item.icon}</span>
              <span className="hidden xl:inline">{item.label}</span>
            </Link>
          );
        })}
      </nav>

      {/* Footer */}
      <div className="hidden px-4 py-4 border-t border-slate-200 dark:border-white/5 text-xs text-slate-400 dark:text-gray-600 xl:block">
        v1.0.0 · Private
      </div>
    </aside>
  );
}
