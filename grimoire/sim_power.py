"""Politics, unrest, coups, diplomacy and war."""
from __future__ import annotations

import math

from .content_conflict import DOCTRINES, TREATY_KINDS, UNITS, WAR_GOALS
from .content_social import AUDIENCES, AXES, GOV_TYPES, POLICIES, POLICY_IDEOLOGY
from .entities import Army, War
from .util import Counter, clamp, clamp01, lerp, mean
from .worldgen_social import ideology_distance, nearest_ideology


# ===========================================================================
def tick_politics(w) -> None:
    rng = w.rng.sub("politics")
    for nat in w.living_nations():
        gd = GOV_TYPES[nat.gov]
        regions = [w.regions[r] for r in nat.regions if r in w.regions]
        if not regions:
            nat.alive = False
            continue
        pop = max(nat.pop, 1.0)
        nat.unrest = clamp01(sum(r.unrest * r.pop for r in regions) / pop)

        # --- how the public feels ---------------------------------------
        # The inflation penalty is capped: unbounded, a currency crisis alone
        # can drive approval — and everything downstream of it — to zero, the
        # same failure mode fixed for tick_unrest's grievance term above.
        econ = (clamp(nat.growth, -0.15, 0.15) * 2.2
                - clamp(nat.inflation - 0.03, 0.0, 0.4) * 1.6
                - max(0.0, nat.unemployment - 0.06) * 1.4
                - mean(list(nat.__dict__.get("_shortfall", {}).values()) or [0.0]) * 1.2)
        war_drag = -0.5 * nat.war_weariness
        service = (nat.get_policy("welfare") * 0.25 + nat.get_policy("healthcare") * 0.25
                   + nat.get_policy("education") * 0.2 - nat.corruption * 0.6)
        target_app = clamp01(0.44 + econ * 0.35 + service * 0.30 + war_drag
                             + nat.prestige * 0.12 - nat.unrest * 0.55)
        nat.approval = clamp01(lerp(nat.approval, target_app, 0.010))

        # Each of these targets is a structural ANCHOR — matching the formula
        # world generation actually seeded it with — plus a small DELTA that is
        # zero when every input sits at its typical baseline value and only
        # moves the target when something is genuinely abnormal (a real war,
        # a real famine, a real corruption spiral).  An earlier version wrote
        # the situational part as a second, independently-calibrated absolute
        # formula blended against the anchor; because that formula's "normal"
        # output didn't equal the anchor, EVERY nation drifted away from its
        # seed from turn one regardless of any actual event, and because
        # legitimacy, corruption, state capacity and unrest all feed each
        # other, that slow drift eventually snowballed into total collapse.
        # Anchor-plus-zero-mean-delta guarantees a stable fixed point at the
        # seeded equilibrium; only a real shock moves it.
        # Each individual deviation is bounded before it is summed.  Left
        # unbounded, a single input sitting at its own extreme (unrest pinned
        # at its 1.0 ceiling, say) can by itself outweigh every anchor and
        # every other input combined, dragging the target to its floor no
        # matter how mild everything else is — and once several variables in
        # this mutually-coupled system saturate together, none of them can
        # ever climb back out.  Capping each term's contribution keeps one
        # runaway input from single-handedly deciding the outcome.
        def bounded(coeff, delta, cap=0.10):
            return clamp(coeff * delta, -cap, cap)

        legit_anchor = gd["legit_base"]
        legit_delta = (bounded(0.14, nat.approval - 0.50) + bounded(-0.16, nat.corruption - 0.45)
                       + bounded(0.10, nat.state_capacity - 0.50) + bounded(-0.18, nat.unrest - 0.15)
                       + bounded(-0.18, nat.war_exhaustion) + bounded(0.08, nat.prestige - 0.30))
        legit_target = clamp01(legit_anchor + legit_delta)
        # A slow crawl back from a crash (this was 0.006, a ~115-day time
        # constant) means legitimacy is still buried from an old shock long
        # after the conditions that caused it have genuinely passed — and
        # across dozens of nations, each recovering that slowly while new
        # crises keep landing elsewhere, the population-wide median never
        # clears at all.  0.016 (a ~43-day constant) still makes legitimacy a
        # slow-moving stat, just not a one-way ratchet.
        nat.legitimacy = clamp01(lerp(nat.legitimacy, legit_target, 0.016))

        cap_anchor = clamp01(0.28 + 0.62 * nat.tech_level)      # matches worldgen.seed_development
        cap_delta = (bounded(0.14, nat.get_policy("education") - 0.42)
                    + bounded(0.10, nat.legitimacy - 0.50) + bounded(-0.16, nat.corruption - 0.45)
                    + bounded(-0.16, nat.unrest - 0.15) + bounded(-0.18, nat.war_exhaustion))
        cap_target = clamp01(cap_anchor + cap_delta)
        nat.state_capacity = clamp01(lerp(nat.state_capacity, cap_target, 0.008))

        corr_anchor = gd["corrupt"]                              # matches worldgen.seed_politics
        corr_delta = (bounded(-0.20, nat.state_capacity - 0.50) + bounded(-0.14, nat.media_freedom - 0.50)
                      + bounded(-0.10, nat.get_policy("policing") - 0.35)
                      + bounded(0.10, (nat.get_policy("surveillance") - 0.25) * (1 - nat.media_freedom))
                      + bounded(0.08, 0.50 - nat.legitimacy))
        corr_target = clamp01(corr_anchor + corr_delta)
        nat.corruption = clamp01(lerp(nat.corruption, corr_target, 0.006))

        nat.stability = clamp01(0.20 + 0.34 * nat.legitimacy + 0.22 * nat.state_capacity
                                + 0.14 * nat.approval - 0.55 * nat.unrest
                                - 0.20 * nat.war_exhaustion
                                + 0.14 * nat.repression * (1 - nat.media_freedom))

        # --- policy drifts toward whoever holds power -------------------
        if nat.coalition:
            vec = {ax: 0.0 for ax in AXES}
            tot = 0.0
            for pid in nat.coalition:
                o = w.orgs.get(pid)
                if o is None:
                    continue
                wgt = o.assets.get("seats", 0.1)
                tot += wgt
                for ax in AXES:
                    vec[ax] += o.ideology.get(ax, 0.0) * wgt
            if tot > 0:
                for ax in AXES:
                    nat.ideology[ax] = clamp(lerp(nat.ideology[ax], vec[ax] / tot, 0.004), -1, 1)
        speed = gd["speed"] * (0.4 + 0.6 * nat.state_capacity)
        for pol, weights in POLICY_IDEOLOGY.items():
            d = POLICIES[pol]
            push = sum(nat.ideology.get(a, 0) * wt for a, wt in weights.items())
            mid = (d["lo"] + d["hi"]) / 2
            span = (d["hi"] - d["lo"]) / 2
            target = clamp(mid + push * span * 0.85, d["lo"], d["hi"])
            if pol == "military" and nat.at_war:
                target = min(d["hi"], target + 0.32)
            if pol in ("surveillance", "policing", "censorship") and nat.unrest > 0.25:
                target = min(d["hi"], target + nat.unrest * 0.5 * (1 - nat.media_freedom))
            if pol in ("welfare", "healthcare") and nat.debt_ratio() > 2.2:
                target = max(d["lo"], target - 0.18)
            nat.policy[pol] = clamp(lerp(nat.policy[pol], target, 0.0022 * speed), d["lo"], d["hi"])

        nat.repression = clamp01(lerp(nat.repression,
                                      clamp01(gd["repress"] * 0.6 + nat.get_policy("policing") * 0.3
                                              + nat.get_policy("surveillance") * 0.4
                                              + nat.get_policy("censorship") * 0.3), 0.006))
        nat.war_weariness = clamp01(nat.war_weariness * (0.997 if not nat.at_war else 1.0))
        nat.war_exhaustion = clamp01(nat.war_exhaustion * 0.9985)
        nat.army_loyalty = clamp01(lerp(nat.army_loyalty,
                                        clamp01(0.30 + 0.35 * nat.legitimacy
                                                + 0.30 * nat.get_policy("military")
                                                - 0.25 * nat.corruption
                                                - 0.20 * nat.war_exhaustion), 0.004))
        nat.prestige = clamp01(lerp(nat.prestige,
                                    clamp01(0.10 + 0.28 * nat.tech_level
                                            + 0.22 * clamp01(w.share_of_world(nat.id, "gdp") * 8)
                                            + 0.18 * clamp01(w.share_of_world(nat.id, "mil") * 8)
                                            + 0.12 * nat.get_policy("space_program")), 0.004))


