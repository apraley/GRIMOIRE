"""Production, consumption, prices, trade, and national accounts.

Design notes
------------
Capacity is measured in jobs.  Gross output *value* per worker is the primitive
(scaled by total factor productivity), and physical quantities fall out of it by
dividing by reference prices.  That keeps GDP-per-capita in a believable band no
matter how the industry mix shakes out, while still letting shortages of a
physical input throttle a physical output.
"""
from __future__ import annotations

import math

from .content_econ import BASKET, GOODS, INDUSTRIES, RESOURCE_GATES
from .content_tech import TECHS
from .util import Counter, clamp, clamp01, lerp, mean

VAL_PER_WORKER = 112.0          # credits of gross output per worker-day at TFP 1
BASE_TFP = 0.015        # subsistence floor: what a worker makes with nothing


def tfp(w, region, industry: str) -> float:
    """Total factor productivity for one industry in one region."""
    nat = w.nations[region.nation]
    d = INDUSTRIES[industry]
    tech = nat.tech_level
    # Productivity is strongly convex in technology, and more so the more
    # sophisticated the process: a poor country can still farm, but it cannot
    # run a fab.  This convexity is what produces a 40x rich/poor spread.
    t = BASE_TFP + 2.0 * (tech ** (1.6 + 1.6 * d["skill"]))
    t *= 0.62 + 0.55 * region.effective_infra()
    t *= (0.70 + 0.55 * region.skill_level()) if d["skill"] > 0.4 else (0.95 + 0.1 * region.education)
    t *= 1.0 - 0.55 * region.devastation
    t *= 0.55 + 0.55 * region.control
    gate = RESOURCE_GATES.get(industry)
    if gate:
        t *= clamp(0.35 + 0.85 * region.resources.get(gate, 0.0), 0.2, 2.4)
    t *= nat.__dict__.get("_tech_quality", 1.0)
    if industry in ("farming", "orchards", "ranching", "plantations"):
        t *= region_climate_factor(w, region)
    return max(0.05, t)


def region_climate_factor(w, region) -> float:
    """Season, drought and heat stress applied to agriculture."""
    season = region.__dict__.get("_season_mod", 1.0)
    return clamp(season, 0.25, 1.6)


def gross_value_per_worker(w, region, industry: str) -> float:
    d = INDUSTRIES[industry]
    cap_intensity = 0.55 + 0.62 * d["capital"]
    return VAL_PER_WORKER * cap_intensity * tfp(w, region, industry)


def refresh_productivity(w, region) -> dict:
    """Recompute and cache value-per-worker for every industry in a region."""
    cache = {i: gross_value_per_worker(w, region, i) for i in region.capacity}
    region.__dict__["_vpw"] = cache
    region.__dict__["_vpw_day"] = w.clock.day
    return cache


def tech_quality(nat) -> float:
    q = 1.0
    for tech_name in nat.techs:
        e = TECHS[tech_name]["e"]
        if "quality" in e:
            q *= 1 + e["quality"] * 0.25
    return q


# ---------------------------------------------------------------- production

def plan_region(w, region) -> dict[str, float]:
    """Unconstrained output each industry in a region would like to make.

    Cached: capacity and productivity only move on the reallocation cadence, so
    recomputing this every day for every region is pure waste.
    """
    d = region.__dict__
    if d.get("_plan") is not None and w.clock.day - d.get("_vpw_day", -99) < 10 \
            and d.get("_plan_n") == len(region.capacity):
        return d["_plan"]
    cache = refresh_productivity(w, region)
    plan = {}
    for ind, jobs in region.capacity.items():
        if jobs <= 0:
            continue
        ref = GOODS[INDUSTRIES[ind]["out"]]["base"]
        plan[ind] = jobs * cache.get(ind, 0.0) / max(ref, 1e-6)
    d["_plan"] = plan
    d["_plan_n"] = len(region.capacity)
    return plan


def cover_target(nat, good: str, daily_use: float) -> float:
    d = GOODS[good]
    days = 12.0 if d["perish"] > 0.02 else 40.0
    days *= 1.0 + 0.9 * d["strat"] + 1.5 * nat.mobilised
    return daily_use * days


