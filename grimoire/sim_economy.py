"""Daily economic simulation: production, consumption, trade, finance, firms."""
from __future__ import annotations

import math

from . import economy as E
from . import io_balance as IO
from .content_econ import GOODS, INDUSTRIES, RESOURCE_GATES
from .content_tech import TECHS
from .util import Counter, clamp, clamp01, lerp, mean

GOOD_KEYS = list(GOODS)


def season_modifier(w, region) -> float:
    """Agricultural output swings with the season and the weather."""
    if abs(region.lat) < 22:
        base = 1.05
    else:
        base = {"Spring": 0.88, "Summer": 1.34, "Autumn": 1.28, "Winter": 0.46}[
            w.clock.season(region.lat)]
    return base * region.__dict__.get("_weather", 1.0)


# ===========================================================================
def tick_economy(w) -> None:
    market = w.market
    market.supply = Counter()
    market.demand = Counter()

    for nat in w.living_nations():
        nat.__dict__["_tech_quality"] = E.tech_quality(nat)
        supply = Counter()
        demand = Counter()
        va = 0.0
        stock = nat.stockpile

        # ---- production --------------------------------------------------
        for rid in nat.regions:
            r = w.regions.get(rid)
            if r is not None:
                r.__dict__["_season_mod"] = season_modifier(w, r)
        out, used, va, util = E.produce_nation(w, nat)
        nat.__dict__["_utilisation"] = util
        for g, q in out.items():
            supply[g] = supply.get(g, 0.0) + q
            stock[g] = stock.get(g, 0.0) + q
        for g, q in used.items():
            demand[g] = demand.get(g, 0.0) + q
            v = stock.get(g, 0.0) - q
            stock[g] = v if v > 0.0 else 0.0

        # ---- consumption: households, investment, the state, the army ----
        scale = getattr(nat, "demand_scale", 1.0)
        want = IO.final_demand(w, nat)
        shortfall: dict[str, float] = {}
        for g, q in want.items():
            q *= scale
            if q <= 0:
                continue
            demand.add(g, q)
            have = stock.get(g, 0.0)
            got = min(have, q)
            stock[g] = have - got
            if got < q * 0.94 and g in IO.PRODUCERS:
                shortfall[g] = 1 - got / max(q, 1e-9)
        nat.__dict__["_shortfall"] = shortfall

        # wartime burn on top of peacetime procurement
        if nat.at_war and nat.forces:
            from .content_conflict import UNITS
            burn = sum(UNITS[u]["supply"] * n for u, n in nat.forces.items()) * 16.0
            for g, frac in (("fuel", 0.42), ("munitions", 0.38), ("foodstuffs", 0.20)):
                q = burn * frac
                demand.add(g, q)
                got = min(stock.get(g, 0.0), q)
                stock[g] = stock.get(g, 0.0) - got
                if got < q * 0.8:
                    nat.readiness = clamp01(nat.readiness - 0.004)
                    nat.morale = clamp01(nat.morale - 0.002)

        # scarcity of essentials is felt directly by the population
        if shortfall:
            food = max(shortfall.get("foodstuffs", 0.0), shortfall.get("produce", 0.0) * 0.5)
            energy = max(shortfall.get("power", 0.0), shortfall.get("fuel", 0.0) * 0.8)
            med = shortfall.get("pharma", 0.0)
            if food > 0.02 or energy > 0.02 or med > 0.05:
                for rid in nat.regions:
                    r = w.regions.get(rid)
                    if r is None:
                        continue
                    r.unrest = clamp01(r.unrest + food * 0.010 + energy * 0.005)
                    r.health = clamp01(r.health - food * 0.0026 - med * 0.0010)

        # ---- decay, prices, accounts -------------------------------------
        for g, d in GOODS.items():
            p = d["perish"]
            if p > 0:
                stock[g] = stock.get(g, 0.0) * (1 - p)
        nat.supply = dict(supply)
        nat.demand = dict(demand)
        E.clear_prices(nat, market, supply, demand)
        E.national_accounts(w, nat, va)

    tick_trade(w)
    E.clear_world_market(w)


