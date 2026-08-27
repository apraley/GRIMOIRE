"""Every information screen the player can pull up."""
from __future__ import annotations

import math

from . import ui
from . import worldmap as WM
from .content_conflict import OPS, RACKETS, UNITS
from .content_econ import GOODS, INDUSTRIES
from .content_social import AUDIENCES, AXES, AXIS_LABEL, GOV_TYPES, POLICIES, SKILLS
from .content_tech import TECHS
from .player import PLAYER_ID
from .util import (clamp, clamp01, fmt_int, fmt_money, fmt_num, fmt_pct, truncate)
from .victory import ENDINGS, PATHS, controlled_nations, evaluate


# ===========================================================================
def dashboard(w) -> list[str]:
    pl = w.player
    p = pl.me(w)
    nat = w.nations.get(p.nation)
    r = w.regions.get(p.region)
    c = w.cities.get(p.city)
    out = [ui.header(f"{p.name}", w.clock.long())]
    heat_name, heat_desc = pl.heat_label()
    loc = f"{c.name}, {nat.name}" if c and nat else (nat.name if nat else "nowhere")
    out += ui.kv([
        ("Standing", p.title or pl.background),
        ("Location", loc),
        ("Age", f"{int(p.age)}"),
        ("Health", ui.tint(fmt_pct(p.health), p.health)),
        ("Liquid", fmt_money(pl.money)),
        ("Net worth", fmt_money(pl.net_worth(w))),
        ("Dirty money", ui.c(fmt_money(pl.dirty_money), "y" if pl.dirty_money > 0 else "K")),
        ("Debt", ui.c(fmt_money(pl.debt), "R" if pl.debt > 0 else "K")),
        ("Action points", f"{pl.ap}/{pl.ap_max}"),
        ("Stress", ui.tint(fmt_pct(pl.stress), pl.stress, good_high=False)),
        ("Fame", fmt_pct(pl.fame)),
        ("Heat", ui.tint(f"{fmt_pct(pl.heat)}  [{heat_name}]", pl.heat, good_high=False)),
    ], cols=2, keyw=14)
    if pl.imprisoned_by:
        out.append(ui.c(f"  IMPRISONED by {w.nations[pl.imprisoned_by].name} — "
                        f"{(pl.prison_until - w.clock.day)} days remain.", "R", "b"))
    if pl.wanted_by:
        out.append(ui.c("  Wanted by: " + ", ".join(
            w.nations[n].name for n in pl.wanted_by if n in w.nations), "R"))
    if pl.wounds:
        out.append(ui.c("  Wounds: " + ", ".join(
            f"{x['kind']} ({fmt_pct(x['sev'])})" for x in pl.wounds), "y"))
    if pl.in_hiding:
        out.append(ui.c("  You are in hiding.", "K"))

    out.append("")
    out.append(ui.c("── Your holdings " + "─" * (ui.term_width() - 17), "K"))
    if pl.orgs:
        rows = []
        for oid in pl.orgs:
            o = w.orgs.get(oid)
            if o and o.alive:
                rows.append([o.name, o.kind, fmt_money(o.valuation),
                             fmt_money(o.revenue * 360), fmt_pct(pl.holdings.get(oid, 0)),
                             w.nations[o.nation].name if o.nation in w.nations else "—"])
        out += ui.table(rows, ["organisation", "kind", "value", "revenue/yr", "stake", "based"],
                        ["<", "<", ">", ">", ">", "<"])
    else:
        out.append(ui.c("  Nothing yet. 'found corp | <name>' is a start.", "K"))
    if pl.assets:
        out.append("")
        out.append(ui.c(f"  Assets ({len(pl.assets)}): ", "K")
                   + ", ".join(w.people[a].name for a in pl.assets[:8] if a in w.people)
                   + (" …" if len(pl.assets) > 8 else ""))
    live = [w.operations[o] for o in w.operations
            if not w.operations[o].resolved and w.operations[o].actor == PLAYER_ID]
    if live:
        out.append("")
        out.append(ui.c("  Operations in flight:", "b"))
        for op in live:
            tgt = _target_name(w, op)
            out.append(f"    {ui.pad(op.codename, 22)}{ui.pad(op.kind, 16)}"
                       f"{ui.pad(truncate(tgt, 22), 24)}{op.eta - w.clock.day}d")

    out.append("")
    out.append(ui.c("── The world " + "─" * (ui.term_width() - 13), "K"))
    wars = [x for x in w.wars.values() if x.ended is None]
    out += ui.kv([
        ("World GDP", fmt_money(w.global_gdp * 360)),
        ("World population", fmt_num(w.global_pop)),
        ("Market index", f"{w.market.index:.1f} {w.market.index_hist.spark(18)}"),
        ("Sentiment", ui.tint(f"{w.market.sentiment:+.2f}", w.market.sentiment, -1, 1)),
        ("Tension", ui.tint(fmt_pct(w.tension), w.tension, good_high=False)),
        ("Active wars", str(len(wars))),
        ("Doomsday", ui.tint(fmt_pct(w.doomsday), w.doomsday, good_high=False)),
        ("Mean tech", fmt_pct(w.world_tech)),
    ], cols=2, keyw=18)
    if nat:
        out.append("")
        out.append(ui.c(f"── {nat.formal} " + "─" * max(0, ui.term_width() - 5 - len(nat.formal)), "K"))
        out += _nation_vitals(w, nat)
    prog = evaluate(w, pl)
    best = sorted(prog.items(), key=lambda kv: -kv[1])[:3]
    out.append("")
    out.append(ui.c("── Toward domination " + "─" * (ui.term_width() - 21), "K"))
    for k, v in best:
        out.append(f"  {ui.pad(PATHS[k]['label'], 16)}{ui.meter(v, 30)} {fmt_pct(v)}")
    return out


