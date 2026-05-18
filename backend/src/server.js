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
  try { await db.query('SELECT 1'); checks.postgres = 'ok'; }
  catch (err) { checks.postgres = `error: ${err.message}`; }

  try { await cache.ping(); checks.redis = 'ok'; }
  catch (err) { checks.redis = `error: ${err.message}`; }

  const ready = checks.postgres === 'ok';
  res.status(ready ? 200 : 503).json({ status: ready ? 'ready' : 'not ready', checks });
});

app.get('/metrics', async (_req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

// ─────────────────────────────────────────────────────────────
// PRODUCTS
// ─────────────────────────────────────────────────────────────

// GET /api/products?category=&limit=&offset=
app.get('/api/products', async (req, res) => {
  const { category, limit = 20, offset = 0 } = req.query;
  const cacheKey = `products:${category || 'all'}:${limit}:${offset}`;

  try {
    const cached = await cache.get(cacheKey);
    if (cached) return res.json(JSON.parse(cached));
  } catch (_) {}

  try {
    const params = [];
    let where = '';
    if (category) { where = 'WHERE category = $1'; params.push(category); }

    const countRow = await db.query(`SELECT COUNT(*) FROM products ${where}`, params);
    const totalCount = parseInt(countRow.rows[0].count);

    params.push(parseInt(limit), parseInt(offset));
    const limitIdx  = params.length - 1;
    const offsetIdx = params.length;
    const { rows } = await db.query(
      `SELECT id, name, category, price, stock, description, created_at
       FROM products ${where}
       ORDER BY created_at DESC
       LIMIT $${limitIdx} OFFSET $${offsetIdx}`,
      params
    );

    const result = { products: rows, total: totalCount, limit: parseInt(limit), offset: parseInt(offset) };
    try {
      await cache.setEx(cacheKey, parseInt(process.env.CACHE_TTL || '60'), JSON.stringify(result));
    } catch (_) {}

    res.json(result);
  } catch (err) {
    console.error('Products query failed:', err.message);
    res.status(500).json({ error: 'Failed to fetch products' });
  }
});

// GET /api/products/search?q=keyword
app.get('/api/products/search', async (req, res) => {
  const { q, limit = 20 } = req.query;
  if (!q || q.trim().length < 1) return res.status(400).json({ error: 'Query parameter q is required' });

  try {
    const term = `%${q.trim()}%`;
    const { rows } = await db.query(
      `SELECT id, name, category, price, stock, description
       FROM products
       WHERE name ILIKE $1 OR description ILIKE $1 OR category ILIKE $1
       ORDER BY name
       LIMIT $2`,
      [term, parseInt(limit)]
    );
    res.json({ products: rows, total: rows.length, query: q });
  } catch (err) {
    console.error('Product search failed:', err.message);
    res.status(500).json({ error: 'Search failed' });
  }
});

// GET /api/categories
app.get('/api/categories', async (_req, res) => {
  try {
    const cached = await cache.get('categories');
    if (cached) return res.json(JSON.parse(cached));
  } catch (_) {}

  try {
    const { rows } = await db.query(
      'SELECT category, COUNT(*) AS product_count FROM products GROUP BY category ORDER BY category'
    );
    const result = { categories: rows };
    try { await cache.setEx('categories', 300, JSON.stringify(result)); } catch (_) {}
    res.json(result);
  } catch (err) {
    console.error('Categories query failed:', err.message);
    res.status(500).json({ error: 'Failed to fetch categories' });
  }
});

// GET /api/products/:id
app.get('/api/products/:id', async (req, res) => {
  try {
    const { rows } = await db.query(
      `SELECT p.id, p.name, p.category, p.price, p.stock, p.description, p.created_at,
              ROUND(AVG(r.rating), 1) AS avg_rating,
              COUNT(r.id) AS review_count
       FROM products p
       LEFT JOIN reviews r ON r.product_id = p.id
       WHERE p.id = $1
       GROUP BY p.id`,
      [req.params.id]
    );
    if (!rows.length) return res.status(404).json({ error: 'Product not found' });
    res.json(rows[0]);
  } catch (err) {
    console.error('Product lookup failed:', err.message);
    res.status(500).json({ error: 'Failed to fetch product' });
  }
});

// POST /api/products — create a product
app.post('/api/products', async (req, res) => {
  const { id, name, category, price, stock = 0, description = '' } = req.body;
  if (!id || !name || !price) return res.status(400).json({ error: 'id, name and price are required' });
  if (isNaN(price) || price <= 0) return res.status(400).json({ error: 'price must be a positive number' });

  try {
    const { rows } = await db.query(
      'INSERT INTO products (id, name, category, price, stock, description) VALUES ($1,$2,$3,$4,$5,$6) RETURNING *',
      [id, name, category, parseFloat(price), parseInt(stock), description]
    );
    try { await cache.del('categories'); } catch (_) {}
    res.status(201).json(rows[0]);
  } catch (err) {
    if (err.code === '23505') return res.status(409).json({ error: 'Product ID already exists' });
    console.error('Product create failed:', err.message);
    res.status(500).json({ error: 'Failed to create product' });
  }
});

// PUT /api/products/:id — update price, stock, description
app.put('/api/products/:id', async (req, res) => {
  const { name, category, price, stock, description } = req.body;
  const updates = [];
  const params  = [];

  if (name        !== undefined) { params.push(name);               updates.push(`name = $${params.length}`); }
  if (category    !== undefined) { params.push(category);           updates.push(`category = $${params.length}`); }
  if (price       !== undefined) { params.push(parseFloat(price));  updates.push(`price = $${params.length}`); }
  if (stock       !== undefined) { params.push(parseInt(stock));    updates.push(`stock = $${params.length}`); }
  if (description !== undefined) { params.push(description);        updates.push(`description = $${params.length}`); }

  if (!updates.length) return res.status(400).json({ error: 'No fields to update' });

  params.push(req.params.id);
  try {
    const { rows } = await db.query(
      `UPDATE products SET ${updates.join(', ')} WHERE id = $${params.length} RETURNING *`,
      params
    );
    if (!rows.length) return res.status(404).json({ error: 'Product not found' });
    try { await cache.del('categories'); } catch (_) {}
    res.json(rows[0]);
  } catch (err) {
    console.error('Product update failed:', err.message);
    res.status(500).json({ error: 'Failed to update product' });
  }
});

// DELETE /api/products/:id
app.delete('/api/products/:id', async (req, res) => {
  try {
    const { rows } = await db.query(
      'DELETE FROM products WHERE id = $1 RETURNING id, name',
      [req.params.id]
    );
    if (!rows.length) return res.status(404).json({ error: 'Product not found' });
    res.json({ message: 'Product deleted', ...rows[0] });
  } catch (err) {
    console.error('Product delete failed:', err.message);
    res.status(500).json({ error: 'Failed to delete product' });
  }
});

// ─────────────────────────────────────────────────────────────
// CART
// ─────────────────────────────────────────────────────────────

// POST /api/cart — add or update item in cart
app.post('/api/cart', async (req, res) => {
  const { product_id, quantity = 1, session_id = 'default' } = req.body;
  if (!product_id) return res.status(400).json({ error: 'product_id is required' });
  if (quantity < 1 || quantity > 100) return res.status(400).json({ error: 'quantity must be between 1 and 100' });

  try {
    const { rows: product } = await db.query('SELECT stock FROM products WHERE id = $1', [product_id]);
    if (!product.length) return res.status(404).json({ error: 'Product not found' });
    if (product[0].stock < quantity) return res.status(409).json({ error: 'Insufficient stock' });

    // Upsert: if item already in cart, replace quantity
    const { rows } = await db.query(
      `INSERT INTO cart_items (session_id, product_id, quantity)
       VALUES ($1, $2, $3)
       ON CONFLICT (session_id, product_id) DO UPDATE SET quantity = $3
       RETURNING *`,
      [session_id, product_id, quantity]
    );
    res.json({ message: 'Cart updated', item: rows[0] });
  } catch (err) {
    console.error('Cart add failed:', err.message);
    res.status(500).json({ error: 'Failed to update cart' });
  }
});

// GET /api/cart/:session_id
app.get('/api/cart/:session_id', async (req, res) => {
  try {
    const { rows } = await db.query(
      `SELECT ci.product_id, p.name, p.price, p.stock, ci.quantity,
              (p.price * ci.quantity) AS subtotal
       FROM cart_items ci
       JOIN products p ON ci.product_id = p.id
       WHERE ci.session_id = $1
       ORDER BY ci.added_at`,
      [req.params.session_id]
    );
    const total = rows.reduce((sum, i) => sum + parseFloat(i.subtotal), 0);
    res.json({
      session_id: req.params.session_id,
      items: rows,
      item_count: rows.length,
      total: Math.round(total * 100) / 100,
    });
  } catch (err) {
    console.error('Cart fetch failed:', err.message);
    res.status(500).json({ error: 'Failed to fetch cart' });
  }
});

// PUT /api/cart/:session_id/item/:product_id — change quantity
app.put('/api/cart/:session_id/item/:product_id', async (req, res) => {
  const { quantity } = req.body;
  if (!quantity || quantity < 1 || quantity > 100)
    return res.status(400).json({ error: 'quantity must be between 1 and 100' });

  try {
    const { rows: product } = await db.query('SELECT stock FROM products WHERE id = $1', [req.params.product_id]);
    if (!product.length) return res.status(404).json({ error: 'Product not found' });
    if (product[0].stock < quantity) return res.status(409).json({ error: 'Insufficient stock' });

    const { rows } = await db.query(
      `UPDATE cart_items SET quantity = $1
       WHERE session_id = $2 AND product_id = $3
       RETURNING *`,
      [quantity, req.params.session_id, req.params.product_id]
    );
    if (!rows.length) return res.status(404).json({ error: 'Item not in cart' });
    res.json({ message: 'Quantity updated', item: rows[0] });
  } catch (err) {
    console.error('Cart update failed:', err.message);
    res.status(500).json({ error: 'Failed to update cart item' });
  }
});

// DELETE /api/cart/:session_id/item/:product_id — remove one item
app.delete('/api/cart/:session_id/item/:product_id', async (req, res) => {
  try {
    const { rows } = await db.query(
      'DELETE FROM cart_items WHERE session_id = $1 AND product_id = $2 RETURNING product_id',
      [req.params.session_id, req.params.product_id]
    );
    if (!rows.length) return res.status(404).json({ error: 'Item not in cart' });
    res.json({ message: 'Item removed from cart', product_id: rows[0].product_id });
  } catch (err) {
    console.error('Cart item delete failed:', err.message);
    res.status(500).json({ error: 'Failed to remove item' });
  }
});

// DELETE /api/cart/:session_id — clear entire cart
app.delete('/api/cart/:session_id', async (req, res) => {
  try {
    const { rowCount } = await db.query(
      'DELETE FROM cart_items WHERE session_id = $1',
      [req.params.session_id]
    );
    res.json({ message: 'Cart cleared', items_removed: rowCount });
  } catch (err) {
    console.error('Cart clear failed:', err.message);
    res.status(500).json({ error: 'Failed to clear cart' });
  }
});

// ─────────────────────────────────────────────────────────────
// ORDERS
// ─────────────────────────────────────────────────────────────

// POST /api/orders — checkout: converts cart into an order
app.post('/api/orders', async (req, res) => {
  const { session_id = 'default' } = req.body;

  try {
    // Fetch cart items
    const { rows: items } = await db.query(
      `SELECT ci.product_id, ci.quantity, p.name, p.price, p.stock
       FROM cart_items ci JOIN products p ON ci.product_id = p.id
       WHERE ci.session_id = $1`,
      [session_id]
    );
    if (!items.length) return res.status(400).json({ error: 'Cart is empty' });

    // Check stock for every item
    for (const item of items) {
      if (item.stock < item.quantity)
        return res.status(409).json({ error: `Insufficient stock for "${item.name}"` });
    }

    const total = items.reduce((sum, i) => sum + parseFloat(i.price) * i.quantity, 0);

    // Create order
    const { rows: orderRows } = await db.query(
      'INSERT INTO orders (session_id, total) VALUES ($1, $2) RETURNING *',
      [session_id, Math.round(total * 100) / 100]
    );
    const order = orderRows[0];

    // Create order items and reduce stock
    for (const item of items) {
      await db.query(
        'INSERT INTO order_items (order_id, product_id, name, quantity, unit_price) VALUES ($1,$2,$3,$4,$5)',
        [order.id, item.product_id, item.name, item.quantity, item.price]
      );
      await db.query(
        'UPDATE products SET stock = stock - $1 WHERE id = $2',
        [item.quantity, item.product_id]
      );
    }

    // Clear the cart
    await db.query('DELETE FROM cart_items WHERE session_id = $1', [session_id]);

    res.status(201).json({
      message: 'Order placed successfully',
      order: { ...order, items },
    });
  } catch (err) {
    console.error('Order create failed:', err.message);
    res.status(500).json({ error: 'Failed to place order' });
  }
});

// GET /api/orders?session_id= — list orders for a session
app.get('/api/orders', async (req, res) => {
  const { session_id } = req.query;
  if (!session_id) return res.status(400).json({ error: 'session_id query param is required' });

  try {
    const { rows } = await db.query(
      'SELECT * FROM orders WHERE session_id = $1 ORDER BY created_at DESC',
      [session_id]
    );
    res.json({ orders: rows, total: rows.length });
  } catch (err) {
    console.error('Orders fetch failed:', err.message);
    res.status(500).json({ error: 'Failed to fetch orders' });
  }
});

// GET /api/orders/:id — get full order with items
app.get('/api/orders/:id', async (req, res) => {
  try {
    const { rows: orderRows } = await db.query('SELECT * FROM orders WHERE id = $1', [req.params.id]);
    if (!orderRows.length) return res.status(404).json({ error: 'Order not found' });

    const { rows: items } = await db.query(
      'SELECT * FROM order_items WHERE order_id = $1',
      [req.params.id]
    );
    res.json({ ...orderRows[0], items });
  } catch (err) {
    console.error('Order fetch failed:', err.message);
    res.status(500).json({ error: 'Failed to fetch order' });
  }
});

// PUT /api/orders/:id/status — update order status (confirm, ship, deliver, cancel)
app.put('/api/orders/:id/status', async (req, res) => {
  const { status } = req.body;
  const valid = ['confirmed', 'shipped', 'delivered', 'cancelled'];
  if (!valid.includes(status)) return res.status(400).json({ error: `status must be one of: ${valid.join(', ')}` });

  try {
    const { rows } = await db.query(
      'UPDATE orders SET status = $1 WHERE id = $2 RETURNING *',
      [status, req.params.id]
    );
    if (!rows.length) return res.status(404).json({ error: 'Order not found' });

    // If cancelled, restore stock
    if (status === 'cancelled') {
      const { rows: items } = await db.query('SELECT * FROM order_items WHERE order_id = $1', [req.params.id]);
      for (const item of items) {
        await db.query('UPDATE products SET stock = stock + $1 WHERE id = $2', [item.quantity, item.product_id]);
      }
    }

    res.json({ message: `Order ${status}`, order: rows[0] });
  } catch (err) {
    console.error('Order status update failed:', err.message);
    res.status(500).json({ error: 'Failed to update order status' });
  }
});

// ─────────────────────────────────────────────────────────────
// REVIEWS
// ─────────────────────────────────────────────────────────────

// POST /api/products/:id/reviews
app.post('/api/products/:id/reviews', async (req, res) => {
  const { session_id = 'anonymous', rating, comment = '' } = req.body;
  if (!rating || rating < 1 || rating > 5)
    return res.status(400).json({ error: 'rating must be between 1 and 5' });

  try {
    const { rows: product } = await db.query('SELECT id FROM products WHERE id = $1', [req.params.id]);
    if (!product.length) return res.status(404).json({ error: 'Product not found' });

    const { rows } = await db.query(
      'INSERT INTO reviews (product_id, session_id, rating, comment) VALUES ($1,$2,$3,$4) RETURNING *',
      [req.params.id, session_id, parseInt(rating), comment]
    );
    res.status(201).json(rows[0]);
  } catch (err) {
    console.error('Review create failed:', err.message);
    res.status(500).json({ error: 'Failed to submit review' });
  }
});

// GET /api/products/:id/reviews
app.get('/api/products/:id/reviews', async (req, res) => {
  try {
    const { rows } = await db.query(
      `SELECT id, session_id, rating, comment, created_at
       FROM reviews WHERE product_id = $1 ORDER BY created_at DESC`,
      [req.params.id]
    );
    const avg = rows.length
      ? Math.round((rows.reduce((s, r) => s + r.rating, 0) / rows.length) * 10) / 10
      : null;
    res.json({ product_id: req.params.id, avg_rating: avg, reviews: rows, total: rows.length });
  } catch (err) {
    console.error('Reviews fetch failed:', err.message);
    res.status(500).json({ error: 'Failed to fetch reviews' });
  }
});

// ─────────────────────────────────────────────────────────────
// WISHLIST
// ─────────────────────────────────────────────────────────────

// POST /api/wishlist — add to wishlist
app.post('/api/wishlist', async (req, res) => {
  const { session_id = 'default', product_id } = req.body;
  if (!product_id) return res.status(400).json({ error: 'product_id is required' });

  try {
    const { rows: product } = await db.query('SELECT id FROM products WHERE id = $1', [product_id]);
    if (!product.length) return res.status(404).json({ error: 'Product not found' });

    await db.query(
      'INSERT INTO wishlist (session_id, product_id) VALUES ($1, $2) ON CONFLICT DO NOTHING',
      [session_id, product_id]
    );
    res.status(201).json({ message: 'Added to wishlist', session_id, product_id });
  } catch (err) {
    console.error('Wishlist add failed:', err.message);
    res.status(500).json({ error: 'Failed to add to wishlist' });
  }
});

// GET /api/wishlist/:session_id
app.get('/api/wishlist/:session_id', async (req, res) => {
  try {
    const { rows } = await db.query(
      `SELECT w.product_id, p.name, p.category, p.price, p.stock, p.description, w.added_at
       FROM wishlist w JOIN products p ON w.product_id = p.id
       WHERE w.session_id = $1
       ORDER BY w.added_at DESC`,
      [req.params.session_id]
    );
    res.json({ session_id: req.params.session_id, items: rows, total: rows.length });
  } catch (err) {
    console.error('Wishlist fetch failed:', err.message);
    res.status(500).json({ error: 'Failed to fetch wishlist' });
  }
});

// DELETE /api/wishlist/:session_id/item/:product_id
app.delete('/api/wishlist/:session_id/item/:product_id', async (req, res) => {
  try {
    const { rows } = await db.query(
      'DELETE FROM wishlist WHERE session_id = $1 AND product_id = $2 RETURNING product_id',
      [req.params.session_id, req.params.product_id]
    );
    if (!rows.length) return res.status(404).json({ error: 'Item not in wishlist' });
    res.json({ message: 'Removed from wishlist', product_id: rows[0].product_id });
  } catch (err) {
    console.error('Wishlist remove failed:', err.message);
    res.status(500).json({ error: 'Failed to remove from wishlist' });
  }
});

// ─────────────────────────────────────────────────────────────
// STATS
// ─────────────────────────────────────────────────────────────

// GET /api/stats — store-wide summary
app.get('/api/stats', async (_req, res) => {
  try {
    const [products, orders, reviews, lowStock] = await Promise.all([
      db.query('SELECT COUNT(*) AS total, SUM(stock) AS total_stock FROM products'),
      db.query(`SELECT COUNT(*) AS total,
                       COALESCE(SUM(total), 0) AS revenue,
                       COUNT(*) FILTER (WHERE status = 'delivered') AS delivered,
                       COUNT(*) FILTER (WHERE status = 'cancelled') AS cancelled
                FROM orders`),
      db.query('SELECT COUNT(*) AS total, ROUND(AVG(rating),1) AS avg_rating FROM reviews'),
      db.query('SELECT id, name, stock FROM products WHERE stock < 20 ORDER BY stock'),
    ]);

    res.json({
      products: {
        total: parseInt(products.rows[0].total),
        total_stock: parseInt(products.rows[0].total_stock),
      },
      orders: {
        total: parseInt(orders.rows[0].total),
        revenue: parseFloat(orders.rows[0].revenue),
        delivered: parseInt(orders.rows[0].delivered),
        cancelled: parseInt(orders.rows[0].cancelled),
      },
      reviews: {
        total: parseInt(reviews.rows[0].total),
        avg_rating: parseFloat(reviews.rows[0].avg_rating) || null,
      },
      low_stock_products: lowStock.rows,
    });
  } catch (err) {
    console.error('Stats fetch failed:', err.message);
    res.status(500).json({ error: 'Failed to fetch stats' });
  }
});

// ── Start server ──────────────────────────────────────────────
const server = app.listen(PORT, async () => {
  console.log(`[backend] Listening on :${PORT}`);
  await db.init();
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
