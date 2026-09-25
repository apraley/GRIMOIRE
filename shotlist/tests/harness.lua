-- Shared bootstrap for headless tests. Usage from the shotlist/ directory:
--   lua5.4 tests/test_core.lua
-- Sets up a fresh temp Data folder and loads the stubbed runtime.

local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)/[^/]+$") or "."
TESTS_DIR = here
SOURCE_DIR = here .. "/../source"

dofile(TESTS_DIR .. "/pdstub.lua")

local H = {}
H.failures = 0
H.passes = 0

function H.freshData(tag)
	local dir = os.getenv("SHOTLIST_TMP") or "/tmp"
	Sim.dataDir = dir .. "/shotlist-data-" .. (tag or "t") .. "-" .. tostring(os.time()) .. "-" .. math.random(1e6)
	os.execute('rm -rf "' .. Sim.dataDir .. '" && mkdir -p "' .. Sim.dataDir .. '"')
	return Sim.dataDir
end

function H.check(cond, msg)
	if cond then
		H.passes = H.passes + 1
	else
		H.failures = H.failures + 1
		print("FAIL: " .. msg)
		print(debug.traceback("", 2))
	end
end

function H.eq(a, b, msg)
	H.check(a == b, msg .. " (expected " .. tostring(b) .. ", got " .. tostring(a) .. ")")
end

function H.done(name)
	print(string.format("%s: %d passed, %d failed", name, H.passes, H.failures))
	if H.failures > 0 then os.exit(1) end
end

-- 2026-09-25 05:55 UTC in Playdate epoch
H.START_EPOCH = os.time({ year = 2026, month = 9, day = 25, hour = 5, min = 55, sec = 0, isdst = false }) - 946684800

function H.loadCore()
	import "core/util"
	import "core/vocab"
	import "core/schema"
	import "core/model"
	import "core/store"
	import "core/templates"
	import "core/report"
	import "core/interchange"
end

return H