def _nation_vitals(w, nat) -> list[str]:
    return ui.kv([
        ("Government", nat.gov.replace("_", " ")),
        ("Population", fmt_num(nat.pop)),
        ("GDP", fmt_money(nat.gdp * 360)),
        ("GDP/capita", fmt_money(nat.gdp_per_capita(), places=0)),
        ("Growth", ui.tint(fmt_pct(nat.growth, signed=True), nat.growth, -0.05, 0.06)),
        ("Inflation", ui.tint(fmt_pct(nat.inflation), nat.inflation, 0, 0.15, good_high=False)),
        ("Unemployment", ui.tint(fmt_pct(nat.unemployment), nat.unemployment, 0, 0.3, good_high=False)),
        ("Debt / GDP", ui.tint(f"{nat.debt_ratio():.2f}", nat.debt_ratio(), 0, 3, good_high=False)),
        ("Stability", ui.tint(fmt_pct(nat.stability), nat.stability)),
        ("Legitimacy", ui.tint(fmt_pct(nat.legitimacy), nat.legitimacy)),
        ("Unrest", ui.tint(fmt_pct(nat.unrest), nat.unrest, good_high=False)),
        ("Corruption", ui.tint(fmt_pct(nat.corruption), nat.corruption, good_high=False)),
    ], cols=2, keyw=16)


def _target_name(w, op) -> str:
    for d in (w.people, w.nations, w.orgs, w.regions):
        if op.target in d:
            return getattr(d[op.target], "name", op.target)
    return op.target


# ===========================================================================
def nation_view(w, nat) -> list[str]:
    pl = w.player
    out = [ui.header(nat.formal, f"{nat.name} · {nat.culture} · founded {nat.founded}")]
    out += ui.para(GOV_TYPES[nat.gov]["desc"], "  ")
    out.append("")
    out += _nation_vitals(w, nat)
    out.append("")
    hos = w.people.get(nat.head_of_state)
    hog = w.people.get(nat.head_of_gov)
    out.append(ui.c("Leadership", "b"))
    if hos:
        out.append(f"  {ui.pad(hos.title or 'Head of state', 22)}{ui.pad(hos.name, 26)}"
                   f"age {int(hos.age)}  influence {ui.meter(hos.influence(), 10)}")
    if hog and hog.id != (hos.id if hos else None):
        out.append(f"  {ui.pad('Head of government', 22)}{ui.pad(hog.name, 26)}"
                   f"age {int(hog.age)}  influence {ui.meter(hog.influence(), 10)}")
    for role, pid in nat.cabinet.items():
        q = w.people.get(pid)
        if q and q.alive:
            mark = ui.c(" ●", "G") if q.asset_of == PLAYER_ID else (
                ui.c(" ◆", "y") if q.blackmailed_by == PLAYER_ID else "")
            out.append(f"  {ui.pad(role.replace('_', ' ').title(), 22)}{ui.pad(q.name, 26)}"
                       f"loyalty {fmt_pct(q.loyalty)}{mark}")
    out.append("")
    out.append(ui.c("Ideology", "b"))
    for ax in AXES:
        lo, hi = AXIS_LABEL[ax]
        v = nat.ideology.get(ax, 0.0)
        out.append(f"  {ui.pad(lo, 18, '>')} {ui.meter((v + 1) / 2, 24)} {ui.pad(hi, 18)}"
                   f" {v:+.2f}")
    out.append("")
    out.append(ui.c("Military", "b"))
    if nat.forces:
        rows = [[u, f"{n:,.0f}", UNITS[u]["dom"], fmt_num(UNITS[u]["men"] * n)]
                for u, n in sorted(nat.forces.items(), key=lambda kv: -kv[1])]
        out += ui.table(rows, ["formation", "count", "domain", "personnel"],
                        ["<", ">", "<", ">"])
    out += ui.kv([("Military index", fmt_num(nat.military_score())),
                  ("Personnel", fmt_num(nat.manpower)),
                  ("Reserves", fmt_num(nat.reserves_men)),
                  ("Morale", fmt_pct(nat.morale)),
                  ("Readiness", fmt_pct(nat.readiness)),
                  ("Army loyalty", ui.tint(fmt_pct(nat.army_loyalty), nat.army_loyalty)),
                  ("Warheads", ui.c(str(nat.nukes), "R" if nat.nukes else "K")),
                  ("Doctrine", nat.doctrine.replace("_", " "))], cols=2, keyw=16)
    out.append("")
    out.append(ui.c("Foreign relations", "b"))
    rel = sorted(((k, v) for k, v in nat.relations.items()
                  if k in w.nations and w.nations[k].alive), key=lambda kv: -kv[1])
    best = rel[:5]
    worst = rel[-5:][::-1]
    rows = []
    for (a, av), (b, bv) in zip(best, worst):
        rows.append([w.nations[a].name, ui.tint(f"{av:+.2f}", av, -1, 1),
                     ",".join(sorted(nat.treaties.get(a, set())))[:22],
                     w.nations[b].name, ui.tint(f"{bv:+.2f}", bv, -1, 1),
                     "WAR" if b in nat.at_war else ("sanctioned" if b in nat.sanctions else "")])
    out += ui.table(rows, ["friend", "rel", "treaties", "rival", "rel", ""],
                    ["<", ">", "<", "<", ">", "<"])
    if nat.at_war:
        out.append(ui.c("  AT WAR WITH: " + ", ".join(
            w.nations[n].name for n in nat.at_war if n in w.nations), "R", "b"))
    out.append("")
    out.append(ui.c("Regions", "b"))
    rows = []
    for rid in nat.regions:
        r = w.regions.get(rid)
        if r is None:
            continue
        rows.append([r.name, fmt_num(r.pop), fmt_pct(r.urban),
                     ui.tint(fmt_pct(r.unrest), r.unrest, good_high=False),
                     ui.tint(fmt_pct(r.control), r.control),
                     fmt_pct(r.devastation) if r.devastation > 0.01 else "—",
                     ",".join(sorted(r.resources, key=lambda k: -r.resources[k])[:3])])
    out += ui.table(rows, ["region", "pop", "urban", "unrest", "control", "damage", "resources"],
                    ["<", ">", ">", ">", ">", ">", "<"])
    out.append("")
    out.append(ui.c("Technology", "b") + f"  {len(nat.techs)} held, "
               f"index {fmt_pct(nat.tech_level)}, "
               f"{nat.rp_per_day:.1f} research/day"
               + (f", researching {nat.research_focus.replace('_', ' ')}"
                  if nat.research_focus else ""))
    if pl is not None:
        auth = 0.0
        from .actions import _authority
        auth = _authority(w, pl, nat)
        out.append("")
        out.append(f"  {ui.c('Your authority here:', 'b')} {ui.meter(auth, 24)} {fmt_pct(auth)}")
    return out


