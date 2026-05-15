'use strict';

const { createClient } = require('redis');

const REDIS_URL = process.env.REDIS_URL || 'redis://redis:6379/0';

const redisClient = createClient({
  url: REDIS_URL,
  socket: {
    connectTimeout: 3000,
    reconnectStrategy: (retries) => {
      if (retries > 10) return new Error('Redis max retries reached');
      return Math.min(retries * 100, 3000);
    },
  },
});

redisClient.on('error',   (err) => console.warn('[cache] Redis error:', err.message));
redisClient.on('connect', ()    => console.log('[cache] Redis connected'));

// Connect lazily — don't crash the app if Redis is unavailable
(async () => {
  try {
    await redisClient.connect();
  } catch (err) {
    console.warn('[cache] Redis unavailable at startup:', err.message);
  }
})();

module.exports = {
  get:    (key)           => redisClient.get(key).catch(() => null),
  setEx:  (key, ttl, val) => redisClient.setEx(key, ttl, val).catch(() => null),
  ping:   ()              => redisClient.ping(),
  quit:   ()              => redisClient.quit().catch(() => {}),
};
