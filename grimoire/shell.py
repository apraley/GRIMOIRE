"""The interactive shell: parse commands, run days, print the world."""
from __future__ import annotations

import os
import sys
import traceback

from . import actions as A
from . import serial
from . import ui
from . import victory
from . import views
from .content_social import BACKGROUNDS, TRAITS
from .engine import tick
from .player import PLAYER_ID, create_player
from .util import clamp01, fmt_money, fmt_num, fmt_pct, truncate
from .worldgen import generate_world

SAVE_DIR = os.path.expanduser("~/.grimoire")

BANNER = r"""
   ▄▄▄  ▄▄▄  ▄ ▄  ▄  ▄▄▄  ▄ ▄▄  ▄▄▄
  █     █▄▄▀ █ █ ▄█ █   █ █ █▄▀ █▄▄
  █ ▀█  █ ▀▄ █ █ █▀ █   █ █ █ █ █
   ▀▀▀  ▀  ▀ ▀ ▀ ▀   ▀▀▀  ▀ ▀ ▀ ▀▀▀
"""


class Shell:
    def __init__(self, world=None):
        self.w = world
        self.running = True
        self.autosave = True
        self.last_digest = None

    # ------------------------------------------------------------------ io
    def say(self, *lines):
        ui.page(list(lines) if len(lines) > 1 else [lines[0] if lines else ""])

    def emit(self, lines):
        ui.page(lines)

    def prompt(self) -> str:
        pl = self.w.player
        p = pl.me(self.w)
        nat = self.w.nations.get(p.nation)
        c = self.w.cities.get(p.city)
        loc = truncate(c.name if c else (nat.name if nat else "?"), 16)
        heat = pl.heat
        hcol = "G" if heat < 0.25 else ("Y" if heat < 0.55 else "R")
        bits = [ui.c(self.w.clock.short(), "Cy"),
                ui.c(loc, "W"),
                ui.c(f"{pl.ap}ap", "G" if pl.ap else "K"),
                ui.c(fmt_money(pl.money), "G" if pl.money > 0 else "R"),
                ui.c(f"♨{fmt_pct(heat)}", hcol)]
        return ui.c(" │ ", "K").join(bits) + ui.c(" ❯ ", "b")

    # -------------------------------------------------------------- new game
    def new_game(self, seed: int | None = None, quick: bool = False) -> None:
        import random
        seed = seed if seed is not None else random.randint(1, 10 ** 9)
        self.say(ui.c(BANNER, "Cy"))
        self.say(ui.c("  GRIMOIRE — a world, and your attempt to take it", "b"))
        self.say(ui.c(f"  world seed {seed}", "K"), "")
        self.say(ui.c("  Building a planet…", "K"))
        w = generate_world(seed, log=lambda s: self.say(ui.c(f"    {s}", "K")))
        w.recompute_globals()
        self.w = w
        self.say("")
        # -- choose a country
        pool = sorted(w.living_nations(), key=lambda n: -n.power())
        choices = pool[:6] + [n for n in pool[6:] if n.tech_level < 0.45][:4]
        self.say(ui.header("Where do you begin?"))
        rows = []
        for i, n in enumerate(choices, 1):
            rows.append([str(i), n.name, n.gov.replace("_", " "), fmt_num(n.pop),
                         fmt_money(n.gdp_per_capita(), places=0), fmt_pct(n.tech_level),
                         fmt_pct(n.stability), str(n.nukes) if n.nukes else ""])
        self.emit(ui.table(rows, ["#", "nation", "government", "pop", "GDP/cap",
                                  "tech", "stability", "nukes"],
                           ["<", "<", "<", ">", ">", ">", ">", ">"]))
        nat = choices[self._ask_index("Country", len(choices), 0) ]
        # -- choose a background
        self.say("")
        self.say(ui.header("Who are you?"))
        bgs = list(BACKGROUNDS)
        for i, k in enumerate(bgs, 1):
            b = BACKGROUNDS[k]
            self.say(f"  {ui.c(str(i).rjust(2), 'b')}. {ui.pad(b['label'], 24)}"
                     f"{ui.c(fmt_money(b['wealth']), 'G')}")
            self.emit(ui.para(b["blurb"], "      "))
        bg = bgs[self._ask_index("Background", len(bgs), 0)]
        # -- name and traits
        self.say("")
        default = _suggest_name(w, nat)
        name = self._ask(f"Your name [{default}]: ").strip() or default
        female = (self._ask("Woman / man / neither (w/m/n) [w]: ").strip().lower() or "w")
        rng = w.rng.sub("chargen")
        traits = rng.sample(list(TRAITS), 3)
        self.say("")
        self.say(ui.c(f"  Traits: {', '.join(traits)}", "K"))
        pl = create_player(w, name, bg, nat.id, female.startswith("w"),
                           age=rng.randint(31, 49), traits=traits)
        self.say("")
        self.emit(ui.banner(f"{name} — {BACKGROUNDS[bg]['label']} of {nat.name}"))
        self.emit(ui.para(BACKGROUNDS[bg]["blurb"], "  "))
        self.say("")
        self.emit(ui.para(
            "You have one life, a limited number of hours in each day, and an entire "
            "planet that does not know you exist. It will keep running whether you act "
            "or not: markets clear, governments fall, wars start, people age and die. "
            "Type 'help' for what you can do, 'goals' for the ways this ends with you "
            "on top, and 'wait' to let the world move.", "  "))
        self.say("")
        self.emit(views.dashboard(w))

    def _ask(self, text: str) -> str:
        try:
            return input(ui.c(text, "b"))
        except (EOFError, KeyboardInterrupt):
            return ""

    def _ask_index(self, label: str, n: int, default: int) -> int:
        while True:
            raw = self._ask(f"  {label} [1-{n}, default {default + 1}]: ").strip()
            if not raw:
                return default
            try:
                v = int(raw) - 1
            except ValueError:
                continue
            if 0 <= v < n:
                return v

    # ------------------------------------------------------------- main loop
    def run(self) -> None:
        while self.running:
            self.flush_messages()
            end = victory.check_end(self.w, self.w.player)
            if end:
                self.finish(end)
                return
            try:
                raw = input(self.prompt())
            except (EOFError, KeyboardInterrupt):
                self.say("")
                self.say(ui.c("  Leaving the world running without you.", "K"))
                return
            self.handle(raw)

    def flush_messages(self) -> None:
        msgs = self.w.messages
        if not msgs:
            return
        self.w.messages = []
        out = []
        for day, kind, text in msgs:
            col = {"bad": "R", "warn": "Y", "good": "G"}.get(kind, "Cy")
            out.append(ui.c("  ▸ ", col) + ui.c(text, col if kind != "info" else "w"))
        self.emit([""] + out + [""])

    def handle(self, raw: str) -> None:
        raw = raw.strip()
        if not raw:
            return
        if ";" in raw:
            for part in raw.split(";"):
                self.handle(part)
            return
        word, _, rest = raw.partition(" ")
        cmd = word.lower()
        rest = rest.strip()
        try:
            if self.screen(cmd, rest):
                return
            out = A.perform(self.w, self.w.player, cmd, rest)
            self.emit([""] + out)
        except A.ActionError as e:
            self.say(ui.c(f"  {e}", "y"))
        except Exception:
            self.say(ui.c("  Something went wrong inside the simulation:", "R"))
            self.say(ui.c(traceback.format_exc(limit=3), "K"))

    # --------------------------------------------------------------- screens
    def screen(self, cmd: str, rest: str) -> bool:
        w = self.w
        pl = w.player
        S = {
            "status": lambda: views.dashboard(w), "dash": lambda: views.dashboard(w),
            "st": lambda: views.dashboard(w),
            "map": lambda: views.map_view(w, rest or "political",
                                          step=2 if "small" in rest else 1),
            "news": lambda: self._news(rest),
            "market": lambda: views.market_view(w, rest),
            "prices": lambda: views.market_view(w, rest),
            "wars": lambda: views.war_view(w),
            "powers": lambda: views.rankings_view(w, rest or "power"),
            "rank": lambda: views.rankings_view(w, rest or "power"),
            "intel": lambda: views.intel_view(w),
            "ledger": lambda: views.ledger_view(w),
            "money": lambda: views.ledger_view(w),
            "goals": lambda: views.victory_view(w),
            "victory": lambda: views.victory_view(w),
            "skills": lambda: views.skills_view(w),
            "timeline": lambda: views.timeline_view(w),
            "people": lambda: views.people_view(w, rest),
            "help": lambda: views.help_view(w, rest),
            "?": lambda: views.help_view(w, rest),
            "actions": lambda: views.help_view(w, rest),
        }
        if cmd in S:
            self.emit([""] + S[cmd]())
            return True
        if cmd in ("tech", "research"):
            nat = w.find_nation(rest) if rest else pl.nation(w)
            self.emit([""] + views.tech_view(w, nat))
            return True
        if cmd in ("nation", "country"):
            nat = w.find_nation(rest) if rest else pl.nation(w)
            if nat is None:
                self.say(ui.c(f"  No nation matching {rest!r}.", "y"))
            else:
                self.emit([""] + views.nation_view(w, nat))
            return True
        if cmd in ("who", "person", "dossier"):
            p = w.find_person(rest)
            if p is None:
                self.say(ui.c(f"  Nobody called {rest!r}.", "y"))
            else:
                self.emit([""] + views.person_view(w, p))
            return True
        if cmd in ("region", "province"):
            r = w.find_region(rest) if rest else pl.region(w)
            if r is None:
                self.say(ui.c(f"  No region matching {rest!r}.", "y"))
            else:
                self.emit([""] + views.region_view(w, r))
            return True
        if cmd == "city":
            c = w.find_city(rest) if rest else pl.city(w)
            if c is None:
                self.say(ui.c(f"  No city matching {rest!r}.", "y"))
            else:
                self.emit([""] + views.city_view(w, c))
            return True
        if cmd in ("org", "company", "firm"):
            o = w.find_org(rest)
            if o is None:
                self.say(ui.c(f"  No organisation matching {rest!r}.", "y"))
            else:
                self.emit([""] + views.org_view(w, o))
            return True
        if cmd in ("wait", "next", "end", "n", "w"):
            self.advance(rest)
            return True
        if cmd == "save":
            self.save(rest or "auto")
            return True
        if cmd == "load":
            self.load(rest or "auto")
            return True
        if cmd in ("saves", "list"):
            self.list_saves()
            return True
        if cmd in ("quit", "exit", "q"):
            if self.autosave:
                self.save("auto", quiet=True)
            self.say(ui.c("  The world continues without you.", "K"))
            self.running = False
            return True
        if cmd == "colour" or cmd == "color":
            ui.set_color(rest.lower() not in ("off", "no", "0"))
            self.say(f"  Colour {'on' if ui.color_enabled() else 'off'}.")
            return True
        if cmd == "seed":
            self.say(f"  World seed: {w.seed}")
            return True
        return False

    def _news(self, rest: str):
        parts = rest.split()
        days = 14
        cat = None
        for p in parts:
            if p.isdigit():
                days = int(p)
            else:
                cat = p
        return views.news_view(self.w, days, cat)

    # ------------------------------------------------------------- advancing
    def advance(self, rest: str) -> None:
        w = self.w
        pl = w.player
        try:
            n = max(1, min(3600, int(rest))) if rest.strip() else 1
        except ValueError:
            n = 1
        day0 = w.clock.day
        news0 = len(w.news)
        results = []
        interrupted = None
        for i in range(n):
            res = tick(w)
            results += res
            end = victory.check_end(w, pl)
            if end:
                interrupted = "end"
                break
            if res or w.messages:
                interrupted = "event"
                if i < n - 1:
                    break
            if n > 20 and i % 30 == 29:
                sys.stdout.write(ui.c(f"\r  …{i + 1}/{n} days", "K"))
                sys.stdout.flush()
        if n > 20:
            sys.stdout.write("\r" + " " * 30 + "\r")
        elapsed = w.clock.day - day0
        out = [""]
        out.append(ui.c(f"── {elapsed} day{'s' if elapsed != 1 else ''} pass "
                        f"─── {w.clock.long()} " + "─" * 12, "K"))
        for r in results:
            out += self._op_report(r)
        fresh = [x for x in w.news[news0:] if x.weight >= (0.55 if elapsed > 3 else 0.35)]
        fresh.sort(key=lambda x: -x.weight)
        if fresh:
            out.append("")
            for item in fresh[:12]:
                out += ui.bullet(item.text, "▪", "K")
            if len(fresh) > 12:
                out.append(ui.c(f"    … {len(fresh) - 12} more — 'news {max(elapsed, 1)}'", "K"))
        pnews = [x for x in w.news[news0:] if "player" in x.tags]
        for item in pnews:
            out.append(ui.c("  ▸ " + item.text, "Y"))
        self.emit(out)
        if interrupted == "event" and elapsed < n:
            self.say(ui.c(f"  (stopped early — something happened)", "K"))

    def _op_report(self, r: dict) -> list[str]:
        col = "G" if r["success"] else "R"
        head = (ui.c(f"  ▸ {r['codename']}", col, "b")
                + ui.c(f"  [{r['kind']}]  ", "K")
                + (ui.c("SUCCESS", "G") if r["success"] else ui.c("FAILURE", "R"))
                + (ui.c("  EXPOSED", "R", "b") if r["exposed"] else ""))
        out = ["", head]
        out += ui.para(r["text"], "     ")
        d = r.get("detail", {})
        if d.get("secrets"):
            for s in d["secrets"]:
                out.append(ui.c(f"     • {s}", "y"))
        if d.get("pattern"):
            pat = d["pattern"]
            out.append(ui.c(f"     role {pat['role']}, influence {pat['power']}, "
                            f"wealth {fmt_money(pat['wealth'])}, loyalty {pat['loyalty']}, "
                            f"corruptible {pat['corruptible']}", "K"))
        if d.get("intel"):
            i = d["intel"]
            out.append(ui.c(f"     {len(i['forces'])} formation types, {i['nukes']} warheads, "
                            f"treasury {fmt_money(i['treasury'])}, {i['techs']} technologies, "
                            f"stability {i['stability']}", "K"))
        if d.get("amount"):
            out.append(ui.c(f"     {fmt_money(d['amount'])} moved.", "G"))
        if d.get("tech"):
            out.append(ui.c(f"     acquired: {d['tech'].replace('_', ' ')}", "G"))
        return out

    # ------------------------------------------------------------- finishing
    def finish(self, end: str) -> None:
        w = self.w
        pl = w.player
        p = w.people[PLAYER_ID]
        self.say("")
        if end.startswith("won:"):
            path = end.split(":", 1)[1]
            self.emit(ui.banner(f"{victory.PATHS[path]['label'].upper()}", "Y"))
            self.emit(ui.para(victory.ENDINGS[path], "  "))
        else:
            self.emit(ui.banner("IT ENDS", "R"))
            self.emit(ui.para(victory.ENDINGS.get(end, "It ends."), "  "))
            if end == "death":
                self.say(ui.c(f"\n  {p.name}, {int(p.age)} — {p.death_cause}.", "K"))
        self.say("")
        self.emit(self._epitaph())
        self.running = False

    def _epitaph(self) -> list[str]:
        w = self.w
        pl = w.player
        scores = victory.evaluate(w, pl)
        out = [ui.header("What you built", f"{w.clock.day} days")]
        out += ui.kv([
            ("Net worth", fmt_money(pl.net_worth(w))),
            ("Organisations", str(len(pl.orgs))),
            ("Assets run", str(len(pl.assets))),
            ("Operations", str(len(pl.op_history))),
            ("Fame", fmt_pct(pl.fame)),
            ("Heat at the end", fmt_pct(pl.heat)),
        ], cols=2, keyw=18)
        out.append("")
        for k, v in sorted(scores.items(), key=lambda kv: -kv[1]):
            out.append(f"  {ui.pad(victory.PATHS[k]['label'], 14)}{ui.meter(v, 30)} {fmt_pct(v)}")
        if pl.timeline:
            out.append("")
            out.append(ui.c("Your history", "b"))
            for day, text in pl.timeline[-14:]:
                out.append(f"  {ui.c('d' + str(day).rjust(6), 'K')}  {text}")
        return out

    # ---------------------------------------------------------------- saving
    def save(self, name: str, quiet: bool = False) -> None:
        os.makedirs(SAVE_DIR, exist_ok=True)
        path = os.path.join(SAVE_DIR, f"{_slug(name)}.grim")
        try:
            n = serial.save_file(self.w, path)
        except Exception as e:
            self.say(ui.c(f"  Save failed: {e}", "R"))
            return
        if not quiet:
            self.say(ui.c(f"  Saved to {path} ({n / 1e6:.1f} MB uncompressed).", "K"))

    def load(self, name: str) -> None:
        path = os.path.join(SAVE_DIR, f"{_slug(name)}.grim")
        if not os.path.exists(path):
            self.say(ui.c(f"  No save called {name!r}. Try 'saves'.", "y"))
            return
        try:
            w = serial.load_file(path)
        except Exception as e:
            self.say(ui.c(f"  Load failed: {e}", "R"))
            return
        w.planet.activate()
        self.w = w
        self.say(ui.c(f"  Loaded {name}. {w.clock.long()}.", "K"))
        self.emit(views.dashboard(w))

    def list_saves(self) -> None:
        if not os.path.isdir(SAVE_DIR):
            self.say(ui.c("  No saves yet.", "K"))
            return
        files = sorted(f for f in os.listdir(SAVE_DIR) if f.endswith(".grim"))
        if not files:
            self.say(ui.c("  No saves yet.", "K"))
            return
        for f in files:
            p = os.path.join(SAVE_DIR, f)
            self.say(f"  {ui.pad(f[:-5], 24)}{os.path.getsize(p) / 1e6:.1f} MB")


def _slug(s: str) -> str:
    return "".join(ch if ch.isalnum() or ch in "-_" else "_" for ch in s.strip()) or "auto"


def _suggest_name(w, nat) -> str:
    from . import names as N
    return N.person_name(w.rng.sub("suggest"), nat.culture)
