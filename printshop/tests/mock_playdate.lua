-- Headless, *strict* mock of the Playdate Lua runtime for tests.
--
-- Every function, method and constant is generated from tests/pd_api.lua,
-- which is extracted from the documented SDK API. Touching anything that is
-- not in the documented API raises an error, so tests catch invented APIs.
-- Drawing calls are no-ops that count invocations; input, time and the
-- datastore are scriptable from tests.

dofile(TEST_DIR .. "pd_api.lua")

MOCK = {
	calls = {},
	nowSec = 811036800,        -- 2025-09-14 00:00 UTC in Playdate epoch seconds
	ms = 0,
	buttons = {},              -- currently held
	justPressed = {},          -- pressed this frame
	justReleased = {},
	crankChange = 0,
	crankDocked = false,
	files = {},                -- datastore: name -> JSON text
	keyboardVisible = false,
	menuItems = {},
}

local function strict(name, t)
	return setmetatable(t or {}, {
		__index = function(_, k)
			error("Playdate API has no member '" .. name .. "." .. tostring(k) .. "'", 2)
		end,
	})
end

local function count(name)
	MOCK.calls[name] = (MOCK.calls[name] or 0) + 1
end

-- Object with only the documented methods of `className`.
local function object(className, fields)
	local o = fields or {}
	local methods = PD_API.methods[className] or {}
	local mt = { __index = {} }
	for _, m in ipairs(methods) do
		mt.__index[m] = function() count(className .. ":" .. m) end
	end
	setmetatable(mt.__index, {
		__index = function(_, k)
			error("Playdate API: " .. className .. " has no method/field '" .. tostring(k) .. "'", 2)
		end,
	})
	return setmetatable(o, mt), mt.__index
end

---------------------------------------------------------------------------
-- build namespaces