# ===========================================================================
def tick_trade(w) -> None:
    """A world warehouse.

    Nations deposit whatever they hold above their cover target and draw on the
    warehouse for whatever they hold below it.  The buffer is what lets a
    comparative advantage in one hemisphere feed a shortage in the other without
    the two having to want the trade on the same day.
    """
    market = w.market
    nats = w.living_nations()
    if len(nats) < 2:
        return
    stockpile = market.stock

    for nat in nats:
        blockade = nat.__dict__.get("_blockade", 0.0)
        openness = clamp01((1.0 - nat.get_policy("tariff") * 0.8)
                           * (1.0 - nat.get_policy("capital_control") * 0.35)
                           * (1.0 - blockade) * (w.trade_openness + 0.30))
        if nat.at_war:
            openness *= 0.72
        sanctioned_by = sum(1 for o in nats if nat.id in o.sanctions)
        openness *= clamp01(1.0 - 0.09 * sanctioned_by)
        nat.__dict__["_openness"] = openness
        if openness <= 0.01:
            continue

        purse = nat.fx_reserves * 0.09 + max(nat.treasury, 0.0) * 0.03
        for g in GOOD_KEYS:
            d = GOODS[g]
            if d["perish"] >= 0.9 or d["bulk"] <= 0.0:
                continue
            use = nat.demand.get(g, 0.0)
            if use <= 0:
                continue
            target = E.cover_target(nat, g, use)
            have = nat.stockpile.get(g, 0.0)
            price = market.p(g)
            if have > target * 1.02:
                qty = (have - target * 0.92) * 0.26 * openness
                if qty <= 0:
                    continue
                nat.stockpile[g] = have - qty
                stockpile[g] = stockpile.get(g, 0.0) + qty
                take = qty * price
                nat.fx_reserves += take
                nat.exports[g] = nat.exports.get(g, 0.0) + qty
                nat.trade_balance += take
                market.supply[g] = market.supply.get(g, 0.0) + qty
            elif have < target * 0.90:
                want = (target - have) * 0.34 * openness
                market.demand[g] = market.demand.get(g, 0.0) + want
                pot = purse
                if d["strat"] > 0.6 or g in ("foodstuffs", "pharma", "produce", "fuel"):
                    headroom = max(0.0, 2.6 - nat.debt_ratio()) * nat.credit_rating
                    pot += nat.gdp * 0.06 * headroom
                ship = 1.0 + d["bulk"] * market.shipping_cost * 0.030
                unit = price * ship
                qty = min(want, stockpile.get(g, 0.0) * 0.40, pot / max(unit, 1e-6))
                if qty <= 0:
                    continue
                stockpile[g] = stockpile.get(g, 0.0) - qty
                nat.stockpile[g] = have + qty
                pay = qty * unit
                purse = max(0.0, purse - pay)
                if pay > nat.fx_reserves:
                    nat.debt += pay - nat.fx_reserves
                    nat.fx_reserves = 0.0
                else:
                    nat.fx_reserves -= pay
                nat.imports[g] = nat.imports.get(g, 0.0) + qty
                nat.trade_balance -= pay
                nat.treasury += qty * price * nat.get_policy("tariff")

    w.flags["trade_volume"] = sum(market.supply.get(g, 0.0) * market.p(g) for g in GOOD_KEYS)
    for nat in nats:
        nat.trade_balance *= 0.98
    for g, d in GOODS.items():
        if d["perish"] > 0:
            stockpile[g] = stockpile.get(g, 0.0) * (1 - d["perish"] * 0.5)


# ===========================================================================
def tick_firms(w) -> None:
    """Corporate revenues, profits, valuations and share prices."""
    rng = w.rng.sub("firms")
    m = w.market
    for o in w.orgs.values():
        if not o.alive or o.kind not in ("corp", "bank", "syndicate"):
            continue
        nat = w.nations.get(o.nation)
        if nat is None or not nat.alive:
            continue
        if o.kind == "corp":
            growth = (nat.growth / 360.0) + rng.gauss(0, 0.004)
            if o.industries:
                px = mean([m.p(INDUSTRIES[i]["out"]) / GOODS[INDUSTRIES[i]["out"]]["base"]
                           for i in o.industries if i in INDUSTRIES] or [1.0])
                growth += (px - 1.0) * 0.003
            growth -= nat.unrest * 0.0010 + (0.004 if nat.at_war else 0.0)
            o.revenue = max(0.0, o.revenue * (1 + clamp(growth, -0.004, 0.004)))
            margin = clamp(0.11 - nat.get_policy("tax_corporate") * 0.22
                           - nat.get_policy("market_reg") * 0.05
                           + o.rnd / max(o.revenue, 1) * 0.4 + rng.gauss(0, 0.010), -0.30, 0.45)
            o.profit = o.revenue * margin
            o.cash += o.profit - o.debt * nat.rate / 360.0
            if o.cash < 0:
                o.debt += -o.cash
                o.cash = 0.0
            o.rnd = o.revenue * clamp(o.rnd / max(o.revenue, 1) * 0.98
                                      + 0.02 * nat.get_policy("research"), 0.0, 0.22)
        elif o.kind == "bank":
            spread = clamp(nat.rate + m.credit_spread - 0.008, 0.002, 0.25)
            o.revenue = o.assets.get("loans", 0.0) * spread / 360.0
            o.profit = o.revenue * clamp(0.35 - nat.unrest, -0.5, 0.5)
            o.cash += o.profit
            o.assets["loans"] = o.assets.get("loans", 0.0) * (
                1 + clamp(nat.growth / 360 - nat.unrest * 0.0008, -0.004, 0.004))
        else:
            from .content_conflict import RACKETS
            take = 0.0
            for rk, scale in o.rackets.items():
                d = RACKETS[rk]
                pressure = nat.get_policy("policing") * nat.state_capacity
                eff = clamp01(1.2 - pressure * 1.1 + nat.corruption * 0.5)
                take += nat.gdp * 0.0016 * scale * d["margin"] * eff
                o.heat = clamp01(o.heat + d["heat"] * 0.0016 * pressure - 0.004)
            o.revenue = take
            o.profit = take * 0.6
            o.cash += o.profit

        if o.public and o.kind in ("corp", "bank"):
            eps = o.profit * 360 / max(o.shares, 1)
            fair = max(1e-4, eps * lerp(9, 30, clamp01(0.5 + nat.growth * 6 + m.sentiment * 0.4)))
            drift = (fair - o.share_price) / max(o.share_price, 1e-6)
            o.share_price = max(1e-4, o.share_price * (1 + clamp(drift * 0.04, -0.08, 0.08)
                                                       + rng.gauss(m.sentiment * 0.0006, 0.010)))
            o.valuation = o.share_price * o.shares
        else:
            o.valuation = max(1e4, o.profit * 360 * 12 + o.cash)


