#!/usr/bin/env python3
"""Bundle the scripted per-machine tests into one Lua file for the Simulator
autotest: SIM_TESTS = { camera = function() ... end, ... }.

Usage: python3 tools/bundle_sim_tests.py > <src>/sim_tests.lua
"""
import pathlib

root = pathlib.Path(__file__).resolve().parent
MACHINES = ["billion", "camera", "civilization", "clockmaker", "elevator", "fishing",
            "lighthouse", "microfiche", "numbers", "projectionist", "safecracker_solve",
            "well", "winch"]
out = ["SIM_TESTS = {}"]
for name in MACHINES:
    src = (root / f"test_{name}.lua").read_text()
    out.append(f"SIM_TESTS[{name!r}] = function()\n{src}\nend")
print("\n".join(out).replace("SIM_TESTS['", 'SIM_TESTS["').replace("'] = function", '"] = function'))
