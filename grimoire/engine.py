"""The tick loop: the order in which the world updates each day."""
from __future__ import annotations

import time

from . import sim_covert as CV
from . import sim_economy as EC
from . import sim_power as PW
from . import sim_society as SO
from . import sim_world as WD
from . import victory
from .player import tick_player
from .util import clamp01


def tick(w, with_player: bool = True) -> list[dict]:
    """Advance the world by one day. Returns operation results for the player."""
    c = w.clock
    day = c.day

    # --- scheduled callbacks -------------------------------------------
    for _due, kind, payload in w.due():
        _handle_scheduled(w, kind, payload)

    # --- economy --------------------------------------------------------
    EC.tick_economy(w)
    EC.tick_firms(w)
    EC.tick_markets_sentiment(w)
    EC.tick_labour(w)
    if day % 10 == 0:
        EC.tick_reallocation(w)
    if day % 5 == 0:
        EC.tick_inequality(w)

    # --- society --------------------------------------------------------
    SO.tick_population(w)
    SO.tick_migration(w)
    SO.tick_health(w)
    if day % 2 == 0:
        SO.spread_epidemics(w)
    SO.maybe_outbreak(w)
    SO.tick_information(w)
    SO.tick_media(w)
    SO.tick_faith(w)
    SO.tick_culture(w)

    # --- power ----------------------------------------------------------
    PW.tick_politics(w)
    PW.tick_unrest(w)
    PW.tick_elections(w)
    PW.tick_diplomacy(w)
    PW.maybe_declare_war(w)
    PW.tick_wars(w)
    PW.tick_insurgency(w)
    PW.tick_military(w)

    # --- world ----------------------------------------------------------
    WD.tick_research(w)
    WD.tick_environment(w)
    WD.maybe_disaster(w)
    WD.tick_people(w)
    WD.tick_crises(w)

    # --- covert ---------------------------------------------------------
    CV.tick_agency_ops(w)
    CV.tick_crime(w)
    results = CV.tick_operations(w)

    if day % 3 == 0:
        w.recompute_globals()

    if with_player and w.player is not None:
        tick_player(w)
        _player_projects(w)

    c.advance()
    return [r for r in results if r["actor"] == "PLAYER"]


def _handle_scheduled(w, kind: str, payload: dict) -> None:
    if kind == "retaliate":
        src = w.nations.get(payload["from"])
        dst = w.nations.get(payload["to"])
        war = w.wars.get(payload["war"])
        if src and dst and war and src.nukes > 0:
            PW._nuclear_strike(w, src, dst, war, w.rng.sub("retaliation"))
    elif kind == "message":
        w.tell(payload.get("text", ""), payload.get("kind", "info"))


def _player_projects(w) -> None:
    pl = w.player
    for pid in pl.projects:
        pr = w.projects.get(pid)
        if pr is None or pr.done:
            continue
        # a completed singularity accelerates everything else
        if pl.flags.get("singularity"):
            pr.progress = clamp01(pr.progress + 0.0009)
        if pr.secret:
            pr.exposure = clamp01(pr.exposure + 0.0006 * (1 + pr.progress))
            if pr.exposure > 0.85 and w.rng.sub("proj").chance(0.01):
                pr.secret = False
                w.report(f"Investigators expose a covert programme: {pr.name}.",
                         "intel", weight=0.9, tags=["player", "exposed"])
                pl.heat = clamp01(pl.heat + 0.15)


def run_days(w, n: int, on_day=None, stop_on_event: bool = True) -> dict:
    """Fast-forward. Returns a digest of what happened."""
    t0 = time.time()
    digest = {"days": 0, "ops": [], "messages": [], "ended": None}
    start_news = len(w.news)
    for i in range(n):
        ops = tick(w)
        digest["ops"] += ops
        digest["days"] += 1
        if on_day:
            on_day(w, i)
        if w.player is not None:
            end = victory.check_end(w, w.player)
            if end:
                digest["ended"] = end
                break
            if stop_on_event and (ops or w.messages):
                break
    digest["news"] = w.news[start_news:]
    digest["elapsed"] = time.time() - t0
    return digest
