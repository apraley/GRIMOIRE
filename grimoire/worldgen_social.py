"""Second half of world generation: politics, people, institutions, diplomacy."""
from __future__ import annotations

import math

from . import names as N
from .content_conflict import DISEASES, DOCTRINES, FAITH_DOCTRINES, RACKETS, UNITS
from .content_econ import GOODS, INDUSTRIES
from .content_social import (ATTRIBUTES, AUDIENCES, AXES, BACKGROUNDS, GOV_TYPES,
                             IDEOLOGIES, POLICIES, POLICY_IDEOLOGY, ROLE_POWER,
                             SECRET_KINDS, SKILLS, TRAITS)
from .content_tech import TECHS
from .entities import Faith, Org, Person
from .rng import RNG
from .util import Counter, clamp, clamp01, lerp, mean


# ===========================================================================
def _ideology_vector(rng: RNG, base: str | None = None) -> dict:
    if base:
        v = IDEOLOGIES[base]["v"]
        return {a: clamp(v[i] + rng.gauss(0, 0.16), -1, 1) for i, a in enumerate(AXES)}
    return {a: clamp(rng.gauss(0, 0.42), -1, 1) for a in AXES}


def ideology_distance(a: dict, b: dict) -> float:
    return math.sqrt(sum((a.get(k, 0) - b.get(k, 0)) ** 2 for k in AXES)) / math.sqrt(len(AXES) * 4)


def nearest_ideology(v: dict) -> str:
    best, bd = "liberalism", 9e9
    for k, d in IDEOLOGIES.items():
        vec = {a: d["v"][i] for i, a in enumerate(AXES)}
        dist = ideology_distance(v, vec)
        if dist < bd:
            best, bd = k, dist
    return best


def apply_ideology_to_policy(nat) -> None:
    for pol, weights in POLICY_IDEOLOGY.items():
        d = POLICIES[pol]
        push = sum(nat.ideology.get(a, 0) * wgt for a, wgt in weights.items())
        mid = (d["lo"] + d["hi"]) / 2
        span = (d["hi"] - d["lo"]) / 2
        nat.policy[pol] = clamp(mid + push * span * 0.85, d["lo"], d["hi"])


# ===========================================================================
def seed_politics(w, rng: RNG) -> None:
    for nat in w.nations.values():
        dev = nat.tech_level
        # richer states skew democratic; resource states skew personalist
        weights = {}
        for g, d in GOV_TYPES.items():
            base = 1.0
            if d["elections"]:
                base *= 0.35 + 2.1 * dev
            else:
                base *= 1.5 - 0.9 * dev
            if g == "failed_state":
                base *= 0.20 + 1.6 * max(0.0, 0.35 - dev)
            if g in ("corporate_state", "technocracy") and dev < 0.5:
                base *= 0.2
            if g == "liberal_democracy" and dev < 0.55:
                base *= 0.25
            weights[g] = base
        nat.gov = rng.weighted_dict(weights)
        gd = GOV_TYPES[nat.gov]
        nat.repression = clamp01(rng.jitter(gd["repress"], 0.25))
        nat.legitimacy = clamp01(rng.clamped_gauss(gd["legit_base"], 0.11, 0.05, 0.95))
        nat.corruption = clamp01(lerp(nat.corruption, gd["corrupt"], 0.45))
        nat.approval = clamp01(rng.clamped_gauss(0.48, 0.14, 0.08, 0.92))
        nat.stability = clamp01(0.30 + 0.42 * nat.legitimacy + 0.25 * nat.state_capacity
                                - 0.30 * nat.corruption + rng.gauss(0, 0.08))
        nat.unrest = clamp01(1 - nat.stability - 0.25 + rng.gauss(0, 0.05))
        nat.media_freedom = clamp01(1.0 - gd["repress"] * 1.15 + rng.gauss(0, 0.10))

        lean = rng.weighted_dict({k: (2.0 if IDEOLOGIES[k]["appeal"] in ("workers", "urban", "rural") else 1.0)
                                  for k in IDEOLOGIES})
        nat.ideology = _ideology_vector(rng, lean)
        if not gd["elections"]:
            nat.ideology["auth"] = clamp(nat.ideology["auth"] + 0.45, -1, 1)
        apply_ideology_to_policy(nat)
        nat.doctrine = rng.pick(list(DOCTRINES))
        nat.term_length = rng.pick([1080, 1440, 1800])
        nat.next_election = rng.randint(60, nat.term_length) if gd["elections"] else 0
        nat.prestige = clamp01(0.12 + 0.55 * dev + rng.gauss(0, 0.10))
        nat.soft_power = clamp01(0.08 + 0.5 * dev + rng.gauss(0, 0.12))
        nat.intel_capacity = clamp01(0.08 + 0.7 * dev * (0.5 + nat.get_policy("intel_budget")))
        nat.rate = clamp(0.015 + 0.05 * (1 - dev) + rng.gauss(0, 0.01), 0.0, 0.22)
        nat.inflation = clamp(0.015 + 0.045 * (1 - dev) + rng.gauss(0, 0.012), -0.02, 0.5)
        nat.unemployment = clamp01(1 - mean([w.regions[r].employment for r in nat.regions]))
        nat.opinion = {a: clamp(rng.gauss(0, 0.22), -1, 1) for a in AUDIENCES}
        nat.morale = clamp01(rng.clamped_gauss(0.62, 0.12, 0.2, 0.95))
        nat.readiness = clamp01(rng.clamped_gauss(0.45 + 0.3 * nat.get_policy("military"), 0.12, 0.1, 0.98))
        nat.army_loyalty = clamp01(rng.clamped_gauss(0.72 - 0.2 * nat.corruption, 0.12, 0.1, 0.99))


