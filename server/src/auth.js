import jwt from 'jsonwebtoken';
import { config } from './config.js';
import { supabaseAdmin, supabaseAuth } from './supabase.js';
import crypto from 'crypto';
import { sendWorkerOtpPush } from './notifications/push_service.js';

// Access token lifetime. Clients transparently rotate it via the refresh token,
// but that refresh needs the network at the right moment — if it fails (e.g. the
// device is offline across the expiry boundary) a short TTL hard-401s the user.
// Keep this generous so the refresh token is a safety net, not a daily single
// point of failure.
const ACCESS_TOKEN_TTL = '30d';
// Refresh token lifetime. Rotated (and its lifetime extended) on every use.
const REFRESH_TOKEN_TTL_MS = 90 * 24 * 60 * 60 * 1000;

export function signSession(payload) {
  return jwt.sign(payload, config.jwtSecret, { expiresIn: ACCESS_TOKEN_TTL });
}

export function verifySessionToken(token) {
  return jwt.verify(token, config.jwtSecret);
}

// Permission map baked into the access token. Exported so the refresh endpoint
// can rebuild a session identically to login.
export function sessionPermissions(user) {
  // Normalize so case/whitespace variants in the DB role column don't silently
  // collapse permission defaults to false.
  const role = String(user.role || '').trim().toLowerCase();
  const isAdmin = role === 'admin';
  const isManager = role === 'manager';
  const isWorker = role === 'worker';
  return {
    perm_products: user.perm_products ?? isAdmin,
    perm_inventory: user.perm_inventory ?? (isAdmin || isManager || isWorker),
    perm_orders: user.perm_orders ?? (isAdmin || isManager),
    perm_reports: user.perm_reports ?? (isAdmin || isManager),
    perm_users: user.perm_users ?? (isAdmin || isManager),
    perm_settings: user.perm_settings ?? isAdmin
  };
}

// Plain SHA-256 (no JWT secret) so refresh tokens survive secret rotation.
function hashRefreshToken(raw) {
  return crypto.createHash('sha256').update(String(raw)).digest('hex');
}

export async function issueRefreshToken(subjectId, role) {
  const raw = crypto.randomBytes(48).toString('hex');
  const expiresAt = new Date(Date.now() + REFRESH_TOKEN_TTL_MS);
  const { error } = await supabaseAdmin.from('refresh_tokens').insert({
    token_hash: hashRefreshToken(raw),
    subject_id: subjectId,
    role: role || null,
    expires_at: expiresAt.toISOString()
  });
  if (error) throw error;
  return { refreshToken: raw, expiresAt: expiresAt.toISOString() };
}

export async function revokeRefreshToken(rawToken) {
  if (!rawToken) return;
  await supabaseAdmin
    .from('refresh_tokens')
    .update({ revoked_at: new Date().toISOString() })
    .eq('token_hash', hashRefreshToken(rawToken))
    .is('revoked_at', null);
}

// Validate a refresh token and rotate it (revoke old, issue new). Returns the
// subject and a brand new refresh token.
export async function rotateRefreshToken(rawToken) {
  if (!rawToken) {
    const e = new Error('refresh token required');
    e.code = 'REFRESH_REQUIRED';
    throw e;
  }
  const { data: record, error } = await supabaseAdmin
    .from('refresh_tokens')
    .select('id, subject_id, role, expires_at, revoked_at')
    .eq('token_hash', hashRefreshToken(rawToken))
    .maybeSingle();
  if (error) throw error;
  if (!record || record.revoked_at) {
    const e = new Error('invalid refresh token');
    e.code = 'REFRESH_INVALID';
    throw e;
  }
  if (new Date(record.expires_at).getTime() < Date.now()) {
    const e = new Error('refresh token expired');
    e.code = 'REFRESH_EXPIRED';
    throw e;
  }

  await supabaseAdmin
    .from('refresh_tokens')
    .update({ revoked_at: new Date().toISOString() })
    .eq('id', record.id);

  const next = await issueRefreshToken(record.subject_id, record.role);
  return { subjectId: record.subject_id, role: record.role, ...next };
}

