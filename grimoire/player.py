"""The playable character and everything they personally own, owe or fear."""
from __future__ import annotations

import math

from .content_social import (ATTRIBUTES, BACKGROUNDS, PERKS, REL_DIMS, SKILLS,
                             TRAITS, WOUND_KINDS)
from .entities import Person
from .rng import RNG
from .serial import serializable
from .util import clamp, clamp01, lerp, mean

PLAYER_ID = "PLAYER"
BASE_AP = 3


@serializable
class Player:
    def __init__(self):
        self.person_id = PLAYER_ID
        self.background = "nobody"
        self.money = 0.0
        self.dirty_money = 0.0
        self.debt = 0.0
        self.income = 0.0
        self.ap = BASE_AP
        self.ap_max = BASE_AP
        self.perks: set[str] = set()
        self.techs: set[str] = set()
        self.research: dict[str, float] = {}
        self.projects: list[str] = []
        self.orgs: list[str] = []
        self.assets: list[str] = []           # recruited NPC ids
        self.holdings: dict[str, float] = {}  # org id -> share fraction
        self.offices: dict[str, str] = {}     # nation id -> role
        self.heat = 0.0
        self.exposure = 0.0
        self.wanted_by: set[str] = set()
        self.notoriety = 0.0
        self.fame = 0.0
        self.identities: list[dict] = []
        self.current_identity = 0
        self.wounds: list[dict] = []
        self.conditions: set[str] = set()
        self.addictions: dict[str, float] = {}
        self.stress = 0.15
        self.sleep = 0.9
        self.nutrition = 0.9
        self.morale = 0.65
        self.imprisoned_by: str | None = None
        self.prison_until = 0
        self.in_hiding = False
        self.op_history: list = []
        self.ledger: list = []                # (day, delta, reason)
        self.timeline: list = []              # notable personal events
        self.doctrine: str | None = None      # ideology the player preaches
        self.movement: str | None = None      # org id of the player's movement
        self.faith: str | None = None
        self.legacy = 0.0
        self.victory_progress: dict[str, float] = {}
        self.won: str | None = None
        self.lost: str | None = None
        self.difficulty = "standard"
        self.turn_log: list = []
        self.travel_until = 0
        self.pending_travel: str | None = None
        self.day_actions: list = []
        self.known_secrets: dict[str, list] = {}
        self.contacts: dict[str, float] = {}
        self.flags: dict = {}

    # -- convenience ------------------------------------------------------
    def me(self, w) -> Person:
        return w.people[self.person_id]

    def nation(self, w):
        return w.nations.get(self.me(w).nation)

    def region(self, w):
        return w.regions.get(self.me(w).region)

    def city(self, w):
        return w.cities.get(self.me(w).city)

    def net_worth(self, w) -> float:
        v = self.money
        for oid, frac in self.holdings.items():
            o = w.orgs.get(oid)
            if o and o.alive:
                v += o.valuation * frac
        return v - self.debt

    def skill(self, w, name: str) -> float:
        return self.me(w).skill(name)

    def attr(self, w, name: str) -> int:
        return self.me(w).attrs.get(name, 10)

    def heat_label(self) -> tuple[str, str]:
        from .sim_covert import heat_stage
        return heat_stage(self.heat)

    def spend(self, amount: float, reason: str, day: int) -> bool:
        if amount > self.money:
            return False
        self.money -= amount
        self.ledger.append((day, -amount, reason))
        if len(self.ledger) > 600:
            del self.ledger[:200]
        return True

    def earn(self, amount: float, reason: str, day: int, dirty: bool = False) -> None:
        self.money += amount
        if dirty:
            self.dirty_money += amount
        self.ledger.append((day, amount, reason))
        if len(self.ledger) > 600:
            del self.ledger[:200]

    def note(self, day: int, text: str) -> None:
        self.timeline.append((day, text))
        if len(self.timeline) > 500:
            del self.timeline[:150]

    def wound(self, kind: str, severity: float, day: int) -> None:
        self.wounds.append({"kind": kind, "sev": severity, "day": day})

    def health(self, w) -> float:
        return w.people[self.person_id].health

    def alive(self, w) -> bool:
        return w.people[self.person_id].alive


