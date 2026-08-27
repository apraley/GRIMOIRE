"""Data-integrity checks for the static content tables.

These tests import only the content_*.py modules (and a few small helpers) —
no world generation, no simulation. They should run in well under a second
and are meant to catch typos and dangling references in the game's data
tables: goods, industries, technologies, backgrounds, policies, etc.
"""
from __future__ import annotations

import unittest

from grimoire.content_econ import BASKET, GOODS, INDUSTRIES, RESOURCE_GATES
from grimoire.content_tech import TECHS
from grimoire.content_social import (BACKGROUNDS, PERKS, POLICIES,
                                      POLICY_IDEOLOGY, SKILLS)
from grimoire.content_conflict import OPS, RACKETS, UNITS


class TestIndustriesAndGoods(unittest.TestCase):
    def test_industry_outputs_are_real_goods(self):
        bad = [(ind, d["out"]) for ind, d in INDUSTRIES.items() if d["out"] not in GOODS]
        self.assertFalse(bad, f"industries with an output good not in GOODS: {bad}")

    def test_industry_inputs_are_real_goods(self):
        bad = []
        for ind, d in INDUSTRIES.items():
            for g in d["inp"]:
                if g not in GOODS:
                    bad.append((ind, g))
        self.assertFalse(bad, f"industries with an input good not in GOODS: {bad}")

    def test_industry_gating_tech_exists(self):
        bad = [(ind, d["tech"]) for ind, d in INDUSTRIES.items()
               if d["tech"] and d["tech"] not in TECHS]
        self.assertFalse(bad, f"industries gated by an unknown technology: {bad}")

    def test_resource_gate_industries_exist(self):
        bad = [ind for ind in RESOURCE_GATES if ind not in INDUSTRIES]
        self.assertFalse(bad, f"RESOURCE_GATES names industries that do not exist: {bad}")

    def test_every_good_has_a_producer(self):
        producers = {d["out"] for d in INDUSTRIES.values()}
        bad = [g for g in GOODS if g not in producers]
        self.assertFalse(bad, f"goods with no industry that produces them: {bad}")

    def test_basket_goods_exist(self):
        bad = [g for g in BASKET if g not in GOODS]
        self.assertFalse(bad, f"consumption-basket goods not in GOODS: {bad}")


class TestTechTree(unittest.TestCase):
    def test_prereqs_exist(self):
        bad = [(t, p) for t, d in TECHS.items() for p in d["p"] if p not in TECHS]
        self.assertFalse(bad, f"technologies with an unknown prerequisite: {bad}")

    def test_graph_is_acyclic(self):
        WHITE, GREY, BLACK = 0, 1, 2
        color = {t: WHITE for t in TECHS}
        cycles = []

        def visit(t, stack):
            color[t] = GREY
            stack.append(t)
            for p in TECHS[t]["p"]:
                if p not in TECHS:
                    continue
                if color[p] == GREY:
                    cycles.append(stack[stack.index(p):] + [p])
                elif color[p] == WHITE:
                    visit(p, stack)
            stack.pop()
            color[t] = BLACK

        for t in TECHS:
            if color[t] == WHITE:
                visit(t, [])
        self.assertFalse(cycles, f"cycles found in the technology prerequisite graph: {cycles}")

    def test_unlock_effects_name_real_industries(self):
        bad = [(t, e["unlock"]) for t, d in TECHS.items()
               for e in [d["e"]] if "unlock" in e and e["unlock"] not in INDUSTRIES]
        self.assertFalse(bad, f"tech 'unlock' effects naming a non-existent industry: {bad}")


class TestBackgrounds(unittest.TestCase):
    def test_skills_exist(self):
        bad = [(bg, s) for bg, d in BACKGROUNDS.items() for s in d["skills"] if s not in SKILLS]
        self.assertFalse(bad, f"backgrounds granting an unknown skill: {bad}")

    def test_perks_exist(self):
        bad = [(bg, p) for bg, d in BACKGROUNDS.items() for p in d["perks"] if p not in PERKS]
        self.assertFalse(bad, f"backgrounds granting an unknown perk: {bad}")


class TestConflictContent(unittest.TestCase):
    def test_op_governing_skills_exist(self):
        bad = [(k, d["skill"]) for k, d in OPS.items() if d["skill"] not in SKILLS]
        self.assertFalse(bad, f"intelligence operations governed by an unknown skill: {bad}")

    def test_racket_governing_skills_exist(self):
        bad = [(k, d["skill"]) for k, d in RACKETS.items() if d["skill"] not in SKILLS]
        self.assertFalse(bad, f"rackets governed by an unknown skill: {bad}")

    def test_unit_tech_exists(self):
        bad = [(u, d["tech"]) for u, d in UNITS.items() if d["tech"] and d["tech"] not in TECHS]
        self.assertFalse(bad, f"military units gated by an unknown technology: {bad}")


class TestPolicyIdeology(unittest.TestCase):
    def test_every_policy_is_in_the_ideology_mapping(self):
        missing = [k for k in POLICIES if k not in POLICY_IDEOLOGY]
        self.assertFalse(missing, f"policies with no entry in POLICY_IDEOLOGY: {missing}")

    def test_ideology_mapping_names_only_real_policies(self):
        extra = [k for k in POLICY_IDEOLOGY if k not in POLICIES]
        self.assertFalse(extra, f"POLICY_IDEOLOGY names non-existent policies: {extra}")


if __name__ == "__main__":
    unittest.main()
