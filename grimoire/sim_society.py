"""Population, health, education, migration, information and faith."""
from __future__ import annotations

import math

from .content_conflict import DISEASES, NARRATIVE_KINDS
from .content_social import AUDIENCES, AXES, IDEOLOGIES
from .content_tech import TECHS
from .entities import Epidemic, Narrative
from .util import Counter, clamp, clamp01, lerp, mean

DAY_YEAR = 360.0


# ===========================================================================
def tick_population(w) -> None:
    """Births, deaths, ageing and the slow drift of the demographic pyramid."""
    rng = w.rng.sub("pop")
    for nat in w.living_nations():
        dev = nat.tech_level
        health_policy = nat.get_policy("healthcare")
        med = 1.0
        for t in nat.techs:
            med += TECHS[t]["e"].get("med", 0.0) * 0.5
        life_target = clamp(46 + 34 * dev + 9 * health_policy + 4 * (med - 1)
                            + sum(TECHS[t]["e"].get("lifespan", 0) for t in nat.techs) * 0.5,
                            38, 108)
        nat.life_expectancy = lerp(nat.life_expectancy, life_target, 0.0016)

        total_born = total_died = 0.0
        for rid in nat.regions:
            r = w.regions.get(rid)
            if r is None or r.pop <= 0:
                continue
            # fertility falls with income, education and urbanisation
            tfr = clamp(6.4 - 3.4 * dev - 1.9 * r.education - 1.1 * r.urban
                        + 0.8 * (1 - r.health), 0.85, 7.2)
            tfr *= 1.0 - 0.35 * r.devastation - 0.25 * r.insurgency
            women = r.pop * r.age.get("25-44", 0.28) * 0.49
            births = women * tfr / (20 * DAY_YEAR)
            # crude death rate is 1/life-expectancy only for a stationary
            # population; a young pyramid dies far more slowly than that
            age_factor = clamp(0.42 + 2.0 * r.age.get("65+", 0.10), 0.35, 1.6)
            base_death = (age_factor / (nat.life_expectancy * DAY_YEAR)) * r.pop
            base_death *= clamp(1.55 - 0.75 * r.health, 0.62, 2.2)
            base_death *= 1.0 + 2.4 * r.devastation + 1.1 * r.insurgency
            deaths = base_death
            r.pop = max(0.0, r.pop + births - deaths)
            total_born += births
            total_died += deaths
            # ageing: shift mass between bands
            a = r.age
            flow = 1.0 / (15 * DAY_YEAR)
            u = a.get("0-14", 0.2) * flow
            a["0-14"] = a.get("0-14", 0.2) - u + births / max(r.pop, 1)
            a["15-24"] = a.get("15-24", 0.15) + u - a.get("15-24", 0.15) / (10 * DAY_YEAR)
            a["25-44"] = a.get("25-44", 0.28) + a.get("15-24", 0.15) / (10 * DAY_YEAR) \
                - a.get("25-44", 0.28) / (20 * DAY_YEAR)
            a["45-64"] = a.get("45-64", 0.22) + a.get("25-44", 0.28) / (20 * DAY_YEAR) \
                - a.get("45-64", 0.22) / (20 * DAY_YEAR)
            a["65+"] = a.get("65+", 0.12) + a.get("45-64", 0.22) / (20 * DAY_YEAR) \
                - deaths / max(r.pop, 1) * 0.72
            tot = sum(max(0.0, v) for v in a.values()) or 1.0
            for k in a:
                a[k] = max(0.0, a[k]) / tot
            # urbanisation and education creep
            r.urban = clamp01(r.urban + (clamp01(0.20 + 0.72 * dev) - r.urban) * 0.0006)
            edu_t = clamp01(0.12 + 0.72 * nat.get_policy("education") + 0.32 * dev)
            r.education = clamp01(r.education + (edu_t - r.education) * 0.0007)
            r.literacy = clamp01(r.literacy + (clamp01(0.3 + 0.7 * r.education) - r.literacy) * 0.001)
            h_t = clamp01(0.14 + 0.52 * health_policy + 0.42 * dev - 0.4 * r.devastation)
            r.health = clamp01(r.health + (h_t - r.health) * 0.0016)
        nat.pop = sum(w.regions[r].pop for r in nat.regions if r in w.regions)
        nat.birth_rate = total_born * DAY_YEAR / max(nat.pop, 1)
        nat.death_rate = total_died * DAY_YEAR / max(nat.pop, 1)
        nat.hdi = clamp01(0.34 * clamp01((nat.life_expectancy - 40) / 55)
                          + 0.33 * mean([w.regions[r].education for r in nat.regions
                                         if r in w.regions] or [0.3])
                          + 0.33 * clamp01(math.log10(max(nat.gdp_per_capita(), 100)) / 5.2))


