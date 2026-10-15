/**
 * Ares Alpha source — placeholder until the private Ares Alpha protocol is captured.
 * See docs/ARES_REVERSE_ENGINEERING.md for the capture procedure. Once endpoints are known,
 * implement `fetchSnapshot()` to return {players, objectives, markers, messages} and keep
 * the mapping below.
 */
import { Kind } from '../world.js';

export class AresSource {
  constructor(world, { pollMs = 3000, client } = {}) {
    this.world = world;
    this.pollMs = pollMs;
    this.client = client;
    this.timer = null;
  }

  start() {
    if (!this.client) {
      throw new Error('Ares source not implemented yet: capture the Ares Alpha API first (docs/ARES_REVERSE_ENGINEERING.md) or use ARES_SOURCE=sim / push');
    }
    const loop = async () => {
      try {
        this.apply(await this.client.fetchSnapshot());
      } catch (err) {
        console.error(`[ares] ${err.message}`);
      }
      this.timer = setTimeout(loop, this.pollMs);
    };
    loop();
  }

  stop() { clearTimeout(this.timer); }

  /** Maps a normalized snapshot into the world. Kept separate so it can be unit tested. */
  apply({ players = [], objectives = [], markers = [], messages = [] }) {
    const seen = new Set();
    for (const p of players) { seen.add(String(p.id)); this.world.upsert({ id: p.id, kind: p.hostile ? Kind.ENEMY : Kind.FRIEND, state: p.state ?? 0, lat: p.lat, lon: p.lon, label: p.name, updatedAt: p.updatedAt }); }
    for (const o of objectives) { seen.add(String(o.id)); this.world.upsert({ id: o.id, kind: Kind.OBJECTIVE, state: o.owner ?? 0, lat: o.lat, lon: o.lon, label: o.name }); }
    for (const m of markers) { seen.add(String(m.id)); this.world.upsert({ id: m.id, kind: m.kind ?? Kind.WAYPOINT, state: 0, lat: m.lat, lon: m.lon, label: m.name }); }
    for (const e of [...this.world.entities.values()]) if (!seen.has(e.externalId)) this.world.remove(e.externalId);
    for (const m of messages) this.world.postMessage({ id: m.id, text: m.text, prio: m.prio ?? 1, at: m.at });
  }
}