def tick_unrest(w) -> None:
    """Grievance accumulates in regions; repression suppresses and inflames."""
    rng = w.rng.sub("unrest")
    for nat in w.living_nations():
        for rid in nat.regions:
            r = w.regions.get(rid)
            if r is None:
                continue
            # Legitimacy appears on both sides of this (grievance and relief)
            # and legitimacy's own target in tick_politics reacts to unrest —
            # a closed loop with no damping.  Keeping legitimacy's weight
            # small here is what breaks the runaway 2-cycle; the anchor terms
            # added in tick_politics do the rest.
            # Inflation is the one term here that is not naturally bounded to
            # [0,1] by construction (hyperinflation is a real, unbounded
            # possibility) — cap its contribution so a currency crisis alone
            # cannot single-handedly saturate unrest at its ceiling.
            infl_grievance = clamp(max(0.0, nat.inflation - 0.05) * 3, 0.0, 0.6)
            grievance = (0.30 * (1 - r.employment) + 0.22 * (1 - r.health)
                         + 0.20 * nat.corruption + 0.16 * infl_grievance
                         + 0.08 * (1 - nat.legitimacy) + 0.20 * r.devastation
                         + 0.14 * clamp01(nat.gini - 0.4) * 2
                         + 0.12 * r.separatism)
            relief = (0.30 * nat.get_policy("welfare") + 0.16 * nat.get_policy("healthcare")
                      + 0.14 * clamp(nat.growth, -0.1, 0.1) * 5
                      + 0.16 * nat.legitimacy)
            control = nat.repression * nat.state_capacity * (1 - r.insurgency * 0.5)
            target = clamp01(grievance * 0.50 - relief * 0.28 - control * 0.28 + 0.02)
            r.unrest = clamp01(lerp(r.unrest, target, 0.008) + rng.gauss(0, 0.0015))

            # Repression that outstrips legitimacy breeds insurgency; and
            # insurgency itself suppresses "control", which is a direct input
            # to unrest's own target above — so as long as insurgency only
            # decays while unrest is already low, a nation that reaches
            # unrest > 0.34 has no way out: insurgency can only grow, control
            # only weakens, and target unrest never gets the chance to fall
            # back under 0.34 to start the decay.  Applying baseline decay
            # unconditionally (just slower while genuinely under pressure)
            # gives the system an interior equilibrium instead of a one-way
            # ratchet — real insurgencies do burn out, get amnestied, or
            # fragment even while grievances persist.
            push = max(0.0, r.unrest - 0.34) * (0.4 + 0.9 * (1 - nat.legitimacy))
            push *= 1.0 + 1.4 * clamp01(control - nat.legitimacy)
            decay = 0.0020 * (0.5 + nat.state_capacity) * (1.0 - 0.4 * clamp01(push))
            r.insurgency = clamp01(r.insurgency + push * 0.0035 - decay)
            if r.insurgency > 0.02:
                r.control = clamp01(lerp(r.control, clamp01(1 - r.insurgency * 1.4), 0.01))
                r.devastation = clamp01(r.devastation + r.insurgency * 0.0016 - 0.0008)
            else:
                r.control = clamp01(lerp(r.control, 1.0, 0.004))
                r.devastation = clamp01(r.devastation - 0.0014)
            # separatism where the region is not a core of its owner
            if r.core_of != r.nation:
                r.separatism = clamp01(r.separatism + 0.0004 + r.unrest * 0.0012
                                       - nat.legitimacy * 0.0006)
            else:
                r.separatism = clamp01(r.separatism - 0.0006)

        _maybe_upheaval(w, nat, rng)


