import crypto from 'node:crypto';
import { redis, makeKey } from '../lib/redis.js';

// POST /api/admin   Authorization: Bearer <ADMIN_SECRET>
// { action: "create", days: 30, count: 1, note: "vip" }   days 0 = never expires
// { action: "revoke" | "unrevoke" | "reset" | "delete" | "info", key: "..." }
function authed(req) {
  const given = Buffer.from((req.headers.authorization || '').replace(/^Bearer\s+/i, ''));
  const want = Buffer.from(process.env.ADMIN_SECRET || '');
  return want.length > 0 && given.length === want.length && crypto.timingSafeEqual(given, want);
}

export default async function handler(req, res) {
  res.setHeader('Cache-Control', 'no-store');
  if (req.method !== 'POST') return res.status(405).json({ error: 'method' });
  if (!authed(req)) return res.status(401).json({ error: 'unauthorized' });

  const { action, key: rawKey, days = 0, count = 1, note = '' } = req.body || {};
  const key = String(rawKey || '').trim().toUpperCase();
  const k = `key:${key}`;

  if (action === 'create') {
    const n = Math.min(Math.max(Number(count) || 1, 1), 100);
    const out = [];
    for (let i = 0; i < n; i++) {
      const nk = makeKey();
      const expires = Number(days) > 0 ? Date.now() + Number(days) * 86400 * 1000 : 0;
      await redis.hset(`key:${nk}`, { created: Date.now(), expires, source: 'admin', note: String(note) });
      if (expires) await redis.expire(`key:${nk}`, Number(days) * 86400 + 3600);
      out.push(nk);
    }
    return res.json({ keys: out });
  }

  if (!key) return res.status(400).json({ error: 'key_required' });
  if (action === 'info') return res.json((await redis.hgetall(k)) || null);
  if (!(await redis.exists(k))) return res.status(404).json({ error: 'not_found' });

  if (action === 'revoke') await redis.hset(k, { revoked: 1 });
  else if (action === 'unrevoke') await redis.hdel(k, 'revoked');
  else if (action === 'reset') await redis.hdel(k, 'uid'); // unbind player
  else if (action === 'delete') await redis.del(k);
  else return res.status(400).json({ error: 'bad_action' });
  res.json({ ok: true });
}
