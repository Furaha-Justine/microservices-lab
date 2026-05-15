'use strict';

const express     = require('express');
const axios       = require('axios');
const helmet      = require('helmet');
const morgan      = require('morgan');
const rateLimit   = require('express-rate-limit');
const path        = require('path');

const app  = express();
const PORT = process.env.PORT || 3000;

// ── Backend URL resolved via Cloud Map / K8s DNS / env var ──
const BACKEND_URL = process.env.BACKEND_URL || 'http://backend:5000';

// ── Middleware ────────────────────────────────────────────────
app.use(helmet());
app.use(morgan('combined'));
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

// Rate limiting: 100 req/min per IP
app.use(rateLimit({ windowMs: 60_000, max: 100 }));

// ── Health / readiness endpoints ─────────────────────────────
app.get('/health', (_req, res) => res.json({ status: 'ok', service: 'frontend' }));

app.get('/ready', async (_req, res) => {
  try {
    await axios.get(`${BACKEND_URL}/health`, { timeout: 3000 });
    res.json({ status: 'ready' });
  } catch {
    res.status(503).json({ status: 'not ready', reason: 'backend unreachable' });
  }
});

// ── API proxy to backend ──────────────────────────────────────
app.get('/api/products', async (_req, res) => {
  try {
    const { data } = await axios.get(`${BACKEND_URL}/api/products`, { timeout: 5000 });
    res.json(data);
  } catch (err) {
    console.error('Backend call failed:', err.message);
    res.status(502).json({ error: 'Backend unavailable' });
  }
});

app.get('/api/products/:id', async (req, res) => {
  try {
    const { data } = await axios.get(`${BACKEND_URL}/api/products/${req.params.id}`, { timeout: 5000 });
    res.json(data);
  } catch (err) {
    const status = err.response?.status || 502;
    res.status(status).json({ error: err.message });
  }
});

app.post('/api/cart', async (req, res) => {
  try {
    const { data } = await axios.post(`${BACKEND_URL}/api/cart`, req.body, { timeout: 5000 });
    res.json(data);
  } catch (err) {
    res.status(502).json({ error: 'Cart service unavailable' });
  }
});

app.get('/api/cart/:session_id', async (req, res) => {
  try {
    const { data } = await axios.get(`${BACKEND_URL}/api/cart/${req.params.session_id}`, { timeout: 5000 });
    res.json(data);
  } catch (err) {
    const status = err.response?.status || 502;
    res.status(status).json({ error: err.message });
  }
});

// ── Serve SPA for all other routes ───────────────────────────
app.get('*', (_req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

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