def produce_nation(w, nat) -> tuple[Counter, Counter, float, dict]:
    """Run one day of production for a whole nation.

    Two constraints bind.  Inputs are rationed *nationally* before anything is
    made, so a shortage is shared across every plant rather than letting
    whichever region is iterated first drain the stockpile.  And nobody produces
    into a full warehouse: output is capped by the room left under the target
    stock cover, which is what turns weak demand into idle capacity instead of
    an unsellable glut.  Exports drain stock, which reopens room to produce —
    that is how a comparative advantage becomes a trade surplus.
    """
    prices = nat.prices
    stock = nat.stockpile
    regions = [w.regions[r] for r in nat.regions if r in w.regions and w.regions[r].pop > 0]

    plans: list[tuple] = []
    need: dict[str, float] = {}
    planned_out: dict[str, float] = {}
    for r in regions:
        plan = plan_region(w, r)
        plans.append((r, plan))
        for ind, want in plan.items():
            d = INDUSTRIES[ind]
            g = d["out"]
            planned_out[g] = planned_out.get(g, 0.0) + want
            for g2, q in d["inp"].items():
                if g2 in GOODS:
                    need[g2] = need.get(g2, 0.0) + want * q

    prev_demand = nat.demand or {}
    # Snapshot the warehouse BEFORE topping it up from the world market: the
    # glut throttle below must react to organic overproduction, not to imports
    # brought in to cover a *different* shortfall.  Using the post-import level
    # here made every import look like a glut and choked off local production
    # nationwide — a self-reinforcing collapse.
    stock_organic = dict(stock)
    # Before rationing, try to buy the gap on the spot market.  A factory short
    # of copper phones a broker; it does not simply stop.  This is what keeps a
    # local shortfall from cascading into a nationwide production collapse.
    _spot_buy(w, nat, need, stock, planned_out)
    avail = {}
    for g, q in need.items():
        if q <= 1e-9:
            avail[g] = 1.0
            continue
        have = stock.get(g, 0.0)
        # Electricity and other flow goods cannot be warehoused: what is
        # available today is what is generated today.
        if GOODS[g]["perish"] >= 0.5:
            have += planned_out.get(g, 0.0)
        avail[g] = 1.0 if have >= q else have / q

    # how much of each good the country can still absorb today
    room = {}
    for g, made in planned_out.items():
        if made <= 1e-9:
            room[g] = 1.0
            continue
        # Reference the buffer to planned *throughput*, not to realised demand.
        # Keying it to realised demand creates a death spiral: output falls, so
        # demand for inputs falls, so the target falls, so output falls again.
        use = made
        pd = prev_demand.get(g, 0.0)
        if pd > use:
            use = pd
        tgt = cover_target(nat, g, use)
        # Producers fill the warehouse to a comfortable margin above target;
        # exports drain it below, which is what keeps an exporter running flat
        # out rather than idling on a full shelf.  Uses the pre-import level —
        # see stock_organic above.
        space = tgt * 1.40 - stock_organic.get(g, 0.0)
        if space < 0.0:
            space = 0.0
        space += use
        room[g] = 1.0 if space >= made else space / made

    out: dict[str, float] = {}
    used: dict[str, float] = {}
    va = 0.0
    util: dict[str, float] = {}
    jobs_used = 0.0
    jobs_total = 0.0
    for r, plan in plans:
        rout: dict[str, float] = {}
        caps = r.capacity
        for ind, want in plan.items():
            d = INDUSTRIES[ind]
            good = d["out"]
            ratio = room.get(good, 1.0)
            for g in d["inp"]:
                a = avail.get(g, 1.0)
                if a < ratio:
                    ratio = a
            jobs = caps.get(ind, 0.0)
            jobs_total += jobs
            jobs_used += jobs * ratio
            prev = util.get(ind)
            util[ind] = ratio if prev is None or ratio < prev else prev
            made = want * ratio
            if made <= 0:
                continue
            input_val = 0.0
            for g, q in d["inp"].items():
                if g in GOODS:
                    qq = made * q
                    used[g] = used.get(g, 0.0) + qq
                    input_val += qq * GOODS[g]["base"]
            out[good] = out.get(good, 0.0) + made
            rout[good] = rout.get(good, 0.0) + made
            # Value added at *reference* prices: GDP is real output.  Measuring
            # it at spot prices makes a commodity spike look like a boom and a
            # glut look like a depression, which then feeds back into capacity.
            va += made * GOODS[good]["base"] - input_val
            r.pollution = r.pollution * 0.9995 + made * d["dirty"] * 2e-9
        r.output = rout

    # Subsistence floor.  Workers with no functioning industry to work in do
    # not simply vanish: they farm, barter and trade locally.  This is what
    # stops a small economy from spiralling to literally zero output when its
    # import lines fail.
    idle = jobs_total - jobs_used
    if idle > 0:
        arable = mean([r.resources.get("arable", 0.2) for r in regions] or [0.2])
        sub_food = idle * 0.0028 * clamp(0.35 + arable, 0.3, 1.6)
        # subsistence feeds the people who grow it; it does not glut world trade
        gap = max(0.0, prev_demand.get("foodstuffs", 0.0) - out.get("foodstuffs", 0.0)
                  - stock.get("foodstuffs", 0.0))
        sub_food = min(sub_food, gap) if prev_demand else sub_food
        out["foodstuffs"] = out.get("foodstuffs", 0.0) + sub_food
        va += sub_food * GOODS["foodstuffs"]["base"] * 0.85
    nat.__dict__["_utilisation_rate"] = jobs_used / max(jobs_total, 1.0)
    return out, used, va, util


