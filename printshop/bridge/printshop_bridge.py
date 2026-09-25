#!/usr/bin/env python3
"""PRINT SHOP companion bridge.

A tiny HTTP+JSON service on your LAN that the Playdate polls
(LocalBridgeProvider / BambuProvider in source/providers/). It exists because
the Playdate can speak plain HTTP (SDK 2.7+, playdate.network.http) but not
MQTT over TLS with a printer's self-signed certificate.

Modes
  --demo                     simulated printer (no hardware; for testing)
  --bambu HOST SERIAL CODE   Bambu Lab printer in LAN mode (A1 Mini, A1, P1, X1)
                             Needs: pip install paho-mqtt

Endpoints (schema documented in docs/BRIDGE.md)
  GET  /api/v1/status          normalized status  (LocalBridgeProvider)
  GET  /api/v1/bambu/report    raw Bambu `print` report (BambuProvider)
  POST /api/v1/pause|resume|cancel
  POST /api/v1/bambu/command   raw Bambu request payload, forwarded to MQTT
  GET  /                       human-readable status page

Standard library only, except paho-mqtt for --bambu.
"""
import argparse
import json
import math
import ssl
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

STATES = {"IDLE", "HEATING", "PRINTING", "PAUSED", "ERROR", "COMPLETE", "OFFLINE"}

# Bambu gcode_state -> PRINT SHOP state (keep in sync with bambu_provider.lua).
BAMBU_STATE = {
    "IDLE": "IDLE", "INIT": "IDLE", "PREPARE": "HEATING", "SLICING": "HEATING",
    "RUNNING": "PRINTING", "PAUSE": "PAUSED", "FINISH": "COMPLETE",
    "FAILED": "ERROR", "OFFLINE": "OFFLINE",
}
MATERIALS = ["PLA", "PETG", "TPU", "ABS", "ASA"]


def material_of(tray_type):
    t = (tray_type or "").upper()
    for m in MATERIALS:
        if t.startswith(m):
            return m
    return "OTHER" if t else ""


def normalize_bambu(report):
    """Bambu `print` report -> bridge schema 1 (same logic as the Lua mapper)."""
    r = report.get("print", report)
    state = BAMBU_STATE.get(str(r.get("gcode_state", "")).upper(), "IDLE")
    if state == "PRINTING" and r.get("stg_cur") in (2, 7):
        state = "HEATING"
    pct = float(r.get("mc_percent") or 0)
    remaining_min = float(r.get("mc_remaining_time") or 0)
    elapsed = int(remaining_min * 60 * pct / (100 - pct)) if 0 < pct < 100 and remaining_min > 0 else 0
    name = str(r.get("subtask_name") or r.get("gcode_file") or "")
    for suffix in (".gcode.3mf", ".3mf", ".gcode"):
        if name.endswith(suffix):
            name = name[: -len(suffix)]
    slots, active = [], None
    ams = r.get("ams") or {}
    units = ams.get("ams") or []
    if units and isinstance(units[0], dict):
        for i, tray in enumerate(units[0].get("tray") or []):
            slots.append({
                "slot": int(tray.get("id", i)) + 1,
                "material": material_of(tray.get("tray_type")),
                "color": tray.get("tray_color", ""),
                "pct": max(0, min(100, float(tray.get("remain") or 0))),
            })
    try:
        now = int(ams.get("tray_now"))
        if now < 254:
            active = now + 1
    except (TypeError, ValueError):
        pass
    err = int(r.get("print_error") or 0)
    message = f"ERROR {err:08X}" if err else ("PRINT FAILED" if state == "ERROR" else "")
    job = None
    if name:
        mat = slots[active - 1]["material"] if active and active <= len(slots) else "OTHER"
        job = {"name": name, "material": mat or "OTHER", "grams": 0}
    return {
        "schema": 1,
        "state": state,
        "message": message,
        "temps": {
            "nozzle": float(r.get("nozzle_temper") or 0),
            "nozzleTarget": float(r.get("nozzle_target_temper") or 0),
            "bed": float(r.get("bed_temper") or 0),
            "bedTarget": float(r.get("bed_target_temper") or 0),
        },
        "progress": {
            "pct": pct, "layer": int(r.get("layer_num") or 0),
            "totalLayers": int(r.get("total_layer_num") or 0),
            "elapsedSec": elapsed, "remainingSec": int(remaining_min * 60),
        },
        "job": job,
        "spools": {"mode": "ams" if slots else "external", "active": active, "slots": slots},
    }


