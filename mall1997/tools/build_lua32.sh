#!/bin/sh
# Build a Lua 5.4 interpreter with 32-bit integers and floats (LUA_32BITS),
# matching the Playdate runtime. Stock desktop Lua uses 64-bit integers, which
# hides overflow bugs (e.g. a literal > 0x7FFFFFFF silently becoming a float).
# usage: tools/build_lua32.sh <path-to-lua-5.4-src-dir> [output]
#   then: ./lua32 tools/flows.lua   (or test_games.lua / smoke.lua / sim30.lua)
set -e
SRC="$1"; OUT="${2:-./lua32}"
[ -f "$SRC/luaconf.h" ] || { echo "usage: $0 <lua-5.4 src dir> [output]"; exit 1; }
TMP=$(mktemp -d)
cp "$SRC"/*.c "$SRC"/*.h "$TMP"/
sed -i.bak 's/^#define LUA_32BITS[[:space:]]*0/#define LUA_32BITS 1/' "$TMP/luaconf.h"
cc -O2 -std=gnu99 -DLUA_USE_POSIX -o "$OUT" $(ls "$TMP"/*.c | grep -v -E '/(luac|ltests|onelua)\.c$') -lm
rm -rf "$TMP"
"$OUT" -e 'assert(math.maxinteger == 2147483647, "not a 32-bit build"); print("built 32-bit Lua: " .. arg[0])'
