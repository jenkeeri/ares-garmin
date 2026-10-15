import { test } from 'node:test';
import assert from 'node:assert/strict';
import { World, Kind } from '../src/world.js';
import { buildFeed } from '../src/feed.js';
import { distance, bearing, offset } from '../src/geo.js';
import { applyPush } from '../src/sources/push.js';
import { SimSource } from '../src/sources/sim.js';
import { AresSource } from '../src/sources/ares.js';
import { createServer } from '../src/server.js';

const fixedWorld = (t = 1_000_000) => new World({ now: () => t });

test('geo: offset/distance/bearing round-trip', () => {
  const [lat, lon] = offset(56.95, 24.1, 500, 45);
  assert.ok(Math.abs(distance(56.95, 24.1, lat, lon) - 500) < 1);
  assert.ok(Math.abs(bearing(56.95, 24.1, lat, lon) - 45) < 0.5);
});

test('feed: unchanged seq returns tiny payload', () => {
  const w = fixedWorld();
  w.upsert({ id: 'a', kind: Kind.FRIEND, lat: 1, lon: 2, label: 'A' });
  const full = buildFeed(w);
  assert.equal(full.u, 1);
  assert.deepEqual(full.e[0], [1, 0, 0, 1000000, 2000000, 0, 'A']);
  const again = buildFeed(w, { q: full.q });
  assert.deepEqual(Object.keys(again).sort(), ['p', 'q', 't', 'u', 'v']);
  assert.equal(again.u, 0);
});

test('feed: identical upsert does not bump seq', () => {
  const w = fixedWorld();
  w.upsert({ id: 'a', kind: 0, lat: 1, lon: 2 });
  const s = w.seq;
  w.upsert({ id: 'a', kind: 0, lat: 1, lon: 2 });
  assert.equal(w.seq, s);
});

test('feed: objectives first, then nearest, limited to n', () => {
  const w = fixedWorld();
  w.upsert({ id: 'far', kind: Kind.FRIEND, lat: 0.01, lon: 0 });
  w.upsert({ id: 'near', kind: Kind.FRIEND, lat: 0.001, lon: 0 });
  w.upsert({ id: 'obj', kind: Kind.OBJECTIVE, lat: 0.05, lon: 0 });
  const f = buildFeed(w, { lat: 0, lon: 0, n: 2 });
  assert.deepEqual(f.e.map((e) => e[0]), [3, 2]);
});

test('feed: ages and labels truncated', () => {
  let t = 10_000;
  const w = new World({ now: () => t });
  w.upsert({ id: 'x', kind: 0, lat: 0, lon: 0, label: 'ABCDEFGHIJKLMNOP' });
  t += 7_400;
  const f = buildFeed(w);
  assert.equal(f.e[0][5], 7);
  assert.equal(f.e[0][6], 'ABCDEFGHIJKL');
});

test('messages: newest first, capped at 5, deduped', () => {
  const w = fixedWorld();
  for (let i = 0; i < 7; i++) w.postMessage({ id: `m${i}`, text: `t${i}` });
  w.postMessage({ id: 'm6', text: 'dup' });
  const f = buildFeed(w);
  assert.equal(f.m.length, 5);
  assert.equal(f.m[0][3], 't6');
});

test('push: string kinds, remove, replace', () => {
  const w = fixedWorld();
  applyPush(w, { entities: [{ id: 'p', kind: 'friend', lat: 1, lon: 1 }, { id: 'o', kind: 'objective', lat: 2, lon: 2, state: 1 }] });
  assert.equal(w.entities.size, 2);
  applyPush(w, { remove: ['p'] });
  assert.equal(w.entities.size, 1);
  applyPush(w, { replace: true, entities: [] });
  assert.equal(w.entities.size, 0);
  assert.throws(() => applyPush(w, { entities: [{ id: 'z', kind: 'tank', lat: 0, lon: 0 }] }));
});

test('sim: anchors on first viewer and produces players/objectives', () => {
  const w = fixedWorld();
  let seed = 1;
  const sim = new SimSource(w, { rng: () => ((seed = (seed * 16807) % 2147483647) / 2147483647) });
  sim.start();
  w.setViewer(56.95, 24.1);
  const kinds = [...w.entities.values()].map((e) => e.kind);
  assert.ok(kinds.filter((k) => k === Kind.FRIEND).length === 5);
  assert.ok(kinds.filter((k) => k === Kind.OBJECTIVE).length === 3);
  for (let i = 0; i < 100; i++) sim.tick();
  for (const e of w.entities.values()) assert.ok(distance(56.95, 24.1, e.lat, e.lon) < 2000);
  sim.stop();
});

test('ares mapping removes vanished entities', () => {
  const w = fixedWorld();
  const a = new AresSource(w);
  a.apply({ players: [{ id: 1, name: 'A', lat: 1, lon: 1 }, { id: 2, name: 'B', lat: 1, lon: 1 }] });
  a.apply({ players: [{ id: 1, name: 'A', lat: 1, lon: 1 }] });
  assert.equal(w.entities.size, 1);
});

test('server: auth, feed, push over HTTP', async () => {
  const w = new World();
  const srv = createServer(w, { key: 'secret' }).listen(0);
  await new Promise((r) => srv.once('listening', r));
  const base = `http://127.0.0.1:${srv.address().port}`;
  try {
    assert.equal((await fetch(`${base}/v1/feed`)).status, 401);
    const push = await fetch(`${base}/v1/push`, { method: 'POST', headers: { 'X-Ares-Key': 'secret' }, body: JSON.stringify({ entities: [{ id: 'a', kind: 'friend', lat: 1.5, lon: 2.5, label: 'A' }] }) });
    assert.equal(push.status, 200);
    const feed = await (await fetch(`${base}/v1/feed?k=secret&lat=1500100&lon=2500000`)).json();
    assert.equal(feed.e[0][3], 1500000);
    assert.deepEqual(w.viewer && [w.viewer.lat, w.viewer.lon], [1.5001, 2.5]);
    const same = await (await fetch(`${base}/v1/feed?k=secret&q=${feed.q}`)).json();
    assert.equal(same.u, 0);
    assert.equal((await fetch(`${base}/v1/push?k=secret`, { method: 'POST', body: 'nope' })).status, 400);
  } finally {
    srv.close();
  }
});
