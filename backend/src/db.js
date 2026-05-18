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
  ['p001', 'Wireless Headphones',    'Electronics',  79.99,  150, 'High-quality wireless audio with 30hr battery'],
  ['p002', 'Running Shoes',          'Sports',        59.99,  200, 'Lightweight performance shoes for all terrain'],
  ['p003', 'Python Cookbook',        'Books',         34.99,   75, 'Advanced Python recipes and patterns'],
  ['p004', 'Smart Watch',            'Electronics',  199.99,   80, 'Health & fitness tracking with GPS'],
  ['p005', 'Yoga Mat',               'Sports',        24.99,  300, 'Non-slip premium 6mm thick mat'],
  ['p006', 'Coffee Maker',           'Home',          49.99,  120, '12-cup programmable brewer with timer'],
  ['p007', 'Organic Green Tea',      'Food',           9.99,  500, 'Premium loose-leaf tea from Kyoto farms'],
  ['p008', 'Denim Jacket',           'Clothing',      69.99,   90, 'Classic indigo wash, slim fit'],
  ['p009', 'Mechanical Keyboard',    'Electronics',  129.99,   60, 'RGB backlit, Cherry MX switches'],
  ['p010', 'Protein Powder',         'Food',          39.99,  250, 'Whey isolate, 25g protein per serving'],
  ['p011', 'Camping Tent',           'Sports',        89.99,   45, '2-person waterproof 3-season tent'],
  ['p012', 'Blender',                'Home',          59.99,   70, '1200W high-speed smoothie blender'],
  ['p013', 'JavaScript: The Good Parts', 'Books',    22.99,  100, 'Essential JS patterns by Douglas Crockford'],
  ['p014', 'Winter Boots',           'Clothing',      94.99,   55, 'Waterproof insulated boots -20°C rated'],
  ['p015', 'USB-C Hub',              'Electronics',   35.99,  180, '7-in-1 hub: HDMI, USB3, SD card, PD'],
  ['p016', 'Resistance Bands Set',   'Sports',        19.99,  400, '5-level resistance set with carry bag'],
  ['p017', 'Scented Candle Set',     'Home',          24.99,  220, 'Set of 4 soy wax candles, 40hr burn each'],
  ['p018', 'Sunglasses',             'Clothing',      49.99,  130, 'UV400 polarised lenses, titanium frame'],
  ['p019', 'Air Fryer',              'Home',          79.99,   95, '5.5L digital air fryer, 8 presets'],
  ['p020', 'Novel: The Midnight Library', 'Books',   14.99,  160, 'Matt Haig bestseller — life, regret & hope'],
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
        session_id  VARCHAR(100)  NOT NULL,
        product_id  VARCHAR(10)   REFERENCES products(id) ON DELETE CASCADE,
        quantity    INTEGER DEFAULT 1,
        added_at    TIMESTAMP DEFAULT NOW(),
        UNIQUE (session_id, product_id)
      )
    `);

    await pool.query(`
      CREATE TABLE IF NOT EXISTS orders (
        id          SERIAL PRIMARY KEY,
        session_id  VARCHAR(100)  NOT NULL,
        status      VARCHAR(20)   DEFAULT 'confirmed',
        total       NUMERIC(10,2) NOT NULL,
        created_at  TIMESTAMP DEFAULT NOW()
      )
    `);

    await pool.query(`
      CREATE TABLE IF NOT EXISTS order_items (
        id          SERIAL PRIMARY KEY,
        order_id    INTEGER       REFERENCES orders(id) ON DELETE CASCADE,
        product_id  VARCHAR(10)   REFERENCES products(id),
        name        VARCHAR(200)  NOT NULL,
        quantity    INTEGER       NOT NULL,
        unit_price  NUMERIC(10,2) NOT NULL
      )
    `);

    await pool.query(`
      CREATE TABLE IF NOT EXISTS reviews (
        id          SERIAL PRIMARY KEY,
        product_id  VARCHAR(10)  REFERENCES products(id) ON DELETE CASCADE,
        session_id  VARCHAR(100),
        rating      INTEGER      CHECK (rating BETWEEN 1 AND 5),
        comment     TEXT,
        created_at  TIMESTAMP DEFAULT NOW()
      )
    `);

    await pool.query(`
      CREATE TABLE IF NOT EXISTS wishlist (
        id          SERIAL PRIMARY KEY,
        session_id  VARCHAR(100) NOT NULL,
        product_id  VARCHAR(10)  REFERENCES products(id) ON DELETE CASCADE,
        added_at    TIMESTAMP DEFAULT NOW(),
        UNIQUE (session_id, product_id)
      )
    `);

    // Seed products if empty
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