class EventLog:
    """Numbered log lines the Playdate shows on PRINT WATCH."""

    def __init__(self):
        self.seq = 0
        self.items = []
        self.lock = threading.Lock()

    def add(self, text):
        with self.lock:
            self.seq += 1
            self.items.append({"seq": self.seq, "type": "log", "text": text})
            self.items = self.items[-20:]

    def recent(self):
        with self.lock:
            return list(self.items)


class DemoBackend:
    """A simulated print so the Playdate side can be tested with no printer."""

    def __init__(self, speed=30.0):
        self.speed = speed
        self.log = EventLog()
        self.lock = threading.Lock()
        self.start_job("BRIDGE BENCHY", minutes=45, layers=240)

    def start_job(self, name, minutes=45, layers=200):
        with self.lock:
            self.name, self.total, self.layers = name, minutes * 60, layers
            self.elapsed, self.state, self.t0 = 0.0, "HEATING", time.time()
            self.nozzle, self.bed = 25.0, 25.0
        self.log.add(f"{name} STARTED")

    def tick(self):
        with self.lock:
            now = time.time()
            dt = (now - self.t0) * self.speed
            self.t0 = now
            if self.state == "HEATING":
                self.nozzle = min(220.0, self.nozzle + 4 * dt)
                self.bed = min(60.0, self.bed + 1.2 * dt)
                if self.nozzle >= 220 and self.bed >= 60:
                    self.state = "PRINTING"
                    self.log.add("TEMPS REACHED")
            elif self.state == "PRINTING":
                self.elapsed = min(self.total, self.elapsed + dt)
                self.nozzle = 220 + math.sin(now) * 0.8
                if self.elapsed >= self.total:
                    self.state = "COMPLETE"
                    self.log.add(f"{self.name} COMPLETE")
            elif self.state in ("COMPLETE", "ERROR", "IDLE"):
                self.nozzle = max(25.0, self.nozzle - 0.5 * dt)
                self.bed = max(25.0, self.bed - 0.2 * dt)

    def status(self):
        self.tick()
        with self.lock:
            pct = 100.0 * self.elapsed / self.total if self.total else 0
            active = self.state in ("HEATING", "PRINTING", "PAUSED")
            return {
                "schema": 1,
                "state": self.state,
                "message": "",
                "temps": {"nozzle": round(self.nozzle, 1), "nozzleTarget": 220 if active else 0,
                          "bed": round(self.bed, 1), "bedTarget": 60 if active else 0},
                "progress": {"pct": round(pct, 1), "layer": int(self.layers * pct / 100),
                             "totalLayers": self.layers, "elapsedSec": int(self.elapsed),
                             "remainingSec": int(self.total - self.elapsed)},
                "job": {"name": self.name, "material": "PLA", "color": "ORANGE", "grams": 15},
                "spools": {"mode": "external", "active": 1,
                           "slots": [{"slot": 1, "material": "PLA", "color": "FF6A13FF", "pct": 70}]},
                "events": self.log.recent(),
            }

    def raw_report(self):
        s = self.status()
        inv = {v: k for k, v in BAMBU_STATE.items()}
        return {"print": {
            "gcode_state": inv.get(s["state"], "IDLE"), "mc_percent": s["progress"]["pct"],
            "mc_remaining_time": s["progress"]["remainingSec"] // 60,
            "layer_num": s["progress"]["layer"], "total_layer_num": s["progress"]["totalLayers"],
            "nozzle_temper": s["temps"]["nozzle"], "nozzle_target_temper": s["temps"]["nozzleTarget"],
            "bed_temper": s["temps"]["bed"], "bed_target_temper": s["temps"]["bedTarget"],
            "subtask_name": s["job"]["name"] + ".gcode.3mf", "print_error": 0,
        }}

    def command(self, name, payload=None):
        with self.lock:
            if name == "pause" and self.state in ("PRINTING", "HEATING"):
                self.state = "PAUSED"
            elif name == "resume" and self.state == "PAUSED":
                self.state = "PRINTING"
            elif name in ("cancel", "stop") and self.state in ("PRINTING", "HEATING", "PAUSED"):
                self.state = "ERROR"
            else:
                return False, f"cannot {name} while {self.state}"
        self.log.add(name.upper())
        return True, ""

    def bambu_command(self, payload):
        cmd = (payload.get("print") or {}).get("command", "")
        return self.command({"stop": "cancel"}.get(cmd, cmd))


