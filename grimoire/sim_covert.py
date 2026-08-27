"""Intelligence operations, counter-intelligence, and organised crime."""
from __future__ import annotations

import math

from . import names as N
from .content_conflict import HEAT_STAGES, OPS, RACKETS
from .content_social import SECRET_KINDS
from .content_tech import TECHS
from .entities import Operation
from .util import clamp, clamp01, lerp, mean

PLAYER = "PLAYER"


# ===========================================================================
def heat_stage(heat: float) -> tuple[str, str]:
    stage = HEAT_STAGES[0]
    for h, name, desc in HEAT_STAGES:
        if heat >= h:
            stage = (h, name, desc)
    return stage[1], stage[2]


def op_difficulty(w, kind: str, target, target_kind: str) -> float:
    d = OPS[kind]
    base = 0.35 + d["risk"] * 0.9
    if target_kind == "person" and target is not None:
        base += target.protection * 0.35 + target.suspicion * 0.25
        nat = w.nations.get(target.nation)
        if nat:
            base += nat.intel_capacity * 0.25 + nat.state_capacity * 0.12
        base += target.influence() * 0.20
    elif target_kind == "nation" and target is not None:
        base += target.intel_capacity * 0.45 + target.state_capacity * 0.20
        base += target.get_policy("surveillance") * 0.25
        for t in target.techs:
            base += TECHS[t]["e"].get("crypto_def", 0) * 0.08
            base += TECHS[t]["e"].get("repress_eff", 0) * 0.10
    elif target_kind == "org" and target is not None:
        base += target.secrecy * 0.40
    return clamp(base, 0.08, 0.97)


def launch_op(w, actor: str, kind: str, target_id: str, target_kind: str,
              skill: float, budget: float = 0.0, assets=None, meta=None) -> Operation:
    d = OPS[kind]
    oid = w.nid("OP")
    op = Operation(oid, kind, actor, target_id, w.clock.day)
    op.target_kind = target_kind
    op.skill = clamp01(skill)
    op.budget = budget
    op.assets = list(assets or [])
    op.codename = N.operation_name(w.rng.sub("ops"))
    op.meta = dict(meta or {})
    funding = clamp(budget / max(d["cost"], 1.0), 0.25, 3.0) if d["cost"] > 0 else 1.0
    op.eta = w.clock.day + max(1, int(d["days"] * clamp(1.6 - 0.5 * op.skill, 0.5, 1.8)
                                      / clamp(funding, 0.4, 1.6)))
    op.risk = d["risk"]
    w.operations[oid] = op
    return op


def tick_operations(w) -> list[dict]:
    """Resolve every operation whose clock has run out."""
    results = []
    for op in list(w.operations.values()):
        if op.resolved or w.clock.day < op.eta:
            continue
        results.append(resolve_op(w, op))
    return results


def resolve_op(w, op) -> dict:
    rng = w.rng.sub("ops")
    op.resolved = True
    d = OPS[op.kind]
    target, tkind = _resolve_target(w, op)
    diff = op_difficulty(w, op.kind, target, tkind)
    funding = clamp(op.budget / max(d["cost"], 1.0), 0.3, 2.5) if d["cost"] > 0 else 1.0
    skill = clamp01(op.skill * (0.75 + 0.25 * funding))
    ok, margin = rng.check(skill, diff, 0.20)
    exposed = False
    exposure_p = clamp01(d["risk"] * (1.4 - skill) * (0.6 + 0.9 * diff))
    if not ok:
        exposure_p *= 1.8
    exposed = rng.chance(exposure_p)

    out = {"op": op.id, "kind": op.kind, "codename": op.codename, "success": ok,
           "margin": margin, "exposed": exposed, "actor": op.actor,
           "target": op.target, "target_kind": tkind, "text": "", "detail": {}}

    handler = _HANDLERS.get(op.kind, _op_generic)
    handler(w, op, target, tkind, ok, margin, exposed, rng, out)

    if exposed:
        _apply_exposure(w, op, target, tkind, out, rng)
    if op.actor == PLAYER and w.player is not None:
        w.player.op_history.append((w.clock.day, op.kind, op.codename, ok, exposed))
    return out


