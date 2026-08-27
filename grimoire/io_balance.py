"""Input-output balancing.

The industry mix is derived from final demand rather than guessed: household
consumption, investment, government and military demand are propagated back
through the recipe table (a Leontief expansion), which gives the physical output
each good needs.  Jobs are then allocated in proportion to the value of that
output.  Without this, an economy produces mountains of grain and no steel.
"""
from __future__ import annotations

from .content_econ import (BASKET, GOODS, GOV_SHARE, INDUSTRIES, INVEST_SHARE,
                           PROCURE_SHARE, RESEARCH_SHARE, RESOURCE_GATES)
from .util import Counter, clamp, clamp01

# Which industries can supply a given good, and their relative default share.
PRODUCERS: dict[str, list[str]] = {}
for _ind, _d in INDUSTRIES.items():
    PRODUCERS.setdefault(_d["out"], []).append(_ind)

POWER_MIX_DEFAULT = {"power_fossil": 0.58, "power_nuclear": 0.14, "power_solar": 0.16,
                     "power_wind": 0.11, "power_fusion": 0.01}


def final_demand(w, nat) -> Counter:
    """Units per day of each good demanded by households, investment and state.

    The household basket is the anchor; every other component is sized as a
    share of its *value*, so the composition of demand stays realistic (roughly
    55% consumption, 22% investment, 18% government, 5% defence and research)
    without any feedback loop through GDP.
    """
    d = Counter()
    poor = mid = rich = 0.0
    for rid in nat.regions:
        r = w.regions.get(rid)
        if r is None:
            continue
        poor += r.pop * r.wealth.get("poor", 0.4)
        mid += r.pop * r.wealth.get("middle", 0.45)
        rich += r.pop * r.wealth.get("rich", 0.15)
    hh_value = 0.0
    for g, (a, b, c) in BASKET.items():
        q = poor * a + mid * b + rich * c
        d.add(g, q)
        hh_value += q * GOODS[g]["base"]

    def spend(value: float, shares: dict) -> None:
        for good, share in shares.items():
            d.add(good, value * share / GOODS[good]["base"])

    invest = hh_value * clamp(0.34 + clamp(nat.growth, -0.06, 0.10) * 1.8
                              + 0.18 * nat.get_policy("infrastructure")
                              - 0.30 * max(0.0, nat.rate - 0.05), 0.14, 0.72)
    gov = hh_value * clamp(0.10 + 0.42 * (nat.get_policy("welfare")
                                          + nat.get_policy("healthcare")
                                          + nat.get_policy("education")
                                          + nat.get_policy("policing")) / 4.0, 0.05, 0.48)
    mil = hh_value * clamp(0.055 * nat.get_policy("military") / 0.28, 0.0, 0.60) \
        * (1.0 + 4.0 * nat.mobilised)
    res = hh_value * clamp(0.048 * nat.get_policy("research") / 0.30, 0.0, 0.30)
    spend(invest, INVEST_SHARE)
    spend(gov, GOV_SHARE)
    spend(mil, PROCURE_SHARE)
    spend(res, RESEARCH_SHARE)
    nat.__dict__["_hh_value"] = hh_value
    return d


def expand(w, nat, final: Counter, rounds: int = 14) -> Counter:
    """Leontief expansion: add the inputs needed to make the final demand."""
    total = Counter(final)
    wave = Counter(final)
    for _ in range(rounds):
        nxt = Counter()
        for good, qty in wave.items():
            if qty <= 1e-9 or good not in PRODUCERS:
                continue
            inds = PRODUCERS[good]
            share = _producer_shares(nat, good, inds)
            for ind, frac in share.items():
                if frac <= 0:
                    continue
                for g, q in INDUSTRIES[ind]["inp"].items():
                    if g in GOODS:
                        nxt.add(g, qty * frac * q)
        if not nxt or sum(nxt.values()) < sum(final.values()) * 1e-4:
            break
        for g, q in nxt.items():
            total.add(g, q)
        wave = nxt
    return total