# ===========================================================================
def create_player(w, name: str, background: str, nation_id: str, female: bool,
                  age: int = 38, traits: list[str] | None = None) -> Player:
    from .content_social import AXES
    rng = w.rng.sub("player")
    bg = BACKGROUNDS[background]
    nat = w.nations[nation_id]
    p = Person(PLAYER_ID, name, nat.culture, nation_id, age, female)
    p.role = "player"
    p.title = bg["label"]
    for a in ATTRIBUTES:
        p.attrs[a] = 10
    for a, bonus in bg["attrs"].items():
        p.attrs[a] += bonus
    for a in ATTRIBUTES:
        p.attrs[a] = int(clamp(p.attrs[a] + rng.randint(-1, 2), 3, 18))
    p.skills = dict(bg["skills"])
    p.traits = traits or rng.sample(list(TRAITS), 3)
    p.ideology = {ax: clamp(rng.gauss(0, 0.35), -1, 1) for ax in AXES}
    p.health = clamp01(1.02 - age / 160 + rng.gauss(0, 0.04))
    p.power = 0.10 + bg["notoriety"] * 0.2
    p.public_profile = bg["notoriety"]
    p.protection = 0.15 + bg["notoriety"] * 0.2
    p.competence = 0.7
    p.loyalty = 1.0
    regions = [w.regions[r] for r in nat.regions if r in w.regions]
    home = max(regions, key=lambda r: r.pop) if regions else None
    if home:
        p.region = home.id
        p.city = nat.capital if nat.capital in w.cities else (home.cities[0] if home.cities else None)
    w.people[PLAYER_ID] = p

    pl = Player()
    pl.background = background
    pl.money = bg["wealth"]
    pl.perks = set(bg["perks"])
    pl.notoriety = bg["notoriety"]
    pl.fame = bg["notoriety"] * 0.6
    pl.identities = [{"name": name, "clean": True, "heat": 0.0, "nation": nation_id}]
    w.player = pl

    _apply_background_perks(w, pl, rng)
    pl.note(0, f"You are {name}. {bg['blurb']}")
    return pl


def _apply_background_perks(w, pl, rng) -> None:
    p = pl.me(w)
    nat = w.nations[p.nation]
    if "old_network" in pl.perks:
        spies = [q for q in w.people.values() if q.alive and q.role in ("spy", "intelligence_chief")]
        for q in rng.sample(spies, min(3, len(spies))):
            q.is_asset = True
            q.asset_of = PLAYER_ID
            q.player_rel["trust"] = 0.5
            pl.assets.append(q.id)
    if "muscle" in pl.perks:
        pl.flags["enforcers"] = 40
    if "flock" in pl.perks:
        pl.flags["followers"] = nat.pop * 0.004
    if "mass_following" in pl.perks:
        pl.flags["followers"] = nat.pop * 0.02
    if "family_seat" in pl.perks:
        pl.offices[nat.id] = "legislator"
        p.role = "legislator"
        p.power = clamp01(p.power + 0.2)
    if "officer_corps" in pl.perks:
        gens = [q for q in w.people.values() if q.alive and q.nation == nat.id
                and q.role in ("general", "admiral", "air_marshal")]
        for q in gens:
            q.player_rel["respect"] = 0.45
            q.player_rel["trust"] = 0.25
    if "sources" in pl.perks:
        pool = [q for q in w.people.values() if q.alive and q.secrets]
        for q in rng.sample(pool, min(6, len(pool))):
            for s in q.secrets:
                if rng.chance(0.5):
                    s["known_by"].append(PLAYER_ID)
    if "lab_access" in pl.perks:
        pl.flags["private_lab"] = 1.0
    if "underworld_ties" in pl.perks:
        syn = [o for o in w.orgs.values() if o.kind == "syndicate" and o.nation == nat.id]
        if syn:
            o = rng.pick(syn)
            o.player_owned = True
            pl.orgs.append(o.id)
            pl.holdings[o.id] = 1.0
    if "capital_access" in pl.perks:
        pl.flags["credit_line"] = pl.money * 3
    if "regulator_friends" in pl.perks:
        pl.flags["heat_resist"] = 0.35
    if "clean_slate" in pl.perks:
        pl.heat = 0.0
        pl.exposure = 0.0
    if "ghost_identity" in pl.perks:
        from . import names as N
        alias = N.person_name(rng, nat.culture, p.female)
        pl.identities.append({"name": alias, "clean": True, "heat": 0.0, "nation": nat.id})


