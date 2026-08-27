"""The action registry: everything the player can actually do with a day."""
from __future__ import annotations

import math

from . import names as N
from . import ui
from .content_conflict import (DOCTRINES, FAITH_DOCTRINES, NARRATIVE_KINDS, OPS,
                               RACKETS, TREATY_KINDS, UNITS, WAR_GOALS)
from .content_econ import GOODS, INDUSTRIES
from .content_social import (AXES, IDEOLOGIES, POLICIES, SKILLS, TRAITS)
from .content_tech import RESEARCH_PROJECTS, TECHS
from .entities import Org, Project
from .player import PLAYER_ID
from .util import clamp, clamp01, fmt_money, fmt_num, fmt_pct, lerp, mean

REGISTRY: dict[str, dict] = {}
ALIASES: dict[str, str] = {}


class ActionError(Exception):
    pass


def action(name: str, cat: str, ap: int = 1, money: float = 0.0, aliases=(),
           usage: str = "", desc: str = "", needs=()):
    def deco(fn):
        REGISTRY[name] = dict(name=name, cat=cat, ap=ap, money=money, fn=fn,
                              usage=usage or name, desc=desc, needs=list(needs))
        ALIASES[name] = name
        for a in aliases:
            ALIASES[a] = name
        return fn
    return deco


def find_action(word: str):
    w = word.lower().strip()
    if w in ALIASES:
        return REGISTRY[ALIASES[w]]
    hits = [k for k in ALIASES if k.startswith(w)]
    if len(hits) == 1:
        return REGISTRY[ALIASES[hits[0]]]
    exact = [k for k in REGISTRY if k.startswith(w)]
    if len(exact) == 1:
        return REGISTRY[exact[0]]
    return None


def perform(w, pl, name: str, args: str) -> list[str]:
    a = find_action(name)
    if a is None:
        raise ActionError(f"No such action: {name!r}. Try 'actions' for the list.")
    if pl.imprisoned_by and a["cat"] not in ("personal", "info"):
        raise ActionError("You are in a cell. Your options are limited to waiting and thinking.")
    if pl.ap < a["ap"]:
        raise ActionError(f"That takes {a['ap']} action point(s); you have {pl.ap} left today.")
    if a["money"] and pl.money < a["money"]:
        raise ActionError(f"That costs {fmt_money(a['money'])}; you have {fmt_money(pl.money)}.")
    out = a["fn"](w, pl, args.strip())
    pl.ap -= a["ap"]
    if a["money"]:
        pl.spend(a["money"], a["name"], w.clock.day)
    pl.day_actions.append(a["name"])
    return out if isinstance(out, list) else [str(out)]


# --------------------------------------------------------------- helpers --
def _person(w, text: str):
    if not text:
        raise ActionError("Name somebody.")
    p = w.find_person(text)
    if p is None or not p.alive:
        raise ActionError(f"No living person matching {text!r}.")
    return p


def _nation(w, text: str):
    n = w.find_nation(text) if text else None
    if n is None:
        raise ActionError(f"No nation matching {text!r}." if text else "Name a nation.")
    return n


def _region(w, text: str):
    r = w.find_region(text) if text else None
    if r is None:
        raise ActionError(f"No region matching {text!r}." if text else "Name a region.")
    return r


def _org(w, text: str):
    o = w.find_org(text) if text else None
    if o is None or not o.alive:
        raise ActionError(f"No organisation matching {text!r}." if text else "Name an organisation.")
    return o


def _split(args: str, n: int = 2):
    parts = [x.strip() for x in args.split("|")]
    while len(parts) < n:
        parts.append("")
    return parts


def _check(w, pl, skill: str, difficulty: float, noise: float = 0.18):
    return w.rng.sub("actions").check(pl.skill(w, skill), difficulty, noise)


def _cost_scaled(base: float, pl) -> float:
    if "deep_pockets" in pl.perks:
        return base * 0.7
    return base


def _heat(pl, amount: float) -> None:
    resist = pl.flags.get("heat_resist", 0.0)
    pl.heat = clamp01(pl.heat + amount * (1 - resist))


# ===========================================================================
#  MOVEMENT & PERSONAL
# ===========================================================================
@action("travel", "move", ap=1, aliases=("go", "fly"), usage="travel <city|region|nation>",
        desc="Move yourself somewhere else. Distance costs days.")
def act_travel(w, pl, args):
    if not args:
        raise ActionError("Travel where?")
    dest = w.find_city(args) or w.find_region(args) or w.find_nation(args)
    if dest is None:
        raise ActionError(f"Nowhere called {args!r}.")
    p = pl.me(w)
    if hasattr(dest, "regions"):          # a nation
        cap = w.cities.get(dest.capital)
        city = cap
        region = w.regions.get(cap.region) if cap else None
    elif hasattr(dest, "cities"):         # a region
        region = dest
        city = w.cities.get(region.cities[0]) if region.cities else None
    else:                                 # a city
        city = dest
        region = w.regions.get(city.region)
    if region is None:
        raise ActionError("There is no way in.")
    target_nation = region.nation
    lines = []
    if target_nation in pl.wanted_by:
        ok, margin = _check(w, pl, "forgery", 0.45 + w.nations[target_nation].state_capacity * 0.4)
        if not ok:
            _heat(pl, 0.08)
            raise ActionError(f"Border control in {w.nations[target_nation].name} flagged your "
                              f"documents. You did not board.")
        lines.append(ui.c("You crossed on papers that will not survive a second look.", "y"))
    old = w.regions.get(p.region)
    dist = 0.0
    if old:
        dx = min(abs(old.centroid[0] - region.centroid[0]),
                 w.planet.w - abs(old.centroid[0] - region.centroid[0]))
        dist = math.hypot(dx, old.centroid[1] - region.centroid[1]) / w.planet.w
    days = max(0, int(dist * 9))
    p.region = region.id
    p.city = city.id if city else None
    p.nation = target_nation
    if days:
        pl.travel_until = w.clock.day + days
    nat = w.nations[target_nation]
    lines.append(f"You are in {ui.c(city.name if city else region.name, 'W', 'b')}, "
                 f"{nat.name}" + (f" — {days} days in transit." if days else "."))
    lines += _look_around(w, pl)
    return lines


@action("look", "info", ap=0, aliases=("where", "l"), usage="look",
        desc="Take in your surroundings.")
def act_look(w, pl, args):
    return _look_around(w, pl)


def _look_around(w, pl):
    p = pl.me(w)
    r = w.regions.get(p.region)
    c = w.cities.get(p.city)
    nat = w.nations.get(p.nation)
    if r is None or nat is None:
        return ["You are nowhere in particular."]
    out = [ui.header(f"{c.name if c else r.name}", f"{r.name}, {nat.formal}")]
    out += ui.para(f"{nat.gov_data()['desc']} Population of the region stands at "
                   f"{fmt_num(r.pop)}; {fmt_pct(r.urban)} of them live in cities. "
                   f"The mood is {_mood(r.unrest)}.")
    if c:
        out += ui.para(f"{c.name} is a {c.tier} city of {fmt_num(c.pop)}. "
                       f"Crime is {_level(c.crime)}, the cost of living is "
                       f"{'brutal' if c.cost_of_living > 2 else 'manageable'}"
                       + (f", and {fmt_pct(c.damage)} of it is rubble." if c.damage > 0.05 else "."))
    here = [q for q in w.people.values() if q.alive and q.region == r.id and q.id != PLAYER_ID]
    here.sort(key=lambda q: -q.influence())
    if here:
        out.append("")
        out.append(ui.c("People of consequence nearby:", "b"))
        for q in here[:8]:
            rel = q.disposition()
            tag = ui.c("ally", "G") if rel > 0.3 else (ui.c("hostile", "R") if rel < -0.3 else "")
            out.append(f"  {ui.pad(q.name, 26)} {ui.pad(q.describe_role(), 22)} "
                       f"{ui.meter(q.influence(), 8)} {tag}")
    return out


def _mood(u):
    return ("placid" if u < 0.10 else "restive" if u < 0.22 else "angry" if u < 0.38
            else "on the edge of revolt")


def _level(x):
    return "negligible" if x < 0.12 else "moderate" if x < 0.3 else "serious" if x < 0.55 else "endemic"


@action("rest", "personal", ap=1, aliases=("sleep",), usage="rest",
        desc="Sleep, eat, and stop being hunted for one day.")
def act_rest(w, pl, args):
    p = pl.me(w)
    pl.sleep = clamp01(pl.sleep + 0.35)
    pl.stress = clamp01(pl.stress - 0.14)
    p.health = clamp01(p.health + 0.012)
    pl.nutrition = clamp01(pl.nutrition + 0.25)
    return ["You sleep for eleven hours. The world does not stop, but you do.",
            f"Stress {fmt_pct(pl.stress)}, health {fmt_pct(p.health)}."]


@action("train", "personal", ap=1, usage="train <skill>",
        desc="Grind a skill upward. Slower the better you already are.")