// Rebuild the access-token session payload for a subject id (mirrors the lookup
// order used by requirePermission: users by id, then workers by id/user_id).
export async function buildSessionForSubject(subjectId) {
  const { data: user, error } = await supabaseAdmin
    .from('users')
    .select('id,name,email,role,is_active,perm_products,perm_inventory,perm_orders,perm_reports,perm_users,perm_settings')
    .eq('id', subjectId)
    .maybeSingle();
  if (error) throw error;

  if (user) {
    if (user.is_active === false) {
      const e = new Error('account disabled');
      e.code = 'ACCOUNT_DISABLED';
      throw e;
    }
    return {
      sub: user.id,
      email: user.email || '',
      name: user.name,
      role: user.role,
      permissions: sessionPermissions(user)
    };
  }

  const { data: workers, error: workerErr } = await supabaseAdmin
    .from('workers')
    .select('id,user_id,name,email,phone,role,is_active,perm_products,perm_inventory,perm_orders,perm_reports,perm_users,perm_settings')
    .or(`id.eq.${subjectId},user_id.eq.${subjectId}`)
    .limit(1);
  if (workerErr) throw workerErr;
  const worker = workers && workers.length ? workers[0] : null;
  if (!worker) {
    const e = new Error('subject not found');
    e.code = 'SUBJECT_NOT_FOUND';
    throw e;
  }
  if (!worker.is_active) {
    const e = new Error('account disabled');
    e.code = 'ACCOUNT_DISABLED';
    throw e;
  }
  const role = worker.role === 'manager' ? 'manager' : 'worker';
  return {
    sub: worker.user_id || worker.id,
    email: worker.email || '',
    name: worker.name || 'Worker',
    phone: worker.phone || null,
    role,
    permissions: sessionPermissions({ ...worker, role })
  };
}

export function getTokenFromRequest(req) {
  const auth = req.headers.authorization;
  if (auth && auth.startsWith('Bearer ')) return auth.slice('Bearer '.length);
  const cookieToken = req.cookies?.[config.cookieName];
  return cookieToken || null;
}

// Decode a token WITHOUT verifying its signature/expiry. For diagnostics only
// (e.g. logging which user's stale token is being rejected) — never trusted for
// authorization.
function decodeClaimsUnverified(token) {
  try {
    const decoded = jwt.decode(token);
    if (decoded && typeof decoded === 'object') return decoded;
  } catch {
    /* malformed token — nothing to decode */
  }
  return null;
}

export async function authRequired(req, res, next) {
  const token = getTokenFromRequest(req);
  if (!token) {
    req.authFailure = { reason: 'missing_token' };
    return res.status(401).json({ error: 'Unauthorized' });
  }
  try {
    req.session = verifySessionToken(token);
    return next();
  } catch (err) {
    // Token rejected (expired or bad signature). Surface the claimed identity in
    // the request log so we can see *who* is hitting 401s, without trusting it.
    const claimed = decodeClaimsUnverified(token);
    req.authFailure = {
      reason: err && err.name === 'TokenExpiredError' ? 'expired' : 'invalid',
      sub: claimed?.sub,
      email: claimed?.email || undefined,
      phone: claimed?.phone || undefined,
      role: claimed?.role
    };
    return res.status(401).json({ error: 'Unauthorized' });
  }
}

export function requireRole(roles) {
  return (req, res, next) => {
    const role = req.session?.role;
    if (!role || !roles.includes(role)) {
      return res.status(403).json({ error: 'Forbidden' });
    }
    return next();
  };
}

function defaultPermissionsForRole(role) {
  if (role === 'admin') {
    return {
      perm_products: true,
      perm_inventory: true,
      perm_orders: true,
      perm_reports: true,
      perm_users: true,
      perm_settings: true
    };
  }
  if (role === 'manager') {
    return {
      perm_products: false,
      perm_inventory: true,
      perm_orders: true,
      perm_reports: true,
      perm_users: true,
      perm_settings: false
    };
  }
  return {
    perm_products: false,
    perm_inventory: true,
    perm_orders: false,
    perm_reports: false,
    perm_users: false,
    perm_settings: false
  };
}

function applyPermissionDefaults(user) {
  const defaults = defaultPermissionsForRole(user.role);
  for (const key of Object.keys(defaults)) {
    if (user[key] === undefined || user[key] === null) {
      user[key] = defaults[key];
    }
  }
  return user;
}

