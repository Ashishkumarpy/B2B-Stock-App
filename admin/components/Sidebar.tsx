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
      <div className="px-6 py-5 border-b border-white/5">
        <span className="text-xl font-bold gradient-text">B2B Stock</span>
        <p className="text-xs text-gray-500 mt-0.5">Admin Panel</p>
      </div>

      {/* Nav */}
      <nav className="flex-1 px-3 py-4 space-y-1 overflow-y-auto">
        {nav.map((item) => {
          const active = pathname === item.href;
          return (
            <Link
              key={item.href}
              href={item.href}
              className={`flex items-center gap-3 px-3 py-2.5 rounded-xl text-sm font-medium transition-all ${
                active
                  ? 'bg-indigo-600/20 text-indigo-300 border border-indigo-500/20'
                  : 'text-gray-400 hover:text-white hover:bg-white/5'
              }`}
            >
              <span className="text-base">{item.icon}</span>
              {item.label}
            </Link>
          );
        })}
      </nav>

      {/* Footer */}
      <div className="px-4 py-4 border-t border-white/5 text-xs text-gray-600">
        v1.0.0 · Private
      </div>
    </aside>
  );
}
