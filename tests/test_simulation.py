"""Run the engine for a long stretch and check nothing explodes.

The economic model is a hard balancing problem that is still being tuned
elsewhere, so this module deliberately separates two kinds of concern:

  * SAFETY invariants (no NaN/Infinity, no negative population or stock,
    bounded 0..1 fields, prices strictly positive, policy values within
    their declared bounds) are asserted strictly — a violation here is a
    real bug.

  * MAGNITUDE-OF-DRIFT (how far GDP wanders in 400 days) is measured and
    printed, but is not itself a hard failure — see test_report_drift.
"""
from __future__ import annotations

import math
import unittest

from grimoire import engine
from grimoire.content_social import POLICIES
from grimoire.worldgen import generate_world

SEEDS = [11, 55]
DAYS = 400


def _is_bad_float(x) -> bool:
    return isinstance(x, float) and (x != x or math.isinf(x))


def find_bad_floats(obj, path="", seen=None, max_depth=5):
    """Recursively walk an object's attributes (and dict/list/set contents)
    looking for NaN or +/-Infinity float values. Returns a list of
    (path, value) tuples for anything bad found."""
    if seen is None:
        seen = set()
    problems = []
    if max_depth < 0:
        return problems
    if isinstance(obj, float):
        if _is_bad_float(obj):
            problems.append((path, obj))
        return problems
    if isinstance(obj, (str, bytes, int, bool)) or obj is None:
        return problems
    oid = id(obj)
    if oid in seen:
        return problems
    seen.add(oid)
    if isinstance(obj, dict):
        for k, v in obj.items():
            problems += find_bad_floats(v, f"{path}[{k!r}]", seen, max_depth - 1)
        return problems
    if isinstance(obj, (list, tuple, set, frozenset)):
        for i, v in enumerate(obj):
            problems += find_bad_floats(v, f"{path}[{i}]", seen, max_depth - 1)
        return problems
    if hasattr(obj, "__dict__"):
        for k, v in vars(obj).items():
            problems += find_bad_floats(v, f"{path}.{k}", seen, max_depth - 1)
        return problems
    return problems


class TestSimulationSafety(unittest.TestCase):
    """Runs each seed for DAYS days once (setUpClass), shared by every test."""

    @classmethod
    def setUpClass(cls):
        cls.runs = []
        for seed in SEEDS:
            w = generate_world(seed)
            start_pop = w.global_pop
            start_gdp = w.global_gdp
            for _ in range(DAYS):
                engine.tick(w, with_player=False)
            cls.runs.append(dict(seed=seed, w=w, start_pop=start_pop, start_gdp=start_gdp))

    def test_no_nan_or_infinity(self):
        for run in self.runs:
            w = run["w"]
            problems = []
            for nid, nat in w.nations.items():
                problems += [(f"nation {nid}{p}", v) for p, v in find_bad_floats(nat)]
            for rid, r in w.regions.items():
                problems += [(f"region {rid}{p}", v) for p, v in find_bad_floats(r)]
            for oid, o in w.orgs.items():
                problems += [(f"org {oid}{p}", v) for p, v in find_bad_floats(o)]
            for pid, person in w.people.items():
                problems += [(f"person {pid}{p}", v) for p, v in find_bad_floats(person)]
            self.assertFalse(
                problems,
                f"seed {run['seed']}: NaN/Infinity found after {DAYS} days: {problems[:15]}")

    def test_population_stays_in_sane_band(self):
        for run in self.runs:
            w = run["w"]
            ratio = w.global_pop / max(run["start_pop"], 1.0)
            self.assertGreaterEqual(
                ratio, 0.5,
                f"seed {run['seed']}: world population fell to {ratio:.3f}x of its start")
            self.assertLessEqual(
                ratio, 2.0,
                f"seed {run['seed']}: world population rose to {ratio:.3f}x of its start")

    def test_policy_values_within_declared_bounds(self):
        for run in self.runs:
            w = run["w"]
            bad = []
            for nid, nat in w.nations.items():
                for k, v in nat.policy.items():
                    d = POLICIES[k]
                    if not (d["lo"] - 1e-6 <= v <= d["hi"] + 1e-6):
                        bad.append((nid, k, v, d["lo"], d["hi"]))
            self.assertFalse(bad, f"seed {run['seed']}: policy values out of bounds: {bad[:15]}")

    def test_zero_one_fields_stay_bounded(self):
        fields = ["stability", "legitimacy", "unrest", "corruption"]
        for run in self.runs:
            w = run["w"]
            bad = []
            for nid, nat in w.nations.items():
                for f in fields:
                    v = getattr(nat, f)
                    if not (-1e-6 <= v <= 1 + 1e-6):
                        bad.append((nid, f, v))
            for rid, r in w.regions.items():
                for f in ("control", "health", "unrest", "employment"):
                    v = getattr(r, f)
                    if not (-1e-6 <= v <= 1 + 1e-6):
                        bad.append((rid, f, v))
            for pid, person in w.people.items():
                if not (-1e-6 <= person.health <= 1 + 1e-6):
                    bad.append((pid, "health", person.health))
            self.assertFalse(bad, f"seed {run['seed']}: 0..1 fields out of range: {bad[:15]}")

    def test_market_prices_strictly_positive(self):
        for run in self.runs:
            w = run["w"]
            bad = [(g, p) for g, p in w.market.price.items() if not p > 0]
            self.assertFalse(bad, f"seed {run['seed']}: non-positive market prices: {bad}")

    def test_no_negative_population_or_stockpiles(self):
        for run in self.runs:
            w = run["w"]
            neg_pop = [(nid, nat.pop) for nid, nat in w.nations.items() if nat.pop < 0]
            self.assertFalse(neg_pop, f"seed {run['seed']}: negative national population: {neg_pop}")
            neg_stock = []
            for nid, nat in w.nations.items():
                for g, v in nat.stockpile.items():
                    if v < 0:
                        neg_stock.append((nid, g, v))
            self.assertFalse(neg_stock, f"seed {run['seed']}: negative stockpiles: {neg_stock[:15]}")
            neg_region_pop = [(rid, r.pop) for rid, r in w.regions.items() if r.pop < 0]
            self.assertFalse(neg_region_pop,
                              f"seed {run['seed']}: negative region population: {neg_region_pop}")

    def test_report_drift(self):
        """Not a strict pass/fail gate on the economic model — the balancing
        work is in progress elsewhere. This prints world GDP drift over the
        run so it shows up in verbose test output, and only fails on truly
        extreme blow-ups (>90% collapse or >20x runaway growth), which would
        indicate the model has gone actually unstable rather than merely
        imbalanced."""
        for run in self.runs:
            w = run["w"]
            ratio = w.global_gdp / max(run["start_gdp"], 1.0)
            print(f"\n  [drift] seed {run['seed']}: world GDP {run['start_gdp']:,.0f} -> "
                  f"{w.global_gdp:,.0f} ({ratio:.3f}x over {DAYS} days)")
            self.assertGreater(
                ratio, 0.10,
                f"seed {run['seed']}: world GDP collapsed to {ratio:.3f}x of its start "
                "(more than 90% loss) — likely a genuine instability, not just imbalance")
            self.assertLess(
                ratio, 20.0,
                f"seed {run['seed']}: world GDP rose to {ratio:.3f}x of its start "
                "(more than 20x growth) — likely a genuine instability, not just imbalance")


if __name__ == "__main__":
    unittest.main()
