-- Browser stand-in for the Playdate Lua runtime (runs under wasmoon, Lua 5.4).
-- The app source runs unchanged on top of it. Graphics calls are recorded as a
-- display list per frame and handed to JavaScript as JSON, which rasterises
-- them at 1-bit. Files live in a Lua table and are mirrored to localStorage
-- through WEB.persist, so data survives a page reload like the Data folder
-- survives a relaunch.
--
-- Globals provided by the page before this file runs:
--   WEB.persist(path, content)   content nil = delete
--   WEB.nowMs()                  wall clock, ms since the Unix epoch
--   WEB.tzOffset()               local offset from UTC in seconds
--   WEB_SOURCES[name]            Lua source text of each app file and json.lua

local J = assert(load(WEB_SOURCES["json.lua"], "@json.lua", "t", _ENV))()
json = { encode = J.encode, encodePretty = J.encodePretty, decode = J.decode }

Web = { buttons = 0, prevButtons = 0, crankDelta = 0, menuItems = {}, fontHeight = 16, draws = 0, sentDraws = -1 }

local EPOCH_2000 = 946684800

playdate = {}
playdate.kButtonLeft, playdate.kButtonRight, playdate.kButtonUp = 1, 2, 4
playdate.kButtonDown, playdate.kButtonB, playdate.kButtonA = 8, 16, 32
playdate.isSimulator = true

---------------------------------------------------------------------------
-- time: epoch seconds since 2000-01-01 UTC; time tables are local time
---------------------------------------------------------------------------
local function nowSec() return WEB.nowMs() / 1000 end

