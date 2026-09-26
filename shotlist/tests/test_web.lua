-- The browser runtime (web/pdweb.lua) boots the unchanged app, draws, persists
-- files through the page bridge, and restores them after a "reload".
local DIR = debug.getinfo(1, "S").source:sub(2):match("^(.*)/[^/]+$") or "."
local ROOT = DIR .. "/.."
local J = dofile(DIR .. "/json.lua")

local fails, checks = 0, 0
local function check(c, msg)
	checks = checks + 1
	if not c then fails = fails + 1; print("FAIL: " .. msg) end
end

local function readAll(p)
	local f = assert(io.open(p, "rb")); local s = f:read("a"); f:close(); return s
end

local function sources()
	local t = { ["json.lua"] = readAll(DIR .. "/json.lua") }
	local h = io.popen('cd "' .. ROOT .. '/source" && ls *.lua */*.lua')
	for name in h:lines() do t[name] = readAll(ROOT .. "/source/" .. name) end
	h:close()
	return t
end

local disk = {}         -- the page's localStorage
local clock = 843000000 * 1000 + 946684800 * 1000

-- Each "page load" gets a fresh Lua state, like a browser reload.
local function pageLoad()
	local env = setmetatable({}, { __index = _G })
	env._G = env
	env.WEB = {
		persist = function(p, c) disk[p] = c end,
		nowMs = function() return clock end,
		tzOffset = function() return 0 end,
	}
	env.WEB_SOURCES = sources()
	local chunk = assert(loadfile(ROOT .. "/web/pdweb.lua", "t", env))
	chunk()
	for p, c in pairs(disk) do env.WebPutFile(p, c) end
	env.WebBoot()
	return env
end

local BTN = { A = 32, B = 16, UP = 4, DOWN = 8, LEFT = 1, RIGHT = 2 }
local function frame(env, buttons, crank)
	clock = clock + 1000 / 30
	local out = J.decode(env.WebFrame(buttons or 0, crank or 0))
	check(out.err == nil, "frame error: " .. tostring(out.err))
	return out
end
local function tap(env, name)
	for _ = 1, 3 do frame(env, BTN[name]) end
	for _ = 1, 2 do frame(env, 0) end
end
local function text(cmds)
	local r = {}
	for _, c in ipairs(cmds or {}) do if c.op == "text" then r[#r + 1] = c.s end end
	return table.concat(r, " | ")
end

-- first launch: welcome screen, A loads the 60-shot demo
local env = pageLoad()
local first = frame(env)
check(first.d and #first.d > 0, "first frame draws")
local again = frame(env)
check(again.d == nil, "unchanged frame sends no display list")
tap(env, "A")
local live = frame(env)
for _ = 1, 30 do local o = frame(env); if o.d then live = o end end
check(env.App.top() == env.App.stack[1] and env.Model.project().title == "FIRST LIGHT :30", "demo loaded into LIVE")
check(text(live.d):find("A CAM", 1, true) ~= nil, "LIVE shows the setup line: " .. text(live.d):sub(1, 120))

-- log a take and rate it GREAT
local shot = env.App.cursorShot()
tap(env, "A")
tap(env, "UP")
check(#shot.takes == 1 and shot.takes[1].rating == "GREAT", "take logged and rated")
check(disk["journal.jsonl"] and #disk["journal.jsonl"] > 0, "journal persisted to page storage")

-- system menu: three items, GO options, menu image built on pause
local menu = J.decode(env.WebMenuOpen())
check(#menu.items == 3, "three system menu items")
check(menu.image and #menu.image.cmds > 0, "menu image built by gameWillPause")
env.WebMenuSelect(3, "SLATE")
env.WebMenuClose()
frame(env); frame(env)
check(env.App.top().__index == env.SlateScreen or getmetatable(env.App.top()) == env.SlateScreen, "GO SLATE opens slate")
tap(env, "B")

-- crank moves the cursor
local before = env.App.cursorShot()
for _ = 1, 4 do frame(env, 0, 10) end
for _ = 1, 30 do frame(env) end
check(env.App.cursorShot() ~= before, "crank scrubs to another shot")

-- keyboard bridge: continuity note from details
env.App.setCursor(shot)
tap(env, "B")
env.App.top().sel = 2
tap(env, "A")
for _ = 1, 3 do frame(env) end
local tries = 0
while not env.playdate.keyboard.isVisible() and tries < 3 do tap(env, "A"); tries = tries + 1 end
local o = frame(env)
check(o.kb and o.kb ~= false, "keyboard visible reported to page")
env.WebKeyboardDone("Mug handle faces camera", true)
for _ = 1, 3 do frame(env) end
local scene = env.Model.ctx(shot.id).scene
local found = false
for _, n in ipairs(scene.notes) do if n.text:upper():find("MUG HANDLE", 1, true) then found = true end end
check(found, "continuity note saved from page keyboard")

-- reload after a crash (no clean save): the journal brings everything back
local takes = #shot.takes
local env2 = pageLoad()
for _ = 1, 5 do frame(env2) end
local p = env2.Model.project()
check(p and p.title == "FIRST LIGHT :30", "project restored after reload")
local s2 = env2.Model.byId[shot.id]
check(s2 and #s2.takes == takes and s2.takes[1].rating == "GREAT", "take restored after reload")

-- clean shutdown writes a snapshot
env2.WebTerminate()
check(disk["shotlist.json"] ~= nil, "snapshot written on terminate")

-- time helpers round-trip
local t = env2.playdate.timeFromEpoch(843000000)
local e = env2.playdate.epochFromTime(t)
check(e == 843000000, "epochFromTime(timeFromEpoch(x)) == x")

print(string.format("test_web: %d checks, %d failed", checks, fails))
if fails > 0 then os.exit(1) end
