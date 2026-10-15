import { distance } from './geo.js';
import { Kind } from './world.js';

export const PROTOCOL_VERSION = 1;

// Lower = more important when the entity budget is tight.
const KIND_PRIORITY = { [Kind.OBJECTIVE]: 0, [Kind.FRIEND]: 1, [Kind.ENEMY]: 2, [Kind.BASE]: 3, [Kind.HAZARD]: 4, [Kind.WAYPOINT]: 5 };

const e6 = (v) => Math.round(v * 1e6);

/**
 * Build the compact v1 feed (see docs/PROTOCOL.md).
 * @param {import('./world.js').World} world
 * @param {{q?: number, lat?: number, lon?: number, n?: number, poll?: number}} req lat/lon in degrees
 */
export function buildFeed(world, { q = 0, lat, lon, n = 32, poll = 5 } = {}) {
  const now = world.now();
  const base = { v: PROTOCOL_VERSION, q: world.seq, t: Math.floor(now / 1000), p: poll };
  if (q === world.seq) return { ...base, u: 0 };

  const hasPos = Number.isFinite(lat) && Number.isFinite(lon);
  const limit = Math.max(1, Math.min(64, n | 0 || 32));
  const ranked = [...world.entities.values()]
    .map((e) => ({ e, d: hasPos ? distance(lat, lon, e.lat, e.lon) : 0 }))
    .sort((a, b) => (KIND_PRIORITY[a.e.kind] ?? 9) - (KIND_PRIORITY[b.e.kind] ?? 9) || a.d - b.d)
    .slice(0, limit);

  return {
    ...base,
    u: 1,
    e: ranked.map(({ e }) => [e.id, e.kind, e.state, e6(e.lat), e6(e.lon), Math.max(0, Math.round((now - e.updatedAt) / 1000)), e.label]),
    m: world.messages.map((m) => [m.id, Math.max(0, Math.round((now - m.at) / 1000)), m.prio, m.text]),
  };
}
