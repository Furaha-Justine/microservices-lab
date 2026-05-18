'use strict';

const request = require('supertest');

// ── Mock DB and Cache before requiring the app ────────────────
jest.mock('../src/db');
jest.mock('../src/cache');

const db    = require('../src/db');
const cache = require('../src/cache');

// Default mock implementations
db.init.mockResolvedValue();
db.close.mockResolvedValue();
cache.ping.mockResolvedValue('PONG');
cache.get.mockResolvedValue(null);   // cache miss by default
cache.setEx.mockResolvedValue(true);
cache.quit.mockResolvedValue();

process.env.PORT = '5001';
process.env.DATABASE_URL = 'postgresql://mock:mock@localhost:5432/mock';
process.env.REDIS_URL    = 'redis://localhost:6379/0';

const { app, server } = require('../src/server');

afterAll(() => server.close());
beforeEach(() => jest.clearAllMocks());

// ── Health & Readiness ────────────────────────────────────────
describe('Health & Readiness', () => {
  test('GET /health returns 200', async () => {
    const res = await request(app).get('/health');
    expect(res.statusCode).toBe(200);
    expect(res.body).toMatchObject({ status: 'ok', service: 'backend' });
    expect(res.body.ts).toBeDefined();
  });

  test('GET /ready returns 200 when DB and Redis are ok', async () => {
    db.query.mockResolvedValueOnce({ rows: [{ '?column?': 1 }] });
    cache.ping.mockResolvedValueOnce('PONG');
    const res = await request(app).get('/ready');
    expect(res.statusCode).toBe(200);
    expect(res.body.status).toBe('ready');
    expect(res.body.checks.postgres).toBe('ok');
    expect(res.body.checks.redis).toBe('ok');
  });

  test('GET /ready returns 503 when DB is down', async () => {
    db.query.mockRejectedValueOnce(new Error('Connection refused'));
    const res = await request(app).get('/ready');
    expect(res.statusCode).toBe(503);
    expect(res.body.status).toBe('not ready');
  });
});

// ── Products ──────────────────────────────────────────────────
describe('Products API', () => {
  const mockRows = [
    { id: 'p001', name: 'Headphones', category: 'Electronics', price: '79.99', stock: 100, description: 'Good' },
    { id: 'p002', name: 'Yoga Mat',   category: 'Sports',      price: '24.99', stock: 200, description: 'Non-slip' },
  ];

  test('GET /api/products returns list from DB', async () => {
    db.query
      .mockResolvedValueOnce({ rows: [{ count: '2' }] })  // COUNT query
      .mockResolvedValueOnce({ rows: mockRows });           // data query
    const res = await request(app).get('/api/products');
    expect(res.statusCode).toBe(200);
    expect(res.body.products).toHaveLength(2);
    expect(res.body.total).toBe(2);
  });

  test('GET /api/products returns cached result on cache hit', async () => {
    const cached = JSON.stringify({ products: mockRows, total: 2 });
    cache.get.mockResolvedValueOnce(cached);
    const res = await request(app).get('/api/products');
    expect(res.statusCode).toBe(200);
    expect(db.query).not.toHaveBeenCalled();   // DB should NOT be hit
  });

  test('GET /api/products?category=Sports filters results', async () => {
    db.query
      .mockResolvedValueOnce({ rows: [{ count: '1' }] })   // COUNT query
      .mockResolvedValueOnce({ rows: [mockRows[1]] });       // data query
    const res = await request(app).get('/api/products?category=Sports');
    expect(res.statusCode).toBe(200);
    expect(res.body.total).toBe(1);
  });

  test('GET /api/products/:id returns single product', async () => {
    db.query.mockResolvedValueOnce({ rows: [mockRows[0]] });
    const res = await request(app).get('/api/products/p001');
    expect(res.statusCode).toBe(200);
    expect(res.body.id).toBe('p001');
  });

  test('GET /api/products/:id returns 404 when not found', async () => {
    db.query.mockResolvedValueOnce({ rows: [] });
    const res = await request(app).get('/api/products/bad-id');
    expect(res.statusCode).toBe(404);
  });

  test('GET /api/products returns 500 on DB error', async () => {
    db.query.mockRejectedValueOnce(new Error('DB down'));
    const res = await request(app).get('/api/products');
    expect(res.statusCode).toBe(500);
  });
});

// ── Cart ──────────────────────────────────────────────────────
describe('Cart API', () => {
  test('POST /api/cart adds item successfully', async () => {
    db.query
      .mockResolvedValueOnce({ rows: [{ stock: 100 }] })                                   // stock check
      .mockResolvedValueOnce({ rows: [{ id: 1, session_id: 'sess-1', product_id: 'p001', quantity: 2 }] }); // upsert
    const res = await request(app)
      .post('/api/cart')
      .send({ product_id: 'p001', quantity: 2, session_id: 'sess-1' });
    expect(res.statusCode).toBe(200);
    expect(res.body.message).toBe('Cart updated');
    expect(res.body.item.product_id).toBe('p001');
  });

  test('POST /api/cart returns 400 when product_id missing', async () => {
    const res = await request(app).post('/api/cart').send({ quantity: 1 });
    expect(res.statusCode).toBe(400);
  });

  test('POST /api/cart returns 404 when product not found', async () => {
    db.query.mockResolvedValueOnce({ rows: [] });
    const res = await request(app)
      .post('/api/cart')
      .send({ product_id: 'bad', quantity: 1 });
    expect(res.statusCode).toBe(404);
  });

  test('POST /api/cart returns 409 when insufficient stock', async () => {
    db.query.mockResolvedValueOnce({ rows: [{ stock: 1 }] });
    const res = await request(app)
      .post('/api/cart')
      .send({ product_id: 'p001', quantity: 10 });
    expect(res.statusCode).toBe(409);
  });

  test('GET /api/cart/:session_id returns cart with total', async () => {
    db.query.mockResolvedValueOnce({
      rows: [
        { product_id: 'p001', name: 'Headphones', price: '79.99', stock: 100, quantity: 2, subtotal: '159.98' },
      ],
    });
    const res = await request(app).get('/api/cart/sess-1');
    expect(res.statusCode).toBe(200);
    expect(res.body.items).toHaveLength(1);
    expect(res.body.total).toBe(159.98);
  });

  test('GET /api/cart/:session_id returns empty cart', async () => {
    db.query.mockResolvedValueOnce({ rows: [] });
    const res = await request(app).get('/api/cart/empty');
    expect(res.statusCode).toBe(200);
    expect(res.body.total).toBe(0);
  });
});
