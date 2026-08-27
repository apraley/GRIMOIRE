"""Technology, environment, individual agency, and the world's random events."""
from __future__ import annotations

import math

from . import names as N
from .content_conflict import CRISIS_KINDS
from .content_econ import BIOMES, GOODS
from .content_social import AXES, SECRET_KINDS
from .content_tech import RESEARCH_PROJECTS, TECHS
from .util import Counter, clamp, clamp01, lerp, mean


# ===========================================================================
def research_points(w, nat) -> float:
    budget = nat.gdp * nat.get_policy("research") * 0.030
    unis = sum(o.assets.get("research", 0.0) for o in w.orgs.values()
               if o.kind == "university" and o.nation == nat.id and o.alive)
    corp_cap = nat.gdp * 0.06          # R&D cannot exceed a sane share of output
    corp = sum(o.rnd for o in w.orgs.values()
               if o.kind == "corp" and o.nation == nat.id and o.alive)
    human = mean([w.regions[r].education for r in nat.regions if r in w.regions] or [0.3])
    corp = min(corp, corp_cap)
    rp = (budget * 1.8e-9 + corp * 1.1e-9 + unis * 0.05) * (0.35 + 1.5 * human)
    mult = 1.0
    for t in nat.techs:
        mult += TECHS[t]["e"].get("research", 0.0)
    rp *= mult * (0.5 + 0.8 * nat.state_capacity) * (1 - 0.4 * nat.war_exhaustion)
    return max(0.0, rp)


def available_techs(w, nat) -> list[str]:
    return [t for t, d in TECHS.items()
            if t not in nat.techs and all(p in nat.techs for p in d["p"])]


def tick_research(w) -> None:
    rng = w.rng.sub("research")
    for nat in w.living_nations():
        rp = research_points(w, nat)
        nat.rp_per_day = rp
        if rp <= 0:
            continue
        avail = available_techs(w, nat)
        if not avail:
            continue
        if nat.research_focus not in avail:
            nat.research_focus = None
        if nat.research_focus is None or rng.chance(0.004):
            # pick by ideology, need, and cheapness
            def score(t):
                d = TECHS[t]
                s = 1.0 / (1 + d["c"] / 4000.0)
                e = d["e"]
                s *= 1 + 1.4 * nat.ideology.get("milit", 0) if d["f"] == "weapons" else 1.0
                s *= 1 + 1.2 * nat.ideology.get("eco", 0) if d["f"] == "energy" else 1.0
                s *= 1 + 1.1 * nat.ideology.get("auth", 0) if "control" in e or "surveil" in e else 1.0
                s *= 1 + 2.0 * nat.get_policy("space_program") if d["f"] == "space" else 1.0
                s *= 1 + 0.8 * nat.get_policy("healthcare") if d["f"] == "medicine" else 1.0
                if nat.at_war and d["f"] == "weapons":
                    s *= 2.2
                return max(0.01, s)
            nat.research_focus = rng.weighted(avail, [score(t) for t in avail])
        focus = nat.research_focus
        # spillover: the whole tree creeps forward, the focus sprints
        nat.research[focus] = nat.research.get(focus, 0.0) + rp * 0.72
        for t in avail[:6]:
            if t != focus:
                nat.research[t] = nat.research.get(t, 0.0) + rp * 0.28 / max(len(avail[:6]), 1)
        # global diffusion: known techs get cheaper for everyone
        for t in list(nat.research):
            if t not in TECHS:
                del nat.research[t]
                continue
            knowers = w.flags.get("tech_known", {}).get(t, 0)
            cost = TECHS[t]["c"] * clamp(1.0 - knowers * 0.030, 0.40, 1.0)
            if nat.research[t] >= cost:
                acquire_tech(w, nat, t)
                del nat.research[t]
                nat.research_focus = None
        nat.tech_level = clamp01(lerp(nat.tech_level, _tech_index(nat), 0.02))


def _tech_index(nat) -> float:
    if not TECHS:
        return 0.4
    have = sum(math.log1p(TECHS[t]["c"]) for t in nat.techs if t in TECHS)
    total = sum(math.log1p(d["c"]) for d in TECHS.values())
    return clamp01(0.06 + 0.98 * (have / total) ** 0.62)