def seed_parties(w, rng: RNG) -> None:
    for nat in w.nations.values():
        gd = GOV_TYPES[nat.gov]
        count = rng.randint(3, 7) if gd["elections"] else rng.randint(1, 3)
        shares = rng.spread(count, 1.0, 1.3)
        for i in range(count):
            oid = w.nid("O")
            base = nearest_ideology(_ideology_vector(rng)) if i else nearest_ideology(nat.ideology)
            o = Org(oid, N.party_name(rng, nat.culture), "party", nat.id)
            o.ideology = _ideology_vector(rng, base)
            o.hq = nat.capital
            o.influence = shares[i]
            o.assets["seats"] = shares[i]
            o.assets["support"] = shares[i]
            o.tags = {base}
            w.orgs[oid] = o
            nat.parties.append(oid)
        nat.parties.sort(key=lambda o: -w.orgs[o].assets["seats"])
        nat.ruling_party = nat.parties[0]
        nat.coalition = [nat.parties[0]]
        acc = w.orgs[nat.parties[0]].assets["seats"]
        for pid in nat.parties[1:]:
            if acc >= 0.5:
                break
            nat.coalition.append(pid)
            acc += w.orgs[pid].assets["seats"]


# ===========================================================================
def seed_faiths(w, rng: RNG) -> None:
    per_culture: dict[str, list[str]] = {}
    for cul in N.CULTURES:
        n = rng.randint(1, 2)
        for _ in range(n):
            fid = w.nid("F")
            f = Faith(fid, N.faith_name(rng, cul), rng.weighted_dict(
                {k: 1.0 for k in FAITH_DOCTRINES}))
            dd = FAITH_DOCTRINES[f.doctrine]
            f.ideology = {a: clamp(dd["v"][i] + rng.gauss(0, 0.12), -1, 1) for i, a in enumerate(AXES)}
            f.militancy = clamp01(rng.jitter(dd["militancy"], 0.3))
            f.orthodoxy = clamp01(rng.uniform(0.3, 0.9))
            w.faiths[fid] = f
            per_culture.setdefault(cul, []).append(fid)
    universal = rng.sample(list(w.faiths), 3)

    for r in w.regions.values():
        nat = w.nations[r.nation]
        pool = per_culture.get(nat.culture, []) + universal
        picks = rng.sample(pool, min(len(pool), rng.randint(1, 3)))
        shares = rng.spread(len(picks) + 1, 1.0, 1.1)
        r.faiths = {picks[i]: shares[i] for i in range(len(picks))}
        r.faiths["secular"] = shares[-1] * (0.4 + 1.4 * nat.tech_level)
        tot = sum(r.faiths.values())
        r.faiths = {k: v / tot for k, v in r.faiths.items()}
    for f in w.faiths.values():
        f.adherents = sum(r.pop * r.faiths.get(f.id, 0) for r in w.regions.values())
    for nat in w.nations.values():
        agg = Counter()
        for rid in nat.regions:
            r = w.regions[rid]
            for k, v in r.faiths.items():
                agg.add(k, v * r.pop)
        nat.faiths = agg.normalized()