def person_view(w, p) -> list[str]:
    nat = w.nations.get(p.nation)
    out = [ui.header(p.name, f"{p.describe_role()} · {nat.name if nat else '—'}")]
    out += ui.kv([
        ("Age", f"{int(p.age)}"),
        ("Culture", p.culture),
        ("Influence", ui.meter(p.influence(), 14) + f" {fmt_pct(p.influence())}"),
        ("Wealth", fmt_money(p.wealth)),
        ("Competence", fmt_pct(p.competence)),
        ("Ambition", fmt_pct(p.ambition)),
        ("Loyalty", fmt_pct(p.loyalty)),
        ("Corruptibility", fmt_pct(p.corruptibility)),
        ("Health", ui.tint(fmt_pct(p.health), p.health)),
        ("Protection", fmt_pct(p.protection)),
        ("Suspicion", ui.tint(fmt_pct(p.suspicion), p.suspicion, good_high=False)),
        ("Public profile", fmt_pct(p.public_profile)),
    ], cols=2, keyw=16)
    out.append(f"  {ui.c('Traits', 'K')}: {', '.join(p.traits)}")
    top = sorted(p.skills.items(), key=lambda kv: -kv[1])[:6]
    out.append(f"  {ui.c('Skills', 'K')}: " + ", ".join(f"{k} {fmt_pct(v)}" for k, v in top))
    out.append("")
    out.append(ui.c("Toward you", "b"))
    for d in ("trust", "affection", "fear", "respect", "debt"):
        v = p.player_rel.get(d, 0.0)
        out.append(f"  {ui.pad(d, 12)}{ui.meter((v + 1) / 2, 24)} "
                   f"{ui.tint(f'{v:+.2f}', v, -1, 1)}")
    tags = []
    if p.asset_of == PLAYER_ID:
        tags.append(ui.c("YOUR ASSET", "G", "b"))
    elif p.asset_of:
        tags.append(ui.c("asset of a foreign service", "y"))
    if p.blackmailed_by == PLAYER_ID:
        tags.append(ui.c("UNDER YOUR THUMB", "y", "b"))
    if p.__dict__.get("_held_by") == PLAYER_ID:
        tags.append(ui.c("HELD BY YOU", "R", "b"))
    if tags:
        out.append("  " + "  ".join(tags))
    known = [s for s in p.secrets if PLAYER_ID in s["known_by"]]
    out.append("")
    if known:
        out.append(ui.c("Secrets you hold", "b"))
        for s in known:
            out.append(f"  • {s['desc']} "
                       + ui.c(f"(severity {fmt_pct(s['severity'])}"
                              + (", fabricated" if s.get("planted") else "") + ")", "K"))
    elif p.secrets:
        out.append(ui.c("  They have something to hide. Surveil them to find out what.", "K"))
    else:
        out.append(ui.c("  Nothing obvious to hold over them.", "K"))
    if p.knows:
        out.append("")
        close = sorted(p.knows.items(), key=lambda kv: -kv[1])[:6]
        out.append(ui.c("Knows", "b") + ": " + ", ".join(
            f"{w.people[k].name}" for k, _v in close if k in w.people and w.people[k].alive))
    return out