def _maybe_upheaval(w, nat, rng) -> None:
    gd = GOV_TYPES[nat.gov]
    if rng.chance(nat.unrest ** 2 * 0.012):
        regions = [w.regions[r] for r in nat.regions if r in w.regions]
        if not regions:
            return
        r = rng.weighted(regions, [x.unrest * x.pop for x in regions])
        if w.clock.day - r.__dict__.get("_last_upheaval", -999) < 90:
            return
        r.__dict__["_last_upheaval"] = w.clock.day
        kind = rng.weighted(["protest", "strike", "riot"],
                            [1.0, 0.7 + nat.unemployment * 2, 0.4 + r.unrest * 2])
        if kind == "protest":
            if r.pop > 4e6 or nat.unrest > 0.30:
                w.report(f"Mass demonstrations fill the streets of {r.name}, {nat.name}.",
                         "unrest", nat.id, 0.30 + nat.unrest)
            nat.approval = clamp01(nat.approval - 0.012)
        elif kind == "strike":
            w.report(f"A general strike halts industry across {r.name}, {nat.name}.",
                     "unrest", nat.id, 0.40 + nat.unrest)
            for rid in nat.regions:
                rr = w.regions.get(rid)
                if rr:
                    rr.employment = clamp01(rr.employment - 0.03)
        else:
            w.report(f"Rioting breaks out in {r.name}, {nat.name}; security forces respond.",
                     "unrest", nat.id, 0.45 + nat.unrest)
            r.devastation = clamp01(r.devastation + 0.012)
            r.unrest = clamp01(r.unrest + 0.02 * (1 - nat.legitimacy))

    # revolution
    if nat.unrest > 0.55 and nat.legitimacy < 0.30 and rng.chance((nat.unrest - 0.5) * 0.010):
        _revolution(w, nat, rng)
    # coup
    coup_p = (gd["coup_risk"] * 0.0016 * (1 - nat.army_loyalty) * 2.5
              * (1 + nat.unrest * 2 + nat.war_exhaustion * 2))
    if rng.chance(coup_p):
        _coup(w, nat, rng, None)


def _revolution(w, nat, rng) -> None:
    old = nat.gov
    succeed = rng.chance(clamp01(0.30 + nat.unrest - nat.repression * 0.7
                                 - nat.army_loyalty * 0.4))
    if not succeed:
        nat.unrest = clamp01(nat.unrest - 0.12)
        nat.repression = clamp01(nat.repression + 0.08)
        nat.legitimacy = clamp01(nat.legitimacy - 0.05)
        w.report(f"An uprising in {nat.name} is crushed. Mass arrests follow.",
                 "politics", nat.id, 0.85, ["revolution", "failed"])
        return
    lean = nat.ideology
    if lean.get("auth", 0) > 0.3:
        nat.gov = rng.pick(["one_party_state", "military_junta", "personalist"])
    else:
        nat.gov = rng.pick(["federal_republic", "council_state", "flawed_democracy"])
    nat.legitimacy = 0.42
    nat.unrest = clamp01(nat.unrest * 0.45)
    nat.stability = 0.35
    nat.corruption = clamp01(nat.corruption * 0.8)
    _install_leader(w, nat, rng, "revolutionary")
    w.report(f"REVOLUTION: the government of {nat.name} falls. "
             f"{old.replace('_', ' ').title()} gives way to {nat.gov.replace('_', ' ')}.",
             "politics", nat.id, 1.0, ["revolution"])
    w.tension = clamp01(w.tension + 0.02)


def _coup(w, nat, rng, plotter) -> None:
    strength = clamp01(0.35 + (1 - nat.army_loyalty) * 0.6 + nat.unrest * 0.4
                       - nat.legitimacy * 0.5 - nat.state_capacity * 0.3)
    if plotter is not None:
        strength = clamp01(strength + 0.25)
    if rng.chance(strength):
        nat.gov = "military_junta" if rng.chance(0.62) else "personalist"
        nat.legitimacy = clamp01(nat.legitimacy * 0.6 + 0.12)
        nat.repression = clamp01(nat.repression + 0.22)
        nat.unrest = clamp01(nat.unrest + 0.10)
        nat.army_loyalty = clamp01(nat.army_loyalty + 0.25)
        _install_leader(w, nat, rng, "junta", plotter)
        w.report(f"COUP: armoured units seize the capital of {nat.name}. "
                 f"The constitution is suspended.", "politics", nat.id, 1.0, ["coup"])
        return True
    nat.army_loyalty = clamp01(nat.army_loyalty + 0.10)
    nat.repression = clamp01(nat.repression + 0.10)
    w.report(f"A coup attempt in {nat.name} collapses within hours. Purges begin.",
             "politics", nat.id, 0.9, ["coup", "failed"])
    return False


def _install_leader(w, nat, rng, flavour: str, person=None) -> None:
    from .worldgen_social import make_person
    old = w.people.get(nat.head_of_state)
    if person is not None:
        new = person
    else:
        pool = [p for p in w.people.values()
                if p.nation == nat.id and p.alive and p.role in
                (("general", "admiral", "air_marshal") if flavour == "junta"
                 else ("activist", "union_boss", "legislator", "cleric"))]
        new = rng.pick(pool) if pool else make_person(w, rng, nat.id, "head_of_state")
    if old and old.alive and old.id != new.id:
        old.role = "legislator" if rng.chance(0.4) else "citizen"
        old.power = clamp01(old.power * 0.3)
        if flavour == "junta" and rng.chance(0.45):
            old.alive = False
            old.death_day = w.clock.day
            old.death_cause = "executed after the coup"
            w.obituaries.append((w.clock.day, old.id, old.death_cause))
    new.role = "head_of_state"
    new.title = {"junta": "Chairman of the Council", "revolutionary": "Provisional President"} \
        .get(flavour, "President")
    new.power = clamp01(0.9)
    nat.head_of_state = new.id
    nat.head_of_gov = new.id
    nat.leader_since = w.clock.day
    for ax in AXES:
        nat.ideology[ax] = clamp(lerp(nat.ideology[ax], new.ideology.get(ax, 0.0), 0.45), -1, 1)


# ===========================================================================
def tick_elections(w) -> None:
    rng = w.rng.sub("elections")
    for nat in w.living_nations():
        if not GOV_TYPES[nat.gov]["elections"]:
            continue
        if nat.next_election <= 0:
            nat.next_election = w.clock.day + nat.term_length
            continue
        if w.clock.day < nat.next_election:
            continue
        _run_election(w, nat, rng)
        nat.next_election = w.clock.day + nat.term_length