# ===========================================================================
def make_person(w, rng: RNG, nation: str, role: str, region: str | None = None,
                age_range=(34, 72), power: float | None = None) -> Person:
    nat = w.nations[nation]
    female = rng.chance(0.44)
    pid = w.nid("P")
    p = Person(pid, N.person_name(rng, nat.culture, female), nat.culture, nation,
               rng.randint(*age_range), female)
    p.role = role
    p.region = region or (rng.pick(nat.regions) if nat.regions else None)
    if p.region:
        cities = w.regions[p.region].cities
        p.city = rng.pick(cities) if cities else None
    rp = ROLE_POWER.get(role, 0.2)
    for a in ATTRIBUTES:
        p.attrs[a] = int(clamp(rng.gauss(10 + rp * 4, 2.6), 1, 20))
    ncount = rng.randint(3, 8)
    for k in rng.sample(list(SKILLS), ncount):
        p.skills[k] = clamp01(rng.beta(2.2, 3.0) * (0.5 + rp))
    for k in _role_skills(role):
        p.skills[k] = clamp01(max(p.skills.get(k, 0), rng.uniform(0.35, 0.55) + rp * 0.35))
    p.traits = rng.sample(list(TRAITS), rng.randint(2, 4))
    p.ideology = _ideology_vector(rng, nearest_ideology(nat.ideology) if rng.chance(0.5) else None)
    p.faith = rng.weighted_dict({k: v for k, v in nat.faiths.items() if k != "secular"}) \
        if nat.faiths and rng.chance(0.6) else None
    p.power = power if power is not None else clamp01(rng.clamped_gauss(rp, 0.12, 0.02, 1.0))
    p.wealth = rng.lognorm(2.4e5 * (1 + 40 * rp) * (0.2 + 2 * nat.tech_level), 1.5)
    p.income = p.wealth * rng.uniform(0.04, 0.22) / 360
    p.ambition = clamp01(rng.beta(2.4, 2.4) + rp * 0.2)
    p.corruptibility = clamp01(rng.beta(2.0, 3.0) * (0.5 + nat.corruption))
    p.competence = clamp01(rng.clamped_gauss(0.45 + 0.35 * nat.state_capacity, 0.15, 0.05, 0.99))
    p.loyalty = clamp01(rng.clamped_gauss(0.62, 0.18, 0.02, 0.99))
    p.health = clamp01(1.05 - p.age / 130 + rng.gauss(0, 0.08))
    p.public_profile = clamp01(rp * rng.uniform(0.4, 1.2))
    p.protection = clamp01(0.08 + rp * 0.85 + rng.gauss(0, 0.08))
    nsec = rng.weighted([0, 1, 2, 3], [0.30, 0.38, 0.22, 0.10])
    for kind, sev, desc in rng.sample(SECRET_KINDS, nsec):
        p.secrets.append({"kind": kind, "severity": sev * rng.uniform(0.6, 1.25),
                          "desc": desc, "known_by": [], "day": 0})
    w.people[pid] = p
    return p