def tick_migration(w) -> None:
    """People move toward safety, work and money."""
    rng = w.rng.sub("migration")
    if w.clock.day % 7:
        return
    regions = list(w.regions.values())
    if len(regions) < 2:
        return

    def attract(r):
        nat = w.nations.get(r.nation)
        if nat is None or not nat.alive:
            return 0.01
        return max(0.01, (0.8 + 2.4 * math.log10(max(nat.gdp_per_capita(), 60)) / 5
                          - 2.2 * r.unrest - 3.0 * r.devastation - 2.4 * r.insurgency
                          + 1.1 * r.employment + 0.8 * nat.get_policy("welfare")))

    scores = {r.id: attract(r) for r in regions}
    for r in rng.sample(regions, min(len(regions), 60)):
        nat = w.nations.get(r.nation)
        push = clamp01(r.unrest * 0.8 + r.devastation * 1.6 + r.insurgency * 1.2
                       + (1 - r.employment) * 0.5)
        if push < 0.05:
            continue
        movers = r.pop * push * 0.00045
        if movers < 10:
            continue
        cands = w.adjacency.get(r.id, set()) | {rng.pick(regions).id for _ in range(3)}
        cands = [c for c in cands if c in w.regions and c != r.id]
        if not cands:
            continue
        best = max(cands, key=lambda c: scores.get(c, 0.0))
        dest = w.regions[best]
        dnat = w.nations.get(dest.nation)
        if scores.get(best, 0) <= scores[r.id] * 1.05:
            continue
        if dnat and dnat.id != nat.id:
            movers *= clamp01(dnat.get_policy("immigration") * 1.3)
            if dnat.id in nat.at_war:
                movers = 0.0
        if movers < 5:
            continue
        r.pop -= movers
        dest.pop += movers
        if dnat and nat and dnat.id != nat.id:
            dnat.migration += movers
            nat.migration -= movers
            # cultural friction in the receiving region
            src = r.culture
            share = movers / max(dest.pop, 1)
            dest.cultures[src] = dest.cultures.get(src, 0.0) + share
            tot = sum(dest.cultures.values()) or 1.0
            dest.cultures = {k: v / tot for k, v in dest.cultures.items()}
            if dnat.get_policy("immigration") < 0.35:
                dest.unrest = clamp01(dest.unrest + share * 0.35)


