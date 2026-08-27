"""The World container: every entity, the global market, the news log."""
from __future__ import annotations

from .content_econ import GOODS
from .gametime import Clock
from .rng import RNG
from .serial import serializable
from .util import Counter, Series, clamp, clamp01


@serializable
class NewsItem:
    __slots__ = ("day", "text", "cat", "scope", "weight", "tags", "seen")

    def __init__(self, day: int, text: str, cat: str = "world", scope: str = "",
                 weight: float = 0.5, tags=()):
        self.day = day
        self.text = text
        self.cat = cat
        self.scope = scope
        self.weight = weight
        self.tags = list(tags)
        self.seen = False

    def __getstate__(self):
        return {k: getattr(self, k) for k in self.__slots__}

    def __setstate__(self, st):
        for k, v in st.items():
            setattr(self, k, v)


@serializable
class WorldMarket:
    """Global clearing house. Nations trade into it subject to friction."""

    def __init__(self):
        self.price: dict[str, float] = {g: d["base"] for g, d in GOODS.items()}
        self.supply: Counter = Counter()
        self.demand: Counter = Counter()
        self.stock: Counter = Counter()
        self.hist: dict[str, Series] = {g: Series(360, d["base"]) for g, d in GOODS.items()}
        self.volatility: dict[str, float] = {g: 0.02 for g in GOODS}
        self.index = 100.0
        self.index_hist = Series(720, 100.0)
        self.shipping_cost = 1.0
        self.sentiment = 0.0            # -1 panic .. +1 euphoria
        self.credit_spread = 0.02

    def p(self, good: str) -> float:
        return self.price.get(good, GOODS[good]["base"])

    def value(self, basket: dict) -> float:
        return sum(self.p(g) * q for g, q in basket.items())


