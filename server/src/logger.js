import crypto from 'crypto';

export function requestId() {
  return crypto.randomUUID();
}

export function errorToObject(err) {
  if (!err) return undefined;
  if (err instanceof Error) {
    return {
      name: err.name,
      message: err.message,
      stack: err.stack
    };
  }
  return { message: String(err) };
}

function isPretty() {
  const format = (process.env.LOG_FORMAT || '').toLowerCase();
  if (format === 'pretty') return true;
  if (format === 'json') return false;
  return (process.env.NODE_ENV || 'development') !== 'production';
}

function color(code, s) {
  if (!process.stdout.isTTY) return s;
  return `\u001b[${code}m${s}\u001b[0m`;
}

function levelColor(level) {
  if (level === 'error') return (s) => color('31', s); // red
  if (level === 'warn') return (s) => color('33', s); // yellow
  return (s) => color('36', s); // cyan
}

function statusColor(status) {
  if (typeof status !== 'number') return (s) => s;
  if (status >= 500) return (s) => color('31', s);
  if (status >= 400) return (s) => color('33', s);
  if (status >= 300) return (s) => color('35', s);
  return (s) => color('32', s);
}

function fmtKeyVal(key, value) {
  if (value === undefined) return '';
  if (value === null) return `${key}=null`;
  if (typeof value === 'object') return `${key}=${JSON.stringify(value)}`;
  return `${key}=${String(value)}`;
}

function prettyLine(obj) {
  const ts = obj.ts ? String(obj.ts) : new Date().toISOString();
  const level = String(obj.level || 'info');
  const msg = String(obj.msg || '');
  const id = obj.id ? String(obj.id).slice(0, 8) : '';

  if (msg === 'http') {
    const method = String(obj.method || '');
    const path = String(obj.path || '');
    const status = typeof obj.status === 'number' ? obj.status : undefined;
    const ms = typeof obj.ms === 'number' ? `${obj.ms}ms` : undefined;
    const user = obj.user?.role ? `${obj.user.role}${obj.user.email ? `:${obj.user.email}` : ''}` : undefined;

    // On a rejected request, show the (unverified) claimed identity + reason,
    // e.g. authfail=expired:worker:jain556@gmail.com
    const af = obj.authFailure;
    const authFail = af
      ? [af.reason, af.role, af.email || af.phone || af.sub].filter(Boolean).join(':')
      : undefined;

    const lvl = levelColor(level)(level.toUpperCase().padEnd(5));
    const st = status !== undefined ? statusColor(status)(String(status)) : '';
    const base = `${ts} ${lvl} ${id ? `[${id}]` : ''} ${method} ${path} ${st} ${ms || ''}`.replace(
      /\s+/g,
      ' '
    );
    const extra = [fmtKeyVal('user', user), fmtKeyVal('authfail', authFail), fmtKeyVal('ip', obj.ip)]
      .filter(Boolean)
      .join(' ');
    return extra ? `${base} ${extra}` : base;
  }

  const lvl = levelColor(level)(level.toUpperCase().padEnd(5));
  const parts = [
    `${ts} ${lvl} ${id ? `[${id}]` : ''} ${msg}`.replace(/\s+/g, ' ').trim(),
    obj.path ? fmtKeyVal('path', obj.path) : '',
    obj.port ? fmtKeyVal('port', obj.port) : '',
    obj.error ? fmtKeyVal('error', obj.error) : ''
  ].filter(Boolean);
  return parts.join(' ');
}

export function log(obj) {
  const payload = {
    ts: new Date().toISOString(),
    ...obj
  };

  const line = isPretty() ? prettyLine(payload) : JSON.stringify(payload);
  // eslint-disable-next-line no-console
  console.log(line);
}