def acquire_tech(w, nat, tech: str, quiet: bool = False) -> None:
    if tech in nat.techs:
        return
    nat.techs.add(tech)
    known = w.flags.setdefault("tech_known", {})
    known[tech] = known.get(tech, 0) + 1
    d = TECHS[tech]
    e = d["e"]
    if e.get("nuclear") and nat.nukes == 0:
        nat.nuke_program = max(nat.nuke_program, 0.35)
    if "prestige" in e:
        nat.prestige = clamp01(nat.prestige + e["prestige"])
    if "risk" in e:
        w.doomsday = clamp01(w.doomsday + e["risk"] * 0.06)
    if "singularity" in e:
        w.flags["singularity_reached"] = w.clock.day
        w.report(f"{nat.name} announces systems that design their own successors. "
                 f"Nobody is certain what happens next.", "tech", nat.id, 1.0, ["singularity"])
    if not quiet and (known[tech] <= 2 or d["c"] > 9000):
        w.report(f"{nat.name} achieves a breakthrough in {tech.replace('_', ' ')}: {d['d']}",
                 "tech", nat.id, clamp01(0.35 + d["c"] / 20000), ["tech"])


# ===========================================================================
def tick_environment(w) -> None:
    """Weather, seasons, pollution, emissions and the climate itself."""
    rng = w.rng.sub("env")
    planet = w.planet
    # daily weather shock per region (cheap: sample a subset, decay the rest)
    for r in rng.sample(list(w.regions.values()), min(len(w.regions), 40)):
        base = 1.0
        drought = clamp01(0.28 + planet.temp_anomaly * 0.08 - 0.2 * sum(
            f for b, f in r.biomes.items() if b in ("wetland", "rainforest", "temperate")))
        shock = rng.gauss(0, 0.14) - max(0.0, rng.random() - (1 - drought * 0.10)) * 1.2
        r.__dict__["_weather"] = clamp(lerp(r.__dict__.get("_weather", 1.0), base + shock, 0.35),
                                       0.25, 1.5)
    for r in w.regions.values():
        if "_weather" in r.__dict__:
            r.__dict__["_weather"] = lerp(r.__dict__["_weather"], 1.0, 0.02)

    if w.clock.day % 10:
        return
    # emissions and the carbon cycle
    total_em = 0.0
    for nat in w.living_nations():
        dirty = 0.0
        for r in w.nation_regions(nat.id):
            dirty += r.pollution
        clean = sum(TECHS[t]["e"].get("emissions", 0.0) for t in nat.techs)
        em = max(0.0, nat.gdp * 1.0e-11 * (1.6 - nat.tech_level * 0.5)
                 * (1 - nat.get_policy("environment") * 0.55) * (1 + clean))
        nat.emissions = em
        total_em += em
        for r in w.nation_regions(nat.id):
            r.pollution = clamp(r.pollution * (1 - 0.004 * (0.3 + nat.get_policy("environment")))
                                + em * 1e-4 / max(len(nat.regions), 1), 0, 6)
    sink = 0.55
    planet.co2 += (total_em * (1 - sink)) * 0.0055 - 0.004
    planet.co2 = max(280.0, planet.co2)
    forcing = 5.35 * math.log(planet.co2 / 280.0)
    planet.temp_anomaly = lerp(planet.temp_anomaly, forcing * 0.55, 0.004)
    planet.sea_rise = max(0.0, planet.sea_rise + planet.temp_anomaly * 4.5e-5)
    w.doomsday = clamp01(lerp(w.doomsday,
                              clamp01(planet.temp_anomaly / 9.0 + w.tension * 0.22), 0.004))


DISASTERS = [
    ("earthquake", 0.16, "An earthquake strikes {place}."),
    ("hurricane", 0.16, "A cyclone makes landfall in {place}."),
    ("flood", 0.18, "Catastrophic flooding inundates {place}."),
    ("drought", 0.14, "A prolonged drought grips {place}."),
    ("wildfire", 0.12, "Wildfires sweep through {place}."),
    ("volcano", 0.05, "A volcanic eruption blankets {place} in ash."),
    ("heatwave", 0.11, "A lethal heatwave settles over {place}."),
    ("tsunami", 0.04, "A tsunami devastates the coast of {place}."),
    ("blizzard", 0.04, "A record blizzard paralyses {place}."),
]