def _role_skills(role: str) -> list[str]:
    m = {
        "head_of_state": ["politics", "oratory", "negotiation"],
        "head_of_government": ["politics", "bureaucracy", "negotiation"],
        "defence_minister": ["command", "strategy", "politics"],
        "finance_minister": ["finance", "accounting", "politics"],
        "foreign_minister": ["diplomacy", "languages", "negotiation"],
        "interior_minister": ["bureaucracy", "intimidation", "politics"],
        "intelligence_chief": ["tradecraft", "surveillance", "interrogation"],
        "central_banker": ["finance", "accounting"],
        "chief_justice": ["law", "bureaucracy"],
        "general": ["command", "strategy", "combat"],
        "admiral": ["command", "logistics", "strategy"],
        "air_marshal": ["command", "engineering"],
        "ceo": ["management", "finance", "negotiation"],
        "banker": ["finance", "accounting", "networking"],
        "industrialist": ["management", "engineering", "trade"],
        "media_baron": ["propaganda", "networking", "finance"],
        "editor": ["propaganda", "surveillance"],
        "cleric": ["theology", "oratory"],
        "professor": ["science", "languages"],
        "scientist": ["science", "engineering"],
        "union_boss": ["oratory", "negotiation", "intimidation"],
        "crime_boss": ["intimidation", "smuggling", "networking"],
        "smuggler": ["smuggling", "logistics"],
        "fixer": ["networking", "deception", "negotiation"],
        "diplomat": ["diplomacy", "languages", "etiquette"],
        "spy": ["tradecraft", "infiltration", "forgery"],
        "activist": ["oratory", "networking"],
        "celebrity": ["arts", "networking"],
        "judge": ["law"], "prosecutor": ["law", "interrogation"],
        "police_chief": ["intimidation", "surveillance"],
        "arms_dealer": ["smuggling", "trade", "negotiation"],
        "lobbyist": ["networking", "negotiation", "politics"],
        "governor": ["politics", "bureaucracy"], "mayor": ["politics", "networking"],
        "legislator": ["politics", "oratory"], "chief_of_staff": ["bureaucracy", "politics"],
    }
    return m.get(role, ["networking"])


def populate_people(w, rng: RNG) -> None:
    for nat in w.nations.values():
        gd = GOV_TYPES[nat.gov]
        hos = make_person(w, rng, nat.id, "head_of_state", age_range=(44, 78), power=None)
        hos.title = {"absolute_monarchy": "Sovereign", "const_monarchy": "Sovereign",
                     "theocratic_state": "Supreme Guide", "military_junta": "Chairman of the Council",
                     "personalist": "President for Life", "one_party_state": "General Secretary",
                     "corporate_state": "Chief Executive of the State",
                     }.get(nat.gov, "President")
        nat.head_of_state = hos.id
        hos.region = w.regions[nat.regions[0]].id if nat.regions else None
        if nat.capital:
            hos.city = nat.capital
        if gd["elections"] and rng.chance(0.55):
            hog = make_person(w, rng, nat.id, "head_of_government", age_range=(42, 72))
            hog.title = "Prime Minister"
            nat.head_of_gov = hog.id
        else:
            nat.head_of_gov = hos.id
        for role in ("defence_minister", "finance_minister", "foreign_minister",
                     "interior_minister", "intelligence_chief", "central_banker",
                     "chief_justice", "chief_of_staff"):
            p = make_person(w, rng, nat.id, role)
            nat.cabinet[role] = p.id
            p.loyalty_to = hos.id
        ngen = clamp(int(2 + 5 * nat.get_policy("military")), 2, 7)
        for _ in range(ngen):
            make_person(w, rng, nat.id, rng.weighted(["general", "admiral", "air_marshal"],
                                                     [3, 1.2 if any(w.regions[r].coastal for r in nat.regions) else 0.1, 1]))
        for role, n in (("legislator", rng.randint(2, 5)), ("governor", min(4, len(nat.regions))),
                        ("ceo", rng.randint(2, 5)), ("banker", rng.randint(1, 3)),
                        ("industrialist", rng.randint(1, 3)), ("media_baron", rng.randint(1, 2)),
                        ("editor", rng.randint(1, 3)), ("cleric", rng.randint(1, 3)),
                        ("scientist", rng.randint(1, 4)), ("professor", rng.randint(1, 3)),
                        ("union_boss", rng.randint(0, 2)), ("crime_boss", rng.randint(0, 2)),
                        ("fixer", rng.randint(1, 3)), ("diplomat", rng.randint(1, 3)),
                        ("spy", rng.randint(1, 3)), ("activist", rng.randint(1, 3)),
                        ("celebrity", rng.randint(1, 3)), ("judge", rng.randint(1, 2)),
                        ("police_chief", rng.randint(1, 2)), ("arms_dealer", rng.randint(0, 1)),
                        ("lobbyist", rng.randint(0, 2)), ("smuggler", rng.randint(0, 2))):
            for _ in range(n):
                make_person(w, rng, nat.id, role, age_range=(28, 70))

    # a sparse acquaintance graph so influence can travel
    people = list(w.people.values())
    by_nation: dict[str, list] = {}
    for p in people:
        by_nation.setdefault(p.nation, []).append(p)
    for p in people:
        peers = by_nation.get(p.nation, [])
        for q in rng.sample(peers, min(len(peers), rng.randint(3, 9))):
            if q.id == p.id:
                continue
            fam = clamp01(rng.beta(2, 3))
            p.knows[q.id] = fam
            q.knows[p.id] = fam * rng.uniform(0.6, 1.0)
        if rng.chance(0.22):
            for q in rng.sample(people, rng.randint(1, 3)):
                if q.nation != p.nation:
                    p.knows[q.id] = clamp01(rng.beta(1.6, 4))


