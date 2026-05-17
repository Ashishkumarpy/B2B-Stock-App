import express from 'express';
import { authRequired, requireRole } from '../auth.js';
import {
  registerNotificationDevice,
  sendPushNotification,
  unregisterNotificationDevice
} from '../notifications/push_service.js';

export const notificationsRouter = express.Router();

notificationsRouter.post('/devices/register', authRequired, async (req, res) => {
  const { token, platform, app, deviceName } = req.body || {};
  try {
    const data = await registerNotificationDevice({
      session: req.session,
      token,
      platform: String(platform || '').trim().toLowerCase(),
      app: String(app || '').trim().toLowerCase(),
      deviceName
    });
    return res.json({ ok: true, data });
  } catch (e) {
    if (e && typeof e === 'object' && e.code === 'TOKEN_REQUIRED') {
      return res.status(400).json({ error: 'token is required' });
    }
    return res.status(400).json({ error: e?.message || 'Failed to register push token' });
  }
});

notificationsRouter.post('/devices/unregister', authRequired, async (req, res) => {
  const { token } = req.body || {};
  try {
    await unregisterNotificationDevice({ token });
    return res.json({ ok: true });
  } catch (e) {
    if (e && typeof e === 'object' && e.code === 'TOKEN_REQUIRED') {
      return res.status(400).json({ error: 'token is required' });
    }
    return res.status(400).json({ error: e?.message || 'Failed to unregister push token' });
  }
});

notificationsRouter.post('/test', authRequired, requireRole(['admin', 'manager']), async (req, res) => {
  const { title, body } = req.body || {};
  try {
    const result = await sendPushNotification({
      title: String(title || 'Test Notification'),
      body: String(body || 'Push notifications are configured successfully.'),
      data: { type: 'test' }
    });
    return res.json({ ok: true, result });
  } catch (e) {
    return res.status(400).json({ error: e?.message || 'Failed to send test notification' });
  }
});

