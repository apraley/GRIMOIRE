-- Headless Playdate runtime mock for THE MALL, 1997.
--
-- Loads the game's Lua sources under stock Lua 5.4 so the simulation can be
-- run and inspected without the Simulator. The mock is *strict*: every
-- playdate.* function and constant is built from tools/pd_api_functions.txt /
-- tools/pd_api_constants.txt, which were extracted from the SDK's documented
-- API (Inside Playdate, via the LuaCATS stubs). Calling any playdate API that
-- is not in that list raises an error, so running the game here doubles as an
-- API verification pass.

local TOOLS = (arg and arg[0] and arg[0]:match("(.*/)")) or "./"
PD_TOOLS_DIR = PD_TOOLS_DIR or TOOLS
local SRC = PD_SOURCE_DIR or (PD_TOOLS_DIR .. "../source/")

local calls = {}          -- api name -> count (for the report)
PDMOCK_CALLS = calls
-- api name -> implementation. Every documented function is a counting stub
-- that dispatches through this table, so tools/pdraster.lua can swap in real
-- implementations without losing strictness or call counts.
local impls = {}
PDMOCK_IMPL = impls

local function readLines(path)
  local t = {}
  local f = assert(io.open(path, "r"), "missing " .. path)
  for line in f:lines() do t[#t + 1] = line end
  f:close()
  return t
end

-- ---------------------------------------------------------------- objects
local instanceClasses = {}   -- class name -> method table

local function newInstance(cls, fields)
  local o = fields or {}
  o.__cls = cls
  return setmetatable(o, {
    __index = function(t, k)
      local m = instanceClasses[cls] and instanceClasses[cls][k]
      if m then return m end
      error("pdmock: " .. cls .. ":" .. tostring(k) .. " is not a documented Playdate API", 2)
    end,
  })
end

-- default return values for specific APIs
local overrides = {}
local inputState = { cur = 0, prev = 0, crank = 0, crankChange = 0, docked = false }
PDMOCK_INPUT = inputState
local nowMs = 0
PDMOCK_TIME = function(ms) nowMs = ms end

PDMOCK_NEW_INSTANCE = newInstance

-- Text metrics: a flat 7px advance / 16px line unless tools/pdraster.lua is
-- loaded, which installs PDMOCK_TEXT (its bitmap font's metrics, see
-- tools/pdtext.lua) so layout matches the rendered screenshots.
local VARIANT_NAMES = { [0] = "normal", [1] = "bold", [2] = "italic" }
local function fontObj(variant) return newInstance("playdate.graphics.font", { variant = VARIANT_NAMES[variant or 0] or "normal" }) end
local function imageObj(w, h) return newInstance("playdate.graphics.image", { w = w or 1, h = h or 1 }) end

overrides["playdate.graphics.image.new"] = function(a, b)
  if type(a) == "number" then return imageObj(a, b) end
  return nil -- no image files ship with the game
end
overrides["playdate.graphics.image:getSize"] = function(self) return self.w, self.h end
overrides["playdate.graphics.getSystemFont"] = function(variant) return fontObj(variant) end
overrides["playdate.graphics.getFont"] = function() return fontObj() end
overrides["playdate.graphics.font.new"] = function() return nil end
overrides["playdate.graphics.font:getHeight"] = function() return PDMOCK_TEXT and PDMOCK_TEXT.height or 16 end
overrides["playdate.graphics.font:getTextWidth"] = function(self, s)
  if PDMOCK_TEXT then return (PDMOCK_TEXT.size(s, self.variant, false)) end
  return #tostring(s) * 7
end
overrides["playdate.graphics.getTextSize"] = function(s, fontFamily, leading)
  if PDMOCK_TEXT then return PDMOCK_TEXT.size(s, "normal", true, leading) end
  return #tostring(s) * 7, 16
end
overrides["playdate.graphics.getDrawOffset"] = function() return 0, 0 end
overrides["playdate.buttonIsPressed"] = function(b) return (inputState.cur & b) ~= 0 end
overrides["playdate.buttonJustPressed"] = function(b) return (inputState.cur & b) ~= 0 and (inputState.prev & b) == 0 end
overrides["playdate.buttonJustReleased"] = function(b) return (inputState.cur & b) == 0 and (inputState.prev & b) ~= 0 end
overrides["playdate.getCrankChange"] = function() return inputState.crankChange, inputState.crankChange end
overrides["playdate.getCrankPosition"] = function() return inputState.crank end
overrides["playdate.isCrankDocked"] = function() return inputState.docked end
overrides["playdate.getCrankTicks"] = function(n) return 0 end
overrides["playdate.getCurrentTimeMilliseconds"] = function() return nowMs end
overrides["playdate.getSecondsSinceEpoch"] = function() return 870000000, 0 end
overrides["playdate.getSystemMenu"] = function() return newInstance("playdate.menu", {}) end
overrides["playdate.menu:addMenuItem"] = function() return newInstance("playdate.menu.item", {}) end
overrides["playdate.menu:addCheckmarkMenuItem"] = function() return newInstance("playdate.menu.item", {}) end
overrides["playdate.menu:addOptionsMenuItem"] = function() return newInstance("playdate.menu.item", {}) end
overrides["playdate.sound.synth.new"] = function() return newInstance("playdate.sound.synth", {}) end
overrides["playdate.isSimulator"] = nil

-- datastore -> files in a scratch dir
local DS = PD_DATA_DIR or "/tmp/pdmock_data/"
os.execute("mkdir -p " .. DS)
overrides["playdate.datastore.write"] = function(t, name)
  local f = assert(io.open(DS .. (name or "data") .. ".json", "w"))
  f:write(json.encode(t)); f:close()
end
overrides["playdate.datastore.read"] = function(name)
  local f = io.open(DS .. (name or "data") .. ".json", "r")
  if not f then return nil end
  local s = f:read("a"); f:close()
  return json.decode(s)
end
overrides["playdate.datastore.delete"] = function(name)
  return os.remove(DS .. (name or "data") .. ".json") ~= nil
end

-- ---------------------------------------------------------------- tables
playdate = {}
local function ensurePath(path)
  local t = _G
  for part in path:gmatch("[^.]+") do
    if t[part] == nil then t[part] = {} end
    t = t[part]
  end
  return t
end

for _, name in ipairs(readLines(PD_TOOLS_DIR .. "pd_api_functions.txt")) do
  local owner, sep, fn = name:match("^(.*)([.:])([%w_]+)$")
  if owner and not owner:match("^_") then
    impls[name] = overrides[name] or function() return nil end
    local counted = function(...) calls[name] = (calls[name] or 0) + 1; return impls[name](...) end
    if sep == ":" then
      instanceClasses[owner] = instanceClasses[owner] or {}
      instanceClasses[owner][fn] = counted
    else
      local tbl = ensurePath(owner)
      if type(tbl) == "table" then tbl[fn] = counted end
    end
  end
end

for _, line in ipairs(readLines(PD_TOOLS_DIR .. "pd_api_constants.txt")) do
  local cls, k, v = line:match("^(%S+) (%S+) (%S+)$")
  if cls then
    local tbl = cls == "kTextAlignment" and ensurePath("kTextAlignment") or ensurePath(cls)
    tbl[k] = tonumber(v)
  end
end
kTextAlignment = kTextAlignment or {}
kTextAlignment.left, kTextAlignment.right, kTextAlignment.center = 0, 1, 2

-- strictness: unknown playdate.* lookups fail loudly
local function strict(tbl, path)
  for k, v in pairs(tbl) do
    if type(v) == "table" and k ~= "inputHandlers" then strict(v, path .. "." .. k) end
  end
  setmetatable(tbl, { __index = function(_, k)
    error("pdmock: " .. path .. "." .. tostring(k) .. " is not a documented Playdate API", 2)
  end })
end

-- ---------------------------------------------------------------- json
json = json or {}
do
  local function esc(s)
    return s:gsub('[%c"\\]', function(c)
      local m = { ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\t'] = '\\t', ['\r'] = '\\r' }
      return m[c] or string.format("\\u%04x", c:byte())
    end)
  end
  local function isArray(t)
    local n = 0
    for k in pairs(t) do
      if type(k) ~= "number" or k < 1 or math.type(k) ~= "integer" then return false end
      n = n + 1
    end
    for i = 1, n do if t[i] == nil then return false end end
    return true, n
  end
  local function enc(v, out)
    local ty = type(v)
    if ty == "table" then
      local arr, n = isArray(v)
      if arr and n > 0 then
        out[#out + 1] = "["
        for i = 1, n do if i > 1 then out[#out + 1] = "," end enc(v[i], out) end
        out[#out + 1] = "]"
      elseif arr then
        out[#out + 1] = "[]"
      else
        out[#out + 1] = "{"
        local first = true
        for k, x in pairs(v) do
          if not first then out[#out + 1] = "," end
          first = false
          out[#out + 1] = '"' .. esc(tostring(k)) .. '":'
          enc(x, out)
        end
        out[#out + 1] = "}"
      end
    elseif ty == "string" then out[#out + 1] = '"' .. esc(v) .. '"'
    elseif ty == "number" then
      if v ~= v or v == math.huge or v == -math.huge then out[#out + 1] = "0"
      elseif math.type(v) == "integer" then out[#out + 1] = tostring(v)
      else out[#out + 1] = string.format("%.14g", v) end
    elseif ty == "boolean" then out[#out + 1] = tostring(v)
    else out[#out + 1] = "null" end
  end
  json.encode = function(t) local o = {}; enc(t, o); return table.concat(o) end
  json.decode = function(s)
    local pos = 1
    local function ws() pos = s:find("[^ \t\r\n]", pos) or #s + 1 end
    local val
    local function str()
      pos = pos + 1
      local buf = {}
      while true do
        local c = s:sub(pos, pos)
        if c == '"' then pos = pos + 1; break end
        if c == "\\" then
          local n = s:sub(pos + 1, pos + 1)
          if n == "u" then
            buf[#buf + 1] = utf8.char(tonumber(s:sub(pos + 2, pos + 5), 16)); pos = pos + 6
          else
            buf[#buf + 1] = ({ n = "\n", t = "\t", r = "\r", b = "\b", f = "\f" })[n] or n; pos = pos + 2
          end
        else buf[#buf + 1] = c; pos = pos + 1 end
      end
      return table.concat(buf)
    end
    val = function()
      ws()
      local c = s:sub(pos, pos)
      if c == "{" then
        pos = pos + 1; local t = {}
        ws(); if s:sub(pos, pos) == "}" then pos = pos + 1; return t end
        while true do
          ws(); local k = str(); ws(); pos = pos + 1
          t[k] = val(); ws()
          local d = s:sub(pos, pos); pos = pos + 1
          if d == "}" then return t end
        end
      elseif c == "[" then
        pos = pos + 1; local t = {}
        ws(); if s:sub(pos, pos) == "]" then pos = pos + 1; return t end
        while true do
          t[#t + 1] = val(); ws()
          local d = s:sub(pos, pos); pos = pos + 1
          if d == "]" then return t end
        end
      elseif c == '"' then return str()
      elseif s:sub(pos, pos + 3) == "true" then pos = pos + 4; return true
      elseif s:sub(pos, pos + 4) == "false" then pos = pos + 5; return false
      elseif s:sub(pos, pos + 3) == "null" then pos = pos + 4; return nil
      else
        local num = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
        pos = pos + #num
        -- be pessimistic: decode every number as a float (the game must
        -- normalize ids itself when loading)
        return tonumber(num) + 0.0
      end
    end
    return val()
  end
end

-- ---------------------------------------------------------------- import
local imported = {}
function import(name)
  if name:match("^CoreLibs/") then return end
  -- simulation-only runs skip the presentation layer
  if HEADLESS and (name:match("^scenes/") or name:match("^ui/sprites") or name:match("^ui/mapview") or name == "game") then return end
  if imported[name] then return end
  imported[name] = true
  local path = SRC .. name
  if not path:match("%.lua$") then path = path .. ".lua" end
  local chunk, err = loadfile(path)
  if not chunk then error(err) end
  chunk()
end

strict(playdate, "playdate")

-- step one frame of the game with the given button mask / crank delta
function PDMOCK_FRAME(buttons, crankDelta)
  inputState.prev = inputState.cur
  inputState.cur = buttons or 0
  inputState.crankChange = crankDelta or 0
  inputState.crank = (inputState.crank + (crankDelta or 0)) % 360
  nowMs = nowMs + 33
  if playdate.update then playdate.update() end
end