# ===========================================================================
def make_orgs(w, rng: RNG) -> None:
    for nat in w.nations.values():
        cities = w.nation_cities(nat.id)
        cap = nat.capital
        ceos = [p for p in w.people.values() if p.nation == nat.id and p.role in ("ceo", "industrialist")]
        gdp_year = max(nat.gdp * 360, 1e8)

        # corporations, sized by a Pareto share of national output
        ncorp = clamp(int(3 + math.log10(gdp_year) - 8 + rng.randint(0, 4)), 3, 14)
        inds = [i for r in w.nation_regions(nat.id) for i in r.capacity]
        for i in range(ncorp):
            oid = w.nid("O")
            o = Org(oid, N.corp_name(rng, nat.culture), "corp", nat.id)
            o.hq = rng.pick([c.id for c in cities]) if cities else cap
            share = rng.pareto(1.35, 0.012)
            o.revenue = gdp_year * min(0.28, share) / 360.0
            o.profit = o.revenue * rng.clamped_gauss(0.09, 0.06, -0.15, 0.42)
            o.valuation = max(1e6, o.profit * 360 * rng.uniform(8, 26))
            o.cash = o.valuation * rng.uniform(0.03, 0.20)
            o.debt = o.valuation * rng.uniform(0.05, 0.75)
            o.public = rng.chance(0.55 + 0.3 * nat.tech_level)
            o.shares = max(1e6, o.valuation / rng.uniform(12, 260))
            o.share_price = o.valuation / o.shares
            o.headcount = o.revenue * 360 / max(6e4, 3.4e4 * (0.4 + nat.tech_level))
            if inds:
                for ind in rng.sample(inds, min(len(inds), rng.randint(1, 3))):
                    o.industries[ind] = rng.uniform(0.05, 0.55)
            o.influence = clamp01(0.05 + 0.6 * min(1.0, o.revenue * 360 / max(gdp_year, 1)) * 3)
            o.leader = rng.pick(ceos).id if ceos else None
            o.rnd = o.revenue * rng.uniform(0.0, 0.11)
            o.founded = -rng.randint(400, 34000)
            w.orgs[oid] = o
            if o.leader:
                w.people[o.leader].org = oid

        # a central bank and some commercial banks
        for i in range(rng.randint(1, 3)):
            oid = w.nid("O")
            b = Org(oid, f"{nat.name} {rng.pick(['Trust', 'Credit', 'Mercantile Bank', 'Union Bank', 'Commercial Bank'])}",
                    "bank", nat.id)
            b.hq = cap
            b.valuation = gdp_year * rng.uniform(0.01, 0.09)
            b.cash = b.valuation * rng.uniform(0.1, 0.5)
            b.assets["loans"] = gdp_year * rng.uniform(0.05, 0.5)
            b.assets["leverage"] = rng.uniform(6, 22)
            b.influence = clamp01(0.15 + 0.5 * rng.random())
            w.orgs[oid] = b

        # media outlets
        for i in range(rng.randint(2, 5)):
            oid = w.nid("O")
            city = rng.pick(cities).name if cities else nat.name
            m = Org(oid, N.outlet_name(rng, city), "media", nat.id)
            m.hq = cap
            m.reach = clamp01(rng.beta(1.6, 3.4))
            m.ideology = _ideology_vector(rng)
            m.bias = dict(m.ideology)
            m.influence = m.reach
            m.assets["credibility"] = clamp01(rng.clamped_gauss(0.55 + 0.3 * nat.media_freedom, 0.16, 0.05, 0.98))
            m.loyalty = clamp01(1 - nat.media_freedom + rng.gauss(0, 0.15))
            w.orgs[oid] = m

        # intelligence service
        oid = w.nid("O")
        ag = Org(oid, f"{nat.name} {rng.pick(['State Security', 'Directorate of Intelligence', 'External Service', 'Central Bureau'])}",
                 "agency", nat.id)
        ag.hq = cap
        ag.influence = nat.intel_capacity
        ag.secrecy = clamp01(0.6 + 0.35 * nat.repression)
        ag.leader = nat.cabinet.get("intelligence_chief")
        ag.assets["budget"] = gdp_year * nat.get_policy("intel_budget") * 0.004
        w.orgs[oid] = ag
        nat.__dict__["agency"] = oid

        # universities
        for c in cities:
            if c.university and rng.chance(0.6):
                oid = w.nid("O")
                u = Org(oid, f"University of {c.name}", "university", nat.id)
                u.hq = c.id
                u.assets["research"] = rng.uniform(0.2, 1.0) * (0.3 + nat.tech_level)
                u.influence = 0.1 + 0.2 * nat.tech_level
                w.orgs[oid] = u

        # organised crime
        for i in range(rng.weighted([0, 1, 2, 3], [0.25, 0.4, 0.25, 0.10])):
            oid = w.nid("O")
            bosses = [p for p in w.people.values() if p.nation == nat.id and p.role == "crime_boss"]
            s = Org(oid, f"the {N.word(rng, nat.culture, 2, 0.4)} {rng.pick(['Family', 'Combine', 'Brotherhood', 'Ring', 'Cartel', 'Firm'])}",
                    "syndicate", nat.id)
            s.hq = rng.pick([c.id for c in cities]) if cities else cap
            s.secrecy = clamp01(rng.uniform(0.5, 0.95))
            s.leader = rng.pick(bosses).id if bosses else None
            for rk in rng.sample(list(RACKETS), rng.randint(1, 4)):
                s.rackets[rk] = rng.uniform(0.1, 0.8)
            s.revenue = gdp_year * rng.uniform(0.0005, 0.012) / 360
            s.cash = s.revenue * 360 * rng.uniform(0.2, 1.4)
            s.influence = clamp01(0.05 + 0.5 * nat.corruption * rng.random())
            w.orgs[oid] = s

    # faith organisations
    for f in w.faiths.values():
        oid = w.nid("O")
        best = max(w.nations.values(), key=lambda n: n.faiths.get(f.id, 0.0))
        o = Org(oid, f.name, "faith", best.id)
        o.hq = best.capital
        o.reach = clamp01(f.adherents / max(w.global_pop or 9e9, 1) * 6)
        o.doctrine = f.doctrine
        o.ideology = dict(f.ideology)
        o.assets["faith"] = f.id
        clerics = [p for p in w.people.values() if p.nation == best.id and p.role == "cleric"]
        o.leader = clerics[0].id if clerics else None
        f.head = o.leader
        w.orgs[oid] = o


