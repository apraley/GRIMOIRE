"""Core game entities: regions, cities, nations, people, organisations."""
from __future__ import annotations

import math

from .content_econ import BASKET, GOODS, INDUSTRIES
from .content_social import (ATTRIBUTES, AUDIENCES, AXES, GOV_TYPES, POLICIES,
                             REL_DIMS, SKILLS)
from .serial import serializable
from .util import Counter, Series, clamp, clamp01, mean, wmean

AGE_BANDS = ["0-14", "15-24", "25-44", "45-64", "65+"]
WEALTH_BANDS = ["poor", "middle", "rich"]


# ===========================================================================
@serializable
class City:
    def __init__(self, cid: str, name: str, region: str, pop: float,
                 x: int, y: int, port: bool = False):
        self.id = cid
        self.name = name
        self.region = region
        self.pop = pop
        self.x, self.y = x, y
        self.port = port
        self.capital = False
        self.tier = "minor"
        self.university = False
        self.airport = False
        self.stock_exchange = False
        self.landmarks: list[str] = []
        self.unrest = 0.05
        self.crime = 0.10
        self.cost_of_living = 1.0
        self.damage = 0.0          # war / disaster damage, 0..1
        self.occupier: str | None = None
        self.tags: set[str] = set()

    def label(self) -> str:
        return self.name + ("★" if self.capital else "")


# ===========================================================================
@serializable
class Region:
    """A province: the unit of territory, production and control."""

    def __init__(self, rid: str, name: str, nation: str):
        self.id = rid
        self.name = name
        self.nation = nation
        self.core_of = nation           # historic claim
        self.tiles: list[tuple[int, int]] = []
        self.cities: list[str] = []
        self.capital_city: str | None = None
        self.centroid = (0, 0)
        self.lat = 0.0
        self.area = 0.0
        self.coastal = False
        self.biomes: dict[str, float] = {}
        self.resources: dict[str, float] = {}
        self.reserves: dict[str, float] = {}     # depletable stock
        # population
        self.pop = 0.0
        self.age: dict[str, float] = {}
        self.wealth: dict[str, float] = {}
        self.urban = 0.4
        self.education = 0.4
        self.literacy = 0.8
        self.health = 0.6
        self.culture = "Meritan"
        self.cultures: dict[str, float] = {}
        self.faiths: dict[str, float] = {}
        self.ideology: dict[str, float] = {}
        # economy
        self.capacity: dict[str, float] = {}     # industry -> capital units
        self.output: dict[str, float] = {}       # good -> units/day
        self.employment = 0.94
        self.infra = 0.4
        self.capital_stock = 0.0
        self.land_used = 0.0
        self.pollution = 0.0
        self.wage = 1.0
        # politics & security
        self.unrest = 0.06
        self.control = 1.0                      # 0..1 government control
        self.occupier: str | None = None
        self.garrison = 0.0
        self.insurgency = 0.0
        self.devastation = 0.0
        self.separatism = 0.0
        self.player_influence = 0.0
        self.player_owned = False
        self.hist_pop = None

    # -- derived ----------------------------------------------------------
    def workforce(self) -> float:
        return self.pop * (self.age.get("15-24", 0.15) + self.age.get("25-44", 0.28)
                           + self.age.get("45-64", 0.22)) * self.employment

    def dependency(self) -> float:
        w = self.age.get("15-24", 0) + self.age.get("25-44", 0) + self.age.get("45-64", 0)
        return (1 - w) / max(w, 0.05)

    def skill_level(self) -> float:
        return clamp01(0.25 + 0.6 * self.education + 0.15 * self.urban)

    def resource(self, kind: str) -> float:
        return self.resources.get(kind, 0.0)

    def effective_infra(self) -> float:
        return clamp01(self.infra * (1 - 0.7 * self.devastation))

    def stability(self) -> float:
        return clamp01(1 - self.unrest - 0.5 * self.insurgency)

    def __repr__(self):
        return f"<Region {self.name} {self.nation} pop={self.pop:,.0f}>"