def maybe_disaster(w) -> None:
    rng = w.rng.sub("disaster")
    rate = 0.055 * (1 + w.planet.temp_anomaly * 0.35)
    if not rng.chance(rate):
        return
    kind = rng.weighted([k for k, _p, _t in DISASTERS], [p for _k, p, _t in DISASTERS])
    text = next(t for k, _p, t in DISASTERS if k == kind)
    cands = [r for r in w.regions.values() if r.pop > 5e4]
    if not cands:
        return

    def suit(r):
        s = 1.0
        if kind == "hurricane":
            s = 2.5 if (r.coastal and abs(r.lat) < 38) else 0.05
        elif kind == "tsunami":
            s = 2.0 if r.coastal else 0.0
        elif kind == "drought":
            s = 1.0 + 3.0 * sum(f for b, f in r.biomes.items() if b in ("desert", "steppe", "savanna"))
        elif kind == "wildfire":
            s = 1.0 + 2.5 * sum(f for b, f in r.biomes.items() if b in ("taiga", "mediterran", "grassland"))
        elif kind == "blizzard":
            s = 3.0 if abs(r.lat) > 42 else 0.05
        elif kind == "heatwave":
            s = 1.0 + 2.0 * clamp01((32 - abs(r.lat)) / 32)
        elif kind == "flood":
            s = 1.0 + 2.0 * sum(f for b, f in r.biomes.items() if b in ("wetland", "rainforest"))
        elif kind == "volcano":
            s = 1.0 + 3.0 * r.biomes.get("mountain", 0)
        return max(0.01, s * math.log10(max(r.pop, 100)))

    r = rng.weighted(cands, [suit(x) for x in cands])
    nat = w.nations.get(r.nation)
    if nat is None:
        return
    severity = clamp01(rng.beta(1.8, 3.4) * (1 + w.planet.temp_anomaly * 0.16))
    resilience = clamp01(0.25 + 0.45 * nat.tech_level + 0.30 * r.effective_infra()
                         + 0.20 * nat.state_capacity)
    impact = severity * (1 - resilience * 0.72)
    dead = r.pop * impact * 0.0022
    r.pop = max(0.0, r.pop - dead)
    r.devastation = clamp01(r.devastation + impact * 0.30)
    r.unrest = clamp01(r.unrest + impact * 0.10)
    r.infra = clamp01(r.infra - impact * 0.12)
    if kind in ("drought", "heatwave", "flood"):
        r.__dict__["_weather"] = clamp(r.__dict__.get("_weather", 1.0) - impact * 0.7, 0.15, 1.5)
    for cid in r.cities:
        c = w.cities.get(cid)
        if c:
            c.damage = clamp01(c.damage + impact * 0.22)
    nat.treasury = max(0.0, nat.treasury - nat.gdp * impact * 4)
    if dead > 200 or impact > 0.3:
        w.report(text.format(place=f"{r.name}, {nat.name}")
                 + f" Around {dead:,.0f} are dead and {r.pop * impact * 0.03:,.0f} displaced.",
                 "disaster", nat.id, clamp01(0.4 + impact), ["disaster", kind])


