'use client';

import { useEffect, useMemo, useState } from 'react';
import { usePathname, useRouter } from 'next/navigation';
import Sidebar from '@/components/Sidebar';
import TopBar from '@/components/TopBar';
import { serverGet, serverPost, ServerApiError } from '@/lib/server_api';
import {
  registerAdminPushNotifications,
  unregisterAdminPushNotifications
} from '@/lib/push_notifications';

type AdminRole = 'admin' | 'manager' | 'worker' | 'customer';

interface AdminProfile {
  sub: string;
  name: string;
  email: string;
  role: AdminRole;
}

interface AuthMeResponse {
  user?: AdminProfile;
}

function initialsFromName(name: string) {
  return name
    .split(' ')
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => part[0]?.toUpperCase() || '')
    .join('');
}

export default function AuthShell({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  const router = useRouter();
  const isLoginRoute = pathname === '/login';

  const [profile, setProfile] = useState<AdminProfile | null>(null);
  const [loading, setLoading] = useState(true);
  const [authError, setAuthError] = useState<string | null>(null);

  useEffect(() => {
    let active = true;

    const loadSession = async () => {
      setLoading(true);
      setAuthError(null);

      try {
        const res = (await serverGet('/auth/me')) as AuthMeResponse | null;
        const user = res?.user;
        if (!active) return;
        setProfile(user ?? null);
      } catch (e: unknown) {
        if (!active) return;
        if (e instanceof ServerApiError && e.status === 401) {
          setProfile(null);
        } else {
          const message = e instanceof Error ? e.message : String(e);
          setAuthError(message);
          setProfile(null);
        }
      } finally {
        if (active) setLoading(false);
      }
    };

    loadSession();

    return () => {
      active = false;
    };
  }, [isLoginRoute, router]);

  const isAuthorized = useMemo(
    () => profile?.role === 'admin' || profile?.role === 'manager',
    [profile]
  );

  useEffect(() => {
    if (loading) return;

    if (!profile && !isLoginRoute) {
      router.replace('/login');
      return;
    }

    if (profile && isLoginRoute && isAuthorized) {
      router.replace('/');
    }
  }, [isAuthorized, isLoginRoute, loading, profile, router]);

  useEffect(() => {
    if (!profile || !isAuthorized || isLoginRoute) return;
    registerAdminPushNotifications().catch(() => {});
  }, [isAuthorized, isLoginRoute, profile]);

  if (loading) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-slate-50 dark:bg-[#0a0a0f] text-slate-800 dark:text-white">
        <div className="rounded-2xl border border-slate-200 dark:border-white/10 bg-white dark:bg-white/[0.03] px-6 py-5 text-sm text-slate-600 dark:text-gray-300">
          Checking admin session...
        </div>
      </div>
    );
  }

  if (isLoginRoute) {
    if (profile && !isAuthorized) {
      return (
        <div className="flex min-h-screen items-center justify-center bg-slate-50 dark:bg-[#0a0a0f] p-6 text-slate-800 dark:text-white">
          <div className="w-full max-w-md rounded-3xl border border-red-500/20 bg-white dark:bg-[#11131a] p-8 shadow-sm">
            <h1 className="text-xl font-semibold">Access denied</h1>
            <p className="mt-3 text-sm text-gray-400">
              Your account is signed in, but it does not have admin dashboard access.
            </p>
            <p className="mt-2 text-sm text-gray-500">
              Ask for a `users.role` of `admin` or `manager` in Supabase.
            </p>
            {authError && <p className="mt-3 text-sm text-red-300">{authError}</p>}
            <button
              type="button"
                onClick={async () => {
                await unregisterAdminPushNotifications();
                try {
                  await serverPost('/auth/logout', {});
                } catch {}
                if (typeof window !== 'undefined') {
                  window.localStorage.removeItem('b2b_stock_token');
                }
                router.replace('/login');
              }}
              className="mt-6 rounded-xl border border-white/10 px-4 py-2 text-sm text-gray-300 transition hover:bg-white/5 hover:text-white"
            >
              Sign Out
            </button>
          </div>
        </div>
      );
    }

    return <>{children}</>;
  }

  if (!profile) return null;

  if (!isAuthorized) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-slate-50 dark:bg-[#0a0a0f] p-6 text-slate-800 dark:text-white">
        <div className="w-full max-w-md rounded-3xl border border-red-500/20 bg-white dark:bg-[#11131a] p-8 shadow-sm">
          <h1 className="text-xl font-semibold">Admin access required</h1>
          <p className="mt-3 text-sm text-gray-400">
            This dashboard only allows users with the `admin` or `manager` role.
          </p>
          <p className="mt-2 text-sm text-gray-500">
            If you see a permission error for `users`, your live Supabase policies for `public.users`
            still need to be applied.
          </p>
          {authError && <p className="mt-3 text-sm text-red-300">{authError}</p>}
          <button
            type="button"
              onClick={async () => {
              try {
                await serverPost('/auth/logout', {});
              } catch {}
              if (typeof window !== 'undefined') {
                window.localStorage.removeItem('b2b_stock_token');
              }
              router.replace('/login');
            }}
            className="mt-6 rounded-xl border border-white/10 px-4 py-2 text-sm text-gray-300 transition hover:bg-white/5 hover:text-white"
          >
            Sign Out
          </button>
        </div>
      </div>
    );
  }

  const name = profile?.name || profile?.email || 'Admin';
  const email = profile?.email || '';
  const initials = initialsFromName(name) || 'A';

  return (
    <div className="flex min-h-screen bg-slate-50 dark:bg-[#0a0a0f] text-slate-800 dark:text-white">
      <Sidebar />
      <div className="flex min-h-screen flex-1 flex-col overflow-hidden">
        <TopBar
          name={name}
          email={email}
          role={profile?.role || 'admin'}
          initials={initials}
          onSignOut={async () => {
            await unregisterAdminPushNotifications();
            try {
              await serverPost('/auth/logout', {});
            } catch {}
            if (typeof window !== 'undefined') {
              window.localStorage.removeItem('b2b_stock_token');
            }
            router.replace('/login');
          }}
        />
        <main className="flex-1 overflow-auto p-6">{children}</main>
      </div>
    </div>
  );
}