# ===========================================================================
def seed_military(w, rng: RNG) -> None:
    for nat in w.nations.values():
        gdp_year = max(nat.gdp * 360, 1e8)
        budget = gdp_year * nat.get_policy("military") * 0.035
        coastal = any(w.regions[r].coastal for r in nat.regions)
        pool = [u for u, d in UNITS.items()
                if (d["tech"] is None or d["tech"] in nat.techs)
                and (coastal or d["dom"] != "sea")
                and (d["dom"] != "nuclear" or nat.nukes > 0)]
        if not pool:
            pool = ["militia", "infantry"]
        weights = []
        for u in pool:
            d = UNITS[u]
            wgt = {"land": 3.0, "air": 1.4, "sea": 1.1 if coastal else 0.0,
                   "cyber": 0.6, "space": 0.4, "nuclear": 0.35}[d["dom"]]
            wgt *= 1.0 + 1.4 * nat.tech_level if d["cost"] > 5e8 else 1.4 - nat.tech_level
            weights.append(max(0.01, wgt * rng.lognorm(1.0, 0.5)))
        spend = rng.spread(len(pool), budget * 4.5, 1.1)
        for u, amount in zip(pool, spend):
            n = amount / UNITS[u]["cost"]
            if n >= 0.6:
                nat.forces[u] = round(n)
        nat.manpower = sum(UNITS[u]["men"] * n for u, n in nat.forces.items())
        nat.reserves_men = nat.pop * (0.004 + 0.03 * nat.get_policy("conscription"))