# ===========================================================================
def tick_people(w) -> None:
    """Ageing, death, ambition, and the churn of elites."""
    rng = w.rng.sub("people")
    if w.clock.day % 30:
        return
    for p in list(w.people.values()):
        if not p.alive:
            continue
        nat = w.nations.get(p.nation)
        p.age += 1 / 12.0
        base = nat.life_expectancy if nat else 72
        hazard = clamp01(math.exp((p.age - base) / 9.0) * 0.0022 / max(p.health, 0.2))
        hazard *= 1 - 0.35 * p.protection
        if rng.chance(hazard):
            _kill(w, p, "natural causes")
            continue
        p.health = clamp01(p.health - max(0.0, (p.age - 45)) * 0.00016
                           - p.stress * 0.0018 + 0.0022)
        p.stress = clamp01(p.stress * 0.985 + rng.gauss(0, 0.02)
                           + (0.02 if nat and nat.at_war else 0.0))
        p.wealth *= 1 + (p.income * 30 / max(p.wealth, 1)) if p.wealth > 0 else 1
        if nat:
            p.wealth *= 1 + (nat.growth / 12.0) * (0.4 + p.power)
            if rng.chance(p.corruptibility * nat.corruption * 0.04):
                take = nat.gdp * 0.0004 * p.power
                p.wealth += take
                nat.treasury = max(0.0, nat.treasury - take)
                if rng.chance(0.05 * nat.media_freedom):
                    _expose_corruption(w, p, nat)
        # ambition drives people to climb
        if rng.chance(p.ambition * 0.012) and nat:
            _climb(w, p, nat, rng)


def _kill(w, p, cause: str) -> None:
    p.alive = False
    p.death_day = w.clock.day
    p.death_cause = cause
    w.obituaries.append((w.clock.day, p.id, cause))
    if len(w.obituaries) > 3000:
        del w.obituaries[:1000]
    nat = w.nations.get(p.nation)
    if nat is None:
        return
    if nat.head_of_state == p.id or nat.head_of_gov == p.id:
        _succeed(w, nat, p)
        w.report(f"{p.describe_role()} {p.name} of {nat.name} has died ({cause}).",
                 "politics", nat.id, 0.9, ["death"])
    for role, pid in list(nat.cabinet.items()):
        if pid == p.id:
            from .worldgen_social import make_person
            nat.cabinet[role] = make_person(w, w.rng.sub("succ"), nat.id, role).id
    for o in w.orgs.values():
        if o.leader == p.id:
            pool = [q for q in w.people.values() if q.alive and q.nation == o.nation
                    and q.org == o.id]
            o.leader = pool[0].id if pool else None


def _succeed(w, nat, dead) -> None:
    from .worldgen_social import make_person
    rng = w.rng.sub("succession")
    if nat.is_democracy():
        pool = [p for p in w.people.values() if p.alive and p.nation == nat.id
                and p.role in ("head_of_government", "legislator", "governor")]
    else:
        pool = [p for p in w.people.values() if p.alive and p.nation == nat.id
                and p.role in ("chief_of_staff", "interior_minister", "defence_minister",
                               "general", "intelligence_chief")]
    heir = max(pool, key=lambda p: p.power * (0.5 + p.ambition)) if pool else \
        make_person(w, rng, nat.id, "head_of_state")
    heir.role = "head_of_state"
    heir.title = dead.title or "President"
    heir.power = clamp01(heir.power + 0.35)
    nat.head_of_state = heir.id
    nat.head_of_gov = heir.id
    nat.leader_since = w.clock.day
    nat.legitimacy = clamp01(nat.legitimacy - (0.02 if nat.is_democracy() else 0.10))
    nat.stability = clamp01(nat.stability - (0.02 if nat.is_democracy() else 0.12))
    if not nat.is_democracy():
        nat.unrest = clamp01(nat.unrest + 0.05)


def _climb(w, p, nat, rng) -> None:
    from .content_social import ROLE_POWER
    ladder = {"legislator": "governor", "governor": "head_of_government",
              "editor": "media_baron", "smuggler": "crime_boss",
              "spy": "intelligence_chief", "general": "defence_minister",
              "banker": "finance_minister", "diplomat": "foreign_minister",
              "activist": "legislator", "professor": "scientist",
              "police_chief": "interior_minister", "lobbyist": "legislator"}
    nxt = ladder.get(p.role)
    if not nxt:
        p.power = clamp01(p.power + 0.004)
        return
    rival = None
    if nxt in nat.cabinet:
        rival = w.people.get(nat.cabinet[nxt])
    if rival and rival.alive:
        if p.power * (0.6 + p.ambition) < rival.power * 1.15:
            return
        rival.role = "legislator"
        rival.power = clamp01(rival.power * 0.6)
    p.role = nxt
    p.power = clamp01(max(p.power, ROLE_POWER.get(nxt, 0.3) * 0.9))
    if nxt in nat.cabinet or nxt in ("head_of_government",):
        nat.cabinet[nxt] = p.id
    if nxt == "head_of_government" and nat.head_of_gov != nat.head_of_state:
        nat.head_of_gov = p.id


