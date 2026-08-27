#!/usr/bin/env python3
"""Dump reference tables from grimoire.content_* as Markdown.

Throwaway generator for docs/CONTENT.md — run it from the repo root with
`python3 docs/gen_tables.py > docs/CONTENT.md` (after pasting the file's
opening prose back in, or just editing the header below) whenever the
content tables change and the reference doc needs refreshing. It imports
only the content_* modules (no world state, no RNG), so it is safe and
fast to run any time.
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from grimoire.content_econ import BIOMES, GOODS, INDUSTRIES, RESOURCE_GATES
from grimoire.content_social import (
    AXES, BACKGROUNDS, GOV_TYPES, IDEOLOGIES, PERKS, POLICIES, SKILLS, TRAITS,
)
from grimoire.content_conflict import (
    DISEASES, OPS, RACKETS, TREATY_KINDS, UNITS, WAR_GOALS,
)
from grimoire.content_tech import FIELDS, RESEARCH_PROJECTS, TECHS


def money(n: float) -> str:
    n = float(n)
    for div, suf in ((1e12, "T"), (1e9, "B"), (1e6, "M"), (1e3, "K")):
        if abs(n) >= div:
            s = f"{n / div:.2f}".rstrip("0").rstrip(".")
            return f"${s}{suf}"
    return f"${n:.0f}"


def esc(s: str) -> str:
    return str(s).replace("|", "\\|")


def table(headers: list[str], rows: list[list[str]]) -> str:
    out = ["| " + " | ".join(headers) + " |",
           "|" + "|".join(["---"] * len(headers)) + "|"]
    for r in rows:
        out.append("| " + " | ".join(esc(c) for c in r) + " |")
    return "\n".join(out)


TIER_NAME = {0: "raw", 1: "refined", 2: "manufactured", 3: "advanced"}


def commodities() -> str:
    out = ["## Commodities", "",
           f"All {len(GOODS)} tradeable goods, grouped by category. `tier` is raw (0) through "
           "advanced/strategic (3). `elast` is price elasticity of demand — higher means price "
           "swings faster with a supply/demand gap. `perish` is the fraction of a stockpile lost "
           "per day (power at 1.000 cannot be warehoused at all: it is generated and consumed the "
           "same day). `strat` is strategic weight, which drives sanctions targeting and war goals. "
           "`bulk` scales shipping cost.", ""]
    cats: dict[str, list[str]] = {}
    for g, d in GOODS.items():
        cats.setdefault(d["cat"], []).append(g)
    for cat in sorted(cats):
        out.append(f"### {cat}")
        out.append("")
        rows = []
        for g in cats[cat]:
            d = GOODS[g]
            rows.append([g, TIER_NAME[d["tier"]], money(d["base"]), f"{d['elast']:.2f}",
                         f"{d['perish']:.3f}", f"{d['strat']:.2f}", f"{d['bulk']:.1f}"])
        rows.sort(key=lambda r: r[0])
        out.append(table(["good", "tier", "base price", "elasticity", "perish/day",
                           "strategic", "bulk"], rows))
        out.append("")
    return "\n".join(out)


def industries() -> str:
    out = ["## Industries", "",
           f"All {len(INDUSTRIES)} production recipes. `out` is the good produced (one unit of "
           "capacity is one worker-equivalent job). `inputs` lists physical inputs consumed per "
           "unit of output. `capital` and `skill` (0..1) describe how capital- and "
           "education-intensive the process is; `dirty` (0..1) drives pollution; `land` is land "
           "use per unit; `gates on` names the regional resource endowment (from `RESOURCE_GATES`) "
           "that must be present for a region to host the industry at all, where one applies. "
           "`tech` names a prerequisite technology.", ""]
    rows = []
    for ind, d in sorted(INDUSTRIES.items()):
        inputs = ", ".join(f"{g} {q:g}" for g, q in d["inp"].items()) or "—"
        gate = RESOURCE_GATES.get(ind, "—")
        tech = d["tech"] or "—"
        flag = " (illegal)" if d.get("illegal") else ""
        rows.append([ind + flag, d["out"], inputs, f"{d['capital']:.2f}", f"{d['skill']:.2f}",
                     f"{d['dirty']:.2f}", f"{d['land']:.1f}", gate, tech])
    out.append(table(["industry", "out", "inputs (per unit)", "capital", "skill", "dirty",
                       "land", "gates on", "tech"], rows))
    out.append("")
    return "\n".join(out)


def tech_tree() -> str:
    out = ["## Technology tree", "",
           f"All {len(TECHS)} technologies, grouped by field, in ascending cost order within a "
           "field. `cost` is research-points required (see docs/SYSTEMS.md for how nations and "
           "the player accumulate research points). `prereqs` lists technologies that must "
           "already be held.", ""]
    by_field: dict[str, list[str]] = {}
    for t, d in TECHS.items():
        by_field.setdefault(d["f"], []).append(t)
    for field in FIELDS:
        techs = by_field.get(field, [])
        if not techs:
            continue
        techs.sort(key=lambda t: TECHS[t]["c"])
        out.append(f"### {field}")
        out.append("")
        rows = []
        for t in techs:
            d = TECHS[t]
            pre = ", ".join(d["p"]) or "—"
            rows.append([t, str(d["c"]), pre, d["d"]])
        out.append(table(["technology", "cost", "prereqs", "effect"], rows))
        out.append("")
    out.append("### Player megaprojects")
    out.append("")
    out.append("Not nation-level tech; these are the six endgame programmes a player can run "
                "personally with `project` / `invest_project` once the prerequisite techs are "
                "held privately (see `study`).")
    out.append("")
    rows = []
    for k, d in RESEARCH_PROJECTS.items():
        rows.append([k, str(d["c"]), ", ".join(d["p"]), d["d"]])
    out.append(table(["project", "cost", "requires", "effect"], rows))
    out.append("")
    return "\n".join(out)


def units() -> str:
    out = ["## Military unit types", "",
           f"All {len(UNITS)} unit types. `cost` is the one-time procurement price; `up` is daily "
           "upkeep; `men` is manpower per unit; `supply` is tonnes of logistics consumption per "
           "day; `build` is days from order to fielding. `atk`/`dfn` are combat factors folded "
           "into `Nation.military_score()` and battle resolution.", ""]
    rows = []
    for u, d in UNITS.items():
        tech = d["tech"] or "—"
        rows.append([u, d["dom"], f"{d['atk']:.2f}", f"{d['dfn']:.2f}", f"{d['hp']:.1f}",
                     money(d["cost"]), money(d["up"]), f"{d['men']:,}", f"{d['supply']:.1f}",
                     tech, str(d["build"])])
    out.append(table(["unit", "domain", "atk", "dfn", "hp", "cost", "upkeep/day", "men",
                       "supply/day", "tech", "build days"], rows))
    out.append("")
    return "\n".join(out)


def intel_ops() -> str:
    out = ["## Intelligence operations", "",
           f"All {len(OPS)} operations available through `launch_op` (the player reaches most of "
           "these directly; see docs/PLAYING.md for the command names). `risk` is the base chance "
           "of exposure on any attempt; `heat` is how much heat/notoriety an exposed attempt "
           "generates; `days` is base time to resolution; `cost` is the base budget, which can be "
           "overspent for faster/likelier success.", ""]
    rows = []
    for k, d in OPS.items():
        rows.append([k, d["skill"], f"{d['risk']:.2f}", f"{d['heat']:.2f}", str(d["days"]),
                     money(d["cost"]), d["d"]])
    out.append(table(["operation", "skill", "risk", "heat", "days", "cost", "description"], rows))
    out.append("")
    return "\n".join(out)


def govs() -> str:
    out = ["## Government types", "",
           f"All {len(GOV_TYPES)} government forms nations can generate with. `repress` and "
           "`legit_base` seed `Nation.repression`/`.legitimacy`; `corrupt` seeds baseline "
           "corruption; `coup_risk` scales into the daily coup-attempt probability; `speed` is "
           "how fast policy can drift toward the ruling ideology.", ""]
    rows = []
    for g, d in GOV_TYPES.items():
        rows.append([g, "yes" if d["elections"] else "no", f"{d['repress']:.2f}",
                     f"{d['legit_base']:.2f}", f"{d['corrupt']:.2f}", f"{d['coup_risk']:.2f}",
                     f"{d['speed']:.2f}", d["desc"]])
    out.append(table(["government", "elections", "repress", "legit base", "corrupt",
                       "coup risk", "speed", "description"], rows))
    out.append("")
    return "\n".join(out)


def ideologies() -> str:
    out = ["## Ideologies", "",
           f"All {len(IDEOLOGIES)} named ideologies, as positions on the six-axis vector "
           "(`econ`, `social`, `auth`, `nation`, `milit`, `eco`; each -1..+1). See "
           "docs/SYSTEMS.md for what each axis means and how it is used. `appeal` is the "
           "audience segment (see `AUDIENCES`) most drawn to it during party formation.", ""]
    rows = []
    for k, d in IDEOLOGIES.items():
        v = d["v"]
        rows.append([k, d["appeal"]] + [f"{x:+.2f}" for x in v])
    out.append(table(["ideology", "appeal"] + AXES, rows))
    out.append("")
    return "\n".join(out)


def skills() -> str:
    out = ["## Skills", "",
           f"All {len(SKILLS)} player/NPC skills (0..1), grouped by category. Effective skill "
           "blends the raw value with the governing attribute: "
           "`0.78 * skill + 0.22 * (attribute / 20)`.", ""]
    from collections import defaultdict
    cats = defaultdict(list)
    for k, d in SKILLS.items():
        cats[d["cat"]].append(k)
    rows = []
    for cat in ("social", "power", "econ", "covert", "self"):
        for k in cats.get(cat, []):
            d = SKILLS[k]
            rows.append([k, cat, d["attr"], d["desc"]])
    out.append(table(["skill", "category", "governing attribute", "description"], rows))
    out.append("")
    return "\n".join(out)


def backgrounds() -> str:
    out = ["## Character backgrounds", "",
           f"All {len(BACKGROUNDS)} starting backgrounds. `wealth` is starting cash. `attrs` "
           "lists attribute bonuses applied before the ±1..2 random jitter every new character "
           "gets. `perks` are permanent, background-defining abilities (see the perk glossary "
           "below). `notoriety` seeds starting fame, public profile and personal protection.", ""]
    rows = []
    for k, d in BACKGROUNDS.items():
        attrs = ", ".join(f"{a} +{v}" for a, v in d["attrs"].items()) or "—"
        skills_s = ", ".join(f"{s} {v:.2f}" for s, v in sorted(d["skills"].items(),
                                                                key=lambda kv: -kv[1]))
        rows.append([d["label"], money(d["wealth"]), attrs, skills_s,
                     ", ".join(d["perks"]), f"{d['notoriety']:.2f}"])
    out.append(table(["background", "wealth", "attribute bonuses", "starting skills",
                       "perks", "notoriety"], rows))
    out.append("")
    out.append("### Background blurbs")
    out.append("")
    for k, d in BACKGROUNDS.items():
        out.append(f"- **{d['label']}** (`{k}`) — {d['blurb']}")
    out.append("")
    out.append("### Perk glossary")
    out.append("")
    rows = [[k, v] for k, v in sorted(PERKS.items())]
    out.append(table(["perk", "effect"], rows))
    out.append("")
    return "\n".join(out)


def traits() -> str:
    out = ["## Personality traits", "",
           f"All {len(TRAITS)} traits. Every new character (player or NPC) draws 2-4 at random; "
           "the player specifically draws 3. `mods` are the mechanical modifiers applied "
           "wherever that key is consulted (skill bonuses, stress gain, AP, etc.).", ""]
    rows = []
    for k, d in sorted(TRAITS.items()):
        mods = ", ".join(f"{m} {v:+.2f}" for m, v in d["mods"].items())
        rows.append([k, ", ".join(d["tags"]), mods])
    out.append(table(["trait", "tags", "modifiers"], rows))
    out.append("")
    return "\n".join(out)


def policies() -> str:
    out = ["## Policy levers", "",
           f"All {len(POLICIES)} sliders every nation carries (0..1 unless noted), settable "
           "directly with the `policy` action once you hold enough authority over a state.", ""]
    rows = []
    for k, d in POLICIES.items():
        rows.append([k, d["label"], f"{d['lo']:.2f}", f"{d['hi']:.2f}", f"{d['default']:.2f}"])
    out.append(table(["lever", "meaning", "min", "max", "typical default"], rows))
    out.append("")
    return "\n".join(out)


def rackets() -> str:
    out = ["## Criminal rackets", "",
           f"All {len(RACKETS)} lines of business a player-controlled syndicate can run "
           "with `racket <syndicate> | <kind>`. `margin` is profit share of revenue; `heat` "
           "drives how fast police attention accumulates; `violence` and `cap` (capacity "
           "ceiling) are flavour/scaling parameters.", ""]
    rows = []
    for k, d in RACKETS.items():
        rows.append([k, f"{d['margin']:.2f}", f"{d['heat']:.2f}", f"{d['violence']:.2f}",
                     f"{d['cap']:.1f}", d["skill"], d["d"]])
    out.append(table(["racket", "margin", "heat", "violence", "cap", "skill", "description"], rows))
    out.append("")
    return "\n".join(out)


def treaties_and_goals() -> str:
    out = ["## Treaty kinds", "",
           table(["kind", "description", "relation bump"],
                 [[k, d["d"], f"{d['relation']:+.2f}"] for k, d in TREATY_KINDS.items()]),
           "", "## War goals", "",
           table(["goal", "description", "cost", "escalation"],
                 [[k, d["d"], f"{d['cost']:.2f}", f"{d['escalation']:.2f}"]
                  for k, d in WAR_GOALS.items()]),
           ""]
    return "\n".join(out)


def diseases() -> str:
    out = ["## Disease registry", "",
           f"All {len(DISEASES)} diseases the SEIR epidemic model (docs/SYSTEMS.md) can seed. "
           "`r0` is basic reproduction number, `incub`/`dur` are days in the exposed and "
           "infectious compartments, `cfr` is case fatality rate, `season` is the amplitude of "
           "seasonal forcing.", ""]
    rows = []
    for k, d in DISEASES.items():
        rows.append([d["name"], f"{d['r0']:.2f}", str(d["incub"]), str(d["dur"]),
                     f"{d['cfr']:.4f}", f"{d['season']:.2f}"])
    out.append(table(["disease", "R0", "incubation (d)", "infectious (d)", "CFR", "seasonality"], rows))
    out.append("")
    return "\n".join(out)


def main():
    sections = [
        commodities(), industries(), tech_tree(), units(), intel_ops(), govs(),
        ideologies(), skills(), traits(), backgrounds(), policies(), rackets(),
        treaties_and_goals(), diseases(),
    ]
    print("\n".join(sections))


if __name__ == "__main__":
    main()
