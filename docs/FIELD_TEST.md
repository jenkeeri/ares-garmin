# Hardware field test (fēnix 8 AMOLED 47mm)

Goal: confirm that the data field and the Ares Map app run stably on the real watch and
receive the relay feed through Garmin Connect. Visual polish comes after this test.

## 1. Start relay, tunnel and build (Mac)

```sh
scripts/field-test.sh            # = all fenix847mm; or: datafield | app [device]
```

The script:

- creates a `RELAY_KEY` in `.env` if it is missing
- starts the relay in simulator mode and a `cloudflared` quick tunnel
- checks the public `/health` and `/v1/feed` endpoints
- builds `build/AresRadar.prg` and `build/AresMap.prg` with the tunnel URL compiled in
- keeps the Mac awake

Keep the script running for the whole test, with the Mac plugged in and online. Its
logs are `build/relay.log` and `build/tunnel.log`. The URL and build time are in
`build/field-test.txt`.

The quick-tunnel URL changes every time the script restarts. After a restart, sideload
the new `.prg` files again.

The simulated team spawns around the first watch position the relay receives. Watch the
team and your own position live at `http://localhost:8787/?k=<RELAY_KEY>`.

## 2. Sideload

1. Connect the watch by USB and open [OpenMTP](https://openmtp.ganeshrvel.com/).
2. Copy both `.prg` files into `GARMIN/APPS/`.
3. Disconnect the watch.
4. Make sure the phone has Garmin Connect open and connected to the watch.

## 3. Checklist

Data field (AresRadar):

- [ ] Add it to an activity, for example Hike: **Data Screens → Add New → 1 field →
      AresRadar**.
- [ ] Before GPS fix: `NO GPS`. After the fix, team markers appear within about 10 s.
- [ ] Markers move, and the range and heading update while walking.
- [ ] Run for 30 minutes or more with the screen on and off. Note any crash (an IQ
      error icon), freeze or reboot.
- [ ] Try 2- and 3-field layouts too (mini radar or objective pointer).

Ares Map app:

- [ ] Starts from the apps list. The radar shows `NO GPS`, and then the team.
- [ ] UP and DOWN zoom.
- [ ] **Tapping the screen does nothing.**
- [ ] START starts recording (red dot) and pauses it (yellow dot).
- [ ] BACK while recording opens the Activity menu (Resume, Save & exit, Discard & exit).
      Saved activities appear in Garmin Connect.
- [ ] Long-press UP opens the menu. Check that Map, Messages, heading-up and auto range
      work.
- [ ] Map page: markers on the Garmin map. START enters browse mode.
- [ ] The watch vibrates on new messages: a short pulse normally, a double pulse for
      urgent ones (enemy, medic). The relay simulator sends them periodically. Applies
      to both the field and the app.

Stability and battery:

- [ ] Turn phone Bluetooth off for a minute, then back on. The status shows
      `NO PHONE` and then recovers by itself.
- [ ] Stop the script (Ctrl-C). The status shows `RELAY ERR` or `RELAY DOWN`. Restart
      the script; it needs a rebuild and sideload, because the URL changes.
- [ ] Note the battery % at the start and end, and the time between.

## Status labels on the watch

| Label | Codes | Meaning / fix |
|---|---|---|
| `NO PHONE` | -104, -2, -3, -4 | No Bluetooth link to the phone. Check Garmin Connect. |
| `TIMEOUT` | -300 | Request timed out. Phone or network is slow. |
| `BAD KEY` | 401, 403 | `RELAY_KEY` in the build does not match the relay. |
| `NEED HTTPS` | -1001 | URL is not public HTTPS. |
| `TOO BIG` | -402, -403 | Response too large. The watch asks for fewer entities automatically. |
| `RELAY ERR` | -400, -1002 | Response is not JSON, usually a dead quick tunnel. Restart the script and re-sideload. |
| `RELAY DOWN` | 404, 502, 503, 530, 1033 | Relay or tunnel is not reachable. |
| `BUSY` | -101 | Too many requests are queued. This clears on its own. |
| `ERR n` | other | Note the code. |

## Report back

For each item, report pass or fail. For failures, include:

- the label or code shown
- the time
- a photo
- the matching lines from `build/relay.log`

The CIQ crash log is on the watch at `GARMIN/APPS/LOGS/CIQ_LOG.YML`. Copy it with
OpenMTP if anything crashes.