def _expose_corruption(w, p, nat) -> None:
    from .sim_society import add_narrative
    add_narrative(w, "scandal",
                  f"{p.name} is revealed to have diverted state funds.",
                  subject=p.id, seed_nation=nat.id, seed=0.10, credibility=0.7)
    p.power = clamp01(p.power - 0.06)
    p.public_profile = clamp01(p.public_profile + 0.10)
    nat.approval = clamp01(nat.approval - 0.01)
    w.report(f"Corruption scandal: {p.name} ({p.describe_role()}, {nat.name}) is accused of "
             f"diverting public money.", "politics", nat.id, 0.55, ["scandal"])


# ===========================================================================
def tick_crises(w) -> None:
    """Discrete geopolitical shocks that reshape the board."""
    rng = w.rng.sub("crisis")
    if not rng.chance(0.020 + w.tension * 0.045):
        return
    nats = w.living_nations()
    if len(nats) < 2:
        return
    kind = rng.pick(CRISIS_KINDS)
    a = rng.weighted(nats, [n.gdp + 1 for n in nats])
    handlers = {
        "border_incident": _crisis_border, "financial_panic": _crisis_panic,
        "energy_shock": _crisis_energy, "cyber_blackout": _crisis_cyber,
        "market_crash": _crisis_crash, "currency_collapse": _crisis_currency,
        "trade_war": _crisis_tradewar, "terror_attack": _crisis_terror,
        "refugee_surge": _crisis_refugee, "nuclear_test": _crisis_nuke_test,
    }
    fn = handlers.get(kind)
    if fn:
        fn(w, a, rng)


def _crisis_border(w, a, rng):
    nb = [w.nations[n] for n in w.neighbours.get(a.id, []) if n in w.nations and w.nations[n].alive]
    if not nb:
        return
    b = rng.pick(nb)
    a.relations[b.id] = clamp(a.relation(b.id) - 0.18, -1, 1)
    b.relations[a.id] = clamp(b.relation(a.id) - 0.18, -1, 1)
    w.tension = clamp01(w.tension + 0.012)
    w.report(f"Shots are exchanged on the {a.name}-{b.name} border. Both sides blame the other.",
             "diplomacy", a.id, 0.6, ["incident"])


def _crisis_panic(w, a, rng):
    w.market.sentiment = clamp(w.market.sentiment - rng.uniform(0.3, 0.8), -1, 1)
    a.credit_rating = clamp01(a.credit_rating - 0.12)
    for o in w.orgs.values():
        if o.kind == "bank" and o.nation == a.id:
            o.cash *= 0.75
    w.report(f"A funding crisis hits the banks of {a.name}; depositors queue at branches.",
             "economy", a.id, 0.8, ["panic"])


def _crisis_energy(w, a, rng):
    for g in ("crude", "gas", "fuel"):
        w.market.price[g] = min(GOODS[g]["base"] * 12, w.market.price[g] * rng.uniform(1.25, 1.8))
    w.report("Energy markets spike after a supply disruption; freight and fertiliser follow.",
             "economy", weight=0.75, tags=["energy"])


def _crisis_cyber(w, a, rng):
    for r in w.nation_regions(a.id):
        r.employment = clamp01(r.employment - 0.05)
        r.unrest = clamp01(r.unrest + 0.03)
    a.state_capacity = clamp01(a.state_capacity - 0.03)
    w.report(f"A cyber attack takes down the power grid across much of {a.name}.",
             "tech", a.id, 0.8, ["cyber"])


def _crisis_crash(w, a, rng):
    w.market.sentiment = clamp(w.market.sentiment - rng.uniform(0.5, 1.2), -1, 1)
    for o in w.orgs.values():
        if o.public:
            o.share_price *= rng.uniform(0.55, 0.85)
            o.valuation = o.share_price * o.shares
    w.report("Equity markets fall sharply worldwide; trillions in paper wealth evaporate.",
             "economy", weight=0.9, tags=["crash"])


