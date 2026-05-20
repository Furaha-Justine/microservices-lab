'use strict';

const express     = require('express');
const axios       = require('axios');
const helmet      = require('helmet');
const morgan      = require('morgan');
const rateLimit   = require('express-rate-limit');
const path        = require('path');

const app  = express();
const PORT = process.env.PORT || 3000;

const BACKEND_URL = process.env.BACKEND_URL || 'http://backend:5000';

const cspDefaults = helmet.contentSecurityPolicy.getDefaultDirectives();
delete cspDefaults['upgrade-insecure-requests']; // no HTTPS on ALB — keep requests as HTTP

app.use(helmet({
  contentSecurityPolicy: {
    directives: {
      ...cspDefaults,
      'script-src':  ["'self'", "'unsafe-inline'"],
      'style-src':   ["'self'", "'unsafe-inline'"],
      'img-src':     ["'self'", 'data:'],
      'connect-src': ["'self'"],
    },
  },
  crossOriginOpenerPolicy: false,
  strictTransportSecurity: false,
}));
app.use(morgan('combined'));
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));
app.use(rateLimit({ windowMs: 60_000, max: 200 }));

// ── Health / readiness ────────────────────────────────────────
app.get('/health', (_req, res) => res.json({ status: 'ok', service: 'frontend' }));

app.get('/ready', async (_req, res) => {
  try {
    await axios.get(`${BACKEND_URL}/health`, { timeout: 3000 });
    res.json({ status: 'ready' });
  } catch {
    res.status(503).json({ status: 'not ready', reason: 'backend unreachable' });
  }
});

// ── Generic proxy helper ──────────────────────────────────────
function proxy(method, backendPath) {
  return async (req, res) => {
    try {
      const url  = `${BACKEND_URL}${backendPath(req)}`;
      const opts = { timeout: 8000 };
      const r    = await axios[method](url, method === 'get' || method === 'delete' ? opts : req.body, method === 'get' || method === 'delete' ? undefined : opts);
      res.status(r.status).json(r.data);
    } catch (err) {
      const status = err.response?.status || 502;
      const body   = err.response?.data  || { error: err.message };
      res.status(status).json(body);
    }
  };
}

// ── Products ──────────────────────────────────────────────────
app.get('/api/products',         proxy('get',    () => '/api/products'));
app.get('/api/products/search',  proxy('get',    (req) => `/api/products/search?q=${encodeURIComponent(req.query.q || '')}&limit=${req.query.limit || 20}`));
app.get('/api/categories',       proxy('get',    () => '/api/categories'));
app.get('/api/products/:id',     proxy('get',    (req) => `/api/products/${req.params.id}`));
app.post('/api/products',        proxy('post',   () => '/api/products'));
app.put('/api/products/:id',     proxy('put',    (req) => `/api/products/${req.params.id}`));
app.delete('/api/products/:id',  proxy('delete', (req) => `/api/products/${req.params.id}`));

// ── Reviews ───────────────────────────────────────────────────
app.get('/api/products/:id/reviews',  proxy('get',  (req) => `/api/products/${req.params.id}/reviews`));
app.post('/api/products/:id/reviews', proxy('post', (req) => `/api/products/${req.params.id}/reviews`));

// ── Cart ──────────────────────────────────────────────────────
app.post('/api/cart',                                   proxy('post',   () => '/api/cart'));
app.get('/api/cart/:session_id',                        proxy('get',    (req) => `/api/cart/${req.params.session_id}`));
app.put('/api/cart/:session_id/item/:product_id',       proxy('put',    (req) => `/api/cart/${req.params.session_id}/item/${req.params.product_id}`));
app.delete('/api/cart/:session_id/item/:product_id',    proxy('delete', (req) => `/api/cart/${req.params.session_id}/item/${req.params.product_id}`));
app.delete('/api/cart/:session_id',                     proxy('delete', (req) => `/api/cart/${req.params.session_id}`));

// ── Orders ────────────────────────────────────────────────────
app.post('/api/orders',            proxy('post', () => '/api/orders'));
app.get('/api/orders',             proxy('get',  (req) => `/api/orders?session_id=${encodeURIComponent(req.query.session_id || '')}`));
app.get('/api/orders/:id',         proxy('get',  (req) => `/api/orders/${req.params.id}`));
app.put('/api/orders/:id/status',  proxy('put',  (req) => `/api/orders/${req.params.id}/status`));

// ── Wishlist ──────────────────────────────────────────────────
app.post('/api/wishlist',                                    proxy('post',   () => '/api/wishlist'));
app.get('/api/wishlist/:session_id',                         proxy('get',    (req) => `/api/wishlist/${req.params.session_id}`));
app.delete('/api/wishlist/:session_id/item/:product_id',     proxy('delete', (req) => `/api/wishlist/${req.params.session_id}/item/${req.params.product_id}`));

// ── Stats ─────────────────────────────────────────────────────
app.get('/api/stats', proxy('get', () => '/api/stats'));

// ── SPA fallback ──────────────────────────────────────────────
app.get('*', (_req, res) => res.sendFile(path.join(__dirname, 'public', 'index.html')));

// ── Graceful shutdown ─────────────────────────────────────────
const server = app.listen(PORT, () => {
  console.log(`[frontend] Listening on :${PORT}  →  backend: ${BACKEND_URL}`);
});

const shutdown = (signal) => {
  console.log(`[frontend] Received ${signal}, shutting down…`);
  server.close(() => process.exit(0));
  setTimeout(() => process.exit(1), 10_000);
};

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT',  () => shutdown('SIGINT'));

module.exports = { app, server };