def _producer_shares(nat, good: str, inds: list[str]) -> dict[str, float]:
    """Split demand for a good among the industries that can make it."""
    avail = [i for i in inds
             if not INDUSTRIES[i].get("illegal")
             and (INDUSTRIES[i]["tech"] is None or INDUSTRIES[i]["tech"] in nat.techs)]
    if not avail:
        return {}
    if good == "power":
        mix = {i: POWER_MIX_DEFAULT.get(i, 0.05) for i in avail}
        eco = nat.get_policy("environment")
        for i in mix:
            if i in ("power_solar", "power_wind", "power_fusion"):
                mix[i] *= 1 + 2.2 * eco + 1.6 * nat.tech_level
            elif i == "power_fossil":
                mix[i] *= 1 - 0.6 * eco
        tot = sum(mix.values()) or 1.0
        return {i: v / tot for i, v in mix.items()}
    return {i: 1.0 / len(avail) for i in avail}


def required_jobs(w, nat) -> dict[str, float]:
    """Jobs each industry needs to satisfy demand, given current productivity."""
    from . import economy as E
    need = expand(w, nat, final_demand(w, nat))
    regions = [w.regions[r] for r in nat.regions if r in w.regions]
    if not regions:
        return {}
    jobs: dict[str, float] = {}
    market = w.market
    for good, qty in need.items():
        if qty <= 0 or good not in PRODUCERS:
            continue
        # Capital chases price: a good trading well above its reference price
        # pulls capacity toward itself, which is how shortages get answered.
        # use a month's average price, not today's tick, or capacity chases
        # its own tail and the whole sector oscillates
        avg = market.hist[good].avg(90) if market and good in market.hist else GOODS[good]["base"]
        ratio = avg / GOODS[good]["base"]
        pull = clamp(ratio ** 0.35, 0.40, 6.0)
        for ind, frac in _producer_shares(nat, good, PRODUCERS[good]).items():
            value = qty * frac * GOODS[good]["base"] * pull
            # value per worker averaged over the nation's regions
            vpw = sum(E.gross_value_per_worker(w, r, ind) for r in regions) / len(regions)
            jobs[ind] = jobs.get(ind, 0.0) + value / max(vpw, 1e-6)
    return jobs


_NATRES_CACHE: dict[tuple[str, int], float] = {}