def region_view(w, r) -> list[str]:
    nat = w.nations.get(r.nation)
    out = [ui.header(r.name, f"{nat.name if nat else '—'} · {fmt_num(r.area)} km²")]
    bio = ", ".join(f"{b} {fmt_pct(f)}" for b, f in
                    sorted(r.biomes.items(), key=lambda kv: -kv[1])[:4])
    out += ui.para(f"Terrain: {bio}. Latitude {r.lat:+.0f}°, "
                   f"{'coastal' if r.coastal else 'landlocked'}.", "  ")
    out += ui.kv([
        ("Population", fmt_num(r.pop)),
        ("Urban", fmt_pct(r.urban)),
        ("Education", fmt_pct(r.education)),
        ("Health", fmt_pct(r.health)),
        ("Employment", fmt_pct(r.employment)),
        ("Wage index", f"{r.wage:.2f}"),
        ("Infrastructure", fmt_pct(r.effective_infra())),
        ("Unrest", ui.tint(fmt_pct(r.unrest), r.unrest, good_high=False)),
        ("Insurgency", ui.tint(fmt_pct(r.insurgency), r.insurgency, good_high=False)),
        ("Devastation", ui.tint(fmt_pct(r.devastation), r.devastation, good_high=False)),
        ("Separatism", ui.tint(fmt_pct(r.separatism), r.separatism, good_high=False)),
        ("Gov control", ui.tint(fmt_pct(r.control), r.control)),
    ], cols=2, keyw=16)
    if r.occupier and r.occupier in w.nations:
        out.append(ui.c(f"  OCCUPIED by {w.nations[r.occupier].name}", "R", "b"))
    out.append("")
    out.append(ui.c("Resources", "b"))
    res = sorted(r.resources.items(), key=lambda kv: -kv[1])[:10]
    out.append("  " + "   ".join(f"{k} {v:.2f}" for k, v in res))
    out.append("")
    out.append(ui.c("Industry", "b"))
    rows = [[i, fmt_num(j), INDUSTRIES[i]["out"], fmt_num(r.output.get(INDUSTRIES[i]["out"], 0))]
            for i, j in sorted(r.capacity.items(), key=lambda kv: -kv[1])[:14]]
    out += ui.table(rows, ["industry", "jobs", "makes", "output/day"], ["<", ">", "<", ">"])
    out.append("")
    out.append(ui.c("Cities", "b"))
    rows = []
    for cid in r.cities:
        c = w.cities.get(cid)
        if c:
            rows.append([c.label(), fmt_num(c.pop), c.tier,
                         "port" if c.port else "", ui.tint(fmt_pct(c.crime), c.crime, good_high=False),
                         fmt_pct(c.damage) if c.damage > 0.01 else "—"])
    out += ui.table(rows, ["city", "pop", "tier", "", "crime", "damage"],
                    ["<", ">", "<", "<", ">", ">"])
    faiths = sorted(r.faiths.items(), key=lambda kv: -kv[1])[:5]
    out.append("")
    out.append(ui.c("Belief", "b") + ": " + ", ".join(
        f"{(w.faiths[k].name if k in w.faiths else 'secular')} {fmt_pct(v)}" for k, v in faiths))
    return out


def org_view(w, o) -> list[str]:
    nat = w.nations.get(o.nation)
    out = [ui.header(o.name, f"{o.kind} · {nat.name if nat else '—'}")]
    out += ui.kv([
        ("Valuation", fmt_money(o.valuation)),
        ("Revenue/yr", fmt_money(o.revenue * 360)),
        ("Profit/yr", ui.tint(fmt_money(o.profit * 360), o.profit, -1, 1)),
        ("Cash", fmt_money(o.cash)),
        ("Debt", fmt_money(o.debt)),
        ("Headcount", fmt_num(o.headcount)),
        ("Influence", fmt_pct(o.influence)),
        ("Listed", "yes" if o.public else "no"),
        ("Share price", fmt_money(o.share_price, places=2) if o.public else "—"),
        ("Your stake", ui.c(fmt_pct(w.player.holdings.get(o.id, 0.0)), "G")
         if w.player and o.id in w.player.holdings else "—"),
        ("Secrecy", fmt_pct(o.secrecy)),
        ("Heat", ui.tint(fmt_pct(o.heat), o.heat, good_high=False)),
    ], cols=2, keyw=16)
    if o.leader and o.leader in w.people:
        out.append(f"  {ui.c('Led by', 'K')}: {w.people[o.leader].name}")
    if o.industries:
        out.append("")
        out.append(ui.c("Operations", "b"))
        rows = [[i, fmt_num(v), INDUSTRIES[i]["out"]] for i, v in
                sorted(o.industries.items(), key=lambda kv: -kv[1])]
        out += ui.table(rows, ["industry", "capacity", "output"], ["<", ">", "<"])
    if o.rackets:
        out.append("")
        out.append(ui.c("Rackets", "b"))
        rows = [[k, fmt_pct(v), fmt_pct(RACKETS[k]["margin"]), fmt_pct(RACKETS[k]["heat"])]
                for k, v in sorted(o.rackets.items(), key=lambda kv: -kv[1])]
        out += ui.table(rows, ["racket", "scale", "margin", "heat"], ["<", ">", ">", ">"])
    if o.kind in ("party",):
        out.append("")
        out.append(f"  Seats {fmt_pct(o.assets.get('seats', 0))}, "
                   f"support {fmt_pct(o.assets.get('support', 0))}")
    if o.kind in ("media", "faith", "movement"):
        out.append("")
        out.append(f"  Reach {fmt_pct(o.reach)}, "
                   f"credibility {fmt_pct(o.assets.get('credibility', 0.5))}, "
                   f"followers {fmt_num(o.assets.get('followers', 0))}")
    return out