def _run_election(w, nat, rng) -> None:
    parties = [w.orgs[p] for p in nat.parties if p in w.orgs and w.orgs[p].alive]
    if not parties:
        nat.next_election = w.clock.day + nat.term_length
        return
    incumbent = nat.ruling_party
    scores = []
    for o in parties:
        fit = 1 - ideology_distance(o.ideology, nat.ideology)
        mood = nat.approval if o.id == incumbent else (1 - nat.approval) * 0.6 + 0.2
        pull = 0.0
        for aud, val in nat.opinion.items():
            pull += val * 0.02
        base = o.assets.get("support", 0.2)
        rig = 0.0
        if nat.gov in ("dominant_party", "corporate_state") and o.id == incumbent:
            rig = 0.25 * nat.repression
        s = max(0.001, base * (0.45 + 0.9 * fit) * (0.55 + 0.9 * mood)
                * (1 + o.influence) * rng.lognorm(1.0, 0.22) + rig + pull)
        scores.append(s)
    tot = sum(scores)
    seats = [s / tot for s in scores]
    for o, sh in zip(parties, seats):
        o.assets["seats"] = sh
        o.assets["support"] = lerp(o.assets.get("support", sh), sh, 0.6)
    order = sorted(zip(parties, seats), key=lambda t: -t[1])
    winner = order[0][0]
    changed = winner.id != incumbent
    nat.ruling_party = winner.id
    nat.coalition = [winner.id]
    acc = order[0][1]
    for o, sh in order[1:]:
        if acc >= 0.5:
            break
        if ideology_distance(o.ideology, winner.ideology) < 0.45:
            nat.coalition.append(o.id)
            acc += sh
    nat.parties = [o.id for o, _ in order]
    if changed:
        pool = [p for p in w.people.values()
                if p.alive and p.nation == nat.id and p.org == winner.id]
        if not pool:
            pool = [p for p in w.people.values()
                    if p.alive and p.nation == nat.id and p.role in ("legislator", "governor")]
        if pool:
            _install_leader(w, nat, rng, "elected", rng.pick(pool))
        nat.legitimacy = clamp01(nat.legitimacy + 0.05)
        nat.approval = clamp01(0.52 + rng.gauss(0, 0.08))
    else:
        nat.legitimacy = clamp01(nat.legitimacy + 0.02)
    w.report(f"Election in {nat.name}: {winner.name} takes {seats[parties.index(winner)] * 100:.0f}% "
             f"of the vote and {'unseats the government' if changed else 'is returned to power'}.",
             "politics", nat.id, 0.8, ["election"])


# ===========================================================================
def tick_diplomacy(w) -> None:
    rng = w.rng.sub("diplomacy")
    nats = w.living_nations()
    if len(nats) < 2:
        return
    for nat in rng.sample(nats, min(len(nats), 12)):
        for other in rng.sample([n for n in nats if n.id != nat.id], 5):
            rel = nat.relation(other.id)
            idist = ideology_distance(nat.ideology, other.ideology)
            neighbour = other.id in w.neighbours.get(nat.id, [])
            pull = (0.34 - 0.50 * idist
                    + (0.14 if nat.culture == other.culture else 0.0)
                    + 0.16 * len(nat.treaties.get(other.id, set()))
                    - (0.22 if neighbour else 0.0)
                    - (0.35 if any(w.regions[c].nation == other.id
                                   for c in nat.claims if c in w.regions) else 0.0)
                    - (0.5 if other.id in nat.at_war else 0.0)
                    - (0.25 if other.id in nat.sanctions or nat.id in other.sanctions else 0.0)
                    + 0.10 * (nat.soft_power + other.soft_power))
            # great powers resent each other
            if nat.id in w.great_powers[:4] and other.id in w.great_powers[:4]:
                pull -= 0.14
            target = clamp(pull, -1, 1)
            # grievances fade: without a live cause, relations creep back toward
            # wary indifference rather than staying pinned at total hostility
            if other.id not in nat.at_war:
                target = lerp(target, 0.0, 0.35)
            nat.relations[other.id] = clamp(lerp(rel, target, 0.006) + rng.gauss(0, 0.004), -1, 1)

        # treaty formation and rupture
        for other in rng.sample([n for n in nats if n.id != nat.id], 3):
            rel = nat.relation(other.id)
            have = nat.treaties.setdefault(other.id, set())
            if rel > 0.5 and rng.chance(0.008) and len(have) < 4:
                options = [k for k in TREATY_KINDS if k not in have and k != "vassalage"]
                if options:
                    k = rng.weighted(options, [1.0 / (1 + TREATY_KINDS[o]["relation"] * 4)
                                               for o in options])
                    have.add(k)
                    other.treaties.setdefault(nat.id, set()).add(k)
                    nat.relations[other.id] = clamp(rel + TREATY_KINDS[k]["relation"] * 0.4, -1, 1)
                    if k in ("alliance", "defence"):
                        w.report(f"{nat.name} and {other.name} sign a {k.replace('_', ' ')} pact.",
                                 "diplomacy", nat.id, 0.7, ["treaty"])
            elif rel < -0.35 and have and rng.chance(0.012):
                k = rng.pick(list(have))
                have.discard(k)
                other.treaties.get(nat.id, set()).discard(k)
                w.report(f"{nat.name} withdraws from its {k.replace('_', ' ')} arrangement "
                         f"with {other.name}.", "diplomacy", nat.id, 0.55, ["treaty"])
            if rel < -0.6 and other.id not in nat.sanctions and rng.chance(0.006):
                nat.sanctions.add(other.id)
                w.report(f"{nat.name} imposes sanctions on {other.name}.",
                         "diplomacy", nat.id, 0.6, ["sanctions"])
            elif rel > 0.1 and other.id in nat.sanctions and rng.chance(0.02):
                nat.sanctions.discard(other.id)

    # global temperature
    # World tension is driven by how the *great powers* regard each other, not
    # by every grudge between micro-states.
    gp = [w.nations[i] for i in w.great_powers if i in w.nations]
    hot = 0.0
    n = 0
    for a in gp:
        for b in gp:
            if a.id != b.id:
                hot += max(0.0, -a.relation(b.id))
                n += 1
    base = hot / max(n, 1)
    wars = sum(1 for x in w.wars.values() if x.ended is None)
    w.tension = clamp01(lerp(w.tension, clamp01(base * 0.85 + wars * 0.030), 0.008))
    w.trade_openness = clamp01(lerp(w.trade_openness, clamp01(0.92 - w.tension * 0.9), 0.004))