class BambuBackend:
    """Bambu Lab LAN-mode MQTT client. The printer must be in LAN mode (or
    LAN-only with developer mode on newer firmware); CODE is the LAN access
    code shown on the printer's screen."""

    def __init__(self, host, serial, code):
        try:
            import paho.mqtt.client as mqtt  # noqa: F401
        except ImportError as exc:
            raise SystemExit("--bambu needs paho-mqtt: pip install paho-mqtt") from exc
        import paho.mqtt.client as mqtt
        self.serial = serial
        self.report = {}
        self.lock = threading.Lock()
        self.log = EventLog()
        self.last_state = None
        self.seq = 0
        try:
            self.client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION1)
        except AttributeError:
            self.client = mqtt.Client()
        self.client.username_pw_set("bblp", code)
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE        # printer uses a self-signed certificate
        self.client.tls_set_context(ctx)
        self.client.on_connect = self._on_connect
        self.client.on_message = self._on_message
        self.client.connect(host, 8883, keepalive=60)
        self.client.loop_start()

    def _on_connect(self, client, userdata, flags, rc):
        client.subscribe(f"device/{self.serial}/report")
        self.publish({"pushing": {"sequence_id": "0", "command": "pushall"}})
        self.log.add("CONNECTED TO PRINTER")

    def _on_message(self, client, userdata, msg):
        try:
            data = json.loads(msg.payload)
        except ValueError:
            return
        p = data.get("print")
        if not isinstance(p, dict):
            return
        with self.lock:
            # Reports are incremental: merge into the last full picture.
            self.report.update(p)
            state = self.report.get("gcode_state")
        if state and state != self.last_state:
            self.log.add(f"STATE {state}")
            self.last_state = state

    def publish(self, payload):
        self.client.publish(f"device/{self.serial}/request", json.dumps(payload))

    def status(self):
        with self.lock:
            doc = normalize_bambu(dict(self.report)) if self.report else {
                "schema": 1, "state": "OFFLINE", "message": "WAITING FOR PRINTER"}
        doc["events"] = self.log.recent()
        return doc

    def raw_report(self):
        with self.lock:
            return {"print": dict(self.report)}

    def command(self, name, payload=None):
        cmd = {"cancel": "stop"}.get(name, name)
        if cmd not in ("pause", "resume", "stop"):
            return False, f"unsupported command {name}"
        self.seq += 1
        self.publish({"print": {"sequence_id": str(self.seq), "command": cmd}})
        self.log.add(cmd.upper() + " SENT")
        return True, ""

    def bambu_command(self, payload):
        cmd = (payload.get("print") or {}).get("command", "")
        if cmd not in ("pause", "resume", "stop"):
            return False, "only pause/resume/stop are forwarded"
        self.publish(payload)
        return True, ""


def make_handler(backend):
    class Handler(BaseHTTPRequestHandler):
        server_version = "PrintShopBridge/1"

        def _send(self, code, obj):
            body = json.dumps(obj).encode()
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, fmt, *args):  # quieter console
            pass

        def do_GET(self):
            if self.path == "/api/v1/status":
                self._send(200, backend.status())
            elif self.path == "/api/v1/bambu/report":
                self._send(200, backend.raw_report())
            elif self.path == "/":
                s = backend.status()
                html = f"<pre>PRINT SHOP bridge\n\n{json.dumps(s, indent=2)}</pre>".encode()
                self.send_response(200)
                self.send_header("Content-Type", "text/html")
                self.send_header("Content-Length", str(len(html)))
                self.end_headers()
                self.wfile.write(html)
            else:
                self._send(404, {"ok": False, "error": "not found"})

        def do_POST(self):
            length = int(self.headers.get("Content-Length") or 0)
            try:
                payload = json.loads(self.rfile.read(length) or b"{}")
            except ValueError:
                return self._send(400, {"ok": False, "error": "bad json"})
            if self.path == "/api/v1/bambu/command":
                ok, err = backend.bambu_command(payload)
            elif self.path in ("/api/v1/pause", "/api/v1/resume", "/api/v1/cancel"):
                ok, err = backend.command(self.path.rsplit("/", 1)[1], payload)
            elif self.path == "/api/v1/start":
                ok, err = False, "start jobs from the printer or slicer"
            else:
                return self._send(404, {"ok": False, "error": "not found"})
            self._send(200 if ok else 409, {"ok": ok, "error": err})

    return Handler


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--port", type=int, default=8787)
    ap.add_argument("--bind", default="0.0.0.0")
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--demo", action="store_true", help="simulated printer")
    g.add_argument("--bambu", nargs=3, metavar=("HOST", "SERIAL", "ACCESS_CODE"))
    ap.add_argument("--speed", type=float, default=30.0, help="demo time multiplier")
    args = ap.parse_args(argv)
    backend = DemoBackend(args.speed) if args.demo else BambuBackend(*args.bambu)
    server = ThreadingHTTPServer((args.bind, args.port), make_handler(backend))
    print(f"PRINT SHOP bridge on http://{args.bind}:{args.port}  ({'demo' if args.demo else 'bambu'})")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
