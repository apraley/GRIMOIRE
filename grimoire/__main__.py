"""Entry point: python3 -m grimoire"""
from __future__ import annotations

import argparse
import os
import sys

from . import ui
from .shell import SAVE_DIR, Shell


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(
        prog="grimoire", description="GRIMOIRE — a world simulator you play one person inside.")
    ap.add_argument("--seed", type=int, default=None, help="world seed")
    ap.add_argument("--load", metavar="NAME", help="resume a save")
    ap.add_argument("--no-color", action="store_true", help="disable ANSI colour")
    ap.add_argument("--script", metavar="FILE", help="run commands from a file, then exit")
    args = ap.parse_args(argv)

    if args.no_color:
        ui.set_color(False)
    sh = Shell()
    if args.load:
        path = os.path.join(SAVE_DIR, f"{args.load}.grim")
        if not os.path.exists(path):
            print(f"no save called {args.load!r}")
            return 1
        sh.load(args.load)
    else:
        sh.new_game(args.seed)
    if args.script:
        with open(args.script) as fh:
            for line in fh:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                print(ui.c(f"\n> {line}", "b"))
                sh.handle(line)
                if not sh.running:
                    break
        return 0
    sh.run()
    return 0


if __name__ == "__main__":
    sys.exit(main())