def _resolve_target(w, op):
    if op.target_kind == "person":
        return w.people.get(op.target), "person"
    if op.target_kind == "nation":
        return w.nations.get(op.target), "nation"
    if op.target_kind == "org":
        return w.orgs.get(op.target), "org"
    if op.target_kind == "region":
        return w.regions.get(op.target), "region"
    return None, op.target_kind


# --------------------------------------------------------------- handlers --
def _op_generic(w, op, target, tkind, ok, margin, exposed, rng, out):
    out["text"] = ("Operation succeeded." if ok else "Operation failed.")


def _op_surveil(w, op, target, tkind, ok, margin, exposed, rng, out):
    if not ok:
        out["text"] = "Your watchers came away with nothing usable."
        return
    if tkind == "person" and target is not None:
        found = []
        for sec in target.secrets:
            if op.actor not in sec["known_by"] and rng.chance(0.35 + margin):
                sec["known_by"].append(op.actor)
                found.append(sec)
        target.__dict__.setdefault("_watched_by", []).append(op.actor)
        out["detail"]["secrets"] = [s["desc"] for s in found]
        out["detail"]["pattern"] = {"role": target.role, "power": round(target.influence(), 2),
                                    "wealth": target.wealth, "loyalty": round(target.loyalty, 2),
                                    "corruptible": round(target.corruptibility, 2)}
        out["text"] = (f"Pattern of life established on {target.name}."
                       + (f" {len(found)} secret(s) uncovered." if found else
                          " Nothing incriminating surfaced."))
    elif tkind == "nation" and target is not None:
        target_intel = target.__dict__
        out["detail"]["intel"] = {"forces": dict(target.forces), "nukes": target.nukes,
                                  "treasury": target.treasury, "techs": len(target.techs),
                                  "stability": round(target.stability, 2)}
        if op.actor != PLAYER:
            w.nations[op.actor].intel_known[target.id] = clamp01(
                w.nations[op.actor].intel_known.get(target.id, 0) + 0.25)
        out["text"] = f"Collection against {target.name} produced a full order-of-battle."


def _op_recruit(w, op, target, tkind, ok, margin, exposed, rng, out):
    if tkind != "person" or target is None:
        out["text"] = "No viable candidate."
        return
    appeal = clamp01(0.20 + target.corruptibility * 0.5 + (1 - target.loyalty) * 0.4
                     + margin * 0.5)
    if ok and rng.chance(appeal):
        target.is_asset = True
        target.asset_of = op.actor
        target.player_rel["debt"] = clamp(target.player_rel["debt"] + 0.4, -1, 1) \
            if op.actor == PLAYER else target.player_rel["debt"]
        out["text"] = f"{target.name} has agreed to work for you."
        out["detail"]["asset"] = target.id
    else:
        target.suspicion = clamp01(target.suspicion + 0.20)
        out["success"] = False
        out["text"] = f"{target.name} declined the approach — and is now wary."


def _op_steal_tech(w, op, target, tkind, ok, margin, exposed, rng, out):
    if not ok:
        out["text"] = "The exfiltration failed; the data was never reached."
        return
    from .sim_world import acquire_tech, available_techs
    donor = target if tkind == "nation" else (w.nations.get(target.nation) if target else None)
    if donor is None:
        out["text"] = "No research programme found."
        return
    if op.actor == PLAYER:
        pl = w.player
        cands = [t for t in donor.techs if t not in pl.techs]
        if cands:
            t = max(cands, key=lambda x: TECHS[x]["c"])
            pl.techs.add(t)
            out["detail"]["tech"] = t
            out["text"] = f"You now hold {donor.name}'s work on {t.replace('_', ' ')}."
        else:
            out["text"] = "Nothing in their archive you do not already have."
    else:
        thief = w.nations.get(op.actor)
        cands = [t for t in donor.techs if t not in thief.techs]
        if cands:
            t = rng.pick(cands)
            acquire_tech(w, thief, t, quiet=True)
            out["detail"]["tech"] = t
            out["text"] = f"{thief.name} acquires {t} from {donor.name}."


