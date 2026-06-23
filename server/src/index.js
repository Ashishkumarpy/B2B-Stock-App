import express from 'express';
import cors from 'cors';
import cookieParser from 'cookie-parser';

import { assertConfig, config } from './config.js';
import { errorToObject, log, requestId } from './logger.js';
import { authRouter } from './routes/auth.js';
import { productsRouter } from './routes/products.js';
import { uploadsRouter } from './routes/uploads.js';
import { suppliersRouter } from './routes/suppliers.js';
import { transactionsRouter } from './routes/transactions.js';
import { ordersRouter } from './routes/orders.js';
import { usersRouter } from './routes/users.js';
import { workersRouter } from './routes/workers.js';
import { warehousesRouter } from './routes/warehouses.js';
import { notificationsRouter } from './routes/notifications.js';
import { appRouter } from './routes/app.js';

assertConfig();

const app = express();

function safePath(url) {
  if (!url) return '/';
  const idx = url.indexOf('?');
  return idx === -1 ? url : url.slice(0, idx);
}

app.use(
  cors({
    origin: true,
    credentials: true
  })
);
app.use(cookieParser());
app.use(express.json({ limit: '2mb' }));

// Request logging (method/path/status/duration + user info when available)
app.use((req, res, next) => {
  const id = requestId();
  req.id = id;
  res.setHeader('x-request-id', id);
  const start = process.hrtime.bigint();
  let finished = false;

  const writeLog = (event) => {
    if (finished) return;
    finished = true;
    const end = process.hrtime.bigint();
    const ms = Number(end - start) / 1e6;
    const session = req.session;

    log({
      level: res.statusCode >= 500 ? 'error' : res.statusCode >= 400 ? 'warn' : 'info',
      msg: 'http',
      event,
      id,
      method: req.method,
      path: safePath(req.originalUrl),
      status: res.statusCode,
      ms: Math.round(ms),
      ip: req.ip,
      ua: req.headers['user-agent'],
      user: session
        ? { sub: session.sub, role: session.role, email: session.email }
        : undefined,
      // When auth failed there's no verified session — log the (unverified)
      // claimed identity so we can see which users are hitting 401s.
      authFailure: session ? undefined : req.authFailure
    });
  };

  res.on('finish', () => writeLog('finish'));
  res.on('close', () => writeLog('close'));

  next();
});

app.get('/', (_req, res) => {
  return res.json({
    ok: true,
    name: 'b2b-stock-server',
    endpoints: ['/health', '/auth/login', '/auth/me']
  });
});
app.get('/health', (_req, res) => res.json({ ok: true }));
app.use('/auth', authRouter);
app.use('/products', productsRouter);
app.use('/suppliers', suppliersRouter);
app.use('/transactions', transactionsRouter);
app.use('/orders', ordersRouter);
app.use('/users', usersRouter);
app.use('/workers', workersRouter);
app.use('/warehouses', warehousesRouter);
app.use('/uploads', uploadsRouter);
app.use('/notifications', notificationsRouter);
app.use('/app', appRouter);

app.use((req, res) => {
  return res.status(404).json({ error: 'Not found' });
});

// Catch-all error handler
// eslint-disable-next-line no-unused-vars
app.use((err, req, res, _next) => {
  log({
    level: 'error',
    msg: 'unhandled_error',
    id: req.id,
    path: safePath(req.originalUrl),
    error: errorToObject(err)
  });
  res.status(500).json({ error: 'Internal server error' });
});

app.listen(config.port, config.host, () => {
  log({ level: 'info', msg: 'listening', host: config.host, port: config.port });
});