# ===========================================================================
@serializable
class Nation:
    def __init__(self, nid: str, name: str, formal: str, culture: str):
        self.id = nid
        self.name = name
        self.formal = formal
        self.culture = culture
        self.adjective = name + "i" if not name.endswith(("a", "e", "i", "o", "u")) else name + "n"
        self.regions: list[str] = []
        self.capital: str | None = None
        self.gov = "flawed_democracy"
        self.founded = 0
        self.flagcolour = "w"
        # leadership
        self.head_of_state: str | None = None
        self.head_of_gov: str | None = None
        self.cabinet: dict[str, str] = {}
        self.ruling_party: str | None = None
        self.coalition: list[str] = []
        self.parties: list[str] = []
        self.next_election = 0
        self.term_length = 1440
        self.leader_since = 0
        # policy & ideology
        self.policy: dict[str, float] = {k: v["default"] for k, v in POLICIES.items()}
        self.ideology: dict[str, float] = {a: 0.0 for a in AXES}
        self.doctrine = "combined_arms"
        # state health
        self.stability = 0.65
        self.legitimacy = 0.60
        self.corruption = 0.35
        self.approval = 0.50
        self.unrest = 0.08
        self.repression = 0.15
        self.civil_war = False
        self.state_capacity = 0.55
        self.war_weariness = 0.0
        self.war_exhaustion = 0.0
        # economy
        self.treasury = 0.0
        self.debt = 0.0
        self.gdp = 0.0
        self.gdp_prev = 0.0
        self.growth = 0.02
        self.inflation = 0.02
        self.unemployment = 0.06
        self.rate = 0.03                 # policy interest rate
        self.currency = 1.0              # units per world credit
        self.fx_reserves = 0.0
        self.credit_rating = 0.7
        self.stockpile: Counter = Counter()
        self.prices: dict[str, float] = {}
        self.demand: dict[str, float] = {}
        self.supply: dict[str, float] = {}
        self.imports: Counter = Counter()
        self.exports: Counter = Counter()
        self.trade_balance = 0.0
        self.money_supply = 0.0
        self.debt_service = 0.0
        self.budget_balance = 0.0
        self.gini = 0.38
        # military
        self.forces: dict[str, float] = {}      # unit type -> count
        self.manpower = 0.0
        self.reserves_men = 0.0
        self.morale = 0.7
        self.readiness = 0.6
        self.nukes = 0
        self.nuke_program = 0.0
        self.mobilised = 0.0
        self.army_loyalty = 0.7
        # tech
        self.techs: set[str] = set()
        self.research: dict[str, float] = {}
        self.research_focus: str | None = None
        self.tech_level = 0.4
        self.rp_per_day = 0.0
        # foreign
        self.relations: dict[str, float] = {}
        self.treaties: dict[str, set[str]] = {}
        self.at_war: set[str] = set()
        self.sanctions: set[str] = set()
        self.embargoes: set[str] = set()
        self.claims: dict[str, str] = {}
        self.prestige = 0.3
        self.soft_power = 0.3
        self.intel_capacity = 0.4
        self.intel_known: dict[str, float] = {}
        self.spy_networks: dict[str, float] = {}
        # society
        self.opinion: dict[str, float] = {a: 0.0 for a in AUDIENCES}
        self.faiths: dict[str, float] = {}
        self.media_freedom = 0.6
        self.pop = 0.0
        self.life_expectancy = 74.0
        self.birth_rate = 0.014
        self.death_rate = 0.008
        self.migration = 0.0
        self.hdi = 0.7
        self.emissions = 0.0
        self.player_control = 0.0        # 0..1 how much the player owns this state
        self.puppet_of: str | None = None
        self.hist = {}
        self.alive = True

    # -- derived ----------------------------------------------------------
    def gov_data(self) -> dict:
        return GOV_TYPES[self.gov]

    def is_democracy(self) -> bool:
        return GOV_TYPES[self.gov]["elections"]

    def gdp_per_capita(self) -> float:
        return self.gdp / max(self.pop, 1.0) * 360.0

    def debt_ratio(self) -> float:
        return self.debt / max(self.gdp * 360.0, 1.0)

    def military_score(self) -> float:
        from .content_conflict import UNITS
        s = 0.0
        for u, n in self.forces.items():
            d = UNITS[u]
            s += n * (d["atk"] + d["dfn"]) * (0.6 + 0.8 * self.tech_level)
        return s * (0.5 + 0.5 * self.morale) * (0.6 + 0.6 * self.readiness)

    def power(self) -> float:
        """Composite national power index."""
        return (0.34 * math.log10(max(self.gdp * 360.0, 1e6))
                + 0.24 * math.log10(max(self.military_score(), 1.0) + 10)
                + 0.14 * math.log10(max(self.pop, 1e4))
                + 2.0 * self.tech_level + 1.6 * self.prestige + 1.2 * self.soft_power)

    def relation(self, other: str) -> float:
        return self.relations.get(other, 0.0)

    def has_treaty(self, other: str, kind: str) -> bool:
        return kind in self.treaties.get(other, set())

    def allies(self) -> list[str]:
        return [n for n, ts in self.treaties.items() if {"alliance", "defence"} & ts]

    def get_policy(self, k: str) -> float:
        return self.policy.get(k, POLICIES[k]["default"])

    def set_policy(self, k: str, v: float) -> None:
        d = POLICIES[k]
        self.policy[k] = clamp(v, d["lo"], d["hi"])

    def __repr__(self):
        return f"<Nation {self.name} pop={self.pop:,.0f} gdp={self.gdp * 360:,.0f}>"