def _op_steal_funds(w, op, target, tkind, ok, margin, exposed, rng, out):
    if not ok:
        out["text"] = "The transfer was reversed before it cleared."
        return
    amount = 0.0
    if tkind == "nation" and target is not None:
        amount = min(target.treasury * clamp01(0.02 + margin * 0.10), target.treasury)
        target.treasury -= amount
    elif tkind == "org" and target is not None:
        amount = min(target.cash * clamp01(0.05 + margin * 0.25), max(target.cash, 0))
        target.cash -= amount
    elif tkind == "person" and target is not None:
        amount = min(target.wealth * clamp01(0.10 + margin * 0.4), target.wealth)
        target.wealth -= amount
    if op.actor == PLAYER:
        w.player.money += amount
        w.player.dirty_money += amount
    out["detail"]["amount"] = amount
    out["text"] = f"Funds extracted and laundered through three jurisdictions."


def _op_sabotage(w, op, target, tkind, ok, margin, exposed, rng, out):
    if not ok:
        out["text"] = "The device was found before it functioned."
        return
    if tkind == "region" and target is not None:
        target.devastation = clamp01(target.devastation + 0.06 + margin * 0.10)
        target.infra = clamp01(target.infra - 0.04)
        out["text"] = f"Industrial capacity in {target.name} is offline indefinitely."
    elif tkind == "nation" and target is not None:
        rs = [w.regions[r] for r in target.regions if r in w.regions]
        if rs:
            r = max(rs, key=lambda x: sum(x.capacity.values()))
            r.devastation = clamp01(r.devastation + 0.06 + margin * 0.10)
            out["detail"]["region"] = r.id
        target.readiness = clamp01(target.readiness - 0.06)
        out["text"] = f"A key facility in {target.name} burns."
    elif tkind == "org" and target is not None:
        target.revenue *= clamp01(0.72 - margin * 0.2)
        target.cash *= 0.85
        out["text"] = f"{target.name} suffers a catastrophic operational failure."


def _op_blackmail(w, op, target, tkind, ok, margin, exposed, rng, out):
    if tkind != "person" or target is None:
        out["text"] = "No leverage available."
        out["success"] = False
        return
    known = [s for s in target.secrets if op.actor in s["known_by"]]
    if not known:
        out["success"] = False
        out["text"] = f"You have nothing on {target.name}. Surveil them first."
        return
    best = max(known, key=lambda s: s["severity"])
    if ok and rng.chance(clamp01(best["severity"] * 0.8 + margin)):
        target.blackmailed_by = op.actor
        if op.actor == PLAYER:
            target.player_rel["fear"] = clamp(target.player_rel["fear"] + 0.45, -1, 1)
            target.player_rel["trust"] = clamp(target.player_rel["trust"] - 0.20, -1, 1)
        target.stress = clamp01(target.stress + 0.3)
        out["detail"]["secret"] = best["desc"]
        out["text"] = f"{target.name} will do what you ask. They will also hate you for it."
    else:
        out["success"] = False
        target.suspicion = clamp01(target.suspicion + 0.30)
        if op.actor == PLAYER:
            target.player_rel["fear"] = clamp(target.player_rel["fear"] + 0.15, -1, 1)
            target.player_rel["trust"] = clamp(target.player_rel["trust"] - 0.35, -1, 1)
        out["text"] = f"{target.name} refused to be moved. They are now an enemy."


