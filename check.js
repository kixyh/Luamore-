import { redis, rateLimit, clientIp } from '../lib/redis.js';

// GET /api/check?key=...&uid=... -> plain text "true" / "false"
export default async function handler(req, res) {
  res.setHeader('Cache-Control', 'no-store');
  res.setHeader('Content-Type', 'text/plain');
  const no = () => res.status(200).send('false');

  const key = String(req.query.key || '').trim().toUpperCase();
  const uid = String(req.query.uid || '').trim();
  if (!/^[A-Z0-9-]{8,64}$/.test(key)) return no();

  if (!(await rateLimit('check', clientIp(req), 60, 60))) return res.status(429).send('false');

  const k = `key:${key}`;
  const d = await redis.hgetall(k);
  if (!d || !d.created) return no();
  if (String(d.revoked) === '1') return no();
  if (Number(d.expires) && Date.now() > Number(d.expires)) return no();

  const bound = d.uid !== undefined && d.uid !== null && String(d.uid) !== '';
  if (!uid) return bound ? no() : res.status(200).send('true');

  if (!bound) {
    // bind the key to the first player that uses it
    const won = await redis.hsetnx(k, 'uid', uid);
    if (!won) {
      const cur = await redis.hget(k, 'uid');
      if (String(cur) !== uid) return no();
    }
  } else if (String(d.uid) !== uid) {
    return no();
  }
  res.status(200).send('true');
}
