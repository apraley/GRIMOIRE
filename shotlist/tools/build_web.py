#!/usr/bin/env python3
"""Build the browser version of SHOT LIST.

Bundles web/index.html + web/pdweb.lua + every file in source/ + tests/json.lua
and the wasmoon Lua 5.4 VM (MIT, fetched from the npm registry) into OUT_DIR:

    OUT_DIR/index.html   the page (Lua sources and wasmoon's JS inlined)
    OUT_DIR/glue.wasm    the Lua VM, loaded by the page from the same folder

usage: build_web.py OUT_DIR [--wasmoon DIR]   (DIR = an unpacked wasmoon package)
"""
import io, json, os, sys, tarfile, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WASMOON = "1.16.0"


def wasmoon_files(pkg_dir):
    if pkg_dir:
        with open(os.path.join(pkg_dir, "dist/index.js"), "rb") as f: js = f.read()
        with open(os.path.join(pkg_dir, "dist/glue.wasm"), "rb") as f: wasm = f.read()
        return js, wasm
    url = f"https://registry.npmjs.org/wasmoon/-/wasmoon-{WASMOON}.tgz"
    data = urllib.request.urlopen(url, timeout=60).read()
    with tarfile.open(fileobj=io.BytesIO(data)) as t:
        return t.extractfile("package/dist/index.js").read(), t.extractfile("package/dist/glue.wasm").read()


def main(argv):
    out = argv[0]
    pkg = argv[argv.index("--wasmoon") + 1] if "--wasmoon" in argv else None
    sources = {}
    src_dir = os.path.join(ROOT, "source")
    for d, _, names in os.walk(src_dir):
        for n in sorted(names):
            if n.endswith(".lua"):
                p = os.path.join(d, n)
                sources[os.path.relpath(p, src_dir)] = open(p, encoding="utf-8").read()
    sources["json.lua"] = open(os.path.join(ROOT, "tests/json.lua"), encoding="utf-8").read()
    sources["pdweb.lua"] = open(os.path.join(ROOT, "web/pdweb.lua"), encoding="utf-8").read()
    js, wasm = wasmoon_files(pkg)
    page = open(os.path.join(ROOT, "web/index.html"), encoding="utf-8").read()
    blob = json.dumps(sources, ensure_ascii=False).replace("</", "<\\/")
    page = page.replace("@@SOURCES@@", blob, 1)
    page = page.replace("/*@@WASMOON@@*/", "/* wasmoon %s (MIT) */\n" % WASMOON + js.decode("utf-8").replace("</script", "<\\/script"), 1)
    os.makedirs(out, exist_ok=True)
    with open(os.path.join(out, "index.html"), "w", encoding="utf-8") as f: f.write(page)
    with open(os.path.join(out, "glue.wasm"), "wb") as f: f.write(wasm)
    print("wrote %s/index.html (%d KB) and glue.wasm (%d KB)" % (out, len(page) // 1024, len(wasm) // 1024))


if __name__ == "__main__":
    main(sys.argv[1:])