def _op_bribe(w, op, target, tkind, ok, margin, exposed, rng, out):
    if tkind != "person" or target is None:
        out["success"] = False
        return
    price = target.influence() * 4.2e7 * (1.6 - target.corruptibility)
    paid = op.budget
    ratio = paid / max(price, 1.0)
    if ok and ratio > 0.5 and rng.chance(clamp01(target.corruptibility * 1.2 * min(ratio, 2))):
        target.wealth += paid
        if op.actor == PLAYER:
            target.player_rel["debt"] = clamp(target.player_rel["debt"] + 0.3 * min(ratio, 2), -1, 1)
            target.player_rel["trust"] = clamp(target.player_rel["trust"] + 0.10, -1, 1)
        target.loyalty = clamp01(target.loyalty - 0.15)
        out["detail"]["price"] = price
        out["text"] = f"{target.name} accepted. The arrangement is discreet."
    else:
        out["success"] = False
        out["detail"]["price"] = price
        target.suspicion = clamp01(target.suspicion + 0.2)
        out["text"] = (f"{target.name} refused the offer"
                       + (" — you did not offer nearly enough." if ratio < 0.6 else "."))


def _op_disinfo(w, op, target, tkind, ok, margin, exposed, rng, out):
    from .sim_society import add_narrative
    if not ok:
        out["text"] = "The story failed to catch."
        return
    kind = op.meta.get("narrative", "conspiracy")
    text = op.meta.get("text", "An anonymous dossier circulates.")
    seed_nation = target.id if tkind == "nation" else (
        target.nation if target is not None and hasattr(target, "nation") else None)
    n = add_narrative(w, kind, text, subject=op.meta.get("subject", ""),
                      origin=op.actor, truth=False,
                      credibility=clamp01(0.42 + margin * 0.6),
                      seed_nation=seed_nation, seed=clamp01(0.06 + margin * 0.25))
    boost = 1.0
    for nid in (w.great_powers if seed_nation is None else [seed_nation]):
        nat = w.nations.get(nid)
        if nat and "synthetic_media" in nat.techs:
            boost = 1.4
    for k in n.salience:
        n.salience[k] *= boost
    out["detail"]["narrative"] = n.id
    out["text"] = "The narrative is in circulation and spreading."


def _op_assassinate(w, op, target, tkind, ok, margin, exposed, rng, out):
    if tkind != "person" or target is None or not target.alive:
        out["success"] = False
        out["text"] = "The target was not reachable."
        return
    from .sim_world import _kill
    survive = clamp01(target.protection * 0.6 + 0.10)
    if ok and not rng.chance(survive):
        cause = rng.pick(["shot at close range", "a bomb beneath their car",
                          "a fall from a high window", "an unexplained cardiac event",
                          "a poisoning", "a helicopter crash", "a shooting in traffic"])
        nat = w.nations.get(target.nation)
        _kill(w, target, cause)
        out["detail"]["killed"] = target.id
        out["text"] = f"{target.name} is dead — {cause}."
        if nat:
            nat.unrest = clamp01(nat.unrest + 0.04)
            nat.stability = clamp01(nat.stability - 0.05)
            w.report(f"{target.describe_role()} {target.name} of {nat.name} has been "
                     f"assassinated ({cause}).", "politics", nat.id, 0.95, ["assassination"])
            from .sim_society import add_narrative
            add_narrative(w, "martyrdom" if target.power > 0.5 else "threat",
                          f"The killing of {target.name}.", subject=target.id,
                          seed_nation=nat.id, seed=0.30)
    else:
        out["success"] = False
        target.protection = clamp01(target.protection + 0.25)
        target.suspicion = clamp01(target.suspicion + 0.4)
        if op.actor == PLAYER:
            target.player_rel["fear"] = clamp(target.player_rel["fear"] + 0.3, -1, 1)
            target.player_rel["trust"] = -1.0
        out["text"] = f"The attempt on {target.name} failed. Their security has doubled."


