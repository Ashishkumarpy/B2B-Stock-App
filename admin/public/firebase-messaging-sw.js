self.addEventListener('push', (event) => {
  if (!event.data) return;

  let payload = {};
  try {
    payload = event.data.json();
  } catch {
    payload = { notification: { title: 'StockIQ Update', body: event.data.text() } };
  }

  const title = payload?.notification?.title || 'StockIQ Update';
  const body = payload?.notification?.body || '';
  const data = payload?.data || {};

  event.waitUntil(
    self.registration.showNotification(title, {
      body,
      data,
      icon: '/next.svg'
    })
  );
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const productId = event.notification?.data?.productId;
  const targetPath = productId ? `/products/${productId}` : '/';

  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientList) => {
      for (const client of clientList) {
        if ('focus' in client) {
          client.navigate(targetPath);
          return client.focus();
        }
      }
      return clients.openWindow(targetPath);
    })
  );
});

