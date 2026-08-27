"""Every screen renderer must produce a list of strings without raising.

Runs each view against a freshly generated world with a player, for a
sampled entity of every kind, with colour on and colour off.
"""
from __future__ import annotations

import unittest

from grimoire import ui, views
from grimoire.content_econ import RESOURCE_KINDS
from grimoire.player import create_player
from grimoire.worldgen import generate_world

SEED = 777


class TestViews(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.w = generate_world(SEED)
        nat = next(n for n in cls.w.living_nations() if len(n.regions) > 0)
        create_player(cls.w, "Dossier Subject", "diplomat", nat.id, True, 51)
        cls.nation = nat
        cls.region = cls.w.regions[nat.regions[0]]
        cls.city = next(c for c in cls.w.nation_cities(nat.id))
        cls.person = next(p for p in cls.w.people.values()
                          if p.alive and p.id != "PLAYER")
        cls.org = next(o for o in cls.w.orgs.values() if o.alive)

    def setUp(self):
        self.addCleanup(ui.set_color, True)

    def _check(self, fn, *args, **kwargs):
        for colour in (True, False):
            ui.set_color(colour)
            with self.subTest(fn=getattr(fn, "__name__", str(fn)), colour=colour):
                out = fn(*args, **kwargs)
                self.assertIsInstance(out, list)
                self.assertTrue(out, "view produced no lines at all")
                for line in out:
                    self.assertIsInstance(line, str)

    def test_dashboard(self):
        self._check(views.dashboard, self.w)

    def test_map_political(self):
        self._check(views.map_view, self.w, "political")

    def test_map_terrain(self):
        self._check(views.map_view, self.w, "terrain")

    def test_map_climate(self):
        self._check(views.map_view, self.w, "climate")

    def test_map_resource(self):
        kind = RESOURCE_KINDS[0]
        self._check(views.map_view, self.w, f"resource:{kind}")

    def test_news(self):
        self._check(views.news_view, self.w)

    def test_market(self):
        self._check(views.market_view, self.w)

    def test_wars(self):
        self._check(views.war_view, self.w)

    def test_rankings(self):
        self._check(views.rankings_view, self.w)

    def test_tech(self):
        self._check(views.tech_view, self.w, self.nation)

    def test_intel(self):
        self._check(views.intel_view, self.w)

    def test_ledger(self):
        self._check(views.ledger_view, self.w)

    def test_victory(self):
        self._check(views.victory_view, self.w)

    def test_skills(self):
        self._check(views.skills_view, self.w)

    def test_timeline(self):
        self._check(views.timeline_view, self.w)

    def test_people(self):
        self._check(views.people_view, self.w)

    def test_help(self):
        self._check(views.help_view, self.w)

    def test_help_on_a_specific_action(self):
        self._check(views.help_view, self.w, "look")

    def test_nation_view(self):
        self._check(views.nation_view, self.w, self.nation)

    def test_region_view(self):
        self._check(views.region_view, self.w, self.region)

    def test_city_view(self):
        self._check(views.city_view, self.w, self.city)

    def test_person_view(self):
        self._check(views.person_view, self.w, self.person)

    def test_org_view(self):
        self._check(views.org_view, self.w, self.org)


if __name__ == "__main__":
    unittest.main()
