"""Tests for the companion bridge:  python3 -m unittest discover printshop/bridge"""
import json
import threading
import unittest
import urllib.request
from http.server import ThreadingHTTPServer

import printshop_bridge as pb


class MappingTest(unittest.TestCase):
    def test_bambu_report_maps_like_the_lua_adapter(self):
        doc = pb.normalize_bambu({"print": {
            "gcode_state": "RUNNING", "mc_percent": 40, "mc_remaining_time": 30,
            "layer_num": 48, "total_layer_num": 120, "nozzle_temper": 219.5,
            "nozzle_target_temper": 220, "bed_temper": 59.8, "bed_target_temper": 60,
            "subtask_name": "cable_clip_v3.gcode.3mf", "print_error": 0,
            "ams": {"tray_now": "1", "ams": [{"id": "0", "tray": [
                {"id": "0", "tray_type": "PLA", "tray_color": "000000FF", "remain": 61},
                {"id": "1", "tray_type": "PETG-CF", "tray_color": "FFFFFFFF", "remain": 80}]}]},
        }})
        self.assertEqual(doc["state"], "PRINTING")
        self.assertEqual(doc["progress"]["elapsedSec"], 1200)
        self.assertEqual(doc["progress"]["remainingSec"], 1800)
        self.assertEqual(doc["job"]["name"], "cable_clip_v3")
        self.assertEqual(doc["job"]["material"], "PETG")
        self.assertEqual(doc["spools"]["active"], 2)
        self.assertEqual(pb.normalize_bambu({"gcode_state": "FAILED", "print_error": 50348044})["message"],
                         "ERROR 0300400C")

    def test_heating_stage(self):
        self.assertEqual(pb.normalize_bambu({"gcode_state": "RUNNING", "stg_cur": 2})["state"], "HEATING")


class ServerTest(unittest.TestCase):
    def setUp(self):
        self.backend = pb.DemoBackend(speed=1000)
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), pb.make_handler(self.backend))
        self.port = self.server.server_address[1]
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()

    def get(self, path):
        with urllib.request.urlopen(f"http://127.0.0.1:{self.port}{path}") as r:
            return json.loads(r.read())

    def post(self, path, payload=None):
        req = urllib.request.Request(f"http://127.0.0.1:{self.port}{path}",
                                     data=json.dumps(payload or {}).encode(), method="POST")
        try:
            with urllib.request.urlopen(req) as r:
                return r.status, json.loads(r.read())
        except urllib.error.HTTPError as e:
            return e.code, json.loads(e.read())

    def test_status_schema(self):
        s = self.get("/api/v1/status")
        self.assertEqual(s["schema"], 1)
        self.assertIn(s["state"], pb.STATES)
        for key in ("temps", "progress", "job", "spools", "events"):
            self.assertIn(key, s)
        raw = self.get("/api/v1/bambu/report")
        self.assertIn("gcode_state", raw["print"])

    def test_commands(self):
        self.backend.state = "PRINTING"
        code, body = self.post("/api/v1/pause")
        self.assertEqual((code, body["ok"]), (200, True))
        self.assertEqual(self.get("/api/v1/status")["state"], "PAUSED")
        code, body = self.post("/api/v1/bambu/command", {"print": {"command": "resume", "sequence_id": "1"}})
        self.assertTrue(body["ok"])
        code, body = self.post("/api/v1/start", {"name": "x"})
        self.assertEqual(code, 409)


if __name__ == "__main__":
    unittest.main()