def act_train(w, pl, args):
    if args not in SKILLS:
        near = [s for s in SKILLS if s.startswith(args.lower())]
        if len(near) != 1:
            raise ActionError("Train which skill? Try 'skills' for the list.")
        args = near[0]
    p = pl.me(w)
    cur = p.skills.get(args, 0.02)
    attr = p.attrs.get(SKILLS[args]["attr"], 10)
    gain = (0.020 + attr * 0.0016) * (1 - cur) ** 1.6 * (0.6 + 0.6 * (1 - pl.stress))
    if "obsessive" in p.traits:
        gain *= 1.15
    p.skills[args] = clamp01(cur + gain)
    pl.stress = clamp01(pl.stress + 0.02)
    return [f"You work at {args.replace('_', ' ')}: "
            f"{fmt_pct(cur)} → {ui.c(fmt_pct(p.skills[args]), 'G')}."]


@action("treat", "personal", ap=1, money=40000, aliases=("doctor", "hospital"),
        usage="treat", desc="Buy the best medicine available to you.")
def act_treat(w, pl, args):
    p = pl.me(w)
    nat = w.nations.get(p.nation)
    quality = clamp01(0.3 + (nat.tech_level if nat else 0.4) * 0.6
                      + (nat.get_policy("healthcare") if nat else 0.3) * 0.3)
    healed = 0
    for wnd in list(pl.wounds):
        wnd["sev"] *= clamp01(1 - quality * 0.7)
        if wnd["sev"] < 0.03:
            pl.wounds.remove(wnd)
            healed += 1
    p.health = clamp01(p.health + 0.08 * quality)
    return [f"Private clinic, no records. {healed} wound(s) closed; "
            f"health now {fmt_pct(p.health)}."]


@action("hide", "personal", ap=1, aliases=("lay_low", "ground"), usage="hide",
        desc="Go to ground. Heat falls, but so does everything else you could be doing.")
def act_hide(w, pl, args):
    pl.in_hiding = True
    _heat(pl, -0.03)
    pl.exposure = clamp01(pl.exposure - 0.05)
    return ["You disappear. Phones off, faces changed, a different bed every third night.",
            f"Heat: {fmt_pct(pl.heat)} and falling. You cannot run an empire from a basement forever."]


@action("surface", "personal", ap=0, usage="surface",
        desc="Stop hiding and start being seen again.")
def act_surface(w, pl, args):
    pl.in_hiding = False
    return ["You come back into the light."]


@action("identity", "personal", ap=1, money=350000, aliases=("legend", "alias"),
        usage="identity [switch <n>]", desc="Build or switch to a clean identity.")
def act_identity(w, pl, args):
    p = pl.me(w)
    if args.startswith("switch"):
        try:
            idx = int(args.split()[-1]) - 1
        except (ValueError, IndexError):
            raise ActionError("Which identity? Use 'identity switch 2'.")
        if not 0 <= idx < len(pl.identities):
            raise ActionError("No such identity.")
        pl.identities[pl.current_identity]["heat"] = pl.heat
        pl.current_identity = idx
        pl.heat = pl.identities[idx]["heat"]
        p.name = pl.identities[idx]["name"]
        return [f"You are now {ui.c(p.name, 'W', 'b')}. Heat resets to {fmt_pct(pl.heat)}."]
    ok, margin = _check(w, pl, "forgery", 0.40)
    if not ok:
        _heat(pl, 0.05)
        raise ActionError("The documents came back wrong. You burned the money and some goodwill.")
    nat = w.nations.get(p.nation)
    alias = N.person_name(w.rng.sub("alias"), nat.culture if nat else "Meritan", p.female)
    pl.identities.append({"name": alias, "clean": True, "heat": 0.0, "nation": p.nation})
    return [f"A complete legend, backstopped three deep: {ui.c(alias, 'W')}.",
            f"Use 'identity switch {len(pl.identities)}' to become them."]


@action("indulge", "personal", ap=1, money=25000, aliases=("drink", "party"),
        usage="indulge", desc="Relieve the pressure. Invite the consequences.")
def act_indulge(w, pl, args):
    rng = w.rng.sub("vice")
    pl.stress = clamp01(pl.stress - 0.22)
    pl.morale = clamp01(pl.morale + 0.10)
    out = ["A very expensive evening. You feel human again."]
    if rng.chance(0.25):
        k = rng.pick(["alcohol", "stimulants", "gambling"])
        pl.addictions[k] = clamp01(pl.addictions.get(k, 0) + 0.15)
        out.append(ui.c(f"You are developing a taste for {k}.", "y"))
    if rng.chance(0.12 + pl.notoriety * 0.3):
        from .sim_society import add_narrative
        p = pl.me(w)
        add_narrative(w, "ridicule", f"Photographs of {p.name} from a very long night.",
                      subject=PLAYER_ID, seed_nation=p.nation, seed=0.08, targets_player=True)
        out.append(ui.c("Someone had a camera.", "R"))
    return out


@action("study", "personal", ap=1, aliases=("read",), usage="study <field>",
        desc="Read your way toward a technology you want to hold personally.")
def act_study(w, pl, args):
    avail = [t for t, d in TECHS.items()
             if t not in pl.techs and all(pr in pl.techs for pr in d["p"])]
    if not args:
        return ([ui.c("Within reach of private study:", "b")]
                + ui.columns([f"{t} ({TECHS[t]['f']})" for t in sorted(avail)[:30]], 3))
    if args not in TECHS:
        near = [t for t in avail if t.startswith(args.lower())]
        if len(near) != 1:
            raise ActionError("No such technology within reach. Run 'study' bare for the list.")
        args = near[0]
    if args not in avail:
        raise ActionError("You lack the prerequisites for that.")
    d = TECHS[args]
    rate = (pl.skill(w, "science") * 0.6 + pl.skill(w, "engineering") * 0.4) * 260
    rate *= 1 + (0.25 if "engineer_mind" in pl.perks else 0)
    rate *= 1 + (0.4 if pl.flags.get("private_lab") else 0)
    pl.research[args] = pl.research.get(args, 0.0) + rate
    if pl.research[args] >= d["c"]:
        pl.techs.add(args)
        del pl.research[args]
        return [ui.c(f"You have mastered {args.replace('_', ' ')}.", "G", "b"), "  " + d["d"]]
    return [f"{args.replace('_', ' ')}: {fmt_pct(pl.research[args] / d['c'])} understood."]


# ===========================================================================
#  SOCIAL
# ===========================================================================
def _adjust(p, dim: str, amount: float) -> None:
    p.player_rel[dim] = clamp(p.player_rel.get(dim, 0.0) + amount, -1, 1)


@action("meet", "social", ap=1, aliases=("talk", "approach"), usage="meet <person>",
        desc="Get in a room with someone and take their measure.")
def act_meet(w, pl, args):
    p = _person(w, args)
    if p.region != pl.me(w).region and w.rng.sub("meet").chance(0.5):
        raise ActionError(f"{p.name} is not within reach. They are in "
                          f"{w.regions[p.region].name if p.region in w.regions else 'parts unknown'}.")
    ok, margin = _check(w, pl, "etiquette" if p.influence() > 0.5 else "networking",
                        0.25 + p.influence() * 0.4 - p.player_rel["trust"] * 0.2)
    _adjust(p, "trust", 0.06 if ok else -0.02)
    p.knows[PLAYER_ID] = clamp01(p.knows.get(PLAYER_ID, 0) + 0.20)
    pl.contacts[p.id] = clamp01(pl.contacts.get(p.id, 0) + 0.2)
    out = [ui.header(p.name, p.describe_role()),
           f"  {ui.pad('Nation', 14)}{w.nations[p.nation].name if p.nation in w.nations else '—'}",
           f"  {ui.pad('Age', 14)}{int(p.age)}    "
           f"{ui.pad('Influence', 12)}{ui.meter(p.influence(), 10)}",
           f"  {ui.pad('Traits', 14)}{', '.join(p.traits)}",
           f"  {ui.pad('Toward you', 14)}" + " ".join(
               f"{d}:{ui.tint(f'{p.player_rel[d]:+.2f}', p.player_rel[d], -1, 1)}"
               for d in ("trust", "affection", "fear", "respect", "debt"))]
    if ok:
        out.append("")
        out += ui.para(f"You read them: ambition {fmt_pct(p.ambition)}, "
                       f"loyalty to their patron {fmt_pct(p.loyalty)}, "
                       f"and a price that is {'high' if p.corruptibility < 0.3 else 'negotiable'}.")
        known = [s for s in p.secrets if PLAYER_ID in s["known_by"]]
        if known:
            out.append(ui.c("  You know: " + "; ".join(s["desc"] for s in known), "y"))
        elif p.secrets and margin > 0.25:
            out.append(ui.c("  They are hiding something. You would need to watch them to learn what.", "K"))
    else:
        out.append(ui.c("\n  They gave you nothing. The conversation was a wall.", "K"))
    return out


@action("cultivate", "social", ap=1, money=15000, aliases=("befriend", "charm"),
        usage="cultivate <person>", desc="Invest in a relationship over dinner and time.")