# ===========================================================================
@serializable
class Person:
    def __init__(self, pid: str, name: str, culture: str, nation: str,
                 age: int, female: bool):
        self.id = pid
        self.name = name
        self.culture = culture
        self.nation = nation
        self.age = age
        self.female = female
        self.alive = True
        self.death_day = None
        self.death_cause = ""
        self.role = "citizen"
        self.title = ""
        self.org: str | None = None
        self.region: str | None = None
        self.city: str | None = None
        self.attrs: dict[str, int] = {}
        self.skills: dict[str, float] = {}
        self.traits: list[str] = []
        self.ideology: dict[str, float] = {}
        self.faith: str | None = None
        self.wealth = 0.0
        self.income = 0.0
        self.power = 0.1
        self.ambition = 0.5
        self.loyalty_to: str | None = None
        self.loyalty = 0.5
        self.corruptibility = 0.35
        self.competence = 0.5
        self.health = 0.9
        self.stress = 0.2
        self.secrets: list[dict] = []
        self.knows: dict[str, float] = {}       # person id -> familiarity
        self.rel: dict[str, dict[str, float]] = {}
        self.opinion_of_player = 0.0
        self.player_rel: dict[str, float] = {d: 0.0 for d in REL_DIMS}
        self.is_asset = False
        self.asset_of: str | None = None
        self.blackmailed_by: str | None = None
        self.suspicion = 0.0
        self.goals: list[str] = []
        self.memory: list[str] = []
        self.public_profile = 0.0
        self.protection = 0.2

    def skill(self, k: str) -> float:
        base = self.skills.get(k, 0.05)
        attr = self.attrs.get(SKILLS[k]["attr"], 5)
        return clamp01(base * 0.78 + (attr / 20.0) * 0.22)

    def influence(self) -> float:
        from .content_social import ROLE_POWER
        return clamp01(0.45 * ROLE_POWER.get(self.role, 0.2) + 0.25 * self.power
                       + 0.15 * self.public_profile + 0.15 * min(1.0, self.wealth / 5e8))

    def disposition(self) -> float:
        r = self.player_rel
        return clamp(0.4 * r["trust"] + 0.3 * r["affection"] + 0.2 * r["respect"]
                     - 0.15 * r["fear"], -1, 1)

    def leverage(self) -> float:
        r = self.player_rel
        return clamp01(0.35 * r["fear"] + 0.3 * r["debt"] + 0.2 * max(0, r["trust"])
                       + (0.4 if self.blackmailed_by == "PLAYER" else 0.0))

    def describe_role(self) -> str:
        return (self.title or self.role.replace("_", " ").title())

    def __repr__(self):
        return f"<Person {self.name} {self.role}@{self.nation}>"


# ===========================================================================
@serializable
class Org:
    """Corporations, banks, parties, faiths, syndicates, agencies, media."""

    KINDS = ("corp", "bank", "party", "faith", "syndicate", "agency", "media",
             "university", "ngo", "militia", "cartel", "movement", "institution")

    def __init__(self, oid: str, name: str, kind: str, nation: str):
        self.id = oid
        self.name = name
        self.kind = kind
        self.nation = nation
        self.hq: str | None = None
        self.founded = 0
        self.leader: str | None = None
        self.members: list[str] = []
        self.headcount = 0.0
        self.cash = 0.0
        self.debt = 0.0
        self.revenue = 0.0
        self.costs = 0.0
        self.profit = 0.0
        self.valuation = 0.0
        self.share_price = 0.0
        self.shares = 0.0
        self.owners: dict[str, float] = {}      # holder id -> fraction
        self.public = False
        self.industries: dict[str, float] = {}  # industry -> capacity owned
        self.regions: dict[str, float] = {}     # presence by region
        self.rackets: dict[str, float] = {}
        self.influence = 0.1
        self.reach = 0.1                        # media/faith audience share
        self.bias: dict[str, float] = {}
        self.doctrine: str | None = None
        self.ideology: dict[str, float] = {}
        self.loyalty = 0.6
        self.secrecy = 0.4
        self.heat = 0.0
        self.player_owned = False
        self.player_stake = 0.0
        self.rnd = 0.0
        self.tech_progress: dict[str, float] = {}
        self.techs: set[str] = set()
        self.assets: dict[str, float] = {}
        self.hist_rev = None
        self.hist_price = None
        self.alive = True
        self.tags: set[str] = set()
        self.notes = ""

    def margin(self) -> float:
        return self.profit / max(self.revenue, 1.0)

    def __repr__(self):
        return f"<Org {self.name} ({self.kind}) {self.nation}>"