# ===========================================================================
def tick_health(w) -> None:
    """SEIR dynamics for every active epidemic, plus endemic burden."""
    rng = w.rng.sub("health")
    for e in list(w.epidemics.values()):
        if e.ended is not None:
            continue
        d = DISEASES[e.disease]
        active = 0.0
        newly = 0.0
        dead = 0.0
        for rid, st in list(e.state.items()):
            r = w.regions.get(rid)
            if r is None or r.pop <= 0:
                continue
            nat = w.nations.get(r.nation)
            if nat is None:
                continue
            n = max(st["s"] + st["e"] + st["i"] + st["r"], 1.0)
            seasonal = 1.0 + d["season"] * math.cos(
                2 * math.pi * (w.clock.doy / 360.0) + (math.pi if r.lat < 0 else 0.0))
            control = clamp01(0.55 * nat.get_policy("healthcare") + 0.30 * nat.state_capacity
                              + 0.35 * r.health + 0.4 * e.vaccine)
            for t in nat.techs:
                control = clamp01(control + TECHS[t]["e"].get("epidemic_res", 0.0) * 0.4)
            crowd = 0.7 + 0.9 * r.urban
            beta = d["r0"] / d["dur"] * seasonal * crowd * e.r0_mod * (1 - control * 0.72)
            new_e = beta * st["s"] * st["i"] / n
            new_i = st["e"] / max(d["incub"], 1)
            leave = st["i"] / max(d["dur"], 1)
            cfr = d["cfr"] * clamp(1.7 - 0.9 * r.health - 0.5 * nat.get_policy("healthcare"), 0.15, 2.4)
            died = leave * cfr
            st["s"] = max(0.0, st["s"] - new_e)
            st["e"] = max(0.0, st["e"] + new_e - new_i)
            st["i"] = max(0.0, st["i"] + new_i - leave)
            st["r"] += leave - died
            st["d"] += died
            r.pop = max(0.0, r.pop - died)
            active += st["i"]
            newly += new_i
            dead += died
            if st["i"] / max(r.pop, 1) > 0.012:
                r.unrest = clamp01(r.unrest + 0.0022)
                r.employment = clamp01(r.employment - 0.0015)
        e.total_dead += dead
        e.total_cases += newly
        if active < 40 and e.total_cases > 0:
            e.ended = w.clock.day
            if e.total_dead > 5e4:
                w.report(f"The {e.name} outbreak is declared over after "
                         f"{(w.clock.day - e.started) // 30} months and "
                         f"{e.total_dead / 1e3:,.0f} thousand deaths.", "health", weight=0.75)
        # vaccine development
        if e.total_cases > 2e5 and e.vaccine < 1.0:
            best = max((w.nations[n].tech_level for n in w.great_powers if n in w.nations),
                       default=0.4)
            speed = 0.0016 * (0.4 + best)
            for n in w.great_powers:
                nat = w.nations.get(n)
                if nat and "mrna_platform" in nat.techs:
                    speed *= 1.5
                    break
            e.vaccine = clamp01(e.vaccine + speed)


def maybe_outbreak(w) -> None:
    rng = w.rng.sub("outbreak")
    if not rng.chance(0.0016 + 0.0009 * w.doomsday):
        return
    dz = rng.weighted(list(DISEASES), [1.4, 1.0, 0.8, 0.35, 0.7, 0.5, 0.3, 0.6, 0.05, 0.12])
    regions = [r for r in w.regions.values() if r.pop > 1e5]
    if not regions:
        return
    origin = rng.weighted(regions, [r.pop * (1.4 - w.nations[r.nation].tech_level) for r in regions])
    eid = w.nid("E")
    e = Epidemic(eid, dz, origin.id, w.clock.day)
    e.name = DISEASES[dz]["name"]
    e.state[origin.id] = {"s": origin.pop - 200, "e": 150.0, "i": 50.0, "r": 0.0, "d": 0.0}
    w.epidemics[eid] = e
    w.report(f"Health authorities in {origin.name} report a cluster of "
             f"{DISEASES[dz]['name'].lower()} cases.", "health", scope=origin.nation, weight=0.6)


def spread_epidemics(w) -> None:
    """Seed new regions from infected ones along travel links."""
    rng = w.rng.sub("spread")
    for e in w.epidemics.values():
        if e.ended is not None:
            continue
        seeded = [rid for rid, st in e.state.items() if st["i"] > 60]
        if not seeded:
            continue
        for rid in rng.sample(seeded, min(4, len(seeded))):
            r = w.regions.get(rid)
            if r is None:
                continue
            nat = w.nations.get(r.nation)
            links = list(w.adjacency.get(rid, set()))
            # air travel jumps borders in proportion to development
            if nat and rng.chance(0.35 * nat.tech_level):
                links += [rng.pick(list(w.regions)) for _ in range(2)]
            for target in rng.sample(links, min(2, len(links))):
                if target in e.state or target not in w.regions:
                    continue
                tr = w.regions[target]
                tn = w.nations.get(tr.nation)
                if tn is None:
                    continue
                barrier = clamp01(tn.state_capacity * 0.5 + tn.get_policy("healthcare") * 0.3)
                if rng.chance(0.30 * (1 - barrier)):
                    e.state[target] = {"s": tr.pop - 30, "e": 20.0, "i": 10.0, "r": 0.0, "d": 0.0}