def act_cultivate(w, pl, args):
    p = _person(w, args)
    ok, margin = _check(w, pl, "networking", 0.30 + p.influence() * 0.35
                        - clamp01(p.player_rel["trust"]) * 0.3)
    if ok:
        _adjust(p, "trust", 0.10 + margin * 0.2)
        _adjust(p, "affection", 0.06 + margin * 0.15)
        _adjust(p, "respect", 0.04)
        t = p.player_rel["trust"]
        return [f"{p.name} is warmer toward you. Trust now {ui.tint('%+.2f' % t, t, -1, 1)}."]
    _adjust(p, "trust", -0.03)
    return [f"{p.name} was polite and entirely unmoved."]


@action("persuade", "social", ap=1, aliases=("convince",), usage="persuade <person> | <what>",
        desc="Argue someone into an alignment with your interests.")
def act_persuade(w, pl, args):
    who, what = _split(args)
    p = _person(w, who)
    lev = p.leverage()
    ok, margin = _check(w, pl, "negotiation",
                        0.42 + p.loyalty * 0.35 - lev * 0.45 - p.disposition() * 0.2)
    if ok:
        _adjust(p, "trust", 0.05)
        p.loyalty = clamp01(p.loyalty - 0.12 - margin * 0.15)
        p.__dict__.setdefault("_promises", []).append(what or "an unspecified favour")
        return [f"{p.name} agrees. \"{what or 'It can be arranged'}.\"",
                ui.c(f"  Their loyalty to their own side falls to {fmt_pct(p.loyalty)}.", "K")]
    _adjust(p, "respect", -0.05)
    return [f"{p.name} refuses. They will remember being asked."]


@action("threaten", "social", ap=1, aliases=("intimidate",), usage="threaten <person>",
        desc="Make the cost of refusal vivid.")
def act_threaten(w, pl, args):
    p = _person(w, args)
    muscle = 0.2 if pl.flags.get("enforcers") else 0.0
    ok, margin = _check(w, pl, "intimidation",
                        0.35 + p.protection * 0.3 + p.influence() * 0.3 - muscle)
    if ok:
        _adjust(p, "fear", 0.25 + margin * 0.3)
        _adjust(p, "trust", -0.15)
        _adjust(p, "affection", -0.20)
        _heat(pl, 0.015)
        fr = p.player_rel["fear"]
        return [f"{p.name} understood you perfectly. Fear {ui.c('%+.2f' % fr, 'R')}."]
    _adjust(p, "respect", -0.15)
    p.suspicion = clamp01(p.suspicion + 0.2)
    _heat(pl, 0.03)
    return [f"{p.name} was not frightened. Now they are forewarned, and hostile."]


@action("recruit", "social", ap=2, aliases=("hire",), usage="recruit <person>",
        desc="Bring someone permanently into your organisation.")
def act_recruit(w, pl, args):
    p = _person(w, args)
    if p.id in pl.assets:
        raise ActionError(f"{p.name} already works for you.")
    magnet = sum(TRAITS[t]["mods"].get("recruit", 0) for t in pl.me(w).traits)
    disp = p.disposition()
    lev = p.leverage()
    ok, margin = _check(w, pl, "networking",
                        0.55 + p.loyalty * 0.35 + p.influence() * 0.25
                        - disp * 0.45 - lev * 0.5 - magnet)
    if ok:
        p.is_asset = True
        p.asset_of = PLAYER_ID
        pl.assets.append(p.id)
        _adjust(p, "trust", 0.15)
        _adjust(p, "debt", 0.2)
        return [ui.c(f"{p.name} is yours.", "G", "b"),
                f"  They bring {p.describe_role().lower()} access and "
                f"{fmt_pct(p.influence())} influence."]
    _adjust(p, "trust", -0.10)
    p.suspicion = clamp01(p.suspicion + 0.15)
    return [f"{p.name} declined. You have shown them your hand."]


@action("favour", "social", ap=1, aliases=("favor", "call_in"), usage="favour <person> | <ask>",
        desc="Spend accumulated goodwill on a concrete act.")
def act_favour(w, pl, args):
    who, ask = _split(args)
    p = _person(w, who)
    lev = p.leverage()
    if lev < 0.18:
        raise ActionError(f"{p.name} owes you nothing yet.")
    ok, margin = _check(w, pl, "negotiation", 0.30 + p.influence() * 0.3 - lev)
    if not ok:
        _adjust(p, "debt", -0.1)
        return [f"{p.name} put you off. The debt is still there, but thinner."]
    _adjust(p, "debt", -0.35)
    nat = w.nations.get(p.nation)
    effects = []
    if nat and p.role in ("finance_minister", "head_of_state", "head_of_government"):
        amount = nat.treasury * 0.02
        nat.treasury -= amount
        pl.earn(amount, f"favour from {p.name}", w.clock.day, dirty=True)
        effects.append(f"A state contract worth {fmt_money(amount)} finds its way to you.")
    elif nat and p.role in ("general", "defence_minister"):
        nat.army_loyalty = clamp01(nat.army_loyalty - 0.06)
        effects.append(f"Officers in {nat.name} now take your calls directly.")
    elif p.role in ("editor", "media_baron"):
        org = next((o for o in w.orgs.values() if o.leader == p.id), None)
        if org:
            org.bias = {ax: lerp(org.bias.get(ax, 0), pl.me(w).ideology.get(ax, 0), 0.4)
                        for ax in AXES}
            effects.append(f"{org.name} begins running your line.")
    elif p.role in ("judge", "prosecutor", "police_chief"):
        _heat(pl, -0.08)
        effects.append("A file with your name on it is quietly misplaced.")
    else:
        pl.earn(p.wealth * 0.05, f"favour from {p.name}", w.clock.day)
        effects.append("They pay what they can.")
    return [f"{p.name}: \"{ask or 'Consider it done'}.\""] + ["  " + e for e in effects]


@action("network", "social", ap=1, money=8000, usage="network",
        desc="Work a room. Meet whoever happens to matter here.")
def act_network(w, pl, args):
    rng = w.rng.sub("network")
    p = pl.me(w)
    here = [q for q in w.people.values() if q.alive and q.region == p.region and q.id != PLAYER_ID]
    if not here:
        raise ActionError("There is nobody here worth knowing.")
    n = 1 + int(pl.skill(w, "networking") * 4)
    met = rng.weighted_sample(here, [q.influence() + 0.1 for q in here], min(n, len(here)))
    out = ["You spend the evening among people who matter here."]
    for q in met:
        q.knows[PLAYER_ID] = clamp01(q.knows.get(PLAYER_ID, 0) + 0.15)
        _adjust(q, "trust", 0.04)
        pl.contacts[q.id] = clamp01(pl.contacts.get(q.id, 0) + 0.15)
        out.append(f"  {ui.pad(q.name, 26)} {ui.pad(q.describe_role(), 22)} "
                   f"{ui.meter(q.influence(), 8)}")
    pl.fame = clamp01(pl.fame + 0.002)
    return out


@action("speech", "media", ap=2, money=60000, aliases=("rally", "address"),
        usage="speech <theme>", desc="Speak in public and move a nation's mood.")
def act_speech(w, pl, args):
    from .sim_society import add_narrative
    p = pl.me(w)
    nat = w.nations.get(p.nation)
    if nat is None:
        raise ActionError("You are not standing in any country.")
    theme = args or "the state of things"
    reach = clamp01(0.02 + pl.skill(w, "oratory") * 0.5 + pl.fame * 0.5
                    + (0.25 if "mass_following" in pl.perks else 0)
                    + (0.15 if "media_gravity" in pl.perks else 0))
    ok, margin = _check(w, pl, "oratory", 0.30 + (1 - nat.media_freedom) * 0.3)
    if not ok:
        pl.fame = clamp01(pl.fame - 0.005)
        return [f"You spoke about {theme}. It did not land."]
    kind = "hope" if pl.me(w).ideology.get("social", 0) > 0 else "grievance"
    n = add_narrative(w, kind, f"{p.name} on {theme}.", subject=PLAYER_ID,
                      origin=PLAYER_ID, seed_nation=nat.id,
                      seed=reach * (0.6 + margin), credibility=clamp01(0.5 + reach))
    pl.fame = clamp01(pl.fame + 0.02 + reach * 0.05)
    followers = pl.flags.get("followers", 0.0) + nat.pop * reach * 0.006 * (1 + margin)
    pl.flags["followers"] = followers
    nat.opinion["youth"] = clamp(nat.opinion.get("youth", 0) + reach * 0.2, -1, 1)
    if nat.repression > 0.5 and w.rng.sub("speech").chance(nat.repression * 0.35):
        _heat(pl, 0.06)
        return [f"You speak on {theme} to a crowd of {fmt_num(nat.pop * reach * 0.02)}.",
                ui.c("  The security services filmed all of it.", "R"),
                f"  Followers: {fmt_num(followers)}."]
    return [f"You speak on {theme}. The clip travels.",
            f"  Reach {fmt_pct(reach)} of {nat.name}. Followers: {ui.c(fmt_num(followers), 'G')}.",
            f"  Fame {fmt_pct(pl.fame)}."]