def _nation_resource(nat, w, kinds: tuple) -> float:
    """Cached per-nation endowment score for a set of resource kinds, 0..~1+."""
    key = (nat.id, id(nat.regions) if False else len(nat.regions))
    ck = (nat.id, kinds, w.clock.day // 30)
    if ck in _NATRES_CACHE:
        return _NATRES_CACHE[ck]
    if len(_NATRES_CACHE) > 4000:
        _NATRES_CACHE.clear()
    regions = [w.regions[r] for r in nat.regions if r in w.regions]
    if not regions:
        v = 0.0
    else:
        v = sum(sum(r.resources.get(k, 0.0) for k in kinds) for r in regions) / len(regions)
    _NATRES_CACHE[ck] = v
    return v


def region_suitability(w, region, ind: str) -> float:
    """How well a region can host an industry (0 = not at all)."""
    d = INDUSTRIES[ind]
    nat = w.nations[region.nation]
    gate = RESOURCE_GATES.get(ind)
    if gate:
        have = region.resources.get(gate, 0.0)
        if have <= 0.02:
            return 0.0
        base = 0.25 + have * 2.0
    else:
        base = 1.0
    if ind == "power_solar":
        base *= 0.4 + region.resources.get("solar", 0.5)
    if ind == "power_wind":
        base *= 0.4 + region.resources.get("wind", 0.5)
    if ind == "power_fossil":
        # Fuel has to actually be reachable: a fossil plant in a region — or a
        # nation — with no coal or gas access is jobs that never produce.
        fuel = region.resources.get("coal", 0.0) + region.resources.get("gas", 0.0)
        nat_fuel = _nation_resource(nat, w, ("coal", "gas"))
        base *= clamp01(0.15 + fuel * 1.4 + nat_fuel * 2.0)
    if ind == "power_nuclear":
        ur = region.resources.get("uranium", 0.0)
        nat_ur = _nation_resource(nat, w, ("uranium",))
        base *= clamp01(0.10 + ur * 1.2 + nat_ur * 3.0)
    if ind == "refining":
        oil = region.resources.get("oil", 0.0)
        nat_oil = _nation_resource(nat, w, ("oil",))
        base *= clamp01(0.15 + oil * 1.4 + nat_oil * 2.0)
    if ind in ("shipyards", "fishing") and not region.coastal:
        return 0.0
    fit = 1.0 - clamp01(abs(d["skill"] - region.skill_level()) * 1.15)
    urban = 1.0 + 0.6 * (region.urban - 0.5) * (1 if d["land"] < 0.4 else -1)
    infra = 0.45 + 0.75 * region.effective_infra()
    return max(0.0, base * fit * urban * infra * region.workforce())


def allocate(w, nat, rng=None, blend: float = 1.0) -> None:
    """Distribute the nation's required jobs across its regions.

    Jobs are first apportioned from the demand vector, then *corrected*: the
    output those jobs would actually produce (at each region's own productivity)
    is compared against what was required, and the allocation is rescaled.
    Without that correction, jobs land in regions whose productivity differs
    from the national average and the economy chronically over- or under-makes
    whole categories of goods, which shows up as prices pinned at their bounds.
    """
    from . import economy as E
    need = expand(w, nat, final_demand(w, nat))
    regions = [w.regions[r] for r in nat.regions if r in w.regions]
    if not regions:
        return
    workforce = sum(r.workforce() for r in regions)
    if workforce <= 0:
        return

    # required physical output per industry
    want_units: dict[str, float] = {}
    market = w.market
    for good, qty in need.items():
        if qty <= 0 or good not in PRODUCERS:
            continue
        avg = market.hist[good].avg(90) if good in market.hist else GOODS[good]["base"]
        # Capital must be able to chase a real price signal hard: a good
        # persistently trading at several times its reference price means the
        # world needs several times more capacity making it, not a fractional
        # nudge.  The old 1.8x ceiling here left genuinely scarce goods (coffee,
        # semis, uranium) stuck at a fraction of required output indefinitely,
        # which is what fed the runaway scarcity -> inflation -> unrest chain.
        pull = clamp((avg / GOODS[good]["base"]) ** 0.35, 0.40, 6.0)
        for ind, frac in _producer_shares(nat, good, PRODUCERS[good]).items():
            want_units[ind] = want_units.get(ind, 0.0) + qty * frac * pull
    if not want_units:
        return

    # per-region output per job, and the share of each industry each region gets
    suit: dict[str, list] = {}
    vpw: dict[tuple[str, str], float] = {}
    unhostable = 0.0
    for ind in list(want_units):
        pairs = []
        for r in regions:
            s = region_suitability(w, r, ind)
            if s > 0:
                pairs.append((r, s))
                vpw[(r.id, ind)] = E.gross_value_per_worker(w, r, ind) \
                    / max(GOODS[INDUSTRIES[ind]["out"]]["base"], 1e-6)
        if not pairs:
            unhostable += want_units.pop(ind)
            continue
        suit[ind] = pairs

    if not suit:
        return
    if unhostable > 0:
        # workers of impossible industries go into what the country *is* good at
        boost = 1.0 + min(3.0, unhostable / max(sum(want_units.values()), 1e-6))
        for ind in want_units:
            want_units[ind] *= boost

    # jobs needed for the wanted output, given real regional productivity
    def jobs_for(units: dict[str, float]) -> dict[str, dict[str, float]]:
        caps: dict[str, dict[str, float]] = {r.id: {} for r in regions}
        for ind, u in units.items():
            pairs = suit[ind]
            tot = sum(x for _r, x in pairs)
            for r, x in pairs:
                share = u * x / tot
                per_job = vpw.get((r.id, ind), 0.0)
                if per_job <= 1e-9:
                    continue
                caps[r.id][ind] = caps[r.id].get(ind, 0.0) + share / per_job
        return caps

    caps = jobs_for(want_units)
    total_jobs = sum(sum(c.values()) for c in caps.values())
    if total_jobs <= 0:
        return
    scale = clamp(workforce * 0.965 / total_jobs, 0.40, 3.2)
    prev = getattr(nat, "demand_scale", None)
    nat.demand_scale = scale if prev is None else prev + (scale - prev) * 0.05
    for cid in caps:
        for k in caps[cid]:
            caps[cid][k] *= scale

    for r in regions:
        fresh = {k: v for k, v in caps[r.id].items() if v > 20}
        if not fresh:
            fresh = {"farming": r.workforce() * 0.4}
        if blend >= 1.0:
            r.capacity = fresh
        else:
            merged = dict(r.capacity)
            for k in set(merged) | set(fresh):
                merged[k] = merged.get(k, 0.0) * (1 - blend) + fresh.get(k, 0.0) * blend
            r.capacity = {k: v for k, v in merged.items() if v > 20}
        r.__dict__["_plan"] = None