# ===========================================================================
@serializable
class Army:
    """A field formation the player or a nation manoeuvres."""

    def __init__(self, aid: str, name: str, owner: str, region: str):
        self.id = aid
        self.name = name
        self.owner = owner
        self.region = region
        self.units: dict[str, float] = {}
        self.strength = 1.0
        self.morale = 0.7
        self.supply = 1.0
        self.entrenched = 0.0
        self.commander: str | None = None
        self.orders = "hold"
        self.target: str | None = None
        self.moving = 0
        self.experience = 0.2
        self.attrition = 0.0

    def size(self) -> float:
        from .content_conflict import UNITS
        return sum(UNITS[u]["men"] * n for u, n in self.units.items())

    def combat_power(self, attacking: bool, tech: float = 0.5) -> float:
        from .content_conflict import UNITS
        p = 0.0
        for u, n in self.units.items():
            d = UNITS[u]
            p += n * (d["atk"] if attacking else d["dfn"]) * d["hp"]
        return (p * self.strength * (0.45 + 0.75 * self.morale)
                * (0.5 + 0.6 * self.supply) * (0.55 + 0.9 * tech)
                * (1 + (0.35 * self.entrenched if not attacking else 0))
                * (0.8 + 0.5 * self.experience))


# ===========================================================================
@serializable
class War:
    def __init__(self, wid: str, attacker: str, defender: str, goal: str, day: int):
        self.id = wid
        self.attackers = [attacker]
        self.defenders = [defender]
        self.goal = goal
        self.started = day
        self.ended = None
        self.name = ""
        self.warscore = 0.0            # + favours attackers
        self.casualties: dict[str, float] = {}
        self.battles: list[dict] = []
        self.occupied: dict[str, str] = {}   # region -> occupier
        self.nuclear = False
        self.instigator: str | None = None
        self.player_involved = False

    def sides(self):
        return self.attackers, self.defenders

    def side_of(self, nid: str):
        if nid in self.attackers:
            return "attacker"
        if nid in self.defenders:
            return "defender"
        return None


# ===========================================================================
@serializable
class Narrative:
    """A story circulating in the information space."""

    def __init__(self, nid: str, kind: str, text: str, subject: str, day: int):
        self.id = nid
        self.kind = kind
        self.text = text
        self.subject = subject           # person / nation / org id, or "" for none
        self.created = day
        self.salience: dict[str, float] = {}     # nation id -> 0..1 penetration
        self.credibility = 0.6
        self.valence = -1
        self.origin: str | None = None
        self.truth = True
        self.suppressed = 0.0
        self.audiences: dict[str, float] = {}
        self.targets_player = False


@serializable
class Faith:
    def __init__(self, fid: str, name: str, doctrine: str):
        self.id = fid
        self.name = name
        self.doctrine = doctrine
        self.founded = 0
        self.adherents = 0.0
        self.holy_sites: list[str] = []
        self.head: str | None = None
        self.militancy = 0.2
        self.orthodoxy = 0.6
        self.wealth = 0.0
        self.ideology: dict[str, float] = {}
        self.parent: str | None = None
        self.player_founded = False


@serializable
class Epidemic:
    def __init__(self, eid: str, disease: str, origin: str, day: int):
        self.id = eid
        self.disease = disease
        self.origin = origin
        self.started = day
        self.ended = None
        self.name = ""
        self.state: dict[str, dict] = {}      # region -> {s,e,i,r,d}
        self.total_dead = 0.0
        self.total_cases = 0.0
        self.r0_mod = 1.0
        self.vaccine = 0.0
        self.engineered = False
        self.attributed_to: str | None = None


@serializable
class Project:
    """A long-running player or national programme."""

    def __init__(self, pid: str, kind: str, name: str, cost: float, owner: str):
        self.id = pid
        self.kind = kind
        self.name = name
        self.cost = cost
        self.spent = 0.0
        self.owner = owner
        self.progress = 0.0
        self.started = 0
        self.done = False
        self.region: str | None = None
        self.meta: dict = {}
        self.secret = False
        self.exposure = 0.0


@serializable
class Operation:
    """An intelligence operation in flight."""

    def __init__(self, oid: str, kind: str, actor: str, target: str, day: int):
        self.id = oid
        self.kind = kind
        self.actor = actor
        self.target = target
        self.target_kind = "person"
        self.started = day
        self.eta = 0
        self.skill = 0.5
        self.risk = 0.2
        self.budget = 0.0
        self.codename = ""
        self.assets: list[str] = []
        self.notes = ""
        self.resolved = False
        self.meta: dict = {}
