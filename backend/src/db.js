'use strict';

const { Pool } = require('pg');

const pool = new Pool({
  connectionString: process.env.DATABASE_URL || 'postgresql://shopnow:shopnow@postgres:5432/shopnow',
  max:              10,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 5000,
});

pool.on('error', (err) => {
  console.error('[db] Unexpected pool error:', err.message);
});

// ── Seed data ─────────────────────────────────────────────────
const SEED_PRODUCTS = [
  ['p001', 'Wireless Headphones', 'Electronics', 79.99,  150, 'High-quality wireless audio'],
  ['p002', 'Running Shoes',       'Sports',       59.99,  200, 'Lightweight performance shoes'],
  ['p003', 'Python Cookbook',     'Books',        34.99,   75, 'Advanced Python recipes'],
  ['p004', 'Smart Watch',         'Electronics', 199.99,   80, 'Health & fitness tracking'],
  ['p005', 'Yoga Mat',            'Sports',       24.99,  300, 'Non-slip premium mat'],
  ['p006', 'Coffee Maker',        'Home',         49.99,  120, '12-cup programmable brewer'],
  ['p007', 'Organic Green Tea',   'Food',          9.99,  500, 'Premium loose-leaf tea'],
  ['p008', 'Denim Jacket',        'Clothing',     69.99,   90, 'Classic indigo wash'],
];

// ── Initialise schema and seed ────────────────────────────────
async function init() {
  try {
    await pool.query(`
      CREATE TABLE IF NOT EXISTS products (
        id          VARCHAR(10)   PRIMARY KEY,
        name        VARCHAR(200)  NOT NULL,
        category    VARCHAR(100),
        price       NUMERIC(10,2),
        stock       INTEGER DEFAULT 0,
        description TEXT,
        created_at  TIMESTAMP DEFAULT NOW()
      )
    `);

    await pool.query(`
      CREATE TABLE IF NOT EXISTS cart_items (
        id          SERIAL PRIMARY KEY,
        session_id  VARCHAR(100),
        product_id  VARCHAR(10) REFERENCES products(id),
        quantity    INTEGER DEFAULT 1,
        added_at    TIMESTAMP DEFAULT NOW()
      )
    `);

    // Seed if empty
    const { rows } = await pool.query('SELECT COUNT(*) FROM products');
    if (parseInt(rows[0].count) === 0) {
      for (const [id, name, category, price, stock, description] of SEED_PRODUCTS) {
        await pool.query(
          'INSERT INTO products (id, name, category, price, stock, description) VALUES ($1,$2,$3,$4,$5,$6)',
          [id, name, category, price, stock, description]
        );
      }
      console.log(`[db] Seeded ${SEED_PRODUCTS.length} products`);
    }

    console.log('[db] Initialised');
  } catch (err) {
    console.warn('[db] Init skipped (not connected yet):', err.message);
  }
}

async function close() {
  await pool.end();
  console.log('[db] Pool closed');
}

module.exports = {
  query: (text, params) => pool.query(text, params),
  init,
  close,
};