def maybe_declare_war(w) -> None:
    rng = w.rng.sub("war_decl")
    nats = w.living_nations()
    for nat in rng.sample(nats, min(len(nats), 14)):
        if nat.at_war or nat.unrest > 0.55 or nat.war_exhaustion > 0.45:
            continue
        targets = [w.nations[n] for n in w.neighbours.get(nat.id, []) if n in w.nations
                   and w.nations[n].alive]
        targets += [w.nations[c] for c in rng.sample(list(w.nations), 2)
                    if c in w.nations and w.nations[c].alive and c != nat.id]
        for other in targets:
            if other.id == nat.id or other.id in nat.at_war:
                continue
            rel = nat.relation(other.id)
            if rel > -0.22:
                continue
            if nat.has_treaty(other.id, "nonaggression") or nat.has_treaty(other.id, "alliance"):
                continue
            mine = nat.military_score()
            theirs = other.military_score() + sum(
                w.nations[a].military_score() * 0.6 for a in other.allies() if a in w.nations)
            if theirs > mine * 1.05:
                continue
            if other.nukes > 0 and nat.nukes == 0:
                continue
            # A legitimacy crisis mostly turns inward (unrest, insurgency,
            # coups — see tick_unrest); it should only weakly translate into
            # foreign adventurism, or falling legitimacy triggers more wars,
            # which crash the economy and legitimacy further, in an
            # unbounded loop.
            appetite = (nat.ideology.get("milit", 0) * 0.4 + nat.ideology.get("nation", 0) * 0.3
                        + (1 - nat.legitimacy) * 0.12 + max(0.0, -rel) * 0.5
                        + (0.4 if any(w.regions[c].nation == other.id for c in nat.claims) else 0))
            if rng.chance(clamp01(appetite) * 0.006):
                goal = "annex_region" if any(w.regions[c].nation == other.id for c in nat.claims) \
                    else rng.weighted(list(WAR_GOALS), [3, 1.2, 1.5, 2.2, 2.6, 0.8, 0.5, 1.0, 1.4])
                declare_war(w, nat, other, goal)
                return


def declare_war(w, attacker, defender, goal: str, instigator: str | None = None) -> "War":
    wid = w.nid("W")
    war = War(wid, attacker.id, defender.id, goal, w.clock.day)
    war.name = f"the {attacker.adjective}-{defender.adjective} War"
    war.instigator = instigator
    attacker.at_war.add(defender.id)
    defender.at_war.add(attacker.id)
    attacker.relations[defender.id] = -1.0
    defender.relations[attacker.id] = -1.0
    attacker.mobilised = clamp01(attacker.mobilised + 0.35)
    defender.mobilised = clamp01(defender.mobilised + 0.45)
    w.wars[wid] = war
    w.tension = clamp01(w.tension + 0.06)
    w.report(f"WAR: {attacker.name} declares war on {defender.name} "
             f"({WAR_GOALS[goal]['d'].lower()})", "war", attacker.id, 1.0, ["war"])
    # allies are called in
    for ally in list(defender.allies()):
        a = w.nations.get(ally)
        if a and a.alive and a.id != attacker.id and a.id not in war.defenders:
            if a.relation(defender.id) > 0.3:
                war.defenders.append(a.id)
                a.at_war.add(attacker.id)
                attacker.at_war.add(a.id)
                a.mobilised = clamp01(a.mobilised + 0.3)
                w.report(f"{a.name} honours its pact and joins the war against {attacker.name}.",
                         "war", a.id, 0.85, ["war"])
    for ally in list(attacker.allies()):
        a = w.nations.get(ally)
        if a and a.alive and a.id not in war.attackers and a.relation(attacker.id) > 0.45 \
                and w.rng.sub("allies").chance(0.4):
            war.attackers.append(a.id)
            for d in war.defenders:
                a.at_war.add(d)
                w.nations[d].at_war.add(a.id)
    return war


# ===========================================================================
#  W A R
# ===========================================================================
def _terrain_defence(w, region) -> float:
    from .content_econ import BIOMES
    bonus = 0.0
    for b, f in region.biomes.items():
        bonus += f * {"mountain": 0.55, "wetland": 0.30, "rainforest": 0.35, "taiga": 0.22,
                      "desert": 0.12, "tundra": 0.15, "ice": 0.30}.get(b, 0.0)
    bonus += 0.25 * region.urban
    bonus += 0.20 * region.effective_infra() if region.nation else 0.0
    return clamp(bonus, 0.0, 0.95)


def _supply_at(w, nat, region) -> float:
    """How well a nation can sustain forces in a region."""
    cap = w.nations[nat.id].capital
    dist = 0.4
    if cap and cap in w.cities:
        c = w.cities[cap]
        dx = min(abs(c.x - region.centroid[0]), w.planet.w - abs(c.x - region.centroid[0]))
        dist = math.hypot(dx, c.y - region.centroid[1]) / w.planet.w
    logi = nat.stockpile.get("logistics", 0.0)
    need = max(nat.manpower * 0.0002, 1.0)
    return clamp(1.15 - dist * 1.5 + 0.35 * region.effective_infra()
                 + 0.25 * clamp01(logi / need) - 0.30 * region.insurgency, 0.10, 1.25)


def war_fronts(w, war) -> list[tuple]:
    """Contested (attacker_region, defender_region) pairs."""
    fronts = []
    att = set(war.attackers)
    dfn = set(war.defenders)
    for rid, r in w.regions.items():
        holder = war.occupied.get(rid, r.nation)
        if holder not in att and holder not in dfn:
            continue
        for nb in w.adjacency.get(rid, ()):
            o = w.regions.get(nb)
            if o is None:
                continue
            oholder = war.occupied.get(nb, o.nation)
            if holder in att and oholder in dfn:
                fronts.append((r, o))
            elif holder in dfn and oholder in att:
                fronts.append((o, r))
    return fronts


def _side_power(w, side: list[str], attacking: bool) -> tuple[float, dict]:
    total = 0.0
    contrib = {}
    for nid in side:
        nat = w.nations.get(nid)
        if nat is None or not nat.alive:
            continue
        doc = DOCTRINES.get(nat.doctrine, DOCTRINES["combined_arms"])
        mod = 1 + (doc["atk"] if attacking else doc["dfn"])
        p = nat.military_score() * mod * (0.6 + 0.7 * nat.army_loyalty)
        contrib[nid] = p
        total += p
    return total, contrib


