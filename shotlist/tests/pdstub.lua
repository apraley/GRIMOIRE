-- Headless stand-in for the Playdate Lua runtime, just wide enough for SHOT LIST.
-- Graphics calls are recorded as display lists (rendered to PNG by
-- tools/render_frames.py); files go to a temp Data folder; buttons, crank,
-- keyboard and system menu are driven by the test script through `Sim`.
--
-- API shapes follow the Playdate SDK docs (Inside Playdate). The stub is
-- deliberately strict where the real device is (3 custom menu items max).

local J = dofile(TESTS_DIR .. "/json.lua")
json = {
	encode = J.encode,
	encodePretty = J.encodePretty,
	decode = J.decode,
}

Sim = {
	dataDir = nil,
	frame = 0,
	ms = 0,
	epoch = 0,          -- playdate epoch seconds (since 2000-01-01)
	buttons = 0,
	prevButtons = 0,
	pressedLatch = 0,
	releasedLatch = 0,
	crankDelta = 0,
	crankAccel = nil,
	crankDocked = false,
	menuItems = {},
	fontHeight = 16,
	log = {},
}

local EPOCH_2000 = 946684800

playdate = {}
playdate.kButtonLeft, playdate.kButtonRight, playdate.kButtonUp = 1, 2, 4
playdate.kButtonDown, playdate.kButtonB, playdate.kButtonA = 8, 16, 32
playdate.isSimulator = true

---------------------------------------------------------------------------
-- time
---------------------------------------------------------------------------
function playdate.getSecondsSinceEpoch() return math.floor(Sim.epoch), 0 end
function playdate.getCurrentTimeMilliseconds() return math.floor(Sim.ms) end
local function tbl(epoch)
	local t = os.date("!*t", math.floor(epoch) + EPOCH_2000)
	local wd = t.wday - 1; if wd == 0 then wd = 7 end
	return { year = t.year, month = t.month, day = t.day, weekday = wd, hour = t.hour, minute = t.min,
		second = t.sec, millisecond = 0 }
end
function playdate.getTime() return tbl(Sim.epoch) end
function playdate.timeFromEpoch(s, ms) return tbl(s) end
function playdate.epochFromTime(t)
	local s = os.time({ year = t.year, month = t.month, day = t.day, hour = t.hour or 0, min = t.minute or 0,
		sec = t.second or 0, isdst = false })
	-- os.time interprets as local; harness runs with TZ=UTC
	return s - EPOCH_2000, 0
end

---------------------------------------------------------------------------
-- files (sandboxed to Sim.dataDir)
---------------------------------------------------------------------------
local function P(path) return Sim.dataDir .. "/" .. path end
local function fexists(path)
	local f = io.open(P(path), "rb")
	if f then f:close(); return true end
	return os.execute('test -d "' .. P(path) .. '"') == true
end

playdate.file = { kFileRead = 3, kFileWrite = 4, kFileAppend = 8 }
function playdate.file.exists(path) return fexists(path) end
function playdate.file.isdir(path) return os.execute('test -d "' .. P(path) .. '"') == true end
function playdate.file.mkdir(path) os.execute('mkdir -p "' .. P(path) .. '"'); return true end
function playdate.file.delete(path) return os.remove(P(path)) ~= nil end
function playdate.file.rename(a, b)
	if not fexists(a) then return false end
	return os.rename(P(a), P(b)) == true
end
function playdate.file.getSize(path)
	local f = io.open(P(path), "rb"); if not f then return nil end
	local n = f:seek("end"); f:close(); return n