def _spot_buy(w, nat, need: dict, stock: dict, planned_out: dict) -> None:
    """Top up missing production inputs from the world buffer stock."""
    m = w.market
    openness = nat.__dict__.get("_openness", 0.6)
    if openness <= 0.02:
        return
    purse = nat.fx_reserves * 0.10 + max(nat.treasury, 0.0) * 0.03 + nat.gdp * 0.10
    for g, q in need.items():
        if q <= 1e-9:
            continue
        d = GOODS[g]
        if d["perish"] >= 0.5 or d["bulk"] <= 0.0:
            continue
        have = stock.get(g, 0.0)
        if have >= q:
            continue
        world = m.stock.get(g, 0.0)
        if world <= 0.0:
            continue
        price = m.p(g) * (1.0 + d["bulk"] * m.shipping_cost * 0.030) * (1 + nat.get_policy("tariff"))
        buy = min(q - have, world * 0.35, purse / max(price, 1e-6))
        if buy <= 0:
            continue
        cost = buy * price
        purse -= cost
        m.stock[g] = world - buy
        stock[g] = have + buy
        nat.imports[g] = nat.imports.get(g, 0.0) + buy
        nat.trade_balance -= cost
        if cost > nat.fx_reserves:
            nat.debt += cost - nat.fx_reserves
            nat.fx_reserves = 0.0
        else:
            nat.fx_reserves -= cost
        if purse <= 0:
            break


def produce_region(w, region, prices: dict) -> tuple[Counter, Counter, float]:
    """Single-region production (used by world generation for sizing)."""
    out = Counter()
    used = Counter()
    va = 0.0
    for ind, want in plan_region(w, region).items():
        d = INDUSTRIES[ind]
        good = d["out"]
        input_val = sum(want * q * prices.get(g, GOODS[g]["base"])
                        for g, q in d["inp"].items() if g in GOODS)
        for g, q in d["inp"].items():
            if g in GOODS:
                used.add(g, want * q)
        out.add(good, want)
        va += want * prices.get(good, GOODS[good]["base"]) - input_val
    return out, used, va


