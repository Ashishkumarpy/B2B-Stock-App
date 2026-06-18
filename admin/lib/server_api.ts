const DEFAULT_SERVER_BASE_URL =
  process.env.NEXT_PUBLIC_SERVER_BASE_URL ||
  (typeof window !== 'undefined' && !window.location.hostname.includes('localhost')
    ? 'https://zentory-api.onrender.com'
    : 'http://localhost:8080');

export function getServerBaseUrl() {
  if (typeof window === 'undefined') return DEFAULT_SERVER_BASE_URL;
  const stored = window.localStorage.getItem('server_base_url');
  return (stored || DEFAULT_SERVER_BASE_URL).trim();
}

export class ServerApiError extends Error {
  status: number;
  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

async function safeFetch(input: RequestInfo | URL, init?: RequestInit) {
  const SERVER_BASE_URL = getServerBaseUrl();

  // Inject Authorization header if token exists in localStorage
  if (typeof window !== 'undefined') {
    const token = window.localStorage.getItem('b2b_stock_token');
    if (token) {
      const headers = new Headers(init?.headers);
      headers.set('Authorization', `Bearer ${token}`);
      init = {
        ...init,
        headers
      };
    }
  }

  try {
    return await fetch(input, init);
  } catch (e) {
    const message =
      e instanceof Error
        ? e.message
        : 'Network error';
    throw new ServerApiError(0, `Cannot reach server (${SERVER_BASE_URL}): ${message}`);
  }
}

function clearAuth() {
  if (typeof window !== 'undefined') {
    window.localStorage.removeItem('b2b_stock_token');
    window.localStorage.removeItem('b2b_stock_refresh');
  }
}

// Single in-flight refresh shared across concurrent 401s.
let refreshPromise: Promise<boolean> | null = null;

async function tryRefresh(): Promise<boolean> {
  if (typeof window === 'undefined') return false;
  const refreshToken = window.localStorage.getItem('b2b_stock_refresh');
  if (!refreshToken) {
    clearAuth();
    return false;
  }
  if (!refreshPromise) {
    refreshPromise = (async () => {
      try {
        const SERVER_BASE_URL = getServerBaseUrl();
        const res = await fetch(`${SERVER_BASE_URL}/auth/refresh`, {
          method: 'POST',
          credentials: 'include',
          headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
          body: JSON.stringify({ refreshToken }),
        });
        if (!res.ok) {
          clearAuth();
          return false;
        }
        const data = await res.json();
        if (data?.token) {
          window.localStorage.setItem('b2b_stock_token', data.token);
          if (data.refreshToken) {
            window.localStorage.setItem('b2b_stock_refresh', data.refreshToken);
          }
          return true;
        }
        clearAuth();
        return false;
      } catch {
        clearAuth();
        return false;
      }
    })().finally(() => {
      refreshPromise = null;
    });
  }
  return refreshPromise;
}

// Runs a fetch, and on a 401 refreshes the access token and retries once.
async function requestWithRefresh(doFetch: () => Promise<Response>) {
  let res = await doFetch();
  if (res.status === 401) {
    const refreshed = await tryRefresh();
    if (refreshed) {
      res = await doFetch(); // safeFetch re-reads the new token from storage
    }
  }
  return decode(res);
}

async function decode(res: Response) {
  if (res.ok) {
    const text = await res.text();
    return text ? JSON.parse(text) : null;
  }
  let message = await res.text();
  try {
    const parsed = JSON.parse(message);
    if (parsed?.error) message = String(parsed.error);
  } catch {}
  throw new ServerApiError(res.status, message);
}

export async function serverGet(path: string) {
  const SERVER_BASE_URL = getServerBaseUrl();
  return requestWithRefresh(() =>
    safeFetch(`${SERVER_BASE_URL}${path}`, {
      method: 'GET',
      credentials: 'include',
      headers: { Accept: 'application/json' },
    })
  );
}

export async function serverPost(path: string, body: unknown) {
  const SERVER_BASE_URL = getServerBaseUrl();
  return requestWithRefresh(() =>
    safeFetch(`${SERVER_BASE_URL}${path}`, {
      method: 'POST',
      credentials: 'include',
      headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
      body: JSON.stringify(body),
    })
  );
}

export async function serverPut(path: string, body: unknown) {
  const SERVER_BASE_URL = getServerBaseUrl();
  return requestWithRefresh(() =>
    safeFetch(`${SERVER_BASE_URL}${path}`, {
      method: 'PUT',
      credentials: 'include',
      headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
      body: JSON.stringify(body),
    })
  );
}

export async function serverPatch(path: string, body: unknown) {
  const SERVER_BASE_URL = getServerBaseUrl();
  return requestWithRefresh(() =>
    safeFetch(`${SERVER_BASE_URL}${path}`, {
      method: 'PATCH',
      credentials: 'include',
      headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
      body: JSON.stringify(body),
    })
  );
}

export async function serverDelete(path: string) {
  const SERVER_BASE_URL = getServerBaseUrl();
  return requestWithRefresh(() =>
    safeFetch(`${SERVER_BASE_URL}${path}`, {
      method: 'DELETE',
      credentials: 'include',
      headers: { Accept: 'application/json' },
    })
  );
}

export async function serverUploadImage(file: File) {
  const SERVER_BASE_URL = getServerBaseUrl();
  const form = new FormData();
  form.append('file', file);
  return requestWithRefresh(() =>
    safeFetch(`${SERVER_BASE_URL}/uploads/image`, {
      method: 'POST',
      credentials: 'include',
      body: form,
    })
  ) as Promise<{ url: string; publicId: string }>;
}
