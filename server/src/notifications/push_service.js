import { supabaseAdmin } from '../supabase.js';
import { getFirebaseMessaging, isFirebaseMessagingEnabled } from './firebase_messaging.js';
import { log } from '../logger.js';

const INVALID_TOKEN_CODES = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token'
]);

function sessionScope(session) {
  const role = String(session?.role || '').trim();
  const sub = String(session?.sub || '').trim();
  if (!sub) return { userId: null, workerId: null, role: role || null };
  if (role === 'admin') {
    return { userId: sub, workerId: null, role };
  }
  return { userId: null, workerId: sub, role: role || 'worker' };
}

export async function registerNotificationDevice({ session, token, platform, app, deviceName }) {
  const pushToken = String(token || '').trim();
  if (!pushToken) {
    const e = new Error('token is required');
    e.code = 'TOKEN_REQUIRED';
    throw e;
  }

  const safePlatform = ['android', 'ios', 'web'].includes(platform) ? platform : 'android';
  const safeApp = ['mobile', 'admin'].includes(app) ? app : 'mobile';
  const scope = sessionScope(session);

  const payload = {
    token: pushToken,
    platform: safePlatform,
    app: safeApp,
    device_name: deviceName ? String(deviceName).slice(0, 120) : null,
    user_id: scope.userId,
    worker_id: scope.workerId,
    role: scope.role,
    is_active: true,
    last_seen: new Date().toISOString(),
    updated_at: new Date().toISOString()
  };

  const { data, error } = await supabaseAdmin
    .from('notification_devices')
    .upsert(payload, { onConflict: 'token' })
    .select('*')
    .single();

  if (error) throw error;
  return data;
}

export async function unregisterNotificationDevice({ token }) {
  const pushToken = String(token || '').trim();
  if (!pushToken) {
    const e = new Error('token is required');
    e.code = 'TOKEN_REQUIRED';
    throw e;
  }

  const { error } = await supabaseAdmin
    .from('notification_devices')
    .update({ is_active: false, updated_at: new Date().toISOString() })
    .eq('token', pushToken);

  if (error) throw error;
  return { ok: true };
}

export async function sendPushNotification({ title, body, data = {}, apps = ['mobile', 'admin'], tokens }) {
  if (!isFirebaseMessagingEnabled()) {
    return { sent: 0, failed: 0, skipped: true, reason: 'firebase_not_configured' };
  }

  let targetTokens = [];
  if (Array.isArray(tokens)) {
    targetTokens = tokens.map((token) => String(token || '').trim()).filter(Boolean);
  } else {
    const { data: devices, error } = await supabaseAdmin
      .from('notification_devices')
      .select('id,token,app,is_active')
      .eq('is_active', true)
      .in('app', apps);

    if (error) throw error;

    targetTokens = (devices ?? [])
      .map((device) => String(device.token || '').trim())
      .filter(Boolean);
  }

  if (targetTokens.length === 0) return { sent: 0, failed: 0, skipped: true, reason: 'no_tokens' };

  const messaging = getFirebaseMessaging();
  if (!messaging) {
    return { sent: 0, failed: 0, skipped: true, reason: 'messaging_unavailable' };
  }

  const chunks = [];
  for (let index = 0; index < targetTokens.length; index += 500) {
    chunks.push(targetTokens.slice(index, index + 500));
  }

  let sent = 0;
  let failed = 0;
  const invalidTokens = [];

  for (const chunkTokens of chunks) {
    const response = await messaging.sendEachForMulticast({
      tokens: chunkTokens,
      notification: { 
        title: String(title || 'Stock Update'), 
        body: String(body || ''),
        imageUrl: data.imageUrl || undefined
      },
      android: {
        notification: {
          imageUrl: data.imageUrl || undefined,
          channelId: 'stock_activity_channel_v3',
          priority: 'high',
          sound: 'default',
          sticky: false,
          visibility: 'public'
        }
      },
      data: Object.fromEntries(
        Object.entries(data).map(([key, value]) => [key, String(value ?? '')])
      )
    });

    sent += response.successCount;
    failed += response.failureCount;

    response.responses.forEach((entry, idx) => {
      if (!entry.success) {
        const code = entry.error?.code;
        if (code && INVALID_TOKEN_CODES.has(code)) {
          invalidTokens.push(chunkTokens[idx]);
        }
      }
    });
  }

  if (invalidTokens.length > 0) {
    const { error: deactivateError } = await supabaseAdmin
      .from('notification_devices')
      .update({ is_active: false, updated_at: new Date().toISOString() })
      .in('token', invalidTokens);

    if (deactivateError) {
      log({
        level: 'warn',
        msg: 'push_deactivate_tokens_failed',
        error: deactivateError.message,
        count: invalidTokens.length
      });
    }
  }

  return { sent, failed, skipped: false, invalidated: invalidTokens.length };
}

export async function sendStockTransactionPush(transactionRow) {
  const isIn = String(transactionRow?.type || '') === 'stock_in';
  const productCode = String(transactionRow?.product_code || 'Product');
  const quantity = Number(transactionRow?.quantity || 0);
  const color = String(transactionRow?.color_name || 'Default');
  const worker = String(transactionRow?.worker_name || 'User');

  const title = productCode;
  const body = `${isIn ? 'Stock In' : 'Stock Out'} • ${isIn ? '+' : '-'}${quantity} (${color}) by ${worker}`;

  try {
    // Fetch product image for rich notification
    let imageUrl = '';
    if (transactionRow?.product_id) {
      const { data: product } = await supabaseAdmin
        .from('products')
        .select('image_url')
        .eq('id', transactionRow.product_id)
        .single();
      if (product?.image_url) imageUrl = product.image_url;
    }

    console.log('Sending push with image:', imageUrl || 'None');
    return await sendPushNotification({
      title,
      body,
      data: {
        type: 'stock_transaction',
        productId: transactionRow?.product_id || '',
        transactionId: transactionRow?.id || '',
        movement: isIn ? 'in' : 'out',
        quantity,
        imageUrl: imageUrl || ''
      },
      apps: ['mobile', 'admin']
    });
  } catch (error) {
    log({
      level: 'warn',
      msg: 'push_stock_transaction_failed',
      error: String(error)
    });
    return { sent: 0, failed: 0, skipped: true, reason: 'send_failed' };
  }
}

export async function sendWorkerOtpPush(workerId, otp) {
  if (!workerId || !otp) return { skipped: true, reason: 'missing_params' };

  // Query tokens registered for this worker even if currently inactive (due to logout)
  // to ensure they can receive their verification code on their trusted device.
  const { data: devices, error } = await supabaseAdmin
    .from('notification_devices')
    .select('token')
    .eq('worker_id', workerId);

  if (error) throw error;
  if (!devices || devices.length === 0) {
    return { sent: 0, failed: 0, skipped: true, reason: 'no_registered_devices' };
  }

  const tokens = devices.map(d => d.token);
  
  return await sendPushNotification({
    title: 'Verification Code',
    body: `Your login code is: ${otp}. It will expire in 5 minutes.`,
    data: {
      type: 'otp_verification',
      otp: String(otp)
    },
    apps: ['mobile'],
    tokens
  });
}