def consume_region(region) -> Counter:
    """Household demand for one day."""
    want = Counter()
    poor = region.pop * region.wealth.get("poor", 0.4)
    mid = region.pop * region.wealth.get("middle", 0.45)
    rich = region.pop * region.wealth.get("rich", 0.15)
    for g, (a, b, c) in BASKET.items():
        want.add(g, poor * a + mid * b + rich * c)
    return want


# ------------------------------------------------------------------- prices

def clear_prices(nat, market, supply: Counter, demand: Counter, dt: float = 1.0) -> None:
    """Move national prices toward the level that clears local supply/demand."""
    for g, d in GOODS.items():
        s = supply.get(g, 0.0) + max(0.0, nat.stockpile.get(g, 0.0)) * 0.06
        dm = demand.get(g, 0.0)
        if dm <= 0 and s <= 0:
            continue
        gap = (dm - s) / max(dm + s, 1e-6)            # -1 glut .. +1 famine
        elast = d["elast"]
        target = nat.prices.get(g, d["base"]) * (1.0 + clamp(gap / max(elast, 0.15), -1.2, 1.2) * 0.09)
        # arbitrage against the world price, damped by trade friction
        wp = market.p(g)
        openness = clamp01(0.85 - nat.get_policy("tariff") - nat.get_policy("capital_control") * 0.3)
        target = lerp(target, wp * (1 + nat.get_policy("tariff")), 0.22 * openness)
        nat.prices[g] = clamp(lerp(nat.prices.get(g, d["base"]), target, 0.20 * dt),
                              d["base"] * 0.16, d["base"] * 14)


def clear_world_market(w) -> None:
    """Reprice the world market from buffer coverage, not from daily flow.

    Pricing off the instantaneous supply/demand gap makes every price a
    high-frequency oscillator.  Pricing off how many days of cover the global
    warehouse holds gives a slow, stable signal that still responds hard to a
    genuine shortage.
    """
    m = w.market
    for g, d in GOODS.items():
        turnover = m.__dict__.setdefault("turnover", {})
        flow = max(m.demand.get(g, 0.0), m.supply.get(g, 0.0))
        turnover[g] = turnover.get(g, flow) * 0.97 + flow * 0.03
        t = max(turnover[g], 1e-6)
        cover = m.stock.get(g, 0.0) / t
        target = 55.0
        # cheap goods with deep inventories move less than scarce strategic ones
        k = 0.30 + 0.35 * d["strat"]
        want = d["base"] * clamp((target / max(cover, 1.0)) ** k, 0.20, 10.0)
        move = clamp((want - m.price[g]) / max(m.price[g], 1e-6), -0.035, 0.035)
        move += w.market.sentiment * 0.002 * d["elast"]
        m.price[g] = clamp(m.price[g] * (1.0 + move), d["base"] * 0.18, d["base"] * 12)
        m.volatility[g] = m.volatility[g] * 0.97 + abs(move) * 0.03
        m.hist[g].push(m.price[g])
    idx = math.exp(mean([math.log(max(m.price[g] / GOODS[g]["base"], 1e-3))
                         for g in GOODS])) * 100.0
    m.index = idx
    m.index_hist.push(idx)
    m.supply = Counter()
    m.demand = Counter()


# --------------------------------------------------------------------- trade

def trade_friction(w, a, b) -> float:
    """Multiplier on trade volume between two nations (0 = closed)."""
    if a.id == b.id:
        return 1.0
    if b.id in a.at_war or b.id in a.embargoes or a.id in b.embargoes:
        return 0.0
    rel = a.relation(b.id)
    f = 1.0
    f *= clamp01(1.0 - a.get_policy("tariff") * 1.1)
    f *= clamp01(1.0 - b.get_policy("tariff") * 1.1)
    f *= clamp(0.55 + 0.45 * (rel + 1) / 2, 0.15, 1.15)
    if b.id in a.sanctions or a.id in b.sanctions:
        f *= 0.20
    if a.has_treaty(b.id, "trade") or a.has_treaty(b.id, "customs_union"):
        f *= 1.55
    f *= w.trade_openness + 0.25
    return clamp(f, 0.0, 1.8)


