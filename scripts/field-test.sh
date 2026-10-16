#!/usr/bin/env bash
# One command for a physical-watch test: starts the relay, exposes it over public HTTPS with
# cloudflared, builds the watch apps with that URL compiled in and keeps everything running
# (and the Mac awake) until Ctrl-C.
#   scripts/field-test.sh [datafield|app|all] [device]      (default: all fenix847mm)
# Env (or .env in repo root):
#   RELAY_KEY                 reused if set; otherwise generated once and saved to .env
#   PORT                      local relay port (default 8787)
#   ARES_SOURCE, SIM_ANCHOR   passed to the relay (default: simulated team around the watch)
#   CLOUDFLARE_TUNNEL_TOKEN   with RELAY_URL: run a named tunnel instead of a quick tunnel,
#                             so the URL (and the sideloaded build) survives restarts
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[ -f "$ROOT/.env" ] && set -a && . "$ROOT/.env" && set +a

WHAT="${1:-all}"
DEVICE="${2:-fenix847mm}"
PORT="${PORT:-8787}"
OUT="$ROOT/build"
mkdir -p "$OUT"
command -v cloudflared >/dev/null || { echo "cloudflared missing: brew install cloudflared"; exit 1; }
command -v node >/dev/null || { echo "node missing: brew install node"; exit 1; }
if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "Port $PORT is already in use (old relay still running?). Stop it or set PORT."; exit 1
fi

if [ -z "${RELAY_KEY:-}" ]; then
  RELAY_KEY="$(openssl rand -hex 8)"
  echo "RELAY_KEY=$RELAY_KEY" >> "$ROOT/.env"
  echo "Generated RELAY_KEY and saved it to .env"
fi

PIDS=()
cleanup() {
  trap - EXIT INT TERM
  for p in "${PIDS[@]}"; do kill "$p" 2>/dev/null || true; done
  echo; echo "Stopped relay and tunnel. A quick-tunnel URL is gone now: the next run needs a new sideload."
}
trap cleanup EXIT INT TERM

RELAY_KEY="$RELAY_KEY" PORT="$PORT" VERBOSE=1 node "$ROOT/relay/src/main.js" > "$OUT/relay.log" 2>&1 &
PIDS+=($!)
for _ in $(seq 1 20); do curl -fs "http://localhost:$PORT/health" >/dev/null && break; sleep 0.5; done
curl -fs "http://localhost:$PORT/health" >/dev/null || { cat "$OUT/relay.log"; echo "Relay did not start"; exit 1; }

if [ -n "${CLOUDFLARE_TUNNEL_TOKEN:-}" ]; then
  [ -n "${RELAY_URL:-}" ] || { echo "CLOUDFLARE_TUNNEL_TOKEN needs RELAY_URL (the tunnel's public hostname)"; exit 1; }
  URL="${RELAY_URL%/}"
  cloudflared tunnel --no-autoupdate run --token "$CLOUDFLARE_TUNNEL_TOKEN" > "$OUT/tunnel.log" 2>&1 &
  PIDS+=($!)
else
  cloudflared tunnel --no-autoupdate --url "http://localhost:$PORT" > "$OUT/tunnel.log" 2>&1 &
  PIDS+=($!)
  URL=""
  for _ in $(seq 1 60); do
    URL="$(grep -Eo 'https://[a-z0-9-]+\.trycloudflare\.com' "$OUT/tunnel.log" | head -1 || true)"
    [ -n "$URL" ] && break
    sleep 1
  done
  [ -n "$URL" ] || { cat "$OUT/tunnel.log"; echo "No tunnel URL from cloudflared"; exit 1; }
fi

echo "Waiting for $URL to become reachable..."
ok=0
for _ in $(seq 1 60); do
  if curl -fs -m 5 "$URL/health" >/dev/null 2>&1; then ok=1; break; fi
  sleep 2
done
[ "$ok" = 1 ] || { tail -20 "$OUT/tunnel.log"; echo "Tunnel not reachable"; exit 1; }
code="$(curl -s -m 5 -o /dev/null -w '%{http_code}' "$URL/v1/feed?k=$RELAY_KEY")"
[ "$code" = 200 ] || { echo "Feed check through the tunnel returned HTTP $code"; exit 1; }

# Device build: never bake in simulator-only options from .env.
rm -f "$OUT/AresRadar.prg" "$OUT/AresMap.prg"
ARES_NO_DOTENV=1 RELAY_URL="$URL" RELAY_KEY="$RELAY_KEY" SIM_POS="" DEBUG="" RELEASE=0 "$ROOT/scripts/build.sh" "$WHAT" "$DEVICE" \
  2>&1 | grep -v "Cannot access internal symbol" || true
for f in AresRadar AresMap; do
  case "$WHAT:$f" in datafield:AresMap|app:AresRadar) continue ;; esac
  [ -f "$OUT/$f.prg" ] || { echo "Build failed: $OUT/$f.prg missing"; exit 1; }
done
{ echo "url=$URL"; echo "device=$DEVICE"; echo "built=$(date '+%Y-%m-%d %H:%M:%S')"; } > "$OUT/field-test.txt"

# Keep the Mac awake while this script runs (lid closed on battery still sleeps).
caffeinate -dims -w $$ &
PIDS+=($!)

cat <<EOF

================================================================
 Relay:      $URL   (key in .env)
 Dashboard:  http://localhost:$PORT/   (simulated team, live)
 Built for:  $DEVICE
   build/AresRadar.prg  -> data field
   build/AresMap.prg    -> watch app
 Sideload:   OpenMTP -> copy the .prg files to GARMIN/APPS/ on the watch, then unplug.
 Checklist:  docs/FIELD_TEST.md
 KEEP THIS RUNNING during the test. Restarting creates a new URL
 and requires rebuilding + sideloading again.
================================================================
 Watch requests (each poll = one line):
EOF
tail -n +1 -f "$OUT/relay.log" &
PIDS+=($!)

# Exit (and clean up) as soon as the relay or the tunnel dies.
while kill -0 "${PIDS[0]}" 2>/dev/null && kill -0 "${PIDS[1]}" 2>/dev/null; do sleep 5; done
echo "Relay or tunnel exited; see build/relay.log and build/tunnel.log"
exit 1