end
function playdate.file.listFiles(path)
	local r = {}
	local h = io.popen('ls -1p "' .. P(path or ".") .. '" 2>/dev/null')
	for line in h:lines() do r[#r + 1] = line end
	h:close()
	return r
end
function playdate.file.open(path, mode)
	mode = mode or playdate.file.kFileRead
	local m = mode == playdate.file.kFileRead and "rb" or (mode == playdate.file.kFileAppend and "ab" or "wb")
	local fh = io.open(P(path), m)
	if fh == nil then return nil, "cannot open " .. path end
	Sim.fileWrites = (Sim.fileWrites or 0) + (m ~= "rb" and 1 or 0)
	local f = {}
	function f:readline()
		local l = fh:read("l")
		if l then l = l:gsub("\r$", "") end
		return l
	end
	function f:write(s)
		if Sim.failWritesAfter then
			Sim.failWritesAfter = Sim.failWritesAfter - 1
			if Sim.failWritesAfter < 0 then
				-- simulate power loss mid-write: write half the bytes, then die
				fh:write(s:sub(1, #s // 2)); fh:close()
				error("SIMULATED CRASH")
			end
		end
		fh:write(s); return #s
	end
	function f:read(n) return fh:read(n) end
	function f:flush() fh:flush() end
	function f:close() fh:close() end
	return f
end

function json.encodeToFile(path, pretty, t)
	local f = playdate.file.open(path, playdate.file.kFileWrite)
	f:write(pretty and J.encodePretty(t) or J.encode(t))
	f:close()
end
function json.decodeFile(path)
	local fh = io.open(P(path), "rb")
	if not fh then return nil end
	local s = fh:read("a"); fh:close()
	return J.decode(s)
end

playdate.datastore = {}
function playdate.datastore.write(t, name, pretty)
	local f = playdate.file.open((name or "data") .. ".json", playdate.file.kFileWrite)
	f:write(pretty and J.encodePretty(t) or J.encode(t))
	f:close()
	Sim.snapshotWrites = (Sim.snapshotWrites or 0) + 1
end
function playdate.datastore.read(name)
	return json.decodeFile((name or "data") .. ".json")
end
function playdate.datastore.delete(name) return playdate.file.delete((name or "data") .. ".json") end

---------------------------------------------------------------------------
-- input
---------------------------------------------------------------------------
function playdate.getButtonState()
	return Sim.buttons, Sim.pressedLatch, Sim.releasedLatch
end
function playdate.buttonIsPressed(b) return (Sim.buttons & b) ~= 0 end
function playdate.buttonJustPressed(b) return (Sim.pressedLatch & b) ~= 0 end
function playdate.buttonJustReleased(b) return (Sim.releasedLatch & b) ~= 0 end
function playdate.getCrankChange()
	local c, a = Sim.crankDelta, Sim.crankAccel or Sim.crankDelta
	Sim.crankDelta, Sim.crankAccel = 0, nil
	return c, a
end
function playdate.isCrankDocked() return Sim.crankDocked end
function playdate.getCrankPosition() return 0 end
function playdate.setAutoLockDisabled() end
function playdate.setCrankSoundsDisabled() end
function playdate.getBatteryPercentage() return 83 end
function playdate.getReduceFlashing() return false end

playdate.keyboard = { text = "", _visible = false }
function playdate.keyboard.show(text)
	playdate.keyboard.text = text or ""
	playdate.keyboard._visible = true
end
function playdate.keyboard.hide() playdate.keyboard._visible = false end
function playdate.keyboard.isVisible() return playdate.keyboard._visible end
function playdate.keyboard.width() return 180 end
function playdate.keyboard.setCapitalizationBehavior() end
playdate.keyboard.kCapitalizationNormal, playdate.keyboard.kCapitalizationWords = 0, 1
playdate.keyboard.kCapitalizationSentences = 2

local Menu = {}
Menu.__index = Menu
function Menu:addMenuItem(title, cb)
	if #Sim.menuItems >= 3 then return nil, "too many menu items" end
	local item = { title = title, cb = cb, kind = "item" }
	Sim.menuItems[#Sim.menuItems + 1] = item
	return setmetatable(item, { __index = { setValue = function(self, v) self.value = v end,
		getValue = function(self) return self.value end, setTitle = function(self, t) self.title = t end } })
end
function Menu:addOptionsMenuItem(title, options, initial, cb)
	if #Sim.menuItems >= 3 then return nil, "too many menu items" end
	local item = { title = title, options = options, value = initial or options[1], cb = cb, kind = "options" }
	Sim.menuItems[#Sim.menuItems + 1] = item
	return setmetatable(item, { __index = { setValue = function(self, v) self.value = v end,
		getValue = function(self) return self.value end, setTitle = function(self, t) self.title = t end } })
end
function Menu:addCheckmarkMenuItem(title, initial, cb)
	if #Sim.menuItems >= 3 then return nil, "too many menu items" end
	local item = { title = title, value = initial, cb = cb, kind = "check" }
	Sim.menuItems[#Sim.menuItems + 1] = item
	return item
end
function Menu:removeAllMenuItems() Sim.menuItems = {} end
local theMenu = setmetatable({}, Menu)
function playdate.getSystemMenu() return theMenu end
function playdate.setMenuImage() end

playdate.display = {}
function playdate.display.setRefreshRate(r) Sim.refreshRate = r end
function playdate.display.getRefreshRate() return Sim.refreshRate or 30 end
function playdate.display.setInverted(f) Sim.inverted = f end
function playdate.display.getWidth() return 400 end
function playdate.display.getHeight() return 240 end

---------------------------------------------------------------------------
-- graphics: display-list recorder
---------------------------------------------------------------------------
local gfx = {}
playdate.graphics = gfx
gfx.kColorBlack, gfx.kColorWhite, gfx.kColorClear, gfx.kColorXOR = 0, 1, 2, 3
gfx.kDrawModeCopy, gfx.kDrawModeWhiteTransparent, gfx.kDrawModeBlackTransparent = 0, 1, 2
gfx.kDrawModeFillWhite, gfx.kDrawModeFillBlack, gfx.kDrawModeXOR, gfx.kDrawModeNXOR = 3, 4, 5, 6
gfx.kDrawModeInverted = 7
gfx.image = {}
gfx.font = { kVariantNormal = 0, kVariantBold = 1, kVariantItalic = 2 }
gfx.kImageUnflipped = 0

local screen = { cmds = {}, w = 400, h = 240 }
local target = screen
local state = { color = 0, alpha = nil, mode = 0, lw = 1 }
local stack = {}

Sim.screen = screen

local function rec(c)
	c.color = state.color
	c.alpha = state.alpha
	c.mode = state.mode
	c.lw = state.lw
	target.cmds[#target.cmds + 1] = c
	Sim.drawCalls = (Sim.drawCalls or 0) + 1
end

function gfx.clear(color)
	target.cmds = {}
	rec({ op = "clear", c = color or gfx.kColorWhite })
end
function gfx.setColor(c) state.color = c; state.alpha = nil end
function gfx.setDitherPattern(a) state.alpha = a end
function gfx.setLineWidth(w) state.lw = w end
function gfx.setImageDrawMode(m) state.mode = m end
function gfx.setBackgroundColor() end
function gfx.fillRect(x, y, w, h) rec({ op = "fillRect", x = x, y = y, w = w, h = h }) end
function gfx.drawRect(x, y, w, h) rec({ op = "drawRect", x = x, y = y, w = w, h = h }) end
function gfx.fillRoundRect(x, y, w, h, r) rec({ op = "fillRect", x = x, y = y, w = w, h = h, r = r }) end
function gfx.drawRoundRect(x, y, w, h, r) rec({ op = "drawRect", x = x, y = y, w = w, h = h, r = r }) end
function gfx.drawLine(x1, y1, x2, y2) rec({ op = "line", x1 = x1, y1 = y1, x2 = x2, y2 = y2 }) end
function gfx.fillCircleAtPoint(x, y, r) rec({ op = "fillCircle", x = x, y = y, r = r }) end
function gfx.drawCircleAtPoint(x, y, r) rec({ op = "drawCircle", x = x, y = y, r = r }) end
function gfx.fillTriangle(x1, y1, x2, y2, x3, y3) rec({ op = "tri", p = { x1, y1, x2, y2, x3, y3 } }) end
function gfx.drawPixel(x, y) rec({ op = "fillRect", x = x, y = y, w = 1, h = 1 }) end
function gfx.setClipRect(x, y, w, h) target.cmds[#target.cmds + 1] = { op = "clip", x = x, y = y, w = w, h = h } end
function gfx.clearClipRect() target.cmds[#target.cmds + 1] = { op = "clip" } end
function gfx.setFont() end

-- Approximate Asheville Sans 14 metrics (uppercase-heavy UI). The device uses
-- the real font's metrics at runtime; these only need to be close.
local W = {}
for c = 32, 126 do W[string.char(c)] = 8 end
for c in ("ABCDEFGHJKLNOPQRSTUVXYZ"):gmatch(".") do W[c] = 9 end
W.M, W.W = 11, 12
W.I, W[" "], W["."], W[","], W[":"], W[";"], W["'"], W["!"], W["|"] = 4, 5, 4, 4, 4, 4, 3, 4, 3
for c in ("0123456789"):gmatch(".") do W[c] = 8 end
W["1"] = 6
for c in ("abcdefghijklmnopqrstuvwxyz"):gmatch(".") do W[c] = 7 end
W.i, W.l, W.j, W.m, W.w = 3, 3, 4, 11, 10
W["-"], W["/"], W["("], W[")"], W["#"], W["+"], W["%"] = 6, 6, 5, 5, 10, 8, 11

local function mkfont(variant)
	local f = { variant = variant }
	function f:getHeight() return Sim.fontHeight end
	function f:getTextWidth(s)
		local w = 0
		for ch in tostring(s):gmatch(".") do w = w + (W[ch] or 8) + (variant == "bold" and 1 or 0) end
		return w
	end
	function f:getGlyph(ch) return ch:byte() >= 32 and ch:byte() < 127 and {} or nil end
	function f:drawText(s, x, y) rec({ op = "text", s = tostring(s), x = x, y = y, w = f:getTextWidth(s), font = variant }) end
	function f:drawTextAligned(s, x, y, a)
		local w = f:getTextWidth(s)
		if a == 1 then x = x - w elseif a == 2 then x = x - w // 2 end
		f:drawText(s, x, y)
	end
	return f
end
local fonts = { normal = mkfont("normal"), bold = mkfont("bold"), italic = mkfont("italic") }
function gfx.getSystemFont(v)
	if v == 1 or v == "bold" then return fonts.bold end
	if v == 2 or v == "italic" then return fonts.italic end
	return fonts.normal
end
function gfx.getFont() return fonts.normal end

local Image = {}
Image.__index = Image
function gfx.image.new(w, h, bg)
	local img = setmetatable({ w = w, h = h, cmds = {}, bg = bg or gfx.kColorClear }, Image)
	return img
end
function Image:getSize() return self.w, self.h end
function Image:draw(x, y) rec({ op = "image", x = x, y = y, s = 1, img = { w = self.w, h = self.h, bg = self.bg, cmds = self.cmds } }) end
function Image:drawScaled(x, y, s, ys)
	rec({ op = "image", x = x, y = y, s = s, ys = ys or s, img = { w = self.w, h = self.h, bg = self.bg, cmds = self.cmds } })
end
function Image:clear(c) self.cmds = {}; self.bg = c end
function gfx.pushContext(img)
	stack[#stack + 1] = { target = target, state = { color = state.color, alpha = state.alpha, mode = state.mode, lw = state.lw } }
	target = img or screen
end
function gfx.popContext()
	local s = table.remove(stack)
	target = s.target
	state = s.state
end
function gfx.lockFocus(img) target = img end
function gfx.unlockFocus() target = screen end

function playdate.drawFPS() end
function playdate.stop() end
function playdate.start() end

---------------------------------------------------------------------------
-- import (compile-time in pdc; a dofile-once here)
---------------------------------------------------------------------------
local imported = {}
function import(name)
	if name:match("^CoreLibs/") then return end
	if not name:match("%.lua$") then name = name .. ".lua" end
	if imported[name] then return end
	imported[name] = true
	dofile(SOURCE_DIR .. "/" .. name)
end

---------------------------------------------------------------------------
-- Sim driver
---------------------------------------------------------------------------
local BTN = { A = 32, B = 16, UP = 4, DOWN = 8, LEFT = 1, RIGHT = 2 }
Sim.BTN = BTN

function Sim.step(n)
	for _ = 1, (n or 1) do
		Sim.pressedLatch = Sim.buttons & ~Sim.prevButtons | (Sim.pressedLatch & 0)
		Sim.releasedLatch = Sim.prevButtons & ~Sim.buttons
		playdate.update()
		Sim.prevButtons = Sim.buttons
		Sim.frame = Sim.frame + 1
		Sim.ms = Sim.ms + 1000 / 30
		Sim.epoch = Sim.epoch + 1 / 30
	end
end

Sim.presses = 0
Sim.pressLog = {}
local function count(kind)
	Sim.presses = Sim.presses + 1
	Sim.pressLog[kind] = (Sim.pressLog[kind] or 0) + 1
end

-- a tap: down for 3 frames, then up, then 2 idle frames
function Sim.tap(name, frames)
	count(name)
	Sim.buttons = Sim.buttons | BTN[name]
	Sim.step(frames or 3)
	Sim.buttons = Sim.buttons & ~BTN[name]
	Sim.step(2)
end

function Sim.hold(name, ms)
	count("hold " .. name)
	Sim.buttons = Sim.buttons | BTN[name]
	Sim.step(math.ceil((ms or 800) / (1000 / 30)))
	Sim.buttons = Sim.buttons & ~BTN[name]
	Sim.step(2)
end

-- crank by `deg` spread over `frames` frames (accel optional multiplier)
function Sim.crank(deg, frames, accelMul)
	count("crank")
	frames = frames or 6
	for _ = 1, frames do
		Sim.crankDelta = deg / frames
		Sim.crankAccel = (deg / frames) * (accelMul or 1)
		Sim.step(1)
	end
	Sim.step(2)
end

function Sim.wait(seconds)
	Sim.step(math.floor(seconds * 30))
end

-- advance wall clock without running frames (e.g. time between takes)
function Sim.advance(seconds)
	Sim.epoch = Sim.epoch + seconds
	Sim.ms = Sim.ms + seconds * 1000
end

function Sim.type(text)
	assert(playdate.keyboard._visible, "keyboard not visible")
	playdate.keyboard.text = text
	if playdate.keyboard.textChangedCallback then playdate.keyboard.textChangedCallback() end
	Sim.step(1)
	if playdate.keyboard.keyboardWillHideCallback then playdate.keyboard.keyboardWillHideCallback(true) end
	playdate.keyboard._visible = false
	if playdate.keyboard.keyboardDidHideCallback then playdate.keyboard.keyboardDidHideCallback() end
	Sim.step(2)
end

function Sim.menu(title, value)
	count("menu")
	count("menu-select")
	for _, it in ipairs(Sim.menuItems) do
		if it.title == title then
			if it.kind == "options" then
				it.value = value
				it.cb(value)
			elseif it.kind == "check" then
				it.value = not it.value
				it.cb(it.value)
			else
				it.cb()
			end
			Sim.step(2)
			return true
		end
	end
	error("no menu item " .. title)
end

-- All text currently on screen (flattened, including scaled images).
function Sim.screenText()
	local out = {}
	local function walk(cmds)
		for _, c in ipairs(cmds) do
			if c.op == "text" then out[#out + 1] = c.s end
			if c.op == "image" then walk(c.img.cmds) end
		end
	end
	walk(screen.cmds)
	return table.concat(out, " | ")
end

function Sim.screenHas(s)
	return Sim.screenText():find(s, 1, true) ~= nil
end

function Sim.dumpFrame(path)
	local f = io.open(path, "wb")
	f:write(J.encode({ w = 400, h = 240, cmds = screen.cmds }))
	f:close()
end

return Sim