# ===========================================================================
#  COVERT
# ===========================================================================
def _launch(w, pl, kind: str, target, tkind: str, budget: float | None = None, meta=None):
    from .sim_covert import launch_op, op_difficulty
    d = OPS[kind]
    cost = _cost_scaled(budget if budget is not None else d["cost"], pl)
    if cost > pl.money:
        raise ActionError(f"That operation needs {fmt_money(cost)}; you have {fmt_money(pl.money)}.")
    pl.spend(cost, f"op:{kind}", w.clock.day)
    skill = pl.skill(w, d["skill"])
    for aid in pl.assets:
        a = w.people.get(aid)
        if a and a.alive and a.nation == getattr(target, "nation", getattr(target, "id", None)):
            skill = clamp01(skill + 0.06)
    op = launch_op(w, PLAYER_ID, kind, target.id, tkind, skill, cost, pl.assets, meta)
    diff = op_difficulty(w, kind, target, tkind)
    return op, diff


def _op_action(name, kind, cat="covert", ap=1, aliases=(), tk="person", usage="", desc=""):
    @action(name, cat, ap=ap, aliases=aliases, usage=usage or f"{name} <target>", desc=desc)
    def _fn(w, pl, args, _kind=kind, _tk=tk):
        finder = {"person": _person, "nation": _nation, "org": _org, "region": _region}[_tk]
        target = finder(w, args)
        op, diff = _launch(w, pl, _kind, target, _tk)
        return [f"Operation {ui.c(op.codename, 'W', 'b')} is running against "
                f"{getattr(target, 'name', target.id)}.",
                f"  Difficulty {ui.tint(fmt_pct(diff), diff, 0, 1, good_high=False)}, "
                f"your skill {fmt_pct(op.skill)}, "
                f"resolves in {op.eta - w.clock.day} days.",
                ui.c(f"  {OPS[_kind]['d']}", "K")]
    return _fn


_op_action("surveil", "surveil", aliases=("watch",), desc="Build a pattern of life on a target.")
_op_action("recruit_asset", "recruit_asset", ap=2, aliases=("turn",),
           desc="Turn an insider into your source.")
_op_action("blackmail", "blackmail", desc="Convert a secret you hold into obedience.")
_op_action("assassinate", "assassinate", ap=2, aliases=("kill",),
           desc="Remove a person permanently.")
_op_action("kidnap", "kidnap", ap=2, desc="Take someone off the board.")
_op_action("seduce", "seduce_target", desc="Build a relationship purely as an access route.")
_op_action("leak", "leak", cat="media", desc="Give a secret to a journalist at the right moment.")
_op_action("frame", "frame_rival", ap=2, desc="Make an enemy's downfall look like their own doing.")
_op_action("plant", "plant_evidence", desc="Manufacture a paper trail that convicts.")
_op_action("extract", "extract", desc="Pull one of your people out before they are taken.")
_op_action("steal_tech", "steal_tech", tk="nation", aliases=("espionage",),
           desc="Exfiltrate a national research programme.")
_op_action("hack", "cyber_intrude", tk="nation", desc="Pre-position access in critical infrastructure.")
_op_action("sabotage", "sabotage", tk="region", desc="Take an industrial or military asset offline.")
_op_action("arm_rebels", "arm_insurgents", ap=2, tk="region",
           desc="Supply an insurgency with weapons and money.")
_op_action("counterintel", "counterintel", tk="nation", aliases=("sweep",),
           desc="Hunt for penetration of your own organisation.")


@action("rob", "covert", ap=1, aliases=("steal",), usage="rob <nation|org|person>",
        desc="Move money out of somewhere it is being watched.")
def act_rob(w, pl, args):
    target = w.find_org(args) or w.find_nation(args) or w.find_person(args)
    if target is None:
        raise ActionError(f"Nothing to rob called {args!r}.")
    tk = "org" if target in w.orgs.values() else ("nation" if target in w.nations.values() else "person")
    op, diff = _launch(w, pl, "steal_funds", target, tk)
    return [f"Operation {ui.c(op.codename, 'W', 'b')} against {target.name}: "
            f"difficulty {fmt_pct(diff)}, {op.eta - w.clock.day} days."]


@action("bribe", "covert", ap=1, usage="bribe <person> | <amount>",
        desc="Buy a decision outright. Offer too little and they remember you tried.")
def act_bribe(w, pl, args):
    who, amt = _split(args)
    p = _person(w, who)
    try:
        amount = float(amt.replace(",", "").replace("$", "")) if amt else 0.0
    except ValueError:
        raise ActionError("Give an amount: bribe <person> | 2500000")
    if amount <= 0:
        est = p.influence() * 4.2e7 * (1.6 - p.corruptibility)
        return [f"{p.name} would plausibly want somewhere near {fmt_money(est)}.",
                "  Offer with: bribe <name> | <amount>"]
    op, diff = _launch(w, pl, "bribe", p, "person", budget=amount)
    return [f"The offer is made through intermediaries. {op.eta - w.clock.day} days for an answer."]


@action("disinfo", "media", ap=1, aliases=("smear", "propaganda"),
        usage="disinfo <nation> | <story>", desc="Push a fabricated narrative into the world.")
def act_disinfo(w, pl, args):
    where, story = _split(args)
    nat = _nation(w, where)
    kinds = list(NARRATIVE_KINDS)
    kind = "conspiracy"
    for k in kinds:
        if story.lower().startswith(k):
            kind = k
            story = story[len(k):].strip(": ")
            break
    op, diff = _launch(w, pl, "disinfo", nat, "nation",
                       meta={"narrative": kind, "text": story or "An anonymous dossier circulates."})
    return [f"Operation {ui.c(op.codename, 'W', 'b')}: seeding a {kind} in {nat.name}.",
            f"  {op.eta - w.clock.day} days until it takes or dies."]


@action("false_flag", "covert", ap=3, usage="false_flag <victim> | <blame>",
        desc="Stage an attack and attribute it to a third party.")
def act_false_flag(w, pl, args):
    victim, blame = _split(args)
    v = _nation(w, victim)
    b = _nation(w, blame)
    op, diff = _launch(w, pl, "false_flag", v, "nation", meta={"blame": b.id})
    return [f"Operation {ui.c(op.codename, 'W', 'b')}: {v.name} will believe {b.name} struck them.",
            ui.c("  If this is traced to you, there is no version of the story you survive.", "R")]


@action("coup", "covert", ap=3, usage="coup <nation> [| figurehead]",
        desc="Assemble officers, a broadcaster, and a list of names.")
def act_coup(w, pl, args):
    where, fig = _split(args)
    nat = _nation(w, where)
    figure = w.find_person(fig) if fig else None
    op, diff = _launch(w, pl, "coup_prep", nat, "nation",
                       meta={"figurehead": figure.id if figure else None})
    return [f"Operation {ui.c(op.codename, 'W', 'b')}: a coup in {nat.name}.",
            f"  Army loyalty to the current government: {fmt_pct(nat.army_loyalty)}.",
            f"  Difficulty {fmt_pct(diff)}. {op.eta - w.clock.day} days of preparation.",
            ui.c("  If it fails, everyone you touched will be shot.", "R")]


# ===========================================================================
#  ECONOMIC
# ===========================================================================
@action("found", "econ", ap=2, aliases=("charter",), usage="found <kind> | <name>",
        desc="Charter a company, bank, party, faith, syndicate, movement or agency.")