# ===========================================================================
def add_narrative(w, kind: str, text: str, subject: str = "", origin: str | None = None,
                  truth: bool = True, credibility: float = 0.6, seed_nation: str | None = None,
                  seed: float = 0.05, targets_player: bool = False) -> Narrative:
    nid = w.nid("Z")
    n = Narrative(nid, kind, text, subject, w.clock.day)
    n.valence = NARRATIVE_KINDS[kind]["valence"]
    n.credibility = credibility
    n.origin = origin
    n.truth = truth
    n.targets_player = targets_player
    if seed_nation:
        n.salience[seed_nation] = seed
    else:
        for g in w.great_powers[:3]:
            n.salience[g] = seed * 0.4
    w.narratives[nid] = n
    return n


def tick_information(w) -> None:
    """Narratives spread, decay, and move public opinion."""
    rng = w.rng.sub("info")
    dead = []
    for n in w.narratives.values():
        k = NARRATIVE_KINDS[n.kind]
        peak = 0.0
        for nid in list(n.salience):
            nat = w.nations.get(nid)
            if nat is None or not nat.alive:
                continue
            s = n.salience[nid]
            connectivity = clamp01(0.20 + 0.75 * nat.tech_level)
            openness = clamp01(nat.media_freedom * 0.7 + 0.3)
            censor = nat.get_policy("censorship") * nat.state_capacity
            growth = k["virality"] * connectivity * openness * n.credibility * (1 - s)
            growth *= 1.0 - clamp01(censor * 1.1) - n.suppressed
            s = clamp01(s + growth * 0.11 - s * k["decay"])
            n.salience[nid] = s
            peak = max(peak, s)
            if s > 0.02:
                _apply_opinion(w, nat, n, s)
            # jump borders
            if s > 0.25 and rng.chance(0.05):
                for other in rng.sample(list(w.nations), 2):
                    if other not in n.salience:
                        rel = abs(nat.relation(other))
                        n.salience[other] = 0.01 * (0.5 + rel)
        n.suppressed = max(0.0, n.suppressed - 0.02)
        if peak < 0.004 and w.clock.day - n.created > 30:
            dead.append(n.id)
    for nid in dead:
        del w.narratives[nid]


def _apply_opinion(w, nat, n, s: float) -> None:
    k = NARRATIVE_KINDS[n.kind]
    push = s * 0.010 * k["virality"]
    if n.kind in ("scandal", "conspiracy", "ridicule"):
        nat.approval = clamp01(nat.approval - push * 0.6)
        nat.legitimacy = clamp01(nat.legitimacy - push * 0.30)
    elif n.kind in ("grievance", "panic"):
        nat.unrest = clamp01(nat.unrest + push * 0.55)
    elif n.kind in ("threat",):
        nat.opinion["military"] = clamp(nat.opinion.get("military", 0) + push, -1, 1)
        nat.ideology["milit"] = clamp(nat.ideology["milit"] + push * 0.25, -1, 1)
        nat.ideology["nation"] = clamp(nat.ideology["nation"] + push * 0.20, -1, 1)
    elif n.kind in ("hero", "triumph", "hope"):
        nat.approval = clamp01(nat.approval + push * 0.45)
        nat.legitimacy = clamp01(nat.legitimacy + push * 0.20)
    elif n.kind == "martyrdom":
        nat.unrest = clamp01(nat.unrest + push * 0.75)
        nat.legitimacy = clamp01(nat.legitimacy - push * 0.35)
    elif n.kind == "doctrine":
        for i, ax in enumerate(AXES):
            tgt = n.audiences.get(ax, 0.0)
            nat.ideology[ax] = clamp(nat.ideology[ax] + (tgt - nat.ideology[ax]) * push * 0.4, -1, 1)
    # subjects of a story take the reputational hit or lift
    if n.subject and n.subject in w.people:
        p = w.people[n.subject]
        p.public_profile = clamp01(p.public_profile + s * 0.004)
        if k["valence"] < 0:
            p.power = clamp01(p.power - s * 0.0016)


