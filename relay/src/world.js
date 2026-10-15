import { EventEmitter } from 'node:events';

export const Kind = Object.freeze({ FRIEND: 0, ENEMY: 1, OBJECTIVE: 2, WAYPOINT: 3, BASE: 4, HAZARD: 5 });
export const State = Object.freeze({ OK: 0, HIT: 1, MEDIC: 2, SUPPORT: 3, STALE: 4, OURS: 1, THEIRS: 2, CONTESTED: 3 });

const MAX_MESSAGES = 5;
const MAX_LABEL = 12;

/**
 * In-memory picture of the game. Sources write into it; the feed reads from it.
 * Every mutation bumps `seq` so watches can skip unchanged polls.
 */
export class World extends EventEmitter {
  constructor({ now = () => Date.now() } = {}) {
    super();
    this.now = now;
    this.seq = 1;
    this.entities = new Map();
    this.messages = [];
    this.viewer = null;
    this.nextNumericId = 1;
    this.idMap = new Map();
  }

  /** Stable small integer id for any external id (string/number). */
  numericId(externalId) {
    const key = String(externalId);
    let id = this.idMap.get(key);
    if (id === undefined) {
      id = this.nextNumericId++;
      this.idMap.set(key, id);
    }
    return id;
  }

  upsert({ id, kind, state = 0, lat, lon, label = '', updatedAt }) {
    if (!Number.isFinite(lat) || !Number.isFinite(lon)) throw new Error(`entity ${id}: invalid position`);
    const nid = this.numericId(id);
    const prev = this.entities.get(nid);
    const next = {
      id: nid,
      externalId: String(id),
      kind: kind | 0,
      state: state | 0,
      lat,
      lon,
      label: String(label).slice(0, MAX_LABEL),
      updatedAt: updatedAt ?? this.now(),
    };
    if (prev && prev.kind === next.kind && prev.state === next.state && prev.lat === next.lat &&
        prev.lon === next.lon && prev.label === next.label && prev.updatedAt === next.updatedAt) {
      return prev;
    }
    this.entities.set(nid, next);
    this.touch();
    return next;
  }

  remove(externalId) {
    const nid = this.idMap.get(String(externalId));
    if (nid !== undefined && this.entities.delete(nid)) this.touch();
  }

  clear() {
    if (this.entities.size || this.messages.length) {
      this.entities.clear();
      this.messages = [];
      this.touch();
    }
  }

  postMessage({ id, text, prio = 1, at }) {
    const mid = id ?? `m${this.now()}-${Math.random().toString(36).slice(2, 7)}`;
    if (this.messages.some((m) => m.externalId === String(mid))) return;
    this.messages.unshift({ id: this.numericId(`msg:${mid}`), externalId: String(mid), text: String(text).slice(0, 120), prio: prio | 0, at: at ?? this.now() });
    this.messages.length = Math.min(this.messages.length, MAX_MESSAGES);
    this.touch();
  }

  setViewer(lat, lon) {
    this.viewer = { lat, lon, at: this.now() };
    this.emit('viewer', this.viewer);
  }

  touch() {
    this.seq++;
    this.emit('change', this.seq);
  }
}