# ===========================================================================
def tick_player(w) -> None:
    """Daily upkeep on the character: needs, wounds, heat, income, pursuit."""
    pl = w.player
    if pl is None:
        return
    rng = w.rng.sub("playerlife")
    p = pl.me(w)
    if not p.alive:
        pl.lost = pl.lost or "death"
        return

    if pl.imprisoned_by:
        if w.clock.day >= pl.prison_until:
            pl.imprisoned_by = None
            pl.note(w.clock.day, "You walk out of the gates. The world moved on without you.")
        else:
            pl.stress = clamp01(pl.stress + 0.004)
            p.health = clamp01(p.health - 0.0006)
            pl.heat = clamp01(pl.heat - 0.0016)
            return

    # --- needs --------------------------------------------------------
    trait_stress = sum(TRAITS[t]["mods"].get("stress_gain", 0.0) for t in p.traits)
    pl.stress = clamp01(pl.stress + (0.006 + 0.004 * len(pl.orgs)) * (1 + trait_stress)
                        - 0.010 * pl.sleep)
    pl.sleep = clamp01(pl.sleep - 0.02 + 0.02 * (1 - pl.stress * 0.5))
    pl.nutrition = clamp01(pl.nutrition - 0.015 + (0.02 if pl.money > 1000 else 0.004))
    pl.morale = clamp01(lerp(pl.morale, clamp01(0.5 + 0.3 * (1 - pl.stress)
                                                + 0.2 * clamp01(pl.fame)), 0.02))

    # --- health -------------------------------------------------------
    heal = 0.0016 * (0.4 + pl.nutrition) * (0.5 + pl.sleep)
    heal *= 1 + 0.5 * pl.skill(w, "medicine")
    for wnd in list(pl.wounds):
        wnd["sev"] = max(0.0, wnd["sev"] - heal * 0.7)
        if wnd["sev"] <= 0.01:
            pl.wounds.remove(wnd)
    burden = sum(x["sev"] for x in pl.wounds) + sum(pl.addictions.values()) * 0.25
    age_decay = max(0.0, p.age - 42) * 0.000018
    p.health = clamp01(p.health + heal - burden * 0.012 - age_decay - pl.stress * 0.0012)
    if p.health <= 0.02:
        from .sim_world import _kill
        _kill(w, p, "wounds and exhaustion")
        pl.lost = "death"
        return
    if rng.chance(max(0.0, p.age - 60) * 0.000018 / max(p.health, 0.2)):
        from .sim_world import _kill
        _kill(w, p, "sudden illness")
        pl.lost = "death"
        return

    for k in list(pl.addictions):
        pl.addictions[k] = clamp01(pl.addictions[k] - 0.001)
        if pl.addictions[k] <= 0:
            del pl.addictions[k]

    # --- action points -------------------------------------------------
    trait_ap = sum(TRAITS[t]["mods"].get("ap", 0.0) for t in p.traits)
    pl.ap_max = max(1, int(round(BASE_AP * (1 + trait_ap)
                                 * (0.55 + 0.45 * p.health)
                                 * (1.15 - 0.35 * pl.stress))))
    pl.ap = pl.ap_max

    # --- money ---------------------------------------------------------
    income = 0.0
    for oid, frac in pl.holdings.items():
        o = w.orgs.get(oid)
        if o and o.alive:
            income += o.profit * frac * 0.35
    if "old_money" in pl.perks:
        income += pl.money * 0.03 / 360
    burn = 2500 + 700 * len(pl.orgs) + len(pl.assets) * 850
    burn *= 1 + pl.notoriety
    pl.income = income - burn
    pl.money += pl.income
    if pl.money < 0:
        pl.debt += -pl.money
        pl.money = 0.0
    if pl.debt > 0:
        pl.debt *= 1 + 0.10 / 360

    # --- heat, exposure and pursuit ------------------------------------
    resist = pl.flags.get("heat_resist", 0.0) + (0.2 if "quantum_ledger" in pl.perks else 0.0)
    cool = 0.0012 * (1 + resist) * (1.6 if pl.in_hiding else 1.0)
    pl.heat = clamp01(pl.heat - cool)
    pl.exposure = clamp01(pl.exposure - cool * 0.8)
    pl.notoriety = clamp01(lerp(pl.notoriety, clamp01(pl.fame * 0.7 + pl.heat * 0.5), 0.01))
    p.public_profile = pl.notoriety

    if pl.wanted_by and rng.chance(pl.heat * 0.004 * len(pl.wanted_by)):
        _pursuit(w, pl, rng)

    # assassination attempts against a hated player
    enemies = [q for q in w.people.values() if q.alive
               and q.player_rel.get("trust", 0) < -0.6 and q.power > 0.4]
    if enemies and rng.chance(0.0005 * len(enemies) * (0.4 + pl.notoriety)):
        _attempt_on_player(w, pl, rng.pick(enemies), rng)


