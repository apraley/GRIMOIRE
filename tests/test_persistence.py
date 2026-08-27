"""Save/load round-trip tests.

Generates a world, creates a player, runs 60 days, serializes with
serial.dumps, deserializes, and checks that the restored world matches the
original on the headline numbers plus the RNG's next draw. Also exercises
save_file/load_file through a temporary file.
"""
from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from grimoire import engine, serial
from grimoire.player import create_player
from grimoire.worldgen import generate_world

SEED = 4242


def snapshot(w):
    return dict(
        day=w.clock.day,
        n_nations=len(w.nations),
        n_regions=len(w.regions),
        n_people=len(w.people),
        gdp={nid: n.gdp for nid, n in w.nations.items()},
        pop={nid: n.pop for nid, n in w.nations.items()},
        money=w.player.money,
        holdings=dict(w.player.holdings),
    )


class TestPersistenceRoundTrip(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.w = generate_world(SEED)
        nat = next(n for n in cls.w.living_nations() if len(n.regions) > 0)
        create_player(cls.w, "Persistent Subject", "banker", nat.id, True, 44)
        for _ in range(60):
            engine.tick(cls.w)
        cls.before = snapshot(cls.w)
        cls.dumped = serial.dumps(cls.w)
        cls.w2 = serial.loads(cls.dumped)

    def test_clock_day_matches(self):
        self.assertEqual(self.w2.clock.day, self.before["day"])

    def test_nation_count_matches(self):
        self.assertEqual(len(self.w2.nations), self.before["n_nations"])

    def test_region_count_matches(self):
        self.assertEqual(len(self.w2.regions), self.before["n_regions"])

    def test_person_count_matches(self):
        self.assertEqual(len(self.w2.people), self.before["n_people"])

    def test_all_nation_gdp_matches(self):
        bad = []
        for nid, gdp in self.before["gdp"].items():
            got = self.w2.nations[nid].gdp
            if abs(got - gdp) > max(1e-6, abs(gdp) * 1e-9):
                bad.append((nid, gdp, got))
        self.assertFalse(bad, f"nation GDP mismatch after round-trip: {bad[:10]}")

    def test_all_nation_population_matches(self):
        bad = []
        for nid, pop in self.before["pop"].items():
            got = self.w2.nations[nid].pop
            if abs(got - pop) > max(1e-6, abs(pop) * 1e-9):
                bad.append((nid, pop, got))
        self.assertFalse(bad, f"nation population mismatch after round-trip: {bad[:10]}")

    def test_player_money_matches(self):
        self.assertAlmostEqual(self.w2.player.money, self.before["money"], delta=1e-6)

    def test_player_holdings_match(self):
        self.assertEqual(self.w2.player.holdings, self.before["holdings"])

    def test_rng_resumes_to_the_same_next_value(self):
        # Neither draw here has been consumed by anything else, so the two
        # streams should still be lined up after the round-trip.
        r1 = self.w.rng.random()
        r2 = self.w2.rng.random()
        self.assertEqual(r1, r2)

    def test_ticking_both_further_keeps_the_clock_in_step(self):
        for _ in range(20):
            engine.tick(self.w)
        for _ in range(20):
            engine.tick(self.w2)
        self.assertEqual(self.w.clock.day, self.w2.clock.day)


class TestSaveLoadFile(unittest.TestCase):
    def test_round_trip_through_a_temp_file(self):
        w = generate_world(SEED + 1)
        nat = next(n for n in w.living_nations() if len(n.regions) > 0)
        create_player(w, "File Subject", "criminal", nat.id, False, 29)
        for _ in range(10):
            engine.tick(w)
        before = snapshot(w)
        with tempfile.TemporaryDirectory() as tmp:
            path = str(Path(tmp) / "save.grim")
            n_bytes = serial.save_file(w, path)
            self.assertGreater(n_bytes, 0)
            self.assertTrue(Path(path).exists())
            w2 = serial.load_file(path)
        after = snapshot(w2)
        self.assertEqual(after["day"], before["day"])
        self.assertEqual(after["n_nations"], before["n_nations"])
        self.assertEqual(after["n_regions"], before["n_regions"])
        self.assertEqual(after["n_people"], before["n_people"])
        self.assertAlmostEqual(after["money"], before["money"], delta=1e-6)


if __name__ == "__main__":
    unittest.main()
