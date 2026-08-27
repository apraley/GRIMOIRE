"""Exercise a broad sample of player actions.

The contract under test: every action either returns a list of strings, or
raises actions.ActionError. Nothing else should ever escape perform() — not
a KeyError, not a ValueError, not an AttributeError.
"""
from __future__ import annotations

import re
import unittest
from pathlib import Path

from grimoire import actions
from grimoire.actions import ActionError
from grimoire.player import create_player
from grimoire.worldgen import generate_world

SEED = 12345


class ActionTestCase(unittest.TestCase):
    """Base class: a single shared world + player, reset before every call."""

    @classmethod
    def setUpClass(cls):
        cls.w = generate_world(SEED)
        cls.nat = next(n for n in cls.w.living_nations() if len(n.regions) > 0)
        cls.other_nat = next(n for n in cls.w.living_nations()
                              if n.id != cls.nat.id and len(n.regions) > 0)
        cls.pl = create_player(cls.w, "Test Subject", "operative", cls.nat.id, False, 35)

    def setUp(self):
        # Give every call a clean slate of resources so we are testing the
        # action's own logic, not incidental AP/money exhaustion — or state
        # a *previous* test left behind, like dirty money laundered down to a
        # nonzero remainder, or a founded faith/movement — from leaking into
        # this one via the class-shared player fixture.
        self.pl.ap = 1000
        self.pl.ap_max = 1000
        self.pl.money = 1e13
        self.pl.dirty_money = 0.0
        self.pl.imprisoned_by = None
        self.pl.faith = None
        self.pl.movement = None
        self.pl.offices = {}
        self.nat.player_control = 0.0

    def call(self, name, args=""):
        """Perform an action and assert the perform() contract: a list of
        strings, or ActionError. Returns the result list, or None on
        ActionError."""
        try:
            result = actions.perform(self.w, self.pl, name, args)
        except ActionError:
            return None
        except Exception as e:  # pragma: no cover - this is exactly what we're checking for
            self.fail(f"{name}({args!r}) raised {type(e).__name__}: {e} "
                      f"(only ActionError is allowed)")
        self.assertIsInstance(result, list, f"{name}({args!r}) did not return a list")
        for line in result:
            self.assertIsInstance(line, str, f"{name}({args!r}) returned a non-string element")
        return result

    def any_person(self):
        return next(p for p in self.w.people.values()
                    if p.alive and p.id != "PLAYER")


class TestRegistryIntegrity(unittest.TestCase):
    def test_every_action_has_nonempty_desc_and_usage(self):
        bad = [name for name, d in actions.REGISTRY.items()
               if not d["desc"].strip() or not d["usage"].strip()]
        self.assertFalse(bad, f"actions with an empty desc or usage: {bad}")

    def test_no_alias_or_name_collisions(self):
        # ALIASES is a plain dict built at import time: a collision would be
        # silently overwritten there, so check the *source* for duplicate
        # tokens directly rather than trusting the already-resolved dict.
        src = Path(actions.__file__).read_text()
        names = re.findall(r'@action\(\s*"(\w+)"', src)
        names += re.findall(r'_op_action\(\s*"(\w+)"', src)
        aliases = []
        for block in re.findall(r"aliases=\(([^)]*)\)", src):
            aliases += re.findall(r'"(\w+)"', block)
        tokens = names + aliases
        seen = {}
        dupes = []
        for t in tokens:
            seen[t] = seen.get(t, 0) + 1
        dupes = sorted(t for t, n in seen.items() if n > 1)
        self.assertFalse(dupes, f"action names/aliases used more than once: {dupes}")

    def test_registry_matches_source_action_count(self):
        src = Path(actions.__file__).read_text()
        names = set(re.findall(r'@action\(\s*"(\w+)"', src))
        names |= set(re.findall(r'_op_action\(\s*"(\w+)"', src))
        self.assertEqual(names, set(actions.REGISTRY),
                          "REGISTRY does not match the actions declared in the source")


class TestBasicActions(ActionTestCase):
    def test_look(self):
        out = self.call("look")
        self.assertIsNotNone(out)
        self.assertTrue(out)

    def test_rest(self):
        out = self.call("rest")
        self.assertIsNotNone(out)

    def test_train(self):
        out = self.call("train", "oratory")
        self.assertIsNotNone(out)

    def test_travel_to_another_nation(self):
        out = self.call("travel", self.other_nat.name)
        self.assertIsNotNone(out)
        self.assertEqual(self.pl.me(self.w).nation, self.other_nat.id)

    def test_travel_nowhere(self):
        out = self.call("travel", "Nowhere Land Does Not Exist 999")
        self.assertIsNone(out)

    def test_meet(self):
        p = self.any_person()
        self.call("meet", p.name)  # may succeed or fail the social check; both are fine

    def test_meet_nonexistent(self):
        out = self.call("meet", "Zzyzx Nonexistent Person 999")
        self.assertIsNone(out)

    def test_cultivate(self):
        p = self.any_person()
        self.call("cultivate", p.name)

    def test_network(self):
        # the player starts in their nation's most populous region, which
        # should have plenty of notable people; either an ActionError (if
        # somehow nobody is there) or a list is an acceptable outcome.
        self.call("network")

    def test_speech(self):
        out = self.call("speech", "the future")
        self.assertIsNotNone(out)