def act_found(w, pl, args):
    kind, name = _split(args)
    kind = (kind or "corp").lower()
    valid = ("corp", "bank", "party", "faith", "syndicate", "media", "movement", "agency", "ngo")
    if kind not in valid:
        raise ActionError(f"Kinds: {', '.join(valid)}")
    p = pl.me(w)
    nat = w.nations.get(p.nation)
    if nat is None:
        raise ActionError("You need to be somewhere with a government to register anything.")
    seed = {"corp": 2.5e6, "bank": 4.0e7, "party": 8e5, "faith": 2e5, "syndicate": 1.2e6,
            "media": 6e6, "movement": 3e5, "agency": 1.5e7, "ngo": 5e5}[kind]
    seed = _cost_scaled(seed, pl)
    if pl.money < seed:
        raise ActionError(f"Founding a {kind} takes {fmt_money(seed)} of working capital.")
    pl.spend(seed, f"found {kind}", w.clock.day)
    oid = w.nid("O")
    label = name or {"corp": N.corp_name(w.rng.sub("found"), nat.culture),
                     "party": N.party_name(w.rng.sub("found"), nat.culture),
                     "faith": N.faith_name(w.rng.sub("found"), nat.culture),
                     "media": N.outlet_name(w.rng.sub("found"),
                                            w.cities[p.city].name if p.city in w.cities else nat.name),
                     }.get(kind, f"the {N.word(w.rng.sub('found'), nat.culture, 2)} {kind.title()}")
    o = Org(oid, label, "corp" if kind == "movement" else kind, nat.id)
    if kind == "movement":
        o.kind = "movement"
    o.hq = p.city
    o.founded = w.clock.day
    o.leader = PLAYER_ID
    o.player_owned = True
    o.player_stake = 1.0
    o.cash = seed * 0.85
    o.valuation = seed
    o.shares = 1e6
    o.share_price = seed / 1e6
    o.ideology = dict(p.ideology)
    o.loyalty = 1.0
    w.orgs[oid] = o
    pl.orgs.append(oid)
    pl.holdings[oid] = 1.0
    out = [ui.c(f"{label} is chartered in {nat.name}.", "G", "b")]
    if kind == "corp":
        o.industries = {}
        o.revenue = 0.0
        out.append("  Give it something to do: 'expand <name> | <industry>'.")
    elif kind == "party":
        nat.parties.append(oid)
        o.assets["seats"] = 0.0
        o.assets["support"] = 0.01
        out.append(f"  It will contest the next election in {nat.name} "
                   f"({(nat.next_election - w.clock.day) // 30} months away).")
    elif kind == "faith":
        from .entities import Faith
        fid = w.nid("F")
        f = Faith(fid, label, w.rng.sub("found").weighted_dict({k: 1.0 for k in FAITH_DOCTRINES}))
        f.founded = w.clock.day
        f.player_founded = True
        f.ideology = dict(p.ideology)
        f.head = PLAYER_ID
        w.faiths[fid] = f
        o.assets["faith"] = fid
        pl.faith = fid
        out.append(f"  Doctrine: {f.doctrine}. Preach it with 'preach'.")
    elif kind == "movement":
        pl.movement = oid
        o.assets["followers"] = pl.flags.get("followers", 0.0)
        out.append("  Grow it with speeches, grievance, and results.")
    elif kind == "syndicate":
        o.rackets = {}
        o.secrecy = 0.7
        out.append("  Add rackets with 'racket <name> | <kind>'.")
    elif kind == "agency":
        o.secrecy = 0.85
        out.append("  A private intelligence service. It improves every operation you run.")
    return out


@action("expand", "econ", ap=1, usage="expand <org> | <industry> [| amount]",
        desc="Put capital into an industry through one of your companies.")
def act_expand(w, pl, args):
    parts = _split(args, 3)
    o = _org(w, parts[0])
    if o.id not in pl.orgs and pl.holdings.get(o.id, 0) < 0.5:
        raise ActionError("You do not control that organisation.")
    ind = parts[1]
    if ind not in INDUSTRIES:
        near = [i for i in INDUSTRIES if i.startswith(ind.lower())]
        if len(near) != 1:
            return ([ui.c("Industries:", "b")] + ui.columns(sorted(INDUSTRIES), 4))
        ind = near[0]
    try:
        amount = float(parts[2].replace(",", "").replace("$", "")) if parts[2] else o.cash * 0.5
    except ValueError:
        raise ActionError("Amount must be a number.")
    amount = min(amount, o.cash)
    if amount < 1e5:
        raise ActionError("Not enough capital in that entity to build anything.")
    d = INDUSTRIES[ind]
    if d["tech"] and d["tech"] not in pl.techs:
        nat = w.nations.get(o.nation)
        if nat is None or d["tech"] not in nat.techs:
            raise ActionError(f"{ind} requires {d['tech'].replace('_', ' ')}, which nobody here has.")
    o.cash -= amount
    added = amount / 6.5e4 / max(d["capital"], 0.2)
    o.industries[ind] = o.industries.get(ind, 0.0) + added
    o.revenue += added * 240
    nat = w.nations.get(o.nation)
    rs = [w.regions[r] for r in (nat.regions if nat else []) if r in w.regions]
    from .io_balance import region_suitability
    best = max(rs, key=lambda r: region_suitability(w, r, ind), default=None)
    if best is not None:
        best.capacity[ind] = best.capacity.get(ind, 0.0) + added
        best.__dict__["_plan"] = None
        o.regions[best.id] = o.regions.get(best.id, 0.0) + added
    return [f"{o.name} commits {fmt_money(amount)} to {ind.replace('_', ' ')}"
            + (f" in {best.name}." if best else "."),
            f"  {fmt_num(added)} jobs created. Projected revenue "
            f"{fmt_money(o.revenue * 360)}/yr."]


@action("invest", "econ", ap=1, usage="invest <org> | <amount>",
        desc="Buy equity in a listed company.")
def act_invest(w, pl, args):
    who, amt = _split(args)
    o = _org(w, who)
    if not o.public:
        raise ActionError(f"{o.name} is not listed. You would have to buy it outright: 'acquire'.")
    try:
        amount = float(amt.replace(",", "").replace("$", ""))
    except ValueError:
        raise ActionError("invest <org> | <amount>")
    if amount > pl.money:
        raise ActionError(f"You have {fmt_money(pl.money)}.")
    frac = amount / max(o.valuation, 1.0)
    if frac > 0.35:
        frac = 0.35
        amount = o.valuation * 0.35
        note = "  A block that size moves the price; you got 35% and paid for it."
    else:
        note = ""
    pl.spend(amount, f"equity in {o.name}", w.clock.day)
    pl.holdings[o.id] = pl.holdings.get(o.id, 0.0) + frac
    o.owners[PLAYER_ID] = pl.holdings[o.id]
    o.player_stake = pl.holdings[o.id]
    o.share_price *= 1 + frac * 0.4
    o.valuation = o.share_price * o.shares
    lines = [f"You hold {fmt_pct(pl.holdings[o.id])} of {o.name} "
             f"(valuation {fmt_money(o.valuation)})."]
    if note:
        lines.append(note)
    if pl.holdings[o.id] > 0.5 and o.id not in pl.orgs:
        pl.orgs.append(o.id)
        o.player_owned = True
        lines.append(ui.c("  You now control the board.", "G"))
    return lines


@action("divest", "econ", ap=1, aliases=("sell",), usage="divest <org> [| fraction]",
        desc="Liquidate a holding.")
def act_divest(w, pl, args):
    who, frac = _split(args)
    o = _org(w, who)
    have = pl.holdings.get(o.id, 0.0)
    if have <= 0:
        raise ActionError(f"You own none of {o.name}.")
    try:
        f = clamp01(float(frac)) if frac else 1.0
    except ValueError:
        f = 1.0
    sold = have * f
    proceeds = o.valuation * sold * 0.97
    pl.holdings[o.id] = have - sold
    if pl.holdings[o.id] < 1e-6:
        del pl.holdings[o.id]
        if o.id in pl.orgs:
            pl.orgs.remove(o.id)
            o.player_owned = False
    o.player_stake = pl.holdings.get(o.id, 0.0)
    o.share_price *= 1 - sold * 0.3
    o.valuation = max(1e4, o.share_price * o.shares)
    pl.earn(proceeds, f"sold {o.name}", w.clock.day)
    return [f"Sold {fmt_pct(sold)} of {o.name} for {fmt_money(proceeds)}."]


@action("acquire", "econ", ap=2, aliases=("takeover",), usage="acquire <org>",
        desc="Buy an organisation outright, willing or not.")
def act_acquire(w, pl, args):
    o = _org(w, args)
    price = o.valuation * (1.35 if o.public else 1.15)
    if pl.money < price:
        raise ActionError(f"A controlling stake in {o.name} costs about {fmt_money(price)}; "
                          f"you have {fmt_money(pl.money)}.")
    resist = 0.0
    if o.leader and o.leader in w.people:
        boss = w.people[o.leader]
        resist = clamp01(boss.loyalty * 0.5 - boss.disposition() * 0.3)
    ok, margin = _check(w, pl, "finance", 0.25 + resist)
    if not ok:
        pl.spend(price * 0.05, "failed bid", w.clock.day)
        return [f"The board of {o.name} rejected your approach. You are out the fees."]
    pl.spend(price, f"acquired {o.name}", w.clock.day)
    o.player_owned = True
    o.player_stake = 1.0
    pl.holdings[o.id] = 1.0
    if o.id not in pl.orgs:
        pl.orgs.append(o.id)
    o.owners = {PLAYER_ID: 1.0}
    o.leader = PLAYER_ID
    return [ui.c(f"{o.name} is yours for {fmt_money(price)}.", "G", "b"),
            f"  Revenue {fmt_money(o.revenue * 360)}/yr, cash {fmt_money(o.cash)}, "
            f"influence {fmt_pct(o.influence)}."]


@action("launder", "econ", ap=1, usage="launder [amount]",
        desc="Wash dirty money through structures that do not invite questions.")
def act_launder(w, pl, args):
    if pl.dirty_money <= 0:
        raise ActionError("Nothing of yours currently smells.")
    try:
        amount = float(args.replace(",", "").replace("$", "")) if args else pl.dirty_money
    except ValueError:
        amount = pl.dirty_money
    amount = min(amount, pl.dirty_money)
    banks = [o for o in w.orgs.values() if o.kind == "bank" and (o.player_owned
                                                                or pl.holdings.get(o.id, 0) > 0.2)]
    quality = clamp01(0.3 + pl.skill(w, "accounting") * 0.5 + 0.2 * bool(banks)
                      + (0.25 if "quantum_ledger" in pl.perks else 0)
                      + (0.2 if "shadow_ledger" in pl.techs else 0))
    fee = amount * (0.28 - 0.18 * quality)
    pl.dirty_money -= amount
    pl.money -= fee
    _heat(pl, 0.02 * (1 - quality))
    return [f"{fmt_money(amount)} comes back clean. The wash cost {fmt_money(fee)} "
            f"({fmt_pct(fee / max(amount, 1))}).",
            f"  Remaining dirty: {fmt_money(pl.dirty_money)}."]