def city_view(w, c) -> list[str]:
    r = w.regions.get(c.region)
    nat = w.nations.get(r.nation) if r else None
    out = [ui.header(c.label(), f"{r.name if r else ''} · {nat.name if nat else ''}")]
    out += ui.kv([("Population", fmt_num(c.pop)), ("Tier", c.tier),
                  ("Port", "yes" if c.port else "no"),
                  ("University", "yes" if c.university else "no"),
                  ("Exchange", "yes" if c.stock_exchange else "no"),
                  ("Crime", ui.tint(fmt_pct(c.crime), c.crime, good_high=False)),
                  ("Cost of living", f"{c.cost_of_living:.2f}"),
                  ("War damage", ui.tint(fmt_pct(c.damage), c.damage, good_high=False))],
                 cols=2, keyw=16)
    here = [q for q in w.people.values() if q.alive and q.city == c.id]
    if here:
        out.append("")
        out.append(ui.c("Notables in residence", "b"))
        for q in sorted(here, key=lambda x: -x.influence())[:12]:
            out.append(f"  {ui.pad(q.name, 26)}{ui.pad(q.describe_role(), 22)}"
                       f"{ui.meter(q.influence(), 10)}")
    return out


# ===========================================================================
def market_view(w, filt: str = "") -> list[str]:
    m = w.market
    out = [ui.header("World market", f"index {m.index:.1f}  "
                                     f"sentiment {m.sentiment:+.2f}  "
                                     f"freight ×{m.shipping_cost:.2f}")]
    rows = []
    for g, d in GOODS.items():
        if filt and filt.lower() not in g and filt.lower() != d["cat"]:
            continue
        price = m.p(g)
        ratio = price / d["base"]
        chg = m.hist[g].change(30)
        rows.append([g, d["cat"], fmt_money(price, places=0),
                     ui.tint(f"{ratio:.2f}×", ratio, 0.4, 2.0, good_high=False),
                     ui.delta(chg * 100, 1, "%"),
                     m.hist[g].spark(20),
                     fmt_num(m.supply.get(g, 0)), fmt_num(m.demand.get(g, 0))])
    out += ui.table(rows, ["good", "class", "price", "vs base", "30d", "trend",
                           "offered", "bid"],
                    ["<", "<", ">", ">", ">", "<", ">", ">"])
    return out


def news_view(w, days: int = 14, cat: str | None = None, minw: float = 0.35) -> list[str]:
    items = [n for n in w.recent_news(days, cat) if n.weight >= minw]
    items.sort(key=lambda n: (-n.day, -n.weight))
    out = [ui.header("Dispatches", f"last {days} days"
                     + (f" · {cat}" if cat else "") + f" · {len(items)} items")]
    if not items:
        out.append(ui.c("  Quiet.", "K"))
        return out
    lastday = None
    for n in items[:90]:
        if n.day != lastday:
            lastday = n.day
            d = w.clock.day - n.day
            out.append(ui.c(f"\n  {d}d ago" if d else "\n  today", "K", "b"))
        col = {"war": "R", "politics": "Y", "economy": "Cy", "tech": "M",
               "unrest": "y", "disaster": "R", "health": "G", "diplomacy": "B",
               "intel": "M", "crime": "y"}.get(n.cat, "w")
        tag = ui.c(f"[{n.cat}]", col)
        for i, line in enumerate(ui.wrap(n.text, ui.term_width() - 16)):
            out.append(f"    {ui.pad(tag if i == 0 else '', 11)}{line}")
    return out


def intel_view(w) -> list[str]:
    pl = w.player
    out = [ui.header("Intelligence", f"heat {fmt_pct(pl.heat)} · "
                                     f"exposure {fmt_pct(pl.exposure)}")]
    name, desc = pl.heat_label()
    out += ui.para(f"Status: {name.replace('_', ' ')}. {desc}", "  ")
    if pl.wanted_by:
        out.append(ui.c("  Warrants outstanding in: " + ", ".join(
            w.nations[n].name for n in pl.wanted_by if n in w.nations), "R"))
    out.append("")
    live = [o for o in w.operations.values() if o.actor == PLAYER_ID and not o.resolved]
    out.append(ui.c("Operations in flight", "b"))
    if live:
        rows = [[o.codename, o.kind, _target_name(w, o), f"{o.eta - w.clock.day}d",
                 fmt_pct(o.skill), fmt_money(o.budget)] for o in live]
        out += ui.table(rows, ["codename", "operation", "target", "eta", "skill", "budget"],
                        ["<", "<", "<", ">", ">", ">"])
    else:
        out.append(ui.c("  Nothing running.", "K"))
    out.append("")
    out.append(ui.c("Assets", "b"))
    if pl.assets:
        rows = []
        for aid in pl.assets:
            a = w.people.get(aid)
            if a and a.alive:
                rows.append([a.name, a.describe_role(),
                             w.nations[a.nation].name if a.nation in w.nations else "—",
                             fmt_pct(a.influence()),
                             ui.tint(fmt_pct(a.suspicion), a.suspicion, good_high=False)])
        out += ui.table(rows, ["asset", "position", "nation", "influence", "suspicion"],
                        ["<", "<", "<", ">", ">"])
    else:
        out.append(ui.c("  None. 'recruit_asset <person>' or 'recruit <person>'.", "K"))
    out.append("")
    out.append(ui.c("Leverage held", "b"))
    holders = []
    for q in w.people.values():
        if not q.alive:
            continue
        known = [s for s in q.secrets if PLAYER_ID in s["known_by"]]
        if known:
            holders.append((q, known))
    holders.sort(key=lambda t: -t[0].influence())
    if holders:
        for q, secs in holders[:14]:
            mark = ui.c(" [owned]", "G") if q.blackmailed_by == PLAYER_ID else ""
            out.append(f"  {ui.pad(q.name, 24)}{ui.pad(q.describe_role(), 20)}"
                       f"{truncate(secs[0]['desc'], 46)}{mark}")
        if len(holders) > 14:
            out.append(ui.c(f"  … and {len(holders) - 14} more.", "K"))
    else:
        out.append(ui.c("  You know nobody's secrets. Surveillance is cheap; ignorance is not.", "K"))
    recent = pl.op_history[-10:]
    if recent:
        out.append("")
        out.append(ui.c("Recent operations", "b"))
        for day, kind, code, ok, exposed in reversed(recent):
            flag = ui.c("success", "G") if ok else ui.c("failure", "R")
            ex = ui.c("  EXPOSED", "R") if exposed else ""
            out.append(f"  d{ui.pad(str(day), 7)}{ui.pad(code, 22)}{ui.pad(kind, 16)}{flag}{ex}")
    return out


