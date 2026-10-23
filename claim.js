import { redis, cfg, clientIp, makeKey, rateLimit, safe } from '../lib/redis.js';

// POST /api/claim { session } -> { key, expires }
async function handler(req, res) {
  res.setHeader('Cache-Control', 'no-store');
  if (req.method !== 'POST') return res.status(405).json({ error: 'method' });

  const session = String(req.body?.session || '');
  if (!/^[a-f0-9]{32}$/.test(session)) return res.status(400).json({ error: 'invalid_session' });

  const sk = `sess:${session}`;
  const s = await redis.get(sk);
  if (!s) return res.status(400).json({ error: 'invalid_session' });

  const elapsed = (Date.now() - s.t) / 1000;
  if (elapsed < cfg.minSeconds) {
    return res.status(425).json({ error: 'too_fast', wait: Math.ceil(cfg.minSeconds - elapsed) });
  }

  const ip = clientIp(req);
  if (!(await rateLimit('claim', ip, cfg.maxPerIp, 86400))) {
    return res.status(429).json({ error: 'rate_limited' });
  }

  // one-time use: whoever deletes the session first wins
  if (!(await redis.getdel(sk))) return res.status(400).json({ error: 'invalid_session' });

  const key = makeKey();
  const now = Date.now();
  const expires = cfg.keyHours > 0 ? now + cfg.keyHours * 3600 * 1000 : 0;
  await redis.hset(`key:${key}`, { created: now, expires, ip, source: 'site' });
  if (cfg.keyHours > 0) await redis.expire(`key:${key}`, cfg.keyHours * 3600 + 3600);

  res.json({ key, expires });
}

export default safe(handler);