def resolve_battle(w, war, front, rng) -> None:
    a_region, d_region = front
    a_holder = war.occupied.get(a_region.id, a_region.nation)
    d_holder = war.occupied.get(d_region.id, d_region.nation)
    att = w.nations.get(a_holder)
    dfn = w.nations.get(d_holder)
    if att is None or dfn is None or not att.alive or not dfn.alive:
        return

    commit = clamp(0.05 + 0.10 * att.mobilised, 0.02, 0.22)
    ap = att.military_score() * commit * (1 + DOCTRINES[att.doctrine]["atk"])
    dp = dfn.military_score() * commit * 1.15 * (1 + DOCTRINES[dfn.doctrine]["dfn"])
    ap *= _supply_at(w, att, d_region) * (0.55 + 0.55 * att.morale)
    dp *= _supply_at(w, dfn, d_region) * (0.55 + 0.55 * dfn.morale)
    dp *= 1 + _terrain_defence(w, d_region)
    dp *= 1 + 0.5 * d_region.control
    if dfn.nukes and att.nukes:
        pass
    ap *= rng.lognorm(1.0, 0.28)
    dp *= rng.lognorm(1.0, 0.28)

    total = ap + dp
    if total <= 0:
        return
    a_share = ap / total
    intensity = min(ap, dp) / max(total, 1.0)
    base_loss = 0.020 * intensity * (1 + 0.6 * w.world_tech)
    a_loss = base_loss * (1.4 - a_share)
    d_loss = base_loss * (0.6 + a_share)

    for nat, loss in ((att, a_loss), (dfn, d_loss)):
        killed = 0.0
        for u in list(nat.forces):
            gone = nat.forces[u] * loss * rng.uniform(0.7, 1.3)
            nat.forces[u] = max(0.0, nat.forces[u] - gone)
            killed += gone * UNITS[u]["men"] * 0.30
            if nat.forces[u] < 0.5:
                del nat.forces[u]
        nat.manpower = sum(UNITS[u]["men"] * n for u, n in nat.forces.items())
        war.casualties[nat.id] = war.casualties.get(nat.id, 0.0) + killed
        nat.war_weariness = clamp01(nat.war_weariness + killed / max(nat.pop, 1) * 22)
        nat.war_exhaustion = clamp01(nat.war_exhaustion + loss * 0.35)
        nat.morale = clamp01(nat.morale - loss * 0.5 + 0.001)
        # replacements from the reserve pool
        if nat.reserves_men > 0 and nat.forces:
            draft = min(nat.reserves_men * 0.004, killed * 1.2)
            nat.reserves_men -= draft
            for u in nat.forces:
                nat.forces[u] += draft / max(len(nat.forces), 1) / max(UNITS[u]["men"], 1)

    d_region.devastation = clamp01(d_region.devastation + intensity * 0.045)
    d_region.unrest = clamp01(d_region.unrest + intensity * 0.02)
    for cid in d_region.cities:
        c = w.cities.get(cid)
        if c:
            c.damage = clamp01(c.damage + intensity * 0.03)

    if a_share > 0.62 and rng.chance((a_share - 0.55) * 1.5):
        war.occupied[d_region.id] = a_holder
        d_region.occupier = a_holder
        d_region.control = 0.25
        att.morale = clamp01(att.morale + 0.02)
        dfn.morale = clamp01(dfn.morale - 0.03)
        w.report(f"{att.name} takes {d_region.name} from {dfn.name}.",
                 "war", att.id, 0.7, ["battle"])
    elif a_share < 0.36 and rng.chance((0.45 - a_share) * 1.2) and a_region.id in war.occupied:
        del war.occupied[a_region.id]
        a_region.occupier = None
        w.report(f"{dfn.name} retakes {a_region.name}.", "war", dfn.id, 0.7, ["battle"])

    war.battles.append({"day": w.clock.day, "where": d_region.id,
                        "att": a_holder, "dfn": d_holder, "score": a_share})
    if len(war.battles) > 300:
        del war.battles[:100]


def tick_wars(w) -> None:
    rng = w.rng.sub("wars")
    for war in list(w.wars.values()):
        if war.ended is not None:
            continue
        fronts = war_fronts(w, war)
        if fronts:
            for front in rng.sample(fronts, min(len(fronts), rng.randint(1, 3))):
                resolve_battle(w, war, front, rng)
        else:
            # no land border: a naval and air war of attrition
            for side, other in ((war.attackers, war.defenders), (war.defenders, war.attackers)):
                for nid in side:
                    nat = w.nations.get(nid)
                    if nat:
                        nat.__dict__["_blockade"] = clamp01(
                            nat.__dict__.get("_blockade", 0.0) + 0.004)
                        nat.war_exhaustion = clamp01(nat.war_exhaustion + 0.0009)

        # score the war
        att_val = sum(w.regions[r].pop for r in war.occupied
                      if r in w.regions and war.occupied[r] in war.attackers)
        dfn_val = sum(w.regions[r].pop for r in war.occupied
                      if r in w.regions and war.occupied[r] in war.defenders)
        a_pop = sum(w.nations[n].pop for n in war.attackers if n in w.nations)
        d_pop = sum(w.nations[n].pop for n in war.defenders if n in w.nations)
        cas_a = sum(war.casualties.get(n, 0) for n in war.attackers)
        cas_d = sum(war.casualties.get(n, 0) for n in war.defenders)
        war.warscore = clamp(att_val / max(d_pop, 1) * 2.2 - dfn_val / max(a_pop, 1) * 2.2
                             + (cas_d - cas_a) / max(cas_a + cas_d, 1) * 0.25, -1, 1)

        _maybe_nuke(w, war, rng)
        _maybe_peace(w, war, rng)


def _maybe_nuke(w, war, rng) -> None:
    for side, enemies in ((war.attackers, war.defenders), (war.defenders, war.attackers)):
        for nid in side:
            nat = w.nations.get(nid)
            if nat is None or nat.nukes <= 0:
                continue
            losing = -war.warscore if nid in war.attackers else war.warscore
            desperation = clamp01(losing * 0.6 + nat.war_exhaustion * 0.5 - nat.legitimacy * 0.3)
            if desperation < 0.55:
                continue
            if not rng.chance((desperation - 0.5) * 0.008):
                continue
            target_nat = w.nations.get(rng.pick(enemies))
            if target_nat is None:
                continue
            _nuclear_strike(w, nat, target_nat, war, rng)
            return


