"""Structural invariants of world generation.

Generates a handful of worlds at fixed seeds and checks that the map, the
regions, the nations and the population they carry hang together
consistently, and that generation is deterministic given a seed.
"""
from __future__ import annotations

import unittest

from grimoire.worldgen import generate_world

SEEDS = [101, 202, 303]


class TestWorldStructure(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.worlds = [generate_world(s) for s in SEEDS]

    def test_land_fraction(self):
        for w, seed in zip(self.worlds, SEEDS):
            p = w.planet
            total = p.w * p.h
            land = sum(1 for _ in p.land_tiles())
            frac = land / total
            self.assertGreaterEqual(frac, 0.2, f"seed {seed}: land fraction {frac:.3f} too low")
            self.assertLessEqual(frac, 0.4, f"seed {seed}: land fraction {frac:.3f} too high")

    def test_minimum_nations_and_regions(self):
        for w, seed in zip(self.worlds, SEEDS):
            self.assertGreaterEqual(len(w.nations), 15,
                                    f"seed {seed}: only {len(w.nations)} nations")
            self.assertGreaterEqual(len(w.regions), 80,
                                    f"seed {seed}: only {len(w.regions)} regions")

    def test_region_nation_bidirectional_consistency(self):
        for w, seed in zip(self.worlds, SEEDS):
            bad = []
            for rid, r in w.regions.items():
                nat = w.nations.get(r.nation)
                if nat is None or rid not in nat.regions:
                    bad.append((rid, r.nation))
            self.assertFalse(bad, f"seed {seed}: regions not listed back by their nation: {bad[:10]}")

    def test_every_nation_with_regions_has_a_valid_capital(self):
        for w, seed in zip(self.worlds, SEEDS):
            bad = []
            for nid, nat in w.nations.items():
                if not nat.regions:
                    continue
                cap = w.cities.get(nat.capital)
                if cap is None:
                    bad.append((nid, "no capital city"))
                elif cap.region not in nat.regions:
                    bad.append((nid, f"capital city {cap.id} sits in {cap.region}, "
                                     "not one of the nation's regions"))
            self.assertFalse(bad, f"seed {seed}: bad capitals: {bad[:10]}")

    def test_population_sums_are_consistent(self):
        for w, seed in zip(self.worlds, SEEDS):
            for nid, nat in w.nations.items():
                region_sum = sum(w.regions[r].pop for r in nat.regions if r in w.regions)
                self.assertAlmostEqual(
                    region_sum, nat.pop, delta=max(1.0, abs(nat.pop) * 1e-6),
                    msg=f"seed {seed}: nation {nid} pop {nat.pop} != region sum {region_sum}")
            world_sum = sum(n.pop for n in w.nations.values())
            self.assertAlmostEqual(
                world_sum, w.global_pop, delta=max(1.0, abs(w.global_pop) * 1e-6),
                msg=f"seed {seed}: world pop {w.global_pop} != nation sum {world_sum}")

    def test_no_region_has_zero_tiles(self):
        for w, seed in zip(self.worlds, SEEDS):
            empty = [rid for rid, r in w.regions.items() if len(r.tiles) == 0]
            self.assertFalse(empty, f"seed {seed}: regions with zero tiles: {empty}")

    def test_every_city_has_a_real_region(self):
        for w, seed in zip(self.worlds, SEEDS):
            bad = [cid for cid, c in w.cities.items() if c.region not in w.regions]
            self.assertFalse(bad, f"seed {seed}: cities pointing at a non-existent region: {bad[:10]}")

    def test_gdp_per_capita_spread_at_least_10x(self):
        for w, seed in zip(self.worlds, SEEDS):
            vals = sorted(n.gdp_per_capita() for n in w.nations.values() if n.pop > 0)
            self.assertGreater(len(vals), 1, f"seed {seed}: not enough nations to compare")
            poorest, richest = vals[0], vals[-1]
            self.assertGreater(poorest, 0, f"seed {seed}: non-positive GDP/capita found")
            ratio = richest / poorest
            self.assertGreaterEqual(
                ratio, 10.0,
                f"seed {seed}: richest/poorest GDP per capita ratio only {ratio:.2f}x "
                f"({poorest:.0f} .. {richest:.0f})")


class TestDeterminism(unittest.TestCase):
    def test_same_seed_twice_matches(self):
        seed = SEEDS[0]
        w1 = generate_world(seed)
        w2 = generate_world(seed)
        names1 = sorted((n.name, n.formal, n.pop) for n in w1.nations.values())
        names2 = sorted((n.name, n.formal, n.pop) for n in w2.nations.values())
        self.assertEqual(names1, names2,
                          "generating the same seed twice produced different nations/populations")
        self.assertEqual(len(w1.regions), len(w2.regions))
        self.assertEqual(w1.global_pop, w2.global_pop)
        self.assertEqual(w1.global_gdp, w2.global_gdp)


if __name__ == "__main__":
    unittest.main()