def _op_kidnap(w, op, target, tkind, ok, margin, exposed, rng, out):
    if tkind != "person" or target is None:
        out["success"] = False
        return
    if ok and not rng.chance(target.protection * 0.5):
        target.__dict__["_held_by"] = op.actor
        target.role = "citizen"
        target.power = clamp01(target.power * 0.3)
        if op.actor == PLAYER:
            target.player_rel["fear"] = 1.0
        out["detail"]["held"] = target.id
        out["text"] = f"{target.name} is in a room you control."
    else:
        out["success"] = False
        target.protection = clamp01(target.protection + 0.2)
        out["text"] = "The snatch team was driven off."


def _op_coup_prep(w, op, target, tkind, ok, margin, exposed, rng, out):
    from .sim_power import _coup
    nat = target if tkind == "nation" else (w.nations.get(target.nation) if target else None)
    if nat is None:
        out["success"] = False
        return
    if not ok:
        nat.army_loyalty = clamp01(nat.army_loyalty + 0.06)
        out["text"] = "The officers you approached would not commit."
        return
    plotter = None
    if op.meta.get("figurehead"):
        plotter = w.people.get(op.meta["figurehead"])
    nat.army_loyalty = clamp01(nat.army_loyalty - 0.30 - margin * 0.2)
    success = _coup(w, nat, rng, plotter)
    out["detail"]["coup"] = success
    out["text"] = ("The generals moved. The palace is yours." if success
                   else "The plot was rolled up in its final hours.")
    if success and op.actor == PLAYER:
        nat.player_control = clamp01(nat.player_control + 0.55)


def _op_false_flag(w, op, target, tkind, ok, margin, exposed, rng, out):
    blamed = w.nations.get(op.meta.get("blame", ""))
    victim = target if tkind == "nation" else None
    if victim is None or blamed is None:
        out["success"] = False
        out["text"] = "The operation needs a victim and someone to blame."
        return
    if not ok:
        out["text"] = "The staging fell apart. Nobody believed it."
        return
    victim.relations[blamed.id] = clamp(victim.relation(blamed.id) - 0.45 - margin * 0.3, -1, 1)
    blamed.relations[victim.id] = clamp(blamed.relation(victim.id) - 0.15, -1, 1)
    victim.ideology["milit"] = clamp(victim.ideology["milit"] + 0.15, -1, 1)
    w.tension = clamp01(w.tension + 0.05)
    from .sim_society import add_narrative
    add_narrative(w, "threat", f"{blamed.name} is behind the attack on {victim.name}.",
                  seed_nation=victim.id, seed=0.35, truth=False)
    out["text"] = f"{victim.name} now believes {blamed.name} attacked them."


def _op_counterintel(w, op, target, tkind, ok, margin, exposed, rng, out):
    found = []
    if op.actor == PLAYER and w.player is not None:
        pl = w.player
        for pid in list(pl.assets):
            p = w.people.get(pid)
            if p and p.asset_of and p.asset_of != PLAYER and ok:
                found.append(p.id)
        pl.exposure = clamp01(pl.exposure - (0.10 + margin * 0.15 if ok else 0.0))
        pl.heat = clamp01(pl.heat - (0.06 if ok else 0.0))
    out["detail"]["moles"] = found
    out["text"] = ("Your organisation is swept clean." if ok
                   else "The sweep turned up nothing. That is not the same as being clean.")


def _op_cyber(w, op, target, tkind, ok, margin, exposed, rng, out):
    nat = target if tkind == "nation" else (w.nations.get(target.nation) if target else None)
    if nat is None or not ok:
        out["success"] = False
        out["text"] = "No persistent access was established."
        return
    nat.__dict__.setdefault("_implants", {})[op.actor] = clamp01(
        nat.__dict__.get("_implants", {}).get(op.actor, 0) + 0.3 + margin * 0.3)
    out["text"] = f"You hold persistent access inside {nat.name}'s critical infrastructure."