class TestCovertActions(ActionTestCase):
    def test_surveil(self):
        p = self.any_person()
        out = self.call("surveil", p.name)
        self.assertIsNotNone(out)

    def test_bribe_without_amount_is_an_estimate(self):
        p = self.any_person()
        out = self.call("bribe", f"{p.name} | ")
        self.assertIsNotNone(out)

    def test_bribe_with_amount(self):
        p = self.any_person()
        out = self.call("bribe", f"{p.name} | 5000000")
        self.assertIsNotNone(out)

    def test_bribe_malformed_amount(self):
        p = self.any_person()
        out = self.call("bribe", f"{p.name} | not-a-number")
        self.assertIsNone(out)

    def test_disinfo(self):
        out = self.call("disinfo", f"{self.other_nat.name} | a fabricated dossier")
        self.assertIsNotNone(out)


class TestEconomicActions(ActionTestCase):
    VALID_FOUND_KINDS = ("corp", "bank", "party", "faith", "syndicate",
                          "media", "movement", "agency", "ngo")

    def test_found_every_valid_kind(self):
        for kind in self.VALID_FOUND_KINDS:
            with self.subTest(kind=kind):
                out = self.call("found", f"{kind} | Test {kind.title()} {SEED}")
                self.assertIsNotNone(out, f"founding a {kind} unexpectedly raised ActionError")

    def test_found_invalid_kind(self):
        out = self.call("found", "not_a_real_kind | Whatever")
        self.assertIsNone(out)

    def test_expand(self):
        self.call("found", "corp | Expand Test Co")
        oid = self.pl.orgs[-1]
        out = self.call("expand", f"{oid} | farming | 500000")
        self.assertIsNotNone(out)

    def test_expand_bad_amount(self):
        self.call("found", "corp | Expand Bad Amount Co")
        oid = self.pl.orgs[-1]
        out = self.call("expand", f"{oid} | farming | not-a-number")
        self.assertIsNone(out)

    def test_invest_in_a_public_company(self):
        pub = next((o for o in self.w.orgs.values() if o.alive and o.public), None)
        if pub is None:
            self.skipTest("no public company in this generated world")
        out = self.call("invest", f"{pub.name} | 1000000")
        self.assertIsNotNone(out)

    def test_launder_with_no_dirty_money(self):
        # a fresh player has no dirty money: this must raise ActionError, not crash
        out = self.call("launder", "")
        self.assertIsNone(out)

    def test_launder_with_dirty_money(self):
        self.pl.dirty_money = 500000.0
        out = self.call("launder", "100000")
        self.assertIsNotNone(out)


class TestPoliticalAndResearchActions(ActionTestCase):
    def test_policy_table(self):
        out = self.call("policy", self.nat.name)
        self.assertIsNotNone(out)

    def test_policy_set_a_lever_without_authority_raises(self):
        # A player holding no office and no control has under 30% authority;
        # actions._authority gates the lever on that, correctly.
        out = self.call("policy", f"{self.nat.name} | welfare | 0.5")
        self.assertIsNone(out)

    def test_policy_set_a_lever_with_authority(self):
        self.nat.player_control = 1.0
        out = self.call("policy", f"{self.nat.name} | welfare | 0.5")
        self.assertIsNotNone(out)

    def test_stand_for_office(self):
        out = self.call("stand", "legislator")
        self.assertIsNotNone(out)

    def test_study(self):
        out = self.call("study", "")
        self.assertIsNotNone(out)

    def test_project_menu(self):
        out = self.call("project", "")
        self.assertIsNotNone(out)

    def test_project_unknown(self):
        out = self.call("project", "not_a_real_project")
        self.assertIsNone(out)

    def test_preach_without_faith_or_movement(self):
        out = self.call("preach", "")
        self.assertIsNone(out)

    def test_preach_with_a_movement(self):
        self.call("found", "movement | Test Movement")
        out = self.call("preach", "solidarity")
        self.assertIsNotNone(out)


class TestBadArguments(ActionTestCase):
    def test_unknown_action_name(self):
        with self.assertRaises(ActionError):
            actions.perform(self.w, self.pl, "definitely_not_a_real_action", "")

    def test_meet_nonexistent_name(self):
        self.assertIsNone(self.call("meet", "Nobody Named This XYZ"))

    def test_recruit_nonexistent_name(self):
        self.assertIsNone(self.call("recruit", "Nobody Named This XYZ"))

    def test_declare_war_missing_pipe_separator(self):
        # no '|' at all: the whole string is read as the attacker's name,
        # leaving the defender argument empty.
        out = self.call("declare_war", "SomeRandomWordsWithNoSeparator")
        self.assertIsNone(out)

    def test_expand_missing_pipe_separator(self):
        out = self.call("expand", "ZZZNoSuchOrgAtAllZZZ")
        self.assertIsNone(out)

    def test_corner_malformed_amount(self):
        out = self.call("corner", "grain | not-a-number")
        self.assertIsNone(out)

    def test_invest_nonexistent_org(self):
        out = self.call("invest", "ZZZNoSuchOrgAtAllZZZ | 1000")
        self.assertIsNone(out)

    def test_acquire_nonexistent_org(self):
        out = self.call("acquire", "ZZZNoSuchOrgAtAllZZZ")
        self.assertIsNone(out)

    def test_travel_empty_args(self):
        out = self.call("travel", "")
        self.assertIsNone(out)


if __name__ == "__main__":
    unittest.main()