export function requirePermission(permission) {
  return async (req, res, next) => {
    try {
      const userId = req.session?.sub;
      if (!userId) return res.status(401).json({ error: 'Unauthorized' });

      let { data: user, error } = await supabaseAdmin
        .from('users')
        .select('role, is_active, perm_products, perm_inventory, perm_orders, perm_reports, perm_users, perm_settings')
        .eq('id', userId)
        .maybeSingle();

      if (error) {
        console.error('[requirePermission] Database query failed:', error.message, error.details || '');
        return res.status(401).json({ 
          error: 'User profile look up failed. Database schema may be outdated.' 
        });
      }

      if (!user) {
        // Fallback: Check if they are in the workers table (SMS OTP logins)
        const { data: worker, error: workerErr } = await supabaseAdmin
          .from('workers')
          .select('*')
          .eq('id', userId)
          .maybeSingle();

        if (workerErr || !worker) {
          return res.status(401).json({ 
            error: 'User/Worker profile not found.' 
          });
        }

        const isManager = worker.role === 'manager';
        user = {
          role: worker.role,
          is_active: worker.is_active ?? true,
          perm_products: worker.perm_products ?? false,
          perm_inventory: worker.perm_inventory ?? true,
          perm_orders: worker.perm_orders ?? isManager,
          perm_reports: worker.perm_reports ?? isManager,
          perm_users: worker.perm_users ?? isManager,
          perm_settings: worker.perm_settings ?? false
        };
      }

      user = applyPermissionDefaults(user);

      if (!user.is_active) {
        return res.status(403).json({ error: 'Account is disabled. Please contact admin.' });
      }

      if (user.role === 'admin') {
        return next();
      }

      if (!user[permission]) {
        return res.status(403).json({ error: `Forbidden: requires ${permission}` });
      }

      return next();
    } catch (e) {
      console.error('[requirePermission] Unhandled exception:', e);
      return res.status(500).json({ error: 'Permission check failed' });
    }
  };
}


export async function loginWithEmailPassword(email, password) {
  const { data, error } = await supabaseAuth.auth.signInWithPassword({ email, password });
  if (error) throw error;
  if (!data?.user) throw new Error('Auth failed');

  const { data: profile, error: profileError } = await supabaseAdmin
    .from('users')
    .select('id,name,email,role,created_at,perm_products,perm_inventory,perm_orders,perm_reports,perm_users,perm_settings')
    .eq('id', data.user.id)
    .maybeSingle();
  if (profileError) {
    const e = new Error(`Profile lookup failed: ${profileError.message}`);
    // @ts-ignore - attach a simple code for routing decisions
    e.code = 'PROFILE_LOOKUP_FAILED';
    throw e;
  }
  if (!profile) {
    const e = new Error('Profile not found');
    // @ts-ignore
    e.code = 'PROFILE_NOT_FOUND';
    throw e;
  }

  return { user: profile };
}

export function normalizePhone(phone) {
  const raw = String(phone || '').trim();
  if (!raw) return '';
  const keepPlus = raw.startsWith('+');
  const digits = raw.replace(/\D/g, '');
  return keepPlus ? `+${digits}` : digits;
}

function hashOtp(phone, otp) {
  return crypto
    .createHash('sha256')
    .update(`${phone}:${otp}:${config.jwtSecret}`)
    .digest('hex');
}