def _op_arm_insurgents(w, op, target, tkind, ok, margin, exposed, rng, out):
    region = target if tkind == "region" else None
    if region is None and tkind == "nation" and target is not None:
        rs = [w.regions[r] for r in target.regions if r in w.regions]
        region = max(rs, key=lambda x: x.unrest, default=None) if rs else None
    if region is None or not ok:
        out["success"] = False
        out["text"] = "The shipment never reached anyone who could use it."
        return
    region.insurgency = clamp01(region.insurgency + 0.10 + margin * 0.15)
    region.separatism = clamp01(region.separatism + 0.06)
    region.unrest = clamp01(region.unrest + 0.06)
    nat = w.nations.get(region.nation)
    if nat:
        nat.state_capacity = clamp01(nat.state_capacity - 0.01)
    out["detail"]["region"] = region.id
    out["text"] = f"The rebels in {region.name} are armed and paid."


def _op_extract(w, op, target, tkind, ok, margin, exposed, rng, out):
    if tkind != "person" or target is None:
        out["success"] = False
        return
    if ok:
        target.suspicion = 0.0
        target.__dict__.pop("_held_by", None)
        target.protection = clamp01(target.protection + 0.15)
        out["text"] = f"{target.name} is out and clean."
    else:
        out["text"] = f"The extraction failed. {target.name} is on their own."


def _op_plant_evidence(w, op, target, tkind, ok, margin, exposed, rng, out):
    if tkind != "person" or target is None:
        out["success"] = False
        return
    if not ok:
        out["text"] = "The forgeries would not survive scrutiny."
        return
    kind, sev, desc = rng.pick(SECRET_KINDS)
    target.secrets.append({"kind": kind, "severity": sev, "desc": desc,
                           "known_by": [op.actor], "day": w.clock.day, "planted": True})
    out["detail"]["secret"] = desc
    out["text"] = f"A paper trail now exists showing that {target.name} {desc}."


def _op_seduce(w, op, target, tkind, ok, margin, exposed, rng, out):
    if tkind != "person" or target is None:
        out["success"] = False
        return
    if ok:
        target.player_rel["affection"] = clamp(target.player_rel["affection"] + 0.4 + margin, -1, 1)
        target.player_rel["trust"] = clamp(target.player_rel["trust"] + 0.25, -1, 1)
        for sec in target.secrets:
            if op.actor not in sec["known_by"] and rng.chance(0.5):
                sec["known_by"].append(op.actor)
        out["text"] = f"{target.name} trusts you with things they should not."
    else:
        target.suspicion = clamp01(target.suspicion + 0.15)
        out["text"] = "They were not interested, and they noticed the effort."


def _op_leak(w, op, target, tkind, ok, margin, exposed, rng, out):
    from .sim_society import add_narrative
    if tkind == "person" and target is not None:
        known = [s for s in target.secrets if op.actor in s["known_by"]]
        if not known:
            out["success"] = False
            out["text"] = "You have nothing to leak."
            return
        sec = max(known, key=lambda s: s["severity"])
        if ok:
            nat = w.nations.get(target.nation)
            n = add_narrative(w, "scandal", f"{target.name} {sec['desc']}.",
                              subject=target.id, origin=op.actor, truth=not sec.get("planted"),
                              credibility=clamp01(0.55 + sec["severity"] * 0.4),
                              seed_nation=nat.id if nat else None,
                              seed=clamp01(0.10 + margin * 0.3))
            target.power = clamp01(target.power - sec["severity"] * 0.35)
            target.public_profile = clamp01(target.public_profile + 0.25)
            out["detail"]["narrative"] = n.id
            out["text"] = f"The story is running everywhere. {target.name} is finished, or nearly."
        else:
            out["text"] = "No outlet would touch it."
    else:
        out["success"] = False
        out["text"] = "Nothing to leak about that target."