def national_accounts(w, nat, va: float, dt: float = 1.0) -> None:
    """Roll value added into GDP, taxes, spending, debt and inflation."""
    nat.gdp_prev = nat.gdp
    nat.gdp = nat.gdp * 0.90 + va * 0.10 if nat.gdp else va
    pol = nat.policy
    gdp_day = max(nat.gdp, 1.0)

    # -- revenue
    compliance = clamp01(0.42 + 0.5 * nat.state_capacity - 0.35 * nat.corruption)
    for t in ("digital_id", "cbdc"):
        if t in nat.techs:
            compliance = clamp01(compliance + TECHS[t]["e"].get("tax_eff", 0) * 0.5)
    rev = gdp_day * compliance * (
        pol["tax_income"] * 0.52 + pol["tax_corporate"] * 0.20
        + pol["tax_consumption"] * 0.40 + pol["tax_wealth"] * 2.2)
    rev += nat.trade_balance * pol["tariff"] * 0.5 if nat.trade_balance < 0 else 0.0
    rev *= (1 - 0.45 * nat.unrest)

    # -- spending
    spend_keys = ("welfare", "healthcare", "education", "infrastructure", "research",
                  "military", "policing", "surveillance", "space_program",
                  "intel_budget", "propaganda", "subsidy_energy", "subsidy_farm")
    spend = gdp_day * sum(pol[k] for k in spend_keys) * 0.0345
    spend *= 1 + 0.25 * nat.corruption
    nat.debt_service = nat.debt * (nat.rate + w.market.credit_spread
                                   + 0.06 * (1 - nat.credit_rating)) / 360.0
    balance = rev - spend - nat.debt_service
    nat.budget_balance = balance
    nat.treasury += balance * dt
    if nat.treasury < 0:
        nat.debt += -nat.treasury
        nat.treasury = 0.0
    elif nat.debt > 0 and nat.treasury > gdp_day * 30:
        pay = min(nat.debt, (nat.treasury - gdp_day * 30) * 0.25)
        nat.debt -= pay
        nat.treasury -= pay

    # -- monetary
    real_rate = nat.rate - nat.inflation
    output_gap = (nat.gdp - nat.gdp_prev) / max(nat.gdp_prev, 1.0)
    money_growth = clamp(min(0.5, nat.debt_service * 360 / gdp_day) * 0.05
                         - clamp(real_rate, -0.15, 0.25) * 0.4, -0.12, 0.35)
    imported = clamp((w.market.index / 100.0 - 1.0) * 0.05, -0.03, 0.09)
    short = nat.__dict__.get("_shortfall", {})
    scarcity = sum(short.values()) / max(len(GOODS), 1)
    target = clamp(0.010 + money_growth * 0.18 + imported
                   + min(0.35, max(0.0, nat.debt_ratio() - 1.6) * 0.04)
                   + nat.unrest * 0.03 + scarcity * 0.30, -0.06, 1.2)
    nat.inflation = lerp(nat.inflation, target, 0.02 * dt)
    nat.growth = lerp(nat.growth, clamp(output_gap * 360, -0.45, 0.45), 0.015 * dt)

    # -- central bank: a Taylor-rule policy rate ---------------------------
    # Without this, the policy rate never moves after world generation, so
    # once inflation ticks above it the real rate goes negative — which
    # itself *feeds* money_growth above — and nothing ever pulls inflation
    # back down.  A rate that leans against inflation and the output gap is
    # what keeps that loop from running away into permanent hyperinflation.
    rate_target = clamp(0.02 + 1.5 * (nat.inflation - 0.02) + 0.5 * clamp(nat.growth, -0.1, 0.1),
                        0.0, 0.60)
    nat.rate = clamp(lerp(nat.rate, rate_target, 0.03 * dt), 0.0, 0.60)

    ratio = nat.debt_ratio()
    nat.credit_rating = clamp01(lerp(nat.credit_rating,
                                     clamp01(1.05 - ratio * 0.42 - nat.inflation * 1.6
                                             - nat.unrest * 0.5 + nat.state_capacity * 0.25),
                                     0.01 * dt))