def war_view(w) -> list[str]:
    active = [x for x in w.wars.values() if x.ended is None]
    out = [ui.header("Wars", f"{len(active)} active · world tension "
                             f"{fmt_pct(w.tension)}")]
    if not active:
        out.append(ui.c("  The world is, for the moment, not shooting at itself.", "K"))
    for war in active:
        att = ", ".join(w.nations[n].name for n in war.attackers if n in w.nations)
        dfn = ", ".join(w.nations[n].name for n in war.defenders if n in w.nations)
        cas = sum(war.casualties.values())
        out.append("")
        out.append(ui.c(f"  {war.name}", "R", "b")
                   + ui.c(f"   [{war.id}]  day {w.clock.day - war.started}", "K"))
        out.append(f"    {ui.pad(att, 34)} vs {dfn}")
        bar = ui.meter((war.warscore + 1) / 2, 30)
        out.append(f"    warscore {bar} {war.warscore:+.2f}   "
                   f"casualties {fmt_num(cas)}   goal: {war.goal.replace('_', ' ')}")
        occ = [w.regions[r].name for r in war.occupied if r in w.regions]
        if occ:
            out.append(ui.c(f"    occupied: {', '.join(occ[:8])}"
                            + (f" (+{len(occ) - 8})" if len(occ) > 8 else ""), "y"))
        if war.nuclear:
            out.append(ui.c("    NUCLEAR WEAPONS HAVE BEEN USED IN THIS WAR", "R", "b"))
    return out


def rankings_view(w, metric: str = "power") -> list[str]:
    nats = w.living_nations()
    keyf = {
        "power": lambda n: n.power(), "gdp": lambda n: n.gdp,
        "pop": lambda n: n.pop, "military": lambda n: n.military_score(),
        "tech": lambda n: n.tech_level, "gdppc": lambda n: n.gdp_per_capita(),
        "stability": lambda n: n.stability, "corruption": lambda n: -n.corruption,
    }.get(metric, lambda n: n.power())
    nats.sort(key=keyf, reverse=True)
    out = [ui.header("The powers", f"ranked by {metric}")]
    rows = []
    for i, n in enumerate(nats[:30], 1):
        rows.append([str(i), n.name, n.gov.replace("_", " ")[:16], fmt_num(n.pop),
                     fmt_money(n.gdp * 360), fmt_money(n.gdp_per_capita(), places=0),
                     fmt_num(n.military_score()), fmt_pct(n.tech_level),
                     ui.tint(fmt_pct(n.stability), n.stability),
                     ui.c(str(n.nukes), "R") if n.nukes else "",
                     "WAR" if n.at_war else ""])
    out += ui.table(rows, ["#", "nation", "government", "pop", "GDP", "GDP/cap",
                           "military", "tech", "stable", "nukes", ""],
                    ["<", "<", "<", ">", ">", ">", ">", ">", ">", ">", "<"])
    return out


def tech_view(w, nat=None) -> list[str]:
    pl = w.player
    out = [ui.header("Technology", f"world index {fmt_pct(w.world_tech)}")]
    out.append(ui.c("Yours (personally held)", "b"))
    if pl.techs:
        out += ui.columns(sorted(t.replace("_", " ") for t in pl.techs), 4)
    else:
        out.append(ui.c("  None. 'study' to see what is within reach.", "K"))
    if pl.research:
        out.append("")
        out.append(ui.c("In progress", "b"))
        for t, v in sorted(pl.research.items(), key=lambda kv: -kv[1]):
            out.append(f"  {ui.pad(t.replace('_', ' '), 24)}{ui.meter(v / TECHS[t]['c'], 24)} "
                       f"{fmt_pct(v / TECHS[t]['c'])}")
    if nat is not None:
        out.append("")
        out.append(ui.c(f"{nat.name}", "b") + f" — {len(nat.techs)} technologies, "
                   f"{nat.rp_per_day:.2f} research/day"
                   + (f", pursuing {nat.research_focus.replace('_', ' ')}"
                      if nat.research_focus else ""))
        by_field = {}
        for t in nat.techs:
            by_field.setdefault(TECHS[t]["f"], []).append(t)
        for f in sorted(by_field):
            out.append(f"  {ui.pad(f, 14)}{ui.c(', '.join(sorted(by_field[f])), 'K')}")
    out.append("")
    out.append(ui.c("Frontier — who holds what nobody else does", "b"))
    known = w.flags.get("tech_known", {})
    rare = [(t, d) for t, d in TECHS.items() if d["c"] > 6000]
    rows = []
    for t, d in sorted(rare, key=lambda kv: -kv[1]["c"])[:14]:
        holders = [n.name for n in w.living_nations() if t in n.techs]
        rows.append([t.replace("_", " "), d["f"], fmt_num(d["c"]),
                     truncate(", ".join(holders) if holders else "—", 44)])
    out += ui.table(rows, ["technology", "field", "cost", "held by"], ["<", "<", ">", "<"])
    return out


