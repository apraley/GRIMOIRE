#!/bin/sh
# Runs every automated check. Usage: sh tools/run_all.sh
cd "$(dirname "$0")/.." || exit 1
fail=0
python3 tools/check_api.py || fail=1
MOCK_DATA_DIR=/tmp/ci-all-wrapper lua5.4 tools/test_wrapper.lua | tail -1 || fail=1
for m in safecracker fishing camera microfiche numbers elevator projectionist lighthouse winch well clockmaker civilization billion; do
  out=$(MOCK_DATA_DIR=/tmp/ci-all-$m lua5.4 tools/test_machine.lua $m 2>&1 | tail -1)
  echo "$out"
  case "$out" in OK*) ;; *) fail=1 ;; esac
done
for t in tools/test_*.lua; do
  case "$t" in */test_machine.lua|*/test_wrapper.lua|*/test_boot.lua) continue ;; esac
  name=$(basename "$t" .lua)
  if MOCK_DATA_DIR=/tmp/ci-all-$name lua5.4 "$t" >/tmp/ci-all-$name.log 2>&1; then echo "OK $name"; else echo "FAIL $name (see /tmp/ci-all-$name.log)"; fail=1; fi
done
exit $fail
