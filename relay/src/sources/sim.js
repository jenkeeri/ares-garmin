import { offset, distance, bearing } from '../geo.js';
import { Kind, State } from '../world.js';

const CALLSIGNS = ['VIPER', 'GHOST', 'NOMAD', 'RAVEN', 'TANGO', 'HAWK'];
const ORDERS = [
  ['Push to OBJ {o}', 1],
  ['Hold position, wait for signal', 1],
  ['Regroup at BASE', 1],
  ['Enemy squad moving on OBJ {o}!', 2],
  ['UAV scan complete', 0],
  ['Medic needed near OBJ {o}', 2],
];

/**
 * Simulated game around an anchor: friendlies walking between objectives, objectives changing
 * owner, intermittent enemy UAV contacts and periodic orders. Used for watch testing until the
 * real Ares Alpha source is available.
 */
export class SimSource {
  constructor(world, { anchor, tickMs = 2000, rng = Math.random } = {}) {
    this.world = world;
    this.anchor = anchor ?? null;
    this.tickMs = tickMs;
    this.rng = rng;
    this.timer = null;
    this.tickCount = 0;
    this.onViewer = (v) => { if (!this.anchor) this.setup(v.lat, v.lon); };
  }

  start() {
    this.world.on('viewer', this.onViewer);
    if (this.anchor) this.setup(this.anchor.lat, this.anchor.lon);
    this.timer = setInterval(() => this.tick(), this.tickMs);
    this.timer.unref?.();
  }

  stop() {
    clearInterval(this.timer);
    this.world.off('viewer', this.onViewer);
  }

  setup(lat, lon) {
    this.anchor = { lat, lon };
    const r = this.rng;
    this.objectives = ['A', 'B', 'C'].map((name, i) => {
      const [olat, olon] = offset(lat, lon, 180 + 140 * i, 40 + i * 110 + r() * 30);
      return { id: `obj-${name}`, name, lat: olat, lon: olon, owner: State.THEIRS * (i % 2) };
    });
    const [blat, blon] = offset(lat, lon, 120, 220);
    this.base = { lat: blat, lon: blon };
    this.players = CALLSIGNS.slice(0, 5).map((cs, i) => {
      const [plat, plon] = offset(lat, lon, 20 + r() * 80, r() * 360);
      return { id: `p-${cs}`, cs, lat: plat, lon: plon, hdg: r() * 360, state: State.OK, target: i % 3, stateUntil: 0 };
    });
    this.enemies = [];
    this.world.clear();
    for (const o of this.objectives) this.world.upsert({ id: o.id, kind: Kind.OBJECTIVE, state: o.owner, lat: o.lat, lon: o.lon, label: `OBJ ${o.name}` });
    this.world.upsert({ id: 'base', kind: Kind.BASE, state: State.OURS, lat: blat, lon: blon, label: 'BASE' });
    this.world.postMessage({ text: 'Game started - sim mode', prio: 1 });
    this.tick();
  }

  tick() {
    if (!this.anchor) return;
    const r = this.rng;
    this.tickCount++;
    const now = this.world.now();

    for (const p of this.players) {
      if (p.stateUntil && now > p.stateUntil) { p.state = State.OK; p.stateUntil = 0; }
      if (p.state === State.OK && r() < 0.01) {
        p.state = r() < 0.5 ? State.MEDIC : State.HIT;
        p.stateUntil = now + 45000;
      }
      if (p.state === State.OK || p.state === State.SUPPORT) {
        const t = this.objectives[p.target];
        if (distance(p.lat, p.lon, t.lat, t.lon) < 25) p.target = Math.floor(r() * this.objectives.length);
        const want = bearing(p.lat, p.lon, t.lat, t.lon);
        p.hdg = want + (r() - 0.5) * 70;
        [p.lat, p.lon] = offset(p.lat, p.lon, 1.5 * (this.tickMs / 1000) * (0.5 + r()), p.hdg);
      }
      this.world.upsert({ id: p.id, kind: Kind.FRIEND, state: p.state, lat: p.lat, lon: p.lon, label: p.cs });
    }

    if (r() < 0.04) {
      const o = this.objectives[Math.floor(r() * this.objectives.length)];
      o.owner = [State.OK, State.OURS, State.THEIRS, State.CONTESTED][Math.floor(r() * 4)];
      this.world.upsert({ id: o.id, kind: Kind.OBJECTIVE, state: o.owner, lat: o.lat, lon: o.lon, label: `OBJ ${o.name}` });
    }

    if (r() < 0.05) {
      const o = this.objectives[Math.floor(r() * this.objectives.length)];
      const [elat, elon] = offset(o.lat, o.lon, 30 + r() * 120, r() * 360);
      const id = `e-${this.tickCount}`;
      this.enemies.push({ id, at: now });
      this.world.upsert({ id, kind: Kind.ENEMY, state: 0, lat: elat, lon: elon, label: 'UAV' });
    }
    for (const e of this.enemies.filter((x) => now - x.at > 90000)) this.world.remove(e.id);
    this.enemies = this.enemies.filter((x) => now - x.at <= 90000);

    if (this.tickCount % 45 === 0) {
      const [text, prio] = ORDERS[Math.floor(r() * ORDERS.length)];
      const o = this.objectives[Math.floor(r() * this.objectives.length)];
      this.world.postMessage({ text: text.replace('{o}', o.name), prio });
    }
  }
}
