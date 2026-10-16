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
  fēnix 8 is CIQ 6.0.3. Data field memory limit 128 KB (current build uses ~17.5 KB).
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
| Radar data field (AresRadar) | `watch/datafield/` | builds cleanly, renders in simulator |
| Build script | `scripts/build.sh` | done; compiles relay URL/key into `AresBuild.mc` |

Watch app IDs: data field `4865da54310044768ef2196020fe5408`,
watch app (planned) `14a5fd12e1b144399ab7d68630a6d98b`.

## Local environment (not in repo)

- Connect IQ SDK 9.2.0 via SDK Manager (`~/Library/Application Support/Garmin/ConnectIQ`),
  fēnix 8 device profiles downloaded. User's watch profile: `fenix847mm`.
- Developer key: `~/ciq/keys/developer_key.der`.
- `cloudflared` installed via Homebrew. Xcode is **not** installed.

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
# then Simulation → Activity Data → Start + ▶ so compute() runs
```

## Open issue (start here)

In the simulator `compute()` is called every second but `AresLink.tick()` never reaches
the request (no `makeWebRequest`, relay sees nothing). Suspects:
1. `_url` empty (settings override / `AresBuild` value) → check `isConfigured()`.
2. `_inFlightSince` stuck, or `_lastReqAt`/interval logic with `System.getTimer()`.
3. Old simulator settings file: delete
   `$TMPDIR/com.garmin.connectiq/GARMIN/APPS/SETTINGS/ARESRADAR.SET`.
Also verify a GPS fix in the simulator (header shows "NO GPS"); the link should poll anyway.

## Next steps

1. Fix the polling issue above; verify radar with sim data + simulated GPS.
2. Watch app `watch/app` (Ares Map): radar view, `MapTrackView` with markers,
   messages list, menu (record activity, range, heading-up, transport).
3. `docs/WATCH_SETUP.md`: sideload `.prg` to `GARMIN/APPS` (OpenMTP on Mac), add the
   data field to an activity (1-field layout), relay hosting options.
4. iOS companion app `ios/` (SwiftUI + Connect IQ SDK, replies to watch `poll` messages).
5. `docs/ARES_REVERSE_ENGINEERING.md`: capture Ares traffic with Proxyman/mitmproxy,
   then implement `fetchSnapshot()` in `relay/src/sources/ares.js`.
6. `docs/ARCHITECTURE.md` and README quick start.
