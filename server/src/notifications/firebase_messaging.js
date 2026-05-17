import { getApps, initializeApp, cert } from 'firebase-admin/app';
import { getMessaging } from 'firebase-admin/messaging';
import { config } from '../config.js';

function resolvePrivateKey(value) {
  if (!value) return '';
  return value.replace(/\\n/g, '\n');
}

export function isFirebaseMessagingEnabled() {
  return Boolean(
    config.firebase.projectId &&
      config.firebase.clientEmail &&
      config.firebase.privateKey
  );
}

let messagingInstance = null;

export function getFirebaseMessaging() {
  if (!isFirebaseMessagingEnabled()) return null;
  if (messagingInstance) return messagingInstance;

  const privateKey = resolvePrivateKey(config.firebase.privateKey);
  const app =
    getApps()[0] ||
    initializeApp({
      credential: cert({
        projectId: config.firebase.projectId,
        clientEmail: config.firebase.clientEmail,
        privateKey
      })
    });

  messagingInstance = getMessaging(app);
  return messagingInstance;
}