-- days since 1970-01-01 <-> civil date (Howard Hinnant's algorithms)
local function daysFromCivil(y, m, d)
	y = m <= 2 and y - 1 or y
	local era = (y >= 0 and y or y - 399) // 400
	local yoe = y - era * 400
	local doy = (153 * (m + (m > 2 and -3 or 9)) + 2) // 5 + d - 1
	local doe = yoe * 365 + yoe // 4 - yoe // 100 + doy
	return era * 146097 + doe - 719468
end
local function civilFromDays(z)
	z = z + 719468
	local era = (z >= 0 and z or z - 146096) // 146097
	local doe = z - era * 146097
	local yoe = (doe - doe // 1460 + doe // 36524 - doe // 146096) // 365
	local y = yoe + era * 400
	local doy = doe - (365 * yoe + yoe // 4 - yoe // 100)
	local mp = (5 * doy + 2) // 153
	local d = doy - (153 * mp + 2) // 5 + 1
	local m = mp + (mp < 10 and 3 or -9)
	return (m <= 2 and y + 1 or y), m, d
end

local function localTable(epoch2000)
	local s = math.floor(epoch2000) + EPOCH_2000 + WEB.tzOffset()
	local days = s // 86400
	local rem = s - days * 86400
	local y, m, d = civilFromDays(days)
	local wd = (days + 4) % 7 -- 1970-01-01 was a Thursday; 0 = Sunday
	if wd == 0 then wd = 7 end -- Playdate: 1 = Monday ... 7 = Sunday
	return { year = y, month = m, day = d, weekday = wd, hour = rem // 3600, minute = rem % 3600 // 60,
		second = rem % 60, millisecond = 0 }
end

function playdate.getSecondsSinceEpoch()
	local s = nowSec() - EPOCH_2000
	return math.floor(s), math.floor((s % 1) * 1000)
end
function playdate.getCurrentTimeMilliseconds() return math.floor(WEB.nowMs() - Web.bootMs) end
function playdate.getTime() return localTable(nowSec() - EPOCH_2000) end
function playdate.timeFromEpoch(s, ms) return localTable(s) end
function playdate.epochFromTime(t)
	local days = daysFromCivil(t.year, t.month, t.day)
	local s = days * 86400 + (t.hour or 0) * 3600 + (t.minute or 0) * 60 + (t.second or 0)
	return s - WEB.tzOffset() - EPOCH_2000, 0
end

---------------------------------------------------------------------------
-- files: FILES[path] = contents, DIRS[path] = true; mirrored to the page
---------------------------------------------------------------------------
FILES, DIRS = {}, {}

local function norm(p)
	p = tostring(p or ""):gsub("^/+", ""):gsub("/+$", "")
	return p
end
local function parentDirs(p)
	local acc = nil
	for part in p:gmatch("[^/]+") do
		if acc then DIRS[acc] = true; acc = acc .. "/" .. part else acc = part end
	end
end
local function store(p, s)
	FILES[p] = s
	parentDirs(p)
	WEB.persist(p, s)
end

function WebPutFile(path, content)
	path = norm(path)
	FILES[path] = content
	parentDirs(path)
end

playdate.file = { kFileRead = 3, kFileWrite = 4, kFileAppend = 8 }
function playdate.file.exists(path)
	path = norm(path)
	return FILES[path] ~= nil or DIRS[path] == true
end
function playdate.file.isdir(path) return DIRS[norm(path)] == true end
function playdate.file.mkdir(path)
	path = norm(path)
	parentDirs(path .. "/x")
	return true
end
function playdate.file.delete(path, recursive)
	path = norm(path)
	if FILES[path] then FILES[path] = nil; WEB.persist(path, nil); return true end
	if DIRS[path] then
		local pre = path .. "/"
		for k in pairs(FILES) do
			if k:sub(1, #pre) == pre then
				if not recursive then return false end
				FILES[k] = nil; WEB.persist(k, nil)
			end
		end
		for k in pairs(DIRS) do if k == path or k:sub(1, #pre) == pre then DIRS[k] = nil end end
		return true
	end
	return false
end
function playdate.file.rename(a, b)
	a, b = norm(a), norm(b)
	if FILES[a] then
		local s = FILES[a]
		FILES[a] = nil; WEB.persist(a, nil)
		store(b, s)
		return true
	end
	if DIRS[a] then
		local pre = a .. "/"
		local moves = {}
		for k, v in pairs(FILES) do if k:sub(1, #pre) == pre then moves[k] = v end end
		for k, v in pairs(moves) do
			FILES[k] = nil; WEB.persist(k, nil)
			store(b .. "/" .. k:sub(#pre + 1), v)
		end
		DIRS[a] = nil
		DIRS[b] = true
		return true
	end
	return false
end
function playdate.file.getSize(path)
	local s = FILES[norm(path)]
	return s and #s or nil
end
function playdate.file.listFiles(path)
	path = norm(path)
	local pre = path == "" and "" or path .. "/"
	local seen, r = {}, {}
	local function add(name)
		if not seen[name] then seen[name] = true; r[#r + 1] = name end
	end
	for k in pairs(FILES) do
		if k:sub(1, #pre) == pre then
			local rest = k:sub(#pre + 1)
			local first, more = rest:match("^([^/]+)(/?)")
			if first then add(more == "/" and first .. "/" or first) end
		end
	end
	for k in pairs(DIRS) do
		if k:sub(1, #pre) == pre then
			local first = k:sub(#pre + 1):match("^([^/]+)")
			if first then add(first .. "/") end
		end
	end
	table.sort(r)
	return r
end
function playdate.file.open(path, mode)
	path = norm(path)
	mode = mode or playdate.file.kFileRead
	local f = {}
	if mode == playdate.file.kFileRead then
		local s = FILES[path]
		if s == nil then return nil, "cannot open " .. path end
		local pos = 1
		function f:readline()
			if pos > #s then return nil end
			local e = s:find("\n", pos, true)
			local l
			if e then l = s:sub(pos, e - 1); pos = e + 1 else l = s:sub(pos); pos = #s + 1 end
			return (l:gsub("\r$", ""))
		end
		function f:read(n)
			if pos > #s then return nil end
			n = n or (#s - pos + 1)
			local out = s:sub(pos, pos + n - 1)
			pos = pos + #out
			return out
		end
		function f:write() return nil, "read only" end
	else
		local buf = {}
		if mode == playdate.file.kFileAppend and FILES[path] then buf[1] = FILES[path] end
		-- create immediately (an empty file exists after open, as on device)
		if FILES[path] == nil or mode ~= playdate.file.kFileAppend then store(path, table.concat(buf)) end
		function f:write(s)
			s = tostring(s)
			buf[#buf + 1] = s
			return #s
		end
		function f:flush() store(path, table.concat(buf)) end
		function f:readline() return nil end
		function f:read() return nil end
	end
	function f:close() if self.flush then self:flush() end end
	if mode == playdate.file.kFileRead then f.flush = nil end
	return f
end

function json.encodeToFile(path, pretty, t)
	store(norm(path), pretty and J.encodePretty(t) or J.encode(t))
end
function json.decodeFile(path)
	local s = FILES[norm(path)]
	if s == nil then return nil end
	local ok, v = pcall(J.decode, s)
	if ok then return v end
	return nil
end

playdate.datastore = {}
function playdate.datastore.write(t, name, pretty)
	store((name or "data") .. ".json", pretty and J.encodePretty(t) or J.encode(t))
end
function playdate.datastore.read(name) return json.decodeFile((name or "data") .. ".json") end
function playdate.datastore.delete(name) return playdate.file.delete((name or "data") .. ".json") end

---------------------------------------------------------------------------
-- input
---------------------------------------------------------------------------
function playdate.getButtonState()
	return Web.buttons, Web.buttons & ~Web.prevButtons, Web.prevButtons & ~Web.buttons
end
function playdate.buttonIsPressed(b) return (Web.buttons & b) ~= 0 end
function playdate.buttonJustPressed(b) return (Web.buttons & ~Web.prevButtons & b) ~= 0 end
function playdate.buttonJustReleased(b) return (Web.prevButtons & ~Web.buttons & b) ~= 0 end
function playdate.getCrankChange()
	local c = Web.crankDelta
	Web.crankDelta = 0
	return c, c
end
function playdate.isCrankDocked() return false end
function playdate.getCrankPosition() return 0 end
function playdate.setAutoLockDisabled() end
function playdate.setCrankSoundsDisabled() end
function playdate.getBatteryPercentage() return 100 end
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

-- System menu (Playdate OS allows three custom items; enforced here too)
local function itemMethods()
	return { __index = {
		setValue = function(self, v) self.value = v end,
		getValue = function(self) return self.value end,
		setTitle = function(self, t) self.title = t end,
		setCallback = function(self, cb) self.cb = cb end,
	} }
end
local Menu = {}
Menu.__index = Menu
local function addItem(item)
	if #Web.menuItems >= 3 then return nil, "too many menu items" end
	Web.menuItems[#Web.menuItems + 1] = item
	return setmetatable(item, itemMethods())
end
function Menu:addMenuItem(title, cb) return addItem({ title = title, cb = cb, kind = "item" }) end
function Menu:addOptionsMenuItem(title, options, initial, cb)
	return addItem({ title = title, options = options, value = initial or options[1], cb = cb, kind = "options" })
end
function Menu:addCheckmarkMenuItem(title, initial, cb)
	return addItem({ title = title, value = initial and true or false, cb = cb, kind = "check" })
end
function Menu:removeMenuItem(item)
	for i, it in ipairs(Web.menuItems) do if it == item then table.remove(Web.menuItems, i) return end end
end
function Menu:removeAllMenuItems() Web.menuItems = {} end
function Menu:getMenuItems() return Web.menuItems end
local theMenu = setmetatable({}, Menu)
function playdate.getSystemMenu() return theMenu end
function playdate.setMenuImage(img) Web.menuImage = img end

playdate.display = {}
function playdate.display.setRefreshRate(r) Web.refreshRate = r end
function playdate.display.getRefreshRate() return Web.refreshRate or 30 end
function playdate.display.setInverted(f) Web.inverted = f end
function playdate.display.getWidth() return 400 end
function playdate.display.getHeight() return 240 end

---------------------------------------------------------------------------
-- graphics: display-list recorder (same shapes as tests/pdstub.lua)
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
local state = { color = 0, mode = 0, lw = 1 }
local stack = {}

local function rec(c)
	c.color = state.color
	c.alpha = state.alpha
	c.mode = state.mode
	c.lw = state.lw
	target.cmds[#target.cmds + 1] = c
	if target == screen then Web.draws = Web.draws + 1 end
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
function gfx.setClipRect(x, y, w, h)
	target.cmds[#target.cmds + 1] = { op = "clip", x = x, y = y, w = w, h = h }
end
function gfx.clearClipRect() target.cmds[#target.cmds + 1] = { op = "clip" } end
function gfx.setFont() end

-- Asheville Sans 14-like metrics, identical to the headless harness so the
-- layout seen here is the layout the tests check.
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
	function f:getHeight() return Web.fontHeight end
	function f:getTextWidth(s)
		local w = 0
		for _, cp in utf8.codes(tostring(s), true) do
			local ch = cp < 128 and string.char(cp) or "?"
			w = w + (W[ch] or 8) + (variant == "bold" and 1 or 0)
		end
		return w
	end
	function f:getGlyph(ch) return {} end
	function f:drawText(s, x, y)
		s = tostring(s)
		rec({ op = "text", s = s, x = x, y = y, w = f:getTextWidth(s), font = variant })
	end
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
	return setmetatable({ w = w, h = h, cmds = {}, bg = bg or gfx.kColorClear }, Image)
end
function Image:getSize() return self.w, self.h end
function Image:draw(x, y)
	rec({ op = "image", x = x, y = y, s = 1, img = { w = self.w, h = self.h, bg = self.bg, cmds = self.cmds } })
end
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
-- import: pdc compiles these in; here they are loaded from WEB_SOURCES
---------------------------------------------------------------------------
local imported = {}
function import(name)
	if name:match("^CoreLibs/") then return end
	if not name:match("%.lua$") then name = name .. ".lua" end
	if imported[name] then return end
	imported[name] = true
	local src = WEB_SOURCES[name]
	if not src then error("import: missing " .. name) end
	assert(load(src, "@" .. name, "t", _ENV))()
end

---------------------------------------------------------------------------
-- page bridge
---------------------------------------------------------------------------
Web.bootMs = WEB.nowMs()

function WebBoot()
	import("main.lua")
end

-- One frame. Returns JSON: {d = display list or nil if unchanged, kb = {...}}
function WebFrame(buttons, crank)
	Web.buttons = buttons
	Web.crankDelta = Web.crankDelta + (crank or 0)
	local ok, err = pcall(playdate.update)
	Web.prevButtons = buttons
	local out = { kb = playdate.keyboard._visible and { t = playdate.keyboard.text or "" } or false }
	if not ok then out.err = tostring(err) end
	if Web.draws ~= Web.sentDraws then
		Web.sentDraws = Web.draws
		out.d = screen.cmds
	end
	return J.encode(out)
end

function WebKeyboardDone(text, ok)
	local kb = playdate.keyboard
	kb.text = text or ""
	if kb.textChangedCallback then kb.textChangedCallback() end
	if kb.keyboardWillHideCallback then kb.keyboardWillHideCallback(ok and true or false) end
	kb._visible = false
	if kb.keyboardDidHideCallback then kb.keyboardDidHideCallback() end
end

-- Opening the Playdate menu pauses the game: gameWillPause runs (it saves and
-- builds the menu image), then the OS shows the items.
function WebMenuOpen()
	if playdate.gameWillPause then pcall(playdate.gameWillPause) end
	local items = {}
	for i, it in ipairs(Web.menuItems) do
		items[i] = { title = it.title, kind = it.kind, options = it.options or false, value = it.value == nil and false or it.value }
	end
	local img = Web.menuImage
	return J.encode({ items = items, image = img and { w = img.w, h = img.h, bg = img.bg, cmds = img.cmds } or false })
end

function WebMenuSelect(i, value)
	local it = Web.menuItems[i]
	if not it then return end
	if it.kind == "options" then
		it.value = value
		if it.cb then it.cb(value) end
	elseif it.kind == "check" then
		it.value = not it.value
		if it.cb then it.cb(it.value) end
	elseif it.cb then
		it.cb()
	end
end

function WebMenuClose()
	if playdate.gameWillResume then pcall(playdate.gameWillResume) end
end

function WebTerminate()
	if playdate.gameWillTerminate then pcall(playdate.gameWillTerminate) end
end