def _pursuit(w, pl, rng) -> None:
    hunters = [w.nations[n] for n in pl.wanted_by if n in w.nations and w.nations[n].alive]
    if not hunters:
        return
    nat = max(hunters, key=lambda n: n.intel_capacity * n.state_capacity)
    here = w.people[PLAYER_ID].nation
    reach = nat.intel_capacity * nat.state_capacity
    if here != nat.id:
        reach *= 0.45 if not nat.has_treaty(here, "extradition") else 0.85
        host = w.nations.get(here)
        if host and host.relation(nat.id) < -0.2:
            reach *= 0.3
    evade = clamp01(0.25 + pl.skill(w, "tradecraft") * 0.6
                    + (0.25 if pl.in_hiding else 0.0)
                    + (0.2 if "ghost_identity" in pl.perks else 0.0))
    if rng.chance(clamp01(reach - evade) * 0.5):
        pl.imprisoned_by = nat.id
        term = int(360 * (1 + pl.heat * 6))
        pl.prison_until = w.clock.day + term
        pl.note(w.clock.day, f"Taken into custody by {nat.name}. Held pending trial.")
        w.tell(f"You have been arrested by {nat.name}. You will be held for roughly "
               f"{term // 30} months unless someone intervenes.", "bad")
        w.report(f"{w.people[PLAYER_ID].name} has been arrested in {nat.name}.",
                 "crime", nat.id, 0.8, ["player"])
    else:
        pl.note(w.clock.day, f"A {nat.name} team came close. You were not there.")
        w.tell(f"{nat.name} raided an address associated with you. You were not at it.", "warn")
        pl.heat = clamp01(pl.heat + 0.02)


def _attempt_on_player(w, pl, enemy, rng) -> None:
    p = pl.me(w)
    guard = clamp01(p.protection + pl.skill(w, "surveillance") * 0.3
                    + (0.2 if pl.in_hiding else 0.0)
                    + (0.35 if "hand_of_god" in pl.perks else 0.0))
    if rng.chance(clamp01(0.55 - guard)):
        kind, sev, days = rng.pick(WOUND_KINDS)
        pl.wound(kind, sev * rng.uniform(0.6, 1.5), w.clock.day)
        p.health = clamp01(p.health - sev * 0.5)
        pl.note(w.clock.day, f"An attempt on your life. You survived it with a {kind}.")
        w.tell(f"Someone tried to kill you. You have a {kind} and a very short list of suspects. "
               f"{enemy.name} is on it.", "bad")
        if p.health <= 0.02:
            from .sim_world import _kill
            _kill(w, p, f"assassinated on the orders of {enemy.name}")
            pl.lost = "death"
    else:
        pl.note(w.clock.day, f"An attempt on your life failed before it began.")
        w.tell(f"Your people intercepted an attempt on your life. The trail leads toward "
               f"{enemy.name}.", "warn")
    p.protection = clamp01(p.protection + 0.08)
