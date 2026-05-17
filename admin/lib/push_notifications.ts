'use client';

import { initializeApp, getApps } from 'firebase/app';
import { getMessaging, getToken, isSupported, onMessage } from 'firebase/messaging';
import { serverPost } from './server_api';

const storageKey = 'admin_fcm_token';

const firebaseConfig = {
  apiKey: process.env.NEXT_PUBLIC_FIREBASE_API_KEY || '',
  authDomain: process.env.NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN || '',
  projectId: process.env.NEXT_PUBLIC_FIREBASE_PROJECT_ID || '',
  messagingSenderId: process.env.NEXT_PUBLIC_FIREBASE_MESSAGING_SENDER_ID || '',
  appId: process.env.NEXT_PUBLIC_FIREBASE_APP_ID || ''
};

const vapidKey = process.env.NEXT_PUBLIC_FIREBASE_VAPID_KEY || '';

function isConfigured() {
  return Boolean(
    firebaseConfig.apiKey &&
      firebaseConfig.projectId &&
      firebaseConfig.messagingSenderId &&
      firebaseConfig.appId &&
      vapidKey
  );
}

export async function registerAdminPushNotifications() {
  if (typeof window === 'undefined' || !('Notification' in window)) return null;
  if (!isConfigured()) return null;
  if (!(await isSupported())) return null;

  if (Notification.permission === 'denied') return null;
  if (Notification.permission !== 'granted') {
    const permission = await Notification.requestPermission();
    if (permission !== 'granted') return null;
  }

  const app = getApps()[0] || initializeApp(firebaseConfig);
  const messaging = getMessaging(app);
  const registration = await navigator.serviceWorker.register('/firebase-messaging-sw.js');
  const token = await getToken(messaging, {
    vapidKey,
    serviceWorkerRegistration: registration
  });

  if (!token) return null;

  await serverPost('/notifications/devices/register', {
    token,
    platform: 'web',
    app: 'admin',
    deviceName: navigator.userAgent
  });
  window.localStorage.setItem(storageKey, token);

  onMessage(messaging, (payload) => {
    const title = payload.notification?.title || 'StockIQ Update';
    const body = payload.notification?.body || '';
    if (Notification.permission === 'granted') {
      new Notification(title, { body });
    }
  });

  return token;
}

export async function unregisterAdminPushNotifications() {
  if (typeof window === 'undefined') return;
  const token = window.localStorage.getItem(storageKey);
  if (!token) return;
  try {
    await serverPost('/notifications/devices/unregister', { token });
  } catch {
    // Ignore unregister errors on sign-out
  } finally {
    window.localStorage.removeItem(storageKey);
  }
}

