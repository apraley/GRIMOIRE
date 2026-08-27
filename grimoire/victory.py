"""Paths to world domination, and the ways this ends badly."""
from __future__ import annotations

import math

from .player import PLAYER_ID
from .util import clamp, clamp01, fmt_num, fmt_pct, mean

PATHS = {
    "conquest": dict(
        label="Conquest",
        blurb="Rule, directly or through vassals, the majority of humanity by force of arms."),
    "hegemony": dict(
        label="Hegemony",
        blurb="Bind the great powers into a system whose centre is you."),
    "capital": dict(
        label="Capital",
        blurb="Own so much of world output that sovereignty becomes a formality."),
    "creed": dict(
        label="Creed",
        blurb="Convert the species to a doctrine you authored."),
    "deep_state": dict(
        label="Deep State",
        blurb="Own the people who own the states. Never hold an office worth naming."),
    "singularity": dict(
        label="Singularity",
        blurb="Build the thing that makes every other path irrelevant."),
    "apotheosis": dict(
        label="Apotheosis",
        blurb="Advance far along several paths at once, until refusal stops being possible."),
}


def controlled_nations(w, pl) -> dict[str, float]:
    """Nation id -> degree of the player's effective control, 0..1."""
    out = {}
    for nat in w.living_nations():
        c = nat.player_control
        if nat.head_of_state == PLAYER_ID:
            c = max(c, 0.95)
        elif pl.offices.get(nat.id) in ("head_of_government",):
            c = max(c, 0.75)
        elif pl.offices.get(nat.id):
            c = max(c, 0.30)
        # leaders who belong to you
        for role, pid in list(nat.cabinet.items()) + [("hos", nat.head_of_state),
                                                      ("hog", nat.head_of_gov)]:
            p = w.people.get(pid)
            if p is None or not p.alive:
                continue
            owned = (p.asset_of == PLAYER_ID) or (p.blackmailed_by == PLAYER_ID)
            if owned:
                weight = 0.32 if role in ("hos", "hog") else 0.07
                c += weight
        if nat.puppet_of and nat.puppet_of in out:
            c = max(c, out[nat.puppet_of] * 0.8)
        if c > 0.02:
            out[nat.id] = clamp01(c)
    # vassals of nations you control
    for nat in w.living_nations():
        if nat.puppet_of and out.get(nat.puppet_of, 0) > 0.5:
            out[nat.id] = max(out.get(nat.id, 0.0), out[nat.puppet_of] * 0.8)
    return out


