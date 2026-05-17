const DEFAULT_SERVER_BASE_URL =
  process.env.NEXT_PUBLIC_SERVER_BASE_URL || 'http://localhost:8080';

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
  const res = await safeFetch(`${SERVER_BASE_URL}${path}`, {
    method: 'GET',
    credentials: 'include',
    headers: { Accept: 'application/json' },
  });
  return decode(res);
}

export async function serverPost(path: string, body: unknown) {
  const SERVER_BASE_URL = getServerBaseUrl();
  const res = await safeFetch(`${SERVER_BASE_URL}${path}`, {
    method: 'POST',
    credentials: 'include',
    headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
    body: JSON.stringify(body),
  });
  return decode(res);
}

export async function serverPut(path: string, body: unknown) {
  const SERVER_BASE_URL = getServerBaseUrl();
  const res = await safeFetch(`${SERVER_BASE_URL}${path}`, {
    method: 'PUT',
    credentials: 'include',
    headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
    body: JSON.stringify(body),
  });
  return decode(res);
}

export async function serverPatch(path: string, body: unknown) {
  const SERVER_BASE_URL = getServerBaseUrl();
  const res = await safeFetch(`${SERVER_BASE_URL}${path}`, {
    method: 'PATCH',
    credentials: 'include',
    headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
    body: JSON.stringify(body),
  });
  return decode(res);
}

export async function serverDelete(path: string) {
  const SERVER_BASE_URL = getServerBaseUrl();
  const res = await safeFetch(`${SERVER_BASE_URL}${path}`, {
    method: 'DELETE',
    credentials: 'include',
    headers: { Accept: 'application/json' },
  });
  return decode(res);
}

export async function serverUploadImage(file: File) {
  const SERVER_BASE_URL = getServerBaseUrl();
  const form = new FormData();
  form.append('file', file);
  const res = await safeFetch(`${SERVER_BASE_URL}/uploads/image`, {
    method: 'POST',
    credentials: 'include',
    body: form,
  });
  return decode(res) as Promise<{ url: string; publicId: string }>;
}
