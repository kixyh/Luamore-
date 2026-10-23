import crypto from 'node:crypto';
import { redis, cfg, clientIp, rateLimit, safe } from '../lib/redis.js';

// POST /api/start -> { session, minSeconds, checkpointUrl }
async function handler(req, res) {
  res.setHeader('Cache-Control', 'no-store');
  if (req.method !== 'POST') return res.status(405).json({ error: 'method' });

  const ip = clientIp(req);
  if (!(await rateLimit('start', ip, 20, 3600))) return res.status(429).json({ error: 'rate_limited' });

  const session = crypto.randomBytes(16).toString('hex');
  await redis.set(`sess:${session}`, { ip, t: Date.now() }, { ex: 3600 });
  res.json({ session, minSeconds: cfg.minSeconds, checkpointUrl: cfg.checkpointUrl });
}

export default safe(handler);
