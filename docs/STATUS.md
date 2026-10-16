# Project status and next steps

Goal: show Ares Alpha (iPhone) team data on a Garmin fēnix 8 AMOLED, ideally inside a
native activity (data field), with a separate watch app + Garmin map as a fallback/extra.

## Key findings (research)

- Ares Alpha (Tdasoft, Romania) has **no public API, export, CoT/TAK or wearable support**.
  Its push notifications already mirror to the watch natively. Plan: generic pipeline now,
  reverse-engineer the Ares app traffic later as the real data source (user's own account;
  ToS risk accepted by user).
- Connect IQ data fields cannot draw on the native activity map. Map markers
  (`MapView`/`MapTrackView`) only work in a full watch app.
- Data fields may use `Communications` (web requests / phone messages) since API 5.0.0;
  fēnix 8 is CIQ 6.0.3. Data field memory limit 128 KB (current build uses ~20 KB).
- Two transports share one protocol ([PROTOCOL.md](PROTOCOL.md)):
  1. **Relay** – watch polls an HTTPS relay via the phone's Garmin Connect app. Works now.
  2. **Phone link** – iOS companion app using the Connect IQ iOS SDK (needs Xcode).
- iOS/Garmin Connect requires publicly trusted HTTPS → use a `cloudflared` tunnel or a
  hosted relay.

## Done

| Part | Path | State |
|---|---|---|
| Feed protocol v1 | `docs/PROTOCOL.md` | done |
| Relay + simulator + debug map | `relay/` | done, 10 tests pass (`npm test`) |
| Shared watch core | `watch/common/` | done |
| Radar data field (AresRadar) | `watch/datafield/` | builds (debug + release), verified end-to-end in simulator |
| Build script | `scripts/build.sh` | done; compiles relay URL/key into `AresBuild.mc` |

Watch app IDs: data field `4865da54310044768ef2196020fe5408`,
watch app (planned) `14a5fd12e1b144399ab7d68630a6d98b`.

## Local environment

### Current workstation (2026-10-16)

- Homebrew `connectiq-sdk-manager` 1.0.16 (`/Applications/SdkManager.app`), Connect IQ
  SDK 9.2.0 + simulator, fēnix 8 profiles (`fenix843mm`, `fenix847mm`, `fenix8pro47mm`,
  `fenix8solar47mm`, `fenix8solar51mm`).
- New 4096-bit RSA developer key (PKCS#8 DER) at `~/ciq/keys/developer_key.der`, mode 600.
  A 2048-bit key builds `.prg` files but `RELEASE=1` export fails with "Failed to extract
  developer signature for export"; 4096 works. This is **not** the previous workstation's
  key; recover the old one before signing updates for an existing store listing.
- `cloudflared` 2026.10.1 installed via Homebrew.
- Node.js v26.11.0. Only Xcode Command Line Tools (no full Xcode → iOS app not buildable).
- Verified: `scripts/build.sh datafield` (debug) and `RELEASE=1 scripts/build.sh datafield`
  (all 7 fēnix 8 variants) succeed; relay `npm test` 10/10.
- Verified end-to-end in the simulator (fenix847mm): data field → cloudflared HTTPS →
  local relay; HTTP 200 every ~5 s, sequence advances, entities/labels/objective header
  and order banner render; memory ~19.8 / 124.4 kB.

### Previous workstation

- Connect IQ SDK 9.2.0 and fēnix 8 device profiles were installed through SDK Manager.
- Developer key was at `~/ciq/keys/developer_key.der`.
- `cloudflared` was installed through Homebrew.

## How to run

```sh
# relay with simulator
cd relay && RELAY_KEY=devkey SIM_ANCHOR=56.9496,24.1052 VERBOSE=1 node src/main.js
# public HTTPS URL (changes on every restart)
cloudflared tunnel --url http://localhost:8787
# build the data field with that URL baked in
RELAY_URL=https://<x>.trycloudflare.com RELAY_KEY=devkey scripts/build.sh datafield
# run in simulator
SDK="$(cat ~/Library/Application\ Support/Garmin/ConnectIQ/current-sdk.cfg)"
"$SDK/bin/connectiq" & "$SDK/bin/monkeydo" build/AresRadar.prg fenix847mm
# with a debug build, SIM_POS=lat,lon gives the field a fixed position when there is no
# GPS fix, so the radar renders without Activity Data playback, and AresLog prints
# settings/request/response lines to the monkeydo console:
#   RELAY_URL=... RELAY_KEY=devkey SIM_POS=56.9496,24.1052 DEBUG=1 scripts/build.sh datafield
```

Simulator notes:

- The simulator enforces device HTTPS rules by default: a plain `http://localhost` relay
  answers 200 but the watch receives `-1001` (SECURE_CONNECTION_REQUIRED). Use the
  cloudflared URL, or untick Settings → "Use Device HTTPS Requirements".
- A refused connection (relay not running) is reported to the app as `404`.
- Re-running `monkeydo` against an already running simulator sometimes loads nothing and
  prints no console output; quit the simulator and start it again.
- `AresLog` (`watch/common/source/AresLog.mc`) is compiled out of release builds.

## Open issue (start here)

No known blocking issue. The earlier "field does not poll" report was caused by the
environment (field not running / plain-HTTP relay rejected by the simulator), not by the
polling logic: with HTTPS the link polls at `POLL_SECONDS`, backs off on errors and
recovers. Not yet verified on a physical watch.

## Next steps

1. Sideload the field to the physical fēnix 8 and verify it through Garmin Connect Mobile
   (needs the relay reachable over public HTTPS).
2. Watch app `watch/app` (Ares Map): radar view, `MapTrackView` with markers,
   messages list, menu (record activity, range, heading-up, transport).
3. `docs/WATCH_SETUP.md`: sideload `.prg` to `GARMIN/APPS` (OpenMTP on Mac), add the
   data field to an activity (1-field layout), relay hosting options.
4. iOS companion app `ios/` (SwiftUI + Connect IQ SDK, replies to watch `poll` messages).
5. `docs/ARES_REVERSE_ENGINEERING.md`: capture Ares traffic with Proxyman/mitmproxy,
   then implement `fetchSnapshot()` in `relay/src/sources/ares.js`.
6. `docs/ARCHITECTURE.md` and README quick start.
