'use client';

import { useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { serverGet, ServerApiError } from './server_api';

export function useRequireAuth() {
  const router = useRouter();

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        await serverGet('/auth/me');
      } catch (e) {
        if (!cancelled && e instanceof ServerApiError && e.status === 401) {
          router.push('/login');
        }
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [router]);
}