def ledger_view(w) -> list[str]:
    pl = w.player
    out = [ui.header("Ledger", f"net worth {fmt_money(pl.net_worth(w))}")]
    out += ui.kv([("Liquid", fmt_money(pl.money)),
                  ("Dirty", fmt_money(pl.dirty_money)),
                  ("Debt", fmt_money(pl.debt)),
                  ("Daily net", ui.delta(pl.income, 0)),
                  ("Organisations", str(len(pl.orgs))),
                  ("Assets on payroll", str(len(pl.assets)))], cols=2, keyw=18)
    if pl.holdings:
        out.append("")
        out.append(ui.c("Equity", "b"))
        rows = []
        for oid, frac in sorted(pl.holdings.items(), key=lambda kv: -kv[1]):
            o = w.orgs.get(oid)
            if o and o.alive:
                rows.append([o.name, o.kind, fmt_pct(frac), fmt_money(o.valuation * frac),
                             ui.delta(o.profit * 360 * frac, 0)])
        out += ui.table(rows, ["holding", "kind", "stake", "value", "profit/yr"],
                        ["<", "<", ">", ">", ">"])
    pos = pl.flags.get("positions", {})
    if pos:
        out.append("")
        out.append(ui.c("Commodity positions", "b"))
        rows = [[g, fmt_num(u), fmt_money(w.market.p(g)), fmt_money(u * w.market.p(g))]
                for g, u in pos.items()]
        out += ui.table(rows, ["good", "units", "price", "value"], ["<", ">", ">", ">"])
    if pl.ledger:
        out.append("")
        out.append(ui.c("Recent movements", "b"))
        for day, amt, reason in reversed(pl.ledger[-18:]):
            out.append(f"  d{ui.pad(str(day), 7)}"
                       f"{ui.pad(ui.c(fmt_money(amt), 'G' if amt > 0 else 'R'), 22)}{reason}")
    return out


def victory_view(w) -> list[str]:
    pl = w.player
    scores = evaluate(w, pl)
    out = [ui.header("The road to power", "seven ways this ends with you on top")]
    for k in PATHS:
        v = scores.get(k, 0.0)
        out.append("")
        out.append(f"  {ui.c(ui.pad(PATHS[k]['label'], 14), 'b')}{ui.meter(v, 34)} "
                   f"{ui.tint(fmt_pct(v), v)}")
        out += ui.para(PATHS[k]["blurb"], "      ")
    ctrl = controlled_nations(w, pl)
    if ctrl:
        out.append("")
        out.append(ui.c("States under your influence", "b"))
        rows = [[w.nations[n].name, ui.meter(c, 18), fmt_pct(c),
                 fmt_num(w.nations[n].pop), fmt_money(w.nations[n].gdp * 360)]
                for n, c in sorted(ctrl.items(), key=lambda kv: -kv[1])[:16]]
        out += ui.table(rows, ["nation", "control", "", "pop", "GDP"],
                        ["<", "<", ">", ">", ">"])
    return out


