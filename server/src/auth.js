import jwt from 'jsonwebtoken';
import { config } from './config.js';
import { supabaseAdmin, supabaseAuth } from './supabase.js';
import crypto from 'crypto';
import { sendWorkerOtpPush } from './notifications/push_service.js';

export function signSession(payload) {
  return jwt.sign(payload, config.jwtSecret, { expiresIn: '30d' });
}

export function verifySessionToken(token) {
  return jwt.verify(token, config.jwtSecret);
}

export function getTokenFromRequest(req) {
  const auth = req.headers.authorization;
  if (auth && auth.startsWith('Bearer ')) return auth.slice('Bearer '.length);
  const cookieToken = req.cookies?.[config.cookieName];
  return cookieToken || null;
}

export async function authRequired(req, res, next) {
  try {
    const token = getTokenFromRequest(req);
    if (!token) return res.status(401).json({ error: 'Unauthorized' });
    req.session = verifySessionToken(token);
    return next();
  } catch {
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

export function requirePermission(permission) {
  return async (req, res, next) => {
    try {
      const userId = req.session?.sub;
      if (!userId) return res.status(401).json({ error: 'Unauthorized' });

      const { data: user, error } = await supabaseAdmin
        .from('users')
        .select('role, is_active, perm_products, perm_inventory, perm_orders, perm_reports, perm_users, perm_settings')
        .eq('id', userId)
        .maybeSingle();

      if (error || !user) {
        return res.status(401).json({ error: 'User profile not found' });
      }

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
    .select('id,name,email,role,created_at')
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
    .select('id,name,phone,role,is_active,can_access_stock')
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
  if (!worker.can_access_stock) {
    const e = new Error('Stock access disabled');
    // @ts-ignore
    e.code = 'WORKER_STOCK_DISABLED';
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
    .select('id,name,phone,role,is_active,can_access_stock')
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
      id: worker.id,
      name: worker.name || 'Worker',
      phone: worker.phone || phone,
      role,
      email: null
    }
  };
}
