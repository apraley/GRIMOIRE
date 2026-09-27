#!/usr/bin/env python3
"""Difficulty calibration: run each machine's scripted skilled player twice,
once perfect and once through the harness's human imperfection layer
(crank jitter, 3 turns/s cap, reaction delay), and compare the best scores
the save records against the machine's medal thresholds."""
import json, os, re, subprocess, sys, pathlib

root = pathlib.Path(__file__).resolve().parent.parent
ids = sys.argv[1:] or ["safecracker", "fishing", "camera", "microfiche", "numbers", "elevator",
                       "projectionist", "lighthouse", "winch", "well", "clockmaker", "civilization", "billion"]

def medals(mid):
    src = (root / "source/machines" / f"{mid}.lua").read_text()
    m = re.search(r"medals\s*=\s*\{\s*standard\s*=\s*\{\s*([\d_]+)\s*,\s*([\d_]+)\s*,\s*([\d_]+)", src)
    return tuple(int(x) for x in m.groups()) if m else None

def best(ddir, mid):
    out = None
    for slot in ("save_a", "save_b"):
        p = pathlib.Path(ddir) / f"{slot}.json"
        if not p.exists():
            continue
        t = json.loads(p.read_text())
        d = json.loads(t["payload"])
        g = lambda o, k: o.get(k, {}) if isinstance(o, dict) else {}
        bt = g(g(g(d, "machines"), mid), "best")
        b = bt.get("standard") if isinstance(bt, dict) else None
        b = b if isinstance(b, (int, float)) else None
        if b is not None and (out is None or t["seq"] > out[0]):
            out = (t["seq"], b)
    return out[1] if out else None

def run(mid, human):
    ddir = f"/tmp/cal-{mid}-{'h' if human else 'p'}"
    subprocess.run(["rm", "-rf", ddir])
    env = dict(os.environ, MOCK_DATA_DIR=ddir)
    if human:
        env.update(HUMAN_JITTER=os.environ.get("HUMAN_JITTER", "0.25"), HUMAN_MAX="36", HUMAN_DELAY=os.environ.get("HUMAN_DELAY", "5"))
    r = subprocess.run(["lua5.4", f"tools/test_{mid}.lua" if (root / f"tools/test_{mid}.lua").exists() else f"tools/test_{mid}_solve.lua"], cwd=root, env=env, capture_output=True, text=True, timeout=1800)
    return best(ddir, mid), r.returncode

def tier(score, md):
    if score is None or md is None:
        return "-"
    return ["none", "BRASS", "SILVER", "GOLD"][sum(1 for x in md if score >= x)]

print(f"{'machine':14} {'medals':>20} {'perfect':>9} {'':7} {'human':>9} {'':7}")
for mid in ids:
    md = medals(mid)
    p, _ = run(mid, False)
    h, _ = run(mid, True)
    print(f"{mid:14} {str(md):>20} {str(p):>9} {tier(p, md):7} {str(h):>9} {tier(h, md):7}", flush=True)
