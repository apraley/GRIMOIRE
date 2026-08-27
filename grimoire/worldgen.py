"""World generation: carve the planet into regions and nations, then populate
them with people, cities, industries, governments and institutions."""
from __future__ import annotations

import math
from collections import deque

from . import names as N
from . import worldmap as WM
from .content_econ import (BIOMES, GOODS, INDUSTRIES, RESOURCE_GATES)
from .content_social import (AUDIENCES, AXES, GOV_TYPES, IDEOLOGIES, POLICIES,
                             POLICY_IDEOLOGY)
from .content_tech import TECHS
from .entities import AGE_BANDS, City, Nation, Region
from .rng import RNG
from .util import Counter, clamp, clamp01, lerp, mean, smoothstep

TARGET_POP = 9.15e9

DEV_ARCHETYPES = {
    "advanced":   dict(w=0.16, gdppc=(48000, 86000), tech=(0.66, 0.86), edu=(0.72, 0.92),
                       infra=(0.72, 0.94), urban=(0.72, 0.90), life=(80, 86)),
    "industrial": dict(w=0.22, gdppc=(17000, 42000), tech=(0.48, 0.68), edu=(0.55, 0.78),
                       infra=(0.52, 0.76), urban=(0.55, 0.78), life=(73, 80)),
    "emerging":   dict(w=0.30, gdppc=(5200, 16000), tech=(0.32, 0.52), edu=(0.38, 0.62),
                       infra=(0.34, 0.58), urban=(0.38, 0.62), life=(66, 75)),
    "frontier":   dict(w=0.22, gdppc=(1100, 4800), tech=(0.16, 0.36), edu=(0.20, 0.44),
                       infra=(0.16, 0.38), urban=(0.22, 0.46), life=(56, 68)),
    "extractive": dict(w=0.10, gdppc=(9000, 52000), tech=(0.28, 0.50), edu=(0.30, 0.56),
                       infra=(0.36, 0.66), urban=(0.55, 0.86), life=(66, 78)),
}