def tick_markets_sentiment(w) -> None:
    rng = w.rng.sub("sentiment")
    m = w.market
    gp = [w.nations[i] for i in w.great_powers if i in w.nations]
    stress = 0.0
    if gp:
        stress = mean([n.unrest for n in gp]) + w.tension * 0.5
        stress += mean([max(0.0, n.inflation - 0.05) for n in gp]) * 2.0
    target = clamp(0.30 - stress * 1.6, -1, 1)
    m.sentiment = clamp(lerp(m.sentiment, target, 0.02) + rng.gauss(0, 0.015), -1, 1)
    m.credit_spread = clamp(0.012 + max(0.0, -m.sentiment) * 0.09, 0.004, 0.25)
    m.shipping_cost = clamp(lerp(m.shipping_cost, 1.0 + w.tension * 1.4, 0.02)
                            + rng.gauss(0, 0.008), 0.5, 5.0)


# ===========================================================================
def tick_labour(w) -> None:
    """Employment, wages, and slow reallocation of jobs between sectors."""
    for nat in w.living_nations():
        auto = 0.0
        for t in nat.techs:
            e = TECHS[t]["e"]
            auto += e.get("labor_sub", 0.0) + e.get("unemployment", 0.0)
        for rid in nat.regions:
            r = w.regions.get(rid)
            if r is None:
                continue
            util = nat.__dict__.get("_utilisation_rate", 1.0)
            # an informal economy absorbs a lot of slack: idle capacity does not
            # translate one-for-one into idle people
            target_emp = clamp01(0.968 * (0.86 + 0.14 * util)
                                 - auto * 0.12 - r.unrest * 0.22
                                 - max(0.0, nat.inflation - 0.08) * 0.35
                                 - r.devastation * 0.30
                                 + clamp(nat.growth, -0.1, 0.1) * 0.30)
            r.employment = clamp01(lerp(r.employment, target_emp, 0.006))
            tight = clamp01((r.employment - 0.90) / 0.09)
            r.wage = clamp(r.wage * (1 + nat.inflation / 360 + (tight - 0.5) * 0.0010
                                     + nat.get_policy("labour_rights") * 0.00030), 0.05, 60.0)
        rs = [w.regions[r] for r in nat.regions if r in w.regions]
        nat.unemployment = clamp01(1 - mean([r.employment for r in rs] or [0.94]))


def tick_reallocation(w) -> None:
    """Every ten days, re-solve the industry mix against current demand."""
    for nat in w.living_nations():
        IO.allocate(w, nat, blend=0.09)


def tick_inequality(w) -> None:
    for nat in w.living_nations():
        pol = nat.policy
        redistribution = (pol["tax_income"] * 0.6 + pol["tax_wealth"] * 4 + pol["welfare"] * 0.35
                          + pol["labour_rights"] * 0.2 + pol["education"] * 0.15)
        concentration = (0.55 + nat.corruption * 0.4 + (1 - pol["market_reg"]) * 0.3
                         + nat.tech_level * 0.2)
        target = clamp01(0.22 + 0.42 * concentration - 0.30 * redistribution)
        nat.gini = clamp01(lerp(nat.gini, target, 0.0025))
        for rid in nat.regions:
            r = w.regions.get(rid)
            if r is None:
                continue
            poor = clamp01(0.16 + 1.05 * nat.gini - 0.30 * nat.tech_level)
            rich = clamp01(0.03 + 0.22 * nat.tech_level - 0.08 * nat.gini)
            r.wealth["poor"] = lerp(r.wealth.get("poor", poor), poor, 0.004)
            r.wealth["rich"] = lerp(r.wealth.get("rich", rich), rich, 0.004)
            r.wealth["middle"] = clamp01(1 - r.wealth["poor"] - r.wealth["rich"])