def evaluate(w, pl) -> dict[str, float]:
    ctrl = controlled_nations(w, pl)
    pop = max(w.global_pop, 1.0)
    gdp = max(w.global_gdp, 1.0)

    # --- conquest -------------------------------------------------------
    ruled_pop = sum(w.nations[n].pop * c for n, c in ctrl.items() if c > 0.55)
    conquest = clamp01(ruled_pop / pop / 0.60)

    # --- hegemony -------------------------------------------------------
    heg = 0.0
    for nid in w.great_powers:
        nat = w.nations.get(nid)
        if nat is None:
            continue
        share = w.share_of_world(nid, "gdp")
        aligned = ctrl.get(nid, 0.0)
        if nat.puppet_of and ctrl.get(nat.puppet_of, 0) > 0.5:
            aligned = max(aligned, 0.7)
        for oid in pl.orgs:
            o = w.orgs.get(oid)
            if o and o.nation == nid:
                aligned = max(aligned, min(0.4, o.influence))
        heg += share * aligned
    hegemony = clamp01(heg / 0.55)

    # --- capital --------------------------------------------------------
    owned_rev = 0.0
    for oid, frac in pl.holdings.items():
        o = w.orgs.get(oid)
        if o and o.alive:
            owned_rev += o.revenue * frac
    capital = clamp01((owned_rev / gdp) / 0.35)
    if pl.flags.get("world_reserve"):
        capital = clamp01(capital + 0.20)

    # --- creed ----------------------------------------------------------
    creed_pop = 0.0
    if pl.faith and pl.faith in w.faiths:
        creed_pop += w.faiths[pl.faith].adherents
    if pl.movement and pl.movement in w.orgs:
        creed_pop += w.orgs[pl.movement].assets.get("followers", 0.0)
    creed_pop += pl.flags.get("followers", 0.0) * 0.5
    creed = clamp01((creed_pop / pop) / 0.50)
    if pl.flags.get("doctrine_engine"):
        creed = clamp01(creed * 1.35)

    # --- deep state -----------------------------------------------------
    owned_power = 0.0
    total_power = 0.0
    for nat in w.living_nations():
        weight = nat.gdp + nat.military_score() * 1e6
        total_power += weight
        leaders = [nat.head_of_state, nat.head_of_gov] + list(nat.cabinet.values())
        held = 0.0
        for pid in leaders:
            p = w.people.get(pid)
            if p is None or not p.alive:
                continue
            if pid == PLAYER_ID:
                held += 1.0
            elif p.asset_of == PLAYER_ID or p.blackmailed_by == PLAYER_ID:
                held += 1.0
            elif p.player_rel.get("debt", 0) > 0.6 or p.player_rel.get("fear", 0) > 0.7:
                held += 0.5
        owned_power += weight * clamp01(held / max(len(leaders), 1))
    deep = clamp01((owned_power / max(total_power, 1.0)) / 0.65)
    if pl.flags.get("panopticon"):
        deep = clamp01(deep + 0.18)

    # --- singularity ----------------------------------------------------
    done = sum(1 for p in pl.projects if p in w.projects and w.projects[p].done)
    prog = mean([w.projects[p].progress for p in pl.projects if p in w.projects] or [0.0])
    sing = 0.0
    if pl.flags.get("singularity"):
        sing = 0.55 + 0.15 * done
        lead = 0.0
        best_other = max((n.tech_level for n in w.living_nations()), default=0.5)
        lead = clamp01((len(pl.techs) / max(len(w.flags.get("tech_known", {})) + 1, 1)))
        sing = clamp01(sing + lead * 0.3)
    else:
        sing = clamp01(prog * 0.45 + done * 0.12)

    scores = {"conquest": conquest, "hegemony": hegemony, "capital": capital,
              "creed": creed, "deep_state": deep, "singularity": sing}
    top = sorted(scores.values(), reverse=True)
    scores["apotheosis"] = clamp01(mean(top[:3]) / 0.72) if len(top) >= 3 else 0.0
    pl.victory_progress = scores
    return scores


def check_end(w, pl) -> str | None:
    if pl.lost:
        return pl.lost
    p = w.people.get(PLAYER_ID)
    if p is None or not p.alive:
        pl.lost = "death"
        return "death"
    if w.doomsday >= 0.995:
        pl.lost = "extinction"
        return "extinction"
    scores = evaluate(w, pl)
    for path, val in scores.items():
        if val >= 1.0:
            pl.won = path
            return "won:" + path
    return None


ENDINGS = {
    "conquest": "The maps are redrawn in your handwriting. Every capital that still flies its own flag does so because you have not yet decided otherwise.",
    "hegemony": "No treaty is signed anywhere on Earth without a copy reaching your desk first. You never had to conquer anyone. They queued up.",
    "capital": "There is no longer a meaningful distinction between the world economy and your balance sheet. Governments send delegations, not demands.",
    "creed": "Half the species now explains the world in words you wrote. Your successors will argue about what you meant, for centuries.",
    "deep_state": "You hold no office. Your name appears in no constitution. Every person who does hold office answers a phone that rings from the same number.",
    "singularity": "The system you built now designs its own successors, and its successors design theirs. You are the last human who was ever in a position to give it an instruction.",
    "apotheosis": "Armies, markets, faith, and machines — you took all of them, and there is no longer any lever left for anyone to pull against you. History does not have a category for what you are.",
    "death": "It ends the way it ends for everyone: suddenly, and with the work unfinished. Somebody else will inherit the pieces.",
    "extinction": "The models were right about the ratchet and wrong about the timing. There is no one left to take over the world, and nothing left to take.",
}
