#!/usr/bin/env python3
"""Builds the CRANKING IT web player.

    cd web && npm install && python3 build.py           # -> web/dist/index.html
    python3 build.py --artifact                          # -> web/dist-artifact/ (page fragment,
                                                         #    wasmoon from jsdelivr)

The player runs the game's real Lua sources in wasmoon (Lua 5.4 compiled to
WebAssembly) against a browser implementation of the Playdate API
(runtime.js + playdate_web.lua).
"""
import base64, json, pathlib, shutil, sys

here = pathlib.Path(__file__).resolve().parent
root = here.parent
artifact = "--artifact" in sys.argv
out = here / ("dist-artifact" if artifact else "dist")
if out.exists():
    shutil.rmtree(out)
out.mkdir()

WASMOON_VERSION = "1.16.0"
wasmoon_dist = here / "node_modules" / "wasmoon" / "dist"
if not (wasmoon_dist / "glue.wasm").exists():
    sys.exit("wasmoon not installed: run `npm install` in web/ first")

# Lua sources, keyed by import path ("core/util", "machines/winch", ...)
sources = {}
for f in sorted((root / "source").rglob("*.lua")):
    sources[str(f.relative_to(root / "source"))[:-4]] = f.read_text()
sources["__playdate_web"] = (here / "playdate_web.lua").read_text()
(out / "game_data.js").write_text("window.CRANK_SOURCES = " + json.dumps(sources) + ";\n")

wasm_b64 = base64.b64encode((wasmoon_dist / "glue.wasm").read_bytes()).decode()
(out / "wasm_data.js").write_text('window.CRANK_WASM = "data:application/octet-stream;base64,' + wasm_b64 + '";\n')

shutil.copy(here / "runtime.js", out / "runtime.js")
shutil.copy(here / "font_data.js", out / "font_data.js")

if artifact:
    wasmoon_tag = f'<script src="https://cdn.jsdelivr.net/npm/wasmoon@{WASMOON_VERSION}/dist/index.js"></script>'
else:
    shutil.copy(wasmoon_dist / "index.js", out / "wasmoon.js")
    wasmoon_tag = '<script src="wasmoon.js"></script>'

scripts = "\n".join([
    wasmoon_tag,
    '<script src="font_data.js"></script>',
    '<script src="wasm_data.js"></script>',
    '<script src="game_data.js"></script>',
    '<script src="runtime.js"></script>',
])
page = (here / "player.html").read_text().replace("{{SCRIPTS}}", scripts)

if artifact:
    (out / "index.html").write_text(page)
else:
    head, body = page.split("</style>", 1)
    doc = ('<!doctype html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n'
           '<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">\n'
           + head + "</style>\n</head>\n<body>\n" + body + "\n</body>\n</html>\n")
    (out / "index.html").write_text(doc)

total = sum(p.stat().st_size for p in out.iterdir())
print(f"built {out.relative_to(root)} ({total // 1024} KB, {len(sources) - 1} Lua files)")