export async function requestWorkerOtp(phoneRaw, clientToken) {
  const phone = normalizePhone(phoneRaw);
  if (!phone) {
    const e = new Error('phone required');
    // @ts-ignore
    e.code = 'PHONE_REQUIRED';
    throw e;
  }

  const { data: worker, error: workerError } = await supabaseAdmin
    .from('workers')
    .select('id,name,phone,role,is_active,can_access_stock,perm_products,perm_inventory,perm_orders,perm_reports,perm_users,perm_settings')
    .eq('phone', phone)
    .maybeSingle();

  if (workerError) throw workerError;
  if (!worker) {
    const e = new Error('Phone not registered');
    // @ts-ignore
    e.code = 'PHONE_NOT_REGISTERED';
    throw e;
  }
  if (!worker.is_active) {
    const e = new Error('Worker profile is inactive');
    // @ts-ignore
    e.code = 'WORKER_INACTIVE';
    throw e;
  }
  const isTestPhone = phone === '+919999999999' || phone === '6309705929';
  const otp = isTestPhone ? '123456' : String(Math.floor(100000 + Math.random() * 900000));
  
  // Terminal log for easy development testing
  console.log('\n---------------------------------------');
  console.log(`🔐 OTP REQUEST [${phone}]: ${otp}`);
  console.log('---------------------------------------\n');

  const expiresAt = new Date(Date.now() + 5 * 60 * 1000);
  const otpHash = hashOtp(phone, otp);

  const { error: insertError } = await supabaseAdmin.from('worker_login_otps').insert({
    worker_id: worker.id,
    phone,
    otp_hash: otpHash,
    expires_at: expiresAt.toISOString()
  });
  if (insertError) throw insertError;
  
  // Best-effort push notification
  try {
    await sendWorkerOtpPush(worker.id, otp, clientToken);
  } catch (pushError) {
    console.error('Failed to send OTP push:', pushError);
  }

  return {
    worker,
    phone,
    expiresAt: expiresAt.toISOString(),
    otpPreview: otp // Return for easy testing in app
  };
}

export async function verifyWorkerOtp(phoneRaw, otpRaw) {
  const phone = normalizePhone(phoneRaw);
  const otp = String(otpRaw || '').trim();
  if (!phone || !otp) {
    const e = new Error('phone and otp required');
    // @ts-ignore
    e.code = 'OTP_INPUT_REQUIRED';
    throw e;
  }

  const { data: challenge, error: challengeError } = await supabaseAdmin
    .from('worker_login_otps')
    .select('id,worker_id,phone,otp_hash,expires_at,attempts,consumed_at,created_at')
    .eq('phone', phone)
    .is('consumed_at', null)
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle();

  if (challengeError) throw challengeError;
  if (!challenge) {
    const e = new Error('OTP not found');
    // @ts-ignore
    e.code = 'OTP_NOT_FOUND';
    throw e;
  }

  if (new Date(challenge.expires_at).getTime() < Date.now()) {
    await supabaseAdmin
      .from('worker_login_otps')
      .update({ consumed_at: new Date().toISOString() })
      .eq('id', challenge.id);
    const e = new Error('OTP expired');
    // @ts-ignore
    e.code = 'OTP_EXPIRED';
    throw e;
  }

  if ((challenge.attempts ?? 0) >= 5) {
    const e = new Error('Too many attempts');
    // @ts-ignore
    e.code = 'OTP_ATTEMPTS_EXCEEDED';
    throw e;
  }

  const isValid = challenge.otp_hash === hashOtp(phone, otp);
  if (!isValid) {
    await supabaseAdmin
      .from('worker_login_otps')
      .update({ attempts: (challenge.attempts ?? 0) + 1 })
      .eq('id', challenge.id);
    const e = new Error('Invalid OTP');
    // @ts-ignore
    e.code = 'OTP_INVALID';
    throw e;
  }

  const { data: worker, error: workerError } = await supabaseAdmin
    .from('workers')
    .select('id,user_id,email,name,phone,role,is_active,can_access_stock,perm_products,perm_inventory,perm_orders,perm_reports,perm_users,perm_settings')
    .eq('id', challenge.worker_id)
    .maybeSingle();
  if (workerError) throw workerError;
  if (!worker || !worker.is_active) {
    const e = new Error('Worker is inactive');
    // @ts-ignore
    e.code = 'WORKER_INACTIVE';
    throw e;
  }

  await supabaseAdmin
    .from('worker_login_otps')
    .update({ consumed_at: new Date().toISOString() })
    .eq('id', challenge.id);

  const role = worker.role === 'manager' ? 'manager' : 'worker';

  return {
    user: {
      id: worker.user_id || worker.id,
      worker_id: worker.id,
      name: worker.name || 'Worker',
      phone: worker.phone || phone,
      role,
      email: worker.email || null,
      permissions: {
        perm_products: worker.perm_products ?? false,
        perm_inventory: worker.perm_inventory ?? true,
        perm_orders: worker.perm_orders ?? role === 'manager',
        perm_reports: worker.perm_reports ?? role === 'manager',
        perm_users: worker.perm_users ?? role === 'manager',
        perm_settings: worker.perm_settings ?? false
      }
    }
  };
}
