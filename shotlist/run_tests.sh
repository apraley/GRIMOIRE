#!/bin/sh
# Headless test suite (Lua 5.4). Optional: FRAMES=dir renders screenshots (needs python3 + Pillow).
set -e
cd "$(dirname "$0")"
export TZ=UTC
for f in source/*.lua source/*/*.lua; do luac5.4 -p "$f"; done
lua5.4 tests/test_core.lua
lua5.4 tests/test_ui_smoke.lua
lua5.4 tests/test_workflows.lua
lua5.4 tests/sim_commercial.lua ${FRAMES:+"$FRAMES/sim"}
if [ -n "$FRAMES" ]; then
	lua5.4 tests/tour.lua "$FRAMES/tour"
	python3 tools/render_frames.py "$FRAMES/png" "$FRAMES"/tour/*.json "$FRAMES"/sim/*.json
	echo "screenshots in $FRAMES/png"
fi
