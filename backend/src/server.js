'use strict';

const express  = require('express');
const helmet   = require('helmet');
const morgan   = require('morgan');
const cors     = require('cors');
const client   = require('prom-client');

const db       = require('./db');
const cache    = require('./cache');

const app  = express();
const PORT = process.env.PORT || 5000;

// ── Prometheus metrics ────────────────────────────────────────
const register = new client.Registry();
client.collectDefaultMetrics({ register });

const httpRequests = new client.Counter({
  name: 'http_requests_total',
  help: 'Total HTTP requests',
  labelNames: ['method', 'route', 'status'],
  registers: [register],
});

// ── Middleware ────────────────────────────────────────────────
app.use(helmet());
app.use(cors());
app.use(morgan('combined'));
app.use(express.json());

// Metrics middleware
app.use((req, _res, next) => {
  _res.on('finish', () => {
    httpRequests.inc({ method: req.method, route: req.path, status: _res.statusCode });
  });
  next();
});

// ── Health & Readiness ────────────────────────────────────────
app.get('/health', (_req, res) => {
  res.json({ status: 'ok', service: 'backend', ts: Math.floor(Date.now() / 1000) });
});

app.get('/ready', async (_req, res) => {
  const checks = {};

  // Check PostgreSQL
  try {
    await db.query('SELECT 1');
    checks.postgres = 'ok';
  } catch (err) {
    checks.postgres = `error: ${err.message}`;
  }

  // Check Redis
  try {
    await cache.ping();
    checks.redis = 'ok';
  } catch (err) {
    checks.redis = `error: ${err.message}`;
  }

  const ready = checks.postgres === 'ok';
  res.status(ready ? 200 : 503).json({
    status: ready ? 'ready' : 'not ready',
    checks,
  });
});

// ── Prometheus metrics endpoint ───────────────────────────────
app.get('/metrics', async (_req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

// ── Products ──────────────────────────────────────────────────
app.get('/api/products', async (req, res) => {
  const { category, limit = 20 } = req.query;
  const cacheKey = `products:${category || 'all'}:${limit}`;

  // Try cache first
  try {
    const cached = await cache.get(cacheKey);
    if (cached) {
      return res.json(JSON.parse(cached));
    }
  } catch (_) { /* cache miss is fine */ }

  // Query DB
  try {
    let queryText = 'SELECT id, name, category, price, stock, description FROM products';
    const params = [];
    if (category) {
      queryText += ' WHERE category = $1 LIMIT $2';
      params.push(category, limit);
    } else {
      queryText += ' LIMIT $1';
      params.push(limit);
    }

    const { rows } = await db.query(queryText, params);
    const result = { products: rows, total: rows.length };

    // Store in cache
    try {
      const ttl = parseInt(process.env.CACHE_TTL || '60');
      await cache.setEx(cacheKey, ttl, JSON.stringify(result));
    } catch (_) { /* cache write failure is non-fatal */ }

    res.json(result);
  } catch (err) {
    console.error('Products query failed:', err.message);
    res.status(500).json({ error: 'Failed to fetch products' });
  }
});

app.get('/api/products/:id', async (req, res) => {
  try {
    const { rows } = await db.query(
      'SELECT id, name, category, price, stock, description FROM products WHERE id = $1',
      [req.params.id]
    );
    if (!rows.length) return res.status(404).json({ error: 'Product not found' });
    res.json(rows[0]);
  } catch (err) {
    console.error('Product lookup failed:', err.message);
    res.status(500).json({ error: 'Failed to fetch product' });
  }
});

// ── Cart ──────────────────────────────────────────────────────
app.post('/api/cart', async (req, res) => {
  const { product_id, quantity = 1, session_id = 'default' } = req.body;

  if (!product_id) return res.status(400).json({ error: 'product_id is required' });
  if (quantity < 1 || quantity > 100) return res.status(400).json({ error: 'Invalid quantity' });

  try {
    // Check product exists and has stock
    const { rows } = await db.query(
      'SELECT stock FROM products WHERE id = $1',
      [product_id]
    );
    if (!rows.length) return res.status(404).json({ error: 'Product not found' });
    if (rows[0].stock < quantity) return res.status(409).json({ error: 'Insufficient stock' });

    // Add to cart
    await db.query(
      'INSERT INTO cart_items (session_id, product_id, quantity) VALUES ($1, $2, $3)',
      [session_id, product_id, quantity]
    );

    res.json({ message: 'Added to cart', product_id, quantity });
  } catch (err) {
    console.error('Cart add failed:', err.message);
    res.status(500).json({ error: 'Failed to add to cart' });
  }
});

app.get('/api/cart/:session_id', async (req, res) => {
  try {
    const { rows } = await db.query(
      `SELECT ci.product_id, p.name, p.price, ci.quantity
       FROM cart_items ci
       JOIN products p ON ci.product_id = p.id
       WHERE ci.session_id = $1`,
      [req.params.session_id]
    );

    const total = rows.reduce((sum, item) => sum + (parseFloat(item.price) * item.quantity), 0);
    res.json({ session_id: req.params.session_id, items: rows, total: Math.round(total * 100) / 100 });
  } catch (err) {
    console.error('Cart fetch failed:', err.message);
    res.status(500).json({ error: 'Failed to fetch cart' });
  }
});

// ── Start server ──────────────────────────────────────────────
const server = app.listen(PORT, async () => {
  console.log(`[backend] Listening on :${PORT}`);
  await db.init();   // create tables + seed data
});

// ── Graceful shutdown ─────────────────────────────────────────
const shutdown = (signal) => {
  console.log(`[backend] ${signal} received, shutting down...`);
  server.close(async () => {
    await db.close();
    await cache.quit();
    process.exit(0);
  });
  setTimeout(() => process.exit(1), 10_000);
};

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT',  () => shutdown('SIGINT'));

module.exports = { app, server };
