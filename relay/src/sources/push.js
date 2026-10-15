import { Kind } from '../world.js';

/**
 * Applies a JSON push body to the world. Lets any external producer (the iOS app, a script,
 * a future Ares adapter running elsewhere) feed the relay:
 * {
 *   "replace": false,
 *   "entities": [{"id":"p1","kind":"friend","state":0,"lat":..,"lon":..,"label":"VIPER","age":3}],
 *   "remove": ["p2"],
 *   "messages": [{"id":"o1","text":"Push to B","prio":1}]
 * }
 */
const KIND_NAMES = { friend: Kind.FRIEND, enemy: Kind.ENEMY, objective: Kind.OBJECTIVE, waypoint: Kind.WAYPOINT, base: Kind.BASE, hazard: Kind.HAZARD };

export function applyPush(world, body) {
  if (!body || typeof body !== 'object') throw new Error('body must be an object');
  if (body.replace) world.clear();
  const now = world.now();
  let count = 0;
  for (const e of body.entities ?? []) {
    const kind = typeof e.kind === 'string' ? KIND_NAMES[e.kind] : e.kind;
    if (kind === undefined) throw new Error(`unknown kind ${e.kind}`);
    world.upsert({ id: e.id, kind, state: e.state ?? 0, lat: Number(e.lat), lon: Number(e.lon), label: e.label ?? '', updatedAt: now - 1000 * (Number(e.age) || 0) });
    count++;
  }
  for (const id of body.remove ?? []) world.remove(id);
  for (const m of body.messages ?? []) world.postMessage({ id: m.id, text: m.text, prio: m.prio ?? 1 });
  return { applied: count, seq: world.seq };
}
