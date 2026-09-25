#!/usr/bin/env python3
"""Static check: every playdate.* / gfx.* / json.* reference and every
method called on a known SDK object must exist in the documented API
(tests/pd_api.lua, generated from the SDK docs stub).

Usage: python3 tools/check_api.py      (exit 1 on unknown APIs)
"""
import re, sys, pathlib

root = pathlib.Path(__file__).resolve().parent.parent
api = (root / "tests/pd_api.lua").read_text()
functions = set(re.findall(r'\["(playdate[\w\.]*)"\] = true', api))
constants = set(re.findall(r'\["(playdate[\w\.]*k\w+)"\] = true', api))
methods = {}
for owner, names in re.findall(r'\["([\w\.]+)"\] = \{ ([^}]*) \}', api):
    methods[owner] = set(re.findall(r'"(\w+)"', names))

# Namespaces are valid prefixes too (playdate.graphics, playdate.network.http ...).
namespaces = set()
for name in functions | constants:
    parts = name.split(".")
    for i in range(1, len(parts)):
        namespaces.add(".".join(parts[:i]))
namespaces |= set(methods)

# Callbacks the game defines on the playdate table (documented as callbacks).
callbacks = {"playdate.update", "playdate.gameWillTerminate", "playdate.deviceWillSleep",
             "playdate.deviceWillLock", "playdate.gameWillPause", "playdate.gameWillResume",
             "playdate.keyboard.keyboardWillHideCallback", "playdate.keyboard.textChangedCallback",
             "playdate.keyboard.text"}
json_api = {"json.encode", "json.decode", "json.encodePretty", "json.decodeFile", "json.encodeToFile"}

errors = []
src = root / "source"
for f in sorted(src.rglob("*.lua")):
    text = f.read_text()
    code = re.sub(r"--\[\[.*?\]\]", "", text, flags=re.S)
    lines = code.splitlines()
    for ln, line in enumerate(lines, 1):
        line = re.sub(r'"(?:[^"\\]|\\.)*"', '""', line)          # strip strings
        line = re.sub(r"--.*$", "", line)                          # strip comments
        line = re.sub(r"\bgfx\.", "playdate.graphics.", line)
        for m in re.finditer(r"\bplaydate(?:\.\w+)+", line):
            name = m.group(0)
            if name in functions or name in constants or name in namespaces or name in callbacks:
                continue
            errors.append(f"{f.relative_to(root)}:{ln}: unknown API {name}")
        for m in re.finditer(r"\bjson\.\w+", line):
            if m.group(0) not in json_api:
                errors.append(f"{f.relative_to(root)}:{ln}: unknown API {m.group(0)}")

# Method calls on SDK objects we create: map variable naming conventions.
OBJECT_HINTS = [
    (r"\b(?:img|image|glyph|g)\s*:\s*(\w+)\(", "playdate.graphics.image"),
    (r"\bconn\s*:\s*(\w+)\(", "playdate.network.http"),
    (r"\b(?:menu)\s*:\s*(\w+)\(", "playdate.menu"),
    (r"\bApp\.menu\.\w+\s*:\s*(\w+)\(", "playdate.menu.item"),
    (r"\bv\s*:\s*(playNote|noteOff|setADSR|setVolume)\(", "playdate.sound.synth"),
]
for f in sorted(src.rglob("*.lua")):
    for ln, line in enumerate(f.read_text().splitlines(), 1):
        for pat, owner in OBJECT_HINTS:
            for m in re.finditer(pat, line):
                if m.group(1) not in methods.get(owner, set()):
                    errors.append(f"{f.relative_to(root)}:{ln}: {owner} has no method {m.group(1)}")
        for m in re.finditer(r"\bconn\.(\w+)\b", line):
            if m.group(1) not in methods.get("playdate.network.http", set()):
                errors.append(f"{f.relative_to(root)}:{ln}: playdate.network.http has no method {m.group(1)}")

if errors:
    print("\n".join(errors))
    sys.exit(1)
print("API check OK: every playdate.* reference is documented.")