# ===========================================================================
def carve_regions(w, rng: RNG) -> None:
    """Multi-source growth partition of the landmass into provinces."""
    p = w.planet
    land = [t for t in p.land_tiles()]
    if not land:
        raise RuntimeError("planet has no land")
    nregions = max(24, min(260, len(land) // 17))

    def hab(t):
        b = BIOMES[t.biome]
        return 0.04 + b["hab"] * (0.5 + 0.5 * t.moist) + (0.35 if t.coastal else 0) \
            + 0.3 * min(1.0, t.river)

    seeds = rng.weighted_sample(land, [hab(t) ** 1.4 for t in land], nregions)
    frontier = deque()
    owner: dict[tuple[int, int], int] = {}
    for i, s in enumerate(seeds):
        owner[(s.x, s.y)] = i
        frontier.append((s, i))
    # randomised BFS keeps region shapes organic rather than square
    while frontier:
        t, i = frontier.popleft()
        for n in rng.shuffled(list(p.neighbours(t.x, t.y, diag=False))):
            if n.land and (n.x, n.y) not in owner:
                owner[(n.x, n.y)] = i
                frontier.append((n, i))

    groups: dict[int, list] = {}
    for (x, y), i in owner.items():
        groups.setdefault(i, []).append(p.t(x, y))

    for i, tiles in groups.items():
        if len(tiles) < 2:
            continue
        rid = w.nid("R")
        seed_t = tiles[0]
        cul = None      # assigned later with the nation
        r = Region(rid, "", "")
        r.tiles = [(t.x, t.y) for t in tiles]
        r.area = len(tiles) * 9800.0          # rough km² per tile
        r.coastal = any(t.coastal for t in tiles)
        r.centroid = (int(mean(t.x for t in tiles)), int(mean(t.y for t in tiles)))
        r.lat = mean(t.lat for t in tiles)
        bio = Counter()
        res = Counter()
        for t in tiles:
            bio.add(t.biome, 1.0)
            for k, v in t.res.items():
                res.add(k, v)
            t.region = rid
        r.biomes = bio.normalized()
        r.resources = dict(res)
        r.reserves = {k: v * rng.uniform(6e4, 2.4e5) for k, v in res.items()
                      if k in ("iron", "copper", "bauxite", "lithium", "rare_earth",
                               "gold", "gems", "uranium", "oil", "gas", "coal")}
        w.regions[rid] = r


def region_adjacency(w) -> dict[str, set[str]]:
    p = w.planet
    adj: dict[str, set[str]] = {rid: set() for rid in w.regions}
    for r in w.regions.values():
        for (x, y) in r.tiles:
            for n in p.neighbours(x, y, diag=False):
                if n.region and n.region != r.id:
                    adj[r.id].add(n.region)
    # sea links: coastal regions within reach of each other
    coastal = [r for r in w.regions.values() if r.coastal]
    for i, a in enumerate(coastal):
        for b in coastal[i + 1:]:
            dx = min(abs(a.centroid[0] - b.centroid[0]), p.w - abs(a.centroid[0] - b.centroid[0]))
            d = math.hypot(dx, a.centroid[1] - b.centroid[1])
            if d < 7 and b.id not in adj[a.id]:
                adj[a.id].add(b.id)
                adj[b.id].add(a.id)
    return adj


# ===========================================================================
def form_nations(w, rng: RNG) -> None:
    """Grow nations out of region seeds, then hand out the leftovers."""
    adj = w.adjacency = region_adjacency(w)
    regions = list(w.regions.values())
    target = max(8, min(48, len(regions) // 5))

    # bias seeds toward good land so capitals sit somewhere plausible
    def seedscore(r):
        return (r.resources.get("arable", 0) + 0.5 * r.resources.get("fishery", 0)
                + 0.3 * len(r.tiles)) * (1.4 if r.coastal else 1.0)

    seeds = rng.weighted_sample(regions, [seedscore(r) ** 1.2 + 0.5 for r in regions], target)
    cultures = rng.shuffled(N.CULTURES)
    nation_of: dict[str, str] = {}
    queues: dict[str, deque] = {}
    sizes: dict[str, int] = {}
    caps: dict[str, int] = {}

    for i, s in enumerate(seeds):
        short, formal = N.nation_name(rng, cultures[i % len(cultures)])
        nid = w.nid("N")
        nat = Nation(nid, short, formal, cultures[i % len(cultures)])
        nat.flagcolour = WM.pal_for(nid)
        w.nations[nid] = nat
        nation_of[s.id] = nid
        queues[nid] = deque([s.id])
        sizes[nid] = 1
        # a power-law of national sizes: a few giants, many small states
        caps[nid] = max(1, int(rng.pareto(1.25, 2.2)))

    # round-robin growth
    growing = True
    while growing:
        growing = False
        for nid, q in queues.items():
            if sizes[nid] >= caps[nid] or not q:
                continue
            for _ in range(len(q)):
                rid = q.popleft()
                took = False
                for nb in rng.shuffled(sorted(adj[rid])):
                    if nb not in nation_of:
                        nation_of[nb] = nid
                        q.append(nb)
                        sizes[nid] += 1
                        took = True
                        growing = True
                        break
                q.append(rid)
                if took:
                    break

    # orphans become microstates or join the nearest neighbour
    for r in regions:
        if r.id in nation_of:
            continue
        neigh = [nation_of[n] for n in sorted(adj[r.id]) if n in nation_of]
        if neigh and rng.chance(0.72):
            nation_of[r.id] = rng.pick(neigh)
        else:
            cul = rng.pick(N.CULTURES)
            short, formal = N.nation_name(rng, cul)
            nid = w.nid("N")
            nat = Nation(nid, short, formal, cul)
            nat.flagcolour = WM.pal_for(nid)
            w.nations[nid] = nat
            nation_of[r.id] = nid

    for rid, nid in nation_of.items():
        r = w.regions[rid]
        r.nation = nid
        r.core_of = nid
        w.nations[nid].regions.append(rid)

    # drop stillborn nations, name the regions
    for nid, nat in list(w.nations.items()):
        if not nat.regions:
            del w.nations[nid]
            continue
        for i, rid in enumerate(nat.regions):
            r = w.regions[rid]
            r.name = N.place_name(rng, nat.culture)
            r.culture = nat.culture


# ===========================================================================
def seed_development(w, rng: RNG) -> None:
    """Give each nation an economic archetype and derived characteristics."""
    keys = list(DEV_ARCHETYPES)
    weights = [DEV_ARCHETYPES[k]["w"] for k in keys]
    for nat in w.nations.values():
        arch = rng.weighted(keys, weights)
        d = DEV_ARCHETYPES[arch]
        nat.hist["arch"] = arch
        nat.tech_level = rng.uniform(*d["tech"])
        nat.hist["gdppc"] = rng.uniform(*d["gdppc"])
        nat.life_expectancy = rng.uniform(*d["life"])
        nat.hist["edu"] = rng.uniform(*d["edu"])
        nat.hist["infra"] = rng.uniform(*d["infra"])
        nat.hist["urban"] = rng.uniform(*d["urban"])
        nat.corruption = clamp01(rng.clamped_gauss(0.72 - 0.55 * nat.tech_level, 0.14, 0.04, 0.94))
        nat.state_capacity = clamp01(rng.clamped_gauss(0.28 + 0.62 * nat.tech_level, 0.11, 0.08, 0.97))
        nat.gini = clamp01(rng.clamped_gauss(0.40 - 0.06 * nat.tech_level
                                             + (0.10 if arch == "extractive" else 0), 0.07, 0.20, 0.68))


def distribute_population(w, rng: RNG) -> None:
    """Spread the world's people across regions by carrying capacity."""
    scores: dict[str, float] = {}
    for r in w.regions.values():
        nat = w.nations[r.nation]
        hab = sum(BIOMES[b]["hab"] * f for b, f in r.biomes.items())
        arable = r.resources.get("arable", 0.0)
        fish = r.resources.get("fishery", 0.0)
        s = (0.55 * hab * len(r.tiles) + 0.9 * arable + 0.25 * fish
             + 0.5 * len(r.tiles) * (0.35 if r.coastal else 0.0))
        s *= (0.65 + 0.9 * nat.hist["urban"])
        s *= rng.lognorm(1.0, 0.55)
        scores[r.id] = max(0.05, s)
    tot = sum(scores.values()) or 1.0
    for r in w.regions.values():
        r.pop = TARGET_POP * scores[r.id] / tot
        nat = w.nations[r.nation]
        dev = nat.tech_level
        # demographic transition: rich nations are old, poor nations young
        young = clamp(0.42 - 0.30 * dev, 0.13, 0.44)
        old = clamp(0.05 + 0.26 * dev, 0.04, 0.30)
        rest = 1 - young - old
        r.age = {"0-14": young, "15-24": rest * 0.24, "25-44": rest * 0.40,
                 "45-64": rest * 0.36, "65+": old}
        g = nat.gini
        r.wealth = {"poor": clamp01(0.20 + 1.05 * g - 0.35 * dev),
                    "rich": clamp01(0.04 + 0.22 * dev - 0.10 * g)}
        r.wealth["middle"] = clamp01(1 - r.wealth["poor"] - r.wealth["rich"])
        r.urban = clamp01(rng.jitter(nat.hist["urban"], 0.16))
        r.education = clamp01(rng.jitter(nat.hist["edu"], 0.14))
        r.literacy = clamp01(0.35 + 0.65 * r.education + rng.gauss(0, 0.05))
        r.infra = clamp01(rng.jitter(nat.hist["infra"], 0.18))
        r.health = clamp01(0.25 + 0.6 * dev + rng.gauss(0, 0.07))
        r.cultures = {nat.culture: 1.0}
        r.unrest = clamp01(rng.clamped_gauss(0.10 - 0.05 * dev + 0.10 * nat.corruption, 0.05, 0.0, 0.5))
    for nat in w.nations.values():
        nat.pop = sum(w.regions[rid].pop for rid in nat.regions)


def place_cities(w, rng: RNG) -> None:
    p = w.planet
    for r in w.regions.values():
        nat = w.nations[r.nation]
        ncity = 1 + min(5, int(math.log10(max(r.pop, 1e4)) - 4.4 + rng.random() * 2))
        tiles = [p.t(x, y) for (x, y) in r.tiles]

        def cscore(t):
            b = BIOMES[t.biome]
            return (b["hab"] + (1.1 if t.coastal else 0) + 0.8 * min(1.0, t.river)
                    + 0.3 * t.res.get("arable", 0) - 0.9 * max(0, t.elev - p.hill_level) * 8)

        best = sorted(tiles, key=lambda t: -cscore(t) - rng.random() * 0.4)
        urban_pop = r.pop * r.urban
        shares = sorted((rng.pareto(1.5, 1.0) for _ in range(ncity)), reverse=True)
        tot = sum(shares)
        for i in range(min(ncity, len(best))):
            t = best[i]
            cid = w.nid("C")
            pop = urban_pop * shares[i] / tot
            cy = City(cid, N.place_name(rng, nat.culture), r.id, pop, t.x, t.y, t.coastal)
            cy.tier = "major" if i == 0 and pop > 1.2e6 else ("mid" if pop > 4e5 else "minor")
            cy.university = rng.chance(clamp01(0.12 + 0.7 * r.education) if i == 0 else 0.18 * r.education)
            cy.airport = pop > 3e5 or rng.chance(0.2)
            cy.crime = clamp01(rng.clamped_gauss(0.22 - 0.12 * nat.tech_level
                                                 + 0.2 * nat.corruption, 0.07, 0.01, 0.8))
            cy.cost_of_living = clamp(0.4 + 1.8 * nat.tech_level + rng.gauss(0, 0.15), 0.25, 3.5)
            w.cities[cid] = cy
            r.cities.append(cid)
        if r.cities:
            r.capital_city = r.cities[0]

    for nat in w.nations.values():
        cs = w.nation_cities(nat.id)
        if not cs:
            continue
        cap = max(cs, key=lambda c: c.pop + (2e6 if c.port else 0))
        cap.capital = True
        cap.tier = "capital"
        cap.stock_exchange = nat.tech_level > 0.35
        cap.university = True
        nat.capital = cap.id


# ===========================================================================
def seed_technology(w, rng: RNG) -> None:
    """Give each nation the technologies its development level implies."""
    order = sorted(TECHS, key=lambda t: TECHS[t]["c"])
    for nat in w.nations.values():
        budget = 900 + 11000 * (nat.tech_level ** 2.1)
        known: set[str] = set()
        for t in order:
            d = TECHS[t]
            if any(pr not in known for pr in d["p"]):
                continue
            if d["c"] > budget * rng.uniform(0.72, 1.35):
                continue
            # weapons of mass destruction are not simply a function of GDP
            if d["e"].get("nuclear") and not rng.chance(0.16):
                continue
            known.add(t)
        nat.techs = known
        nat.research = {}
        if any(TECHS[t]["e"].get("nuclear") for t in known):
            nat.nukes = rng.randint(8, 320)
            nat.nuke_program = 1.0


def build_economy(w, rng: RNG) -> None:
    """Set wages and employment; the industry mix comes from io_balance."""
    from . import io_balance as IO
    for r in w.regions.values():
        nat = w.nations[r.nation]
        dev = nat.tech_level
        r.wage = clamp(0.22 + 3.0 * dev * (0.6 + 0.8 * r.education), 0.12, 8.0)
        r.employment = clamp01(rng.clamped_gauss(0.94 - 0.06 * (1 - dev), 0.03, 0.7, 0.99))
    for nat in w.nations.values():
        for g in GOODS:
            nat.prices[g] = GOODS[g]["base"] * rng.jitter(1.0, 0.08)
        nat.stockpile = Counter({g: 0.0 for g in GOODS})
        nat.gdp = nat.pop * nat.hist["gdppc"] / 360.0        # provisional, for sizing demand
        IO.allocate(w, nat)
    for r in w.regions.values():
        r.capital_stock = sum(r.capacity[i] * INDUSTRIES[i]["capital"] for i in r.capacity) * 4.2e4
        r.land_used = sum(r.capacity[i] * INDUSTRIES[i]["land"] for i in r.capacity)


def seed_stockpiles(w, rng: RNG) -> None:
    """Open the game with a realistic amount of cover in every warehouse."""
    from . import economy as E
    from . import io_balance as IO
    from .content_econ import GOODS as G
    for nat in w.nations.values():
        need = Counter()
        scale = getattr(nat, "demand_scale", 1.0)
        for g, q in IO.final_demand(w, nat).items():
            need.add(g, q * scale)
        for r in w.nation_regions(nat.id):
            for ind, want in E.plan_region(w, r).items():
                for g, q in INDUSTRIES[ind]["inp"].items():
                    if g in G:
                        need.add(g, want * q)
        nat.demand = {g: need.get(g, 0.0) for g in G}
        for g in G:
            w.market.stock[g] = w.market.stock.get(g, 0.0) + need.get(g, 0.0) * 55.0
        for g, d in G.items():
            days = 12.0 if d["perish"] > 0.02 else 40.0
            days *= 1.0 + 0.9 * d["strat"]
            nat.stockpile[g] = need.get(g, 0.0) * days * rng.uniform(0.90, 1.20)


# ===========================================================================
def generate_world(seed: int, log=None) -> "World":
    from .world import World
    w = World(seed)
    rng = w.rng
    say = log or (lambda *a: None)

    say("shaping the planet")
    w.planet = WM.generate(rng.sub("planet"))
    w.planet.activate()
    say("carving provinces")
    carve_regions(w, rng.sub("regions"))
    say("drawing borders")
    form_nations(w, rng.sub("nations"))
    seed_development(w, rng.sub("dev"))
    say("settling populations")
    distribute_population(w, rng.sub("pop"))
    place_cities(w, rng.sub("cities"))
    say("distributing technology")
    seed_technology(w, rng.sub("tech"))
    say("building economies")
    build_economy(w, rng.sub("econ"))
    seed_stockpiles(w, rng.sub("stock"))

    # a first pass of production so GDP exists before institutions size themselves
    from . import economy as E
    for nat in w.nations.values():
        va = 0.0
        for rid in nat.regions:
            _o, _u, v = E.produce_region(w, w.regions[rid], nat.prices)
            va += v
        nat.gdp = va
    w.recompute_globals()

    from . import worldgen_social as S
    say("forming governments")
    S.seed_politics(w, rng.sub("politics"))
    S.seed_parties(w, rng.sub("parties"))
    say("seeding faiths")
    S.seed_faiths(w, rng.sub("faiths"))
    say("populating the world with people")
    S.populate_people(w, rng.sub("people"))
    say("chartering institutions")
    S.make_orgs(w, rng.sub("orgs"))
    say("raising armies")
    S.seed_military(w, rng.sub("mil"))
    say("negotiating the state of the world")
    S.seed_relations(w, rng.sub("rel"))
    S.seed_endemics(w, rng.sub("dz"))
    w.recompute_globals()
    for nat in w.nations.values():
        nat.treasury = max(nat.gdp * 360, 1e7) * rng.uniform(0.01, 0.09)
        nat.debt = max(nat.gdp * 360, 1e7) * rng.uniform(0.15, 1.5)
        nat.fx_reserves = max(nat.gdp * 360, 1e7) * rng.uniform(0.02, 0.20)
        nat.money_supply = max(nat.gdp * 360, 1e7) * rng.uniform(0.4, 1.1)
    return w