def map_view(w, key: str = "political", focus: str | None = None,
             step: int = 1) -> list[str]:
    owner = {}
    for r in w.regions.values():
        nat = w.nations.get(r.nation)
        if nat:
            owner[r.id] = nat.name
    p = w.people.get(PLAYER_ID)
    mark = {}
    if p is not None and p.region in w.regions:
        cx, cy = w.regions[p.region].centroid
        mark[(cx // step * step, cy // step * step)] = "@"
    lines = WM.render(w.planet, owner, focus=focus, key=key, mark=mark, step=step)
    out = [ui.header("The world", f"{key} · @ marks you")]
    out += lines
    if key == "political":
        top = sorted(w.living_nations(), key=lambda n: -n.pop)[:14]
        out.append("")
        out.append(ui.c("  " + "   ".join(
            ui.c(n.name[0], WM.pal_for(n.id), "b") + " " + truncate(n.name, 13)
            for n in top), "K"))
    return out


def people_view(w, query: str = "") -> list[str]:
    q = query.lower().strip()
    pool = [p for p in w.people.values() if p.alive and p.id != PLAYER_ID]
    if q:
        nat = w.find_nation(q)
        if nat:
            pool = [p for p in pool if p.nation == nat.id]
        else:
            pool = [p for p in pool if q in p.name.lower() or q in p.role.lower()]
    pool.sort(key=lambda p: -p.influence())
    out = [ui.header("People", f"{len(pool)} matching" + (f" '{query}'" if query else ""))]
    rows = []
    for p in pool[:40]:
        nat = w.nations.get(p.nation)
        flags = []
        if p.asset_of == PLAYER_ID:
            flags.append(ui.c("asset", "G"))
        if p.blackmailed_by == PLAYER_ID:
            flags.append(ui.c("held", "y"))
        if any(PLAYER_ID in s["known_by"] for s in p.secrets):
            flags.append(ui.c("leverage", "M"))
        d = p.disposition()
        rows.append([p.name, p.describe_role(), nat.name if nat else "—", str(int(p.age)),
                     fmt_pct(p.influence()), ui.tint(f"{d:+.2f}", d, -1, 1), " ".join(flags)])
    out += ui.table(rows, ["name", "position", "nation", "age", "influence", "toward you", ""],
                    ["<", "<", "<", ">", ">", ">", "<"])
    return out


def help_view(w, topic: str = "") -> list[str]:
    from .actions import REGISTRY
    if topic:
        from .actions import find_action
        a = find_action(topic)
        if a:
            return ([ui.header(a["name"], a["cat"])]
                    + ui.para(a["desc"], "  ")
                    + ["", f"  {ui.c('Usage', 'b')}: {a['usage']}",
                       f"  {ui.c('Cost', 'b')}: {a['ap']} AP"
                       + (f", {fmt_money(a['money'])}" if a["money"] else "")])
    out = [ui.header("GRIMOIRE", "commands")]
    out += ui.para("Type an action and its arguments. Multi-part arguments are separated "
                   "by a pipe: 'bribe Renna Voss | 4000000'. Names can be abbreviated. "
                   "Every day gives you action points; 'wait' or 'next' ends the day.", "  ")
    out.append("")
    groups = {}
    for a in REGISTRY.values():
        groups.setdefault(a["cat"], []).append(a)
    for cat in ("info", "move", "personal", "social", "covert", "econ", "politics",
                "military", "media", "research"):
        if cat not in groups:
            continue
        out.append(ui.c(f"  {cat.upper()}", "b", "Cy"))
        for a in sorted(groups[cat], key=lambda x: x["name"]):
            cost = f"{a['ap']}ap" + (f" {fmt_money(a['money'])}" if a["money"] else "")
            out.append(f"    {ui.pad(a['usage'], 40)}{ui.pad(ui.c(cost, 'K'), 22)}{a['desc']}")
        out.append("")
    out.append(ui.c("  SCREENS", "b", "Cy"))
    for name, desc in SCREENS:
        out.append(f"    {ui.pad(name, 40)}{desc}")
    return out


SCREENS = [
    ("status / dash", "your position at a glance"),
    ("look", "your immediate surroundings"),
    ("map [political|terrain|climate|resource:<kind>]", "the world"),
    ("news [days] [category]", "what has been happening"),
    ("nation <name>", "a full national dossier"),
    ("region <name>", "a province in detail"),
    ("city <name>", "a city in detail"),
    ("who <name>", "a person's dossier"),
    ("org <name>", "an organisation's books"),
    ("people [nation|query]", "everyone who matters"),
    ("market [filter]", "world commodity prices"),
    ("wars", "every shooting war"),
    ("powers [gdp|military|tech|pop]", "the league table"),
    ("tech [nation]", "the state of the art"),
    ("intel", "your operations, assets and leverage"),
    ("ledger", "your money"),
    ("goals", "progress toward domination"),
    ("skills", "your abilities"),
    ("timeline", "your own history"),
    ("wait [n] / next", "end the day (or n days)"),
    ("save [name] / load [name]", "persistence"),
    ("help [action]", "this, or detail on one action"),
    ("quit", "leave"),
]


def skills_view(w) -> list[str]:
    pl = w.player
    p = pl.me(w)
    out = [ui.header("Capabilities", p.name)]
    out.append(ui.c("Attributes", "b"))
    from .content_social import ATTRIBUTES
    rows = [[a, str(p.attrs.get(a, 10)), ui.meter(p.attrs.get(a, 10) / 20, 18), d]
            for a, d in ATTRIBUTES.items()]
    out += ui.table(rows, ["attribute", "", "", "governs"], ["<", ">", "<", "<"])
    out.append("")
    for cat in ("social", "power", "econ", "covert", "self"):
        out.append(ui.c(f"{cat.upper()}", "b", "Cy"))
        rows = []
        for k, d in SKILLS.items():
            if d["cat"] != cat:
                continue
            v = p.skill(k)
            rows.append([k, ui.meter(v, 20), fmt_pct(v), d["desc"]])
        out += ui.table(rows, ["skill", "", "", ""], ["<", "<", ">", "<"])
        out.append("")
    if p.traits:
        out.append(ui.c("Traits", "b") + ": " + ", ".join(p.traits))
    if pl.perks:
        out.append("")
        out.append(ui.c("Perks", "b"))
        from .content_social import PERKS
        for k in sorted(pl.perks):
            out.append(f"  {ui.pad(k, 22)}{PERKS.get(k, '')}")
    return out


def timeline_view(w) -> list[str]:
    pl = w.player
    out = [ui.header("Your history", f"{len(pl.timeline)} entries")]
    for day, text in pl.timeline[-60:]:
        out.append(f"  {ui.c('d' + str(day).rjust(6), 'K')}  {text}")
    return out
