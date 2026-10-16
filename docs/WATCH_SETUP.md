# Watch setup

## 1. Toolchain (macOS)

```sh
brew install --cask connectiq-sdk-manager   # or download it from developer.garmin.com
brew install cloudflared node
```

Open **SdkManager.app**, sign in with a Garmin account, then install:

- the latest Connect IQ SDK (9.x), and make it the current SDK;
- the device profiles `fenix843mm`, `fenix847mm`, `fenix8pro47mm`, `fenix8solar47mm`
  and `fenix8solar51mm`.

`scripts/build.sh` finds the SDK through
`~/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg`. To use a different
SDK, set `CIQ_SDK`.

## 2. Developer key

The key must be **4096-bit** RSA in PKCS#8 DER format. A 2048-bit key still builds
`.prg` files, but `RELEASE=1` export fails with "Failed to extract developer signature".

```sh
mkdir -p ~/ciq/keys && cd ~/ciq/keys
openssl genrsa -out developer_key.pem 4096
openssl pkcs8 -topk8 -inform PEM -outform DER -in developer_key.pem -out developer_key.der -nocrypt
chmod 600 developer_key.*
```

Keep the key private and backed up. Updates to a published app must be signed with the
same key. To use a different path, set `DEV_KEY`.

## 3. Relay over public HTTPS

The watch reaches the relay through Garmin Connect on the phone. That path only allows
publicly trusted HTTPS, so plain `http://` or self-signed certificates fail. You can
use either:

- **Quick tunnel** (testing): `cloudflared tunnel --url http://localhost:8787`. The URL
  changes on every restart, so rebuild after each restart.
- **Stable hosting**: a named Cloudflare tunnel, or the relay deployed to any HTTPS host.

Relay environment variables:

| Variable | Meaning |
|---|---|
| `PORT` | Listen port (default `8787`) |
| `RELAY_KEY` | Key the watch must send (`x-ares-key` header or `?k=`). Always set it outside local testing. |
| `ARES_SOURCE` | `sim` (default), `push` (data `POST`ed to `/v1/push`), or `ares` (not implemented yet) |
| `RELAY_PUSH_KEY` | Separate write key for `/v1/push` (defaults to `RELAY_KEY`) |
| `SIM_ANCHOR` | `lat,lon` where the simulated team is placed |
| `POLL_SECONDS` | Poll interval suggested to the watch (default 5) |
| `VERBOSE=1` | Log each request |

## 4. Build

```sh
RELAY_URL=https://<relay-host> RELAY_KEY=<key> scripts/build.sh all fenix847mm   # → build/*.prg
RELAY_URL=https://<relay-host> RELAY_KEY=<key> RELEASE=1 scripts/build.sh all     # → build/*.iq (all fēnix 8 variants)
```

Settings can also be kept in a `.env` file in the repository root, which is gitignored.
Sideloaded apps cannot be configured from Garmin Connect, so the relay URL and key are
compiled into the build. App settings only override them when the settings are not empty.

Debug-only options:

- `DEBUG=1` prints poll and response lines to the `monkeydo` console.
- `SIM_POS=lat,lon` sets a fixed position when there is no GPS.

Release builds compile both out.

Pick the `.prg` that matches the watch model: `fenix847mm` covers the fēnix 8 47mm and
51mm AMOLED. Run `ls "$SDK/../../Devices"` for the other profiles.

## 5. Sideload to the watch

1. Connect the watch by USB. On macOS, use [OpenMTP](https://openmtp.ganeshrvel.com/)
   because the watch uses MTP.
2. Copy `build/AresRadar.prg` and/or `build/AresMap.prg` into `GARMIN/APPS/`.
3. Disconnect. The watch installs the apps on reboot or disconnect.

## 6. Use

- **Data field**: open an activity's settings, then **Data Screens → Add New**, and
  choose a 1-field layout with the **AresRadar** field. In smaller field slots,
  it shows a mini radar or a pointer to the nearest objective.
- **Watch app**: start **Ares Map** from the apps list. The controls are listed in the
  [README](../README.md#watch-app-controls).
- The phone must have Garmin Connect running and connected to the watch.

## Simulator notes

- By default the simulator enforces device HTTPS rules. A plain `http://localhost`
  relay answers 200, but the app receives `-1001`. Use the tunnel URL, or turn off
  Settings → "Use Device HTTPS Requirements".
- A refused connection (relay not running) is reported to the app as `404`.
- If `monkeydo` loads nothing into a simulator that is already running, quit the
  simulator and start it again.
- In the simulator, buttons are pressed by clicking the watch's side buttons. A long
  press (the menu) needs a held click.