def _op_frame(w, op, target, tkind, ok, margin, exposed, rng, out):
    _op_plant_evidence(w, op, target, tkind, ok, margin, exposed, rng, out)
    if ok and tkind == "person" and target is not None:
        _op_leak(w, op, target, tkind, ok, margin, exposed, rng, out)
        target.power = clamp01(target.power * 0.4)
        target.role = "citizen" if rng.chance(0.5) else target.role
        out["text"] = f"{target.name} goes down for something they did not do."


_HANDLERS = {
    "surveil": _op_surveil, "recruit_asset": _op_recruit, "steal_tech": _op_steal_tech,
    "steal_funds": _op_steal_funds, "sabotage": _op_sabotage, "blackmail": _op_blackmail,
    "bribe": _op_bribe, "disinfo": _op_disinfo, "assassinate": _op_assassinate,
    "kidnap": _op_kidnap, "coup_prep": _op_coup_prep, "false_flag": _op_false_flag,
    "counterintel": _op_counterintel, "cyber_intrude": _op_cyber,
    "arm_insurgents": _op_arm_insurgents, "extract": _op_extract,
    "plant_evidence": _op_plant_evidence, "seduce_target": _op_seduce,
    "leak": _op_leak, "frame_rival": _op_frame,
}


# --------------------------------------------------------------- exposure --
def _apply_exposure(w, op, target, tkind, out, rng) -> None:
    d = OPS[op.kind]
    victim_nation = None
    if tkind == "nation" and target is not None:
        victim_nation = target
    elif target is not None and getattr(target, "nation", None):
        victim_nation = w.nations.get(target.nation)
    attributed = rng.chance(clamp01(0.35 + (victim_nation.intel_capacity if victim_nation else 0.3)))
    out["detail"]["attributed"] = attributed
    if op.actor == PLAYER and w.player is not None:
        pl = w.player
        gain = d["heat"] * (1.4 if attributed else 0.5)
        pl.heat = clamp01(pl.heat + gain)
        pl.exposure = clamp01(pl.exposure + gain * 0.6)
        if attributed and victim_nation is not None:
            pl.wanted_by.add(victim_nation.id)
            victim_nation.__dict__.setdefault("_player_hostility", 0.0)
            victim_nation.__dict__["_player_hostility"] += d["heat"]
        out["text"] += "  [EXPOSED]" + (" — and traced back to you." if attributed
                                        else " — but not yet attributed.")
    elif victim_nation is not None and op.actor in w.nations and attributed:
        actor = w.nations[op.actor]
        victim_nation.relations[actor.id] = clamp(
            victim_nation.relation(actor.id) - d["heat"] * 0.9, -1, 1)
        if d["heat"] > 0.4:
            w.report(f"{victim_nation.name} publicly accuses {actor.name} of "
                     f"{op.kind.replace('_', ' ')} on its territory.",
                     "intel", victim_nation.id, 0.7, ["exposed"])
            w.tension = clamp01(w.tension + 0.02)