def _nuclear_strike(w, attacker, target, war, rng) -> None:
    n = min(attacker.nukes, rng.randint(1, max(1, attacker.nukes // 8)))
    attacker.nukes -= n
    war.nuclear = True
    dead = 0.0
    cities = sorted(w.nation_cities(target.id), key=lambda c: -c.pop)[:n]
    for c in cities:
        r = w.regions.get(c.region)
        kill = c.pop * rng.uniform(0.25, 0.62)
        c.pop = max(0.0, c.pop - kill)
        c.damage = 1.0
        dead += kill
        if r:
            r.pop = max(0.0, r.pop - kill)
            r.devastation = clamp01(r.devastation + 0.55)
            r.health = clamp01(r.health - 0.4)
            r.unrest = clamp01(r.unrest + 0.3)
    target.war_exhaustion = clamp01(target.war_exhaustion + 0.35)
    target.morale = clamp01(target.morale - 0.2)
    w.doomsday = clamp01(w.doomsday + 0.14)
    w.tension = clamp01(w.tension + 0.25)
    w.planet.temp_anomaly += 0.01 * n
    for other in w.living_nations():
        if other.id != attacker.id:
            other.relations[attacker.id] = clamp(other.relation(attacker.id) - 0.6, -1, 1)
    attacker.prestige = clamp01(attacker.prestige - 0.15)
    w.report(f"NUCLEAR STRIKE: {attacker.name} detonates {n} warhead{'s' if n > 1 else ''} on "
             f"{target.name}. Casualties are estimated at {dead / 1e6:.1f} million.",
             "war", attacker.id, 1.0, ["nuclear"])
    # retaliation
    if target.nukes > 0 and rng.chance(0.88):
        w.schedule(1, "retaliate", {"from": target.id, "to": attacker.id, "war": war.id})


def _maybe_peace(w, war, rng) -> None:
    att = [w.nations[n] for n in war.attackers if n in w.nations and w.nations[n].alive]
    dfn = [w.nations[n] for n in war.defenders if n in w.nations and w.nations[n].alive]
    if not att or not dfn:
        end_war(w, war, None)
        return
    length = w.clock.day - war.started
    exhaust_a = mean([n.war_exhaustion for n in att])
    exhaust_d = mean([n.war_exhaustion for n in dfn])
    decisive = abs(war.warscore) > 0.45
    stalemate = length > 300 and abs(war.warscore) < 0.20
    collapse = exhaust_a > 0.55 or exhaust_d > 0.55
    p = 0.010                              # wars end on their own, given time
    if decisive:
        p += 0.045
    if stalemate:
        p += 0.030
    if collapse:
        p += 0.070
    if war.nuclear:
        p += 0.08
    if length < 60:
        p *= 0.15
    if not rng.chance(p):
        return
    winner = "attacker" if war.warscore > 0.12 else ("defender" if war.warscore < -0.12 else None)
    end_war(w, war, winner)


def end_war(w, war, winner: str | None) -> None:
    war.ended = w.clock.day
    att = [w.nations[n] for n in war.attackers if n in w.nations]
    dfn = [w.nations[n] for n in war.defenders if n in w.nations]
    for a in att:
        for d in dfn:
            a.at_war.discard(d.id)
            d.at_war.discard(a.id)
            a.relations[d.id] = clamp(a.relation(d.id) + 0.25, -1, 0.2)
            d.relations[a.id] = clamp(d.relation(a.id) + 0.25, -1, 0.2)
    for n in att + dfn:
        n.mobilised = clamp01(n.mobilised - 0.4)
        n.__dict__["_blockade"] = 0.0

    if winner == "attacker" and att and dfn:
        victor, loser = att[0], dfn[0]
        _apply_peace(w, war, victor, loser)
    elif winner == "defender" and att and dfn:
        victor, loser = dfn[0], att[0]
        if war.goal in ("annex_region", "resource_grab", "unify"):
            loser.prestige = clamp01(loser.prestige - 0.12)
        _apply_peace(w, war, victor, loser, punitive=True)
    else:
        for rid in list(war.occupied):
            r = w.regions.get(rid)
            if r:
                r.occupier = None
        w.report(f"{war.name} ends in a negotiated stalemate after "
                 f"{(w.clock.day - war.started) // 30} months.", "war", weight=0.85, tags=["peace"])
        return
    w.report(f"{war.name} ends. {(winner or 'nobody').title()} prevails after "
             f"{(w.clock.day - war.started) // 30} months and "
             f"{sum(war.casualties.values()) / 1e6:.2f}M dead.",
             "war", weight=0.95, tags=["peace"])


def _apply_peace(w, war, victor, loser, punitive: bool = False) -> None:
    goal = war.goal
    taken = [rid for rid, holder in war.occupied.items() if holder == victor.id
             and rid in w.regions and w.regions[rid].nation == loser.id]
    if goal in ("annex_region", "resource_grab") and taken:
        for rid in taken[:max(1, len(taken) // 2 + 1)]:
            transfer_region(w, rid, victor.id)
    elif goal == "unify" and taken:
        for rid in list(loser.regions):
            transfer_region(w, rid, victor.id)
    elif goal == "vassalise":
        loser.puppet_of = victor.id
        loser.treaties.setdefault(victor.id, set()).add("vassalage")
        victor.treaties.setdefault(loser.id, set()).add("vassalage")
        w.report(f"{loser.name} is reduced to a client state of {victor.name}.",
                 "diplomacy", victor.id, 0.9, ["vassal"])
    elif goal == "regime_change":
        _install_leader(w, loser, w.rng.sub("peace"), "junta")
        loser.ideology = {k: lerp(loser.ideology[k], victor.ideology[k], 0.6) for k in AXES}
        loser.legitimacy = clamp01(loser.legitimacy - 0.2)
        loser.unrest = clamp01(loser.unrest + 0.15)
    elif goal == "liberate" and taken:
        for rid in taken[:2]:
            _secede(w, rid)
    elif goal == "disarm":
        for u in list(loser.forces):
            loser.forces[u] *= 0.4
        loser.nuke_program = 0.0
    if goal in ("reparations", "punitive") or punitive:
        amount = min(loser.treasury * 0.5 + loser.gdp * 90, loser.gdp * 200)
        loser.treasury = max(0.0, loser.treasury - amount)
        loser.debt += amount * 0.5
        victor.treasury += amount
    for rid in list(war.occupied):
        r = w.regions.get(rid)
        if r and r.nation != war.occupied[rid]:
            r.occupier = None
    victor.prestige = clamp01(victor.prestige + 0.10)
    loser.prestige = clamp01(loser.prestige - 0.12)
    loser.legitimacy = clamp01(loser.legitimacy - 0.10)


def transfer_region(w, rid: str, to_nation: str) -> None:
    r = w.regions.get(rid)
    if r is None:
        return
    old = w.nations.get(r.nation)
    new = w.nations.get(to_nation)
    if old is None or new is None:
        return
    if rid in old.regions:
        old.regions.remove(rid)
    if rid not in new.regions:
        new.regions.append(rid)
    r.nation = to_nation
    r.occupier = None
    r.separatism = clamp01(r.separatism + 0.35)
    r.unrest = clamp01(r.unrest + 0.20)
    r.control = 0.45
    old.pop = sum(w.regions[x].pop for x in old.regions if x in w.regions)
    new.pop = sum(w.regions[x].pop for x in new.regions if x in w.regions)
    if not old.regions:
        old.alive = False
        w.report(f"{old.formal} ceases to exist.", "politics", weight=1.0, tags=["annexed"])
    elif old.capital and w.cities.get(old.capital) and \
            w.cities[old.capital].region == rid:
        cs = w.nation_cities(old.id)
        if cs:
            cap = max(cs, key=lambda c: c.pop)
            cap.capital = True
            old.capital = cap.id


def _secede(w, rid: str) -> None:
    from . import names as N
    r = w.regions.get(rid)
    if r is None:
        return
    old = w.nations.get(r.nation)
    if old is None or len(old.regions) <= 1:
        return
    from .entities import Nation
    short, formal = N.nation_name(w.rng.sub("secede"), r.culture)
    nid = w.nid("N")
    from . import worldmap as WM
    nat = Nation(nid, short, formal, r.culture)
    nat.flagcolour = WM.pal_for(nid)
    nat.gov = "council_state"
    nat.tech_level = old.tech_level * 0.85
    nat.techs = set(old.techs)
    nat.ideology = dict(old.ideology)
    nat.policy = dict(old.policy)
    nat.legitimacy = 0.55
    nat.founded = w.clock.day
    w.nations[nid] = nat
    old.regions.remove(rid)
    nat.regions.append(rid)
    r.nation = nid
    r.core_of = nid
    r.separatism = 0.0
    r.unrest = clamp01(r.unrest * 0.5)
    nat.pop = r.pop
    old.pop = sum(w.regions[x].pop for x in old.regions if x in w.regions)
    if r.cities:
        cap = max((w.cities[c] for c in r.cities if c in w.cities), key=lambda c: c.pop, default=None)
        if cap:
            cap.capital = True
            nat.capital = cap.id
    for other in w.living_nations():
        nat.relations[other.id] = clamp(other.relation(old.id) * 0.4, -1, 1)
        other.relations[nid] = -0.4 if other.id == old.id else 0.0
    nat.relations[old.id] = -0.7
    old.relations[nid] = -0.8
    w.report(f"{r.name} declares independence as {formal}.",
             "politics", nid, 1.0, ["secession"])


def tick_insurgency(w) -> None:
    """Civil wars, separatist risings and the slow rot of state control."""
    rng = w.rng.sub("insurgency")
    for nat in w.living_nations():
        deep = [w.regions[r] for r in nat.regions
                if r in w.regions and w.regions[r].insurgency > 0.45]
        if deep and not nat.civil_war and rng.chance(0.004 * len(deep)):
            nat.civil_war = True
            w.report(f"Civil war engulfs {nat.name}: {len(deep)} regions are beyond "
                     f"government control.", "war", nat.id, 1.0, ["civil_war"])
        if nat.civil_war:
            nat.state_capacity = clamp01(nat.state_capacity - 0.0008)
            if not deep:
                nat.civil_war = False
                w.report(f"The civil war in {nat.name} burns out.", "war", nat.id, 0.8)
        for rid in list(nat.regions):
            r = w.regions.get(rid)
            if r is None:
                continue
            if r.separatism > 0.85 and r.insurgency > 0.55 and rng.chance(0.00035):
                _secede(w, rid)


def tick_military(w) -> None:
    """Recruitment, procurement, readiness and morale between the battles."""
    rng = w.rng.sub("military")
    for nat in w.living_nations():
        budget = nat.gdp * nat.get_policy("military") * 0.035
        upkeep = sum(UNITS[u]["up"] * n for u, n in nat.forces.items())
        if upkeep > budget * 1.05:
            # cannot pay: units wither
            for u in list(nat.forces):
                nat.forces[u] *= 0.9995
                if nat.forces[u] < 0.5:
                    del nat.forces[u]
            nat.morale = clamp01(nat.morale - 0.0009)
            nat.readiness = clamp01(nat.readiness - 0.0012)
        else:
            spare = budget - upkeep
            pool = [u for u, d in UNITS.items()
                    if (d["tech"] is None or d["tech"] in nat.techs)
                    and (d["dom"] != "nuclear" or nat.nukes > 0)
                    and (d["dom"] != "sea" or any(w.regions[r].coastal for r in nat.regions
                                                  if r in w.regions))]
            if pool and spare > 0:
                want = rng.weighted(pool, [
                    (2.5 if UNITS[u]["dom"] == "land" else 1.0)
                    * (1 + 2 * nat.tech_level if UNITS[u]["cost"] > 1e9 else 1.0)
                    * (2.0 if nat.at_war and UNITS[u]["dom"] in ("land", "air") else 1.0)
                    for u in pool])
                n = spare * 30 / UNITS[want]["cost"]
                if n > 0:
                    nat.forces[want] = nat.forces.get(want, 0.0) + n
            nat.readiness = clamp01(nat.readiness + 0.0008 * (0.5 + nat.get_policy("military")))
            nat.morale = clamp01(nat.morale + 0.0010 * nat.legitimacy)
        nat.manpower = sum(UNITS[u]["men"] * n for u, n in nat.forces.items())
        pool_growth = nat.pop * (0.00002 + 0.00018 * nat.get_policy("conscription"))
        nat.reserves_men = min(nat.pop * 0.09, nat.reserves_men + pool_growth)
        nat.mobilised = clamp01(nat.mobilised - (0.0 if nat.at_war else 0.003))
        # nuclear programmes
        if nat.nuke_program > 0 and nat.nukes == 0:
            nat.nuke_program = clamp01(nat.nuke_program + 0.0006 * nat.tech_level)
            if nat.nuke_program >= 1.0:
                nat.nukes = 1
                w.report(f"{nat.name} conducts a successful nuclear test.",
                         "war", nat.id, 1.0, ["nuclear"])
                w.tension = clamp01(w.tension + 0.08)
                w.doomsday = clamp01(w.doomsday + 0.03)
        elif nat.nukes > 0 and "thermonuclear" in nat.techs and rng.chance(0.02):
            nat.nukes += 1
