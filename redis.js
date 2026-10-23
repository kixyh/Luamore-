import crypto from 'node:crypto';
import { Redis } from '@upstash/redis';

// Works with the Upstash Redis integration from the Vercel Marketplace
// (KV_REST_API_*) or a plain Upstash database (UPSTASH_REDIS_REST_*).
export const redis = new Redis({
  url: process.env.UPSTASH_REDIS_REST_URL || process.env.KV_REST_API_URL,
  token: process.env.UPSTASH_REDIS_REST_TOKEN || process.env.KV_REST_API_TOKEN,
});

export const configured = Boolean(
  (process.env.UPSTASH_REDIS_REST_URL || process.env.KV_REST_API_URL) &&
  (process.env.UPSTASH_REDIS_REST_TOKEN || process.env.KV_REST_API_TOKEN)
);

// Wraps a handler so config/Redis problems return a clear JSON error instead of a blank 500.
export const safe = (fn) => async (req, res) => {
  if (!configured) return res.status(500).json({ error: 'redis_not_configured' });
  try { return await fn(req, res); }
  catch (e) { console.error(e); return res.status(500).json({ error: 'server_error' }); }
};

export const cfg = {
  minSeconds: Number(process.env.MIN_SECONDS ?? 20),   // minimum time between Start and Claim
  keyHours: Number(process.env.KEY_HOURS ?? 24),       // key lifetime, 0 = never expires
  prefix: process.env.KEY_PREFIX || 'JOBLESS',
  maxPerIp: Number(process.env.MAX_KEYS_PER_IP ?? 3),  // keys per IP per 24h
  checkpointUrl: process.env.CHECKPOINT_URL || '',     // optional ad/checkpoint link
};

export function clientIp(req) {
  return (req.headers['x-forwarded-for'] || '').split(',')[0].trim() || req.socket?.remoteAddress || 'unknown';
}

const ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // 32 chars, no lookalikes
export function makeKey(prefix = cfg.prefix) {
  const part = () => Array.from(crypto.randomBytes(4), (b) => ALPHABET[b % 32]).join('');
  return `${prefix}-${part()}-${part()}-${part()}`;
}

export async function rateLimit(name, id, max, seconds) {
  const k = `rl:${name}:${id}`;
  const n = await redis.incr(k);
  if (n === 1) await redis.expire(k, seconds);
  return n <= max;
}
