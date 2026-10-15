import http from 'node:http';
import { timingSafeEqual } from 'node:crypto';
import { buildFeed } from './feed.js';
import { applyPush } from './sources/push.js';
import { DASHBOARD_HTML } from './dashboard.js';

const MAX_BODY = 256 * 1024;

function safeEqual(a, b) {
  const x = Buffer.from(String(a));
  const y = Buffer.from(String(b));
  return x.length === y.length && timingSafeEqual(x, y);
}

function send(res, status, body, type = 'application/json') {
  const data = type === 'application/json' ? JSON.stringify(body) : body;
  res.writeHead(status, { 'Content-Type': type, 'Cache-Control': 'no-store', 'Content-Length': Buffer.byteLength(data) });
  res.end(data);
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    req.on('data', (c) => {
      size += c.length;
      if (size > MAX_BODY) { reject(new Error('body too large')); req.destroy(); return; }
      chunks.push(c);
    });
    req.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
    req.on('error', reject);
  });
}

const intParam = (v) => (v === null || v === '' ? undefined : Number.parseInt(v, 10));

/**
 * @param {import('./world.js').World} world
 * @param {{key?: string, pushKey?: string, pollSeconds?: number, log?: (msg: string) => void}} opts
 */
export function createServer(world, { key = '', pushKey, pollSeconds = 5, log = () => {} } = {}) {
  const writeKey = pushKey ?? key;
  const authorized = (url, req, expected) => !expected || safeEqual(req.headers['x-ares-key'] ?? url.searchParams.get('k') ?? '', expected);

  return http.createServer(async (req, res) => {
    const url = new URL(req.url, 'http://relay');
    try {
      if (req.method === 'GET' && url.pathname === '/health') return send(res, 200, { ok: true, seq: world.seq, entities: world.entities.size });

      if (req.method === 'GET' && url.pathname === '/v1/feed') {
        if (!authorized(url, req, key)) return send(res, 401, { error: 'unauthorized' });
        const latE6 = intParam(url.searchParams.get('lat'));
        const lonE6 = intParam(url.searchParams.get('lon'));
        const lat = Number.isFinite(latE6) ? latE6 / 1e6 : undefined;
        const lon = Number.isFinite(lonE6) ? lonE6 / 1e6 : undefined;
        if (lat !== undefined && lon !== undefined && Math.abs(lat) <= 90 && Math.abs(lon) <= 180 && (lat !== 0 || lon !== 0)) world.setViewer(lat, lon);
        const feed = buildFeed(world, { q: intParam(url.searchParams.get('q')) ?? 0, lat, lon, n: intParam(url.searchParams.get('n')) ?? 32, poll: pollSeconds });
        log(`feed q=${url.searchParams.get('q')} -> ${feed.q} u=${feed.u} e=${feed.e?.length ?? 0}`);
        return send(res, 200, feed);
      }

      if (req.method === 'POST' && url.pathname === '/v1/push') {
        if (!authorized(url, req, writeKey)) return send(res, 401, { error: 'unauthorized' });
        const result = applyPush(world, JSON.parse(await readBody(req)));
        return send(res, 200, result);
      }

      if (req.method === 'GET' && url.pathname === '/v1/state') {
        if (!authorized(url, req, key)) return send(res, 401, { error: 'unauthorized' });
        return send(res, 200, { seq: world.seq, viewer: world.viewer, entities: [...world.entities.values()], messages: world.messages });
      }

      if (req.method === 'GET' && url.pathname === '/') return send(res, 200, DASHBOARD_HTML, 'text/html; charset=utf-8');

      return send(res, 404, { error: 'not found' });
    } catch (err) {
      log(`error ${req.method} ${url.pathname}: ${err.message}`);
      return send(res, 400, { error: err.message });
    }
  });
}