# ===========================================================================
def seed_relations(w, rng: RNG) -> None:
    from . import worldmap as WM
    nats = list(w.nations.values())
    planet = w.planet
    pos = {}
    for n in nats:
        rs = [w.regions[r] for r in n.regions]
        pos[n.id] = (mean(r.centroid[0] for r in rs), mean(r.centroid[1] for r in rs))
    adj = w.adjacency
    neighbours: dict[str, set[str]] = {n.id: set() for n in nats}
    for r in w.regions.values():
        for nb in adj[r.id]:
            other = w.regions[nb].nation
            if other != r.nation:
                neighbours[r.nation].add(other)
                neighbours[other].add(r.nation)
    w.neighbours = {k: sorted(v) for k, v in neighbours.items()}

    for i, a in enumerate(nats):
        for b in nats[i + 1:]:
            dx = min(abs(pos[a.id][0] - pos[b.id][0]), planet.w - abs(pos[a.id][0] - pos[b.id][0]))
            dist = math.hypot(dx, pos[a.id][1] - pos[b.id][1]) / planet.w
            idist = ideology_distance(a.ideology, b.ideology)
            same_culture = a.culture == b.culture
            rel = (0.30 - 1.05 * idist + (0.30 if same_culture else 0.0)
                   - 0.55 * max(0.0, 0.22 - dist) / 0.22 * (1.0 if b.id in neighbours[a.id] else 0.0)
                   + rng.gauss(0, 0.20))
            rel = clamp(rel, -1, 1)
            a.relations[b.id] = rel
            b.relations[a.id] = clamp(rel + rng.gauss(0, 0.08), -1, 1)
            if rel > 0.45 and rng.chance(0.42):
                kind = rng.weighted(["trade", "nonaggression", "defence", "alliance", "intel_share"],
                                    [4, 3, 1.4, 0.7, 0.9])
                a.treaties.setdefault(b.id, set()).add(kind)
                b.treaties.setdefault(a.id, set()).add(kind)
            elif rel > 0.10 and rng.chance(0.35):
                a.treaties.setdefault(b.id, set()).add("trade")
                b.treaties.setdefault(a.id, set()).add("trade")
            if rel < -0.55 and rng.chance(0.30):
                a.sanctions.add(b.id)
            # contested border regions become live claims
            if b.id in neighbours[a.id] and rng.chance(0.14):
                border = [r for r in w.regions.values() if r.nation == b.id
                          and any(w.regions[x].nation == a.id for x in adj[r.id])]
                if border:
                    a.claims[rng.pick(border).id] = "irredentist"


def seed_endemics(w, rng: RNG) -> None:
    from .entities import Epidemic
    for dz in ("seasonal_flu", "drug_res_tb", "vector_fever"):
        eid = w.nid("E")
        e = Epidemic(eid, dz, "", 0)
        e.name = DISEASES[dz]["name"]
        for r in w.regions.values():
            if dz == "vector_fever" and abs(r.lat) > 36:
                continue
            if dz == "drug_res_tb" and w.nations[r.nation].tech_level > 0.62 and rng.chance(0.7):
                continue
            frac = rng.uniform(0.00004, 0.0008) * (1.6 - w.nations[r.nation].tech_level)
            e.state[r.id] = {"s": r.pop * (1 - frac), "e": r.pop * frac * 0.3,
                             "i": r.pop * frac, "r": 0.0, "d": 0.0}
        w.epidemics[eid] = e