@action("racket", "econ", ap=1, usage="racket <syndicate> | <kind>",
        desc="Open a criminal line of business.")
def act_racket(w, pl, args):
    who, kind = _split(args)
    o = _org(w, who)
    if o.kind != "syndicate" or o.id not in pl.orgs:
        raise ActionError("That is not a syndicate you control.")
    if kind not in RACKETS:
        return ([ui.c("Rackets:", "b")]
                + [f"  {ui.pad(k, 14)}{ui.pad('margin ' + fmt_pct(d['margin']), 16)}"
                   f"heat {fmt_pct(d['heat'])}  {d['d']}" for k, d in RACKETS.items()])
    d = RACKETS[kind]
    ok, margin = _check(w, pl, d["skill"], 0.35 + o.heat * 0.4)
    if not ok:
        o.heat = clamp01(o.heat + 0.08)
        return [f"The move into {kind} went badly. Heat on {o.name} is now {fmt_pct(o.heat)}."]
    o.rackets[kind] = clamp01(o.rackets.get(kind, 0.0) + 0.18 + margin * 0.25)
    pl.dirty_money += 0.0
    return [f"{o.name} is now running {kind} at {fmt_pct(o.rackets[kind])} of local capacity.",
            ui.c(f"  {d['d']}", "K")]


@action("corner", "econ", ap=2, usage="corner <good> | <amount>",
        desc="Buy a commodity heavily enough to move the world price.")
def act_corner(w, pl, args):
    good, amt = _split(args)
    if good not in GOODS:
        return ([ui.c("Goods:", "b")] + ui.columns(sorted(GOODS), 4))
    try:
        amount = float(amt.replace(",", "").replace("$", ""))
    except ValueError:
        raise ActionError("corner <good> | <amount of money>")
    if amount > pl.money:
        raise ActionError(f"You have {fmt_money(pl.money)}.")
    m = w.market
    world_daily = sum(n.demand.get(good, 0.0) for n in w.living_nations())
    price = m.p(good)
    units = amount / max(price, 1e-6)
    grip = clamp01(units / max(world_daily * 30, 1e-6))
    pl.spend(amount, f"cornering {good}", w.clock.day)
    pl.flags.setdefault("positions", {})[good] = \
        pl.flags.get("positions", {}).get(good, 0.0) + units
    m.price[good] = min(GOODS[good]["base"] * 12, price * (1 + grip * 0.9))
    return [f"You take delivery of {fmt_num(units)} units of {good} at {fmt_money(price)}.",
            f"  That is {fmt_pct(grip)} of a month of world demand. "
            f"Price moves to {fmt_money(m.p(good))}.",
            "  Sell with 'unwind <good>'."]


@action("unwind", "econ", ap=1, usage="unwind <good>", desc="Liquidate a commodity position.")
def act_unwind(w, pl, args):
    pos = pl.flags.get("positions", {})
    if args not in pos:
        raise ActionError(f"No position in {args!r}. Holding: {', '.join(pos) or 'nothing'}.")
    units = pos.pop(args)
    price = w.market.p(args)
    proceeds = units * price * 0.96
    w.market.price[args] = max(GOODS[args]["base"] * 0.18, price * 0.92)
    pl.earn(proceeds, f"unwound {args}", w.clock.day)
    return [f"Sold {fmt_num(units)} of {args} at {fmt_money(price)} for {fmt_money(proceeds)}."]


@action("donate", "econ", ap=1, usage="donate <nation|org> | <amount>",
        desc="Give money where it buys something other than goods.")
def act_donate(w, pl, args):
    who, amt = _split(args)
    target = w.find_org(who) or w.find_nation(who)
    if target is None:
        raise ActionError(f"Nobody called {who!r}.")
    try:
        amount = float(amt.replace(",", "").replace("$", ""))
    except ValueError:
        raise ActionError("donate <target> | <amount>")
    if amount > pl.money:
        raise ActionError(f"You have {fmt_money(pl.money)}.")
    pl.spend(amount, f"donation to {target.name}", w.clock.day)
    if target in w.nations.values():
        target.treasury += amount
        target.__dict__["_player_goodwill"] = target.__dict__.get("_player_goodwill", 0.0) \
            + amount / max(target.gdp, 1)
        pl.fame = clamp01(pl.fame + 0.004)
        return [f"{fmt_money(amount)} to the treasury of {target.name}. "
                f"They will remember it for a while."]
    target.cash += amount
    target.influence = clamp01(target.influence + amount / max(target.valuation, 1e6) * 0.1)
    if target.kind == "party":
        target.assets["support"] = clamp01(target.assets.get("support", 0.1)
                                           + amount / max(w.nations[target.nation].gdp, 1) * 0.4)
        return [f"{fmt_money(amount)} to {target.name}. Their polling improves; "
                f"support now {fmt_pct(target.assets['support'])}."]
    return [f"{fmt_money(amount)} to {target.name}."]


# ===========================================================================
#  POLITICAL & STATE
# ===========================================================================
def _authority(w, pl, nat, need: float = 0.5) -> float:
    """How much of a nation's machinery the player can actually direct."""
    a = nat.player_control
    if pl.offices.get(nat.id) in ("head_of_state", "head_of_government"):
        a = max(a, 0.85)
    elif pl.offices.get(nat.id):
        a = max(a, 0.35)
    if w.people[PLAYER_ID].id == nat.head_of_state:
        a = max(a, 0.95)
    controlled = sum(1 for pid in pl.assets
                     if pid in w.people and w.people[pid].nation == nat.id
                     and w.people[pid].power > 0.5)
    a += controlled * 0.08
    return clamp01(a)


@action("stand", "politics", ap=2, money=2000000, aliases=("run", "campaign"),
        usage="stand <office>", desc="Contest an office. Requires an election or a vacancy.")
def act_stand(w, pl, args):
    p = pl.me(w)
    nat = w.nations.get(p.nation)
    if nat is None:
        raise ActionError("Nowhere to stand.")
    office = (args or "legislator").lower().replace(" ", "_")
    if office in ("head_of_state", "president", "leader"):
        office = "head_of_state"
    if office == "head_of_state" and not nat.is_democracy():
        raise ActionError(f"{nat.name} does not choose its leader by election. "
                          f"Try 'coup', or take the party that does choose.")
    party = next((w.orgs[o] for o in pl.orgs if o in w.orgs and w.orgs[o].kind == "party"), None)
    machine = (party.assets.get("support", 0.0) if party else 0.0)
    strength = clamp01(0.10 + pl.skill(w, "oratory") * 0.35 + pl.skill(w, "politics") * 0.3
                       + pl.fame * 0.4 + machine * 0.8
                       + clamp01(pl.money / max(nat.gdp * 20, 1)) * 0.3
                       - pl.heat * 0.4)
    difficulty = {"legislator": 0.30, "mayor": 0.35, "governor": 0.50,
                  "head_of_state": 0.72}.get(office, 0.45)
    ok, margin = _check(w, pl, "oratory", difficulty + (1 - nat.media_freedom) * 0.2, 0.16)
    ok = ok and w.rng.sub("elect").chance(clamp01(strength * 1.6))
    if not ok:
        pl.fame = clamp01(pl.fame + 0.01)
        return [f"You lost. {fmt_pct(strength)} was not enough of a machine.",
                "  Build support: speeches, a party, money, or people who owe you."]
    pl.offices[nat.id] = office
    p.role = office
    p.power = clamp01(max(p.power, {"legislator": 0.35, "mayor": 0.34, "governor": 0.5,
                                    "head_of_state": 0.95}.get(office, 0.4)))
    if office == "head_of_state":
        nat.head_of_state = PLAYER_ID
        nat.head_of_gov = PLAYER_ID
        nat.leader_since = w.clock.day
        nat.player_control = clamp01(nat.player_control + 0.6)
        if party:
            nat.ruling_party = party.id
            nat.coalition = [party.id]
        w.report(f"{p.name} is elected to lead {nat.name}.", "politics", nat.id, 1.0, ["player"])
    pl.fame = clamp01(pl.fame + 0.08)
    pl.note(w.clock.day, f"Took office as {office.replace('_', ' ')} of {nat.name}.")
    return [ui.c(f"You are {office.replace('_', ' ')} of {nat.name}.", "G", "b"),
            f"  Authority over the state: {fmt_pct(_authority(w, pl, nat))}."]


@action("policy", "politics", ap=1, usage="policy <nation> | <lever> | <value 0-1>",
        desc="Move a policy lever, if you have the authority to move it.")