def _crisis_currency(w, a, rng):
    a.currency *= rng.uniform(1.4, 3.0)
    a.inflation = clamp(a.inflation + rng.uniform(0.15, 0.7), -0.05, 3.0)
    a.fx_reserves *= 0.5
    for r in w.nation_regions(a.id):
        r.unrest = clamp01(r.unrest + 0.06)
    w.report(f"The {a.name} currency collapses on foreign exchange markets.",
             "economy", a.id, 0.85, ["currency"])


def _crisis_tradewar(w, a, rng):
    others = [n for n in w.living_nations() if n.id != a.id]
    if not others:
        return
    b = rng.weighted(others, [max(0.05, -a.relation(n.id) + 0.3) for n in others])
    a.set_policy("tariff", a.get_policy("tariff") + 0.14)
    b.set_policy("tariff", b.get_policy("tariff") + 0.14)
    a.relations[b.id] = clamp(a.relation(b.id) - 0.15, -1, 1)
    w.trade_openness = clamp01(w.trade_openness - 0.03)
    w.report(f"{a.name} and {b.name} impose retaliatory tariffs; supply chains scramble.",
             "economy", a.id, 0.7, ["trade_war"])


def _crisis_terror(w, a, rng):
    cs = w.nation_cities(a.id)
    if not cs:
        return
    c = rng.weighted(cs, [x.pop for x in cs])
    dead = rng.randint(6, 900)
    c.pop = max(0.0, c.pop - dead)
    a.unrest = clamp01(a.unrest + 0.03)
    a.set_policy("policing", a.get_policy("policing") + 0.06)
    a.set_policy("surveillance", a.get_policy("surveillance") + 0.05)
    a.ideology["auth"] = clamp(a.ideology["auth"] + 0.05, -1, 1)
    from .sim_society import add_narrative
    add_narrative(w, "threat", f"An attack in {c.name} kills {dead}.", seed_nation=a.id, seed=0.30)
    w.report(f"Attack in {c.name}, {a.name}: {dead} dead. Emergency powers are invoked.",
             "unrest", a.id, 0.85, ["terror"])


def _crisis_refugee(w, a, rng):
    src = [r for r in w.nation_regions(a.id)]
    if not src:
        return
    r = max(src, key=lambda x: x.unrest + x.devastation)
    nb = [w.nations[n] for n in w.neighbours.get(a.id, []) if n in w.nations and w.nations[n].alive]
    if not nb:
        return
    dest = rng.pick(nb)
    movers = r.pop * rng.uniform(0.004, 0.03)
    r.pop -= movers
    drs = [w.regions[x] for x in dest.regions if x in w.regions]
    if drs:
        target = rng.pick(drs)
        target.pop += movers
        target.unrest = clamp01(target.unrest + 0.05 * (1 - dest.get_policy("immigration")))
    dest.ideology["nation"] = clamp(dest.ideology["nation"] + 0.04, -1, 1)
    w.report(f"{movers / 1e3:,.0f} thousand people flee {r.name} for {dest.name}.",
             "unrest", a.id, 0.7, ["refugees"])


def _crisis_nuke_test(w, a, rng):
    if a.nukes == 0 and a.nuke_program <= 0:
        cands = [n for n in w.living_nations() if n.nuke_program > 0 or n.nukes > 0]
        if not cands:
            return
        a = rng.pick(cands)
    if a.nukes == 0:
        a.nuke_program = clamp01(a.nuke_program + 0.25)
        w.report(f"Seismic sensors detect a suspected weapons test in {a.name}.",
                 "war", a.id, 0.8, ["nuclear"])
    else:
        w.tension = clamp01(w.tension + 0.05)
        w.report(f"{a.name} conducts a demonstrative nuclear test.", "war", a.id, 0.85, ["nuclear"])
    for n in w.living_nations():
        if n.id != a.id:
            n.relations[a.id] = clamp(n.relation(a.id) - 0.10, -1, 1)