# ===========================================================================
def tick_agency_ops(w) -> None:
    """State intelligence services work against each other unprompted."""
    rng = w.rng.sub("agencies")
    nats = w.living_nations()
    for nat in rng.sample(nats, min(len(nats), 6)):
        budget = nat.gdp * nat.get_policy("intel_budget") * 0.004
        if budget <= 0 or not rng.chance(0.10 + nat.intel_capacity * 0.25):
            continue
        rivals = [n for n in nats if n.id != nat.id and nat.relation(n.id) < 0.15]
        if not rivals:
            continue
        target = rng.weighted(rivals, [max(0.05, -nat.relation(n.id) + 0.2) * (1 + n.power() / 12)
                                       for n in rivals])
        kinds = ["surveil", "steal_tech", "cyber_intrude", "recruit_asset", "disinfo"]
        if nat.relation(target.id) < -0.5:
            kinds += ["sabotage", "arm_insurgents"]
        if nat.relation(target.id) < -0.75 and nat.ideology.get("milit", 0) > 0.3:
            kinds += ["assassinate", "coup_prep"]
        kind = rng.pick(kinds)
        tkind = "nation"
        tid = target.id
        if kind in ("recruit_asset", "assassinate", "surveil"):
            pool = [p for p in w.people.values() if p.alive and p.nation == target.id
                    and p.power > 0.3]
            if pool:
                victim = rng.weighted(pool, [p.power for p in pool])
                tkind, tid = "person", victim.id
        launch_op(w, nat.id, kind, tid, tkind,
                  skill=clamp01(nat.intel_capacity * 0.9 + rng.gauss(0, 0.08)),
                  budget=budget * 30)
    nat_ids = {n.id for n in nats}
    for nat in nats:
        nat.intel_capacity = clamp01(lerp(nat.intel_capacity,
                                          clamp01(0.05 + 0.55 * nat.tech_level
                                                  + 0.45 * nat.get_policy("intel_budget")
                                                  + 0.15 * nat.state_capacity), 0.004))


# ===========================================================================
def tick_crime(w) -> None:
    """Syndicates grow, police push back, and corruption greases both."""
    rng = w.rng.sub("crime")
    for o in w.orgs.values():
        if o.kind != "syndicate" or not o.alive:
            continue
        nat = w.nations.get(o.nation)
        if nat is None or not nat.alive:
            o.alive = False
            continue
        pressure = nat.get_policy("policing") * nat.state_capacity * (1 - nat.corruption * 0.6)
        o.heat = clamp01(o.heat * 0.995 + sum(RACKETS[r]["heat"] * s for r, s in o.rackets.items())
                         * 0.0016 * (0.4 + pressure))
        if o.heat > 0.75 and rng.chance((o.heat - 0.7) * 0.06 * (0.4 + pressure)):
            hit = rng.pick(list(o.rackets)) if o.rackets else None
            if hit:
                o.rackets[hit] *= 0.45
                if o.rackets[hit] < 0.05:
                    del o.rackets[hit]
            o.cash *= 0.7
            o.heat = clamp01(o.heat - 0.35)
            w.report(f"Police in {nat.name} dismantle part of {o.name}'s operation.",
                     "crime", nat.id, 0.45, ["crackdown"])
            if not o.rackets:
                o.alive = False
        elif rng.chance(0.006 * (1 + nat.corruption) * (1 - pressure * 0.5)):
            avail = [r for r in RACKETS if r not in o.rackets]
            if avail:
                o.rackets[rng.pick(avail)] = rng.uniform(0.05, 0.25)
        for r in list(o.rackets):
            o.rackets[r] = clamp01(o.rackets[r] * (1 + 0.0016 * (1 + nat.corruption)
                                                   - 0.0022 * pressure))
        # bribery corrodes the state
        if o.cash > 0 and rng.chance(0.02 * nat.corruption):
            bribe = o.cash * 0.03
            o.cash -= bribe
            nat.corruption = clamp01(nat.corruption + 0.0012)
            o.influence = clamp01(o.influence + 0.004)
    for nat in w.living_nations():
        syn = [o for o in w.orgs.values() if o.kind == "syndicate" and o.nation == nat.id and o.alive]
        crime_level = clamp01(sum(sum(o.rackets.values()) for o in syn) * 0.12)
        for rid in nat.regions:
            r = w.regions.get(rid)
            if r is None:
                continue
            for cid in r.cities:
                c = w.cities.get(cid)
                if c:
                    c.crime = clamp01(lerp(c.crime, clamp01(0.05 + crime_level * 0.6
                                                            + r.unrest * 0.4
                                                            + (1 - r.employment) * 0.8
                                                            - nat.get_policy("policing") * 0.4),
                                           0.004))
