# Ares → Garmin feed protocol (v1)

One compact payload format is used by **both** transports:

* **Relay (HTTPS)** – the watch polls `GET {relay}/v1/feed` via `Communications.makeWebRequest`
  (proxied through Garmin Connect Mobile on the iPhone).
* **Phone link (BLE)** – the iOS companion app answers watch `poll` messages with
  `ConnectIQ.sendMessage(...)`. The dictionary is identical to the JSON body below.

The format is optimised for the fenix 8 data-field budget (128 KB total app memory) and the
slow Garmin BLE channel: arrays instead of objects, integers instead of floats, short keys.

## Watch → source

Relay: query string. Phone link: a dictionary sent with `Communications.transmit`.

| key   | type   | meaning                                                        |
|-------|--------|----------------------------------------------------------------|
| `c`   | string | command, always `"poll"` (phone link only)                     |
| `q`   | int    | last feed sequence the watch has (`0` = none)                  |
| `lat` | int    | watch latitude × 1e6 (omitted when no GPS fix)                 |
| `lon` | int    | watch longitude × 1e6                                          |
| `n`   | int    | max entities wanted (default 32)                               |
| `k`   | string | relay access key (relay only, also accepted as `X-Ares-Key`)   |

## Source → watch

```json
{
  "v": 1,
  "q": 1234,
  "u": 1,
  "t": 1792091418,
  "p": 5,
  "e": [[id, kind, state, latE6, lonE6, ageS, "label"], ...],
  "m": [[id, ageS, prio, "text"], ...]
}
```

| key | meaning |
|-----|---------|
| `v` | protocol version (1) |
| `q` | feed sequence; increments whenever the world changes |
| `u` | `1` = full update follows, `0` = nothing changed since the watch's `q` (`e`/`m` omitted) |
| `t` | source unix time (s) |
| `p` | suggested poll interval (s) |
| `e` | entities, most important first, at most `n` |
| `m` | most recent orders/messages (newest first, max 5) |

### Entity kinds (`kind`)

| value | kind | `state` meaning |
|------:|------|-----------------|
| 0 | friendly player | 0 ok · 1 hit/dead · 2 medic needed · 3 needs support · 4 offline/stale |
| 1 | enemy / hostile contact | 0 seen · 4 stale |
| 2 | objective | 0 neutral · 1 ours · 2 enemy · 3 contested |
| 3 | waypoint / marker | unused (0) |
| 4 | base / respawn | 0 ours · 2 enemy |
| 5 | hazard / no-go | unused (0) |

`ageS` is the age of the position in seconds when the payload was produced; the watch keeps
aging it locally. `label` is ≤ 12 characters (callsign / objective name).

### Message priority (`prio`)

`0` info · `1` order (short vibration + banner) · `2` urgent (long vibration + banner).

## Sizes

A full update with 32 entities is ~1.5 KB of JSON; an unchanged response is ~40 bytes.
Polling every 3–5 s is therefore cheap when nothing moves.
