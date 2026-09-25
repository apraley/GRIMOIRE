#!/usr/bin/env python3
"""Verify that every Playdate SDK function the game calls exists in the
official API list (playdate-luacats stub generated from Inside Playdate).

Usage: python3 tools/check_api.py [stub.lua]
"""
import re
import sys
import pathlib

root = pathlib.Path(__file__).resolve().parent.parent
stub_path = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else root / "tools" / "sdk_stub.lua"
stub = stub_path.read_text()

# functions and methods declared in the stub
funcs = set(re.findall(r"^function ([\w.]+)[.:](\w+)\(", stub, re.M))
qualified = {f"{a}.{b}" for a, b in funcs}
methods = {b for _, b in funcs}
fields = set(re.findall(r"^---@field (\w+)", stub, re.M))
consts = set(re.findall(r"\b(k[A-Z]\w+)\b", stub))

ALIASES = {
    "gfx": "playdate.graphics",
    "snd": "playdate.sound",
    "pd": "playdate",
}

# functions provided by the game itself or Lua, not the SDK
IGNORE_METHODS = {
    # Lua string methods
    "byte", "char", "find", "format", "gmatch", "gsub", "len", "lower", "match",
    "rep", "reverse", "sub", "upper", "pack", "unpack",
}

problems = []
src_files = sorted((root / "source").rglob("*.lua"))
game_methods = set()
for f in src_files:
    text = f.read_text()
    game_methods |= set(re.findall(r"function [\w.]+:(\w+)\(", text))
    game_methods |= set(re.findall(r"function [\w.]+\.(\w+)\(", text))
    game_methods |= set(re.findall(r"(\w+)\s*=\s*function", text))

for f in src_files:
    text = f.read_text()
    # strip comments
    text_nc = re.sub(r"--\[\[.*?\]\]", "", text, flags=re.S)
    text_nc = re.sub(r"--[^\n]*", "", text_nc)
    for lineno, line in enumerate(text_nc.splitlines(), 1):
        for m in re.finditer(r"\b(playdate(?:\.\w+)*|gfx|snd|pd)\.(\w+)", line):
            base, name = m.group(1), m.group(2)
            base = ALIASES.get(base, base)
            full = f"{base}.{name}"
            if name.startswith("k") and name[1:2].isupper():
                if name not in consts:
                    problems.append(f"{f.relative_to(root)}:{lineno}: unknown constant {full}")
                continue
            after = line[m.end():m.end() + 1]
            if after == "(":
                if full not in qualified:
                    # user callbacks like playdate.update are assignments, not calls
                    problems.append(f"{f.relative_to(root)}:{lineno}: unknown SDK function {full}")
            elif after in ("", " ", ")", ",", "}", "."):
                pass
        for m in re.finditer(r":(\w+)\(", line):
            name = m.group(1)
            if name not in methods and name not in game_methods and name not in IGNORE_METHODS:
                problems.append(f"{f.relative_to(root)}:{lineno}: unknown method :{name}()")

# Lua standard library functions that do not exist on Playdate
for f in src_files:
    text = f.read_text()
    for bad in (r"\bio\.", r"\bos\.", r"\brequire\(", r"\bpackage\.", r"\bloadfile\(", r"\bdofile\(", r"\bdebug\."):
        for lineno, line in enumerate(text.splitlines(), 1):
            code = line.split("--")[0]
            if re.search(bad, code):
                problems.append(f"{f.relative_to(root)}:{lineno}: '{bad}' is not available on Playdate")

if problems:
    print("\n".join(sorted(set(problems))))
    print(f"{len(set(problems))} problem(s)")
    sys.exit(1)
print(f"API check OK ({len(src_files)} files)")