def tick_media(w) -> None:
    """Outlets drift with their owners, their audience and state pressure."""
    rng = w.rng.sub("media")
    if w.clock.day % 3:
        return
    for o in w.orgs.values():
        if o.kind != "media" or not o.alive:
            continue
        nat = w.nations.get(o.nation)
        if nat is None:
            continue
        pressure = nat.get_policy("censorship") * nat.state_capacity
        o.loyalty = clamp01(lerp(o.loyalty, clamp01(pressure * 1.3), 0.02))
        drift = 0.006
        for ax in AXES:
            o.bias[ax] = clamp(lerp(o.bias.get(ax, 0.0), nat.ideology[ax],
                                    drift * (0.4 + o.loyalty)), -1, 1)
        o.reach = clamp01(o.reach + rng.gauss(0, 0.004)
                          + (0.002 if nat.media_freedom > 0.5 else -0.001))
        o.assets["credibility"] = clamp01(o.assets.get("credibility", 0.5)
                                          + (nat.media_freedom - o.loyalty) * 0.002)
    for nat in w.living_nations():
        outlets = [o for o in w.orgs.values() if o.kind == "media" and o.nation == nat.id and o.alive]
        if outlets:
            nat.media_freedom = clamp01(lerp(nat.media_freedom,
                                             1 - nat.get_policy("censorship") * nat.state_capacity,
                                             0.01))


# ===========================================================================
def tick_faith(w) -> None:
    """Religious adherence shifts with prosperity, crisis and militancy."""
    if w.clock.day % 5:
        return
    rng = w.rng.sub("faith")
    for r in rng.sample(list(w.regions.values()), min(70, len(w.regions))):
        nat = w.nations.get(r.nation)
        if nat is None or not r.faiths:
            continue
        crisis = clamp01(r.unrest + r.devastation + (1 - r.health) * 0.4
                         + nat.unemployment * 0.5)
        modern = clamp01(0.3 * nat.tech_level + 0.5 * r.education + 0.2 * r.urban)
        for fid in list(r.faiths):
            if fid == "secular":
                delta = (modern * 0.0022 - crisis * 0.0026)
            else:
                f = w.faiths.get(fid)
                if f is None:
                    continue
                spread = 0.7
                from .content_conflict import FAITH_DOCTRINES
                spread = FAITH_DOCTRINES.get(f.doctrine, {}).get("spread", 1.0)
                delta = (crisis * 0.0021 * spread - modern * 0.0018)
                if nat.gov == "theocratic_state" and nat.faiths.get(fid, 0) > 0.3:
                    delta += 0.0016
            r.faiths[fid] = clamp01(r.faiths[fid] + delta)
        tot = sum(r.faiths.values()) or 1.0
        r.faiths = {k: v / tot for k, v in r.faiths.items()}
    if w.clock.day % 30 == 0:
        for f in w.faiths.values():
            f.adherents = sum(r.pop * r.faiths.get(f.id, 0.0) for r in w.regions.values())
        for nat in w.living_nations():
            agg = Counter()
            for rid in nat.regions:
                r = w.regions.get(rid)
                if r is None:
                    continue
                for k, v in r.faiths.items():
                    agg.add(k, v * r.pop)
            nat.faiths = agg.normalized()


def tick_culture(w) -> None:
    """Soft power: who the world watches, listens to and imitates."""
    if w.clock.day % 10:
        return
    for nat in w.living_nations():
        media_out = sum(r.output.get("media", 0.0) for r in w.nation_regions(nat.id))
        wealth = math.log10(max(nat.gdp_per_capita(), 100)) / 5.0
        target = clamp01(0.28 * wealth + 0.30 * clamp01(media_out / max(w.global_gdp * 1e-6, 1))
                         + 0.18 * nat.media_freedom + 0.14 * nat.prestige
                         - 0.20 * nat.repression)
        nat.soft_power = clamp01(lerp(nat.soft_power, target, 0.02))
