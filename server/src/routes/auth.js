import express from 'express';
import { config } from '../config.js';
import {
  authRequired,
  loginWithEmailPassword,
  requestWorkerOtp,
  signSession,
  verifyWorkerOtp
} from '../auth.js';
import { log } from '../logger.js';
import { supabaseAdmin } from '../supabase.js';
import { logActivity } from '../activity_logger.js';

export const authRouter = express.Router();

authRouter.post('/login', async (req, res) => {
  const { email, password } = req.body || {};
  if (!email || !password) return res.status(400).json({ error: 'email and password required' });

  try {
    const { user } = await loginWithEmailPassword(String(email), String(password));
    if (user.role !== 'admin' && user.role !== 'manager') {
      await supabaseAdmin.from('login_history').insert({
        email: String(email),
        ip_address: req.ip || req.headers['x-forwarded-for'] || '',
        user_agent: req.headers['user-agent'] || '',
        status: 'failed'
      });
      return res.status(403).json({
        error: 'Only admin and manager accounts can use email/password login.'
      });
    }

    const session = {
      sub: user.id,
      email: user.email,
      name: user.name,
      role: user.role
    };
    const token = signSession(session);

    res.cookie(config.cookieName, token, {
      httpOnly: true,
      secure: config.cookieSecure,
      sameSite: config.cookieSameSite,
      path: '/',
      maxAge: 30 * 24 * 60 * 60 * 1000 // 30 days
    });

    log({
      level: 'info',
      msg: 'auth_login',
      id: req.id,
      user: { sub: session.sub, role: session.role, email: session.email }
    });

    // Write to login history and activity logs
    await supabaseAdmin.from('login_history').insert({
      user_id: user.id,
      email: user.email,
      ip_address: req.ip || req.headers['x-forwarded-for'] || '',
      user_agent: req.headers['user-agent'] || '',
      status: 'success'
    });

    await logActivity({
      actorId: user.id,
      actorName: user.name,
      actionType: 'login',
      description: `${user.name} (${user.role}) logged in successfully`,
      metadata: {
        ip: req.ip || req.headers['x-forwarded-for'] || '',
        ua: req.headers['user-agent'] || ''
      }
    });

    return res.json({ token, user: session });
  } catch (e) {
    // Log failed login
    await supabaseAdmin.from('login_history').insert({
      email: String(email),
      ip_address: req.ip || req.headers['x-forwarded-for'] || '',
      user_agent: req.headers['user-agent'] || '',
      status: 'failed'
    });

    const code = e && typeof e === 'object' ? e.code : undefined;
    if (code === 'PROFILE_LOOKUP_FAILED') {
      log({ level: 'error', msg: 'auth_profile_lookup_failed', id: req.id, email: String(email) });
      return res.status(500).json({ error: 'Server user profile misconfigured' });
    }
    if (code === 'PROFILE_NOT_FOUND') {
      log({ level: 'warn', msg: 'auth_profile_missing', id: req.id, email: String(email) });
      return res.status(403).json({ error: 'User profile not provisioned' });
    }
    log({
      level: 'warn',
      msg: 'auth_login_failed',
      id: req.id,
      email: String(email)
    });
    return res.status(401).json({ error: 'Invalid credentials' });
  }
});

authRouter.post('/worker/request-otp', async (req, res) => {
  const { phone, token } = req.body || {};
  try {
    const result = await requestWorkerOtp(phone, token);
    log({
      level: 'info',
      msg: 'worker_otp_requested',
      id: req.id,
      phone: result.phone
    });
    return res.json({
      ok: true,
      message: 'OTP sent successfully.',
      phone: result.phone,
      expiresAt: result.expiresAt,
      otpPreview: result.otpPreview
    });
  } catch (e) {
    const code = e && typeof e === 'object' ? e.code : undefined;
    if (code === 'PHONE_REQUIRED') {
      return res.status(400).json({ error: 'Phone number is required.' });
    }
    if (code === 'PHONE_NOT_REGISTERED') {
      return res.status(404).json({
        error: 'This phone number is not registered. Please contact admin.'
      });
    }
    if (code === 'WORKER_INACTIVE' || code === 'WORKER_STOCK_DISABLED') {
      return res.status(403).json({
        error: 'Worker login is disabled. Please contact admin.'
      });
    }
    log({ level: 'error', msg: 'worker_otp_request_failed', id: req.id, err: String(e) });
    return res.status(500).json({ error: 'Unable to send OTP right now.' });
  }
});

authRouter.post('/worker/verify-otp', async (req, res) => {
  const { phone, otp } = req.body || {};
  try {
    const result = await verifyWorkerOtp(phone, otp);
    const session = {
      sub: result.user.id,
      email: '',
      name: result.user.name,
      role: result.user.role,
      phone: result.user.phone
    };
    const token = signSession(session);
    res.cookie(config.cookieName, token, {
      httpOnly: true,
      secure: config.cookieSecure,
      sameSite: config.cookieSameSite,
      path: '/',
      maxAge: 30 * 24 * 60 * 60 * 1000 // 30 days
    });

    log({
      level: 'info',
      msg: 'worker_otp_login_success',
      id: req.id,
      user: { sub: session.sub, role: session.role, phone: session.phone }
    });

    // Write to login history and activity logs
    await supabaseAdmin.from('login_history').insert({
      user_id: result.user.id,
      email: result.user.email || '',
      ip_address: req.ip || req.headers['x-forwarded-for'] || '',
      user_agent: req.headers['user-agent'] || '',
      status: 'success'
    });

    await logActivity({
      actorId: result.user.id,
      actorName: result.user.name,
      actionType: 'login',
      description: `Worker ${result.user.name} logged in via OTP`,
      metadata: {
        phone: result.user.phone,
        ip: req.ip || req.headers['x-forwarded-for'] || '',
        ua: req.headers['user-agent'] || ''
      }
    });

    return res.json({ token, user: session });
  } catch (e) {
    // Log failed login
    await supabaseAdmin.from('login_history').insert({
      email: String(phone),
      ip_address: req.ip || req.headers['x-forwarded-for'] || '',
      user_agent: req.headers['user-agent'] || '',
      status: 'failed'
    });

    const code = e && typeof e === 'object' ? e.code : undefined;
    if (code === 'OTP_INPUT_REQUIRED') {
      return res.status(400).json({ error: 'Phone number and OTP are required.' });
    }
    if (code === 'OTP_NOT_FOUND' || code === 'OTP_EXPIRED') {
      return res.status(400).json({ error: 'OTP expired. Please request a new one.' });
    }
    if (code === 'OTP_ATTEMPTS_EXCEEDED') {
      return res.status(429).json({ error: 'Too many wrong attempts. Request a new OTP.' });
    }
    if (code === 'OTP_INVALID') {
      return res.status(401).json({ error: 'Invalid OTP.' });
    }
    if (code === 'WORKER_INACTIVE') {
      return res.status(403).json({ error: 'Worker is inactive. Please contact admin.' });
    }
    log({ level: 'error', msg: 'worker_otp_verify_failed', id: req.id, err: String(e) });
    return res.status(500).json({ error: 'Unable to verify OTP right now.' });
  }
});


authRouter.post('/logout', (req, res) => {
  res.clearCookie(config.cookieName, { path: '/' });
  log({ level: 'info', msg: 'auth_logout', id: req.id });
  return res.json({ ok: true });
});

authRouter.get('/me', authRequired, (req, res) => {
  return res.json({ user: req.session });
});