def act_policy(w, pl, args):
    parts = _split(args, 3)
    nat = _nation(w, parts[0]) if parts[0] else pl.nation(w)
    if nat is None:
        raise ActionError("Which nation?")
    if not parts[1]:
        rows = [[k, POLICIES[k]["label"], f"{nat.policy[k]:.2f}",
                 f"{POLICIES[k]['lo']:.2f}-{POLICIES[k]['hi']:.2f}"] for k in POLICIES]
        return [ui.header(f"Policy — {nat.name}")] + ui.table(
            rows, ["lever", "meaning", "now", "range"], ["<", "<", ">", ">"])
    lever = parts[1]
    if lever not in POLICIES:
        near = [k for k in POLICIES if k.startswith(lever.lower())]
        if len(near) != 1:
            raise ActionError(f"No lever {lever!r}.")
        lever = near[0]
    auth = _authority(w, pl, nat)
    if auth < 0.30:
        raise ActionError(f"You have {fmt_pct(auth)} authority in {nat.name}. "
                          f"Not enough to set policy. Win an office, buy the cabinet, or take it.")
    try:
        val = float(parts[2])
    except ValueError:
        raise ActionError("Give a value between 0 and 1.")
    d = POLICIES[lever]
    old = nat.policy[lever]
    room = auth * 0.6
    new = clamp(old + clamp(val - old, -room, room), d["lo"], d["hi"])
    nat.policy[lever] = new
    cost = abs(new - old)
    nat.approval = clamp01(nat.approval - cost * 0.25 * (1 - auth))
    nat.legitimacy = clamp01(nat.legitimacy - cost * 0.10 * (1 - auth))
    return [f"{d['label']} in {nat.name}: {old:.2f} → {ui.c(f'{new:.2f}', 'G')}"
            + (f"  (capped by your {fmt_pct(auth)} authority)" if abs(val - new) > 0.01 else ""),
            f"  Approval cost: {fmt_pct(cost * 0.25 * (1 - auth))}."]


@action("purge", "politics", ap=2, usage="purge <nation> | <person>",
        desc="Remove an inconvenient official through the machinery of the state.")
def act_purge(w, pl, args):
    where, who = _split(args)
    nat = _nation(w, where)
    target = _person(w, who)
    auth = _authority(w, pl, nat)
    if auth < 0.5:
        raise ActionError(f"Purges need real control. You have {fmt_pct(auth)}.")
    ok, margin = _check(w, pl, "bureaucracy", 0.35 + target.power * 0.5 - auth * 0.3)
    if not ok:
        nat.army_loyalty = clamp01(nat.army_loyalty - 0.06)
        nat.legitimacy = clamp01(nat.legitimacy - 0.03)
        return [f"The move against {target.name} failed publicly. They are stronger for it."]
    old_role = target.describe_role()
    target.power = clamp01(target.power * 0.25)
    target.role = "citizen"
    for role, pid in list(nat.cabinet.items()):
        if pid == target.id:
            from .worldgen_social import make_person
            nat.cabinet[role] = make_person(w, w.rng.sub("purge"), nat.id, role).id
    nat.repression = clamp01(nat.repression + 0.04)
    nat.legitimacy = clamp01(nat.legitimacy - 0.02)
    nat.unrest = clamp01(nat.unrest + 0.01)
    return [f"{target.name} is removed as {old_role}. The file is sealed.",
            f"  {nat.name}: repression {fmt_pct(nat.repression)}, "
            f"legitimacy {fmt_pct(nat.legitimacy)}."]


@action("appoint", "politics", ap=1, usage="appoint <nation> | <person> | <role>",
        desc="Put your own person into a ministry.")
def act_appoint(w, pl, args):
    parts = _split(args, 3)
    nat = _nation(w, parts[0])
    target = _person(w, parts[1])
    role = parts[2].lower().replace(" ", "_")
    auth = _authority(w, pl, nat)
    if auth < 0.55:
        raise ActionError(f"Appointments need control of the executive. You have {fmt_pct(auth)}.")
    if role not in nat.cabinet and role not in ("head_of_government",):
        raise ActionError(f"Posts: {', '.join(nat.cabinet)}")
    nat.cabinet[role] = target.id
    target.role = role
    target.nation = nat.id
    target.power = clamp01(max(target.power, 0.55))
    target.loyalty_to = PLAYER_ID
    if target.id in pl.assets:
        nat.player_control = clamp01(nat.player_control + 0.06)
    return [f"{target.name} is now {role.replace('_', ' ')} of {nat.name}.",
            f"  Your control of the state: {fmt_pct(nat.player_control)}."]


@action("decree", "politics", ap=2, usage="decree <nation> | <what>",
        desc="Rule by fiat. Fast, and expensive in legitimacy.")
def act_decree(w, pl, args):
    where, what = _split(args)
    nat = _nation(w, where)
    auth = _authority(w, pl, nat)
    if auth < 0.7:
        raise ActionError("Decrees require near-total control of the executive.")
    nat.legitimacy = clamp01(nat.legitimacy - 0.05)
    nat.repression = clamp01(nat.repression + 0.05)
    nat.state_capacity = clamp01(nat.state_capacity + 0.02)
    nat.unrest = clamp01(nat.unrest + 0.02 * (1 - nat.repression))
    return [f"By decree of the executive of {nat.name}: \"{what or 'as ordered'}\".",
            f"  Legitimacy {fmt_pct(nat.legitimacy)}, repression {fmt_pct(nat.repression)}."]


@action("mobilise", "military", ap=1, aliases=("mobilize",), usage="mobilise <nation>",
        desc="Call up reserves and put the economy on a war footing.")
def act_mobilise(w, pl, args):
    nat = _nation(w, args) if args else pl.nation(w)
    if _authority(w, pl, nat) < 0.6:
        raise ActionError("You do not command that state's armed forces.")
    nat.mobilised = clamp01(nat.mobilised + 0.30)
    nat.readiness = clamp01(nat.readiness + 0.12)
    nat.set_policy("military", nat.get_policy("military") + 0.10)
    nat.set_policy("conscription", nat.get_policy("conscription") + 0.15)
    for r in w.nation_regions(nat.id):
        r.unrest = clamp01(r.unrest + 0.02)
    return [f"{nat.name} mobilises. Reserves {fmt_num(nat.reserves_men)}, "
            f"readiness {fmt_pct(nat.readiness)}.",
            "  The economy will feel this within the month."]


@action("declare_war", "military", ap=3, aliases=("war",),
        usage="declare_war <attacker> | <defender> | <goal>",
        desc="Start a war on someone else's behalf, or your own.")
def act_declare_war(w, pl, args):
    parts = _split(args, 3)
    a = _nation(w, parts[0])
    b = _nation(w, parts[1])
    goal = parts[2] or "punitive"
    if goal not in WAR_GOALS:
        return ([ui.c("War goals:", "b")]
                + [f"  {ui.pad(k, 16)}{d['d']}" for k, d in WAR_GOALS.items()])
    if _authority(w, pl, a) < 0.7:
        raise ActionError(f"You cannot commit {a.name} to a war. Authority: "
                          f"{fmt_pct(_authority(w, pl, a))}.")
    if b.id in a.at_war:
        raise ActionError("They are already at war.")
    from .sim_power import declare_war
    declare_war(w, a, b, goal, instigator=PLAYER_ID)
    pl.notoriety = clamp01(pl.notoriety + 0.05)
    return [ui.c(f"{a.name} declares war on {b.name}.", "R", "b"),
            f"  Goal: {WAR_GOALS[goal]['d']}",
            f"  Balance of force: {fmt_num(a.military_score())} vs {fmt_num(b.military_score())}."]


@action("peace", "military", ap=2, usage="peace <war id or nation>",
        desc="End a war you have the standing to end.")
def act_peace(w, pl, args):
    war = None
    for x in w.wars.values():
        if x.ended is None and (x.id.lower() == args.lower()
                                or any(args.lower() in w.nations[n].name.lower()
                                       for n in x.attackers + x.defenders if n in w.nations)):
            war = x
            break
    if war is None:
        raise ActionError("No matching active war.")
    sides = [w.nations[n] for n in war.attackers + war.defenders if n in w.nations]
    if not any(_authority(w, pl, n) > 0.6 for n in sides):
        raise ActionError("None of the belligerents answer to you.")
    from .sim_power import end_war
    winner = "attacker" if war.warscore > 0.12 else ("defender" if war.warscore < -0.12 else None)
    end_war(w, war, winner)
    return [f"{war.name} is over. Warscore was {war.warscore:+.2f}."]


@action("treaty", "politics", ap=1, usage="treaty <a> | <b> | <kind>",
        desc="Broker or sign an agreement between two states.")
