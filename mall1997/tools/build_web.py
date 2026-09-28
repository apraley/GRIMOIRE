#!/usr/bin/env python3
"""Build the browser version of THE MALL, 1997.

Writes two builds of web/index.html into web/dist/:

  index.html + glue.wasm   the page loads the WebAssembly file next to it
                           (for hosting, e.g. as a published web page)
  mall1997-offline.html    one self-contained file with the WebAssembly
                           embedded, for opening straight from disk
  netlify/ + mall1997-netlify.zip
                           index.html, glue.wasm and a _headers file, ready
                           to drop onto app.netlify.com/drop

Both embed the game's Lua sources (source/**/*.lua), the Playdate mock and
rasterizer from tools/, and web/boot.lua, and inline wasmoon (Lua 5.4 in
WebAssembly, MIT; vendored in web/vendor/).

usage: python3 tools/build_web.py
"""
import base64
import json
import os
import shutil
import zipfile

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
WEB = os.path.join(ROOT, "web")
DIST = os.path.join(WEB, "dist")
TOOL_FILES = ["pdmock.lua", "pdraster.lua", "pdtext.lua", "pdfont.lua", "pd_api_functions.txt", "pd_api_constants.txt"]


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def sources():
    files = {}
    src = os.path.join(ROOT, "source")
    for dirpath, _, names in os.walk(src):
        for n in sorted(names):
            if n.endswith(".lua"):
                p = os.path.join(dirpath, n)
                files[os.path.relpath(p, ROOT).replace(os.sep, "/")] = read(p)
    for n in TOOL_FILES:
        files["tools/" + n] = read(os.path.join(ROOT, "tools", n))
    files["web/boot.lua"] = read(os.path.join(WEB, "boot.lua"))
    return dict(sorted(files.items()))


def build(template, wasmoon, files, wasm_uri):
    # keep "</script>" out of the embedded JSON
    blob = json.dumps(files, ensure_ascii=False).replace("</", "<\\/")
    out = template.replace("__SOURCES__", blob)
    out = out.replace("__WASMOON__", "/* wasmoon 1.16.0 (MIT) https://github.com/ceifa/wasmoon */\n" + wasmoon)
    return out.replace("__WASM_URI__", json.dumps(wasm_uri))


def main():
    os.makedirs(DIST, exist_ok=True)
    template = read(os.path.join(WEB, "index.html"))
    wasmoon = read(os.path.join(WEB, "vendor", "wasmoon.js"))
    wasm_path = os.path.join(WEB, "vendor", "glue.wasm")
    files = sources()
    with open(os.path.join(DIST, "index.html"), "w", encoding="utf-8") as f:
        f.write(build(template, wasmoon, files, "glue.wasm"))
    shutil.copyfile(wasm_path, os.path.join(DIST, "glue.wasm"))
    with open(wasm_path, "rb") as f:
        data_uri = "data:application/wasm;base64," + base64.b64encode(f.read()).decode("ascii")
    head = ('<!doctype html>\n<html lang="en"><head><meta charset="utf-8">'
            '<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">'
            '<style>body{margin:0}[hidden]{display:none!important}</style></head><body>\n')
    with open(os.path.join(DIST, "mall1997-offline.html"), "w", encoding="utf-8") as f:
        f.write(head + build(template, wasmoon, files, data_uri) + "\n</body></html>\n")
    # a Netlify-ready bundle: drag the zip (or the folder) onto app.netlify.com/drop
    site = os.path.join(DIST, "netlify")
    shutil.rmtree(site, ignore_errors=True)
    os.makedirs(site)
    shutil.copyfile(os.path.join(DIST, "index.html"), os.path.join(site, "index.html"))
    shutil.copyfile(wasm_path, os.path.join(site, "glue.wasm"))
    with open(os.path.join(site, "_headers"), "w", encoding="utf-8") as f:
        f.write("/glue.wasm\n  Content-Type: application/wasm\n  Cache-Control: public, max-age=3600\n"
                "/*\n  X-Content-Type-Options: nosniff\n")
    zpath = os.path.join(DIST, "mall1997-netlify.zip")
    if os.path.exists(zpath):
        os.remove(zpath)
    with zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED) as z:
        for n in ("index.html", "glue.wasm", "_headers"):
            z.write(os.path.join(site, n), n)
    for n in ("index.html", "glue.wasm", "mall1997-offline.html", "mall1997-netlify.zip"):
        print("%-24s %7d KB" % (n, os.path.getsize(os.path.join(DIST, n)) // 1024))
    print("%d Lua/text files embedded" % len(files))


if __name__ == "__main__":
    main()