@serializable
class World:
    def __init__(self, seed: int):
        self.seed = seed
        self.rng = RNG(seed, "world")
        self.clock = Clock()
        self.planet = None
        self.regions: dict = {}
        self.cities: dict = {}
        self.nations: dict = {}
        self.people: dict = {}
        self.orgs: dict = {}
        self.armies: dict = {}
        self.wars: dict = {}
        self.narratives: dict = {}
        self.faiths: dict = {}
        self.epidemics: dict = {}
        self.projects: dict = {}
        self.operations: dict = {}
        self.market = WorldMarket()
        self.news: list = []
        self.log: list = []
        self.player = None
        self.flags: dict = {}
        self.counters: Counter = Counter()
        self.ids: dict = {}
        self.hist: dict = {}
        self.pending: list = []          # scheduled callbacks (day, kind, payload)
        self.world_tech = 0.42
        self.tension = 0.20              # global geopolitical temperature
        self.trade_openness = 0.72
        self.global_pop = 0.0
        self.global_gdp = 0.0
        self.doomsday = 0.30             # 0 safe .. 1 catastrophe
        self.year_summary: list = []
        self.obituaries: list = []
        self.treaty_body = None          # the world assembly org id
        self.great_powers: list = []
        self.messages: list = []         # queued player-facing events

    # -- ids ---------------------------------------------------------------
    def nid(self, prefix: str) -> str:
        n = int(self.ids.get(prefix, 0)) + 1
        self.ids[prefix] = n
        return f"{prefix}{n}"

    # -- lookups -----------------------------------------------------------
    def nation(self, nid: str):
        return self.nations.get(nid)

    def region(self, rid: str):
        return self.regions.get(rid)

    def person(self, pid: str):
        return self.people.get(pid)

    def org(self, oid: str):
        return self.orgs.get(oid)

    def city(self, cid: str):
        return self.cities.get(cid)

    def living_nations(self):
        return [n for n in self.nations.values() if n.alive]

    def nation_regions(self, nid: str):
        return [self.regions[r] for r in self.nations[nid].regions if r in self.regions]

    def nation_cities(self, nid: str):
        out = []
        for r in self.nation_regions(nid):
            out += [self.cities[c] for c in r.cities if c in self.cities]
        return out

    def find_nation(self, text: str):
        t = text.strip().lower()
        for n in self.nations.values():
            if n.id.lower() == t or n.name.lower() == t:
                return n
        cands = [n for n in self.nations.values()
                 if t in n.name.lower() or t in n.formal.lower()]
        return cands[0] if len(cands) >= 1 else None

    def find_person(self, text: str):
        t = text.strip().lower()
        for p in self.people.values():
            if p.id.lower() == t or p.name.lower() == t:
                return p
        cands = [p for p in self.people.values() if p.alive and t in p.name.lower()]
        return cands[0] if cands else None

    def find_region(self, text: str):
        t = text.strip().lower()
        for r in self.regions.values():
            if r.id.lower() == t or r.name.lower() == t:
                return r
        cands = [r for r in self.regions.values() if t in r.name.lower()]
        return cands[0] if cands else None

    def find_org(self, text: str):
        t = text.strip().lower()
        for o in self.orgs.values():
            if o.id.lower() == t or o.name.lower() == t:
                return o
        cands = [o for o in self.orgs.values() if o.alive and t in o.name.lower()]
        return cands[0] if cands else None

    def find_city(self, text: str):
        t = text.strip().lower()
        for cy in self.cities.values():
            if cy.id.lower() == t or cy.name.lower() == t:
                return cy
        cands = [cy for cy in self.cities.values() if t in cy.name.lower()]
        return cands[0] if cands else None

    def find_any(self, text: str):
        for fn in (self.find_nation, self.find_person, self.find_org,
                   self.find_region, self.find_city):
            r = fn(text)
            if r is not None:
                return r
        return None

    # -- news --------------------------------------------------------------
    def report(self, text: str, cat: str = "world", scope: str = "",
               weight: float = 0.5, tags=()) -> None:
        self.news.append(NewsItem(self.clock.day, text, cat, scope, weight, tags))
        if len(self.news) > 4000:
            del self.news[:1200]

    def tell(self, text: str, kind: str = "info") -> None:
        """Something the player should see on their next prompt."""
        self.messages.append((self.clock.day, kind, text))

    def recent_news(self, days: int = 7, cat: str | None = None,
                    scope: str | None = None, minw: float = 0.0):
        d0 = self.clock.day - days
        return [n for n in self.news
                if n.day >= d0 and n.weight >= minw
                and (cat is None or n.cat == cat)
                and (scope is None or n.scope == scope)]

    # -- scheduling --------------------------------------------------------
    def schedule(self, days: int, kind: str, payload: dict) -> None:
        self.pending.append((self.clock.day + max(1, days), kind, payload))

    def due(self):
        d = self.clock.day
        ready = [p for p in self.pending if p[0] <= d]
        self.pending = [p for p in self.pending if p[0] > d]
        return ready

    # -- aggregates --------------------------------------------------------
    def recompute_globals(self) -> None:
        self.global_pop = sum(n.pop for n in self.living_nations())
        self.global_gdp = sum(n.gdp for n in self.living_nations())
        ranked = sorted(self.living_nations(), key=lambda n: -n.power())
        self.great_powers = [n.id for n in ranked[:8]]
        alive = self.living_nations()
        if alive:
            self.world_tech = sum(n.tech_level * n.gdp for n in alive) / max(self.global_gdp, 1.0)
        self.flags["mil_total"] = sum(n.military_score() for n in alive) or 1.0

    def share_of_world(self, nid: str, metric: str = "gdp") -> float:
        n = self.nations.get(nid)
        if not n:
            return 0.0
        if metric == "gdp":
            return n.gdp / max(self.global_gdp, 1.0)
        if metric == "pop":
            return n.pop / max(self.global_pop, 1.0)
        return n.military_score() / max(self.flags.get("mil_total", 1.0), 1.0)
