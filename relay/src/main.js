import { World } from './world.js';
import { createServer } from './server.js';
import { SimSource } from './sources/sim.js';
import { AresSource } from './sources/ares.js';

const env = process.env;
const port = Number(env.PORT ?? 8787);
const source = env.ARES_SOURCE ?? 'sim';
const key = env.RELAY_KEY ?? '';
if (!key) console.warn('[relay] RELAY_KEY not set: feed is public. Set RELAY_KEY for anything but local testing.');

const world = new World();
let anchor;
if (env.SIM_ANCHOR) {
  const [lat, lon] = env.SIM_ANCHOR.split(',').map(Number);
  anchor = { lat, lon };
}

if (source === 'sim') new SimSource(world, { anchor }).start();
else if (source === 'ares') new AresSource(world).start();
else if (source !== 'push') throw new Error(`unknown ARES_SOURCE ${source} (sim | push | ares)`);

const verbose = env.VERBOSE === '1';
createServer(world, { key, pushKey: env.RELAY_PUSH_KEY, pollSeconds: Number(env.POLL_SECONDS ?? 5), log: verbose ? (m) => console.log(`[relay] ${m}`) : undefined })
  .listen(port, () => console.log(`[relay] source=${source} listening on http://localhost:${port}`));