playdate = strict("playdate", {})
local function ensurePath(path)
	local parts = {}
	for p in string.gmatch(path, "[^%.]+") do parts[#parts + 1] = p end
	local t = _G
	local prefix = ""
	for i = 1, #parts - 1 do
		local p = parts[i]
		prefix = prefix == "" and p or (prefix .. "." .. p)
		local nxt = rawget(t, p)
		if nxt == nil then
			nxt = strict(prefix, {})
			rawset(t, p, nxt)
		end
		t = nxt
	end
	return t, parts[#parts]
end

for fname in pairs(PD_API.functions) do
	if string.sub(fname, 1, 9) == "playdate." then
		local t, last = ensurePath(fname)
		rawset(t, last, function() count(fname) end)
	end
end
local constValue = 0
for cname in pairs(PD_API.constants) do
	if string.sub(cname, 1, 9) == "playdate." then
		local t, last = ensurePath(cname)
		constValue = constValue + 1
		rawset(t, last, constValue)
	end
end
-- Buttons need real bit values.
rawset(playdate, "kButtonLeft", 1)
rawset(playdate, "kButtonRight", 2)
rawset(playdate, "kButtonUp", 4)
rawset(playdate, "kButtonDown", 8)
rawset(playdate, "kButtonB", 16)
rawset(playdate, "kButtonA", 32)

local gfx = playdate.graphics
MOCK.object = object

---------------------------------------------------------------------------
-- behaviour overrides

-- time
rawset(playdate, "getSecondsSinceEpoch", function() return MOCK.nowSec, 0 end)
rawset(playdate, "getCurrentTimeMilliseconds", function() return MOCK.ms end)
rawset(playdate, "timeFromEpoch", function(sec, ms)
	local t = os.date("!*t", sec + 946684800)
	return { year = t.year, month = t.month, day = t.day, weekday = (t.wday + 5) % 7 + 1,
		hour = t.hour, minute = t.min, second = t.sec, millisecond = ms or 0 }
end)
rawset(playdate, "getTime", function() return playdate.timeFromEpoch(MOCK.nowSec, 0) end)

-- input
rawset(playdate, "buttonIsPressed", function(b) return MOCK.buttons[b] == true end)
rawset(playdate, "buttonJustPressed", function(b) return MOCK.justPressed[b] == true end)
rawset(playdate, "buttonJustReleased", function(b) return MOCK.justReleased[b] == true end)
rawset(playdate, "getCrankChange", function() return MOCK.crankChange, MOCK.crankChange end)
rawset(playdate, "isCrankDocked", function() return MOCK.crankDocked end)
rawset(playdate, "getCrankPosition", function() return 0 end)

-- keyboard (CoreLibs/keyboard)
rawset(playdate.keyboard, "show", function(text)
	MOCK.keyboardVisible = true
	playdate.keyboard.text = text or ""
end)
rawset(playdate.keyboard, "hide", function() MOCK.keyboardVisible = false end)
rawset(playdate.keyboard, "isVisible", function() return MOCK.keyboardVisible end)
rawset(playdate.keyboard, "text", "")

-- system menu
rawset(playdate, "getSystemMenu", function()
	local menu = object("playdate.menu")
	local function item(title, value, cb)
		local it, methods = object("playdate.menu.item", { title = title, value = value, cb = cb })
		methods.getValue = function(self) return self.value end
		methods.setValue = function(self, v) self.value = v end
		methods.getTitle = function(self) return self.title end
		MOCK.menuItems[#MOCK.menuItems + 1] = it
		return it
	end
	local mt = getmetatable(menu).__index
	rawset(mt, "addMenuItem", function(_, title, cb) return item(title, nil, cb) end)
	rawset(mt, "addCheckmarkMenuItem", function(_, title, v, cb) return item(title, v, cb) end)
	rawset(mt, "addOptionsMenuItem", function(_, title, opts, v, cb) return item(title, v, cb) end)
	rawset(mt, "removeAllMenuItems", function() MOCK.menuItems = {} end)
	return menu
end)

-- graphics objects
local function newImage(w, h)
	local img, methods = object("playdate.graphics.image", { w = w or 1, h = h or 1 })
	methods.getSize = function(self) return self.w, self.h end
	methods.copy = function(self) return newImage(self.w, self.h) end
	methods.draw = function(self, x, y)
		assert(type(x) == "number" and type(y) == "number", "image:draw needs numbers")
		count("image:draw")
	end
	methods.drawScaled = function(self, x, y, s)
		assert(type(s) == "number", "drawScaled scale")
		count("image:drawScaled")
	end
	return img
end
rawset(gfx.image, "new", function(a, b, c)
	if type(a) == "string" then return nil end    -- no image assets in tests
	assert(type(a) == "number" and type(b) == "number", "image.new(w, h)")
	assert(a > 0 and b > 0, "image.new with zero size")
	return newImage(math.floor(a), math.floor(b))
end)
local contextDepth = 0
rawset(gfx, "pushContext", function() contextDepth = contextDepth + 1 end)
rawset(gfx, "popContext", function()
	contextDepth = contextDepth - 1
	assert(contextDepth >= 0, "popContext without pushContext")
end)
function MOCK.contextDepth() return contextDepth end

local function checkNums(name, n)
	rawset(gfx, name, function(...)
		local args = { ... }
		for i = 1, n do
			if type(args[i]) ~= "number" then
				error("gfx." .. name .. " arg " .. i .. " is " .. type(args[i]), 2)
			end
		end
		count("gfx." .. name)
	end)
end
checkNums("fillRect", 4)
checkNums("drawRect", 4)
checkNums("drawLine", 4)
checkNums("fillTriangle", 6)
checkNums("fillCircleAtPoint", 3)
checkNums("drawCircleAtPoint", 3)
checkNums("fillRoundRect", 5)
checkNums("drawRoundRect", 5)
checkNums("drawPixel", 2)
checkNums("fillEllipseInRect", 4)
checkNums("drawEllipseInRect", 4)
rawset(gfx, "setPattern", function(p)
	assert(type(p) == "table" and #p >= 8, "setPattern needs 8 rows")
	count("gfx.setPattern")
end)

-- sound
rawset(playdate.sound.synth, "new", function() return object("playdate.sound.synth") end)
rawset(playdate.sound, "getCurrentTime", function() return MOCK.ms / 1000 end)

-- network: present (SDK 2.7+), but no server answers in tests.
rawset(playdate.network.http, "new", function() return nil end)

---------------------------------------------------------------------------
-- JSON + datastore (roundtrip through text, like the device)

json = strict("json", {})

local function isArray(t)
	local n = 0
	for k in pairs(t) do
		if type(k) ~= "number" or k < 1 or math.floor(k) ~= k then return false end
		n = n + 1
	end
	for i = 1, n do if t[i] == nil then return false end end
	return true, n
end

local function encode(v, out)
	local tv = type(v)
	if tv == "nil" then out[#out + 1] = "null"
	elseif tv == "boolean" then out[#out + 1] = tostring(v)
	elseif tv == "number" then
		if v ~= v or v == math.huge or v == -math.huge then out[#out + 1] = "null"
		elseif math.type(v) == "integer" then out[#out + 1] = tostring(v)
		else out[#out + 1] = string.format("%.14g", v) end
	elseif tv == "string" then
		out[#out + 1] = '"' .. v:gsub('[%c"\\]', function(c)
			local map = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\t"] = "\\t", ["\r"] = "\\r" }
			return map[c] or string.format("\\u%04x", string.byte(c))
		end) .. '"'
	elseif tv == "table" then
		local arr, n = isArray(v)
		if arr then
			out[#out + 1] = "["
			for i = 1, n do
				if i > 1 then out[#out + 1] = "," end
				encode(v[i], out)
			end
			out[#out + 1] = "]"
		else
			out[#out + 1] = "{"
			local first = true
			local keys = {}
			for k in pairs(v) do keys[#keys + 1] = k end
			table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
			for _, k in ipairs(keys) do
				if type(v[k]) ~= "function" then
					if not first then out[#out + 1] = "," end
					first = false
					encode(tostring(k), out)
					out[#out + 1] = ":"
					encode(v[k], out)
				end
			end
			out[#out + 1] = "}"
		end
	else
		error("cannot encode " .. tv)
	end
end

rawset(json, "encode", function(v)
	local out = {}
	encode(v, out)
	return table.concat(out)
end)

rawset(json, "decode", function(s)
	local pos = 1
	local function ws() pos = s:find("[^ \t\r\n]", pos) or #s + 1 end
	local value
	local function str()
		local buf = {}
		pos = pos + 1
		while true do
			local c = s:sub(pos, pos)
			if c == "" then error("unterminated string") end
			if c == '"' then pos = pos + 1 break end
			if c == "\\" then
				local e = s:sub(pos + 1, pos + 1)
				if e == "u" then
					buf[#buf + 1] = string.char(tonumber(s:sub(pos + 2, pos + 5), 16) % 256)
					pos = pos + 6
				else
					buf[#buf + 1] = ({ n = "\n", t = "\t", r = "\r" })[e] or e
					pos = pos + 2
				end
			else
				buf[#buf + 1] = c
				pos = pos + 1
			end
		end
		return table.concat(buf)
	end
	function value()
		ws()
		local c = s:sub(pos, pos)
		if c == "{" then
			local t = {}
			pos = pos + 1
			ws()
			if s:sub(pos, pos) == "}" then pos = pos + 1 return t end
			while true do
				ws()
				local k = str()
				ws()
				assert(s:sub(pos, pos) == ":", "expected :")
				pos = pos + 1
				t[k] = value()
				ws()
				local d = s:sub(pos, pos)
				pos = pos + 1
				if d == "}" then return t end
				assert(d == ",", "expected , in object")
			end
		elseif c == "[" then
			local t = {}
			pos = pos + 1
			ws()
			if s:sub(pos, pos) == "]" then pos = pos + 1 return t end
			while true do
				t[#t + 1] = value()
				ws()
				local d = s:sub(pos, pos)
				pos = pos + 1
				if d == "]" then return t end
				assert(d == ",", "expected , in array")
			end
		elseif c == '"' then
			return str()
		elseif s:sub(pos, pos + 3) == "true" then pos = pos + 4 return true
		elseif s:sub(pos, pos + 4) == "false" then pos = pos + 5 return false
		elseif s:sub(pos, pos + 3) == "null" then pos = pos + 4 return nil
		else
			local num = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
			assert(num and #num > 0, "bad json at " .. pos)
			pos = pos + #num
			return math.tointeger(tonumber(num)) or tonumber(num)
		end
	end
	return value()
end)

rawset(playdate.datastore, "write", function(t, name)
	MOCK.files[name or "data"] = json.encode(t)
end)
rawset(playdate.datastore, "read", function(name)
	local s = MOCK.files[name or "data"]
	if s == nil then return nil end
	return json.decode(s)
end)
rawset(playdate.datastore, "delete", function(name)
	local had = MOCK.files[name or "data"] ~= nil
	MOCK.files[name or "data"] = nil
	return had
end)

-- table helpers from the Playdate runtime
table.indexOfElement = function(t, e)
	for i, v in ipairs(t) do if v == e then return i end end
	return nil
end

---------------------------------------------------------------------------
-- import: CoreLibs are provided by this mock; everything else is loaded
-- from the source directory exactly once, like pdc does.

local imported = {}
function import(path)
	if string.sub(path, 1, 9) == "CoreLibs/" then return end
	if imported[path] then return end
	imported[path] = true
	local file = SOURCE_DIR .. path
	if not string.find(path, "%.lua$") then file = file .. ".lua" end
	local chunk, err = loadfile(file)
	if not chunk then error(err) end
	chunk()
end

-- playdate.timer (CoreLibs/timer)
rawset(playdate.timer, "updateTimers", function() end)

---------------------------------------------------------------------------
-- frame driver

-- Simulates one frame: buttons in `press` are pressed this frame (and held
-- for the frame), crank turns `crank` degrees.
function MOCK.frame(press, crank, dtMs)
	MOCK.justPressed = {}
	MOCK.justReleased = {}
	for b in pairs(MOCK.buttons) do MOCK.justReleased[b] = true end
	MOCK.buttons = {}
	for _, b in ipairs(press or {}) do
		MOCK.justPressed[b] = true
		MOCK.buttons[b] = true
		MOCK.justReleased[b] = nil
	end
	MOCK.crankChange = crank or 0
	MOCK.ms = MOCK.ms + (dtMs or 33)
	playdate.update()
	assert(contextDepth == 0, "graphics context stack leaked: " .. contextDepth)
end

function MOCK.advance(seconds)
	MOCK.nowSec = MOCK.nowSec + seconds
end
