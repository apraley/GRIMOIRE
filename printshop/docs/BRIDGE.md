# PRINT SHOP bridge protocol

PRINT SHOP talks to real printers through a small companion service on your
LAN. The Playdate polls it over plain HTTP using `playdate.network.http`
(Playdate OS/SDK 2.7 or later). A reference implementation is
`bridge/printshop_bridge.py`.

## Why a bridge?

A Bambu Lab A1 Mini in LAN mode publishes its status over **MQTT on TLS
port 8883**, with a self-signed certificate and a LAN access code. The
Playdate SDK has HTTP/HTTPS and raw TCP, but it has no MQTT client and no
way to trust a custom certificate. So PRINT SHOP does not talk to the
printer directly. The bridge:

1. subscribes to `device/<serial>/report` (user `bblp`, password = access code),
2. merges the incremental `print` reports into one full picture,
3. serves that picture over HTTP, raw and normalized,
4. forwards pause, resume and stop requests to `device/<serial>/request`.

Everything else in PRINT SHOP works without a bridge. The DEMO SIM provider
is a complete simulated printer.

## Running it

```sh
cd printshop/bridge
python3 printshop_bridge.py --demo                  # simulated printer
pip install paho-mqtt
python3 printshop_bridge.py --bambu 192.168.1.40 01P00A123456789 12345678
```

On the Playdate, go to **Settings > CONNECTION** and pick `LOCAL BRIDGE`
(uses the normalized status) or `BAMBU (VIA BRIDGE)` (uses the raw Bambu
report and maps it on the device). Then set **BRIDGE HOST** to your
computer's IP and **BRIDGE PORT** to 8787. The first request shows the
system's network permission dialog.

## Endpoints

| Method | Path | Used by | Body / response |
|---|---|---|---|
| GET | `/api/v1/status` | `LocalBridgeProvider` | normalized status (below) |
| GET | `/api/v1/bambu/report` | `BambuProvider` | `{ "print": { ...raw Bambu report... } }` |
| POST | `/api/v1/pause` | LocalBridge | `{}` → `{ "ok": true }` |
| POST | `/api/v1/resume` | LocalBridge | `{}` → `{ "ok": true }` |
| POST | `/api/v1/cancel` | LocalBridge | `{}` → `{ "ok": true }` |
| POST | `/api/v1/start` | LocalBridge (optional) | `{ jobId, name, file }` → 409 if unsupported |
| POST | `/api/v1/bambu/command` | BambuProvider | `{ "print": { "command": "pause", "sequence_id": "1" } }` |

Errors return a non-2xx status with `{ "ok": false, "error": "..." }`.

## Normalized status (schema 1)

```json
{
  "schema": 1,
  "state": "PRINTING",
  "message": "",
  "temps":    { "nozzle": 219.8, "nozzleTarget": 220, "bed": 60.1, "bedTarget": 60 },
  "progress": { "pct": 42.5, "layer": 51, "totalLayers": 120, "elapsedSec": 2400, "remainingSec": 3300 },
  "job":      { "id": "j1", "name": "CABLE CLIPS x12", "material": "PLA", "color": "BLACK", "grams": 18 },
  "spools":   { "mode": "ams", "active": 1,
                "slots": [ { "slot": 1, "material": "PLA", "color": "000000FF", "pct": 61 } ] },
  "events":   [ { "seq": 12, "type": "log", "text": "LAYER 50 REACHED" } ]
}
```

* `state` is one of `IDLE HEATING PRINTING PAUSED ERROR COMPLETE OFFLINE`.
* `job` may be `null`. If `job.id` matches a PRINT SHOP queue id it is linked
  directly. Otherwise the job is matched by name, or adopted into the queue
  as a new job marked "Started on the printer".
* `events` are optional. The provider shows each `log` event once, tracked
  by `seq`.
* The bridge does not need to emit completion or failure events. The
  provider works them out from state changes:
  `PRINTING/PAUSED/HEATING -> COMPLETE` finishes the job (filament, history,
  stats, maintenance hours, Captain), and `... -> ERROR` opens the failure
  log.

## Bambu field mapping

| Bambu `print` field | PRINT SHOP |
|---|---|
| `gcode_state` IDLE/INIT | IDLE |
| `gcode_state` PREPARE/SLICING, or RUNNING with `stg_cur` 2 or 7 | HEATING |
| `gcode_state` RUNNING | PRINTING |
| `gcode_state` PAUSE | PAUSED |
| `gcode_state` FINISH | COMPLETE |
| `gcode_state` FAILED | ERROR |
| `mc_percent`, `layer_num`, `total_layer_num` | progress |
| `mc_remaining_time` (minutes) | remainingSec (elapsed is estimated from percent) |
| `nozzle_temper`, `nozzle_target_temper`, `bed_temper`, `bed_target_temper` | temps |
| `subtask_name` / `gcode_file` (`.gcode.3mf` stripped) | job name |
| `ams.ams[0].tray[]` (`tray_type`, `tray_color`, `remain`), `ams.tray_now` | AMS lite slots and the active slot |
| `vt_tray` | external spool |
| `print_error` | message `ERROR XXXXXXXX` |

The same mapping exists twice and both copies are tested:
`BambuProvider.mapReport` (Lua, on the device) and `normalize_bambu`
(Python, in the bridge).

## Writing a bridge for another printer

Serve `/api/v1/status` in the normalized shape. OctoPrint, Moonraker/Klipper
and PrusaLink all expose enough to fill it in. Accept the three POST
commands if you want remote control. No Playdate code changes are needed:
pick `LOCAL BRIDGE` in Settings.
