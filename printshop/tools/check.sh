#!/bin/sh
# Full local verification: syntax, API usage, tests. Run from printshop/.
set -e
cd "$(dirname "$0")/.."
for f in $(find source tests -name "*.lua"); do
	luac5.4 -p "$f"
done
echo "syntax OK"
python3 tools/check_api.py
lua5.4 tests/run.lua
