'use strict';

const request = require('supertest');

// Mock axios before requiring the app
jest.mock('axios');
const axios = require('axios');

// Set env before requiring server
process.env.BACKEND_URL = 'http://mock-backend:5000';
process.env.PORT = '3001';

const { app, server } = require('../server');

afterAll(() => server.close());

describe('Frontend Health & Readiness', () => {
  test('GET /health returns 200 with ok status', async () => {
    const res = await request(app).get('/health');
    expect(res.statusCode).toBe(200);
    expect(res.body).toMatchObject({ status: 'ok', service: 'frontend' });
  });

  test('GET /ready returns 200 when backend is reachable', async () => {
    axios.get.mockResolvedValueOnce({ data: { status: 'ok' } });
    const res = await request(app).get('/ready');
    expect(res.statusCode).toBe(200);
    expect(res.body.status).toBe('ready');
  });

  test('GET /ready returns 503 when backend is unreachable', async () => {
    axios.get.mockRejectedValueOnce(new Error('ECONNREFUSED'));
    const res = await request(app).get('/ready');
    expect(res.statusCode).toBe(503);
    expect(res.body.status).toBe('not ready');
  });
});

describe('Product API Proxy', () => {
  test('GET /api/products proxies to backend and returns data', async () => {
    const mockProducts = { products: [{ id: 'p001', name: 'Test', price: 9.99 }], total: 1 };
    axios.get.mockResolvedValueOnce({ data: mockProducts });
    const res = await request(app).get('/api/products');
    expect(res.statusCode).toBe(200);
    expect(res.body.products).toHaveLength(1);
  });

  test('GET /api/products returns 502 when backend fails', async () => {
    axios.get.mockRejectedValueOnce(new Error('Backend down'));
    const res = await request(app).get('/api/products');
    expect(res.statusCode).toBe(502);
    expect(res.body.error).toBeDefined();
  });

  test('GET /api/products/:id proxies to backend', async () => {
    axios.get.mockResolvedValueOnce({ data: { id: 'p001', name: 'Test' } });
    const res = await request(app).get('/api/products/p001');
    expect(res.statusCode).toBe(200);
    expect(res.body.id).toBe('p001');
  });
});

describe('Cart API Proxy', () => {
  test('POST /api/cart proxies cart addition', async () => {
    axios.post.mockResolvedValueOnce({ data: { message: 'Added to cart' } });
    const res = await request(app)
      .post('/api/cart')
      .send({ product_id: 'p001', quantity: 1 });
    expect(res.statusCode).toBe(200);
    expect(res.body.message).toBe('Added to cart');
  });

  test('POST /api/cart returns 502 when backend fails', async () => {
    axios.post.mockRejectedValueOnce(new Error('Backend down'));
    const res = await request(app)
      .post('/api/cart')
      .send({ product_id: 'p001', quantity: 1 });
    expect(res.statusCode).toBe(502);
  });

  test('GET /api/cart/:session_id proxies to backend', async () => {
    axios.get.mockResolvedValueOnce({
      data: { session_id: 'sess-1', items: [], total: 0 },
    });
    const res = await request(app).get('/api/cart/sess-1');
    expect(res.statusCode).toBe(200);
    expect(res.body.session_id).toBe('sess-1');
  });

  test('GET /api/cart/:session_id returns 502 when backend fails', async () => {
    axios.get.mockRejectedValueOnce(new Error('Backend down'));
    const res = await request(app).get('/api/cart/sess-1');
    expect(res.statusCode).toBe(502);
  });
});