def act_treaty(w, pl, args):
    parts = _split(args, 3)
    a = _nation(w, parts[0])
    b = _nation(w, parts[1])
    kind = parts[2]
    if kind not in TREATY_KINDS:
        return ([ui.c("Treaty kinds:", "b")]
                + [f"  {ui.pad(k, 16)}{d['d']}" for k, d in TREATY_KINDS.items()])
    auth = max(_authority(w, pl, a), _authority(w, pl, b))
    ok, margin = _check(w, pl, "diplomacy",
                        0.45 - a.relation(b.id) * 0.4 - auth * 0.4
                        + (0.3 if kind in ("alliance", "vassalage") else 0.0))
    if not ok:
        return [f"{a.name} and {b.name} could not be brought to terms."]
    a.treaties.setdefault(b.id, set()).add(kind)
    b.treaties.setdefault(a.id, set()).add(kind)
    bump = TREATY_KINDS[kind]["relation"]
    a.relations[b.id] = clamp(a.relation(b.id) + bump, -1, 1)
    b.relations[a.id] = clamp(b.relation(a.id) + bump, -1, 1)
    if kind == "vassalage":
        b.puppet_of = a.id
    pl.fame = clamp01(pl.fame + 0.01)
    return [f"{a.name} and {b.name} sign a {kind.replace('_', ' ')} agreement.",
            f"  Relations: {a.relation(b.id):+.2f}."]


@action("sanction", "politics", ap=1, usage="sanction <by> | <target>",
        desc="Cut a state out of the world economy.")
def act_sanction(w, pl, args):
    by, target = _split(args)
    a = _nation(w, by)
    b = _nation(w, target)
    if _authority(w, pl, a) < 0.6:
        raise ActionError(f"You do not set {a.name}'s foreign policy.")
    a.sanctions.add(b.id)
    a.relations[b.id] = clamp(a.relation(b.id) - 0.2, -1, 1)
    b.relations[a.id] = clamp(b.relation(a.id) - 0.25, -1, 1)
    return [f"{a.name} sanctions {b.name}.",
            f"  {b.name} trade openness will fall; expect shortages within weeks."]


@action("fund_research", "research", ap=1, usage="fund_research <nation|org> | <amount>",
        desc="Push money into a research programme.")
def act_fund_research(w, pl, args):
    who, amt = _split(args)
    target = w.find_nation(who) or w.find_org(who)
    if target is None:
        raise ActionError(f"Nobody called {who!r}.")
    try:
        amount = float(amt.replace(",", "").replace("$", ""))
    except ValueError:
        raise ActionError("fund_research <target> | <amount>")
    if amount > pl.money:
        raise ActionError(f"You have {fmt_money(pl.money)}.")
    pl.spend(amount, "research funding", w.clock.day)
    if target in w.nations.values():
        target.treasury += amount
        target.set_policy("research", target.get_policy("research") + 0.03)
        focus = target.research_focus or "unspecified programmes"
        return [f"{fmt_money(amount)} into {target.name}'s laboratories "
                f"(current focus: {focus.replace('_', ' ')})."]
    target.rnd += amount / 360
    target.cash += amount * 0.2
    return [f"{fmt_money(amount)} into R&D at {target.name}."]


@action("project", "research", ap=2, usage="project [<name>]",
        desc="Begin a megaproject. These are how the world actually changes.")
def act_project(w, pl, args):
    if not args:
        rows = []
        for k, d in RESEARCH_PROJECTS.items():
            have = all(t in pl.techs for t in d["p"])
            rows.append([ui.c(k, "G" if have else "K"), fmt_num(d["c"]),
                         ", ".join(t.replace("_", " ") for t in d["p"])])
        out = [ui.header("Megaprojects", "world-changing programmes")]
        out += ui.table(rows, ["project", "cost", "requires"])
        for k, d in RESEARCH_PROJECTS.items():
            out += ui.bullet(f"{k}: {d['d']}")
        running = [w.projects[p] for p in pl.projects if p in w.projects]
        if running:
            out.append("")
            out.append(ui.c("Under way:", "b"))
            for pr in running:
                out.append(f"  {ui.pad(pr.name, 24)}{ui.meter(pr.progress, 20)} "
                           f"{fmt_pct(pr.progress)}")
        return out
    if args not in RESEARCH_PROJECTS:
        raise ActionError(f"No project called {args!r}.")
    d = RESEARCH_PROJECTS[args]
    missing = [t for t in d["p"] if t not in pl.techs]
    if missing:
        raise ActionError(f"You lack: {', '.join(m.replace('_', ' ') for m in missing)}.")
    if any(w.projects[p].kind == args for p in pl.projects if p in w.projects):
        raise ActionError("Already under way.")
    pid = w.nid("PR")
    pr = Project(pid, args, args.replace("_", " ").title(), d["c"], PLAYER_ID)
    pr.started = w.clock.day
    pr.secret = True
    w.projects[pid] = pr
    pl.projects.append(pid)
    return [ui.c(f"{pr.name} begins.", "G", "b"), "  " + d["d"],
            f"  Total cost {fmt_num(d['c'])} research-units. Feed it with 'invest_project'."]


@action("invest_project", "research", ap=1, usage="invest_project <name> | <amount>",
        desc="Pour money and people into a megaproject.")
def act_invest_project(w, pl, args):
    who, amt = _split(args)
    pr = next((w.projects[p] for p in pl.projects
               if p in w.projects and who.lower() in w.projects[p].name.lower()), None)
    if pr is None:
        raise ActionError("No such project of yours. Run 'project' for the list.")
    try:
        amount = float(amt.replace(",", "").replace("$", ""))
    except ValueError:
        raise ActionError("invest_project <name> | <amount>")
    if amount > pl.money:
        raise ActionError(f"You have {fmt_money(pl.money)}.")
    pl.spend(amount, f"project {pr.name}", w.clock.day)
    labs = sum(o.rnd for o in w.orgs.values() if o.id in pl.orgs)
    units = amount / 3.2e6 * (1 + pl.skill(w, "engineering") * 0.6) * (1 + labs / max(amount, 1))
    pr.spent += amount
    pr.progress = clamp01(pr.progress + units / max(pr.cost, 1))
    out = [f"{pr.name}: {fmt_pct(pr.progress)} complete "
           f"({fmt_money(pr.spent)} committed)."]
    if pr.progress >= 1.0 and not pr.done:
        pr.done = True
        out += _complete_project(w, pl, pr)
    return out


def _complete_project(w, pl, pr):
    out = [ui.c(f"\n  {pr.name.upper()} IS COMPLETE.", "G", "b")]
    p = pl.me(w)
    if pr.kind == "singularity_engine":
        w.flags["player_singularity"] = w.clock.day
        pl.flags["singularity"] = True
        out.append("  Every research programme you touch now runs at machine speed.")
    elif pr.kind == "panopticon":
        pl.flags["panopticon"] = True
        for q in w.people.values():
            for s in q.secrets:
                if PLAYER_ID not in s["known_by"]:
                    s["known_by"].append(PLAYER_ID)
        out.append("  There is no longer a private conversation anywhere on Earth.")
    elif pr.kind == "eternal_program":
        pl.flags["eternal"] = True
        p.health = 1.0
        out.append("  Your biological clock has been stopped. Nobody else's has.")
    elif pr.kind == "world_reserve":
        pl.flags["world_reserve"] = True
        out.append("  Every central bank on the planet now clears through a system you own.")
    elif pr.kind == "doctrine_engine":
        pl.flags["doctrine_engine"] = True
        out.append("  You can now author what eight billion people believe, one person at a time.")
    elif pr.kind == "orbital_ring":
        pl.flags["orbital_ring"] = True
        out.append("  You are the landlord of the only road off this planet.")
    w.report(f"{p.name} completes {pr.name}.", "tech", weight=1.0, tags=["megaproject", "player"])
    pl.note(w.clock.day, f"Completed {pr.name}.")
    return out


@action("preach", "media", ap=1, money=30000, usage="preach [theme]",
        desc="Spread the faith or movement you founded.")
def act_preach(w, pl, args):
    if not pl.faith and not pl.movement:
        raise ActionError("You have no faith or movement. Found one first.")
    p = pl.me(w)
    nat = w.nations.get(p.nation)
    r = w.regions.get(p.region)
    if nat is None or r is None:
        raise ActionError("Nowhere to preach.")
    ok, margin = _check(w, pl, "theology" if pl.faith else "oratory", 0.35)
    if not ok:
        return ["The message did not carry today."]
    gain = (0.008 + margin * 0.02) * (1 + pl.skill(w, "oratory"))
    if pl.faith:
        f = w.faiths[pl.faith]
        r.faiths[pl.faith] = clamp01(r.faiths.get(pl.faith, 0.0) + gain)
        tot = sum(r.faiths.values()) or 1.0
        r.faiths = {k: v / tot for k, v in r.faiths.items()}
        f.adherents = sum(x.pop * x.faiths.get(pl.faith, 0.0) for x in w.regions.values())
        return [f"You preach in {r.name}. {f.name} now claims {fmt_pct(r.faiths[pl.faith])} "
                f"of the region and {fmt_num(f.adherents)} souls worldwide."]
    o = w.orgs[pl.movement]
    o.assets["followers"] = o.assets.get("followers", 0.0) + r.pop * gain
    pl.flags["followers"] = o.assets["followers"]
    o.reach = clamp01(o.reach + gain * 0.5)
    return [f"You speak for the movement in {r.name}. "
            f"Followers: {fmt_num(o.assets['followers'])}."]
